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
		_, err = tx.Exec(ctx, `
			INSERT INTO playlist_tracks (playlist_id, track_id, position)
			VALUES ($1, $2, $3)
			ON CONFLICT DO NOTHING
		`, playlistID, trackID, position)
		if err != nil {
			return fmt.Errorf("insert playlist_track pos %d: %w", position, err)
		}
	}
	log.Info().Int("count", len(trackIDs)).Msg("seed: tracks ajoutées à la playlist")

	return nil
}
