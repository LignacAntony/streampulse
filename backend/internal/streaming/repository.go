package streaming

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
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
		return Stream{}, createStreamError(err)
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

func (r *pgRepository) ListPublicLive(ctx context.Context, limit, offset int32) ([]Stream, error) {
	rows, err := r.q.ListPublicLiveStreams(ctx, streamingdb.ListPublicLiveStreamsParams{
		Lim: limit,
		Off: offset,
	})
	if err != nil {
		return nil, fmt.Errorf("repo: list public live streams: %w", err)
	}

	streams := make([]Stream, 0, len(rows))
	for _, row := range rows {
		streams = append(streams, Stream{
			ID:          row.ID,
			UserID:      row.UserID,
			Title:       row.Title,
			Description: textValue(row.Description),
			Category:    textValue(row.Category),
			Status:      row.Status,
			IsPublic:    row.IsPublic,
			StartedAt:   row.StartedAt,
			EndedAt:     row.EndedAt,
			CreatedAt:   row.CreatedAt,
			UpdatedAt:   row.UpdatedAt,
		})
	}
	return streams, nil
}

func (r *pgRepository) GetByID(ctx context.Context, id string) (Stream, error) {
	uid, ok := parseUUID(id)
	if !ok {
		return Stream{}, apperror.NotFound("stream not found")
	}
	row, err := r.q.GetStreamByID(ctx, uid)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Stream{}, apperror.NotFound("stream not found")
		}
		return Stream{}, fmt.Errorf("repo: get stream: %w", err)
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
		StartedAt:   row.StartedAt,
		EndedAt:     row.EndedAt,
		CreatedAt:   row.CreatedAt,
		UpdatedAt:   row.UpdatedAt,
	}, nil
}

func (r *pgRepository) Update(ctx context.Context, p UpdateParams) (Stream, error) {
	uid, ok := parseUUID(p.ID)
	if !ok {
		return Stream{}, apperror.NotFound("stream not found")
	}
	row, err := r.q.UpdateStream(ctx, streamingdb.UpdateStreamParams{
		ID:          uid,
		UserID:      uuidParam(p.UserID),
		Title:       p.Title,
		Description: textParam(p.Description),
		Category:    textParam(p.Category),
		IsPublic:    p.IsPublic,
	})
	if err != nil {
		// Aucune ligne mise à jour (id inconnu, archivé, ou autre propriétaire).
		if errors.Is(err, pgx.ErrNoRows) {
			return Stream{}, apperror.NotFound("stream not found")
		}
		return Stream{}, fmt.Errorf("repo: update stream: %w", err)
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
		StartedAt:   row.StartedAt,
		EndedAt:     row.EndedAt,
		CreatedAt:   row.CreatedAt,
		UpdatedAt:   row.UpdatedAt,
	}, nil
}

func (r *pgRepository) Archive(ctx context.Context, id, userID string) error {
	uid, ok := parseUUID(id)
	if !ok {
		return apperror.NotFound("stream not found")
	}
	n, err := r.q.ArchiveStream(ctx, streamingdb.ArchiveStreamParams{
		ID:     uid,
		UserID: uuidParam(userID),
	})
	if err != nil {
		return fmt.Errorf("repo: archive stream: %w", err)
	}
	if n == 0 {
		return apperror.NotFound("stream not found")
	}
	return nil
}

// uuidParam convertit un UUID provenant d'une source de confiance (JWT) ;
// une valeur invalide est un bug, d'où le panic.
func uuidParam(s string) pgtype.UUID {
	var u pgtype.UUID
	if err := u.Scan(s); err != nil {
		panic("streaming: invalid UUID from internal source: " + s)
	}
	return u
}

// parseUUID convertit un UUID fourni par l'utilisateur (path param) sans paniquer.
func parseUUID(s string) (pgtype.UUID, bool) {
	var u pgtype.UUID
	if err := u.Scan(s); err != nil {
		return u, false
	}
	return u, true
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

func createStreamError(err error) error {
	if isForeignKeyViolation(err) {
		return apperror.Unauthorized("invalid user")
	}
	return fmt.Errorf("repo: create stream: %w", err)
}

func isForeignKeyViolation(err error) bool {
	var pgErr interface{ SQLState() string }
	if errors.As(err, &pgErr) {
		return pgErr.SQLState() == "23503"
	}
	return false
}
