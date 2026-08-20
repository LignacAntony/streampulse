//go:build integration

// Package pgtest fournit le socle commun aux tests d'intégration des
// repositories : un pool vers une base PostgreSQL réelle, migrée.
//
// Il existe parce que les sept domaines ont besoin exactement du même
// échafaudage — ouvrir un pool, appliquer les migrations une fois, sauter
// proprement si la base est absente. Recopier cette centaine de lignes sept
// fois garantissait qu'elles divergeraient.
//
// Le build tag `integration` le tient hors de `go test ./...` et hors de tout
// binaire : rien ne l'importe en dehors des tests ainsi taggés.
//
// # Lancer les tests d'intégration
//
// La base cible est **toujours** explicite, via TEST_DATABASE_URL. Il n'y a
// pas de valeur par défaut, et c'est délibéré : ces tests écrivent dans la
// base qu'on leur donne. Un défaut pointant sur un port courant finirait tôt
// ou tard par tomber sur la base de développement de quelqu'un.
//
//	docker run -d --rm --name streampulse-it \
//	  -e POSTGRES_USER=test -e POSTGRES_PASSWORD=test -e POSTGRES_DB=test \
//	  -p 15432:5432 postgres:16-alpine
//
//	cd backend && TEST_DATABASE_URL='postgres://<user>:<pass>@localhost:15432/test?sslmode=disable' \
//	  go test -tags integration ./...
//
//	docker stop streampulse-it
//
// en remplaçant <user> et <pass> par les identifiants du conteneur ci-dessus.
//
// Sans TEST_DATABASE_URL, ou si la base est injoignable, ces tests se
// **sautent** — ils n'échouent pas. La même commande reste donc jouable sur un
// poste sans PostgreSQL.
package pgtest

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/pgx/v5"
	_ "github.com/golang-migrate/migrate/v4/source/file"
	"github.com/jackc/pgx/v5/pgxpool"
)

// EnvDSN nomme la variable qui porte la base de test.
const EnvDSN = "TEST_DATABASE_URL"

var migrateOnce sync.Once

// DSN rend la chaîne de connexion des tests, ou la chaîne vide si elle n'est
// pas fournie.
//
// Aucune valeur par défaut, volontairement. La version précédente en avait une
// — un conteneur jetable sur un port inhabituel — et c'était déjà une
// concession : ces tests écrivent dans la base qu'on leur donne, et un défaut
// finit toujours par s'appliquer à une base qu'on ne visait pas. L'absence de
// défaut supprime aussi le seul identifiant en dur du dépôt hors fichiers de
// test, que le garde-fou `Scan for hardcoded ports / DSN / secrets` relevait à
// juste titre.
func DSN() string { return os.Getenv(EnvDSN) }

// Pool ouvre un pool vers la base de test, applique les migrations une seule
// fois par processus de test, et referme le pool à la fin du test.
//
// Si la base n'est pas joignable, le test est **sauté** et non mis en échec :
// `go test -tags integration ./...` sans PostgreSQL doit rester silencieux,
// sans quoi personne ne lancerait jamais la commande en local.
func Pool(t *testing.T) *pgxpool.Pool {
	t.Helper()

	dsn := DSN()
	if dsn == "" {
		t.Skipf("integration: %s non défini — cf. l'en-tête de pgtest pour la commande", EnvDSN)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Skipf("integration: ouverture du pool impossible (%v) — démarrer PostgreSQL, cf. en-tête de pgtest", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		t.Skipf("integration: PostgreSQL injoignable (%v) — démarrer PostgreSQL, cf. en-tête de pgtest", err)
	}

	applyMigrations(t, dsn)
	t.Cleanup(pool.Close)
	return pool
}

// applyMigrations joue backend/migrations sur la base ciblée, une fois par
// processus. Le répertoire est cherché en remontant depuis le dossier du test,
// pour que le helper fonctionne quelle que soit la profondeur de l'appelant.
func applyMigrations(t *testing.T, dsn string) {
	t.Helper()
	migrateOnce.Do(func() {
		dir, err := findMigrationsDir()
		if err != nil {
			t.Fatalf("integration: %v", err)
		}
		m, err := migrate.New("file://"+dir, toMigrateURL(dsn))
		if err != nil {
			t.Fatalf("integration: migrate init: %v", err)
		}
		defer func() { _, _ = m.Close() }()
		if err := m.Up(); err != nil && !errors.Is(err, migrate.ErrNoChange) {
			t.Fatalf("integration: migrate up: %v", err)
		}
	})
}

func findMigrationsDir() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("répertoire courant: %w", err)
	}
	for i := 0; i < 6; i++ {
		candidate := filepath.Join(dir, "migrations")
		if info, err := os.Stat(candidate); err == nil && info.IsDir() {
			return candidate, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return "", fmt.Errorf("répertoire migrations introuvable en remontant depuis le test")
}

// toMigrateURL substitue le pseudo-scheme « pgx5 » attendu par
// golang-migrate ; pgx, lui, n'accepte que « postgres:// ». Même distinction
// que config.DatabaseURL / config.MigrationURL.
func toMigrateURL(dsn string) string {
	if i := strings.Index(dsn, "://"); i != -1 {
		return "pgx5" + dsn[i:]
	}
	return dsn
}

// UniqueTag rend un préfixe que deux tests ne peuvent pas partager. Les tests
// s'exécutent sur une base commune et ne la vident pas : sans ce préfixe dans
// les champs recherchables, le filtre d'un test verrait les lignes d'un autre.
func UniqueTag(t *testing.T) string {
	t.Helper()
	return fmt.Sprintf("it%d", time.Now().UnixNano())
}

// InsertUser insère un utilisateur minimal et rend son identifiant. La ligne
// est supprimée à la fin du test, que celui-ci réussisse ou échoue — les
// suppressions en cascade emportent tout ce qui s'y rattache.
func InsertUser(t *testing.T, pool *pgxpool.Pool, tag, role string) string {
	t.Helper()
	var id string
	err := pool.QueryRow(context.Background(),
		`INSERT INTO users (email, username, password_hash, role, is_active)
		 VALUES ($1, $2, 'x', $3, true) RETURNING id`,
		tag+"@it.test", tag, role,
	).Scan(&id)
	if err != nil {
		t.Fatalf("integration: insertion utilisateur %s: %v", tag, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

// InsertTrack insère une piste minimale appartenant à userID et rend son
// identifiant. Les valeurs non signifiantes (chemin, type, taille) satisfont
// les contraintes CHECK de la table sans prétendre décrire un vrai fichier.
func InsertTrack(t *testing.T, pool *pgxpool.Pool, userID, title string) string {
	t.Helper()
	var id string
	err := pool.QueryRow(context.Background(),
		`INSERT INTO tracks (user_id, title, file_path, mime_type, file_size)
		 VALUES ($1, $2, $3, 'audio/mpeg', 1024) RETURNING id`,
		userID, title, "/dev/null/"+title,
	).Scan(&id)
	if err != nil {
		t.Fatalf("integration: insertion piste %s: %v", title, err)
	}
	return id
}
