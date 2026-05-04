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
	defaultGoEnv   = "development"
	defaultAPIPort = "8080"
	defaultDBHost  = "localhost"
	defaultDBPort  = "5432"

	minJWTSecretLen = 32
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
	v.SetDefault("GO_ENV", defaultGoEnv)
	v.SetDefault("API_PORT", defaultAPIPort)
	v.SetDefault("DB_HOST", defaultDBHost)
	v.SetDefault("DB_PORT", defaultDBPort)

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

	// Une variable d'environnement définie à "" est sémantiquement équivalente
	// à une variable absente (12-Factor) — on retombe sur le défaut.
	// Viper ne le fait pas seul : os.Getenv retourne "" pour set vide ET pour
	// absent, et viper privilégie cette chaîne vide sur SetDefault.
	cfg.applyDefaultsForEmpty()

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

	return nil
}
