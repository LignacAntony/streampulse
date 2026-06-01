package auth

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	authdb "github.com/LignacAntony/streampulse/internal/auth/db"
	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

type pgRepository struct {
	pool *pgxpool.Pool
	q    *authdb.Queries
}

func NewRepository(pool *pgxpool.Pool) Repository {
	return &pgRepository{pool: pool, q: authdb.New(pool)}
}

func (r *pgRepository) CreateUser(ctx context.Context, email, username, passwordHash string) (User, error) {
	row, err := r.q.CreateUser(ctx, authdb.CreateUserParams{
		Email:        email,
		Username:     username,
		PasswordHash: passwordHash,
	})
	if err != nil {
		if isUniqueViolation(err) {
			return User{}, apperror.Conflict("email or username already taken")
		}
		return User{}, fmt.Errorf("repo: insert user: %w", err)
	}
	return User{
		ID:        row.ID,
		Email:     row.Email,
		Username:  row.Username,
		Role:      row.Role,
		CreatedAt: row.CreatedAt,
	}, nil
}

func (r *pgRepository) GetUserByEmail(ctx context.Context, email string) (UserWithHash, error) {
	row, err := r.q.GetUserByEmail(ctx, email)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return UserWithHash{}, apperror.NotFound("user not found")
		}
		return UserWithHash{}, fmt.Errorf("repo: get user by email: %w", err)
	}
	return UserWithHash{
		User: User{
			ID:        row.ID,
			Email:     row.Email,
			Username:  row.Username,
			Role:      row.Role,
			CreatedAt: row.CreatedAt,
		},
		PasswordHash: row.PasswordHash,
	}, nil
}

func (r *pgRepository) StoreRefreshToken(ctx context.Context, userID, tokenHash string, expiresAt time.Time) error {
	if err := r.q.InsertRefreshToken(ctx, authdb.InsertRefreshTokenParams{
		UserID:    uuidParam(userID),
		TokenHash: tokenHash,
		ExpiresAt: expiresAt,
	}); err != nil {
		return fmt.Errorf("repo: store refresh token: %w", err)
	}
	return nil
}

func (r *pgRepository) GetUserByRefreshToken(ctx context.Context, tokenHash string) (User, error) {
	row, err := r.q.GetUserByRefreshToken(ctx, tokenHash)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return User{}, apperror.Unauthorized("invalid or expired refresh token")
		}
		return User{}, fmt.Errorf("repo: get user by refresh token: %w", err)
	}
	return User{
		ID:        row.ID,
		Email:     row.Email,
		Username:  row.Username,
		Role:      row.Role,
		CreatedAt: row.CreatedAt,
	}, nil
}

// RotateRefreshToken : WithTx permet d'utiliser les mêmes queries générées dans la transaction.
func (r *pgRepository) RotateRefreshToken(ctx context.Context, oldHash, newHash, userID string, expiresAt time.Time) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("repo: begin rotate tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	qtx := r.q.WithTx(tx)

	tag, err := qtx.DeleteRefreshToken(ctx, oldHash)
	if err != nil {
		return fmt.Errorf("repo: delete old refresh token: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return apperror.Unauthorized("invalid or expired refresh token")
	}

	if err := qtx.InsertRefreshToken(ctx, authdb.InsertRefreshTokenParams{
		UserID:    uuidParam(userID),
		TokenHash: newHash,
		ExpiresAt: expiresAt,
	}); err != nil {
		return fmt.Errorf("repo: insert new refresh token: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("repo: commit rotate tx: %w", err)
	}
	return nil
}

func (r *pgRepository) RevokeRefreshToken(ctx context.Context, tokenHash string) error {
	if _, err := r.q.DeleteRefreshToken(ctx, tokenHash); err != nil {
		return fmt.Errorf("repo: revoke refresh token: %w", err)
	}
	return nil
}

func (r *pgRepository) CheckPasswordResetToken(ctx context.Context, tokenHash string) error {
	_, err := r.q.GetValidPasswordResetToken(ctx, tokenHash)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return apperror.InvalidArgument("invalid or expired reset token")
		}
		return fmt.Errorf("repo: check password reset token: %w", err)
	}
	return nil
}

func (r *pgRepository) StorePasswordResetToken(ctx context.Context, userID, tokenHash string, expiresAt time.Time) error {
	if err := r.q.InsertPasswordResetToken(ctx, authdb.InsertPasswordResetTokenParams{
		UserID:    uuidParam(userID),
		TokenHash: tokenHash,
		ExpiresAt: expiresAt,
	}); err != nil {
		return fmt.Errorf("repo: store password reset token: %w", err)
	}
	return nil
}

func (r *pgRepository) DeletePendingPasswordResetsByUser(ctx context.Context, userID string) error {
	if err := r.q.DeletePendingPasswordResetsByUser(ctx, uuidParam(userID)); err != nil {
		return fmt.Errorf("repo: delete pending password resets: %w", err)
	}
	return nil
}

func (r *pgRepository) ResetPassword(ctx context.Context, tokenHash, passwordHash string) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("repo: begin reset password tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	qtx := r.q.WithTx(tx)

	userID, err := qtx.GetValidPasswordResetToken(ctx, tokenHash)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return apperror.InvalidArgument("invalid or expired reset token")
		}
		return fmt.Errorf("repo: get password reset token: %w", err)
	}

	if err := qtx.UpdateUserPasswordHash(ctx, authdb.UpdateUserPasswordHashParams{
		PasswordHash: passwordHash,
		ID:           uuidParam(userID),
	}); err != nil {
		return fmt.Errorf("repo: update user password: %w", err)
	}

	if err := qtx.MarkPasswordResetTokenUsed(ctx, tokenHash); err != nil {
		return fmt.Errorf("repo: mark reset token used: %w", err)
	}

	if err := qtx.DeleteAllRefreshTokensByUser(ctx, uuidParam(userID)); err != nil {
		return fmt.Errorf("repo: revoke refresh tokens after password reset: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("repo: commit reset password tx: %w", err)
	}
	return nil
}

func uuidParam(s string) pgtype.UUID {
	var u pgtype.UUID
	if err := u.Scan(s); err != nil {
		panic("auth: invalid UUID from internal source: " + s)
	}
	return u
}

func isUniqueViolation(err error) bool {
	var pgErr interface{ SQLState() string }
	if errors.As(err, &pgErr) {
		return pgErr.SQLState() == "23505"
	}
	return false
}
