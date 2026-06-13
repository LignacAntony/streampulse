package profiles

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	profilesdb "github.com/LignacAntony/streampulse/internal/profiles/db"
	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

type pgRepository struct {
	pool *pgxpool.Pool
	q    *profilesdb.Queries
}

func NewRepository(pool *pgxpool.Pool) Repository {
	return &pgRepository{pool: pool, q: profilesdb.New(pool)}
}

func (r *pgRepository) GetMe(ctx context.Context, userID string) (Profile, error) {
	row, err := r.q.GetMe(ctx, uuidParam(userID))
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Profile{}, apperror.NotFound("user not found")
		}
		return Profile{}, fmt.Errorf("repo: get me: %w", err)
	}

	var avatarURL *string
	if row.AvatarUrl.Valid {
		avatarURL = &row.AvatarUrl.String
	}

	return Profile{
		ID:                   row.ID,
		Email:                row.Email,
		Role:                 row.Role,
		Pseudo:               row.Pseudo,
		Bio:                  row.Bio,
		AvatarURL:            avatarURL,
		Theme:                row.Theme,
		NotificationsEnabled: row.NotificationsEnabled,
		AudioQuality:         row.AudioQuality,
		CreatedAt:            row.CreatedAt,
	}, nil
}

func (r *pgRepository) UpsertProfile(ctx context.Context, userID string, in UpdateProfileInput) error {
	if err := r.q.UpsertProfile(ctx, profilesdb.UpsertProfileParams{
		UserID:               uuidParam(userID),
		Pseudo:               in.Pseudo,
		Bio:                  in.Bio,
		Theme:                in.Theme,
		NotificationsEnabled: in.NotificationsEnabled,
		AudioQuality:         in.AudioQuality,
	}); err != nil {
		return fmt.Errorf("repo: upsert profile: %w", err)
	}
	return nil
}

func uuidParam(s string) pgtype.UUID {
	var u pgtype.UUID
	if err := u.Scan(s); err != nil {
		panic("profiles: invalid UUID from internal source: " + s)
	}
	return u
}
