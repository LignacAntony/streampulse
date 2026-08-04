package playlist

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	playlistdb "github.com/LignacAntony/streampulse/internal/playlist/db"
	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

type pgRepository struct {
	q *playlistdb.Queries
}

// NewRepository construit le repository PostgreSQL du domaine playlist.
func NewRepository(pool *pgxpool.Pool) Repository {
	return &pgRepository{q: playlistdb.New(pool)}
}

func (r *pgRepository) Create(ctx context.Context, p CreateParams) (Playlist, error) {
	row, err := r.q.CreatePlaylist(ctx, playlistdb.CreatePlaylistParams{
		UserID:      uuidParam(p.UserID),
		Name:        p.Name,
		Description: textParam(p.Description),
	})
	if err != nil {
		if isUniqueViolation(err) {
			return Playlist{}, apperror.Conflict("Une playlist porte déjà ce nom")
		}
		if isForeignKeyViolation(err) {
			return Playlist{}, apperror.Unauthorized("invalid user")
		}
		return Playlist{}, fmt.Errorf("repo: create playlist: %w", err)
	}
	return Playlist{
		ID:          row.ID,
		UserID:      row.UserID,
		Name:        row.Name,
		Description: textValue(row.Description),
		IsPublic:    row.IsPublic,
		TrackCount:  int(row.TrackCount),
		CreatedAt:   row.CreatedAt,
		UpdatedAt:   row.UpdatedAt,
	}, nil
}

func (r *pgRepository) ListByUser(ctx context.Context, userID string) ([]Playlist, error) {
	rows, err := r.q.ListPlaylistsByUser(ctx, uuidParam(userID))
	if err != nil {
		return nil, fmt.Errorf("repo: list playlists: %w", err)
	}
	playlists := make([]Playlist, 0, len(rows))
	for _, row := range rows {
		playlists = append(playlists, Playlist{
			ID:          row.ID,
			UserID:      row.UserID,
			Name:        row.Name,
			Description: textValue(row.Description),
			IsPublic:    row.IsPublic,
			TrackCount:  int(row.TrackCount),
			CreatedAt:   row.CreatedAt,
			UpdatedAt:   row.UpdatedAt,
		})
	}
	return playlists, nil
}

func (r *pgRepository) GetByID(ctx context.Context, id string) (Playlist, error) {
	uid, ok := parseUUID(id)
	if !ok {
		return Playlist{}, apperror.NotFound("playlist not found")
	}
	row, err := r.q.GetPlaylistByID(ctx, uid)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Playlist{}, apperror.NotFound("playlist not found")
		}
		return Playlist{}, fmt.Errorf("repo: get playlist: %w", err)
	}
	return Playlist{
		ID:          row.ID,
		UserID:      row.UserID,
		Name:        row.Name,
		Description: textValue(row.Description),
		IsPublic:    row.IsPublic,
		TrackCount:  int(row.TrackCount),
		CreatedAt:   row.CreatedAt,
		UpdatedAt:   row.UpdatedAt,
	}, nil
}

func (r *pgRepository) Update(ctx context.Context, p UpdateParams) (Playlist, error) {
	uid, ok := parseUUID(p.ID)
	if !ok {
		return Playlist{}, apperror.NotFound("playlist not found")
	}
	row, err := r.q.UpdatePlaylist(ctx, playlistdb.UpdatePlaylistParams{
		ID:          uid,
		UserID:      uuidParam(p.UserID),
		Name:        p.Name,
		Description: textParam(p.Description),
	})
	if err != nil {
		// Aucune ligne mise à jour (id inconnu ou autre propriétaire).
		if errors.Is(err, pgx.ErrNoRows) {
			return Playlist{}, apperror.NotFound("playlist not found")
		}
		if isUniqueViolation(err) {
			return Playlist{}, apperror.Conflict("Une playlist porte déjà ce nom")
		}
		return Playlist{}, fmt.Errorf("repo: update playlist: %w", err)
	}
	return Playlist{
		ID:          row.ID,
		UserID:      row.UserID,
		Name:        row.Name,
		Description: textValue(row.Description),
		IsPublic:    row.IsPublic,
		TrackCount:  int(row.TrackCount),
		CreatedAt:   row.CreatedAt,
		UpdatedAt:   row.UpdatedAt,
	}, nil
}

func (r *pgRepository) Delete(ctx context.Context, id, userID string) error {
	uid, ok := parseUUID(id)
	if !ok {
		return apperror.NotFound("playlist not found")
	}
	if _, err := r.q.DeletePlaylist(ctx, playlistdb.DeletePlaylistParams{
		ID:     uid,
		UserID: uuidParam(userID),
	}); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return apperror.NotFound("playlist not found")
		}
		return fmt.Errorf("repo: delete playlist: %w", err)
	}
	return nil
}

func (r *pgRepository) ListTracks(ctx context.Context, playlistID string) ([]PlaylistTrack, error) {
	uid, ok := parseUUID(playlistID)
	if !ok {
		return nil, apperror.NotFound("playlist not found")
	}
	rows, err := r.q.ListPlaylistTracks(ctx, uid)
	if err != nil {
		return nil, fmt.Errorf("repo: list playlist tracks: %w", err)
	}
	tracks := make([]PlaylistTrack, 0, len(rows))
	for _, row := range rows {
		tracks = append(tracks, PlaylistTrack{
			ID:        row.ID,
			Title:     row.Title,
			Artist:    textValue(row.Artist),
			DurationS: int4Value(row.DurationS),
			Position:  int(row.Position),
		})
	}
	return tracks, nil
}

func uuidParam(s string) pgtype.UUID {
	var u pgtype.UUID
	if err := u.Scan(s); err != nil {
		panic("playlist: invalid UUID from internal source: " + s)
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
