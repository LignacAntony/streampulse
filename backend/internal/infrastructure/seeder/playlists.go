package seeder

import (
	"context"
	"log"

	"github.com/jackc/pgx/v5"
)

func seedPlaylists(ctx context.Context, conn *pgx.Conn) {
	log.Println("seed playlists...")

	var user1ID string
	err := conn.QueryRow(ctx,
		"SELECT id FROM users WHERE email = $1",
		"user1@streampulse.dev",
	).Scan(&user1ID)
	if err != nil {
		log.Fatalf("récupération user1: %v", err)
	}

	var playlistID string
	err = conn.QueryRow(ctx, `
		INSERT INTO playlists (user_id, name, description, is_public)
		VALUES ($1, 'My Favorites', 'Ma playlist préférée', true)
		ON CONFLICT DO NOTHING
		RETURNING id
	`, user1ID).Scan(&playlistID)
	if err != nil {
		err = conn.QueryRow(ctx,
			"SELECT id FROM playlists WHERE user_id = $1 AND name = 'My Favorites'",
			user1ID,
		).Scan(&playlistID)
		if err != nil {
			log.Fatalf("récupération playlist: %v", err)
		}
	}
	log.Println("  ✓ playlist \"My Favorites\"")

	// Collecter tous les IDs d'abord, puis fermer le curseur avant d'insérer
	rows, err := conn.Query(ctx,
		"SELECT id FROM tracks WHERE user_id = $1 ORDER BY created_at LIMIT 3",
		user1ID,
	)
	if err != nil {
		log.Fatalf("récupération tracks: %v", err)
	}

	var trackIDs []string
	for rows.Next() {
		var trackID string
		if err := rows.Scan(&trackID); err != nil {
			log.Fatalf("scan track: %v", err)
		}
		trackIDs = append(trackIDs, trackID)
	}
	rows.Close()

	// Insérer une fois le curseur fermé
	for position, trackID := range trackIDs {
		_, err = conn.Exec(ctx, `
			INSERT INTO playlist_tracks (playlist_id, track_id, position)
			VALUES ($1, $2, $3)
			ON CONFLICT DO NOTHING
		`, playlistID, trackID, position)
		if err != nil {
			log.Fatalf("insert playlist_track: %v", err)
		}
	}
	log.Printf("  ✓ %d tracks ajoutées à la playlist", len(trackIDs))
}
