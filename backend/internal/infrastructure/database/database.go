package database

import (
	"context"
	"strings"
	"time"

	"github.com/rs/zerolog/log"

	"github.com/jackc/pgx/v5"
)

// Connect établit une connexion simple à PostgreSQL (seeder de développement).
// La DSN vient de la config, dérivée des DB_*. Un timeout de 10 s évite un
// blocage infini si Postgres est indisponible.
func Connect(ctx context.Context, databaseURL string) *pgx.Conn {
	dbURL := strings.Replace(databaseURL, "pgx5://", "postgres://", 1)

	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	conn, err := pgx.Connect(ctx, dbURL)
	if err != nil {
		log.Fatal().Err(err).Msg("connexion base de données")
	}

	return conn
}
