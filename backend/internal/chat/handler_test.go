package chat

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"

	"github.com/LignacAntony/streampulse/internal/auth"
	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

const (
	testJWTSecret     = "test-secret-which-is-at-least-32-bytes!!"
	testUserID        = "00000000-0000-0000-0000-000000000001"
	testBroadcasterID = "00000000-0000-0000-0000-000000000002"
	testStreamID      = "00000000-0000-0000-0000-000000000042"
)

type stubChatService struct {
	messages    []Message
	bans        []BannedUser
	banned      bool
	bannedErr   error
	sendErr     error
	deleteErr   error
	banErr      error
	unbanErr    error
	listBansErr error
	recentErr   error
	username    string
	usernameErr error
	sentMsg     Message
}

func (s *stubChatService) SendMessage(_ context.Context, _, _, content string) (Message, error) {
	if s.sendErr != nil {
		return Message{}, s.sendErr
	}
	s.sentMsg = Message{ID: "msg-1", UserID: testUserID, Content: content, CreatedAt: time.Now()}
	return s.sentMsg, nil
}

func (s *stubChatService) DeleteMessage(_ context.Context, _, _ string) error {
	return s.deleteErr
}

func (s *stubChatService) BanUser(_ context.Context, _, _, _ string, _ *string) error {
	return s.banErr
}

func (s *stubChatService) UnbanUser(_ context.Context, _, _ string) error {
	return s.unbanErr
}

func (s *stubChatService) IsBanned(_ context.Context, _, _ string) (bool, error) {
	return s.banned, s.bannedErr
}

func (s *stubChatService) ListBans(_ context.Context, _ string) ([]BannedUser, error) {
	return s.bans, s.listBansErr
}

func (s *stubChatService) RecentMessages(_ context.Context, _ string) ([]Message, error) {
	return s.messages, s.recentErr
}

func (s *stubChatService) GetUsername(_ context.Context, _ string) (string, error) {
	if s.usernameErr != nil {
		return "", s.usernameErr
	}
	return s.username, nil
}

type stubLiveness struct{ live bool }

func (s *stubLiveness) IsLive(_ string) bool { return s.live }

type stubBroadcasters struct{ ownerID string }

func (s *stubBroadcasters) BroadcasterID(_ context.Context, _ string) (string, error) {
	return s.ownerID, nil
}

func tokenHeader(t *testing.T, userID, role string) string {
	t.Helper()
	tok, err := auth.GenerateAccessToken(userID, role, testJWTSecret, time.Now().UTC())
	if err != nil {
		t.Fatalf("generate token: %v", err)
	}
	return "Bearer " + tok
}

// dialChat monte un serveur de test, dial une connexion WebSocket authentifiée
// et renvoie la connexion prête à lire/écrire. Le serveur est fermé à la fin
// du test. Le body de la réponse HTTP du handshake est fermé pour satisfaire
// bodyclose.
func dialChat(t *testing.T, h *Handler, userID, role string) (*websocket.Conn, context.Context) {
	t.Helper()

	mux := http.NewServeMux()
	mux.Handle("/ws/streams/{id}/chat", auth.RequireAuth(testJWTSecret, http.HandlerFunc(h.Connect)))
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)

	url := "ws" + strings.TrimPrefix(srv.URL, "http") + "/ws/streams/" + testStreamID + "/chat"
	headers := http.Header{}
	headers.Set("Authorization", tokenHeader(t, userID, role))
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	t.Cleanup(cancel)

	conn, resp, err := websocket.Dial(ctx, url, &websocket.DialOptions{HTTPHeader: headers})
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	if resp != nil && resp.Body != nil {
		_ = resp.Body.Close()
	}
	t.Cleanup(func() { _ = conn.CloseNow() })
	return conn, ctx
}

// readEvent lit un message WebSocket et le décode en outgoingMsg.
func readEvent(t *testing.T, conn *websocket.Conn, ctx context.Context) outgoingMsg {
	t.Helper()
	_, data, err := conn.Read(ctx)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	var msg outgoingMsg
	if err := json.Unmarshal(data, &msg); err != nil {
		t.Fatalf("decode: %v", err)
	}
	return msg
}

// --- REST handler tests ---

func doListBans(t *testing.T, h *Handler, withToken bool) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/api/chat/bans", nil)
	if withToken {
		req.Header.Set("Authorization", tokenHeader(t, testBroadcasterID, "broadcaster"))
	}
	rec := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, http.HandlerFunc(h.ListBans)).ServeHTTP(rec, req)
	return rec
}

func doUnban(t *testing.T, h *Handler, targetID string, withToken bool) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodDelete, "/api/chat/bans/"+targetID, nil)
	req.SetPathValue("userId", targetID)
	if withToken {
		req.Header.Set("Authorization", tokenHeader(t, testBroadcasterID, "broadcaster"))
	}
	rec := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, http.HandlerFunc(h.Unban)).ServeHTTP(rec, req)
	return rec
}

func TestHandler_ListBans_OK(t *testing.T) {
	reason := "spam"
	svc := &stubChatService{bans: []BannedUser{
		{UserID: "u1", Username: "alice", Reason: &reason, CreatedAt: time.Now()},
		{UserID: "u2", Username: "bob", CreatedAt: time.Now()},
	}}
	h := NewHandler(svc, NewChatHub(), &stubLiveness{}, &stubBroadcasters{})

	rec := doListBans(t, h, true)
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	var got []bannedUserJSON
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(got) != 2 {
		t.Errorf("got %d bans, want 2", len(got))
	}
	if got[0].Username != "alice" || got[0].Reason == nil || *got[0].Reason != "spam" {
		t.Errorf("ban[0] = %+v", got[0])
	}
}

func TestHandler_ListBans_NoToken(t *testing.T) {
	h := NewHandler(&stubChatService{}, NewChatHub(), &stubLiveness{}, &stubBroadcasters{})
	if rec := doListBans(t, h, false); rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d", rec.Code)
	}
}

func TestHandler_ListBans_ServiceError(t *testing.T) {
	svc := &stubChatService{listBansErr: apperror.Internal("db error", nil)}
	h := NewHandler(svc, NewChatHub(), &stubLiveness{}, &stubBroadcasters{})
	if rec := doListBans(t, h, true); rec.Code != http.StatusInternalServerError {
		t.Fatalf("want 500, got %d", rec.Code)
	}
}

func TestHandler_ListBans_Empty(t *testing.T) {
	svc := &stubChatService{bans: []BannedUser{}}
	h := NewHandler(svc, NewChatHub(), &stubLiveness{}, &stubBroadcasters{})
	if rec := doListBans(t, h, true); rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d", rec.Code)
	}
}

func TestHandler_Unban_OK(t *testing.T) {
	h := NewHandler(&stubChatService{}, NewChatHub(), &stubLiveness{}, &stubBroadcasters{})
	if rec := doUnban(t, h, "u1", true); rec.Code != http.StatusNoContent {
		t.Fatalf("want 204, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Unban_NotFound(t *testing.T) {
	svc := &stubChatService{unbanErr: apperror.NotFound("ban not found")}
	h := NewHandler(svc, NewChatHub(), &stubLiveness{}, &stubBroadcasters{})
	if rec := doUnban(t, h, "u1", true); rec.Code != http.StatusNotFound {
		t.Fatalf("want 404, got %d", rec.Code)
	}
}

func TestHandler_Unban_NoToken(t *testing.T) {
	h := NewHandler(&stubChatService{}, NewChatHub(), &stubLiveness{}, &stubBroadcasters{})
	if rec := doUnban(t, h, "u1", false); rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d", rec.Code)
	}
}

// --- WebSocket Connect pre-upgrade tests ---

func TestHandler_Connect_StreamNotLive(t *testing.T) {
	svc := &stubChatService{username: "alice"}
	h := NewHandler(svc, NewChatHub(), &stubLiveness{live: false}, &stubBroadcasters{ownerID: testBroadcasterID})

	req := httptest.NewRequest(http.MethodGet, "/ws/streams/s1/chat", nil)
	req.SetPathValue("id", testStreamID)
	req.Header.Set("Authorization", tokenHeader(t, testUserID, "user"))
	rec := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, http.HandlerFunc(h.Connect)).ServeHTTP(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("want 409, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Connect_BannedUser(t *testing.T) {
	svc := &stubChatService{banned: true, username: "alice"}
	h := NewHandler(svc, NewChatHub(), &stubLiveness{live: true}, &stubBroadcasters{ownerID: testBroadcasterID})

	req := httptest.NewRequest(http.MethodGet, "/ws/streams/s1/chat", nil)
	req.SetPathValue("id", testStreamID)
	req.Header.Set("Authorization", tokenHeader(t, testUserID, "user"))
	rec := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, http.HandlerFunc(h.Connect)).ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("want 403, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Connect_BanCheckError(t *testing.T) {
	svc := &stubChatService{bannedErr: apperror.Internal("db error", nil)}
	h := NewHandler(svc, NewChatHub(), &stubLiveness{live: true}, &stubBroadcasters{ownerID: testBroadcasterID})

	req := httptest.NewRequest(http.MethodGet, "/ws/streams/s1/chat", nil)
	req.SetPathValue("id", testStreamID)
	req.Header.Set("Authorization", tokenHeader(t, testUserID, "user"))
	rec := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, http.HandlerFunc(h.Connect)).ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("want 500, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Connect_UsernameError(t *testing.T) {
	svc := &stubChatService{usernameErr: apperror.NotFound("user not found")}
	h := NewHandler(svc, NewChatHub(), &stubLiveness{live: true}, &stubBroadcasters{ownerID: testBroadcasterID})

	req := httptest.NewRequest(http.MethodGet, "/ws/streams/s1/chat", nil)
	req.SetPathValue("id", testStreamID)
	req.Header.Set("Authorization", tokenHeader(t, testUserID, "user"))
	rec := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, http.HandlerFunc(h.Connect)).ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("want 404, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Connect_NoToken(t *testing.T) {
	h := NewHandler(&stubChatService{}, NewChatHub(), &stubLiveness{live: true}, &stubBroadcasters{})

	req := httptest.NewRequest(http.MethodGet, "/ws/streams/s1/chat", nil)
	rec := httptest.NewRecorder()
	auth.RequireAuth(testJWTSecret, http.HandlerFunc(h.Connect)).ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d", rec.Code)
	}
}

// --- WebSocket Connect post-upgrade tests ---

func TestHandler_Connect_WebSocket_SendMessage(t *testing.T) {
	svc := &stubChatService{username: "alice"}
	h := NewHandler(svc, NewChatHub(), &stubLiveness{live: true}, &stubBroadcasters{ownerID: testBroadcasterID})

	conn, ctx := dialChat(t, h, testUserID, "user")

	connected := readEvent(t, conn, ctx)
	if connected.Type != "connected" {
		t.Errorf("first message type = %q, want connected", connected.Type)
	}

	if err := conn.Write(ctx, websocket.MessageText, []byte(`{"type":"message","content":"hello world"}`)); err != nil {
		t.Fatalf("write: %v", err)
	}

	broadcast := readEvent(t, conn, ctx)
	if broadcast.Type != "message" || broadcast.Content != "hello world" {
		t.Errorf("broadcast = %+v", broadcast)
	}
}

func TestHandler_Connect_WebSocket_WithHistory(t *testing.T) {
	svc := &stubChatService{
		username: "alice",
		messages: []Message{
			{ID: "m1", UserID: "u1", Username: "bob", Content: "older", CreatedAt: time.Now().Add(-time.Minute)},
			{ID: "m2", UserID: "u1", Username: "bob", Content: "newer", CreatedAt: time.Now()},
		},
	}
	h := NewHandler(svc, NewChatHub(), &stubLiveness{live: true}, &stubBroadcasters{ownerID: testBroadcasterID})

	conn, ctx := dialChat(t, h, testUserID, "user")

	_ = readEvent(t, conn, ctx) // connected
	history := readEvent(t, conn, ctx)

	if history.Type != "history" {
		t.Errorf("type = %q, want history", history.Type)
	}
	if len(history.Messages) != 2 {
		t.Errorf("got %d history messages, want 2", len(history.Messages))
	}
}

func TestHandler_Connect_WebSocket_RateLimit(t *testing.T) {
	svc := &stubChatService{username: "alice"}
	h := NewHandler(svc, NewChatHub(), &stubLiveness{live: true}, &stubBroadcasters{ownerID: testBroadcasterID})

	conn, ctx := dialChat(t, h, testUserID, "user")
	_ = readEvent(t, conn, ctx) // connected

	if err := conn.Write(ctx, websocket.MessageText, []byte(`{"type":"message","content":"first"}`)); err != nil {
		t.Fatalf("write first: %v", err)
	}
	_ = readEvent(t, conn, ctx) // broadcast

	if err := conn.Write(ctx, websocket.MessageText, []byte(`{"type":"message","content":"second"}`)); err != nil {
		t.Fatalf("write second: %v", err)
	}
	errMsg := readEvent(t, conn, ctx)

	if errMsg.Type != "error" || !strings.Contains(errMsg.Message, "rate") {
		t.Errorf("expected rate limit error, got %+v", errMsg)
	}
}

func TestHandler_Connect_WebSocket_InvalidJSON(t *testing.T) {
	svc := &stubChatService{username: "alice"}
	h := NewHandler(svc, NewChatHub(), &stubLiveness{live: true}, &stubBroadcasters{ownerID: testBroadcasterID})

	conn, ctx := dialChat(t, h, testUserID, "user")
	_ = readEvent(t, conn, ctx) // connected

	if err := conn.Write(ctx, websocket.MessageText, []byte(`not json`)); err != nil {
		t.Fatalf("write: %v", err)
	}
	errMsg := readEvent(t, conn, ctx)

	if errMsg.Type != "error" || !strings.Contains(errMsg.Message, "invalid JSON") {
		t.Errorf("expected invalid JSON error, got %+v", errMsg)
	}
}

func TestHandler_Connect_WebSocket_DeleteNotBroadcaster(t *testing.T) {
	svc := &stubChatService{username: "alice"}
	h := NewHandler(svc, NewChatHub(), &stubLiveness{live: true}, &stubBroadcasters{ownerID: testBroadcasterID})

	conn, ctx := dialChat(t, h, testUserID, "user")
	_ = readEvent(t, conn, ctx) // connected

	if err := conn.Write(ctx, websocket.MessageText, []byte(`{"type":"delete","message_id":"m1"}`)); err != nil {
		t.Fatalf("write: %v", err)
	}
	errMsg := readEvent(t, conn, ctx)

	if errMsg.Type != "error" || !strings.Contains(errMsg.Message, "unauthorized") {
		t.Errorf("expected unauthorized error, got %+v", errMsg)
	}
}

func TestHandler_Connect_WebSocket_BanNotBroadcaster(t *testing.T) {
	svc := &stubChatService{username: "alice"}
	h := NewHandler(svc, NewChatHub(), &stubLiveness{live: true}, &stubBroadcasters{ownerID: testBroadcasterID})

	conn, ctx := dialChat(t, h, testUserID, "user")
	_ = readEvent(t, conn, ctx) // connected

	if err := conn.Write(ctx, websocket.MessageText, []byte(`{"type":"ban","user_id":"u2"}`)); err != nil {
		t.Fatalf("write: %v", err)
	}
	errMsg := readEvent(t, conn, ctx)

	if errMsg.Type != "error" || !strings.Contains(errMsg.Message, "unauthorized") {
		t.Errorf("expected unauthorized error, got %+v", errMsg)
	}
}

func TestHandler_Connect_WebSocket_BroadcasterDelete(t *testing.T) {
	svc := &stubChatService{username: "broadcaster"}
	h := NewHandler(svc, NewChatHub(), &stubLiveness{live: true}, &stubBroadcasters{ownerID: testBroadcasterID})

	conn, ctx := dialChat(t, h, testBroadcasterID, "broadcaster")

	connected := readEvent(t, conn, ctx)
	if !connected.IsBroadcaster {
		t.Error("broadcaster should have is_broadcaster=true")
	}

	if err := conn.Write(ctx, websocket.MessageText, []byte(`{"type":"delete","message_id":"m1"}`)); err != nil {
		t.Fatalf("write: %v", err)
	}
	del := readEvent(t, conn, ctx)

	if del.Type != "delete" || del.MessageID != "m1" {
		t.Errorf("expected delete broadcast, got %+v", del)
	}
}

func TestHandler_Connect_WebSocket_BroadcasterBan(t *testing.T) {
	svc := &stubChatService{username: "broadcaster"}
	h := NewHandler(svc, NewChatHub(), &stubLiveness{live: true}, &stubBroadcasters{ownerID: testBroadcasterID})

	conn, ctx := dialChat(t, h, testBroadcasterID, "broadcaster")
	_ = readEvent(t, conn, ctx) // connected

	if err := conn.Write(ctx, websocket.MessageText, []byte(`{"type":"ban","user_id":"u3"}`)); err != nil {
		t.Fatalf("write: %v", err)
	}
	ban := readEvent(t, conn, ctx)

	if ban.Type != "ban" || ban.UserID != "u3" {
		t.Errorf("expected ban broadcast, got %+v", ban)
	}
}

func TestHandler_Connect_WebSocket_SendError(t *testing.T) {
	svc := &stubChatService{username: "alice", sendErr: apperror.Internal("db", nil)}
	h := NewHandler(svc, NewChatHub(), &stubLiveness{live: true}, &stubBroadcasters{ownerID: testBroadcasterID})

	conn, ctx := dialChat(t, h, testUserID, "user")
	_ = readEvent(t, conn, ctx) // connected

	if err := conn.Write(ctx, websocket.MessageText, []byte(`{"type":"message","content":"fail"}`)); err != nil {
		t.Fatalf("write: %v", err)
	}
	errMsg := readEvent(t, conn, ctx)

	if errMsg.Type != "error" {
		t.Errorf("expected error, got %+v", errMsg)
	}
}

func TestToMsgJSON(t *testing.T) {
	now := time.Now()
	m := Message{ID: "m1", UserID: "u1", Username: "alice", Content: "hello", CreatedAt: now}
	j := toMsgJSON(m)
	if j.ID != "m1" || j.UserID != "u1" || j.Username != "alice" || j.Content != "hello" {
		t.Errorf("toMsgJSON = %+v", j)
	}
	if j.CreatedAt != now.Format(time.RFC3339Nano) {
		t.Errorf("createdAt = %q", j.CreatedAt)
	}
}
