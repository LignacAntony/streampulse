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

type pgRepository struct {
	q *chatdb.Queries
}

// NewRepository construit le repository PostgreSQL du domaine chat.
func NewRepository(pool *pgxpool.Pool) Repository {
	return &pgRepository{q: chatdb.New(pool)}
}

func (r *pgRepository) InsertMessage(ctx context.Context, streamID, userID, content string) (Message, error) {
	row, err := r.q.InsertChatMessage(ctx, chatdb.InsertChatMessageParams{
		StreamID: uuidParam(streamID),
		UserID:   uuidParam(userID),
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
	res, err := r.q.SoftDeleteChatMessage(ctx, chatdb.SoftDeleteChatMessageParams{
		ID:            uuidParam(messageID),
		BroadcasterID: uuidParam(broadcasterID),
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
	params := chatdb.InsertChatBanParams{
		BannedUserID: uuidParam(bannedUserID),
		BannedBy:     uuidParam(bannedBy),
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
	res, err := r.q.DeleteChatBan(ctx, chatdb.DeleteChatBanParams{
		BannedUserID: uuidParam(bannedUserID),
		BannedBy:     uuidParam(bannedBy),
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
	rows, err := r.q.ListChatBans(ctx, uuidParam(bannedBy))
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
	banned, err := r.q.IsChatBanned(ctx, chatdb.IsChatBannedParams{
		UserID:        uuidParam(userID),
		BroadcasterID: uuidParam(broadcasterID),
	})
	if err != nil {
		return false, fmt.Errorf("chat: is banned: %w", err)
	}
	return banned, nil
}

func (r *pgRepository) ListRecentMessages(ctx context.Context, streamID string, limit int32) ([]Message, error) {
	rows, err := r.q.ListRecentChatMessages(ctx, chatdb.ListRecentChatMessagesParams{
		StreamID: uuidParam(streamID),
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
	username, err := r.q.GetUsername(ctx, uuidParam(userID))
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", apperror.NotFound("user not found")
		}
		return "", fmt.Errorf("chat: get username: %w", err)
	}
	return username, nil
}

func (r *pgRepository) IsGloballyBanned(ctx context.Context, userID string) (bool, error) {
	banned, err := r.q.IsGloballyBanned(ctx, uuidParam(userID))
	if err != nil {
		return false, fmt.Errorf("chat: is globally banned: %w", err)
	}
	return banned, nil
}

func (r *pgRepository) InsertGlobalBan(ctx context.Context, bannedUserID, bannedBy string, reason *string) error {
	params := chatdb.InsertGlobalBanParams{
		BannedUserID: uuidParam(bannedUserID),
		BannedBy:     uuidParam(bannedBy),
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
	res, err := r.q.DeleteGlobalBan(ctx, uuidParam(bannedUserID))
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
	rows, err := r.q.ListUserChatMessages(ctx, chatdb.ListUserChatMessagesParams{
		UserID: uuidParam(userID),
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

func uuidParam(s string) pgtype.UUID {
	var u pgtype.UUID
	if err := u.Scan(s); err != nil {
		panic("chat: invalid UUID from internal source: " + s)
	}
	return u
}
