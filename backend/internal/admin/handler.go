package admin

import (
	"context"
	"net/http"
	"time"

	"strconv"

	"github.com/rs/zerolog"

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
	ListLiveStreams(ctx context.Context, limit, offset int32) ([]AdminStream, int64, error)
	StopStream(ctx context.Context, streamID, actorID string) error
	Overview(ctx context.Context) (Overview, error)
}

// ChatModerator expose au handler admin la modération du chat : ban/unban
// global, liste des bans, messages d'un utilisateur. Interface étroite (ISP),
// satisfaite par un adaptateur câblé dans main.go (les types domaine du chat
// ne fuient pas dans le domaine admin).
type ChatModerator interface {
	GlobalBan(ctx context.Context, targetUserID, adminID string, reason *string) error
	GlobalUnban(ctx context.Context, targetUserID string) error
	ListGlobalBans(ctx context.Context) ([]ChatBannedUser, error)
	ListUserMessages(ctx context.Context, userID string, limit, offset int32) ([]ChatUserMessage, error)
	IsGloballyBanned(ctx context.Context, userID string) (bool, error)
	DisconnectUserFromAll(userID string)
}

// ChatBannedUser est la vue d'un utilisateur banni globalement.
type ChatBannedUser struct {
	UserID    string
	Username  string
	Reason    *string
	CreatedAt time.Time
}

// ChatUserMessage est un message de chat avec le titre du flux (vue admin).
type ChatUserMessage struct {
	ID          string
	StreamID    string
	UserID      string
	Username    string
	Content     string
	CreatedAt   time.Time
	StreamTitle string
}

// Handler expose le domaine admin en HTTP (US-08-01). Les routes sont montées
// derrière auth.RequireAuth + auth.RequireRole("admin") côté câblage (main.go).
type Handler struct {
	svc  AdminService
	chat ChatModerator
}

func NewHandler(svc AdminService) *Handler {
	return &Handler{svc: svc}
}

// SetChatModerator branche la modération chat (câblé dans main.go).
func (h *Handler) SetChatModerator(chat ChatModerator) {
	h.chat = chat
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

	limit, offset := clampPagination(r)

	users, total, err := h.svc.ListUsers(r.Context(), ListUsersInput{
		Search: r.URL.Query().Get("search"),
		Role:   role,
		Status: status,
		Limit:  limit,
		Offset: offset,
	})
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}
	if users == nil {
		users = []AdminUser{}
	}

	if err := httpjson.Write(w, http.StatusOK, listUsersResponse{Users: users, Total: total}); err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("admin: encode list")
	}
}

// Metrics gère GET /api/admin/metrics : résumé de supervision réservé au rôle
// admin (STR-244).
//
// Cette route ne double pas /metrics, elle répond à une autre question. /metrics
// sert l'exposition Prometheus — texte brut, non authentifié, bloqué par Caddy
// en production et scrapé depuis le réseau interne (ADR 019). Ici, l'admin
// **applicatif** obtient en JSON les quelques chiffres qui l'intéressent, avec
// l'autorisation dérivée de son rôle et non d'un compte Grafana séparé.
func (h *Handler) Metrics(w http.ResponseWriter, r *http.Request) {
	overview, err := h.svc.Overview(r.Context())
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}
	if err := httpjson.Write(w, http.StatusOK, overview); err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("admin: encode metrics")
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
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("admin: encode set-active")
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

// listStreamsResponse est l'enveloppe de pagination de GET /api/admin/streams.
type listStreamsResponse struct {
	Streams []AdminStream `json:"streams"`
	Total   int64         `json:"total"`
}

// ListStreams gère GET /api/admin/streams : liste de modération paginée (tous
// les flux en direct, publics et privés). Mêmes bornes de pagination que List
// (users) : limit défaut 20 / max 100, offset borné [0, MaxInt32].
func (h *Handler) ListStreams(w http.ResponseWriter, r *http.Request) {
	limit, offset := clampPagination(r)

	streams, total, err := h.svc.ListLiveStreams(r.Context(), limit, offset)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}
	if streams == nil {
		streams = []AdminStream{}
	}

	if err := httpjson.Write(w, http.StatusOK, listStreamsResponse{Streams: streams, Total: total}); err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("admin: encode list streams")
	}
}

// StopStream gère POST /api/admin/streams/{id}/stop : interruption d'un flux
// en direct par un modérateur (audit journalisé côté service, best-effort).
func (h *Handler) StopStream(w http.ResponseWriter, r *http.Request) {
	actorID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	if err := h.svc.StopStream(r.Context(), r.PathValue("id"), actorID); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// clampPagination lit et borne les paramètres `limit`/`offset` d'une requête de
// liste admin : limit dans [1, maxListLimit] (défaut defaultListLimit), offset
// dans [0, MaxInt32] (borne haute pour éviter un OFFSET négatif après le cast
// int32 → 500). Partagée par les endpoints paginés du domaine (List, ListStreams).
func clampPagination(r *http.Request) (limit, offset int32) {
	l := parseIntDefault(r.URL.Query().Get("limit"), defaultListLimit)
	if l < 1 {
		l = defaultListLimit
	}
	if l > maxListLimit {
		l = maxListLimit
	}
	o := parseIntDefault(r.URL.Query().Get("offset"), 0)
	if o < 0 {
		o = 0
	}
	if o > 1<<31-1 {
		o = 1<<31 - 1
	}
	return int32(l), int32(o)
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

// --- Modération chat admin ---

const maxGlobalBanBodyBytes = 1 << 10

type globalBanRequest struct {
	Reason *string `json:"reason,omitempty"`
}

type globalBannedUserJSON struct {
	UserID    string  `json:"user_id"`
	Username  string  `json:"username"`
	Reason    *string `json:"reason,omitempty"`
	CreatedAt string  `json:"created_at"`
}

type userMessageJSON struct {
	ID          string `json:"id"`
	StreamID    string `json:"stream_id"`
	Username    string `json:"username"`
	Content     string `json:"content"`
	CreatedAt   string `json:"created_at"`
	StreamTitle string `json:"stream_title"`
}

// ListUserMessages gère GET /api/admin/users/{id}/chat-messages : messages de
// chat d'un utilisateur, paginés.
func (h *Handler) ListUserMessages(w http.ResponseWriter, r *http.Request) {
	if h.chat == nil {
		httpjson.WriteError(w, r, apperror.Internal("chat moderation not configured", nil))
		return
	}

	userID := r.PathValue("id")
	limit, offset := clampPagination(r)

	msgs, err := h.chat.ListUserMessages(r.Context(), userID, limit, offset)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	out := make([]userMessageJSON, len(msgs))
	for i, m := range msgs {
		out[i] = userMessageJSON{
			ID:          m.ID,
			StreamID:    m.StreamID,
			Username:    m.Username,
			Content:     m.Content,
			CreatedAt:   m.CreatedAt.Format(time.RFC3339Nano),
			StreamTitle: m.StreamTitle,
		}
	}

	if err := httpjson.Write(w, http.StatusOK, out); err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("admin: encode user messages")
	}
}

// GlobalBan gère POST /api/admin/users/{id}/chat-ban : bannissement global.
func (h *Handler) GlobalBan(w http.ResponseWriter, r *http.Request) {
	if h.chat == nil {
		httpjson.WriteError(w, r, apperror.Internal("chat moderation not configured", nil))
		return
	}

	adminID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	var req globalBanRequest
	if err := httpjson.Decode(w, r, &req, maxGlobalBanBodyBytes); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	targetID := r.PathValue("id")
	if err := h.chat.GlobalBan(r.Context(), targetID, adminID, req.Reason); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	h.chat.DisconnectUserFromAll(targetID)

	w.WriteHeader(http.StatusNoContent)
}

// GlobalUnban gère DELETE /api/admin/users/{id}/chat-ban : levée du ban global.
func (h *Handler) GlobalUnban(w http.ResponseWriter, r *http.Request) {
	if h.chat == nil {
		httpjson.WriteError(w, r, apperror.Internal("chat moderation not configured", nil))
		return
	}

	targetID := r.PathValue("id")
	if err := h.chat.GlobalUnban(r.Context(), targetID); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ListGlobalBans gère GET /api/admin/chat-bans : liste des bans globaux.
func (h *Handler) ListGlobalBans(w http.ResponseWriter, r *http.Request) {
	if h.chat == nil {
		httpjson.WriteError(w, r, apperror.Internal("chat moderation not configured", nil))
		return
	}

	bans, err := h.chat.ListGlobalBans(r.Context())
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	out := make([]globalBannedUserJSON, len(bans))
	for i, b := range bans {
		out[i] = globalBannedUserJSON{
			UserID:    b.UserID,
			Username:  b.Username,
			Reason:    b.Reason,
			CreatedAt: b.CreatedAt.Format(time.RFC3339Nano),
		}
	}

	if err := httpjson.Write(w, http.StatusOK, out); err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("admin: encode global bans")
	}
}
