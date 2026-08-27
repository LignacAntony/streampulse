package chat

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"

	chatdb "github.com/LignacAntony/streampulse/internal/chat/db"
)

var errInvalidUUID = apperror.InvalidArgument("invalid UUID")

type pgRepository struct {
	pool *pgxpool.Pool
	q    *chatdb.Queries
}

// NewRepository construit le repository PostgreSQL du domaine chat.
func NewRepository(pool *pgxpool.Pool) Repository {
	return &pgRepository{pool: pool, q: chatdb.New(pool)}
}

func (r *pgRepository) InsertMessage(ctx context.Context, streamID, userID, content string) (Message, error) {
	sid, ok := parseUUID(streamID)
	if !ok {
		return Message{}, errInvalidUUID
	}
	uid, ok := parseUUID(userID)
	if !ok {
		return Message{}, errInvalidUUID
	}
	row, err := r.q.InsertChatMessage(ctx, chatdb.InsertChatMessageParams{
		StreamID: sid,
		UserID:   uid,
		Content:  content,
	})
	if err != nil {
		return Message{}, fmt.Errorf("chat: insert message: %w", err)
	}
	return Message{
		ID:        row.ID,
		StreamID:  row.StreamID,
		UserID:    row.UserID,
		Content:   row.Content,
		CreatedAt: row.CreatedAt,
	}, nil
}

func (r *pgRepository) SoftDeleteMessage(ctx context.Context, messageID, broadcasterID string) error {
	mid, ok := parseUUID(messageID)
	if !ok {
		return errInvalidUUID
	}
	bid, ok := parseUUID(broadcasterID)
	if !ok {
		return errInvalidUUID
	}
	res, err := r.q.SoftDeleteChatMessage(ctx, chatdb.SoftDeleteChatMessageParams{
		ID:            mid,
		BroadcasterID: bid,
	})
	if err != nil {
		return fmt.Errorf("chat: soft delete message: %w", err)
	}
	if res.RowsAffected() == 0 {
		return apperror.NotFound("message not found or already deleted")
	}
	return nil
}

func (r *pgRepository) InsertBan(ctx context.Context, bannedUserID, bannedBy string, reason *string) error {
	buid, ok := parseUUID(bannedUserID)
	if !ok {
		return errInvalidUUID
	}
	bby, ok := parseUUID(bannedBy)
	if !ok {
		return errInvalidUUID
	}
	params := chatdb.InsertChatBanParams{
		BannedUserID: buid,
		BannedBy:     bby,
	}
	if reason != nil {
		params.Reason = pgtype.Text{String: *reason, Valid: true}
	}
	if err := r.q.InsertChatBan(ctx, params); err != nil {
		return fmt.Errorf("chat: insert ban: %w", err)
	}
	return nil
}

func (r *pgRepository) DeleteBan(ctx context.Context, bannedUserID, bannedBy string) error {
	buid, ok := parseUUID(bannedUserID)
	if !ok {
		return errInvalidUUID
	}
	bby, ok := parseUUID(bannedBy)
	if !ok {
		return errInvalidUUID
	}
	res, err := r.q.DeleteChatBan(ctx, chatdb.DeleteChatBanParams{
		BannedUserID: buid,
		BannedBy:     bby,
	})
	if err != nil {
		return fmt.Errorf("chat: delete ban: %w", err)
	}
	if res.RowsAffected() == 0 {
		return apperror.NotFound("ban not found")
	}
	return nil
}

func (r *pgRepository) ListBans(ctx context.Context, bannedBy string) ([]BannedUser, error) {
	bby, ok := parseUUID(bannedBy)
	if !ok {
		return nil, errInvalidUUID
	}
	rows, err := r.q.ListChatBans(ctx, bby)
	if err != nil {
		return nil, fmt.Errorf("chat: list bans: %w", err)
	}
	bans := make([]BannedUser, len(rows))
	for i, row := range rows {
		bans[i] = BannedUser{
			UserID:    row.BannedUserID,
			Username:  row.Username,
			CreatedAt: row.CreatedAt,
		}
		if row.Reason.Valid {
			bans[i].Reason = &row.Reason.String
		}
	}
	return bans, nil
}

func (r *pgRepository) IsBanned(ctx context.Context, userID, broadcasterID string) (bool, error) {
	uid, ok := parseUUID(userID)
	if !ok {
		return false, errInvalidUUID
	}
	bid, ok := parseUUID(broadcasterID)
	if !ok {
		return false, errInvalidUUID
	}
	banned, err := r.q.IsChatBanned(ctx, chatdb.IsChatBannedParams{
		UserID:        uid,
		BroadcasterID: bid,
	})
	if err != nil {
		return false, fmt.Errorf("chat: is banned: %w", err)
	}
	return banned, nil
}

func (r *pgRepository) ListRecentMessages(ctx context.Context, streamID string, limit int32) ([]Message, error) {
	sid, ok := parseUUID(streamID)
	if !ok {
		return nil, errInvalidUUID
	}
	rows, err := r.q.ListRecentChatMessages(ctx, chatdb.ListRecentChatMessagesParams{
		StreamID: sid,
		Lim:      limit,
	})
	if err != nil {
		return nil, fmt.Errorf("chat: list recent messages: %w", err)
	}
	msgs := make([]Message, len(rows))
	for i, row := range rows {
		msgs[i] = Message{
			ID:        row.ID,
			StreamID:  row.StreamID,
			UserID:    row.UserID,
			Username:  row.Username,
			Content:   row.Content,
			CreatedAt: row.CreatedAt,
		}
	}
	return msgs, nil
}

func (r *pgRepository) GetUsername(ctx context.Context, userID string) (string, error) {
	uid, ok := parseUUID(userID)
	if !ok {
		return "", errInvalidUUID
	}
	username, err := r.q.GetUsername(ctx, uid)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", apperror.NotFound("user not found")
		}
		return "", fmt.Errorf("chat: get username: %w", err)
	}
	return username, nil
}

func (r *pgRepository) IsGloballyBanned(ctx context.Context, userID string) (bool, error) {
	uid, ok := parseUUID(userID)
	if !ok {
		return false, errInvalidUUID
	}
	banned, err := r.q.IsGloballyBanned(ctx, uid)
	if err != nil {
		return false, fmt.Errorf("chat: is globally banned: %w", err)
	}
	return banned, nil
}

func (r *pgRepository) InsertGlobalBan(ctx context.Context, bannedUserID, bannedBy string, reason *string) error {
	buid, ok := parseUUID(bannedUserID)
	if !ok {
		return errInvalidUUID
	}
	bby, ok := parseUUID(bannedBy)
	if !ok {
		return errInvalidUUID
	}
	params := chatdb.InsertGlobalBanParams{
		BannedUserID: buid,
		BannedBy:     bby,
	}
	if reason != nil {
		params.Reason = pgtype.Text{String: *reason, Valid: true}
	}
	if err := r.q.InsertGlobalBan(ctx, params); err != nil {
		return fmt.Errorf("chat: insert global ban: %w", err)
	}
	return nil
}

func (r *pgRepository) DeleteGlobalBan(ctx context.Context, bannedUserID string) error {
	buid, ok := parseUUID(bannedUserID)
	if !ok {
		return errInvalidUUID
	}
	res, err := r.q.DeleteGlobalBan(ctx, buid)
	if err != nil {
		return fmt.Errorf("chat: delete global ban: %w", err)
	}
	if res.RowsAffected() == 0 {
		return apperror.NotFound("global ban not found")
	}
	return nil
}

func (r *pgRepository) ListGlobalBans(ctx context.Context) ([]BannedUser, error) {
	rows, err := r.q.ListGlobalBans(ctx)
	if err != nil {
		return nil, fmt.Errorf("chat: list global bans: %w", err)
	}
	bans := make([]BannedUser, len(rows))
	for i, row := range rows {
		bans[i] = BannedUser{
			UserID:    row.BannedUserID,
			Username:  row.Username,
			CreatedAt: row.CreatedAt,
		}
		if row.Reason.Valid {
			bans[i].Reason = &row.Reason.String
		}
	}
	return bans, nil
}

func (r *pgRepository) ListUserMessages(ctx context.Context, userID string, limit, offset int32) ([]UserMessage, error) {
	uid, ok := parseUUID(userID)
	if !ok {
		return nil, errInvalidUUID
	}
	rows, err := r.q.ListUserChatMessages(ctx, chatdb.ListUserChatMessagesParams{
		UserID: uid,
		Lim:    limit,
		Off:    offset,
	})
	if err != nil {
		return nil, fmt.Errorf("chat: list user messages: %w", err)
	}
	msgs := make([]UserMessage, len(rows))
	for i, row := range rows {
		msgs[i] = UserMessage{
			ID:          row.ID,
			StreamID:    row.StreamID,
			UserID:      row.UserID,
			Username:    row.Username,
			Content:     row.Content,
			CreatedAt:   row.CreatedAt,
			StreamTitle: row.StreamTitle,
		}
	}
	return msgs, nil
}

func parseUUID(s string) (pgtype.UUID, bool) {
	var u pgtype.UUID
	if err := u.Scan(s); err != nil {
		return u, false
	}
	return u, true
}
