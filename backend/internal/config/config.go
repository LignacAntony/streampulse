// Package config charge la configuration de l'application depuis les
// variables d'environnement (méthodologie 12-Factor App).
//
// En développement, un fichier .env à la racine du repo est chargé
// automatiquement s'il est présent. En production, les variables sont
// injectées par l'orchestrateur (Docker Compose, Kubernetes, etc.).
package config

import (
	"errors"
	"fmt"
	"strings"

	"github.com/spf13/viper"
)

// Valeurs par défaut pour les variables non-sensibles. Centralisées en
// constantes pour qu'elles soient à la fois passées à viper.SetDefault
// et appliquées en post-processing si la variable est définie à "".
const (
	defaultGoEnv               = "development"
	defaultAPIPort             = "8080"
	defaultDBHost              = "localhost"
	defaultDBPort              = "5432"
	defaultStreamIngestBaseURL = "http://localhost:8080"
	defaultHLSMaxConcurrent    = 256
	defaultLogLevel            = "info"

	minJWTSecretLen = 32
)

// validLogLevels énumère les niveaux acceptés pour LOG_LEVEL
// (alignés sur zerolog.ParseLevel).
var validLogLevels = map[string]bool{
	"trace": true, "debug": true, "info": true,
	"warn": true, "error": true, "fatal": true, "panic": true,
}

// Config représente la configuration complète de l'API StreamPulse.
//
// Toutes les valeurs proviennent de variables d'environnement —
// aucune n'est codée en dur dans le code source.
type Config struct {
	GoEnv     string `mapstructure:"GO_ENV"`
	APIPort   string `mapstructure:"API_PORT"`
	JWTSecret string `mapstructure:"JWT_SECRET"`

	DBHost     string `mapstructure:"DB_HOST"`
	DBPort     string `mapstructure:"DB_PORT"`
	DBUser     string `mapstructure:"DB_USER"`
	DBPassword string `mapstructure:"DB_PASSWORD"`
	DBName     string `mapstructure:"DB_NAME"`

	// SMTP — optionnel. Si SMTPHost est vide, le LogMailer est utilisé.
	SMTPHost     string `mapstructure:"SMTP_HOST"`
	SMTPPort     string `mapstructure:"SMTP_PORT"`
	SMTPUsername string `mapstructure:"SMTP_USERNAME"`
	SMTPPassword string `mapstructure:"SMTP_PASSWORD"`
	SMTPFrom     string `mapstructure:"SMTP_FROM"`

	// AppBaseURL est utilisée pour construire les liens dans les emails.
	AppBaseURL string `mapstructure:"APP_BASE_URL"`

	// StreamIngestBaseURL préfixe l'URL de stream source renvoyée au diffuseur
	// (cf. ADR 013) : {StreamIngestBaseURL}/api/streams/ingest/{stream_key}.
	StreamIngestBaseURL string `mapstructure:"STREAM_INGEST_BASE_URL"`

	// HLSMaxConcurrent borne le nombre de requêtes HLS (playlist + segments)
	// servies simultanément — STR-88. <= 0 désactive la borne.
	HLSMaxConcurrent int `mapstructure:"HLS_MAX_CONCURRENT"`

	// CORSAllowedOrigins : origines autorisées par CORS (CSV dans CORS_ALLOWED_ORIGINS).
	CORSAllowedOrigins []string `mapstructure:"-"`

	// LogLevel : niveau minimal des logs (trace|debug|info|warn|error|fatal|panic).
	LogLevel string `mapstructure:"LOG_LEVEL"`

	// LogPretty : sortie console lisible (dev local hors Docker uniquement) —
	// en conteneur la sortie doit rester du JSON pour la collecte Loki (STR-172).
	LogPretty bool `mapstructure:"LOG_PRETTY"`
}

// Load lit la configuration depuis l'environnement et la valide.
// Retourne une erreur si une variable requise est manquante ou
// si une valeur ne respecte pas les contraintes.
func Load() (*Config, error) {
	v := viper.New()

	// Valeurs par défaut pour les variables non sensibles.
	v.SetDefault("GO_ENV", defaultGoEnv)
	v.SetDefault("API_PORT", defaultAPIPort)
	v.SetDefault("DB_HOST", defaultDBHost)
	v.SetDefault("DB_PORT", defaultDBPort)
	v.SetDefault("STREAM_INGEST_BASE_URL", defaultStreamIngestBaseURL)
	v.SetDefault("HLS_MAX_CONCURRENT", defaultHLSMaxConcurrent)
	v.SetDefault("LOG_LEVEL", defaultLogLevel)
	v.SetDefault("LOG_PRETTY", false)

	// Charge .env à la racine du repo si présent (dev local uniquement).
	v.SetConfigName(".env")
	v.SetConfigType("env")
	v.AddConfigPath(".")
	v.AddConfigPath("..")
	v.AddConfigPath("../..")
	if err := v.ReadInConfig(); err != nil {
		var notFound viper.ConfigFileNotFoundError
		if !errors.As(err, &notFound) {
			return nil, fmt.Errorf("config: read .env: %w", err)
		}
		// .env absent → on continue, c'est attendu en prod.
	}

	// Override par les variables d'environnement (priorité max).
	v.AutomaticEnv()

	// Bind explicite — viper.Unmarshal ne lit pas AutomaticEnv() seul.
	for _, key := range []string{
		"GO_ENV", "API_PORT", "JWT_SECRET",
		"DB_HOST", "DB_PORT", "DB_USER", "DB_PASSWORD", "DB_NAME",
		"SMTP_HOST", "SMTP_PORT", "SMTP_USERNAME", "SMTP_PASSWORD", "SMTP_FROM",
		"APP_BASE_URL", "CORS_ALLOWED_ORIGINS", "STREAM_INGEST_BASE_URL",
		"HLS_MAX_CONCURRENT", "LOG_LEVEL", "LOG_PRETTY",
	} {
		if err := v.BindEnv(key); err != nil {
			return nil, fmt.Errorf("config: bind %s: %w", key, err)
		}
	}

	cfg := &Config{}
	if err := v.Unmarshal(cfg); err != nil {
		return nil, fmt.Errorf("config: unmarshal: %w", err)
	}

	cfg.CORSAllowedOrigins = parseCSV(v.GetString("CORS_ALLOWED_ORIGINS"))

	// Une variable d'environnement définie à "" est sémantiquement équivalente
	// à une variable absente (12-Factor) — on retombe sur le défaut.
	// Viper ne le fait pas seul : os.Getenv retourne "" pour set vide ET pour
	// absent, et viper privilégie cette chaîne vide sur SetDefault.
	cfg.applyDefaultsForEmpty()

	// HLSMaxConcurrent est un int : le weak-decode de viper a déjà transformé
	// "" en 0 pendant l'Unmarshal ci-dessus, indiscernable d'un 0 explicite
	// (= limiteur désactivé, cf. commentaire du champ). On revérifie donc la
	// chaîne brute — via .env ou l'environnement OS — plutôt que le champ cfg
	// déjà converti : seule une chaîne vide retombe sur le défaut.
	if strings.TrimSpace(v.GetString("HLS_MAX_CONCURRENT")) == "" {
		cfg.HLSMaxConcurrent = defaultHLSMaxConcurrent
	}

	if err := cfg.validate(); err != nil {
		return nil, err
	}

	return cfg, nil
}

// applyDefaultsForEmpty remplace les valeurs vides par les défauts
// pour les champs qui en ont un. Les champs requis (DB_USER, DB_NAME, etc.)
// restent vides volontairement et seront remontés par validate().
func (c *Config) applyDefaultsForEmpty() {
	if c.GoEnv == "" {
		c.GoEnv = defaultGoEnv
	}
	if c.APIPort == "" {
		c.APIPort = defaultAPIPort
	}
	if c.DBHost == "" {
		c.DBHost = defaultDBHost
	}
	if c.DBPort == "" {
		c.DBPort = defaultDBPort
	}
	if c.SMTPPort == "" {
		c.SMTPPort = "587"
	}
	if c.StreamIngestBaseURL == "" {
		c.StreamIngestBaseURL = defaultStreamIngestBaseURL
	}
	c.LogLevel = strings.ToLower(strings.TrimSpace(c.LogLevel))
	if c.LogLevel == "" {
		c.LogLevel = defaultLogLevel
	}
}

// parseCSV découpe une liste CSV en ignorant espaces et entrées vides.
func parseCSV(raw string) []string {
	var out []string
	for _, part := range strings.Split(raw, ",") {
		if v := strings.TrimSpace(part); v != "" {
			out = append(out, v)
		}
	}
	return out
}

// IsDev indique si l'application tourne en mode développement.
func (c *Config) IsDev() bool {
	return strings.EqualFold(c.GoEnv, "development") || strings.EqualFold(c.GoEnv, "dev")
}

// IsProd indique si l'application tourne en mode production.
func (c *Config) IsProd() bool {
	return strings.EqualFold(c.GoEnv, "production") || strings.EqualFold(c.GoEnv, "prod")
}

// HTTPAddr retourne l'adresse d'écoute HTTP au format ":port".
func (c *Config) HTTPAddr() string {
	return ":" + c.APIPort
}

// DBDSN retourne la DSN PostgreSQL prête à passer à database/sql ou pgx.
func (c *Config) DBDSN() string {
	return fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		c.DBHost, c.DBPort, c.DBUser, c.DBPassword, c.DBName,
	)
}

// validate vérifie que les variables requises sont présentes et que
// les valeurs critiques respectent les contraintes minimales.
func (c *Config) validate() error {
	var missing []string
	required := map[string]string{
		"JWT_SECRET":  c.JWTSecret,
		"DB_USER":     c.DBUser,
		"DB_PASSWORD": c.DBPassword,
		"DB_NAME":     c.DBName,
	}
	for name, val := range required {
		if strings.TrimSpace(val) == "" {
			missing = append(missing, name)
		}
	}
	if len(missing) > 0 {
		return fmt.Errorf("config: missing required env vars: %s", strings.Join(missing, ", "))
	}

	if len(c.JWTSecret) < minJWTSecretLen {
		return fmt.Errorf("config: JWT_SECRET must be at least %d characters", minJWTSecretLen)
	}

	if !validLogLevels[c.LogLevel] {
		return fmt.Errorf("config: LOG_LEVEL invalide %q (attendu: trace|debug|info|warn|error|fatal|panic)", c.LogLevel)
	}

	return nil
}
