package database

import (
	"context"
	"log"
	"os"
	"strings"

	"github.com/jackc/pgx/v5"
)

// Connect établit une connexion à PostgreSQL via DATABASE_URL.
// pgx natif attend postgres://, on remplace pgx5:// si nécessaire.
func Connect(ctx context.Context) *pgx.Conn {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL non définie")
	}

	dbURL = strings.Replace(dbURL, "pgx5://", "postgres://", 1)

	conn, err := pgx.Connect(ctx, dbURL)
	if err != nil {
		log.Fatalf("connexion base de données: %v", err)
	}

	return conn
}
