package seeder

import (
	"context"
	"log"

	"github.com/jackc/pgx/v5"
)

func seedStreams(ctx context.Context, conn *pgx.Conn) {
	log.Println("seed streams...")

	var broadcasterID string
	err := conn.QueryRow(ctx,
		"SELECT id FROM users WHERE email = $1",
		"broadcaster@streampulse.dev",
	).Scan(&broadcasterID)
	if err != nil {
		log.Fatalf("récupération broadcaster: %v", err)
	}

	streams := []struct {
		title    string
		category string
		status   string
	}{
		{"Morning Jazz Session", "music", "live"},
		{"Tech Talk Live", "technology", "ended"},
		{"Chill Beats Radio", "music", "idle"},
	}

	for _, s := range streams {
		_, err = conn.Exec(ctx, `
			INSERT INTO streams (user_id, title, category, status, is_public)
			VALUES ($1, $2, $3, $4, true)
			ON CONFLICT DO NOTHING
		`, broadcasterID, s.title, s.category, s.status)
		if err != nil {
			log.Fatalf("insert stream %s: %v", s.title, err)
		}
		log.Printf("  ✓ stream \"%s\" (%s)", s.title, s.status)
	}
}
