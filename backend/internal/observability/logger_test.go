package observability

import (
	"bytes"
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/rs/zerolog"

	"github.com/LignacAntony/streampulse/internal/config"
)

func testConfig(level string, pretty bool) *config.Config {
	return &config.Config{GoEnv: "test", LogLevel: level, LogPretty: pretty}
}

func TestNew_JSONStructure(t *testing.T) {
	var buf bytes.Buffer
	logger := New(testConfig("info", false), &buf)

	logger.Info().Msg("hello")

	var entry map[string]any
	if err := json.Unmarshal(buf.Bytes(), &entry); err != nil {
		t.Fatalf("sortie non-JSON: %v — got %q", err, buf.String())
	}
	for field, want := range map[string]string{
		"level":       "info",
		"message":     "hello",
		"service":     "streampulse-api",
		"environment": "test",
	} {
		if got, _ := entry[field].(string); got != want {
			t.Errorf("champ %q = %q, want %q", field, got, want)
		}
	}
	ts, _ := entry["time"].(string)
	if _, err := time.Parse(time.RFC3339, ts); err != nil {
		t.Errorf("champ time %q pas au format RFC3339: %v", ts, err)
	}
}

func TestNew_LevelFiltering(t *testing.T) {
	var buf bytes.Buffer
	logger := New(testConfig("warn", false), &buf)

	logger.Info().Msg("filtré")
	if buf.Len() != 0 {
		t.Errorf("info loggé malgré LOG_LEVEL=warn: %q", buf.String())
	}

	logger.Warn().Msg("visible")
	if !strings.Contains(buf.String(), "visible") {
		t.Errorf("warn absent de la sortie: %q", buf.String())
	}
}

func TestNew_PrettyOptIn(t *testing.T) {
	var buf bytes.Buffer
	logger := New(testConfig("info", true), &buf)

	logger.Info().Msg("pretty")

	out := strings.TrimSpace(buf.String())
	if strings.HasPrefix(out, "{") {
		t.Errorf("LOG_PRETTY=true doit produire du texte console, pas du JSON: %q", out)
	}
	if !strings.Contains(out, "pretty") {
		t.Errorf("message absent de la sortie console: %q", out)
	}
}

func TestNew_InvalidLevelFallsBackToInfo(t *testing.T) {
	// config.Load valide déjà LOG_LEVEL ; New doit rester robuste si un
	// appelant construit une Config à la main avec un niveau invalide.
	var buf bytes.Buffer
	logger := New(testConfig("bogus", false), &buf)

	logger.Info().Msg("fallback")
	if !strings.Contains(buf.String(), "fallback") {
		t.Errorf("niveau invalide doit retomber sur info, sortie: %q", buf.String())
	}
}

func TestNew_SetsDefaultContextLogger(t *testing.T) {
	var buf bytes.Buffer
	New(testConfig("info", false), &buf)
	t.Cleanup(func() { zerolog.DefaultContextLogger = nil })

	// Un contexte sans logger attaché doit retomber sur le logger racine,
	// jamais sur le logger désactivé de zerolog (logs silencieusement perdus).
	zerolog.Ctx(context.Background()).Info().Msg("hors requête")

	if !strings.Contains(buf.String(), "hors requête") {
		t.Errorf("zerolog.Ctx sans logger doit utiliser le logger racine, sortie: %q", buf.String())
	}
}
