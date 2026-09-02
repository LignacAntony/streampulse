package playlist

import (
	"context"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

// Contraintes de validation du nom d'une playlist.
const (
	MinNameLen        = 1
	MaxNameLen        = 120
	MaxDescriptionLen = 500
)

// MaxTracksPerPlaylist borne la taille d'un réordonnancement : le corps de la
// requête porte l'ordre complet, il faut donc un plafond explicite.
const MaxTracksPerPlaylist = 1000

// Playlist est le type domaine d'une playlist. Description est un pointeur pour
// pouvoir être nul. TrackCount est le nombre de pistes qu'elle contient.
type Playlist struct {
	ID          string
	UserID      string
	Name        string
	Description *string
	IsPublic    bool
	TrackCount  int
	// IsFavorite indique si le demandeur a épinglé cette playlist (STR-250).
	IsFavorite bool
	CreatedAt  time.Time
	UpdatedAt  time.Time
}

// PlaylistTrack est une piste au sein d'une playlist. Artist et DurationS sont
// des pointeurs : la table tracks les autorise nuls.
type PlaylistTrack struct {
	ID        string
	Title     string
	Artist    *string
	DurationS *int
	Position  int
}

// AddTrackParams est la demande d'ajout adressée au Repository. UserID sert à
// restreindre l'ajout aux pistes du demandeur.
type AddTrackParams struct {
	PlaylistID string
	TrackID    string
	UserID     string
}

// CreateInput porte les champs fournis à la création. UserID provient du JWT.
type CreateInput struct {
	UserID      string
	Name        string
	Description *string
}

// UpdateInput porte les champs modifiables (renommage + description).
type UpdateInput struct {
	Name        string
	Description *string
}

// CreateParams est la demande de persistance adressée au Repository (champs
// validés + user_id de confiance).
type CreateParams struct {
	UserID      string
	Name        string
	Description *string
}

// UpdateParams est la demande de mise à jour adressée au Repository, restreinte
// à la playlist du propriétaire (id + user_id).
type UpdateParams struct {
	ID          string
	UserID      string
	Name        string
	Description *string
}

// Repository est l'interface de persistance (implémentée par pgRepository).
type Repository interface {
	Create(ctx context.Context, p CreateParams) (Playlist, error)
	ListByUser(ctx context.Context, userID string) ([]Playlist, error)
	GetByID(ctx context.Context, id, userID string) (Playlist, error)
	Update(ctx context.Context, p UpdateParams) (Playlist, error)
	Delete(ctx context.Context, id, userID string) error
	ListTracks(ctx context.Context, playlistID string) ([]PlaylistTrack, error)
	AddTrack(ctx context.Context, p AddTrackParams) error
	RemoveTrack(ctx context.Context, playlistID, trackID string) error
	Reorder(ctx context.Context, playlistID string, trackIDs []string) error
	AddFavorite(ctx context.Context, userID, playlistID string) error
	RemoveFavorite(ctx context.Context, userID, playlistID string) error
}

// Service porte la logique métier du domaine playlist.
type Service struct {
	repo Repository
}

func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

// normalizeName trime le nom et valide sa longueur (1-120). normalizeDescription
// trime la description (vide -> nil) et valide sa longueur (<=500).
func normalizeName(raw string) (string, error) {
	name := strings.TrimSpace(raw)
	if n := utf8.RuneCountInString(name); n < MinNameLen || n > MaxNameLen {
		return "", apperror.InvalidArgument("invalid name")
	}
	return name, nil
}

func normalizeDescription(raw *string) (*string, error) {
	if raw == nil {
		return nil, nil
	}
	d := strings.TrimSpace(*raw)
	if utf8.RuneCountInString(d) > MaxDescriptionLen {
		return nil, apperror.InvalidArgument("description too long")
	}
	if d == "" {
		return nil, nil
	}
	return &d, nil
}

// CreatePlaylist valide l'entrée et persiste une playlist vide. Un nom déjà
// utilisé par le même utilisateur renvoie 409 (contrainte uq_playlists_user_name).
func (s *Service) CreatePlaylist(ctx context.Context, in CreateInput) (Playlist, error) {
	name, err := normalizeName(in.Name)
	if err != nil {
		return Playlist{}, err
	}
	desc, err := normalizeDescription(in.Description)
	if err != nil {
		return Playlist{}, err
	}
	return s.repo.Create(ctx, CreateParams{
		UserID:      in.UserID,
		Name:        name,
		Description: desc,
	})
}

// ListPlaylists retourne les playlists de l'utilisateur (avec leur nombre de
// pistes), triées par date de création décroissante.
func (s *Service) ListPlaylists(ctx context.Context, requesterID string) ([]Playlist, error) {
	return s.repo.ListByUser(ctx, requesterID)
}

// GetPlaylist retourne une playlist du demandeur. Une playlist appartenant à un
// tiers renvoie 404 (on ne divulgue pas son existence).
func (s *Service) GetPlaylist(ctx context.Context, id, requesterID string) (Playlist, error) {
	pl, err := s.repo.GetByID(ctx, id, requesterID)
	if err != nil {
		return Playlist{}, err
	}
	if pl.UserID != requesterID {
		return Playlist{}, apperror.NotFound("playlist not found")
	}
	return pl, nil
}

// AddFavorite épingle la playlist du demandeur. On réutilise GetPlaylist pour ne
// favoriser qu'une playlist visible : une playlist inexistante ou appartenant à
// un tiers renvoie 404 (sans divulguer son existence). Idempotent (un favori
// déjà présent ne lève pas d'erreur).
func (s *Service) AddFavorite(ctx context.Context, id, requesterID string) error {
	if _, err := s.GetPlaylist(ctx, id, requesterID); err != nil {
		return err
	}
	return s.repo.AddFavorite(ctx, requesterID, id)
}

// RemoveFavorite retire la playlist des favoris du demandeur. Idempotent : aucune
// erreur si elle n'était pas en favori (pas de contrôle de visibilité).
func (s *Service) RemoveFavorite(ctx context.Context, id, requesterID string) error {
	return s.repo.RemoveFavorite(ctx, requesterID, id)
}

// UpdatePlaylist valide puis renomme la playlist du propriétaire (404 si absente
// ou appartenant à un tiers ; 409 si le nouveau nom est déjà utilisé).
func (s *Service) UpdatePlaylist(ctx context.Context, id, requesterID string, in UpdateInput) (Playlist, error) {
	name, err := normalizeName(in.Name)
	if err != nil {
		return Playlist{}, err
	}
	desc, err := normalizeDescription(in.Description)
	if err != nil {
		return Playlist{}, err
	}
	return s.repo.Update(ctx, UpdateParams{
		ID:          id,
		UserID:      requesterID,
		Name:        name,
		Description: desc,
	})
}

// DeletePlaylist supprime définitivement la playlist du propriétaire (404 sinon).
func (s *Service) DeletePlaylist(ctx context.Context, id, requesterID string) error {
	return s.repo.Delete(ctx, id, requesterID)
}

// ListTracks retourne les pistes de la playlist du demandeur, ordonnées par
// position. Réutilise GetPlaylist pour le contrôle de propriété (404 si tiers).
func (s *Service) ListTracks(ctx context.Context, id, requesterID string) ([]PlaylistTrack, error) {
	if _, err := s.GetPlaylist(ctx, id, requesterID); err != nil {
		return nil, err
	}
	return s.repo.ListTracks(ctx, id)
}

// AddTrack ajoute une piste en fin de playlist et retourne l'ordre résultant.
// La playlist doit appartenir au demandeur (404 sinon) ; la piste aussi (404 :
// on ne divulgue pas l'existence de la piste d'un tiers). Une piste déjà
// présente renvoie 409.
func (s *Service) AddTrack(ctx context.Context, playlistID, trackID, requesterID string) ([]PlaylistTrack, error) {
	if _, err := s.GetPlaylist(ctx, playlistID, requesterID); err != nil {
		return nil, err
	}
	if err := s.repo.AddTrack(ctx, AddTrackParams{
		PlaylistID: playlistID,
		TrackID:    trackID,
		UserID:     requesterID,
	}); err != nil {
		return nil, err
	}
	return s.repo.ListTracks(ctx, playlistID)
}

// RemoveTrack retire une piste de la playlist du demandeur. Le repo recompacte
// les positions pour qu'elles restent contiguës (0..n-1).
func (s *Service) RemoveTrack(ctx context.Context, playlistID, trackID, requesterID string) error {
	if _, err := s.GetPlaylist(ctx, playlistID, requesterID); err != nil {
		return err
	}
	return s.repo.RemoveTrack(ctx, playlistID, trackID)
}

// ReorderTracks réécrit l'ordre complet de la playlist du demandeur à partir de
// la liste d'identifiants fournie (index 0 = première piste), et retourne
// l'ordre persisté. La liste doit couvrir exactement les pistes de la playlist :
// un doublon est rejeté ici (400), un effectif ou un identifiant qui ne
// correspond pas est rejeté par le repo (409).
func (s *Service) ReorderTracks(ctx context.Context, playlistID, requesterID string, trackIDs []string) ([]PlaylistTrack, error) {
	if _, err := s.GetPlaylist(ctx, playlistID, requesterID); err != nil {
		return nil, err
	}
	if len(trackIDs) == 0 {
		return nil, apperror.InvalidArgument("track_ids must not be empty")
	}
	if len(trackIDs) > MaxTracksPerPlaylist {
		return nil, apperror.InvalidArgument("too many tracks")
	}
	seen := make(map[string]struct{}, len(trackIDs))
	for _, id := range trackIDs {
		if _, dup := seen[id]; dup {
			return nil, apperror.InvalidArgument("duplicate track id")
		}
		seen[id] = struct{}{}
	}
	if err := s.repo.Reorder(ctx, playlistID, trackIDs); err != nil {
		return nil, err
	}
	return s.repo.ListTracks(ctx, playlistID)
}
