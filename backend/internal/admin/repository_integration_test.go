//go:build integration

// Tests d'intégration du repository admin contre un vrai PostgreSQL.
//
// Le socle (pool, migrations, saut si la base est absente) vient de
// internal/testsupport/pgtest : il était dupliqué ici, il ne l'est plus.
//
// Deux de ces tests remontent à la revue de la PR #264 et verrouillent des
// régressions qui ne peuvent se manifester qu'au niveau SQL :
//
//   - le total de pagination doit rester juste même quand la page demandée
//     dépasse le nombre de lignes filtrées ;
//   - « _ » et « % » dans une recherche sont des caractères littéraux, pas des
//     jokers ILIKE.
//
// Lancement : cf. l'en-tête de internal/testsupport/pgtest.
package admin

import (
	"context"
	"fmt"
	"testing"

	"github.com/LignacAntony/streampulse/internal/testsupport/pgtest"
	"github.com/jackc/pgx/v5/pgxpool"
)

// testRepository rend le pgRepository concret : les fixtures écrivent
// directement par le pool, ce que l'interface Repository ne permet pas.
func testRepository(t *testing.T) *pgRepository {
	t.Helper()
	repo, ok := NewRepository(pgtest.Pool(t)).(*pgRepository)
	if !ok {
		t.Fatalf("NewRepository n'a pas rendu un *pgRepository")
	}
	return repo
}

func uniqueTag(t *testing.T) string {
	t.Helper()
	return pgtest.UniqueTag(t)
}

// insertTestUser insère une ligne users minimale, supprimée en fin de test.
func insertTestUser(t *testing.T, pool *pgxpool.Pool, email, username, role string, isActive bool) {
	t.Helper()
	ctx := context.Background()
	_, err := pool.Exec(ctx,
		`INSERT INTO users (email, username, password_hash, role, is_active) VALUES ($1, $2, 'x', $3, $4)`,
		email, username, role, isActive)
	if err != nil {
		t.Fatalf("integration: insertion fixture %s: %v", username, err)
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

func TestRepository_GetUser(t *testing.T) {
	repo := testRepository(t)
	tag := uniqueTag(t)
	insertTestUser(t, repo.pool, tag+"@example.com", tag, "broadcaster", true)

	liste, _, err := repo.ListUsers(context.Background(), ListUsersInput{Search: tag, Limit: 10})
	if err != nil {
		t.Fatalf("ListUsers: %v", err)
	}
	if len(liste) != 1 {
		t.Fatalf("%d résultats, want 1", len(liste))
	}

	got, err := repo.GetUser(context.Background(), liste[0].ID)
	if err != nil {
		t.Fatalf("GetUser: %v", err)
	}
	if got.Username != tag || got.Role != "broadcaster" || !got.IsActive {
		t.Errorf("utilisateur = %+v, want %s/broadcaster/actif", got, tag)
	}
}

func TestRepository_GetUser_Inconnu(t *testing.T) {
	repo := testRepository(t)
	if _, err := repo.GetUser(context.Background(), "00000000-0000-0000-0000-000000000000"); err == nil {
		t.Error("un identifiant inconnu doit produire une erreur")
	}
}

func TestRepository_SetUserActive(t *testing.T) {
	repo := testRepository(t)
	ctx := context.Background()
	tag := uniqueTag(t)
	insertTestUser(t, repo.pool, tag+"@example.com", tag, "user", true)

	liste, _, err := repo.ListUsers(ctx, ListUsersInput{Search: tag, Limit: 10})
	if err != nil || len(liste) != 1 {
		t.Fatalf("ListUsers: %v (%d résultats)", err, len(liste))
	}
	id := liste[0].ID

	desactive, err := repo.SetUserActive(ctx, id, false)
	if err != nil {
		t.Fatalf("SetUserActive(false): %v", err)
	}
	if desactive.IsActive {
		t.Error("le compte doit être désactivé")
	}

	reactive, err := repo.SetUserActive(ctx, id, true)
	if err != nil {
		t.Fatalf("SetUserActive(true): %v", err)
	}
	if !reactive.IsActive {
		t.Error("la désactivation doit être réversible")
	}
}

func TestRepository_SetUserActive_Inconnu(t *testing.T) {
	repo := testRepository(t)
	if _, err := repo.SetUserActive(context.Background(), "00000000-0000-0000-0000-000000000000", false); err == nil {
		t.Error("désactiver un compte inconnu doit produire une erreur")
	}
}

// Ce compteur est le garde-fou qui empêche de retirer le dernier
// administrateur actif. S'il comptait faux, l'administration deviendrait
// inaccessible sans que rien ne l'ait signalé.
func TestRepository_CountActiveAdmins(t *testing.T) {
	repo := testRepository(t)
	ctx := context.Background()

	avant, err := repo.CountActiveAdmins(ctx)
	if err != nil {
		t.Fatalf("CountActiveAdmins: %v", err)
	}

	tag := uniqueTag(t)
	insertTestUser(t, repo.pool, tag+"@example.com", tag, "admin", true)

	apres, err := repo.CountActiveAdmins(ctx)
	if err != nil {
		t.Fatalf("CountActiveAdmins après ajout: %v", err)
	}
	if apres != avant+1 {
		t.Fatalf("compte = %d, want %d", apres, avant+1)
	}

	// Un administrateur désactivé ne compte plus.
	liste, _, err := repo.ListUsers(ctx, ListUsersInput{Search: tag, Limit: 10})
	if err != nil || len(liste) != 1 {
		t.Fatalf("ListUsers: %v (%d)", err, len(liste))
	}
	if _, err := repo.SetUserActive(ctx, liste[0].ID, false); err != nil {
		t.Fatalf("SetUserActive: %v", err)
	}
	final, err := repo.CountActiveAdmins(ctx)
	if err != nil {
		t.Fatalf("CountActiveAdmins après désactivation: %v", err)
	}
	if final != avant {
		t.Errorf("compte = %d, want %d — un admin désactivé ne doit pas compter", final, avant)
	}
}

func TestRepository_DeleteUser(t *testing.T) {
	repo := testRepository(t)
	ctx := context.Background()
	tag := uniqueTag(t)
	insertTestUser(t, repo.pool, tag+"@example.com", tag, "user", true)

	liste, _, err := repo.ListUsers(ctx, ListUsersInput{Search: tag, Limit: 10})
	if err != nil || len(liste) != 1 {
		t.Fatalf("ListUsers: %v (%d)", err, len(liste))
	}
	id := liste[0].ID

	if err := repo.DeleteUser(ctx, id); err != nil {
		t.Fatalf("DeleteUser: %v", err)
	}
	if _, err := repo.GetUser(ctx, id); err == nil {
		t.Error("le compte supprimé reste lisible")
	}
}

func TestRepository_ListLiveStreams(t *testing.T) {
	repo := testRepository(t)
	ctx := context.Background()
	tag := uniqueTag(t)
	insertTestUser(t, repo.pool, tag+"@example.com", tag, "broadcaster", true)

	var userID string
	if err := repo.pool.QueryRow(ctx, `SELECT id FROM users WHERE username = $1`, tag).Scan(&userID); err != nil {
		t.Fatalf("relecture de l'identifiant: %v", err)
	}

	// Flux live inséré directement : la modération lit les flux, elle ne les
	// crée pas, et le domaine streaming n'est pas importable ici.
	var streamID string
	err := repo.pool.QueryRow(ctx,
		`INSERT INTO streams (user_id, title, is_public, status, stream_key, started_at)
		 VALUES ($1, $2, true, 'live', $3, NOW()) RETURNING id`,
		userID, "Direct "+tag, tag+"-key",
	).Scan(&streamID)
	if err != nil {
		t.Fatalf("insertion du flux: %v", err)
	}

	liste, total, err := repo.ListLiveStreams(ctx, 100, 0)
	if err != nil {
		t.Fatalf("ListLiveStreams: %v", err)
	}
	if total < 1 {
		t.Fatalf("total = %d, want au moins 1", total)
	}
	var trouve bool
	for _, s := range liste {
		if s.ID == streamID {
			trouve = true
			if s.Username != tag {
				t.Errorf("username = %q, want %q — la jointure users doit être remplie", s.Username, tag)
			}
			if s.StartedAt == nil {
				t.Error("started_at doit être renseigné sur un flux live")
			}
		}
	}
	if !trouve {
		t.Error("le flux en direct doit apparaître dans la liste de modération")
	}
}

// La trace d'audit doit survivre à la suppression du compte de l'administrateur
// qui a agi : actor_id passe à NULL, la ligne reste. C'est l'arbitrage entre le
// droit à l'effacement et l'obligation de garder trace des décisions.
func TestRepository_InsertAuditLog_SurvitALaSuppressionDeLActeur(t *testing.T) {
	repo := testRepository(t)
	ctx := context.Background()
	tag := uniqueTag(t)
	insertTestUser(t, repo.pool, tag+"@example.com", tag, "admin", true)

	var adminID string
	if err := repo.pool.QueryRow(ctx, `SELECT id FROM users WHERE username = $1`, tag).Scan(&adminID); err != nil {
		t.Fatalf("relecture de l'identifiant: %v", err)
	}

	cible := "11111111-1111-1111-1111-111111111111"
	if err := repo.InsertAuditLog(ctx, adminID, "stream.stopped", "stream", cible); err != nil {
		t.Fatalf("InsertAuditLog: %v", err)
	}
	t.Cleanup(func() {
		_, _ = repo.pool.Exec(context.Background(), `DELETE FROM audit_logs WHERE target_id = $1`, cible)
	})

	if err := repo.DeleteUser(ctx, adminID); err != nil {
		t.Fatalf("DeleteUser: %v", err)
	}

	var action string
	var acteur *string
	err := repo.pool.QueryRow(ctx,
		`SELECT action, actor_id::text FROM audit_logs WHERE target_id = $1`, cible).Scan(&action, &acteur)
	if err != nil {
		t.Fatalf("la trace d'audit doit survivre: %v", err)
	}
	if action != "stream.stopped" {
		t.Errorf("action = %q, want stream.stopped", action)
	}
	if acteur != nil {
		t.Errorf("actor_id = %v, want NULL après suppression du compte", *acteur)
	}
}
