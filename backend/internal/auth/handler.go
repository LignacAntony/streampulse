package auth

import (
	"context"
	"log"
	"net/http"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
	"github.com/LignacAntony/streampulse/internal/shared/httpjson"
)

const (
	maxRegisterBodyBytes = 1 << 20 // 1 MiB
	maxLoginBodyBytes    = 1 << 20
	maxRefreshBodyBytes  = 1 << 20
)

// registerRequest correspond au contrat JSON de POST /api/auth/register.
type registerRequest struct {
	Email    string `json:"email"`
	Username string `json:"username"`
	Password string `json:"password"`
}

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

// Registrar est le sous-ensemble du Service utilisé par le handler d'inscription.
// Permet de l'isoler dans les tests via un mock léger.
type Registrar interface {
	Register(ctx context.Context, in RegisterInput) (User, error)
}

// Authenticator est le sous-ensemble du Service utilisé par le handler de login.
type Authenticator interface {
	Login(ctx context.Context, in LoginInput) (TokenPair, error)
}

// TokenRefresher est le sous-ensemble du Service utilisé par le handler de refresh.
type TokenRefresher interface {
	Refresh(ctx context.Context, in RefreshInput) (TokenPair, error)
}

// Handler expose les endpoints HTTP d'authentification.
// Chaque champ est une interface étroite (ISP) : les tests ne stubbent que ce dont ils ont besoin.
type Handler struct {
	svc           Registrar
	authenticator Authenticator
	refresher     TokenRefresher
}

// NewHandler construit un handler d'authentification.
func NewHandler(svc Registrar, authenticator Authenticator, refresher TokenRefresher) *Handler {
	return &Handler{svc: svc, authenticator: authenticator, refresher: refresher}
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

func (h *Handler) Login(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		httpjson.WriteError(w, r, httpjson.StatusError(http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed"))
		return
	}

	var req loginRequest
	if err := httpjson.Decode(w, r, &req, maxLoginBodyBytes); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	pair, err := h.authenticator.Login(r.Context(), LoginInput(req))
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusOK, pair); err != nil {
		log.Printf("auth: encode login response: %v", err)
	}
}

func (h *Handler) Refresh(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		httpjson.WriteError(w, r, httpjson.StatusError(http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed"))
		return
	}

	var req refreshRequest
	if err := httpjson.Decode(w, r, &req, maxRefreshBodyBytes); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if req.RefreshToken == "" {
		httpjson.WriteError(w, r, apperror.InvalidArgument("refresh_token required"))
		return
	}

	pair, err := h.refresher.Refresh(r.Context(), RefreshInput(req))
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusOK, pair); err != nil {
		log.Printf("auth: encode refresh response: %v", err)
	}
}
