package seeder

import (
	"context"
	"fmt"
	"log"

	"github.com/jackc/pgx/v5"
)

func seedStreams(ctx context.Context, tx pgx.Tx) error {
	log.Println("seed streams...")

	var broadcasterID string
	err := tx.QueryRow(ctx,
		"SELECT id FROM users WHERE email = $1",
		"broadcaster@streampulse.dev",
	).Scan(&broadcasterID)
	if err != nil {
		return fmt.Errorf("récupération broadcaster: %w", err)
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
		_, err = tx.Exec(ctx, `
			INSERT INTO streams (user_id, title, category, status, is_public, stream_key)
			VALUES ($1, $2, $3, $4, true, replace(gen_random_uuid()::text, '-', ''))
			ON CONFLICT DO NOTHING
		`, broadcasterID, s.title, s.category, s.status)
		if err != nil {
			return fmt.Errorf("insert stream %s: %w", s.title, err)
		}
		log.Printf("  ✓ stream \"%s\" (%s)", s.title, s.status)
	}

	return nil
}
