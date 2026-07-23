package migrator

import (
	"errors"
	"os"

	"github.com/rs/zerolog/log"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/pgx/v5"
	_ "github.com/golang-migrate/migrate/v4/source/file"
)

// Run applique toutes les migrations en attente.
// Utilise DATABASE_URL injecté via variable d'environnement.
func Run() {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal().Msg("DATABASE_URL non définie")
	}

	m, err := migrate.New("file://migrations", dbURL)
	if err != nil {
		log.Fatal().Err(err).Msg("migrate init")
	}
	defer func() {
		srcErr, dbErr := m.Close()
		if srcErr != nil {
			log.Warn().Err(srcErr).Msg("migrate: fermeture de la source")
		}
		if dbErr != nil {
			log.Warn().Err(dbErr).Msg("migrate: fermeture de la connexion")
		}
	}()

	if err := m.Up(); err != nil && !errors.Is(err, migrate.ErrNoChange) {
		log.Fatal().Err(err).Msg("migrate up")
	}

	log.Info().Msg("migrations appliquées avec succès")
}
