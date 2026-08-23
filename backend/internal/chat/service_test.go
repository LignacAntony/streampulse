package chat

import (
	"context"
	"testing"
	"time"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

// --- Stubs ---

type stubRepo struct {
	messages     []Message
	bans         map[string]bool // "userID:broadcasterID" → banned
	globalBans   map[string]bool // userID → globally banned
	insertedMsgs []Message
	deletedIDs   []string
	bannedPairs  [][2]string
	usernames    map[string]string
}

func newStubRepo() *stubRepo {
	return &stubRepo{
		bans:       make(map[string]bool),
		globalBans: make(map[string]bool),
		usernames:  map[string]string{"user-1": "alice", "user-2": "bob"},
	}
}

func (r *stubRepo) InsertMessage(_ context.Context, streamID, userID, content string) (Message, error) {
	m := Message{
		ID:        "msg-" + content[:min(5, len(content))],
		StreamID:  streamID,
		UserID:    userID,
		Content:   content,
		CreatedAt: time.Now(),
	}
	r.insertedMsgs = append(r.insertedMsgs, m)
	return m, nil
}

func (r *stubRepo) SoftDeleteMessage(_ context.Context, messageID, broadcasterID string) error {
	r.deletedIDs = append(r.deletedIDs, messageID)
	return nil
}

func (r *stubRepo) InsertBan(_ context.Context, bannedUserID, bannedBy string, _ *string) error {
	r.bannedPairs = append(r.bannedPairs, [2]string{bannedUserID, bannedBy})
	r.bans[bannedUserID+":"+bannedBy] = true
	return nil
}

func (r *stubRepo) IsBanned(_ context.Context, userID, broadcasterID string) (bool, error) {
	return r.bans[userID+":"+broadcasterID], nil
}

func (r *stubRepo) ListRecentMessages(_ context.Context, _ string, limit int32) ([]Message, error) {
	n := int(limit)
	if n > len(r.messages) {
		n = len(r.messages)
	}
	return r.messages[:n], nil
}

func (r *stubRepo) DeleteBan(_ context.Context, bannedUserID, bannedBy string) error {
	key := bannedUserID + ":" + bannedBy
	if !r.bans[key] {
		return apperror.NotFound("ban not found")
	}
	delete(r.bans, key)
	return nil
}

func (r *stubRepo) ListBans(_ context.Context, bannedBy string) ([]BannedUser, error) {
	var result []BannedUser
	for k := range r.bans {
		parts := [2]string{}
		for i, s := range splitKey(k) {
			parts[i] = s
		}
		if parts[1] == bannedBy {
			result = append(result, BannedUser{UserID: parts[0], Username: "user", CreatedAt: time.Now()})
		}
	}
	return result, nil
}

func splitKey(k string) []string {
	for i, c := range k {
		if c == ':' {
			return []string{k[:i], k[i+1:]}
		}
	}
	return []string{k}
}

func (r *stubRepo) GetUsername(_ context.Context, userID string) (string, error) {
	if u, ok := r.usernames[userID]; ok {
		return u, nil
	}
	return "", apperror.NotFound("user not found")
}

func (r *stubRepo) IsGloballyBanned(_ context.Context, userID string) (bool, error) {
	return r.globalBans[userID], nil
}

func (r *stubRepo) InsertGlobalBan(_ context.Context, _, _ string, _ *string) error {
	return nil
}

func (r *stubRepo) DeleteGlobalBan(_ context.Context, _ string) error {
	return nil
}

func (r *stubRepo) ListGlobalBans(_ context.Context) ([]BannedUser, error) {
	return nil, nil
}

func (r *stubRepo) ListUserMessages(_ context.Context, _ string, _, _ int32) ([]UserMessage, error) {
	return nil, nil
}

type stubOwner struct {
	owners map[string]string // streamID → userID
}

func (s *stubOwner) BroadcasterID(_ context.Context, streamID string) (string, error) {
	if id, ok := s.owners[streamID]; ok {
		return id, nil
	}
	return "", apperror.NotFound("stream not found")
}

// --- Tests ---

func TestSendMessage_OK(t *testing.T) {
	repo := newStubRepo()
	svc := NewService(repo, &stubOwner{owners: map[string]string{"s1": "broadcaster-1"}})

	msg, err := svc.SendMessage(context.Background(), "s1", "user-1", "hello")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if msg.Content != "hello" {
		t.Errorf("content = %q, want %q", msg.Content, "hello")
	}
	if len(repo.insertedMsgs) != 1 {
		t.Errorf("inserted %d messages, want 1", len(repo.insertedMsgs))
	}
}

func TestSendMessage_TooLong(t *testing.T) {
	repo := newStubRepo()
	svc := NewService(repo, &stubOwner{owners: map[string]string{"s1": "broadcaster-1"}})

	long := make([]byte, 501)
	for i := range long {
		long[i] = 'a'
	}
	_, err := svc.SendMessage(context.Background(), "s1", "user-1", string(long))
	if err == nil {
		t.Fatal("expected error for message too long")
	}
	var appErr *apperror.Error
	if !isAppError(err, &appErr) || appErr.Code != apperror.CodeInvalidArgument {
		t.Errorf("expected InvalidArgument, got %v", err)
	}
}

func TestSendMessage_Empty(t *testing.T) {
	repo := newStubRepo()
	svc := NewService(repo, &stubOwner{owners: map[string]string{"s1": "broadcaster-1"}})

	_, err := svc.SendMessage(context.Background(), "s1", "user-1", "   ")
	if err == nil {
		t.Fatal("expected error for empty message")
	}
}

func TestSendMessage_Banned(t *testing.T) {
	repo := newStubRepo()
	repo.bans["user-1:broadcaster-1"] = true
	svc := NewService(repo, &stubOwner{owners: map[string]string{"s1": "broadcaster-1"}})

	_, err := svc.SendMessage(context.Background(), "s1", "user-1", "hello")
	if err == nil {
		t.Fatal("expected error for banned user")
	}
	var appErr *apperror.Error
	if !isAppError(err, &appErr) || appErr.Code != apperror.CodeForbidden {
		t.Errorf("expected Forbidden, got %v", err)
	}
}

func TestSendMessage_GloballyBanned(t *testing.T) {
	repo := newStubRepo()
	repo.globalBans["user-1"] = true
	svc := NewService(repo, &stubOwner{owners: map[string]string{"s1": "broadcaster-1"}})

	_, err := svc.SendMessage(context.Background(), "s1", "user-1", "hello")
	if err == nil {
		t.Fatal("expected error for globally banned user")
	}
	var appErr *apperror.Error
	if !isAppError(err, &appErr) || appErr.Code != apperror.CodeForbidden {
		t.Errorf("expected Forbidden, got %v", err)
	}
}

func TestBanUser_OK(t *testing.T) {
	repo := newStubRepo()
	svc := NewService(repo, &stubOwner{owners: map[string]string{"s1": "broadcaster-1"}})

	err := svc.BanUser(context.Background(), "s1", "user-1", "broadcaster-1", nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(repo.bannedPairs) != 1 {
		t.Errorf("banned %d pairs, want 1", len(repo.bannedPairs))
	}
}

func TestBanUser_SelfBan(t *testing.T) {
	repo := newStubRepo()
	svc := NewService(repo, &stubOwner{owners: map[string]string{"s1": "broadcaster-1"}})

	err := svc.BanUser(context.Background(), "s1", "broadcaster-1", "broadcaster-1", nil)
	if err == nil {
		t.Fatal("expected error when banning yourself")
	}
	var appErr *apperror.Error
	if !isAppError(err, &appErr) || appErr.Code != apperror.CodeInvalidArgument {
		t.Errorf("expected InvalidArgument, got %v", err)
	}
}

func TestBanUser_NotBroadcaster(t *testing.T) {
	repo := newStubRepo()
	svc := NewService(repo, &stubOwner{owners: map[string]string{"s1": "broadcaster-1"}})

	err := svc.BanUser(context.Background(), "s1", "user-1", "user-2", nil)
	if err == nil {
		t.Fatal("expected error when non-broadcaster bans")
	}
	var appErr *apperror.Error
	if !isAppError(err, &appErr) || appErr.Code != apperror.CodeForbidden {
		t.Errorf("expected Forbidden, got %v", err)
	}
}

func TestRecentMessages_Reversed(t *testing.T) {
	repo := newStubRepo()
	repo.messages = []Message{
		{ID: "3", Content: "c", CreatedAt: time.Now()},
		{ID: "2", Content: "b", CreatedAt: time.Now().Add(-time.Second)},
		{ID: "1", Content: "a", CreatedAt: time.Now().Add(-2 * time.Second)},
	}
	svc := NewService(repo, &stubOwner{owners: map[string]string{"s1": "broadcaster-1"}})

	msgs, err := svc.RecentMessages(context.Background(), "s1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(msgs) != 3 {
		t.Fatalf("got %d messages, want 3", len(msgs))
	}
	if msgs[0].ID != "1" || msgs[2].ID != "3" {
		t.Errorf("messages not reversed: first=%s last=%s", msgs[0].ID, msgs[2].ID)
	}
}

func isAppError(err error, target **apperror.Error) bool {
	if e, ok := err.(*apperror.Error); ok {
		*target = e
		return true
	}
	return false
}
