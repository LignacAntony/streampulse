package admin

import (
	"context"
	"log"
	"net/http"
	"strconv"

	"github.com/LignacAntony/streampulse/internal/auth"
	"github.com/LignacAntony/streampulse/internal/shared/apperror"
	"github.com/LignacAntony/streampulse/internal/shared/httpjson"
)

// maxSetActiveBodyBytes borne le corps de PATCH /api/admin/users/{id} (un seul
// champ booléen : 1 Ko est très large).
const maxSetActiveBodyBytes = 1 << 10 // 1 Ko

// Bornes de pagination de la liste admin (mêmes valeurs que streaming.List).
const (
	defaultListLimit = 20
	maxListLimit     = 100
)

// validRoles/validStatuses : listes blanches des filtres de GET /api/admin/users
// ("" désactive le filtre correspondant, cf. queries/admin.sql).
var validRoles = map[string]bool{"": true, "user": true, "broadcaster": true, "admin": true}
var validStatuses = map[string]bool{"": true, "active": true, "inactive": true}

// AdminService est l'interface requise par le handler (ISP) : *Service la satisfait.
type AdminService interface {
	ListUsers(ctx context.Context, in ListUsersInput) ([]AdminUser, int64, error)
	SetUserActive(ctx context.Context, targetID, requesterID string, active bool) (AdminUser, error)
	DeleteUser(ctx context.Context, targetID, requesterID string) error
}

// Handler expose le domaine admin en HTTP (US-08-01). Les routes sont montées
// derrière auth.RequireAuth + auth.RequireRole("admin") côté câblage (main.go).
type Handler struct {
	svc AdminService
}

func NewHandler(svc AdminService) *Handler {
	return &Handler{svc: svc}
}

// listUsersResponse est l'enveloppe de pagination de GET /api/admin/users.
type listUsersResponse struct {
	Users []AdminUser `json:"users"`
	Total int64       `json:"total"`
}

// List gère GET /api/admin/users : recherche/filtre/pagination.
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	role := r.URL.Query().Get("role")
	if !validRoles[role] {
		httpjson.WriteError(w, r, apperror.InvalidArgument("invalid role"))
		return
	}
	status := r.URL.Query().Get("status")
	if !validStatuses[status] {
		httpjson.WriteError(w, r, apperror.InvalidArgument("invalid status"))
		return
	}

	limit := parseIntDefault(r.URL.Query().Get("limit"), defaultListLimit)
	if limit < 1 {
		limit = defaultListLimit
	}
	if limit > maxListLimit {
		limit = maxListLimit
	}
	offset := parseIntDefault(r.URL.Query().Get("offset"), 0)
	if offset < 0 {
		offset = 0
	}
	if offset > 1<<31-1 {
		offset = 1<<31 - 1 // borne haute : évite un débordement int32 (OFFSET négatif → 500)
	}

	users, total, err := h.svc.ListUsers(r.Context(), ListUsersInput{
		Search: r.URL.Query().Get("search"),
		Role:   role,
		Status: status,
		Limit:  int32(limit),
		Offset: int32(offset),
	})
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}
	if users == nil {
		users = []AdminUser{}
	}

	if err := httpjson.Write(w, http.StatusOK, listUsersResponse{Users: users, Total: total}); err != nil {
		log.Printf("admin: encode list response: %v", err)
	}
}

// setActiveRequest : pointeur pour distinguer « champ absent » de la valeur false.
type setActiveRequest struct {
	IsActive *bool `json:"is_active"`
}

// SetActive gère PATCH /api/admin/users/{id} : active/désactive un compte.
func (h *Handler) SetActive(w http.ResponseWriter, r *http.Request) {
	requesterID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	var req setActiveRequest
	if err := httpjson.Decode(w, r, &req, maxSetActiveBodyBytes); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}
	if req.IsActive == nil {
		httpjson.WriteError(w, r, apperror.InvalidArgument("missing required field: is_active"))
		return
	}

	user, err := h.svc.SetUserActive(r.Context(), r.PathValue("id"), requesterID, *req.IsActive)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusOK, user); err != nil {
		log.Printf("admin: encode set-active response: %v", err)
	}
}

// Delete gère DELETE /api/admin/users/{id} : suppression définitive (hard delete).
func (h *Handler) Delete(w http.ResponseWriter, r *http.Request) {
	requesterID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	if err := h.svc.DeleteUser(r.Context(), r.PathValue("id"), requesterID); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// parseIntDefault recopiée depuis streaming.parseIntDefault : la fonction est
// privée à ce package (cf. brief), pas de dépendance inter-domaine pour si peu.
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
