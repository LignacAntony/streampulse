package streaming

import (
	"context"
	"errors"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/rs/zerolog"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

// Contraintes de validation du titre et de la description.
const (
	MinTitleLen       = 3
	MaxTitleLen       = 120
	MaxDescriptionLen = 500
)

// Statuts d'un flux (miroir du CHECK SQL sur streams.status).
// 'idle' = inactif : flux créé mais pas encore diffusé.
const (
	StatusIdle  = "idle"
	StatusLive  = "live"
	StatusEnded = "ended"
)

// Bornes de pagination de la liste des flux.
const (
	DefaultListLimit = 20
	MaxListLimit     = 100
)

// validCategories est la liste blanche des catégories autorisées.
var validCategories = map[string]bool{
	"music":      true,
	"talk":       true,
	"technology": true,
	"gaming":     true,
	"news":       true,
	"sport":      true,
	"other":      true,
}

// Stream est le type domaine d'un flux live. Description, Category, StartedAt
// et EndedAt sont des pointeurs pour pouvoir être nuls.
type Stream struct {
	ID          string
	UserID      string
	Title       string
	Description *string
	Category    *string
	Status      string
	IsPublic    bool
	StreamKey   string
	StartedAt   *time.Time
	EndedAt     *time.Time
	CreatedAt   time.Time
	UpdatedAt   time.Time
	// BroadcasterUsername : nom du diffuseur, renseigné seulement pour la liste
	// publique (ListPublicLive) ; vide ailleurs.
	BroadcasterUsername string
}

// CreateStreamInput porte les champs fournis par le diffuseur à la création.
// UserID provient du JWT (source de confiance), pas du payload.
type CreateStreamInput struct {
	UserID      string
	Title       string
	Description *string
	Category    *string
	IsPublic    bool
}

// validate applique les règles métier de création et retourne une copie
// normalisée (titre/description trimés, optionnels vides ramenés à nil).
func (in CreateStreamInput) validate() (CreateStreamInput, error) {
	title, desc, cat, err := normalizeStreamFields(in.Title, in.Description, in.Category)
	if err != nil {
		return CreateStreamInput{}, err
	}
	return CreateStreamInput{
		UserID:      in.UserID,
		Title:       title,
		Description: desc,
		Category:    cat,
		IsPublic:    in.IsPublic,
	}, nil
}

// normalizeStreamFields applique les règles communes à la création et à la mise
// à jour : titre 3-120 (trimé), description <=500 (vide -> nil), category dans la
// liste blanche (vide -> nil).
func normalizeStreamFields(rawTitle string, rawDesc, rawCat *string) (title string, desc, cat *string, err error) {
	title = strings.TrimSpace(rawTitle)
	if n := utf8.RuneCountInString(title); n < MinTitleLen || n > MaxTitleLen {
		return "", nil, nil, apperror.InvalidArgument("invalid title")
	}
	if rawDesc != nil {
		d := strings.TrimSpace(*rawDesc)
		if utf8.RuneCountInString(d) > MaxDescriptionLen {
			return "", nil, nil, apperror.InvalidArgument("description too long")
		}
		if d != "" {
			desc = &d
		}
	}
	if rawCat != nil {
		c := strings.TrimSpace(*rawCat)
		if c != "" {
			if !validCategories[c] {
				return "", nil, nil, apperror.InvalidArgument("invalid category")
			}
			cat = &c
		}
	}
	return title, desc, cat, nil
}

// UpdateStreamInput porte les champs modifiables d'un flux (PUT = remplacement
// complet ; status, stream_key et user_id ne sont jamais modifiables ici).
type UpdateStreamInput struct {
	Title       string
	Description *string
	Category    *string
	IsPublic    bool
}

func (in UpdateStreamInput) validate() (UpdateStreamInput, error) {
	title, desc, cat, err := normalizeStreamFields(in.Title, in.Description, in.Category)
	if err != nil {
		return UpdateStreamInput{}, err
	}
	return UpdateStreamInput{Title: title, Description: desc, Category: cat, IsPublic: in.IsPublic}, nil
}

// CreateParams est la demande de persistance adressée au Repository (champs
// validés + statut initial + stream_key généré).
type CreateParams struct {
	UserID      string
	Title       string
	Description *string
	Category    *string
	IsPublic    bool
	Status      string
	StreamKey   string
}

// UpdateParams est la demande de mise à jour adressée au Repository, restreinte
// au flux du propriétaire (id + user_id) et non archivé.
type UpdateParams struct {
	ID          string
	UserID      string
	Title       string
	Description *string
	Category    *string
	IsPublic    bool
}

// Repository est l'interface de persistance (implémentée par pgRepository).
type Repository interface {
	Create(ctx context.Context, p CreateParams) (Stream, error)
	ListPublicLive(ctx context.Context, limit, offset int32) ([]Stream, error)
	GetByID(ctx context.Context, id string) (Stream, error)
	Update(ctx context.Context, p UpdateParams) (Stream, error)
	Archive(ctx context.Context, id, userID string) (string, error)
	StartStream(ctx context.Context, id, userID string) (Stream, error)
	StopStream(ctx context.Context, id, userID string) (Stream, error)
	EndOrphanLiveStreams(ctx context.Context) (int64, error)
	AddFavorite(ctx context.Context, userID, streamID string) error
	RemoveFavorite(ctx context.Context, userID, streamID string) error
	ListFavorites(ctx context.Context, userID string) ([]Stream, error)
	ListByOwner(ctx context.Context, userID string) ([]Stream, error)
	StopLiveStreamsByUser(ctx context.Context, userID string) ([]string, error)
	ForceStopLiveStream(ctx context.Context, id string) (string, error)
	RotateStreamKey(ctx context.Context, id, userID, newKey string) (Stream, error)
}

// AuditRecorder journalise une action sensible dans le journal d'audit.
// Interface étroite (ISP) : le domaine streaming ne connaît ni la table ni le
// package qui sait y écrire — main.go lui injecte l'implémentation du domaine
// admin, seul propriétaire d'audit_logs. Jamais nil : noopAudit par défaut.
type AuditRecorder interface {
	InsertAuditLog(ctx context.Context, actorID, action, targetType, targetID string) error
}

type noopAudit struct{}

func (noopAudit) InsertAuditLog(context.Context, string, string, string, string) error { return nil }

// KeyGenerator génère le secret de stream source (implémenté par keyGenerator).
type KeyGenerator interface {
	NewStreamKey() (string, error)
}

// Sessions gère le cycle de vie des goroutines de diffusion (implémenté par
// *LiveSessions). Le service enregistre/annule la session au start/stop. La clé
// de flux est fournie au start pour router l'ingest audio (cf. ADR 015).
type Sessions interface {
	Start(streamID, streamKey string)
	Stop(streamID string)
}

// Service porte la logique métier du domaine streaming.
type Service struct {
	repo     Repository
	keys     KeyGenerator
	sessions Sessions
	audit    AuditRecorder // jamais nil : noopAudit par défaut
}

func NewService(repo Repository, keys KeyGenerator, sessions Sessions) *Service {
	return &Service{repo: repo, keys: keys, sessions: sessions, audit: noopAudit{}}
}

// SetAuditRecorder injecte le journal d'audit (STR-228). Setter plutôt que
// paramètre de constructeur, comme SetMetrics côté sessions : le domaine
// fonctionne sans, et l'implémentation vit dans un autre domaine construit plus
// tard dans main.go. Appelé une fois au démarrage, avant les requêtes HTTP.
func (s *Service) SetAuditRecorder(rec AuditRecorder) {
	if rec == nil {
		rec = noopAudit{}
	}
	s.audit = rec
}

// CreateStream valide l'entrée, génère le stream_key et persiste le flux avec
// le statut initial 'idle'.
func (s *Service) CreateStream(ctx context.Context, in CreateStreamInput) (Stream, error) {
	validated, err := in.validate()
	if err != nil {
		return Stream{}, err
	}

	key, err := s.keys.NewStreamKey()
	if err != nil {
		return Stream{}, apperror.Internal("generate stream key", err)
	}

	return s.repo.Create(ctx, CreateParams{
		UserID:      validated.UserID,
		Title:       validated.Title,
		Description: validated.Description,
		Category:    validated.Category,
		IsPublic:    validated.IsPublic,
		Status:      StatusIdle,
		StreamKey:   key,
	})
}

// ListPublicLive retourne les flux publics en direct (non archivés), paginés.
func (s *Service) ListPublicLive(ctx context.Context, limit, offset int32) ([]Stream, error) {
	return s.repo.ListPublicLive(ctx, limit, offset)
}

// GetStream retourne un flux par id et indique si le demandeur en est le
// propriétaire. Un flux privé n'est visible que de son propriétaire (sinon 404,
// pour ne pas divulguer son existence).
func (s *Service) GetStream(ctx context.Context, id, requesterID string) (Stream, bool, error) {
	stream, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return Stream{}, false, err
	}
	isOwner := stream.UserID == requesterID
	if !isOwner && !stream.IsPublic {
		return Stream{}, false, apperror.NotFound("stream not found")
	}
	return stream, isOwner, nil
}

// AddFavorite ajoute le flux aux favoris du demandeur. On réutilise GetStream
// pour ne favoriser qu'un flux visible : un flux inexistant, archivé ou privé
// appartenant à un tiers renvoie 404 (sans divulguer son existence). L'opération
// est idempotente (un favori déjà présent ne lève pas d'erreur).
func (s *Service) AddFavorite(ctx context.Context, streamID, requesterID string) error {
	if _, _, err := s.GetStream(ctx, streamID, requesterID); err != nil {
		return err
	}
	return s.repo.AddFavorite(ctx, requesterID, streamID)
}

// RemoveFavorite retire le flux des favoris du demandeur. Idempotent : aucune
// erreur si le flux n'était pas en favori (pas de vérification de visibilité).
func (s *Service) RemoveFavorite(ctx context.Context, streamID, requesterID string) error {
	return s.repo.RemoveFavorite(ctx, requesterID, streamID)
}

// ListFavorites retourne les flux favoris du demandeur, encore visibles et non
// archivés, triés par date d'ajout décroissante.
func (s *Service) ListFavorites(ctx context.Context, requesterID string) ([]Stream, error) {
	return s.repo.ListFavorites(ctx, requesterID)
}

// ListMyStreams retourne les flux du demandeur pour son tableau de bord
// (STR-153) : tous statuts, archivés exclus, secrets inclus.
//
// Aucun contrôle de rôle : un utilisateur sans le rôle diffuseur ne possède
// simplement aucun flux et reçoit une liste vide. C'est volontaire — le client
// n'a pas à distinguer « pas diffuseur » de « pas encore de flux » (ADR 024).
func (s *Service) ListMyStreams(ctx context.Context, requesterID string) ([]Stream, error) {
	return s.repo.ListByOwner(ctx, requesterID)
}

// UpdateStream valide puis met à jour le flux du propriétaire (404 si absent,
// archivé, ou appartenant à un autre diffuseur).
func (s *Service) UpdateStream(ctx context.Context, id, requesterID string, in UpdateStreamInput) (Stream, error) {
	validated, err := in.validate()
	if err != nil {
		return Stream{}, err
	}
	return s.repo.Update(ctx, UpdateParams{
		ID:          id,
		UserID:      requesterID,
		Title:       validated.Title,
		Description: validated.Description,
		Category:    validated.Category,
		IsPublic:    validated.IsPublic,
	})
}

// ArchiveStream effectue le soft delete du flux du propriétaire (404 sinon) et,
// si le flux était en direct, libère sa session (goroutine + abonnés SSE notifiés).
// La query a déjà ramené status à 'ended' pour un flux live archivé.
func (s *Service) ArchiveStream(ctx context.Context, id, requesterID string) error {
	archivedID, err := s.repo.Archive(ctx, id, requesterID)
	if err != nil {
		return err
	}
	s.sessions.Stop(archivedID) // no-op si aucune session active
	return nil
}

// StartStream fait passer un flux idle -> live (propriétaire uniquement) puis
// enregistre la session de diffusion. 404 si absent/pas propriétaire ; 409 si
// le flux n'est pas idle ou si le diffuseur a déjà un flux en direct.
func (s *Service) StartStream(ctx context.Context, id, requesterID string) (Stream, error) {
	stream, err := s.repo.StartStream(ctx, id, requesterID)
	if err != nil {
		if errors.Is(err, errStreamAlreadyLive) {
			return Stream{}, apperror.Conflict("you already have a live stream")
		}
		if errors.Is(err, errNoRowAffected) {
			return Stream{}, s.classifyTransitionFailure(ctx, id, requesterID, "stream is not idle")
		}
		return Stream{}, err
	}
	s.sessions.Start(stream.ID, stream.StreamKey)
	return stream, nil
}

// StopStream fait passer un flux live -> ended (propriétaire uniquement) puis
// annule la session (notifie les auditeurs). 404 si absent/pas propriétaire ;
// 409 si le flux n'est pas en direct.
func (s *Service) StopStream(ctx context.Context, id, requesterID string) (Stream, error) {
	stream, err := s.repo.StopStream(ctx, id, requesterID)
	if err != nil {
		if errors.Is(err, errNoRowAffected) {
			return Stream{}, s.classifyTransitionFailure(ctx, id, requesterID, "stream is not live")
		}
		return Stream{}, err
	}
	s.sessions.Stop(stream.ID)
	return stream, nil
}

// RotateStreamKey remplace le secret d'ingest d'un flux (propriétaire
// uniquement) et invalide l'ancien. 404 si absent/pas propriétaire ; 409 si le
// flux est en direct — une rotation couperait l'ingest en cours et laisserait
// l'index de session sur l'ancienne clé (cf. la query).
//
// L'audit est best-effort, comme côté admin : la rotation est irréversible une
// fois faite, échouer la requête sur un journal indisponible ne rendrait pas
// l'ancienne clé et laisserait l'appelant croire que rien n'a bougé.
func (s *Service) RotateStreamKey(ctx context.Context, id, requesterID string) (Stream, error) {
	key, err := s.keys.NewStreamKey()
	if err != nil {
		return Stream{}, apperror.Internal("generate stream key", err)
	}

	stream, err := s.repo.RotateStreamKey(ctx, id, requesterID, key)
	if err != nil {
		if errors.Is(err, errNoRowAffected) {
			return Stream{}, s.classifyTransitionFailure(ctx, id, requesterID, "stream is live")
		}
		return Stream{}, err
	}

	// Ni la clé ni l'URL d'ingest ne doivent atteindre le journal : seul l'id
	// public du flux est tracé (cf. httpjson.LoggablePath, ADR 018).
	if err := s.audit.InsertAuditLog(ctx, requesterID, "stream.key_rotated", "stream", stream.ID); err != nil {
		zerolog.Ctx(ctx).Error().Err(err).Str("stream_id", stream.ID).
			Msg("streaming: rotation de clé non journalisée")
	}
	return stream, nil
}

// EndDisconnectedStream termine un direct dont le bail audio a expiré. La
// transition est idempotente face à un stop utilisateur concurrent.
func (s *Service) EndDisconnectedStream(ctx context.Context, id string) error {
	endedID, err := s.repo.ForceStopLiveStream(ctx, id)
	if err != nil {
		if errors.Is(err, errNoRowAffected) {
			s.sessions.Stop(id)
			return nil
		}
		return err
	}
	s.sessions.Stop(endedID)
	return nil
}

// classifyTransitionFailure traduit un échec de transition (0 ligne mise à jour)
// en 404 (absent/archivé/pas propriétaire) ou 409 (mauvais statut, conflictMsg).
func (s *Service) classifyTransitionFailure(ctx context.Context, id, requesterID, conflictMsg string) error {
	stream, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return err // NotFound (absent/archivé)
	}
	if stream.UserID != requesterID {
		return apperror.NotFound("stream not found")
	}
	return apperror.Conflict(conflictMsg)
}

// ReconcileLiveStreams termine les flux restés 'live' en base sans session active
// (à appeler au démarrage — cf. divergence DB/registre après un redémarrage).
func (s *Service) ReconcileLiveStreams(ctx context.Context) (int64, error) {
	return s.repo.EndOrphanLiveStreams(ctx)
}

// StopLiveForUser termine tous les lives d'un utilisateur (usage admin, STR-191) :
// transition DB puis arrêt des sessions in-memory (ffmpeg tué, SSE "ended").
// Sans contrôle de propriétaire : l'appelant (service admin) est déjà derrière RequireRole.
func (s *Service) StopLiveForUser(ctx context.Context, userID string) error {
	ids, err := s.repo.StopLiveStreamsByUser(ctx, userID)
	if err != nil {
		return err
	}
	for _, id := range ids {
		s.sessions.Stop(id)
	}
	return nil
}

// ForceStopStream interrompt un flux en direct (modération admin, STR-192) :
// transition live -> ended SANS contrôle de propriétaire, puis arrêt de la
// session in-memory (ffmpeg tué, event SSE "ended" publié aux auditeurs).
// 404 si le flux est absent/archivé, 409 s'il n'est pas en direct.
func (s *Service) ForceStopStream(ctx context.Context, streamID string) error {
	id, err := s.repo.ForceStopLiveStream(ctx, streamID)
	if err != nil {
		if errors.Is(err, errNoRowAffected) {
			// Pas de requesterID ici : absent/archivé -> 404, sinon 409.
			if _, err := s.repo.GetByID(ctx, streamID); err != nil {
				return err // NotFound
			}
			return apperror.Conflict("stream is not live")
		}
		return err
	}
	s.sessions.Stop(id)
	return nil
}
