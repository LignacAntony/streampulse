package streaming

import (
	"context"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/LignacAntony/streampulse/internal/auth"
	"github.com/LignacAntony/streampulse/internal/shared/apperror"
	"github.com/LignacAntony/streampulse/internal/shared/httpjson"
)

const maxCreateStreamBodyBytes = 1 << 20 // 1 MiB

// StreamService est l'interface requise par le handler (ISP) : *Service la satisfait.
type StreamService interface {
	CreateStream(ctx context.Context, in CreateStreamInput) (Stream, error)
	ListPublicLive(ctx context.Context, limit, offset int32) ([]Stream, error)
	GetStream(ctx context.Context, id, requesterID string) (Stream, bool, error)
	UpdateStream(ctx context.Context, id, requesterID string, in UpdateStreamInput) (Stream, error)
	ArchiveStream(ctx context.Context, id, requesterID string) error
	StartStream(ctx context.Context, id, requesterID string) (Stream, error)
	StopStream(ctx context.Context, id, requesterID string) (Stream, error)
}

// Handler expose le domaine streaming en HTTP. ingestBaseURL sert à construire
// l'URL de stream source renvoyée au diffuseur.
type Handler struct {
	svc           StreamService
	ingestBaseURL string
}

func NewHandler(svc StreamService, ingestBaseURL string) *Handler {
	return &Handler{svc: svc, ingestBaseURL: strings.TrimRight(ingestBaseURL, "/")}
}

// createStreamRequest : pointeurs pour distinguer « champ absent » de zéro.
// title et is_public sont requis ; description et category sont optionnels.
type createStreamRequest struct {
	Title       *string `json:"title"`
	Description *string `json:"description"`
	Category    *string `json:"category"`
	IsPublic    *bool   `json:"is_public"`
}

func (r createStreamRequest) toInput(userID string) (CreateStreamInput, error) {
	if r.Title == nil {
		return CreateStreamInput{}, apperror.InvalidArgument("missing required field: title")
	}
	if r.IsPublic == nil {
		return CreateStreamInput{}, apperror.InvalidArgument("missing required field: is_public")
	}
	return CreateStreamInput{
		UserID:      userID,
		Title:       *r.Title,
		Description: r.Description,
		Category:    r.Category,
		IsPublic:    *r.IsPublic,
	}, nil
}

// streamResponse est la vue détaillée d'un flux. stream_key et stream_source_url
// sont des pointeurs : ils ne sont remplis que pour le propriétaire et valent
// null pour un tiers (un seul schéma, désérialisable côté client, sans fuite).
type streamResponse struct {
	ID              string     `json:"id"`
	UserID          string     `json:"user_id"`
	Title           string     `json:"title"`
	Description     *string    `json:"description"`
	Category        *string    `json:"category"`
	Status          string     `json:"status"`
	IsPublic        bool       `json:"is_public"`
	StreamKey       *string    `json:"stream_key"`
	StreamSourceURL *string    `json:"stream_source_url"`
	StartedAt       *time.Time `json:"started_at"`
	EndedAt         *time.Time `json:"ended_at"`
	CreatedAt       time.Time  `json:"created_at"`
	UpdatedAt       time.Time  `json:"updated_at"`
}

// Create gère POST /api/streams. L'authentification et le rôle broadcaster
// sont garantis en amont par auth.RequireAuth + auth.RequireRole.
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	var req createStreamRequest
	if err := httpjson.Decode(w, r, &req, maxCreateStreamBodyBytes); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	in, err := req.toInput(userID)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	stream, err := h.svc.CreateStream(r.Context(), in)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusCreated, h.toResponse(stream, true)); err != nil {
		log.Printf("streaming: encode create response: %v", err)
	}
}

// toResponse construit la vue détaillée d'un flux. includeSecrets n'est vrai que
// pour le propriétaire : sinon stream_key et stream_source_url restent null.
func (h *Handler) toResponse(s Stream, includeSecrets bool) streamResponse {
	resp := streamResponse{
		ID:          s.ID,
		UserID:      s.UserID,
		Title:       s.Title,
		Description: s.Description,
		Category:    s.Category,
		Status:      s.Status,
		IsPublic:    s.IsPublic,
		StartedAt:   s.StartedAt,
		EndedAt:     s.EndedAt,
		CreatedAt:   s.CreatedAt,
		UpdatedAt:   s.UpdatedAt,
	}
	if includeSecrets {
		key := s.StreamKey
		url := h.ingestBaseURL + "/api/streams/ingest/" + s.StreamKey
		resp.StreamKey = &key
		resp.StreamSourceURL = &url
	}
	return resp
}

// streamSummaryResponse est la vue publique d'un flux : aucun secret
// (stream_key, stream_source_url) n'y figure.
type streamSummaryResponse struct {
	ID          string     `json:"id"`
	UserID      string     `json:"user_id"`
	Title       string     `json:"title"`
	Description *string    `json:"description"`
	Category    *string    `json:"category"`
	Status      string     `json:"status"`
	IsPublic    bool       `json:"is_public"`
	StartedAt   *time.Time `json:"started_at"`
	CreatedAt   time.Time  `json:"created_at"`
}

func toSummary(s Stream) streamSummaryResponse {
	return streamSummaryResponse{
		ID:          s.ID,
		UserID:      s.UserID,
		Title:       s.Title,
		Description: s.Description,
		Category:    s.Category,
		Status:      s.Status,
		IsPublic:    s.IsPublic,
		StartedAt:   s.StartedAt,
		CreatedAt:   s.CreatedAt,
	}
}

// List gère GET /api/streams : flux publics en direct, paginés. Auth requise.
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	limit := parseIntDefault(r.URL.Query().Get("limit"), DefaultListLimit)
	if limit < 1 {
		limit = DefaultListLimit
	}
	if limit > MaxListLimit {
		limit = MaxListLimit
	}
	offset := parseIntDefault(r.URL.Query().Get("offset"), 0)
	if offset < 0 {
		offset = 0
	}
	if offset > 1<<31-1 {
		offset = 1<<31 - 1 // borne haute : évite un débordement int32 (OFFSET négatif → 500)
	}

	streams, err := h.svc.ListPublicLive(r.Context(), int32(limit), int32(offset))
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	out := make([]streamSummaryResponse, 0, len(streams))
	for _, s := range streams {
		out = append(out, toSummary(s))
	}
	if err := httpjson.Write(w, http.StatusOK, out); err != nil {
		log.Printf("streaming: encode list response: %v", err)
	}
}

func parseIntDefault(raw string, def int) int {
	if raw == "" {
		return def
	}
	n, err := strconv.Atoi(raw)
	if err != nil {
		return def
	}
	return n
}

// toUpdateInput réutilise la forme de createStreamRequest : title et is_public
// sont requis (PUT = remplacement complet), description et category optionnels.
func (r createStreamRequest) toUpdateInput() (UpdateStreamInput, error) {
	if r.Title == nil {
		return UpdateStreamInput{}, apperror.InvalidArgument("missing required field: title")
	}
	if r.IsPublic == nil {
		return UpdateStreamInput{}, apperror.InvalidArgument("missing required field: is_public")
	}
	return UpdateStreamInput{
		Title:       *r.Title,
		Description: r.Description,
		Category:    r.Category,
		IsPublic:    *r.IsPublic,
	}, nil
}

// Get gère GET /api/streams/{id}. Réponse unique (streamResponse) : le
// propriétaire reçoit stream_key + stream_source_url, un tiers les reçoit à null.
func (h *Handler) Get(w http.ResponseWriter, r *http.Request) {
	requesterID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	stream, isOwner, err := h.svc.GetStream(r.Context(), r.PathValue("id"), requesterID)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusOK, h.toResponse(stream, isOwner)); err != nil {
		log.Printf("streaming: encode get response: %v", err)
	}
}

// Update gère PUT /api/streams/{id} : remplacement complet, propriétaire uniquement.
func (h *Handler) Update(w http.ResponseWriter, r *http.Request) {
	requesterID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	var req createStreamRequest
	if err := httpjson.Decode(w, r, &req, maxCreateStreamBodyBytes); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	in, err := req.toUpdateInput()
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	stream, err := h.svc.UpdateStream(r.Context(), r.PathValue("id"), requesterID, in)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusOK, h.toResponse(stream, true)); err != nil {
		log.Printf("streaming: encode update response: %v", err)
	}
}

// Delete gère DELETE /api/streams/{id} : soft delete, propriétaire uniquement.
func (h *Handler) Delete(w http.ResponseWriter, r *http.Request) {
	requesterID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	if err := h.svc.ArchiveStream(r.Context(), r.PathValue("id"), requesterID); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// Start gère PATCH /api/streams/{id}/start : passe le flux du diffuseur en direct.
func (h *Handler) Start(w http.ResponseWriter, r *http.Request) {
	requesterID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	stream, err := h.svc.StartStream(r.Context(), r.PathValue("id"), requesterID)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusOK, h.toResponse(stream, true)); err != nil {
		log.Printf("streaming: encode start response: %v", err)
	}
}

// Stop gère PATCH /api/streams/{id}/stop : termine le flux du diffuseur.
func (h *Handler) Stop(w http.ResponseWriter, r *http.Request) {
	requesterID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	stream, err := h.svc.StopStream(r.Context(), r.PathValue("id"), requesterID)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusOK, h.toResponse(stream, true)); err != nil {
		log.Printf("streaming: encode stop response: %v", err)
	}
}
