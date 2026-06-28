package broadcaster

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	broadcasterdb "github.com/LignacAntony/streampulse/internal/broadcaster/db"
	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

type pgRepository struct {
	pool *pgxpool.Pool
	q    *broadcasterdb.Queries
}

func NewRepository(pool *pgxpool.Pool) Repository {
	return &pgRepository{pool: pool, q: broadcasterdb.New(pool)}
}

func (r *pgRepository) GetUserRole(ctx context.Context, userID string) (string, error) {
	role, err := r.q.GetUserRole(ctx, uuidParam(userID))
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", apperror.NotFound("user not found")
		}
		return "", fmt.Errorf("repo: get user role: %w", err)
	}
	return role, nil
}

func (r *pgRepository) Create(ctx context.Context, userID, message string) (Request, error) {
	row, err := r.q.CreateBroadcasterRequest(ctx, broadcasterdb.CreateBroadcasterRequestParams{
		UserID:  uuidParam(userID),
		Message: message,
	})
	if err != nil {
		if isUniqueViolation(err) {
			return Request{}, apperror.Conflict("a pending broadcaster request already exists")
		}
		return Request{}, fmt.Errorf("repo: create broadcaster request: %w", err)
	}
	return Request{
		ID:         row.ID,
		Status:     row.Status,
		Message:    row.Message,
		ReviewNote: row.ReviewNote,
		ReviewedBy: uuidText(row.ReviewedBy),
		CreatedAt:  row.CreatedAt,
		UpdatedAt:  row.UpdatedAt,
	}, nil
}

func (r *pgRepository) GetLatestByUser(ctx context.Context, userID string) (Request, error) {
	row, err := r.q.GetLatestRequestByUser(ctx, uuidParam(userID))
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Request{}, apperror.NotFound("no broadcaster request found")
		}
		return Request{}, fmt.Errorf("repo: get latest broadcaster request: %w", err)
	}
	return Request{
		ID:         row.ID,
		Status:     row.Status,
		Message:    row.Message,
		ReviewNote: row.ReviewNote,
		ReviewedBy: uuidText(row.ReviewedBy),
		CreatedAt:  row.CreatedAt,
		UpdatedAt:  row.UpdatedAt,
	}, nil
}

func (r *pgRepository) List(ctx context.Context, status *string) ([]AdminRequest, error) {
	var statusParam pgtype.Text
	if status != nil {
		statusParam = pgtype.Text{String: *status, Valid: true}
	}

	rows, err := r.q.ListBroadcasterRequests(ctx, statusParam)
	if err != nil {
		return nil, fmt.Errorf("repo: list broadcaster requests: %w", err)
	}

	requests := make([]AdminRequest, 0, len(rows))
	for _, row := range rows {
		requests = append(requests, AdminRequest{
			Request: Request{
				ID:         row.ID,
				Status:     row.Status,
				Message:    row.Message,
				ReviewNote: row.ReviewNote,
				ReviewedBy: uuidText(row.ReviewedBy),
				CreatedAt:  row.CreatedAt,
				UpdatedAt:  row.UpdatedAt,
			},
			UserID:   row.UserID,
			Email:    row.Email,
			Username: row.Username,
		})
	}
	return requests, nil
}

// Review traite une demande en attente dans une transaction : verrouillage de la
// ligne, vérification du statut, mise à jour, puis promotion du rôle si demandé.
func (r *pgRepository) Review(ctx context.Context, requestID, adminID, status, note string, promote bool) (Request, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return Request{}, fmt.Errorf("repo: begin review tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	qtx := r.q.WithTx(tx)

	current, err := qtx.GetRequestForReview(ctx, uuidParam(requestID))
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Request{}, apperror.NotFound("broadcaster request not found")
		}
		return Request{}, fmt.Errorf("repo: get request for review: %w", err)
	}
	if current.Status != StatusPending {
		return Request{}, apperror.Conflict("broadcaster request already reviewed")
	}

	row, err := qtx.ReviewRequest(ctx, broadcasterdb.ReviewRequestParams{
		ID:         uuidParam(requestID),
		Status:     status,
		ReviewedBy: uuidParam(adminID),
		ReviewNote: note,
	})
	if err != nil {
		return Request{}, fmt.Errorf("repo: review request: %w", err)
	}

	if promote {
		if err := qtx.PromoteUserToBroadcaster(ctx, uuidParam(current.UserID)); err != nil {
			return Request{}, fmt.Errorf("repo: promote user: %w", err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return Request{}, fmt.Errorf("repo: commit review tx: %w", err)
	}

	return Request{
		ID:         row.ID,
		Status:     row.Status,
		Message:    row.Message,
		ReviewNote: row.ReviewNote,
		ReviewedBy: uuidText(row.ReviewedBy),
		CreatedAt:  row.CreatedAt,
		UpdatedAt:  row.UpdatedAt,
	}, nil
}

func uuidParam(s string) pgtype.UUID {
	var u pgtype.UUID
	if err := u.Scan(s); err != nil {
		panic("broadcaster: invalid UUID from internal source: " + s)
	}
	return u
}

// uuidText convertit un UUID nullable en *string canonique pour la sérialisation
// JSON (nil quand la valeur SQL est NULL, ex. demande non encore traitée).
func uuidText(u pgtype.UUID) *string {
	if !u.Valid {
		return nil
	}
	b := u.Bytes
	s := fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
	return &s
}

func isUniqueViolation(err error) bool {
	var pgErr interface{ SQLState() string }
	if errors.As(err, &pgErr) {
		return pgErr.SQLState() == "23505"
	}
	return false
}
