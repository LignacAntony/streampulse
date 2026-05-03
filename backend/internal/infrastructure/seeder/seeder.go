package seeder

import (
	"context"
	"log"

	"github.com/jackc/pgx/v5"
)

func Run(ctx context.Context, conn *pgx.Conn) {
	log.Println("démarrage du seed...")

	seedUsers(ctx, conn)
	seedStreams(ctx, conn)
	seedTracks(ctx, conn)
	seedPlaylists(ctx, conn)

	log.Println("seed terminé avec succès")
}
