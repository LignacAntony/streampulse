//go:build integration

// Tests d'intégration du repository admin (pgRepository) contre un vrai
// PostgreSQL. Deux bugs de revue PR #264 vivent au niveau SQL réel et ne
// peuvent pas se manifester via fakeRepo (utilisé par service_test.go) :
//
//   - fix #2 : le total de pagination doit rester correct même quand la page
//     demandée (offset) dépasse le nombre de lignes filtrées (page vide).
//   - fix #4 : '_' et '%' dans le terme de recherche doivent être traités
//     comme des caractères littéraux, pas comme des jokers ILIKE.
//
// Exclus de `go test ./...` par le build tag, comme internal/streaming/loadtest
// (cf. CLAUDE.md). Lancer :
//
//	docker run -d --rm --name streampulse-admin-it \
//	  -e POSTGRES_USER=test -e POSTGRES_PASSWORD=test -e POSTGRES_DB=test \
//	  -p 15432:5432 postgres:16-alpine
//	cd backend && go test -tags integration ./internal/admin/... -run TestRepository -v
//	docker stop streampulse-admin-it
//
// DSN surchargeable via TEST_DATABASE_URL (format URL postgres://, sans le
// sous-scheme pgx5 propre à golang-migrate — dérivé automatiquement).
package admin

import (
	"context"
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

const defaultTestDSN = "postgres://test:test@localhost:15432/test?sslmode=disable"

var migrateOnce sync.Once

// testRepository ouvre un pool vers TEST_DATABASE_URL (ou defaultTestDSN),
// applique les migrations une seule fois par process de test (idempotent via
// ErrNoChange), et renvoie le pgRepository concret (accès direct au pool pour
// les fixtures, cf. insertTestUser). t.Skip si la base n'est pas joignable :
// `go test -tags integration ./...` sans Postgres démarré ne doit jamais
// échouer, juste sauter ces tests.
func testRepository(t *testing.T) *pgRepository {
	t.Helper()

	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		dsn = defaultTestDSN
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Skipf("integration: cannot open pool (%v) — start postgres first, see file header", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		t.Skipf("integration: cannot reach postgres (%v) — start postgres first, see file header", err)
	}

	applyMigrations(t, dsn)

	t.Cleanup(pool.Close)
	repo, ok := NewRepository(pool).(*pgRepository)
	if !ok {
		t.Fatalf("NewRepository did not return a *pgRepository")
	}
	return repo
}

// applyMigrations exécute toutes les migrations SQL (backend/migrations) sur
// la base ciblée par dsn, une seule fois par process de test.
func applyMigrations(t *testing.T, dsn string) {
	t.Helper()
	migrateOnce.Do(func() {
		migrationsDir, err := filepath.Abs("../../migrations")
		if err != nil {
			t.Fatalf("integration: resolve migrations dir: %v", err)
		}
		m, err := migrate.New("file://"+migrationsDir, toMigrateURL(dsn))
		if err != nil {
			t.Fatalf("integration: migrate init: %v", err)
		}
		defer m.Close()
		if err := m.Up(); err != nil && err != migrate.ErrNoChange {
			t.Fatalf("integration: migrate up: %v", err)
		}
	})
}

// toMigrateURL substitue à dsn (postgres://...) le pseudo-scheme "pgx5"
// attendu par le driver golang-migrate/database/pgx/v5 (cf. migrator.go).
func toMigrateURL(dsn string) string {
	if i := strings.Index(dsn, "://"); i != -1 {
		return "pgx5" + dsn[i:]
	}
	return dsn
}

// uniqueTag renvoie un préfixe improbable à collisionner, utilisé dans les
// champs recherchables (email/username) des fixtures pour que le filtre
// Search d'un test ne matche jamais les lignes d'un autre test partageant la
// même base.
func uniqueTag(t *testing.T) string {
	t.Helper()
	return fmt.Sprintf("it%d", time.Now().UnixNano())
}

// insertTestUser insère une ligne users minimale et la supprime à la fin du
// test (t.Cleanup), que le test réussisse ou non.
func insertTestUser(t *testing.T, pool *pgxpool.Pool, email, username, role string, isActive bool) {
	t.Helper()
	ctx := context.Background()
	_, err := pool.Exec(ctx,
		`INSERT INTO users (email, username, password_hash, role, is_active) VALUES ($1, $2, 'x', $3, $4)`,
		email, username, role, isActive)
	if err != nil {
		t.Fatalf("integration: insert fixture user %s: %v", username, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE email = $1`, email)
	})
}

// Fix #2 revue PR #264 : COUNT(*) OVER() n'est porté que par les lignes
// renvoyées — une page vide (offset au-delà du nombre de lignes filtrées)
// renvoyait total=0 au lieu du vrai total de correspondances.
func TestRepository_ListUsers_TotalReflectsAllMatchesNotJustPage(t *testing.T) {
	repo := testRepository(t)
	tag := uniqueTag(t)

	for i := 0; i < 5; i++ {
		insertTestUser(t, repo.pool, fmt.Sprintf("%s-%d@example.com", tag, i), fmt.Sprintf("%s_user%d", tag, i), "user", true)
	}

	// Sanity check : la première page renvoie bien les 5 lignes et le bon total.
	users, total, err := repo.ListUsers(context.Background(), ListUsersInput{Search: tag, Limit: 20, Offset: 0})
	if err != nil {
		t.Fatalf("unexpected error (offset 0): %v", err)
	}
	if len(users) != 5 || total != 5 {
		t.Fatalf("sanity check failed: got %d users, total=%d, want 5/5", len(users), total)
	}

	// Le cas du bug : offset au-delà des 5 lignes filtrées -> page vide, mais
	// le total doit toujours refléter les 5 correspondances réelles.
	users, total, err = repo.ListUsers(context.Background(), ListUsersInput{Search: tag, Limit: 20, Offset: 20})
	if err != nil {
		t.Fatalf("unexpected error (offset 20): %v", err)
	}
	if len(users) != 0 {
		t.Errorf("want an empty page at offset 20, got %d users", len(users))
	}
	if total != 5 {
		t.Errorf("fix #2: total must reflect all matches regardless of pagination, got total=%d, want 5", total)
	}
}

// Fix #4 revue PR #264 : '_' est un joker ILIKE (un caractère quelconque) —
// une recherche contenant un underscore littéral matchait aussi des lignes
// qui ne le contiennent pas.
func TestRepository_ListUsers_SearchEscapesLikeWildcards(t *testing.T) {
	repo := testRepository(t)
	tag := uniqueTag(t)

	exactUsername := tag + "_a_b"    // contient l'underscore littéral recherché
	wildcardUsername := tag + "_axb" // ne matche que si '_' agit comme joker

	insertTestUser(t, repo.pool, tag+"-exact@example.com", exactUsername, "user", true)
	insertTestUser(t, repo.pool, tag+"-wildcard@example.com", wildcardUsername, "user", true)

	users, total, err := repo.ListUsers(context.Background(), ListUsersInput{Search: tag + "_a_b", Limit: 20, Offset: 0})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if total != 1 || len(users) != 1 {
		t.Fatalf("fix #4: '_' must be literal, not a SQL wildcard — got %d results (total=%d), want exactly 1", len(users), total)
	}
	if users[0].Username != exactUsername {
		t.Errorf("wrong match: got username %q, want %q", users[0].Username, exactUsername)
	}
}
