package auth

import (
	"context"
	"log"
	"net/http"

	"github.com/LignacAntony/streampulse/internal/shared/httpjson"
)

const maxRegisterBodyBytes = 1 << 20 // 1 MiB

// registerRequest correspond au contrat JSON de POST /api/auth/register.
type registerRequest struct {
	Email    string `json:"email"`
	Username string `json:"username"`
	Password string `json:"password"`
}

// Registrar est le sous-ensemble du Service utilisé par le handler.
// Permet de l'isoler dans les tests via un mock léger.
type Registrar interface {
	Register(ctx context.Context, in RegisterInput) (User, error)
}

// Handler expose les endpoints HTTP d'inscription.
type Handler struct {
	svc Registrar
}

// NewHandler construit un handler d'inscription.
func NewHandler(svc Registrar) *Handler {
	return &Handler{svc: svc}
}

// Register implémente POST /api/auth/register.
func (h *Handler) Register(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		httpjson.WriteError(w, r, httpjson.StatusError(http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed"))
		return
	}

	var req registerRequest
	if err := httpjson.Decode(w, r, &req, maxRegisterBodyBytes); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	user, err := h.svc.Register(r.Context(), RegisterInput(req))
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusCreated, user); err != nil {
		log.Printf("auth: encode response: %v", err)
	}
}
