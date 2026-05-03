package seeder

import (
	"context"
	"fmt"
	"log"

	"github.com/jackc/pgx/v5"
)

func seedTracks(ctx context.Context, conn *pgx.Conn) {
	log.Println("seed tracks...")

	var user1ID string
	err := conn.QueryRow(ctx,
		"SELECT id FROM users WHERE email = $1",
		"user1@streampulse.dev",
	).Scan(&user1ID)
	if err != nil {
		log.Fatalf("récupération user1: %v", err)
	}

	tracks := []struct {
		title    string
		artist   string
		duration int
	}{
		{"Midnight Drive", "Neon Lights", 214},
		{"Ocean Waves", "Chill Collective", 187},
		{"Urban Jungle", "Street Beats", 253},
		{"Solar Wind", "Astro Sound", 198},
		{"Deep Focus", "Lo-Fi Lab", 320},
	}

	for _, t := range tracks {
		_, err = conn.Exec(ctx, `
			INSERT INTO tracks (user_id, title, artist, duration_s, file_path, mime_type, file_size)
			VALUES ($1, $2, $3, $4, $5, 'audio/mpeg', 1048576)
			ON CONFLICT DO NOTHING
		`, user1ID, t.title, t.artist, t.duration,
			fmt.Sprintf("/uploads/%s.mp3", t.title))
		if err != nil {
			log.Fatalf("insert track %s: %v", t.title, err)
		}
		log.Printf("  ✓ track \"%s\" — %s", t.title, t.artist)
	}
}
