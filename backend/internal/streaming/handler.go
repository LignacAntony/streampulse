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

type streamResponse struct {
	ID              string     `json:"id"`
	UserID          string     `json:"user_id"`
	Title           string     `json:"title"`
	Description     *string    `json:"description"`
	Category        *string    `json:"category"`
	Status          string     `json:"status"`
	IsPublic        bool       `json:"is_public"`
	StreamKey       string     `json:"stream_key"`
	StreamSourceURL string     `json:"stream_source_url"`
	StartedAt       *time.Time `json:"started_at"`
	EndedAt         *time.Time `json:"ended_at"`
	CreatedAt       time.Time  `json:"created_at"`
	UpdatedAt       time.Time  `json:"updated_at"`
}

// Create gère POST /api/streams. L'authentification et le rôle broadcaster
// sont garantis en amont par auth.RequireAuth + auth.RequireRole.
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		httpjson.WriteError(w, r, httpjson.StatusError(http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed"))
		return
	}

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

	if err := httpjson.Write(w, http.StatusCreated, h.toResponse(stream)); err != nil {
		log.Printf("streaming: encode create response: %v", err)
	}
}

func (h *Handler) toResponse(s Stream) streamResponse {
	return streamResponse{
		ID:              s.ID,
		UserID:          s.UserID,
		Title:           s.Title,
		Description:     s.Description,
		Category:        s.Category,
		Status:          s.Status,
		IsPublic:        s.IsPublic,
		StreamKey:       s.StreamKey,
		StreamSourceURL: h.ingestBaseURL + "/api/streams/ingest/" + s.StreamKey,
		StartedAt:       s.StartedAt,
		EndedAt:         s.EndedAt,
		CreatedAt:       s.CreatedAt,
		UpdatedAt:       s.UpdatedAt,
	}
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
