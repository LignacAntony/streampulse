// Package observability fournit les fondations de supervision de l'API :
// logs structurés JSON (STR-163), et à terme métriques et traces
// (STR-164/165). Décisions détaillées dans l'ADR 018.
package observability

import (
	"io"

	"github.com/rs/zerolog"

	"github.com/LignacAntony/streampulse/internal/config"
)

// serviceName identifie l'émetteur dans chaque ligne de log — requêtable
// dans Loki via le champ `service`.
const serviceName = "streampulse-api"

// New construit le logger racine de l'application : JSON par défaut
// (collecte Loki via Alloy), sortie console lisible si cfg.LogPretty
// (réservé au `go run` local hors Docker). Le niveau vient de
// cfg.LogLevel ; un niveau invalide retombe silencieusement sur info,
// config.Load ayant déjà rejeté les valeurs inconnues.
func New(cfg *config.Config, w io.Writer) zerolog.Logger {
	// RFC3339 milliseconde — indexable par Loki, lisible par un humain.
	zerolog.TimeFieldFormat = "2006-01-02T15:04:05.000Z07:00"

	level, err := zerolog.ParseLevel(cfg.LogLevel)
	if err != nil || level == zerolog.NoLevel {
		level = zerolog.InfoLevel
	}

	if cfg.LogPretty {
		w = zerolog.ConsoleWriter{Out: w}
	}

	logger := zerolog.New(w).
		Level(level).
		With().
		Timestamp().
		Str("service", serviceName).
		Str("environment", cfg.GoEnv).
		Logger()

	// zerolog.Ctx sur un context sans logger retournerait sinon le logger
	// désactivé — un call site hors requête HTTP perdrait ses logs en silence.
	zerolog.DefaultContextLogger = &logger

	return logger
}
