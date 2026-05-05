package auth

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgerrcode"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

// pgRepository persiste les utilisateurs via un *pgxpool.Pool partagé.
type pgRepository struct {
	pool *pgxpool.Pool
}

// NewRepository construit un Repository basé sur PostgreSQL.
func NewRepository(pool *pgxpool.Pool) Repository {
	return &pgRepository{pool: pool}
}

const insertUserSQL = `
	INSERT INTO users (email, username, password_hash)
	VALUES ($1, $2, $3)
	RETURNING id::text, email, username, role, created_at
`

// CreateUser insère une ligne dans users. Retourne un conflit si la
// contrainte UNIQUE sur email ou username est violée.
func (r *pgRepository) CreateUser(ctx context.Context, email, username, passwordHash string) (User, error) {
	var u User
	err := r.pool.
		QueryRow(ctx, insertUserSQL, email, username, passwordHash).
		Scan(&u.ID, &u.Email, &u.Username, &u.Role, &u.CreatedAt)

	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == pgerrcode.UniqueViolation {
			return User{}, apperror.Conflict("email or username already taken")
		}
		return User{}, fmt.Errorf("repo: insert user: %w", err)
	}

	return u, nil
}
