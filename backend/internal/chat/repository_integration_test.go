//go:build integration

package chat

import (
	"context"
	"testing"

	"github.com/LignacAntony/streampulse/internal/testsupport/pgtest"
	"github.com/jackc/pgx/v5/pgxpool"
)

func testRepository(t *testing.T) *pgRepository {
	t.Helper()
	repo, ok := NewRepository(pgtest.Pool(t)).(*pgRepository)
	if !ok {
		t.Fatalf("NewRepository n'a pas rendu un *pgRepository")
	}
	return repo
}

func insertStream(t *testing.T, pool *pgxpool.Pool, userID, title, key string) string {
	t.Helper()
	var id string
	err := pool.QueryRow(context.Background(),
		`INSERT INTO streams (user_id, title, is_public, status, stream_key, started_at)
		 VALUES ($1, $2, true, 'live', $3, NOW()) RETURNING id`,
		userID, title, key,
	).Scan(&id)
	if err != nil {
		t.Fatalf("integration: insertion flux %s: %v", title, err)
	}
	return id
}

func TestRepository_InsertAndListMessages(t *testing.T) {
	repo := testRepository(t)
	ctx := context.Background()
	tag := pgtest.UniqueTag(t)

	broadcasterID := pgtest.InsertUser(t, repo.pool, tag+"_bc", "broadcaster")
	userID := pgtest.InsertUser(t, repo.pool, tag+"_u", "user")
	streamID := insertStream(t, repo.pool, broadcasterID, "Chat "+tag, tag+"-key")

	msg1, err := repo.InsertMessage(ctx, streamID, userID, "hello")
	if err != nil {
		t.Fatalf("InsertMessage: %v", err)
	}
	if msg1.Content != "hello" || msg1.UserID == "" || msg1.ID == "" {
		t.Errorf("message = %+v", msg1)
	}

	msg2, err := repo.InsertMessage(ctx, streamID, userID, "world")
	if err != nil {
		t.Fatalf("InsertMessage 2: %v", err)
	}

	msgs, err := repo.ListRecentMessages(ctx, streamID, 50)
	if err != nil {
		t.Fatalf("ListRecentMessages: %v", err)
	}
	if len(msgs) < 2 {
		t.Fatalf("got %d messages, want at least 2", len(msgs))
	}

	found := 0
	for _, m := range msgs {
		if m.ID == msg1.ID || m.ID == msg2.ID {
			found++
		}
	}
	if found != 2 {
		t.Errorf("found %d of our messages, want 2", found)
	}
}

func TestRepository_SoftDeleteMessage(t *testing.T) {
	repo := testRepository(t)
	ctx := context.Background()
	tag := pgtest.UniqueTag(t)

	broadcasterID := pgtest.InsertUser(t, repo.pool, tag+"_bc", "broadcaster")
	userID := pgtest.InsertUser(t, repo.pool, tag+"_u", "user")
	streamID := insertStream(t, repo.pool, broadcasterID, "Del "+tag, tag+"-key")

	msg, err := repo.InsertMessage(ctx, streamID, userID, "to delete")
	if err != nil {
		t.Fatalf("InsertMessage: %v", err)
	}

	if err := repo.SoftDeleteMessage(ctx, msg.ID, broadcasterID); err != nil {
		t.Fatalf("SoftDeleteMessage: %v", err)
	}

	msgs, err := repo.ListRecentMessages(ctx, streamID, 50)
	if err != nil {
		t.Fatalf("ListRecentMessages: %v", err)
	}
	for _, m := range msgs {
		if m.ID == msg.ID {
			t.Error("deleted message should not appear in recent messages")
		}
	}
}

func TestRepository_SoftDeleteMessage_NotFound(t *testing.T) {
	repo := testRepository(t)
	err := repo.SoftDeleteMessage(context.Background(), "00000000-0000-0000-0000-000000000000", "00000000-0000-0000-0000-000000000001")
	if err == nil {
		t.Error("expected error for non-existent message")
	}
}

func TestRepository_BanAndUnban(t *testing.T) {
	repo := testRepository(t)
	ctx := context.Background()
	tag := pgtest.UniqueTag(t)

	broadcasterID := pgtest.InsertUser(t, repo.pool, tag+"_bc", "broadcaster")
	userID := pgtest.InsertUser(t, repo.pool, tag+"_u", "user")

	reason := "spam"
	if err := repo.InsertBan(ctx, userID, broadcasterID, &reason); err != nil {
		t.Fatalf("InsertBan: %v", err)
	}

	banned, err := repo.IsBanned(ctx, userID, broadcasterID)
	if err != nil {
		t.Fatalf("IsBanned: %v", err)
	}
	if !banned {
		t.Error("user should be banned")
	}

	bans, err := repo.ListBans(ctx, broadcasterID)
	if err != nil {
		t.Fatalf("ListBans: %v", err)
	}
	found := false
	for _, b := range bans {
		if b.UserID == userID {
			found = true
			if b.Reason == nil || *b.Reason != "spam" {
				t.Errorf("reason = %v, want 'spam'", b.Reason)
			}
		}
	}
	if !found {
		t.Error("banned user not found in list")
	}

	if err := repo.DeleteBan(ctx, userID, broadcasterID); err != nil {
		t.Fatalf("DeleteBan: %v", err)
	}

	banned, err = repo.IsBanned(ctx, userID, broadcasterID)
	if err != nil {
		t.Fatalf("IsBanned after unban: %v", err)
	}
	if banned {
		t.Error("user should not be banned after unban")
	}
}

func TestRepository_DeleteBan_NotFound(t *testing.T) {
	repo := testRepository(t)
	err := repo.DeleteBan(context.Background(), "00000000-0000-0000-0000-000000000000", "00000000-0000-0000-0000-000000000001")
	if err == nil {
		t.Error("expected error for non-existent ban")
	}
}

func TestRepository_GlobalBanAndUnban(t *testing.T) {
	repo := testRepository(t)
	ctx := context.Background()
	tag := pgtest.UniqueTag(t)

	adminID := pgtest.InsertUser(t, repo.pool, tag+"_admin", "admin")
	userID := pgtest.InsertUser(t, repo.pool, tag+"_u", "user")

	reason := "abuse"
	if err := repo.InsertGlobalBan(ctx, userID, adminID, &reason); err != nil {
		t.Fatalf("InsertGlobalBan: %v", err)
	}

	banned, err := repo.IsGloballyBanned(ctx, userID)
	if err != nil {
		t.Fatalf("IsGloballyBanned: %v", err)
	}
	if !banned {
		t.Error("user should be globally banned")
	}

	bans, err := repo.ListGlobalBans(ctx)
	if err != nil {
		t.Fatalf("ListGlobalBans: %v", err)
	}
	found := false
	for _, b := range bans {
		if b.UserID == userID {
			found = true
			if b.Reason == nil || *b.Reason != "abuse" {
				t.Errorf("reason = %v, want 'abuse'", b.Reason)
			}
		}
	}
	if !found {
		t.Error("globally banned user not found in list")
	}

	if err := repo.DeleteGlobalBan(ctx, userID); err != nil {
		t.Fatalf("DeleteGlobalBan: %v", err)
	}

	banned, err = repo.IsGloballyBanned(ctx, userID)
	if err != nil {
		t.Fatalf("IsGloballyBanned after unban: %v", err)
	}
	if banned {
		t.Error("user should not be globally banned after unban")
	}
}

func TestRepository_DeleteGlobalBan_NotFound(t *testing.T) {
	repo := testRepository(t)
	err := repo.DeleteGlobalBan(context.Background(), "00000000-0000-0000-0000-000000000000")
	if err == nil {
		t.Error("expected error for non-existent global ban")
	}
}

func TestRepository_GetUsername(t *testing.T) {
	repo := testRepository(t)
	ctx := context.Background()
	tag := pgtest.UniqueTag(t)

	userID := pgtest.InsertUser(t, repo.pool, tag, "user")

	username, err := repo.GetUsername(ctx, userID)
	if err != nil {
		t.Fatalf("GetUsername: %v", err)
	}
	if username != tag {
		t.Errorf("username = %q, want %q", username, tag)
	}
}

func TestRepository_GetUsername_NotFound(t *testing.T) {
	repo := testRepository(t)
	_, err := repo.GetUsername(context.Background(), "00000000-0000-0000-0000-000000000000")
	if err == nil {
		t.Error("expected error for non-existent user")
	}
}

func TestRepository_ListUserMessages(t *testing.T) {
	repo := testRepository(t)
	ctx := context.Background()
	tag := pgtest.UniqueTag(t)

	broadcasterID := pgtest.InsertUser(t, repo.pool, tag+"_bc", "broadcaster")
	userID := pgtest.InsertUser(t, repo.pool, tag+"_u", "user")
	streamID := insertStream(t, repo.pool, broadcasterID, "Msgs "+tag, tag+"-key")

	if _, err := repo.InsertMessage(ctx, streamID, userID, "msg1"); err != nil {
		t.Fatalf("InsertMessage: %v", err)
	}
	if _, err := repo.InsertMessage(ctx, streamID, userID, "msg2"); err != nil {
		t.Fatalf("InsertMessage: %v", err)
	}

	msgs, err := repo.ListUserMessages(ctx, userID, 50, 0)
	if err != nil {
		t.Fatalf("ListUserMessages: %v", err)
	}
	if len(msgs) < 2 {
		t.Fatalf("got %d messages, want at least 2", len(msgs))
	}

	for _, m := range msgs {
		if m.StreamTitle == "" {
			t.Error("stream title should be populated via join")
		}
	}
}

func TestRepository_IsGloballyBanned_False(t *testing.T) {
	repo := testRepository(t)
	banned, err := repo.IsGloballyBanned(context.Background(), "00000000-0000-0000-0000-000000000000")
	if err != nil {
		t.Fatalf("IsGloballyBanned: %v", err)
	}
	if banned {
		t.Error("non-existent user should not be globally banned")
	}
}

func TestRepository_IsBanned_False(t *testing.T) {
	repo := testRepository(t)
	banned, err := repo.IsBanned(context.Background(), "00000000-0000-0000-0000-000000000000", "00000000-0000-0000-0000-000000000001")
	if err != nil {
		t.Fatalf("IsBanned: %v", err)
	}
	if banned {
		t.Error("non-existent user should not be banned")
	}
}

func TestRepository_InsertBan_Idempotent(t *testing.T) {
	repo := testRepository(t)
	ctx := context.Background()
	tag := pgtest.UniqueTag(t)

	broadcasterID := pgtest.InsertUser(t, repo.pool, tag+"_bc", "broadcaster")
	userID := pgtest.InsertUser(t, repo.pool, tag+"_u", "user")

	if err := repo.InsertBan(ctx, userID, broadcasterID, nil); err != nil {
		t.Fatalf("InsertBan first: %v", err)
	}
	if err := repo.InsertBan(ctx, userID, broadcasterID, nil); err != nil {
		t.Fatalf("InsertBan second (idempotent): %v", err)
	}
}
