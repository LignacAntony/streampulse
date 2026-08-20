package database

import (
	"context"
	"time"

	"github.com/rs/zerolog/log"

	"github.com/jackc/pgx/v5"
)

// Connect établit une connexion simple à PostgreSQL (seeder de développement).
// La DSN vient de la config, dérivée des DB_*. Un timeout de 10 s évite un
// blocage infini si Postgres est indisponible.
//
// databaseURL doit porter un schéma que pgx accepte — « postgres:// » ou
// « postgresql:// ». C'est ce que rend cfg.DatabaseURL(), seul appelant.
// L'URL de migration (cfg.MigrationURL(), en « pgx5:// ») ne convient pas ici :
// ce schéma est un nom de pilote golang-migrate, que pgx rejette.
//
// Cette fonction réécrivait auparavant « pgx5:// » en « postgres:// ». La
// substitution est retirée : depuis la séparation des deux URL, aucun appelant
// ne peut plus lui passer de « pgx5:// », et la garder laissait croire le
// contraire.
func Connect(ctx context.Context, databaseURL string) *pgx.Conn {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	conn, err := pgx.Connect(ctx, databaseURL)
	if err != nil {
		log.Fatal().Err(err).Msg("connexion base de données")
	}

	return conn
}
