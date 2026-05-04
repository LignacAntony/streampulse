package seeder

import (
	"context"
	"errors"
	"fmt"
	"log"

	"github.com/jackc/pgx/v5"
)

// Run exécute tous les seeders dans une transaction unique.
// En cas d'erreur sur l'un d'eux, toute la transaction est rollbackée.
func Run(ctx context.Context, conn *pgx.Conn) error {
	log.Println("démarrage du seed...")

	tx, err := conn.Begin(ctx)
	if err != nil {
		return fmt.Errorf("début transaction seed: %w", err)
	}
	defer func() {
		if err := tx.Rollback(ctx); err != nil && !errors.Is(err, pgx.ErrTxClosed) {
			log.Printf("rollback seed: %v", err)
		}
	}()

	if err := seedUsers(ctx, tx); err != nil {
		return fmt.Errorf("seed users: %w", err)
	}
	if err := seedStreams(ctx, tx); err != nil {
		return fmt.Errorf("seed streams: %w", err)
	}
	if err := seedTracks(ctx, tx); err != nil {
		return fmt.Errorf("seed tracks: %w", err)
	}
	if err := seedPlaylists(ctx, tx); err != nil {
		return fmt.Errorf("seed playlists: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit seed: %w", err)
	}

	log.Println("seed terminé avec succès")
	return nil
}
