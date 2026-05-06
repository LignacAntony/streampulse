package auth

import (
	"context"
	"log"
	"net/http"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
	"github.com/LignacAntony/streampulse/internal/shared/httpjson"
)

const (
	maxRegisterBodyBytes       = 1 << 20 // 1 MiB
	maxLoginBodyBytes          = 1 << 20
	maxRefreshBodyBytes        = 1 << 20
	maxForgotPasswordBodyBytes = 1 << 20
)

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

type logoutRequest struct {
	RefreshToken string `json:"refresh_token"`
}

type forgotPasswordRequest struct {
	Email string `json:"email"`
}

type Registrar interface {
	Register(ctx context.Context, in RegisterInput) (User, error)
}

type Authenticator interface {
	Login(ctx context.Context, in LoginInput) (TokenPair, error)
}

type TokenRefresher interface {
	Refresh(ctx context.Context, in RefreshInput) (TokenPair, error)
}

type Logouter interface {
	Logout(ctx context.Context, in LogoutInput) error
}

type PasswordResetter interface {
	ForgotPassword(ctx context.Context, in ForgotPasswordInput) error
}

type Handler struct {
	svc           Registrar
	authenticator Authenticator
	refresher     TokenRefresher
	logouter      Logouter
	resetter      PasswordResetter
}

func NewHandler(svc Registrar, authenticator Authenticator, refresher TokenRefresher, logouter Logouter, resetter PasswordResetter) *Handler {
	return &Handler{svc: svc, authenticator: authenticator, refresher: refresher, logouter: logouter, resetter: resetter}
}

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

func (h *Handler) Logout(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		httpjson.WriteError(w, r, httpjson.StatusError(http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed"))
		return
	}

	var req logoutRequest
	if err := httpjson.Decode(w, r, &req, maxRefreshBodyBytes); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if req.RefreshToken == "" {
		httpjson.WriteError(w, r, apperror.InvalidArgument("refresh_token required"))
		return
	}

	if err := h.logouter.Logout(r.Context(), LogoutInput(req)); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) ForgotPassword(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		httpjson.WriteError(w, r, httpjson.StatusError(http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed"))
		return
	}

	var req forgotPasswordRequest
	if err := httpjson.Decode(w, r, &req, maxForgotPasswordBodyBytes); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := h.resetter.ForgotPassword(r.Context(), ForgotPasswordInput(req)); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusOK, map[string]string{
		"message": "if this email is registered, you will receive a password reset link shortly",
	}); err != nil {
		log.Printf("auth: encode forgot-password response: %v", err)
	}
}
