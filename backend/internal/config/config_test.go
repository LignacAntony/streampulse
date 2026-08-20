package config

import (
	"reflect"
	"strings"
	"testing"
	"time"
)

// setEnv positionne plusieurs variables d'environnement pour la durée du test.
// t.Setenv s'occupe automatiquement du nettoyage.
func setEnv(t *testing.T, vars map[string]string) {
	t.Helper()
	for k, v := range vars {
		t.Setenv(k, v)
	}
}

// validVars retourne un set complet de variables valides utilisables comme baseline.
func validVars() map[string]string {
	return map[string]string{
		"GO_ENV":      "test",
		"API_PORT":    "8080",
		"JWT_SECRET":  "this-is-a-very-long-secret-of-32+chars",
		"DB_HOST":     "localhost",
		"DB_PORT":     "5432",
		"DB_USER":     "streampulse",
		"DB_PASSWORD": "secret",
		"DB_NAME":     "streampulse_db",
	}
}

func TestLoad_Success(t *testing.T) {
	setEnv(t, validVars())

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() unexpected error: %v", err)
	}

	if cfg.APIPort != "8080" {
		t.Errorf("APIPort = %q, want %q", cfg.APIPort, "8080")
	}
	if cfg.HTTPAddr() != ":8080" {
		t.Errorf("HTTPAddr() = %q, want %q", cfg.HTTPAddr(), ":8080")
	}
	if cfg.DBName != "streampulse_db" {
		t.Errorf("DBName = %q, want %q", cfg.DBName, "streampulse_db")
	}
}

func TestLoad_MissingRequired(t *testing.T) {
	vars := validVars()
	delete(vars, "JWT_SECRET")
	setEnv(t, vars)
	t.Setenv("JWT_SECRET", "") // explicit empty

	_, err := Load()
	if err == nil {
		t.Fatal("Load() expected error for missing JWT_SECRET, got nil")
	}
	if !strings.Contains(err.Error(), "JWT_SECRET") {
		t.Errorf("error should mention JWT_SECRET, got: %v", err)
	}
}

func TestLoad_ShortJWTSecret(t *testing.T) {
	vars := validVars()
	vars["JWT_SECRET"] = "too-short"
	setEnv(t, vars)

	_, err := Load()
	if err == nil {
		t.Fatal("Load() expected error for short JWT_SECRET, got nil")
	}
	if !strings.Contains(err.Error(), "JWT_SECRET") {
		t.Errorf("error should mention JWT_SECRET, got: %v", err)
	}
}

func TestLoad_DefaultsApplied(t *testing.T) {
	// Variante 1 : variables optionnelles absentes — défauts viper appliqués.
	t.Run("absent", func(t *testing.T) {
		vars := validVars()
		delete(vars, "API_PORT")
		delete(vars, "GO_ENV")
		delete(vars, "DB_HOST")
		delete(vars, "DB_PORT")
		setEnv(t, vars)

		cfg, err := Load()
		if err != nil {
			t.Fatalf("Load() unexpected error: %v", err)
		}
		assertDefaults(t, cfg)
	})

	// Variante 2 : variables optionnelles présentes mais à "" — empty est
	// traité comme absent (post-process), les défauts sont appliqués.
	t.Run("empty string", func(t *testing.T) {
		setEnv(t, validVars())
		t.Setenv("API_PORT", "")
		t.Setenv("GO_ENV", "")
		t.Setenv("DB_HOST", "")
		t.Setenv("DB_PORT", "")

		cfg, err := Load()
		if err != nil {
			t.Fatalf("Load() unexpected error: %v", err)
		}
		assertDefaults(t, cfg)
	})
}

// assertDefaults vérifie qu'une config a bien reçu les valeurs par défaut
// pour les champs optionnels (GoEnv, APIPort, DBHost, DBPort).
func assertDefaults(t *testing.T, cfg *Config) {
	t.Helper()
	if cfg.APIPort != defaultAPIPort {
		t.Errorf("default APIPort = %q, want %q", cfg.APIPort, defaultAPIPort)
	}
	if cfg.GoEnv != defaultGoEnv {
		t.Errorf("default GoEnv = %q, want %q", cfg.GoEnv, defaultGoEnv)
	}
	if cfg.DBHost != defaultDBHost {
		t.Errorf("default DBHost = %q, want %q", cfg.DBHost, defaultDBHost)
	}
	if cfg.DBPort != defaultDBPort {
		t.Errorf("default DBPort = %q, want %q", cfg.DBPort, defaultDBPort)
	}
}

// TestLoad_HLSMaxConcurrent couvre le fix « "" ≠ désactivé » : une valeur
// vide est équivalente à absente (retombe sur le défaut 256), alors qu'un 0
// explicite reste 0 (limiteur désactivé, cf. commentaire du champ
// Config.HLSMaxConcurrent).
//
// Limite connue : ces sous-tests positionnent HLS_MAX_CONCURRENT via
// l'environnement OS (t.Setenv) — ce fichier n'a pas de harnais pour écrire
// un .env temporaire et le faire lire par Load() (AddConfigPath dépend du
// cwd du process au moment de l'appel, que ces tests ne modifient pas).
// Le code de production traite les deux sources de façon identique :
// v.GetString("HLS_MAX_CONCURRENT") est relu après Unmarshal quelle que soit
// la couche d'où vient la valeur (env OS, fichier .env, ou défaut viper) —
// le cas « vide via .env » emprunte donc exactement le même chemin que le
// cas « vide via env » couvert ci-dessous.
func TestLoad_HLSMaxConcurrent(t *testing.T) {
	tests := []struct {
		name   string
		setEnv bool // false = variable absente (ni env ni .env)
		value  string
		want   int
	}{
		{name: "vide -> défaut 256", setEnv: true, value: "", want: defaultHLSMaxConcurrent},
		{name: "0 explicite -> désactivé", setEnv: true, value: "0", want: 0},
		{name: "absente -> défaut 256", setEnv: false, want: defaultHLSMaxConcurrent},
		{name: "128 -> 128", setEnv: true, value: "128", want: 128},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			setEnv(t, validVars())
			if tt.setEnv {
				t.Setenv("HLS_MAX_CONCURRENT", tt.value)
			}

			cfg, err := Load()
			if err != nil {
				t.Fatalf("Load() unexpected error: %v", err)
			}
			if cfg.HLSMaxConcurrent != tt.want {
				t.Errorf("HLSMaxConcurrent = %d, want %d", cfg.HLSMaxConcurrent, tt.want)
			}
		})
	}
}

func TestLoad_IngestTimeouts(t *testing.T) {
	t.Run("défauts", func(t *testing.T) {
		setEnv(t, validVars())
		cfg, err := Load()
		if err != nil {
			t.Fatalf("Load() unexpected error: %v", err)
		}
		if cfg.IngestReconnectGrace() != 45*time.Second {
			t.Errorf("IngestReconnectGrace() = %s, want 45s", cfg.IngestReconnectGrace())
		}
		if cfg.IngestStopTimeout() != 10*time.Second {
			t.Errorf("IngestStopTimeout() = %s, want 10s", cfg.IngestStopTimeout())
		}
	})

	t.Run("personnalisés", func(t *testing.T) {
		setEnv(t, validVars())
		t.Setenv("INGEST_RECONNECT_GRACE_SECONDS", "60")
		t.Setenv("INGEST_STOP_TIMEOUT_SECONDS", "15")
		cfg, err := Load()
		if err != nil {
			t.Fatalf("Load() unexpected error: %v", err)
		}
		if cfg.IngestReconnectGrace() != time.Minute {
			t.Errorf("IngestReconnectGrace() = %s, want 1m", cfg.IngestReconnectGrace())
		}
		if cfg.IngestStopTimeout() != 15*time.Second {
			t.Errorf("IngestStopTimeout() = %s, want 15s", cfg.IngestStopTimeout())
		}
	})

	for _, key := range []string{"INGEST_RECONNECT_GRACE_SECONDS", "INGEST_STOP_TIMEOUT_SECONDS"} {
		t.Run(key+" invalide", func(t *testing.T) {
			setEnv(t, validVars())
			t.Setenv(key, "0")
			if _, err := Load(); err == nil || !strings.Contains(err.Error(), key) {
				t.Fatalf("Load() error = %v, want erreur pour %s", err, key)
			}
		})
	}

	// Invariant de l'ADR 027 : un bail plus court que le backoff mobile
	// couperait les directs pendant la fenêtre de reconnexion normale du
	// téléphone. La borne est refusée au démarrage, pas seulement documentée.
	for _, value := range []string{"20", "30"} {
		t.Run("bail plus court que le backoff mobile ("+value+"s)", func(t *testing.T) {
			setEnv(t, validVars())
			t.Setenv("INGEST_RECONNECT_GRACE_SECONDS", value)
			_, err := Load()
			if err == nil || !strings.Contains(err.Error(), "INGEST_RECONNECT_GRACE_SECONDS") {
				t.Fatalf("Load() error = %v, want refus du bail %ss", err, value)
			}
		})
	}

	t.Run("bail juste au-dessus du backoff mobile", func(t *testing.T) {
		setEnv(t, validVars())
		t.Setenv("INGEST_RECONNECT_GRACE_SECONDS", "31")
		cfg, err := Load()
		if err != nil {
			t.Fatalf("Load() unexpected error: %v", err)
		}
		if cfg.IngestReconnectGrace() != 31*time.Second {
			t.Errorf("IngestReconnectGrace() = %s, want 31s", cfg.IngestReconnectGrace())
		}
	})
}

func TestConfig_DBDSN(t *testing.T) {
	cfg := &Config{
		DBHost:     "db.example.com",
		DBPort:     "5432",
		DBUser:     "u",
		DBPassword: "p",
		DBName:     "n",
	}
	want := "host=db.example.com port=5432 user=u password=p dbname=n sslmode=disable"
	if got := cfg.DBDSN(); got != want {
		t.Errorf("DBDSN() = %q, want %q", got, want)
	}
}

// Les deux URL de connexion ne diffèrent que par leur schéma, et ce détail
// décide si l'API démarre. golang-migrate résout son pilote par le schéma :
// `database/pgx/v5` ne s'enregistre que sous « pgx5 », et une URL « postgres://
// » fait échouer le démarrage sur « unknown driver postgres (forgotten
// import?) ». pgx.ParseConfig, lui, rejette « pgx5:// ».
//
// Rien d'autre ne couvre cette contrainte : la CI compile et joue les tests
// unitaires, elle ne démarre jamais le binaire.
func TestConfig_URLsDeConnexion(t *testing.T) {
	cfg := &Config{
		DBHost:     "db.example.com",
		DBPort:     "5432",
		DBUser:     "u",
		DBPassword: "p",
		DBName:     "n",
	}

	const credsEtCible = "://u:p@db.example.com:5432/n?sslmode=disable"

	if got, want := cfg.DatabaseURL(), "postgres"+credsEtCible; got != want {
		t.Errorf("DatabaseURL() = %q, want %q", got, want)
	}
	if got, want := cfg.MigrationURL(), "pgx5"+credsEtCible; got != want {
		t.Errorf("MigrationURL() = %q, want %q", got, want)
	}

	// Les deux doivent désigner la même base : seul le schéma change.
	if strings.TrimPrefix(cfg.DatabaseURL(), "postgres") !=
		strings.TrimPrefix(cfg.MigrationURL(), "pgx5") {
		t.Errorf("les deux URL ne pointent pas sur la même base:\n  %s\n  %s",
			cfg.DatabaseURL(), cfg.MigrationURL())
	}
}

func TestConfig_IsDev_IsProd(t *testing.T) {
	tests := []struct {
		env      string
		wantDev  bool
		wantProd bool
	}{
		{"development", true, false},
		{"dev", true, false},
		{"production", false, true},
		{"prod", false, true},
		{"staging", false, false},
		{"DEV", true, false}, // case-insensitive
	}
	for _, tt := range tests {
		t.Run(tt.env, func(t *testing.T) {
			cfg := &Config{GoEnv: tt.env}
			if got := cfg.IsDev(); got != tt.wantDev {
				t.Errorf("IsDev() = %v, want %v", got, tt.wantDev)
			}
			if got := cfg.IsProd(); got != tt.wantProd {
				t.Errorf("IsProd() = %v, want %v", got, tt.wantProd)
			}
		})
	}
}

func TestLoad_Logging(t *testing.T) {
	t.Run("défauts", func(t *testing.T) {
		setEnv(t, validVars())
		cfg, err := Load()
		if err != nil {
			t.Fatalf("Load() error = %v", err)
		}
		if cfg.LogLevel != "info" {
			t.Errorf("LogLevel = %q, want %q", cfg.LogLevel, "info")
		}
		if cfg.LogPretty {
			t.Error("LogPretty = true, want false par défaut")
		}
	})

	t.Run("valeurs explicites", func(t *testing.T) {
		vars := validVars()
		vars["LOG_LEVEL"] = "DEBUG"
		vars["LOG_PRETTY"] = "true"
		setEnv(t, vars)
		cfg, err := Load()
		if err != nil {
			t.Fatalf("Load() error = %v", err)
		}
		if cfg.LogLevel != "debug" {
			t.Errorf("LogLevel = %q, want %q (normalisé en minuscules)", cfg.LogLevel, "debug")
		}
		if !cfg.LogPretty {
			t.Error("LogPretty = false, want true")
		}
	})

	t.Run("LOG_LEVEL vide retombe sur le défaut", func(t *testing.T) {
		vars := validVars()
		vars["LOG_LEVEL"] = ""
		setEnv(t, vars)
		cfg, err := Load()
		if err != nil {
			t.Fatalf("Load() error = %v", err)
		}
		if cfg.LogLevel != "info" {
			t.Errorf("LogLevel = %q, want %q", cfg.LogLevel, "info")
		}
	})

	t.Run("LOG_LEVEL invalide rejeté", func(t *testing.T) {
		vars := validVars()
		vars["LOG_LEVEL"] = "verbose"
		setEnv(t, vars)
		if _, err := Load(); err == nil {
			t.Fatal("Load() = nil error, want erreur pour LOG_LEVEL invalide")
		} else if !strings.Contains(err.Error(), "LOG_LEVEL") {
			t.Errorf("erreur %q ne mentionne pas LOG_LEVEL", err)
		}
	})
}

func TestLoad_OTELEndpoint(t *testing.T) {
	t.Run("défaut vide (tracing désactivé)", func(t *testing.T) {
		setEnv(t, validVars())
		cfg, err := Load()
		if err != nil {
			t.Fatalf("Load() error = %v", err)
		}
		if cfg.OTELExporterOTLPEndpoint != "" {
			t.Errorf("OTELExporterOTLPEndpoint = %q, want vide par défaut", cfg.OTELExporterOTLPEndpoint)
		}
	})

	t.Run("valeur explicite", func(t *testing.T) {
		vars := validVars()
		vars["OTEL_EXPORTER_OTLP_ENDPOINT"] = "http://tempo:4318"
		setEnv(t, vars)
		cfg, err := Load()
		if err != nil {
			t.Fatalf("Load() error = %v", err)
		}
		if cfg.OTELExporterOTLPEndpoint != "http://tempo:4318" {
			t.Errorf("OTELExporterOTLPEndpoint = %q", cfg.OTELExporterOTLPEndpoint)
		}
	})
}

// TestEnvKeys_CouvrentTousLesChampsDeConfig garde boundEnvKeys aligné sur la
// structure Config.
//
// Un champ dont la clé n'est ni dans boundEnvKeys ni dans un SetDefault est
// invisible pour viper.Unmarshal : la variable d'environnement reste sans
// effet, sans le moindre message. Exiger la présence dans boundEnvKeys pour
// *tous* les champs supprime la question « ce champ a-t-il un défaut ? » —
// c'est une condition suffisante, vérifiable mécaniquement.
func TestEnvKeys_CouvrentTousLesChampsDeConfig(t *testing.T) {
	bound := make(map[string]bool, len(envKeys))
	for _, e := range envKeys {
		bound[e.key] = true
	}

	typ := reflect.TypeOf(Config{})
	for i := range typ.NumField() {
		field := typ.Field(i)
		tag := field.Tag.Get("mapstructure")
		if tag == "" || tag == "-" {
			continue
		}
		if !bound[tag] {
			t.Errorf("champ %s : %q absent de envKeys — la variable d'environnement serait ignorée", field.Name, tag)
		}
	}
}

// TestLoad_TrustProxyHeaders verrouille la lecture de la variable.
//
// STR-240 : la clé manquait à boundEnvKeys, et son absence de
// docker-compose.prod.yml laissait le défaut `false` s'appliquer en production
// — derrière Caddy, tous les auditeurs partagent l'adresse du proxy et le
// comptage sature à un. Le SetDefault suffisait en fait à rendre la clé
// lisible ; ce test l'établit plutôt que de le supposer.
func TestLoad_TrustProxyHeaders(t *testing.T) {
	t.Run("absent → false", func(t *testing.T) {
		setEnv(t, validVars())
		// Neutralise explicitement : la variable peut être exportée dans le
		// shell (CI ou poste de dev), ce qui rendrait l'assertion faussement
		// verte ou instable.
		t.Setenv("TRUST_PROXY_HEADERS", "")

		cfg, err := Load()
		if err != nil {
			t.Fatalf("Load() unexpected error: %v", err)
		}
		if cfg.TrustProxyHeaders {
			t.Error("TrustProxyHeaders = true, attendu false par défaut")
		}
	})

	t.Run("true → true", func(t *testing.T) {
		setEnv(t, validVars())
		t.Setenv("TRUST_PROXY_HEADERS", "true")

		cfg, err := Load()
		if err != nil {
			t.Fatalf("Load() unexpected error: %v", err)
		}
		if !cfg.TrustProxyHeaders {
			t.Error("TrustProxyHeaders = false alors que TRUST_PROXY_HEADERS=true")
		}
	})
}
