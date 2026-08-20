//go:build integration

// Tests d'intégration du repository auth contre un vrai PostgreSQL.
//
// C'est le domaine où l'écart entre un fake et le SQL réel coûte le plus cher :
// la sécurité des sessions repose sur des propriétés de la base, pas sur du
// code Go.
//
//   - la rotation d'un refresh token est **destructive** : rejouer l'ancien
//     doit échouer, sinon un jeton volé reste utilisable ;
//   - les requêtes de connexion et de renouvellement joignent sur
//     `is_active = true` : un compte désactivé ne doit plus pouvoir renouveler ;
//   - un jeton de réinitialisation est à **usage unique** (`used_at`).
//
// Lancement : cf. l'en-tête de internal/testsupport/pgtest.
package auth

import (
	"context"
	"testing"
	"time"

	"github.com/LignacAntony/streampulse/internal/testsupport/pgtest"
	"github.com/jackc/pgx/v5/pgxpool"
)

func newAuthRepo(t *testing.T) (Repository, *pgxpool.Pool) {
	t.Helper()
	pool := pgtest.Pool(t)
	return NewRepository(pool), pool
}

func createUser(t *testing.T, repo Repository) User {
	t.Helper()
	tag := pgtest.UniqueTag(t)
	u, err := repo.CreateUser(context.Background(), tag+"@it.test", tag, "hash-bidon")
	if err != nil {
		t.Fatalf("CreateUser: %v", err)
	}
	t.Cleanup(func() {
		_ = repo.DeleteUserByID(context.Background(), u.ID)
	})
	return u
}

func TestRepository_CreateUser_EtRelecture(t *testing.T) {
	repo, _ := newAuthRepo(t)
	ctx := context.Background()
	u := createUser(t, repo)

	if u.ID == "" || u.Role != "user" {
		t.Fatalf("utilisateur créé incohérent: %+v", u)
	}

	parEmail, err := repo.GetUserByEmail(ctx, u.Email)
	if err != nil {
		t.Fatalf("GetUserByEmail: %v", err)
	}
	if parEmail.ID != u.ID || parEmail.PasswordHash != "hash-bidon" {
		t.Errorf("relecture par email = %+v, want l'utilisateur créé avec son hash", parEmail)
	}

	parID, err := repo.GetUserByID(ctx, u.ID)
	if err != nil {
		t.Fatalf("GetUserByID: %v", err)
	}
	if parID.Email != u.Email {
		t.Errorf("relecture par id = %+v", parID)
	}
}

func TestRepository_CreateUser_EmailDejaPris(t *testing.T) {
	repo, _ := newAuthRepo(t)
	ctx := context.Background()
	u := createUser(t, repo)

	if _, err := repo.CreateUser(ctx, u.Email, u.Username+"bis", "x"); err == nil {
		t.Error("un email déjà pris doit être refusé")
	}
}

func TestRepository_GetUserByEmail_Inconnu(t *testing.T) {
	repo, _ := newAuthRepo(t)
	if _, err := repo.GetUserByEmail(context.Background(), "personne@it.test"); err == nil {
		t.Error("un email inconnu doit produire une erreur")
	}
}

// La rotation est destructive : c'est ce qui rend un vol de refresh token
// détectable et borné dans le temps.
func TestRepository_RotateRefreshToken_InvalideLAncien(t *testing.T) {
	repo, _ := newAuthRepo(t)
	ctx := context.Background()
	u := createUser(t, repo)
	exp := time.Now().Add(time.Hour)

	if err := repo.StoreRefreshToken(ctx, u.ID, "hash-1", exp); err != nil {
		t.Fatalf("StoreRefreshToken: %v", err)
	}
	if got, err := repo.GetUserByRefreshToken(ctx, "hash-1"); err != nil || got.ID != u.ID {
		t.Fatalf("GetUserByRefreshToken avant rotation: %+v / %v", got, err)
	}

	if err := repo.RotateRefreshToken(ctx, "hash-1", "hash-2", u.ID, exp); err != nil {
		t.Fatalf("RotateRefreshToken: %v", err)
	}

	if _, err := repo.GetUserByRefreshToken(ctx, "hash-1"); err == nil {
		t.Error("l'ancien jeton reste utilisable après rotation — un vol ne serait pas borné")
	}
	if got, err := repo.GetUserByRefreshToken(ctx, "hash-2"); err != nil || got.ID != u.ID {
		t.Errorf("le nouveau jeton doit être utilisable: %+v / %v", got, err)
	}
}

func TestRepository_RevokeRefreshToken(t *testing.T) {
	repo, _ := newAuthRepo(t)
	ctx := context.Background()
	u := createUser(t, repo)

	if err := repo.StoreRefreshToken(ctx, u.ID, "hash-revoque", time.Now().Add(time.Hour)); err != nil {
		t.Fatalf("StoreRefreshToken: %v", err)
	}
	if err := repo.RevokeRefreshToken(ctx, "hash-revoque"); err != nil {
		t.Fatalf("RevokeRefreshToken: %v", err)
	}
	if _, err := repo.GetUserByRefreshToken(ctx, "hash-revoque"); err == nil {
		t.Error("un jeton révoqué doit être inutilisable")
	}
}

func TestRepository_GetUserByRefreshToken_Expire(t *testing.T) {
	repo, _ := newAuthRepo(t)
	ctx := context.Background()
	u := createUser(t, repo)

	if err := repo.StoreRefreshToken(ctx, u.ID, "hash-expire", time.Now().Add(-time.Minute)); err != nil {
		t.Fatalf("StoreRefreshToken: %v", err)
	}
	if _, err := repo.GetUserByRefreshToken(ctx, "hash-expire"); err == nil {
		t.Error("un jeton expiré doit être refusé — la date est filtrée en SQL")
	}
}

// Un compte désactivé ne doit plus pouvoir renouveler : la requête joint sur
// is_active. C'est ce qui borne une désactivation à la durée d'un access token.
func TestRepository_CompteDesactive_NePeutPlusRenouveler(t *testing.T) {
	repo, pool := newAuthRepo(t)
	ctx := context.Background()
	u := createUser(t, repo)

	if err := repo.StoreRefreshToken(ctx, u.ID, "hash-actif", time.Now().Add(time.Hour)); err != nil {
		t.Fatalf("StoreRefreshToken: %v", err)
	}
	if _, err := repo.GetUserByRefreshToken(ctx, "hash-actif"); err != nil {
		t.Fatalf("jeton valide avant désactivation: %v", err)
	}

	if _, err := pool.Exec(ctx, `UPDATE users SET is_active = false WHERE id = $1`, u.ID); err != nil {
		t.Fatalf("désactivation: %v", err)
	}

	if _, err := repo.GetUserByRefreshToken(ctx, "hash-actif"); err == nil {
		t.Error("un compte désactivé ne doit plus pouvoir renouveler sa session")
	}
	if _, err := repo.GetUserByEmail(ctx, u.Email); err == nil {
		t.Error("un compte désactivé ne doit plus pouvoir se connecter")
	}
}

func TestRepository_PasswordReset_UsageUnique(t *testing.T) {
	repo, _ := newAuthRepo(t)
	ctx := context.Background()
	u := createUser(t, repo)

	if err := repo.StorePasswordResetToken(ctx, u.ID, "reset-1", time.Now().Add(time.Hour)); err != nil {
		t.Fatalf("StorePasswordResetToken: %v", err)
	}
	if err := repo.CheckPasswordResetToken(ctx, "reset-1"); err != nil {
		t.Fatalf("CheckPasswordResetToken: %v", err)
	}

	if err := repo.ResetPassword(ctx, "reset-1", "nouveau-hash"); err != nil {
		t.Fatalf("ResetPassword: %v", err)
	}

	// used_at est renseigné : rejouer le même jeton ne doit plus rien donner.
	if err := repo.CheckPasswordResetToken(ctx, "reset-1"); err == nil {
		t.Error("un jeton de réinitialisation doit être à usage unique")
	}
	if err := repo.ResetPassword(ctx, "reset-1", "encore-un"); err == nil {
		t.Error("rejouer ResetPassword avec un jeton consommé doit échouer")
	}

	// Le mot de passe a bien changé en base.
	got, err := repo.GetUserByEmail(ctx, u.Email)
	if err != nil {
		t.Fatalf("relecture: %v", err)
	}
	if got.PasswordHash != "nouveau-hash" {
		t.Errorf("hash = %q, want %q", got.PasswordHash, "nouveau-hash")
	}
}

func TestRepository_DeletePendingPasswordResetsByUser(t *testing.T) {
	repo, _ := newAuthRepo(t)
	ctx := context.Background()
	u := createUser(t, repo)

	if err := repo.StorePasswordResetToken(ctx, u.ID, "reset-purge", time.Now().Add(time.Hour)); err != nil {
		t.Fatalf("StorePasswordResetToken: %v", err)
	}
	if err := repo.DeletePendingPasswordResetsByUser(ctx, u.ID); err != nil {
		t.Fatalf("DeletePendingPasswordResetsByUser: %v", err)
	}
	if err := repo.CheckPasswordResetToken(ctx, "reset-purge"); err == nil {
		t.Error("les demandes en attente doivent être purgées")
	}
}

// La suppression est un hard delete : la cascade doit emporter tout ce qui
// pend au compte, sans laisser de ligne orpheline.
func TestRepository_DeleteUserByID_Cascade(t *testing.T) {
	repo, pool := newAuthRepo(t)
	ctx := context.Background()

	tag := pgtest.UniqueTag(t)
	u, err := repo.CreateUser(ctx, tag+"@it.test", tag, "hash")
	if err != nil {
		t.Fatalf("CreateUser: %v", err)
	}
	if err := repo.StoreRefreshToken(ctx, u.ID, "hash-cascade", time.Now().Add(time.Hour)); err != nil {
		t.Fatalf("StoreRefreshToken: %v", err)
	}

	if err := repo.DeleteUserByID(ctx, u.ID); err != nil {
		t.Fatalf("DeleteUserByID: %v", err)
	}

	var restants int
	if err := pool.QueryRow(ctx,
		`SELECT count(*) FROM refresh_tokens WHERE user_id = $1`, u.ID).Scan(&restants); err != nil {
		t.Fatalf("comptage: %v", err)
	}
	if restants != 0 {
		t.Errorf("%d refresh_tokens survivent à la suppression du compte", restants)
	}
	if _, err := repo.GetUserByID(ctx, u.ID); err == nil {
		t.Error("l'utilisateur supprimé reste lisible")
	}
}

// La suppression est **idempotente** : un identifiant inconnu ne produit pas
// d'erreur. Le repository ne compte pas les lignes affectées, et c'est
// défendable ici — l'identifiant vient d'un JWT déjà validé, donc d'une ligne
// qui existait ; une seconde suppression n'a rien à signaler.
//
// Ce test fixe ce comportement plutôt que de le supposer : le changer ferait
// remonter une 404 sur DELETE /api/auth/me à la seconde tentative, ce qui
// serait un changement de contrat, pas une correction.
func TestRepository_DeleteUserByID_InconnuEstIdempotent(t *testing.T) {
	repo, _ := newAuthRepo(t)
	if err := repo.DeleteUserByID(context.Background(), "00000000-0000-0000-0000-000000000000"); err != nil {
		t.Errorf("supprimer un identifiant inconnu doit rester silencieux, got %v", err)
	}
}
