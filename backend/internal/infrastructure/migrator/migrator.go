package migrator

import (
	"errors"

	"github.com/rs/zerolog/log"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/pgx/v5"
	_ "github.com/golang-migrate/migrate/v4/source/file"
)

// Run applique toutes les migrations en attente. La DSN vient de la config
// (dérivée des DB_*), et non plus d'un DATABASE_URL lu directement dans
// l'environnement — cette variable était une seconde source de vérité que rien
// ne validait ni ne gardait synchrone avec les DB_*.
func Run(databaseURL string) {
	m, err := migrate.New("file://migrations", databaseURL)
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
