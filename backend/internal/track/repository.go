package track

import (
	"context"
	"errors"
	"fmt"
	"math"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
	trackdb "github.com/LignacAntony/streampulse/internal/track/db"
)

type pgRepository struct {
	q *trackdb.Queries
}

// NewRepository construit le repository PostgreSQL du domaine track.
func NewRepository(pool *pgxpool.Pool) Repository {
	return &pgRepository{q: trackdb.New(pool)}
}

func (r *pgRepository) CreateTrack(ctx context.Context, p CreateTrackParams) (Track, error) {
	row, err := r.q.CreateTrack(ctx, trackdb.CreateTrackParams{
		UserID:    uuidParam(p.UserID),
		Title:     p.Title,
		Artist:    textParam(p.Artist),
		DurationS: int4Param(p.DurationS),
		FilePath:  p.FilePath,
		MimeType:  p.MimeType,
		FileSize:  p.FileSize,
		IsPublic:  p.IsPublic,
	})
	if err != nil {
		if isUniqueViolation(err) {
			return Track{}, apperror.Conflict("Une piste porte déjà ce titre")
		}
		if isForeignKeyViolation(err) {
			return Track{}, apperror.Unauthorized("invalid user")
		}
		return Track{}, fmt.Errorf("repo: create track: %w", err)
	}
	return Track{
		ID:        row.ID,
		Title:     row.Title,
		Artist:    textValue(row.Artist),
		DurationS: int4Value(row.DurationS),
		IsPublic:  row.IsPublic,
	}, nil
}

func (r *pgRepository) ListTracksByUser(ctx context.Context, userID string) ([]Track, error) {
	rows, err := r.q.ListTracksByUser(ctx, uuidParam(userID))
	if err != nil {
		return nil, fmt.Errorf("repo: list user tracks: %w", err)
	}
	tracks := make([]Track, 0, len(rows))
	for _, row := range rows {
		tracks = append(tracks, Track{
			ID:        row.ID,
			Title:     row.Title,
			Artist:    textValue(row.Artist),
			DurationS: int4Value(row.DurationS),
			IsPublic:  row.IsPublic,
		})
	}
	return tracks, nil
}

func (r *pgRepository) DeleteTrack(ctx context.Context, trackID, userID string) (string, bool, error) {
	id, ok := parseUUID(trackID)
	if !ok {
		return "", false, nil
	}
	filePath, err := r.q.DeleteTrack(ctx, trackdb.DeleteTrackParams{
		ID:     id,
		UserID: uuidParam(userID),
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", false, nil
		}
		return "", false, fmt.Errorf("repo: delete track: %w", err)
	}
	return filePath, true, nil
}

func (r *pgRepository) ListPublicTracks(ctx context.Context, cursor *PublicTrackCursor, pageSize int) ([]PublicTrack, error) {
	var rows []trackdb.ListPublicTracksFirstRow
	var err error

	ps := int32(min(pageSize, 50))
	if cursor == nil {
		rows, err = r.q.ListPublicTracksFirst(ctx, ps)
	} else {
		var dbRows []trackdb.ListPublicTracksRow
		dbRows, err = r.q.ListPublicTracks(ctx, trackdb.ListPublicTracksParams{
			CursorCreatedAt: timestamptzParam(cursor.CreatedAt),
			CursorID:        uuidParam(cursor.ID),
			PageSize:        ps,
		})
		rows = make([]trackdb.ListPublicTracksFirstRow, len(dbRows))
		for i, r := range dbRows {
			rows[i] = trackdb.ListPublicTracksFirstRow(r)
		}
	}
	if err != nil {
		return nil, fmt.Errorf("repo: list public tracks: %w", err)
	}
	tracks := make([]PublicTrack, 0, len(rows))
	for _, row := range rows {
		tracks = append(tracks, PublicTrack{
			ID:        row.ID,
			Title:     row.Title,
			Artist:    textValue(row.Artist),
			DurationS: int4Value(row.DurationS),
			OwnerName: row.OwnerName,
		})
	}
	return tracks, nil
}

func (r *pgRepository) UpdateTrackVisibility(ctx context.Context, trackID, userID string, isPublic bool) (bool, error) {
	id, ok := parseUUID(trackID)
	if !ok {
		return false, nil
	}
	n, err := r.q.UpdateTrackVisibility(ctx, trackdb.UpdateTrackVisibilityParams{
		IsPublic: isPublic,
		ID:       id,
		UserID:   uuidParam(userID),
	})
	if err != nil {
		return false, fmt.Errorf("repo: update track visibility: %w", err)
	}
	return n > 0, nil
}

func (r *pgRepository) GetTrackFileForStream(ctx context.Context, trackID, userID string) (TrackFile, error) {
	id, ok := parseUUID(trackID)
	if !ok {
		return TrackFile{}, apperror.NotFound("track not found")
	}
	row, err := r.q.GetTrackFileForStream(ctx, trackdb.GetTrackFileForStreamParams{
		ID:     id,
		UserID: uuidParam(userID),
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return TrackFile{}, apperror.NotFound("track not found")
		}
		return TrackFile{}, fmt.Errorf("repo: get track file for stream: %w", err)
	}
	return TrackFile{
		Path:     row.FilePath,
		MimeType: row.MimeType,
	}, nil
}

func (r *pgRepository) GetTrackFileByUser(ctx context.Context, trackID, userID string) (TrackFile, error) {
	// L'id vient du path : un UUID malformé n'est pas une erreur serveur, c'est
	// une piste qui n'existe pas.
	id, ok := parseUUID(trackID)
	if !ok {
		return TrackFile{}, apperror.NotFound("track not found")
	}
	row, err := r.q.GetTrackFileByUser(ctx, trackdb.GetTrackFileByUserParams{
		ID:     id,
		UserID: uuidParam(userID),
	})
	if err != nil {
		// 0 ligne = piste inconnue OU piste d'un tiers : même réponse, l'API ne
		// divulgue pas l'existence de la bibliothèque d'autrui.
		if errors.Is(err, pgx.ErrNoRows) {
			return TrackFile{}, apperror.NotFound("track not found")
		}
		return TrackFile{}, fmt.Errorf("repo: get track file: %w", err)
	}
	return TrackFile{
		Path:     row.FilePath,
		MimeType: row.MimeType,
	}, nil
}

func (r *pgRepository) SumFileSizeByUser(ctx context.Context, userID string) (int64, error) {
	total, err := r.q.SumTrackSizeByUser(ctx, uuidParam(userID))
	if err != nil {
		return 0, fmt.Errorf("repo: sum user file size: %w", err)
	}
	return total, nil
}

func (r *pgRepository) ListFilePathsByUser(ctx context.Context, userID string) ([]string, error) {
	paths, err := r.q.ListFilePathsByUser(ctx, uuidParam(userID))
	if err != nil {
		return nil, fmt.Errorf("repo: list user file paths: %w", err)
	}
	return paths, nil
}

// uuidParam convertit un UUID de source interne (user_id issu du JWT). Une valeur
// invalide signalerait un bug d'authentification, d'où le panic.
func uuidParam(s string) pgtype.UUID {
	var u pgtype.UUID
	if err := u.Scan(s); err != nil {
		panic("track: invalid UUID from internal source: " + s)
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

func timestamptzParam(t time.Time) pgtype.Timestamptz {
	return pgtype.Timestamptz{Time: t, Valid: true}
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

func int4Param(v *int) pgtype.Int4 {
	// La durée est déjà validée en amont (normalizeDuration : > 0 et ≤ MaxInt32).
	// Ce garde-fou borne quand même la conversion int -> int32 (colonne int4) pour
	// écarter tout débordement (gosec G115) : hors plage -> NULL plutôt que wrap.
	if v == nil || *v < 0 || *v > math.MaxInt32 {
		return pgtype.Int4{}
	}
	return pgtype.Int4{Int32: int32(*v), Valid: true}
}

func int4Value(v pgtype.Int4) *int {
	if !v.Valid {
		return nil
	}
	n := int(v.Int32)
	return &n
}

func isForeignKeyViolation(err error) bool {
	return isPgError(err, "23503")
}

func isUniqueViolation(err error) bool {
	return isPgError(err, "23505")
}

func isPgError(err error, sqlState string) bool {
	var pgErr interface{ SQLState() string }
	if errors.As(err, &pgErr) {
		return pgErr.SQLState() == sqlState
	}
	return false
}
