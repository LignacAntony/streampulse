package config

import (
	"strings"
	"testing"
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
	vars := validVars()
	delete(vars, "API_PORT")
	delete(vars, "GO_ENV")
	delete(vars, "DB_HOST")
	delete(vars, "DB_PORT")
	setEnv(t, vars)
	// Ensure no leftover values from outer process leak in.
	t.Setenv("API_PORT", "")
	t.Setenv("GO_ENV", "")
	t.Setenv("DB_HOST", "")
	t.Setenv("DB_PORT", "")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() unexpected error: %v", err)
	}

	if cfg.APIPort != "8080" {
		t.Errorf("default APIPort = %q, want %q", cfg.APIPort, "8080")
	}
	if cfg.GoEnv != "development" {
		t.Errorf("default GoEnv = %q, want %q", cfg.GoEnv, "development")
	}
	if cfg.DBHost != "localhost" {
		t.Errorf("default DBHost = %q, want %q", cfg.DBHost, "localhost")
	}
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
