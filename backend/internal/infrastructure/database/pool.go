package database

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/exaring/otelpgx"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/LignacAntony/streampulse/internal/config"
)

const (
	poolMaxConns       = 10
	poolMinConns       = 2
	poolMaxConnLife    = 30 * time.Minute
	poolMaxConnIdle    = 5 * time.Minute
	poolHealthCheck    = 1 * time.Minute
	poolPingTimeoutSec = 10

	// statementTimeout borne chaque requête SQL côté serveur. Large devant les
	// requêtes du projet (toutes indexées, paginées) et étroit devant le
	// ReadTimeout HTTP : une requête qui l'atteint est un défaut, pas une
	// lenteur normale.
	statementTimeout = 5 * time.Second
)

// NewPool ouvre un *pgxpool.Pool prêt à servir les requêtes HTTP.
// La DSN provient de config.DBDSN() — source unique, dérivée des DB_*.
func NewPool(ctx context.Context, cfg *config.Config) (*pgxpool.Pool, error) {
	dsn := cfg.DBDSN()

	poolCfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("pool: parse config: %w", err)
	}

	poolCfg.MaxConns = poolMaxConns
	poolCfg.MinConns = poolMinConns
	poolCfg.MaxConnLifetime = poolMaxConnLife
	poolCfg.MaxConnIdleTime = poolMaxConnIdle
	poolCfg.HealthCheckPeriod = poolHealthCheck

	// Borne côté serveur la durée d'une requête. Aucun repository ne pose de
	// context.WithTimeout : une requête pathologique bloquerait sa connexion
	// jusqu'à ce que le client abandonne, et le pool se viderait sous charge.
	// PostgreSQL annule lui-même au-delà, et pgx remonte l'erreur normalement.
	poolCfg.ConnConfig.RuntimeParams["statement_timeout"] = strconv.Itoa(int(statementTimeout.Milliseconds()))

	// Un span par requête SQL, enfant du span HTTP via le ctx (STR-164,
	// ADR 020). Sans TracerProvider global (OTEL désactivé), coût quasi nul.
	// Le texte SQL est tracé sans ses arguments (queries sqlc paramétrées).
	poolCfg.ConnConfig.Tracer = otelpgx.NewTracer()

	pool, err := pgxpool.NewWithConfig(ctx, poolCfg)
	if err != nil {
		return nil, fmt.Errorf("pool: open: %w", err)
	}

	pingCtx, cancel := context.WithTimeout(ctx, poolPingTimeoutSec*time.Second)
	defer cancel()
	if err := pool.Ping(pingCtx); err != nil {
		pool.Close()
		// Masque le mot de passe dans le message d'erreur si présent.
		return nil, fmt.Errorf("pool: ping: %w", redactDSN(err))
	}

	return pool, nil
}

// redactDSN remplace une éventuelle valeur "password=..." dans le message
// d'erreur par "password=***" pour éviter les fuites en logs.
func redactDSN(err error) error {
	msg := err.Error()
	if idx := strings.Index(msg, "password="); idx >= 0 {
		end := strings.IndexAny(msg[idx:], " \"")
		if end == -1 {
			end = len(msg) - idx
		}
		msg = msg[:idx] + "password=***" + msg[idx+end:]
	}
	return fmt.Errorf("%s", msg)
}
