package profiles

import (
	"context"
	"log"
	"net/http"

	"github.com/LignacAntony/streampulse/internal/auth"
	"github.com/LignacAntony/streampulse/internal/shared/apperror"
	"github.com/LignacAntony/streampulse/internal/shared/httpjson"
)

const maxUpdateProfileBodyBytes = 1 << 20 // 1 MiB

type updateProfileRequest struct {
	Pseudo               string `json:"pseudo"`
	Bio                  string `json:"bio"`
	Theme                string `json:"theme"`
	NotificationsEnabled bool   `json:"notifications_enabled"`
	AudioQuality         string `json:"audio_quality"`
}

type ProfileReader interface {
	GetMe(ctx context.Context, userID string) (Profile, error)
}

type ProfileUpdater interface {
	UpdateMe(ctx context.Context, userID string, in UpdateProfileInput) (Profile, error)
}

type Handler struct {
	reader  ProfileReader
	updater ProfileUpdater
}

func NewHandler(reader ProfileReader, updater ProfileUpdater) *Handler {
	return &Handler{reader: reader, updater: updater}
}

// Me route GET (consultation) et PUT (modification) sur /api/users/me.
// L'authentification est garantie en amont par auth.RequireAuth.
func (h *Handler) Me(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		h.getMe(w, r)
	case http.MethodPut:
		h.updateMe(w, r)
	default:
		w.Header().Set("Allow", http.MethodGet+", "+http.MethodPut)
		httpjson.WriteError(w, r, httpjson.StatusError(http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed"))
	}
}

func (h *Handler) getMe(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	profile, err := h.reader.GetMe(r.Context(), userID)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusOK, profile); err != nil {
		log.Printf("profiles: encode get-me response: %v", err)
	}
}

func (h *Handler) updateMe(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	var req updateProfileRequest
	if err := httpjson.Decode(w, r, &req, maxUpdateProfileBodyBytes); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	profile, err := h.updater.UpdateMe(r.Context(), userID, UpdateProfileInput(req))
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusOK, profile); err != nil {
		log.Printf("profiles: encode update-me response: %v", err)
	}
}
