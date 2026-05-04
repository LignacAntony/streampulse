package seeder

import (
	"context"
	"errors"
	"log"

	"github.com/jackc/pgx/v5"
)

// Run exécute tous les seeders dans une transaction unique.
// En cas d'erreur sur l'un d'eux, toute la transaction est rollbackée.
func Run(ctx context.Context, conn *pgx.Conn) {
	log.Println("démarrage du seed...")

	tx, err := conn.Begin(ctx)
	if err != nil {
		log.Fatalf("début transaction seed: %v", err)
	}
	defer func() {
		if err := tx.Rollback(ctx); err != nil && !errors.Is(err, pgx.ErrTxClosed) {
			log.Printf("rollback seed: %v", err)
		}
	}()

	if err := seedUsers(ctx, tx); err != nil {
		log.Fatalf("seed users: %v", err)
	}
	if err := seedStreams(ctx, tx); err != nil {
		log.Fatalf("seed streams: %v", err)
	}
	if err := seedTracks(ctx, tx); err != nil {
		log.Fatalf("seed tracks: %v", err)
	}
	if err := seedPlaylists(ctx, tx); err != nil {
		log.Fatalf("seed playlists: %v", err)
	}

	if err := tx.Commit(ctx); err != nil {
		log.Fatalf("commit seed: %v", err)
	}

	log.Println("seed terminé avec succès")
}
