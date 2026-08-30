package chat

import (
	"context"
	"encoding/json"
	"net/http"
	"sync"
	"time"

	"github.com/coder/websocket"
	"github.com/rs/zerolog"

	"github.com/LignacAntony/streampulse/internal/auth"
	"github.com/LignacAntony/streampulse/internal/shared/apperror"
	"github.com/LignacAntony/streampulse/internal/shared/httpjson"
)

const (
	writeTimeout = 10 * time.Second
	pingInterval = 30 * time.Second
	readLimit    = 4096
	rateInterval = time.Second
)

// ChatService est l'interface étroite (ISP) du service chat consommée par le handler.
type ChatService interface {
	SendMessage(ctx context.Context, streamID, userID, content string) (Message, error)
	DeleteMessage(ctx context.Context, messageID, requesterID string) error
	BanUser(ctx context.Context, streamID, targetUserID, requesterID string, reason *string) error
	UnbanUser(ctx context.Context, targetUserID, requesterID string) error
	IsBanned(ctx context.Context, userID, streamID string) (bool, error)
	ListBans(ctx context.Context, broadcasterID string) ([]BannedUser, error)
	RecentMessages(ctx context.Context, streamID string) ([]Message, error)
	GetUsername(ctx context.Context, userID string) (string, error)
}

// ChatLiveness vérifie si un flux est en direct.
type ChatLiveness interface {
	IsLive(streamID string) bool
}

// BroadcasterResolver identifie le diffuseur d'un flux.
type BroadcasterResolver interface {
	BroadcasterID(ctx context.Context, streamID string) (string, error)
}

// Handler gère les connexions WebSocket du chat.
type Handler struct {
	svc          ChatService
	hub          *ChatHub
	liveness     ChatLiveness
	broadcasters BroadcasterResolver

	rateMu   sync.Mutex
	rateByID map[string]time.Time
}

// NewHandler construit le handler chat.
func NewHandler(svc ChatService, hub *ChatHub, liveness ChatLiveness, broadcasters BroadcasterResolver) *Handler {
	return &Handler{
		svc:          svc,
		hub:          hub,
		liveness:     liveness,
		broadcasters: broadcasters,
		rateByID:     make(map[string]time.Time),
	}
}

// --- Protocole JSON ---

type incomingMsg struct {
	Type      string  `json:"type"`
	Content   string  `json:"content,omitempty"`
	MessageID string  `json:"message_id,omitempty"`
	UserID    string  `json:"user_id,omitempty"`
	Reason    *string `json:"reason,omitempty"`
}

type outgoingMsg struct {
	Type          string    `json:"type"`
	ID            string    `json:"id,omitempty"`
	UserID        string    `json:"user_id,omitempty"`
	Username      string    `json:"username,omitempty"`
	Content       string    `json:"content,omitempty"`
	CreatedAt     string    `json:"created_at,omitempty"`
	MessageID     string    `json:"message_id,omitempty"`
	IsBroadcaster bool      `json:"is_broadcaster,omitempty"`
	Message       string    `json:"message,omitempty"`
	Messages      []msgJSON `json:"messages,omitempty"`
}

type msgJSON struct {
	ID        string `json:"id"`
	UserID    string `json:"user_id"`
	Username  string `json:"username"`
	Content   string `json:"content"`
	CreatedAt string `json:"created_at"`
}

// Connect gère l'upgrade WebSocket et le cycle de vie du client.
func (h *Handler) Connect(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, nil)
		return
	}
	streamID := r.PathValue("id")

	if !h.liveness.IsLive(streamID) {
		httpjson.WriteError(w, r, apperror.Conflict("stream is not live"))
		return
	}

	banned, err := h.svc.IsBanned(r.Context(), userID, streamID)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}
	if banned {
		httpjson.WriteError(w, r, apperror.Forbidden("you are banned from this chat"))
		return
	}

	username, err := h.svc.GetUsername(r.Context(), userID)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{})
	if err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("chat: websocket accept failed")
		return
	}
	conn.SetReadLimit(readLimit)

	c := newClient(userID, username)
	rm := h.hub.Room(streamID)
	rm.Join(c)
	defer rm.Leave(c)

	broadcasterID, _ := h.broadcasters.BroadcasterID(r.Context(), streamID)
	isBroadcaster := userID == broadcasterID

	h.sendEvent(conn, r.Context(), outgoingMsg{
		Type:          "connected",
		IsBroadcaster: isBroadcaster,
	})

	if msgs, err := h.svc.RecentMessages(r.Context(), streamID); err == nil && len(msgs) > 0 {
		history := make([]msgJSON, len(msgs))
		for i, m := range msgs {
			history[i] = toMsgJSON(m)
		}
		h.sendEvent(conn, r.Context(), outgoingMsg{
			Type:     "history",
			Messages: history,
		})
	}

	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()

	go h.writePump(ctx, cancel, conn, c)
	h.readPump(ctx, conn, c, rm, streamID, isBroadcaster)
}

func (h *Handler) readPump(ctx context.Context, conn *websocket.Conn, c *client, rm *room, streamID string, isBroadcaster bool) {
	defer func() {
		_ = conn.CloseNow()
		h.rateMu.Lock()
		delete(h.rateByID, c.userID)
		h.rateMu.Unlock()
	}()

	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			return
		}

		var msg incomingMsg
		if err := json.Unmarshal(data, &msg); err != nil {
			h.sendEvent(conn, ctx, outgoingMsg{Type: "error", Message: "invalid JSON"})
			continue
		}

		switch msg.Type {
		case "message":
			h.rateMu.Lock()
			last := h.rateByID[c.userID]
			if time.Since(last) < rateInterval {
				h.rateMu.Unlock()
				h.sendEvent(conn, ctx, outgoingMsg{Type: "error", Message: "rate limited"})
				continue
			}
			h.rateByID[c.userID] = time.Now()
			h.rateMu.Unlock()

			m, err := h.svc.SendMessage(ctx, streamID, c.userID, msg.Content)
			if err != nil {
				h.sendEvent(conn, ctx, outgoingMsg{Type: "error", Message: "failed to send message"})
				continue
			}
			m.Username = c.username

			out := outgoingMsg{
				Type:      "message",
				ID:        m.ID,
				UserID:    m.UserID,
				Username:  m.Username,
				Content:   m.Content,
				CreatedAt: m.CreatedAt.Format(time.RFC3339Nano),
			}
			if b, err := json.Marshal(out); err == nil {
				rm.Broadcast(b)
			}

		case "delete":
			if !isBroadcaster {
				h.sendEvent(conn, ctx, outgoingMsg{Type: "error", Message: "unauthorized"})
				continue
			}
			if err := h.svc.DeleteMessage(ctx, msg.MessageID, c.userID); err != nil {
				h.sendEvent(conn, ctx, outgoingMsg{Type: "error", Message: "failed to delete message"})
				continue
			}
			out := outgoingMsg{Type: "delete", MessageID: msg.MessageID}
			if b, err := json.Marshal(out); err == nil {
				rm.Broadcast(b)
			}

		case "ban":
			if !isBroadcaster {
				h.sendEvent(conn, ctx, outgoingMsg{Type: "error", Message: "unauthorized"})
				continue
			}
			if err := h.svc.BanUser(ctx, streamID, msg.UserID, c.userID, msg.Reason); err != nil {
				h.sendEvent(conn, ctx, outgoingMsg{Type: "error", Message: "failed to ban user"})
				continue
			}
			out := outgoingMsg{Type: "ban", UserID: msg.UserID}
			if b, err := json.Marshal(out); err == nil {
				rm.Broadcast(b)
			}
			rm.DisconnectUser(msg.UserID)
		}
	}
}

func (h *Handler) writePump(ctx context.Context, cancel context.CancelFunc, conn *websocket.Conn, c *client) {
	ticker := time.NewTicker(pingInterval)
	defer ticker.Stop()
	defer cancel()

	for {
		select {
		case <-ctx.Done():
			return
		case <-c.done:
			_ = conn.Close(websocket.StatusNormalClosure, "disconnected")
			return
		case msg, ok := <-c.send:
			if !ok {
				return
			}
			writeCtx, wc := context.WithTimeout(ctx, writeTimeout)
			err := conn.Write(writeCtx, websocket.MessageText, msg)
			wc()
			if err != nil {
				return
			}
		case <-ticker.C:
			pingCtx, pc := context.WithTimeout(ctx, writeTimeout)
			err := conn.Ping(pingCtx)
			pc()
			if err != nil {
				return
			}
		}
	}
}

func (h *Handler) sendEvent(conn *websocket.Conn, ctx context.Context, msg outgoingMsg) {
	b, err := json.Marshal(msg)
	if err != nil {
		return
	}
	writeCtx, cancel := context.WithTimeout(ctx, writeTimeout)
	defer cancel()
	_ = conn.Write(writeCtx, websocket.MessageText, b)
}

func toMsgJSON(m Message) msgJSON {
	return msgJSON{
		ID:        m.ID,
		UserID:    m.UserID,
		Username:  m.Username,
		Content:   m.Content,
		CreatedAt: m.CreatedAt.Format(time.RFC3339Nano),
	}
}

// --- Endpoints REST pour la gestion des bans ---

type bannedUserJSON struct {
	UserID    string  `json:"user_id"`
	Username  string  `json:"username"`
	Reason    *string `json:"reason,omitempty"`
	CreatedAt string  `json:"created_at"`
}

// ListBans renvoie les utilisateurs bannis par le diffuseur authentifié.
func (h *Handler) ListBans(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, nil)
		return
	}

	bans, err := h.svc.ListBans(r.Context(), userID)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	out := make([]bannedUserJSON, len(bans))
	for i, b := range bans {
		out[i] = bannedUserJSON{
			UserID:    b.UserID,
			Username:  b.Username,
			Reason:    b.Reason,
			CreatedAt: b.CreatedAt.Format(time.RFC3339Nano),
		}
	}
	if err := httpjson.Write(w, http.StatusOK, out); err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("chat: encode bans")
	}
}

// Unban retire le bannissement d'un utilisateur.
func (h *Handler) Unban(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, nil)
		return
	}

	targetID := r.PathValue("userId")
	if err := h.svc.UnbanUser(r.Context(), targetID, userID); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
