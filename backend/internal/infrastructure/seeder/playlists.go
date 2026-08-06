package seeder

import (
	"context"
	"fmt"

	"github.com/rs/zerolog/log"

	"github.com/jackc/pgx/v5"
)

func seedPlaylists(ctx context.Context, tx pgx.Tx) error {
	log.Info().Msg("seed playlists...")

	var user1ID string
	err := tx.QueryRow(ctx,
		"SELECT id FROM users WHERE email = $1",
		"user1@streampulse.dev",
	).Scan(&user1ID)
	if err != nil {
		return fmt.Errorf("récupération user1: %w", err)
	}

	var playlistID string
	err = tx.QueryRow(ctx, `
		INSERT INTO playlists (user_id, name, description, is_public)
		VALUES ($1, 'My Favorites', 'Ma playlist préférée', true)
		ON CONFLICT DO NOTHING
		RETURNING id
	`, user1ID).Scan(&playlistID)
	if err != nil {
		err = tx.QueryRow(ctx,
			"SELECT id FROM playlists WHERE user_id = $1 AND name = 'My Favorites'",
			user1ID,
		).Scan(&playlistID)
		if err != nil {
			return fmt.Errorf("récupération playlist: %w", err)
		}
	}
	log.Info().Str("name", "My Favorites").Msg("seed: playlist")

	// Le seed n'amorce le contenu que d'une playlist vide. Depuis US-05-03
	// l'utilisateur peut retirer et réordonner ses pistes : ré-insérer
	// aveuglément les positions 0..2 au démarrage suivant écraserait son ordre —
	// et, une piste ayant pu être retirée, réattribuerait une position déjà
	// occupée (violation de uq_playlist_tracks_position au COMMIT, migration
	// 000019). Un seed ne doit jamais réécrire des données utilisateur.
	var existingTracks int
	if err := tx.QueryRow(ctx,
		"SELECT COUNT(*) FROM playlist_tracks WHERE playlist_id = $1",
		playlistID,
	).Scan(&existingTracks); err != nil {
		return fmt.Errorf("comptage playlist_tracks: %w", err)
	}
	if existingTracks > 0 {
		log.Info().Int("count", existingTracks).Msg("seed: playlist déjà peuplée, contenu inchangé")
		return nil
	}

	// Collecter tous les IDs d'abord, puis fermer le curseur avant d'insérer
	rows, err := tx.Query(ctx,
		"SELECT id FROM tracks WHERE user_id = $1 ORDER BY created_at LIMIT 3",
		user1ID,
	)
	if err != nil {
		return fmt.Errorf("récupération tracks: %w", err)
	}

	var trackIDs []string
	for rows.Next() {
		var trackID string
		if err := rows.Scan(&trackID); err != nil {
			rows.Close()
			return fmt.Errorf("scan track: %w", err)
		}
		trackIDs = append(trackIDs, trackID)
	}
	rows.Close()

	for position, trackID := range trackIDs {
		// Arbitre explicite : depuis la migration 000019, playlist_tracks porte
		// une contrainte unique DEFERRABLE sur (playlist_id, position).
		// Un `ON CONFLICT DO NOTHING` sans colonnes force Postgres à considérer
		// toutes les contraintes uniques comme arbitres possibles, et il refuse
		// les contraintes différées dans ce rôle (SQLSTATE 55000). Nommer la PK
		// dit exactement ce que le seed veut dédupliquer.
		_, err = tx.Exec(ctx, `
			INSERT INTO playlist_tracks (playlist_id, track_id, position)
			VALUES ($1, $2, $3)
			ON CONFLICT (playlist_id, track_id) DO NOTHING
		`, playlistID, trackID, position)
		if err != nil {
			return fmt.Errorf("insert playlist_track pos %d: %w", position, err)
		}
	}
	log.Info().Int("count", len(trackIDs)).Msg("seed: tracks ajoutées à la playlist")

	return nil
}
