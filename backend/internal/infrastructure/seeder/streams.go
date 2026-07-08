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
		// Statut 'idle' : un flux 'live' seedé serait un orphelin sans session en
		// mémoire (terminé au boot par la réconciliation), et bloquerait la règle
		// un-seul-live. Le diffuseur peut le passer live via PATCH .../start.
		{"Morning Jazz Session", "music", "idle"},
		{"Tech Talk Live", "technology", "ended"},
		{"Chill Beats Radio", "music", "idle"},
	}

	for _, s := range streams {
		// Idempotent sans contrainte d'unicité sur le titre (retirée en 000015) :
		// on n'insère que si ce diffuseur n'a pas déjà un flux ACTIF de ce titre
		// (on ignore les lignes archivées pour garantir qu'un flux seedé existe).
		_, err = tx.Exec(ctx, `
			INSERT INTO streams (user_id, title, category, status, is_public, stream_key)
			SELECT $1, $2, $3, $4, true, replace(gen_random_uuid()::text, '-', '')
			WHERE NOT EXISTS (
				SELECT 1 FROM streams
				WHERE user_id = $1 AND title = $2 AND archived_at IS NULL
			)
		`, broadcasterID, s.title, s.category, s.status)
		if err != nil {
			return fmt.Errorf("insert stream %s: %w", s.title, err)
		}
		log.Printf("  ✓ stream \"%s\" (%s)", s.title, s.status)
	}

	return nil
}
