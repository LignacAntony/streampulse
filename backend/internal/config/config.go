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
	"net"
	"net/url"
	"strings"
	"time"

	"github.com/spf13/viper"
)

// Valeurs par défaut pour les variables non-sensibles. Centralisées en
// constantes pour qu'elles soient à la fois passées à viper.SetDefault
// et appliquées en post-processing si la variable est définie à "".
const (
	defaultGoEnv                       = "development"
	defaultAPIPort                     = "8080"
	defaultDBHost                      = "localhost"
	defaultDBPort                      = "5432"
	defaultDBSSLMode                   = "disable"
	defaultStreamIngestBaseURL         = "http://localhost:8080"
	defaultStoragePath                 = "./data/tracks"
	defaultHLSMaxConcurrent            = 256
	defaultIngestReconnectGraceSeconds = 45
	defaultIngestStopTimeoutSeconds    = 10
	defaultLogLevel                    = "info"

	// Timeouts du serveur HTTP. Les chemins longs (ingest, SSE) ne s'en
	// remettent pas à ces valeurs : ils neutralisent la write deadline et
	// renouvellent la read deadline à chaque bloc (cf. streaming/handler.go).
	defaultHTTPReadTimeoutSeconds  = 5
	defaultHTTPWriteTimeoutSeconds = 10
	defaultHTTPIdleTimeoutSeconds  = 120

	minJWTSecretLen = 32

	// mobileMaxReconnectBackoffSeconds reprend le plafond du backoff de
	// reconnexion du mobile (cappedExponentialBackoff, ADR 027 §3). Le bail
	// d'ingest doit le dépasser, sinon le serveur couperait les directs pendant
	// la fenêtre de reprise normale du téléphone.
	mobileMaxReconnectBackoffSeconds = 30
)

// validLogLevels énumère les niveaux acceptés pour LOG_LEVEL
// (alignés sur zerolog.ParseLevel).
var validLogLevels = map[string]bool{
	"trace": true, "debug": true, "info": true,
	"warn": true, "error": true, "fatal": true, "panic": true,
}

// envKeys énumère les variables d'environnement lues par Load, avec leur valeur
// par défaut quand elles en ont une. Table unique et non deux listes parallèles :
// une clé oubliée d'un côté diverge en silence.
//
// Le bind est nécessaire parce que viper.Unmarshal n'itère que sur les clés
// qu'il connaît — AutomaticEnv() ne suffit pas à en révéler une. Une clé devient
// connue par SetDefault *ou* par BindEnv ; les clés sans défaut (secrets, SMTP,
// endpoints) ne dépendent donc que de cette table. On lie toutes les clés, avec
// ou sans défaut, pour n'avoir jamais à se demander laquelle des deux voies
// couvre quel champ.
//
// TestEnvKeys_CouvrentTousLesChampsDeConfig la garde alignée sur les tags
// mapstructure de Config.
//
// CORS_ALLOWED_ORIGINS y figure alors que le champ porte `mapstructure:"-"` :
// il est lu à part via v.GetString puis découpé (parseCSV).
var envKeys = []struct {
	key string
	def any // nil = pas de défaut (valeur requise, ou vide acceptée)
}{
	{key: "GO_ENV", def: defaultGoEnv},
	{key: "API_PORT", def: defaultAPIPort},
	{key: "JWT_SECRET"},
	{key: "GOOGLE_CLIENT_ID"},

	{key: "DB_HOST", def: defaultDBHost},
	{key: "DB_PORT", def: defaultDBPort},
	{key: "DB_USER"},
	{key: "DB_PASSWORD"},
	{key: "DB_NAME"},
	{key: "DB_SSLMODE", def: defaultDBSSLMode},

	{key: "SMTP_HOST"},
	{key: "SMTP_PORT"},
	{key: "SMTP_USERNAME"},
	{key: "SMTP_PASSWORD"},
	{key: "SMTP_FROM"},

	{key: "APP_BASE_URL"},
	{key: "CORS_ALLOWED_ORIGINS"},
	{key: "STREAM_INGEST_BASE_URL", def: defaultStreamIngestBaseURL},
	{key: "STORAGE_PATH", def: defaultStoragePath},

	{key: "HLS_MAX_CONCURRENT", def: defaultHLSMaxConcurrent},
	{key: "INGEST_RECONNECT_GRACE_SECONDS", def: defaultIngestReconnectGraceSeconds},
	{key: "INGEST_STOP_TIMEOUT_SECONDS", def: defaultIngestStopTimeoutSeconds},
	{key: "TRUST_PROXY_HEADERS", def: false},
	{key: "HTTP_READ_TIMEOUT_SECONDS", def: defaultHTTPReadTimeoutSeconds},
	{key: "HTTP_WRITE_TIMEOUT_SECONDS", def: defaultHTTPWriteTimeoutSeconds},
	{key: "HTTP_IDLE_TIMEOUT_SECONDS", def: defaultHTTPIdleTimeoutSeconds},

	{key: "LOG_LEVEL", def: defaultLogLevel},
	{key: "LOG_PRETTY", def: false},
	{key: "OTEL_EXPORTER_OTLP_ENDPOINT"},
}

// Config représente la configuration complète de l'API StreamPulse.
//
// Toutes les valeurs proviennent de variables d'environnement —
// aucune n'est codée en dur dans le code source.
type Config struct {
	GoEnv     string `mapstructure:"GO_ENV"`
	APIPort   string `mapstructure:"API_PORT"`
	JWTSecret string `mapstructure:"JWT_SECRET"`

	// GoogleClientID est l'audience attendue des ID tokens Google (« Sign in
	// with Google »). Vide = connexion Google désactivée : la route /api/auth/google
	// n'est alors pas montée (404). En pratique, le **Client Web** OAuth du projet
	// Google Cloud, que le client mobile passe en serverClientId pour que l'audience
	// du jeton corresponde côté serveur.
	GoogleClientID string `mapstructure:"GOOGLE_CLIENT_ID"`

	DBHost     string `mapstructure:"DB_HOST"`
	DBPort     string `mapstructure:"DB_PORT"`
	DBUser     string `mapstructure:"DB_USER"`
	DBPassword string `mapstructure:"DB_PASSWORD"`
	DBName     string `mapstructure:"DB_NAME"`

	// DBSSLMode : mode TLS de la connexion PostgreSQL. `disable` par défaut —
	// la base n'est jointe que par le réseau interne Docker — mais paramétrable,
	// une base managée exigeant `require` ou `verify-full`.
	DBSSLMode string `mapstructure:"DB_SSLMODE"`

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

	// StoragePath est le répertoire racine où sont stockés les fichiers audio
	// uploadés (US-05-01, ADR 032). Hors de tout répertoire servi en HTTP ; en
	// Docker, monté sur un volume nommé pour la persistance.
	StoragePath string `mapstructure:"STORAGE_PATH"`

	// HLSMaxConcurrent borne le nombre de requêtes HLS (playlist + segments)
	// servies simultanément — STR-88. <= 0 désactive la borne.
	HLSMaxConcurrent int `mapstructure:"HLS_MAX_CONCURRENT"`

	// IngestReconnectGraceSeconds est le bail sans audio accordé au diffuseur
	// avant l'arrêt automatique du direct. IngestStopTimeoutSeconds borne chaque
	// tentative de transition persistante live -> ended.
	IngestReconnectGraceSeconds int `mapstructure:"INGEST_RECONNECT_GRACE_SECONDS"`
	IngestStopTimeoutSeconds    int `mapstructure:"INGEST_STOP_TIMEOUT_SECONDS"`

	// TrustProxyHeaders autorise la lecture de X-Forwarded-For pour identifier
	// l'auditeur d'un flux (comptage d'audience, STR-154).
	//
	// Faux par défaut, et c'est volontaire : l'en-tête est falsifiable par le
	// client, l'activer sans reverse proxy devant laisserait n'importe qui
	// gonfler le compteur d'un flux en variant sa valeur. À passer à true
	// **uniquement** derrière un proxy qui réécrit l'en-tête (Caddy le fait).
	// Sans lui, tous les auditeurs derrière le proxy partagent une adresse et
	// le compteur sature à 1.
	TrustProxyHeaders bool `mapstructure:"TRUST_PROXY_HEADERS"`

	// Timeouts du serveur HTTP, en secondes. Externalisés pour respecter le
	// zéro-hardcoding : un déploiement derrière un proxy lent ou un réseau
	// dégradé peut avoir besoin de les élargir sans reconstruire l'image.
	HTTPReadTimeoutSeconds  int `mapstructure:"HTTP_READ_TIMEOUT_SECONDS"`
	HTTPWriteTimeoutSeconds int `mapstructure:"HTTP_WRITE_TIMEOUT_SECONDS"`
	HTTPIdleTimeoutSeconds  int `mapstructure:"HTTP_IDLE_TIMEOUT_SECONDS"`

	// CORSAllowedOrigins : origines autorisées par CORS (CSV dans CORS_ALLOWED_ORIGINS).
	CORSAllowedOrigins []string `mapstructure:"-"`

	// LogLevel : niveau minimal des logs (trace|debug|info|warn|error|fatal|panic).
	LogLevel string `mapstructure:"LOG_LEVEL"`

	// LogPretty : sortie console lisible (dev local hors Docker uniquement) —
	// en conteneur la sortie doit rester du JSON pour la collecte Loki (STR-172).
	LogPretty bool `mapstructure:"LOG_PRETTY"`

	// OTELExporterOTLPEndpoint : endpoint OTLP/HTTP de Tempo (ADR 020).
	// Vide = tracing désactivé (provider noop) — cas du `go run` local.
	OTELExporterOTLPEndpoint string `mapstructure:"OTEL_EXPORTER_OTLP_ENDPOINT"`
}

// Load lit la configuration depuis l'environnement et la valide.
// Retourne une erreur si une variable requise est manquante ou
// si une valeur ne respecte pas les contraintes.
func Load() (*Config, error) {
	v := viper.New()

	// Valeurs par défaut, posées avant la lecture du .env (elles restent de plus
	// basse précédence quoi qu'il arrive).
	for _, e := range envKeys {
		if e.def != nil {
			v.SetDefault(e.key, e.def)
		}
	}

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

	for _, e := range envKeys {
		if err := v.BindEnv(e.key); err != nil {
			return nil, fmt.Errorf("config: bind %s: %w", e.key, err)
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
	if strings.TrimSpace(v.GetString("INGEST_RECONNECT_GRACE_SECONDS")) == "" {
		cfg.IngestReconnectGraceSeconds = defaultIngestReconnectGraceSeconds
	}
	if strings.TrimSpace(v.GetString("INGEST_STOP_TIMEOUT_SECONDS")) == "" {
		cfg.IngestStopTimeoutSeconds = defaultIngestStopTimeoutSeconds
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
	if strings.TrimSpace(c.StoragePath) == "" {
		c.StoragePath = defaultStoragePath
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

// IngestReconnectGrace retourne le bail sans audio configuré.
func (c *Config) IngestReconnectGrace() time.Duration {
	return time.Duration(c.IngestReconnectGraceSeconds) * time.Second
}

// IngestStopTimeout borne une tentative d'arrêt automatique en base.
func (c *Config) IngestStopTimeout() time.Duration {
	return time.Duration(c.IngestStopTimeoutSeconds) * time.Second
}

// DBDSN retourne la DSN PostgreSQL prête à passer à database/sql ou pgx.
// sslMode retombe sur le défaut quand le champ est vide, pour qu'un Config
// construit à la main (tests, outillage) produise une DSN utilisable sans
// passer par Load.
func (c *Config) sslMode() string {
	if c.DBSSLMode == "" {
		return defaultDBSSLMode
	}
	return c.DBSSLMode
}

func (c *Config) DBDSN() string {
	return fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
		c.DBHost, c.DBPort, c.DBUser, c.DBPassword, c.DBName, c.sslMode(),
	)
}

// DatabaseURL rend la connexion au format URL attendu par pgx.
//
// Dérivée de DBDSN plutôt que lue dans DATABASE_URL : cette variable était une
// seconde source de vérité en doublon avec les DB_*, et .env.example y
// dupliquait le mot de passe en dur — changer POSTGRES_PASSWORD sans la mettre à
// jour cassait silencieusement les migrations.
func (c *Config) DatabaseURL() string { return c.databaseURL("postgres") }

// MigrationURL rend la même connexion pour golang-migrate.
//
// Le schéma diffère de DatabaseURL, et ce n'est pas cosmétique : golang-migrate
// résout son pilote **par le schéma de l'URL**, et le pilote importé par
// internal/infrastructure/migrator est `database/pgx/v5`, qui s'enregistre sous
// le seul nom « pgx5 ». Une URL en « postgres:// » le fait échouer au démarrage
// sur « unknown driver postgres (forgotten import?) ».
//
// L'inverse est vrai aussi : pgx.ParseConfig n'accepte que « postgres:// » ou
// « postgresql:// » et rejette « pgx5:// ». Aucune URL unique ne peut donc
// servir les deux — d'où deux méthodes plutôt qu'une valeur partagée.
func (c *Config) MigrationURL() string { return c.databaseURL("pgx5") }

func (c *Config) databaseURL(scheme string) string {
	u := &url.URL{
		Scheme:   scheme,
		User:     url.UserPassword(c.DBUser, c.DBPassword),
		Host:     net.JoinHostPort(c.DBHost, c.DBPort),
		Path:     "/" + c.DBName,
		RawQuery: url.Values{"sslmode": {c.sslMode()}}.Encode(),
	}
	return u.String()
}

func (c *Config) HTTPReadTimeout() time.Duration {
	return time.Duration(c.HTTPReadTimeoutSeconds) * time.Second
}

func (c *Config) HTTPWriteTimeout() time.Duration {
	return time.Duration(c.HTTPWriteTimeoutSeconds) * time.Second
}

func (c *Config) HTTPIdleTimeout() time.Duration {
	return time.Duration(c.HTTPIdleTimeoutSeconds) * time.Second
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

	if c.IngestReconnectGraceSeconds <= mobileMaxReconnectBackoffSeconds {
		return fmt.Errorf(
			"config: INGEST_RECONNECT_GRACE_SECONDS invalide %d (attendu: > %d, le backoff de reconnexion maximal du mobile)",
			c.IngestReconnectGraceSeconds, mobileMaxReconnectBackoffSeconds,
		)
	}
	if c.IngestStopTimeoutSeconds <= 0 {
		return fmt.Errorf("config: INGEST_STOP_TIMEOUT_SECONDS invalide %d (attendu: > 0)", c.IngestStopTimeoutSeconds)
	}

	// Sans SMTP_HOST, email.NewFromConfig retombe sur LogMailer, qui écrit le
	// jeton de réinitialisation en clair dans les logs pour permettre le
	// workflow sans serveur mail. C'est acceptable en développement, jamais en
	// production : Loki n'a pas de rétention, et quiconque lit les logs prendrait
	// la main sur tout compte ayant demandé une réinitialisation. On refuse de
	// démarrer plutôt que de le découvrir après coup.
	for name, v := range map[string]int{
		"HTTP_READ_TIMEOUT_SECONDS":  c.HTTPReadTimeoutSeconds,
		"HTTP_WRITE_TIMEOUT_SECONDS": c.HTTPWriteTimeoutSeconds,
		"HTTP_IDLE_TIMEOUT_SECONDS":  c.HTTPIdleTimeoutSeconds,
	} {
		if v <= 0 {
			return fmt.Errorf("config: %s invalide %d (attendu: > 0)", name, v)
		}
	}

	if c.IsProd() && strings.TrimSpace(c.SMTPHost) == "" {
		return errors.New("config: SMTP_HOST est requis en production (sans lui les jetons de réinitialisation partiraient dans les logs)")
	}

	return nil
}
