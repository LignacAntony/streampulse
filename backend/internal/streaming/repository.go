package streaming

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
	streamingdb "github.com/LignacAntony/streampulse/internal/streaming/db"
)

// errNoRowAffected signale qu'aucune ligne n'a été mise à jour par une transition
// de statut (le service classe alors 404 vs 409 via un GetByID).
var errNoRowAffected = errors.New("streaming: no row affected")

// errStreamAlreadyLive signale que la garde d'unicité « un seul live par diffuseur »
// a rejeté un start (index unique partiel, 23505) → 409.
var errStreamAlreadyLive = errors.New("streaming: broadcaster already has a live stream")

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

func (r *pgRepository) ListPublicLive(ctx context.Context, f ListFilter) ([]Stream, error) {
	rows, err := r.q.ListPublicLiveStreams(ctx, streamingdb.ListPublicLiveStreamsParams{
		Lim:      f.Limit,
		Off:      f.Offset,
		Category: textFilter(f.Category),
		Search:   searchPattern(f.Search),
	})
	if err != nil {
		return nil, fmt.Errorf("repo: list public live streams: %w", err)
	}

	streams := make([]Stream, 0, len(rows))
	for _, row := range rows {
		streams = append(streams, Stream{
			ID:                  row.ID,
			UserID:              row.UserID,
			Title:               row.Title,
			Description:         textValue(row.Description),
			Category:            textValue(row.Category),
			Status:              row.Status,
			IsPublic:            row.IsPublic,
			StartedAt:           row.StartedAt,
			EndedAt:             row.EndedAt,
			CreatedAt:           row.CreatedAt,
			UpdatedAt:           row.UpdatedAt,
			BroadcasterUsername: row.BroadcasterUsername,
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
	return fullStream(row.ID, row.UserID, row.Title, row.Description, row.Category,
		row.Status, row.IsPublic, row.StreamKey, row.StartedAt, row.EndedAt, row.CreatedAt, row.UpdatedAt), nil
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
	return fullStream(row.ID, row.UserID, row.Title, row.Description, row.Category,
		row.Status, row.IsPublic, row.StreamKey, row.StartedAt, row.EndedAt, row.CreatedAt, row.UpdatedAt), nil
}

func (r *pgRepository) Archive(ctx context.Context, id, userID string) (string, error) {
	uid, ok := parseUUID(id)
	if !ok {
		return "", apperror.NotFound("stream not found")
	}
	archivedID, err := r.q.ArchiveStream(ctx, streamingdb.ArchiveStreamParams{
		ID:     uid,
		UserID: uuidParam(userID),
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", apperror.NotFound("stream not found")
		}
		return "", fmt.Errorf("repo: archive stream: %w", err)
	}
	return archivedID, nil
}

func (r *pgRepository) StartStream(ctx context.Context, id, userID string) (Stream, error) {
	uid, ok := parseUUID(id)
	if !ok {
		return Stream{}, errNoRowAffected
	}
	row, err := r.q.StartStream(ctx, streamingdb.StartStreamParams{ID: uid, UserID: uuidParam(userID)})
	if err != nil {
		if isUniqueViolation(err) {
			// L'index unique partiel a rejeté un 2e live concurrent (write-skew).
			return Stream{}, errStreamAlreadyLive
		}
		if errors.Is(err, pgx.ErrNoRows) {
			return Stream{}, errNoRowAffected
		}
		return Stream{}, fmt.Errorf("repo: start stream: %w", err)
	}
	return fullStream(row.ID, row.UserID, row.Title, row.Description, row.Category,
		row.Status, row.IsPublic, row.StreamKey, row.StartedAt, row.EndedAt, row.CreatedAt, row.UpdatedAt), nil
}

func (r *pgRepository) StopStream(ctx context.Context, id, userID string) (Stream, error) {
	uid, ok := parseUUID(id)
	if !ok {
		return Stream{}, errNoRowAffected
	}
	row, err := r.q.StopStream(ctx, streamingdb.StopStreamParams{ID: uid, UserID: uuidParam(userID)})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Stream{}, errNoRowAffected
		}
		return Stream{}, fmt.Errorf("repo: stop stream: %w", err)
	}
	return fullStream(row.ID, row.UserID, row.Title, row.Description, row.Category,
		row.Status, row.IsPublic, row.StreamKey, row.StartedAt, row.EndedAt, row.CreatedAt, row.UpdatedAt), nil
}

// RotateStreamKey remplace le secret d'ingest par newKey. errNoRowAffected si le
// flux est absent/archivé/pas au demandeur, ou s'il est en direct (cf. la query).
//
// Une collision sur uq_streams_stream_key n'est pas traitée à part, comme dans
// Create : deux clés de 32 octets tirées d'un CSPRNG ne se rencontrent pas, et
// si cela arrivait ce serait un incident interne, pas une erreur utilisateur.
func (r *pgRepository) RotateStreamKey(ctx context.Context, id, userID, newKey string) (Stream, error) {
	uid, ok := parseUUID(id)
	if !ok {
		return Stream{}, errNoRowAffected
	}
	row, err := r.q.RotateStreamKey(ctx, streamingdb.RotateStreamKeyParams{
		StreamKey: newKey,
		ID:        uid,
		UserID:    uuidParam(userID),
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Stream{}, errNoRowAffected
		}
		return Stream{}, fmt.Errorf("repo: rotate stream key: %w", err)
	}
	return fullStream(row.ID, row.UserID, row.Title, row.Description, row.Category,
		row.Status, row.IsPublic, row.StreamKey, row.StartedAt, row.EndedAt, row.CreatedAt, row.UpdatedAt), nil
}

// EndOrphanLiveStreams termine les flux restés 'live' en base sans session active
// (réconciliation au démarrage après un redémarrage du process).
func (r *pgRepository) EndOrphanLiveStreams(ctx context.Context) (int64, error) {
	n, err := r.q.EndOrphanLiveStreams(ctx)
	if err != nil {
		return 0, fmt.Errorf("repo: end orphan live streams: %w", err)
	}
	return n, nil
}

// AddFavorite ajoute le flux aux favoris de l'utilisateur (idempotent via
// ON CONFLICT DO NOTHING). La visibilité du flux est déjà vérifiée par le
// service (GetStream) en amont ; la contrainte FK protège d'une insertion
// orpheline en cas de course (flux supprimé entre-temps → NotFound).
func (r *pgRepository) AddFavorite(ctx context.Context, userID, streamID string) error {
	sid, ok := parseUUID(streamID)
	if !ok {
		return apperror.NotFound("stream not found")
	}
	err := r.q.AddFavorite(ctx, streamingdb.AddFavoriteParams{
		UserID:   uuidParam(userID),
		StreamID: sid,
	})
	if err != nil {
		if isForeignKeyViolation(err) {
			return apperror.NotFound("stream not found")
		}
		return fmt.Errorf("repo: add favorite: %w", err)
	}
	return nil
}

// RemoveFavorite retire le flux des favoris (idempotent : aucun effet si absent
// ou si l'id est mal formé).
func (r *pgRepository) RemoveFavorite(ctx context.Context, userID, streamID string) error {
	sid, ok := parseUUID(streamID)
	if !ok {
		return nil
	}
	if err := r.q.RemoveFavorite(ctx, streamingdb.RemoveFavoriteParams{
		UserID:   uuidParam(userID),
		StreamID: sid,
	}); err != nil {
		return fmt.Errorf("repo: remove favorite: %w", err)
	}
	return nil
}

// ListFavorites retourne les flux favoris de l'utilisateur, encore visibles et
// non archivés, triés par date d'ajout décroissante (sans stream_key).
func (r *pgRepository) ListFavorites(ctx context.Context, userID string) ([]Stream, error) {
	rows, err := r.q.ListFavoritesByUser(ctx, uuidParam(userID))
	if err != nil {
		return nil, fmt.Errorf("repo: list favorites: %w", err)
	}
	streams := make([]Stream, 0, len(rows))
	for _, row := range rows {
		streams = append(streams, Stream{
			ID:                  row.ID,
			UserID:              row.UserID,
			Title:               row.Title,
			Description:         textValue(row.Description),
			Category:            textValue(row.Category),
			Status:              row.Status,
			IsPublic:            row.IsPublic,
			StartedAt:           row.StartedAt,
			EndedAt:             row.EndedAt,
			CreatedAt:           row.CreatedAt,
			UpdatedAt:           row.UpdatedAt,
			BroadcasterUsername: row.BroadcasterUsername,
		})
	}
	return streams, nil
}

// ListByOwner retourne les flux d'un diffuseur, tous statuts, non archivés,
// AVEC leur stream_key : la requête filtre sur user_id, l'appelant est donc le
// propriétaire par construction (STR-153).
//
// Un userID syntaxiquement invalide ne peut par construction posséder aucun
// flux : traité comme « aucun résultat » plutôt qu'en paniquant (même choix que
// StopLiveStreamsByUser — le sub d'un JWT n'est pas une donnée de confiance).
func (r *pgRepository) ListByOwner(ctx context.Context, userID string) ([]Stream, error) {
	uid, ok := parseUUID(userID)
	if !ok {
		return []Stream{}, nil
	}
	rows, err := r.q.ListStreamsByOwner(ctx, uid)
	if err != nil {
		return nil, fmt.Errorf("repo: list streams by owner: %w", err)
	}
	streams := make([]Stream, 0, len(rows))
	for _, row := range rows {
		streams = append(streams, fullStream(row.ID, row.UserID, row.Title, row.Description,
			row.Category, row.Status, row.IsPublic, row.StreamKey, row.StartedAt, row.EndedAt,
			row.CreatedAt, row.UpdatedAt))
	}
	return streams, nil
}

// StopLiveStreamsByUser termine tous les flux live d'un utilisateur (usage admin,
// STR-191) et renvoie les ids arrêtés (pour que le service coupe leur session
// in-memory). Un userID syntaxiquement invalide n'a par construction aucun flux
// live associé : traité comme "aucun flux à arrêter" plutôt qu'une erreur.
func (r *pgRepository) StopLiveStreamsByUser(ctx context.Context, userID string) ([]string, error) {
	uid, ok := parseUUID(userID)
	if !ok {
		return []string{}, nil
	}
	rows, err := r.q.StopLiveStreamsByUser(ctx, uid)
	if err != nil {
		return nil, fmt.Errorf("repo: stop live streams by user: %w", err)
	}
	ids := make([]string, 0, len(rows))
	for _, row := range rows {
		ids = append(ids, row.String())
	}
	return ids, nil
}

// ForceStopLiveStream termine un flux live sans contrôle de propriétaire (usage
// admin, STR-192) et renvoie son id (pour que le service coupe sa session
// in-memory). 0 ligne affectée (absent/archivé/pas live) -> errNoRowAffected,
// même pattern que StopStream.
func (r *pgRepository) ForceStopLiveStream(ctx context.Context, id string) (string, error) {
	uid, ok := parseUUID(id)
	if !ok {
		return "", errNoRowAffected
	}
	gotID, err := r.q.ForceStopLiveStream(ctx, uid)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", errNoRowAffected
		}
		return "", fmt.Errorf("repo: force stop live stream: %w", err)
	}
	return gotID, nil
}

// fullStream construit une entité Stream à partir des colonnes complètes d'une
// ligne (mapping partagé par GetByID/Update/StartStream/StopStream).
func fullStream(id, userID, title string, description, category pgtype.Text, status string, isPublic bool, streamKey string, startedAt, endedAt *time.Time, createdAt, updatedAt time.Time) Stream {
	return Stream{
		ID:          id,
		UserID:      userID,
		Title:       title,
		Description: textValue(description),
		Category:    textValue(category),
		Status:      status,
		IsPublic:    isPublic,
		StreamKey:   streamKey,
		StartedAt:   startedAt,
		EndedAt:     endedAt,
		CreatedAt:   createdAt,
		UpdatedAt:   updatedAt,
	}
}

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

// textFilter rend un pgtype.Text NULL pour une chaîne vide : côté SQL, un filtre
// NULL est inactif (`narg IS NULL OR …`).
func textFilter(s string) pgtype.Text {
	if s == "" {
		return pgtype.Text{}
	}
	return pgtype.Text{String: s, Valid: true}
}

// searchPattern transforme un terme de recherche en motif ILIKE `%terme%`, en
// échappant d'abord les métacaractères LIKE (`\`, `%`, `_`) pour qu'ils soient
// pris au pied de la lettre — sans quoi un `%` tapé par l'utilisateur matcherait
// n'importe quoi. Terme vide => filtre inactif (NULL). L'antislash reste le
// caractère d'échappement par défaut de LIKE dans PostgreSQL.
func searchPattern(s string) pgtype.Text {
	if s == "" {
		return pgtype.Text{}
	}
	replacer := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`)
	return pgtype.Text{String: "%" + replacer.Replace(s) + "%", Valid: true}
}

func createStreamError(err error) error {
	if isForeignKeyViolation(err) {
		return apperror.Unauthorized("invalid user")
	}
	return fmt.Errorf("repo: create stream: %w", err)
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
