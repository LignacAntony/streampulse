package playlist

import (
	"context"
	"net/http"
	"time"

	"github.com/rs/zerolog"

	"github.com/LignacAntony/streampulse/internal/auth"
	"github.com/LignacAntony/streampulse/internal/shared/apperror"
	"github.com/LignacAntony/streampulse/internal/shared/httpjson"
)

const maxPlaylistBodyBytes = 1 << 20 // 1 MiB

// PlaylistService est l'interface requise par le handler (ISP) : *Service la satisfait.
type PlaylistService interface {
	CreatePlaylist(ctx context.Context, in CreateInput) (Playlist, error)
	ListPlaylists(ctx context.Context, requesterID string) ([]Playlist, error)
	GetPlaylist(ctx context.Context, id, requesterID string) (Playlist, error)
	UpdatePlaylist(ctx context.Context, id, requesterID string, in UpdateInput) (Playlist, error)
	DeletePlaylist(ctx context.Context, id, requesterID string) error
	ListTracks(ctx context.Context, id, requesterID string) ([]PlaylistTrack, error)
}

// Handler expose le domaine playlist en HTTP.
type Handler struct {
	svc PlaylistService
}

func NewHandler(svc PlaylistService) *Handler {
	return &Handler{svc: svc}
}

// createPlaylistRequest : pointeurs pour distinguer « champ absent » de zéro.
// name est requis ; description est optionnelle.
type createPlaylistRequest struct {
	Name        *string `json:"name"`
	Description *string `json:"description"`
}

func (r createPlaylistRequest) toInput(userID string) (CreateInput, error) {
	if r.Name == nil {
		return CreateInput{}, apperror.InvalidArgument("missing required field: name")
	}
	return CreateInput{
		UserID:      userID,
		Name:        *r.Name,
		Description: r.Description,
	}, nil
}

func (r createPlaylistRequest) toUpdateInput() (UpdateInput, error) {
	if r.Name == nil {
		return UpdateInput{}, apperror.InvalidArgument("missing required field: name")
	}
	return UpdateInput{
		Name:        *r.Name,
		Description: r.Description,
	}, nil
}

// playlistResponse est la vue d'une playlist. description est un pointeur (null
// possible). is_public est exposé en lecture (non éditable via cette API).
type playlistResponse struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	Description *string   `json:"description"`
	IsPublic    bool      `json:"is_public"`
	TrackCount  int       `json:"track_count"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

func toResponse(p Playlist) playlistResponse {
	return playlistResponse{
		ID:          p.ID,
		Name:        p.Name,
		Description: p.Description,
		IsPublic:    p.IsPublic,
		TrackCount:  p.TrackCount,
		CreatedAt:   p.CreatedAt,
		UpdatedAt:   p.UpdatedAt,
	}
}

// trackResponse est la vue d'une piste d'une playlist. artist et duration_s sont
// des pointeurs (null possible).
type trackResponse struct {
	ID        string  `json:"id"`
	Title     string  `json:"title"`
	Artist    *string `json:"artist"`
	DurationS *int    `json:"duration_s"`
	Position  int     `json:"position"`
}

func toTrackResponse(t PlaylistTrack) trackResponse {
	return trackResponse{
		ID:        t.ID,
		Title:     t.Title,
		Artist:    t.Artist,
		DurationS: t.DurationS,
		Position:  t.Position,
	}
}

// Create gère POST /api/playlists : crée une playlist vide (201).
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	var req createPlaylistRequest
	if err := httpjson.Decode(w, r, &req, maxPlaylistBodyBytes); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	in, err := req.toInput(userID)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	pl, err := h.svc.CreatePlaylist(r.Context(), in)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusCreated, toResponse(pl)); err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("playlist: encode create")
	}
}

// List gère GET /api/playlists : playlists du demandeur (200).
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	playlists, err := h.svc.ListPlaylists(r.Context(), userID)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	out := make([]playlistResponse, 0, len(playlists))
	for _, p := range playlists {
		out = append(out, toResponse(p))
	}
	if err := httpjson.Write(w, http.StatusOK, out); err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("playlist: encode list")
	}
}

// Get gère GET /api/playlists/{id} : une playlist du demandeur (404 si tiers).
func (h *Handler) Get(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	pl, err := h.svc.GetPlaylist(r.Context(), r.PathValue("id"), userID)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusOK, toResponse(pl)); err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("playlist: encode get")
	}
}

// Update gère PUT /api/playlists/{id} : renommage/description, propriétaire
// uniquement (404 si tiers, 409 si nom déjà utilisé).
func (h *Handler) Update(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	var req createPlaylistRequest
	if err := httpjson.Decode(w, r, &req, maxPlaylistBodyBytes); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	in, err := req.toUpdateInput()
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	pl, err := h.svc.UpdatePlaylist(r.Context(), r.PathValue("id"), userID, in)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusOK, toResponse(pl)); err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("playlist: encode update")
	}
}

// Delete gère DELETE /api/playlists/{id} : suppression, propriétaire uniquement (204).
func (h *Handler) Delete(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	if err := h.svc.DeletePlaylist(r.Context(), r.PathValue("id"), userID); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// ListTracks gère GET /api/playlists/{id}/tracks : pistes de la playlist du
// demandeur, ordonnées par position (404 si tiers).
func (h *Handler) ListTracks(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	tracks, err := h.svc.ListTracks(r.Context(), r.PathValue("id"), userID)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	out := make([]trackResponse, 0, len(tracks))
	for _, t := range tracks {
		out = append(out, toTrackResponse(t))
	}
	if err := httpjson.Write(w, http.StatusOK, out); err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("playlist: encode tracks")
	}
}
