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
	// pool sert aux mutations multi-requêtes (retrait + recompactage,
	// réordonnancement) qui doivent tenir dans une seule transaction.
	pool *pgxpool.Pool
}

// NewRepository construit le repository PostgreSQL du domaine playlist.
func NewRepository(pool *pgxpool.Pool) Repository {
	return &pgRepository{q: playlistdb.New(pool), pool: pool}
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
		IsFavorite:  row.IsFavorite,
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
			IsFavorite:  row.IsFavorite,
			CreatedAt:   row.CreatedAt,
			UpdatedAt:   row.UpdatedAt,
		})
	}
	return playlists, nil
}

func (r *pgRepository) GetByID(ctx context.Context, id, userID string) (Playlist, error) {
	uid, ok := parseUUID(id)
	if !ok {
		return Playlist{}, apperror.NotFound("playlist not found")
	}
	row, err := r.q.GetPlaylistByID(ctx, playlistdb.GetPlaylistByIDParams{
		ID:     uid,
		UserID: uuidParam(userID),
	})
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
		IsFavorite:  row.IsFavorite,
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
		IsFavorite:  row.IsFavorite,
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

// addTrackAttempts borne la reprise d'un ajout perdu à la course sur la position
// (cf. AddTrack). Une seule reprise suffit : deux ajouts concurrents sur la même
// playlist restent un cas rare (même utilisateur, deux appareils), et le perdant
// relit un MAX(position) désormais à jour.
const addTrackAttempts = 2

func (r *pgRepository) AddTrack(ctx context.Context, p AddTrackParams) error {
	playlistID, ok := parseUUID(p.PlaylistID)
	if !ok {
		return apperror.NotFound("playlist not found")
	}
	trackID, ok := parseUUID(p.TrackID)
	if !ok {
		return apperror.NotFound("track not found")
	}

	// La position vient d'un MAX(position)+1 lu dans la transaction : deux ajouts
	// simultanés lisent le même maximum et visent la même position. Le perdant
	// échoue au COMMIT (contrainte différée) — on rejoue son insertion plutôt que
	// de lui renvoyer un conflit qu'il n'a aucun moyen de résoudre.
	var err error
	for attempt := 0; attempt < addTrackAttempts; attempt++ {
		err = r.inTx(ctx, func(q *playlistdb.Queries) error {
			total, err := q.CountPlaylistTracks(ctx, playlistID)
			if err != nil {
				return fmt.Errorf("repo: count playlist tracks: %w", err)
			}
			// Plafond aligné sur celui du réordonnancement : au-delà, le PUT
			// (qui porte l'ordre complet) serait rejeté et la playlist
			// deviendrait impossible à réordonner.
			if total >= MaxTracksPerPlaylist {
				return apperror.Conflict("Cette playlist a atteint sa taille maximale")
			}
			if _, err := q.AddTrackToPlaylist(ctx, playlistdb.AddTrackToPlaylistParams{
				PlaylistID: playlistID,
				TrackID:    trackID,
				UserID:     uuidParam(p.UserID),
			}); err != nil {
				// Aucune ligne insérée : la piste n'existe pas ou appartient à un tiers.
				if errors.Is(err, pgx.ErrNoRows) {
					return apperror.NotFound("track not found")
				}
				// PK (playlist_id, track_id) : contrainte immédiate, elle lève
				// ici et non au COMMIT — la piste est déjà dans la playlist.
				if isUniqueViolation(err) {
					return apperror.Conflict("Cette piste est déjà dans la playlist")
				}
				return fmt.Errorf("repo: add track: %w", err)
			}
			return q.TouchPlaylist(ctx, playlistID)
		})
		if !errors.Is(err, errPositionTaken) {
			return err
		}
	}
	// Reprises épuisées : message propre à l'ajout, pas celui du réordonnancement.
	return apperror.Conflict("Ajout impossible pour le moment, réessaie")
}

func (r *pgRepository) RemoveTrack(ctx context.Context, playlistID, trackID string) error {
	pid, ok := parseUUID(playlistID)
	if !ok {
		return apperror.NotFound("playlist not found")
	}
	tid, ok := parseUUID(trackID)
	if !ok {
		return apperror.NotFound("track not found")
	}
	err := r.inTx(ctx, func(q *playlistdb.Queries) error {
		if _, err := q.RemoveTrackFromPlaylist(ctx, playlistdb.RemoveTrackFromPlaylistParams{
			PlaylistID: pid,
			TrackID:    tid,
		}); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return apperror.NotFound("track not found")
			}
			return fmt.Errorf("repo: remove track: %w", err)
		}
		// Recompactage dans la même transaction : les positions restent
		// contiguës, sans quoi un réordonnancement ultérieur partirait d'index
		// troués.
		if err := q.ResequencePlaylistTracks(ctx, pid); err != nil {
			return fmt.Errorf("repo: resequence tracks: %w", err)
		}
		return q.TouchPlaylist(ctx, pid)
	})
	if errors.Is(err, errPositionTaken) {
		return apperror.Conflict("La playlist a changé, recharge-la")
	}
	return err
}

func (r *pgRepository) Reorder(ctx context.Context, playlistID string, trackIDs []string) error {
	pid, ok := parseUUID(playlistID)
	if !ok {
		return apperror.NotFound("playlist not found")
	}
	ids := make([]pgtype.UUID, 0, len(trackIDs))
	for _, raw := range trackIDs {
		id, ok := parseUUID(raw)
		if !ok {
			return apperror.InvalidArgument("invalid track id")
		}
		ids = append(ids, id)
	}
	err := r.inTx(ctx, func(q *playlistdb.Queries) error {
		// L'ordre fourni doit couvrir exactement la playlist : on compare son
		// effectif au nombre de lignes réellement repositionnées (un id absent
		// de la playlist n'en touche aucune).
		total, err := q.CountPlaylistTracks(ctx, pid)
		if err != nil {
			return fmt.Errorf("repo: count playlist tracks: %w", err)
		}
		if int64(len(ids)) != total {
			return apperror.Conflict("L'ordre fourni ne correspond plus à la playlist")
		}
		updated, err := q.ReorderPlaylistTracks(ctx, playlistdb.ReorderPlaylistTracksParams{
			PlaylistID: pid,
			TrackIds:   ids,
		})
		if err != nil {
			return fmt.Errorf("repo: reorder tracks: %w", err)
		}
		if updated != total {
			return apperror.Conflict("L'ordre fourni ne correspond plus à la playlist")
		}
		return q.TouchPlaylist(ctx, pid)
	})
	// Une position en double au COMMIT signifie qu'une écriture concurrente a
	// bougé la playlist sous nos pieds : même conclusion qu'un effectif qui ne
	// correspond plus.
	if errors.Is(err, errPositionTaken) {
		return apperror.Conflict("L'ordre fourni ne correspond plus à la playlist")
	}
	return err
}

func (r *pgRepository) AddFavorite(ctx context.Context, userID, playlistID string) error {
	pid, ok := parseUUID(playlistID)
	if !ok {
		return apperror.NotFound("playlist not found")
	}
	if err := r.q.AddPlaylistFavorite(ctx, playlistdb.AddPlaylistFavoriteParams{
		UserID:     uuidParam(userID),
		PlaylistID: pid,
	}); err != nil {
		return fmt.Errorf("repo: add playlist favorite: %w", err)
	}
	return nil
}

func (r *pgRepository) RemoveFavorite(ctx context.Context, userID, playlistID string) error {
	pid, ok := parseUUID(playlistID)
	if !ok {
		return apperror.NotFound("playlist not found")
	}
	if err := r.q.RemovePlaylistFavorite(ctx, playlistdb.RemovePlaylistFavoriteParams{
		UserID:     uuidParam(userID),
		PlaylistID: pid,
	}); err != nil {
		return fmt.Errorf("repo: remove playlist favorite: %w", err)
	}
	return nil
}

// errPositionTaken signale qu'une transaction a échoué au COMMIT sur
// uq_playlist_tracks_position : deux écritures concurrentes ont visé la même
// position. Sentinelle interne — chaque appelant décide s'il rejoue (ajout) ou
// s'il remonte un conflit à l'utilisateur (réordonnancement).
var errPositionTaken = errors.New("playlist: position déjà prise")

// inTx exécute fn dans une transaction et l'annule si fn renvoie une erreur.
// Les contraintes différées (uq_playlist_tracks_position) ne sont vérifiées
// qu'au COMMIT : une violation y remonte, elle est donc traduite ici.
func (r *pgRepository) inTx(ctx context.Context, fn func(*playlistdb.Queries) error) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("repo: begin tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if err := fn(r.q.WithTx(tx)); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		if isUniqueViolation(err) {
			return errPositionTaken
		}
		return fmt.Errorf("repo: commit tx: %w", err)
	}
	return nil
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
