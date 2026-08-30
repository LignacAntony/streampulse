package recommendation

import (
	"context"
	"fmt"
	"math"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	recommendationdb "github.com/LignacAntony/streampulse/internal/recommendation/db"
)

type pgRepository struct {
	q *recommendationdb.Queries
}

// NewRepository construit le repository PostgreSQL du domaine recommendation.
func NewRepository(pool *pgxpool.Pool) Repository {
	return &pgRepository{q: recommendationdb.New(pool)}
}

func (r *pgRepository) RecordPlay(ctx context.Context, userID, trackID string) error {
	uid, ok := parseUUID(userID)
	if !ok {
		return fmt.Errorf("repo: record play: invalid user id %q", userID)
	}
	tid, ok := parseUUID(trackID)
	if !ok {
		return fmt.Errorf("repo: record play: invalid track id %q", trackID)
	}
	if err := r.q.RecordPlay(ctx, recommendationdb.RecordPlayParams{
		UserID:  uid,
		TrackID: tid,
	}); err != nil {
		return fmt.Errorf("repo: record play: %w", err)
	}
	return nil
}

func (r *pgRepository) Recommend(ctx context.Context, userID string, limit int) ([]ScoredTrack, error) {
	uid, ok := parseUUID(userID)
	if !ok {
		return nil, fmt.Errorf("repo: recommend: invalid user id %q", userID)
	}
	rows, err := r.q.RecommendTracks(ctx, recommendationdb.RecommendTracksParams{
		UserID: uid,
		Lim:    int32Limit(limit),
	})
	if err != nil {
		return nil, fmt.Errorf("repo: recommend: %w", err)
	}
	out := make([]ScoredTrack, 0, len(rows))
	for _, row := range rows {
		out = append(out, ScoredTrack{
			ID:          row.ID,
			Title:       row.Title,
			Artist:      textValue(row.Artist),
			DurationS:   int4Value(row.DurationS),
			ArtistPlays: row.ArtistPlays,
			NeverPlayed: row.NeverPlayed,
			FromOthers:  row.FromOthers,
		})
	}
	return out, nil
}

// parseUUID convertit un identifiant sans paniquer : un id invalide n'est pas une
// erreur serveur mais une entrée à rejeter (l'enregistrement d'écoute est
// best-effort, il ne doit jamais crasher la lecture).
func parseUUID(s string) (pgtype.UUID, bool) {
	var u pgtype.UUID
	if err := u.Scan(s); err != nil {
		return u, false
	}
	return u, true
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

// int32Limit borne la limite dans l'intervalle d'un int4 positif (la colonne SQL
// est un int). La valeur vient du service (constante), ce garde-fou couvre le cas
// théorique d'un débordement.
func int32Limit(limit int) int32 {
	if limit <= 0 {
		return 0
	}
	if limit > math.MaxInt32 {
		return math.MaxInt32
	}
	return int32(limit)
}
