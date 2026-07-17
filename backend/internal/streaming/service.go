package streaming

import (
	"context"
	"errors"
	"strings"
	"time"
	"unicode/utf8"

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
}

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
}

func NewService(repo Repository, keys KeyGenerator, sessions Sessions) *Service {
	return &Service{repo: repo, keys: keys, sessions: sessions}
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
