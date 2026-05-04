package database

import (
	"context"
	"log"
	"os"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// Connect établit une connexion à PostgreSQL via DATABASE_URL.
// pgx natif attend postgres://, on remplace pgx5:// si nécessaire.
// Un timeout de 10s est appliqué pour éviter un blocage infini si Postgres est indisponible.
func Connect(ctx context.Context) *pgx.Conn {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL non définie")
	}

	dbURL = strings.Replace(dbURL, "pgx5://", "postgres://", 1)

	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	conn, err := pgx.Connect(ctx, dbURL)
	if err != nil {
		log.Fatalf("connexion base de données: %v", err)
	}

	return conn
}
