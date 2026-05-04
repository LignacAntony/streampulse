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
}

// Load lit la configuration depuis l'environnement et la valide.
// Retourne une erreur si une variable requise est manquante ou
// si une valeur ne respecte pas les contraintes.
func Load() (*Config, error) {
	v := viper.New()

	// Valeurs par défaut pour les variables non sensibles.
	v.SetDefault("GO_ENV", "development")
	v.SetDefault("API_PORT", "8080")
	v.SetDefault("DB_HOST", "localhost")
	v.SetDefault("DB_PORT", "5432")

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
	} {
		if err := v.BindEnv(key); err != nil {
			return nil, fmt.Errorf("config: bind %s: %w", key, err)
		}
	}

	cfg := &Config{}
	if err := v.Unmarshal(cfg); err != nil {
		return nil, fmt.Errorf("config: unmarshal: %w", err)
	}

	if err := cfg.validate(); err != nil {
		return nil, err
	}

	return cfg, nil
}

// MustLoad est l'équivalent de Load mais panique en cas d'erreur.
// Pratique pour le bootstrap d'une application — fail-fast au démarrage.
func MustLoad() *Config {
	cfg, err := Load()
	if err != nil {
		panic(fmt.Errorf("config: load failed: %w", err))
	}
	return cfg
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

const minJWTSecretLen = 32

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

	return nil
}
