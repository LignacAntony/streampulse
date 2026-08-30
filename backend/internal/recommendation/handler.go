package recommendation

import (
	"context"
	"net/http"

	"github.com/rs/zerolog"

	"github.com/LignacAntony/streampulse/internal/auth"
	"github.com/LignacAntony/streampulse/internal/shared/apperror"
	"github.com/LignacAntony/streampulse/internal/shared/httpjson"
)

type RecommendationService interface {
	Recommend(ctx context.Context, userID string) ([]RecommendedTrack, error)
}

type Handler struct {
	svc RecommendationService
}

func NewHandler(svc RecommendationService) *Handler {
	return &Handler{svc: svc}
}

type recommendationResponse struct {
	ID        string  `json:"id"`
	Title     string  `json:"title"`
	Artist    *string `json:"artist"`
	DurationS *int    `json:"duration_s"`
	Reason    string  `json:"reason"`
}

func (h *Handler) Recommend(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	recs, err := h.svc.Recommend(r.Context(), userID)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	out := make([]recommendationResponse, 0, len(recs))
	for _, t := range recs {
		out = append(out, recommendationResponse{
			ID:        t.ID,
			Title:     t.Title,
			Artist:    t.Artist,
			DurationS: t.DurationS,
			Reason:    t.Reason,
		})
	}
	if err := httpjson.Write(w, http.StatusOK, out); err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("recommendation: encode response")
	}
}
