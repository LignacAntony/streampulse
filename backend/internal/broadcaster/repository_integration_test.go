//go:build integration

// Tests d'intégration du repository broadcaster contre un vrai PostgreSQL.
//
// Ce que seul le SQL réel vérifie ici : `Review` **promeut l'utilisateur et
// enregistre la décision dans une même transaction**. Les deux écritures
// touchent deux tables ; si elles n'étaient pas atomiques, une panne au milieu
// laisserait soit un compte promu sans trace, soit une demande acceptée sans
// promotion. Un fake en mémoire ne peut pas distinguer les deux cas.
//
// Lancement : cf. l'en-tête de internal/testsupport/pgtest.
package broadcaster

import (
	"context"
	"testing"

	"github.com/LignacAntony/streampulse/internal/testsupport/pgtest"
	"github.com/jackc/pgx/v5/pgxpool"
)

func newBroadcasterRepo(t *testing.T) (Repository, *pgxpool.Pool) {
	t.Helper()
	pool := pgtest.Pool(t)
	return NewRepository(pool), pool
}

func roleEnBase(t *testing.T, pool *pgxpool.Pool, userID string) string {
	t.Helper()
	var role string
	if err := pool.QueryRow(context.Background(), `SELECT role FROM users WHERE id = $1`, userID).Scan(&role); err != nil {
		t.Fatalf("lecture du rôle: %v", err)
	}
	return role
}

func TestRepository_GetUserRole(t *testing.T) {
	repo, pool := newBroadcasterRepo(t)
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "user")

	role, err := repo.GetUserRole(context.Background(), userID)
	if err != nil {
		t.Fatalf("GetUserRole: %v", err)
	}
	if role != "user" {
		t.Errorf("rôle = %q, want user", role)
	}
}

func TestRepository_GetUserRole_Inconnu(t *testing.T) {
	repo, _ := newBroadcasterRepo(t)
	if _, err := repo.GetUserRole(context.Background(), "00000000-0000-0000-0000-000000000000"); err == nil {
		t.Error("un utilisateur inconnu doit produire une erreur")
	}
}

func TestRepository_CreateEtGetLatestByUser(t *testing.T) {
	repo, pool := newBroadcasterRepo(t)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "user")

	cree, err := repo.Create(ctx, userID, "je veux diffuser du jazz")
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	if cree.ID == "" || cree.Status != "pending" {
		t.Fatalf("demande créée incohérente: %+v", cree)
	}

	dernier, err := repo.GetLatestByUser(ctx, userID)
	if err != nil {
		t.Fatalf("GetLatestByUser: %v", err)
	}
	if dernier.ID != cree.ID || dernier.Message != "je veux diffuser du jazz" {
		t.Errorf("dernière demande = %+v, want la demande créée", dernier)
	}
}

func TestRepository_GetLatestByUser_AucuneDemande(t *testing.T) {
	repo, pool := newBroadcasterRepo(t)
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "user")

	if _, err := repo.GetLatestByUser(context.Background(), userID); err == nil {
		t.Error("un utilisateur sans demande doit produire une erreur")
	}
}

func TestRepository_List_FiltreParStatut(t *testing.T) {
	repo, pool := newBroadcasterRepo(t)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "user")

	cree, err := repo.Create(ctx, userID, "en attente")
	if err != nil {
		t.Fatalf("Create: %v", err)
	}

	contient := func(l []AdminRequest, id string) bool {
		for _, r := range l {
			if r.ID == id {
				return true
			}
		}
		return false
	}

	// Sans filtre, la demande est présente, jointe à l'identité du demandeur.
	toutes, err := repo.List(ctx, nil)
	if err != nil {
		t.Fatalf("List sans filtre: %v", err)
	}
	if !contient(toutes, cree.ID) {
		t.Error("la demande créée doit apparaître dans la liste non filtrée")
	}
	for _, r := range toutes {
		if r.ID == cree.ID && (r.UserID != userID || r.Email == "") {
			t.Errorf("la jointure sur users n'est pas remplie: %+v", r)
		}
	}

	enAttente := "pending"
	filtrees, err := repo.List(ctx, &enAttente)
	if err != nil {
		t.Fatalf("List filtrée: %v", err)
	}
	if !contient(filtrees, cree.ID) {
		t.Error("la demande en attente doit passer le filtre pending")
	}

	rejetees := "rejected"
	autres, err := repo.List(ctx, &rejetees)
	if err != nil {
		t.Fatalf("List rejected: %v", err)
	}
	if contient(autres, cree.ID) {
		t.Error("une demande en attente ne doit pas passer le filtre rejected")
	}
}

// Le cœur du domaine : accepter promeut le compte **et** enregistre la
// décision, dans une seule transaction.
func TestRepository_Review_ApprobationPromeutDansLaMemeTransaction(t *testing.T) {
	repo, pool := newBroadcasterRepo(t)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"u", "user")
	adminID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"a", "admin")

	demande, err := repo.Create(ctx, userID, "je veux diffuser")
	if err != nil {
		t.Fatalf("Create: %v", err)
	}

	revue, err := repo.Review(ctx, demande.ID, adminID, "approved", "bienvenue", true)
	if err != nil {
		t.Fatalf("Review: %v", err)
	}
	if revue.Status != "approved" || revue.ReviewNote != "bienvenue" {
		t.Errorf("demande revue = %+v, want approved/bienvenue", revue)
	}
	if revue.ReviewedBy == nil || *revue.ReviewedBy != adminID {
		t.Errorf("reviewed_by = %v, want %q", revue.ReviewedBy, adminID)
	}
	if got := roleEnBase(t, pool, userID); got != "broadcaster" {
		t.Errorf("rôle après approbation = %q, want broadcaster", got)
	}
}

// Refuser enregistre la décision **sans** toucher au rôle : c'est la moitié de
// la transaction qui ne doit pas s'exécuter.
func TestRepository_Review_RefusNePromeutPas(t *testing.T) {
	repo, pool := newBroadcasterRepo(t)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"u", "user")
	adminID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"a", "admin")

	demande, err := repo.Create(ctx, userID, "je veux diffuser")
	if err != nil {
		t.Fatalf("Create: %v", err)
	}

	revue, err := repo.Review(ctx, demande.ID, adminID, "rejected", "motif insuffisant", false)
	if err != nil {
		t.Fatalf("Review: %v", err)
	}
	if revue.Status != "rejected" {
		t.Errorf("statut = %q, want rejected", revue.Status)
	}
	if got := roleEnBase(t, pool, userID); got != "user" {
		t.Errorf("rôle après refus = %q, want user — un refus ne doit pas promouvoir", got)
	}
}

func TestRepository_Review_DemandeInconnue(t *testing.T) {
	repo, pool := newBroadcasterRepo(t)
	adminID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"a", "admin")

	_, err := repo.Review(context.Background(),
		"00000000-0000-0000-0000-000000000000", adminID, "approved", "", true)
	if err == nil {
		t.Error("réviser une demande inconnue doit produire une erreur")
	}
}
