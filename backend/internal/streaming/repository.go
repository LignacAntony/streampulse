package streaming

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	streamingdb "github.com/LignacAntony/streampulse/internal/streaming/db"
)

type pgRepository struct {
	q *streamingdb.Queries
}

// NewRepository construit le repository PostgreSQL du domaine streaming.
func NewRepository(pool *pgxpool.Pool) Repository {
	return &pgRepository{q: streamingdb.New(pool)}
}

func (r *pgRepository) Create(ctx context.Context, p CreateParams) (Stream, error) {
	row, err := r.q.CreateStream(ctx, streamingdb.CreateStreamParams{
		UserID:      uuidParam(p.UserID),
		Title:       p.Title,
		Description: textParam(p.Description),
		Category:    textParam(p.Category),
		Status:      p.Status,
		IsPublic:    p.IsPublic,
		StreamKey:   p.StreamKey,
	})
	if err != nil {
		return Stream{}, fmt.Errorf("repo: create stream: %w", err)
	}

	return Stream{
		ID:          row.ID,
		UserID:      row.UserID,
		Title:       row.Title,
		Description: textValue(row.Description),
		Category:    textValue(row.Category),
		Status:      row.Status,
		IsPublic:    row.IsPublic,
		StreamKey:   row.StreamKey,
		CreatedAt:   row.CreatedAt,
		UpdatedAt:   row.UpdatedAt,
	}, nil
}

func uuidParam(s string) pgtype.UUID {
	var u pgtype.UUID
	if err := u.Scan(s); err != nil {
		panic("streaming: invalid UUID from internal source: " + s)
	}
	return u
}

func textParam(s *string) pgtype.Text {
	if s == nil {
		return pgtype.Text{}
	}
	return pgtype.Text{String: *s, Valid: true}
}

func textValue(t pgtype.Text) *string {
	if !t.Valid {
		return nil
	}
	return &t.String
}
