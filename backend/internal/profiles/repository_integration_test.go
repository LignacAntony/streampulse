//go:build integration

// Tests d'intégration du repository profiles contre un vrai PostgreSQL.
//
// Le point non testable en mémoire : le profil est créé **par un trigger** à
// l'insertion de l'utilisateur (migration 000011). `GetMe` doit donc rendre un
// profil pour un compte qui n'a jamais rien enregistré, et `UpsertProfile` doit
// mettre à jour cette ligne plutôt que d'en insérer une seconde — la contrainte
// `UNIQUE (user_id)` l'interdirait.
//
// Lancement : cf. l'en-tête de internal/testsupport/pgtest.
package profiles

import (
	"context"
	"testing"

	"github.com/LignacAntony/streampulse/internal/testsupport/pgtest"
)

func TestRepository_GetMe_ProfilCreeParLeTrigger(t *testing.T) {
	pool := pgtest.Pool(t)
	repo := NewRepository(pool)
	tag := pgtest.UniqueTag(t)
	userID := pgtest.InsertUser(t, pool, tag, "user")

	p, err := repo.GetMe(context.Background(), userID)
	if err != nil {
		t.Fatalf("GetMe juste après création du compte: %v", err)
	}
	if p.Email != tag+"@it.test" {
		t.Errorf("email = %q, want %q", p.Email, tag+"@it.test")
	}
	if p.Role != "user" {
		t.Errorf("rôle = %q, want user", p.Role)
	}
	// Valeurs par défaut du schéma, pas du code Go.
	if p.Theme != "dark" || !p.NotificationsEnabled || p.AudioQuality != "normal" {
		t.Errorf("préférences par défaut = %q/%v/%q, want dark/true/normal",
			p.Theme, p.NotificationsEnabled, p.AudioQuality)
	}
}

func TestRepository_GetMe_UtilisateurInconnu(t *testing.T) {
	repo := NewRepository(pgtest.Pool(t))
	if _, err := repo.GetMe(context.Background(), "00000000-0000-0000-0000-000000000000"); err == nil {
		t.Error("un utilisateur inconnu doit produire une erreur")
	}
}

func TestRepository_UpsertProfile_MetAJourLaLigneExistante(t *testing.T) {
	pool := pgtest.Pool(t)
	repo := NewRepository(pool)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "user")

	in := UpdateProfileInput{
		Pseudo:               "Nouveau pseudo",
		Bio:                  "Une bio",
		Theme:                "light",
		NotificationsEnabled: false,
		AudioQuality:         "high",
	}
	if err := repo.UpsertProfile(ctx, userID, in); err != nil {
		t.Fatalf("UpsertProfile: %v", err)
	}

	p, err := repo.GetMe(ctx, userID)
	if err != nil {
		t.Fatalf("GetMe: %v", err)
	}
	if p.Pseudo != in.Pseudo || p.Bio != in.Bio || p.Theme != "light" ||
		p.NotificationsEnabled || p.AudioQuality != "high" {
		t.Errorf("profil après upsert = %+v, want %+v", p, in)
	}

	// Un second upsert doit encore mettre à jour, pas insérer : la contrainte
	// UNIQUE (user_id) ferait échouer une seconde insertion.
	in.Pseudo = "Encore un autre"
	if err := repo.UpsertProfile(ctx, userID, in); err != nil {
		t.Fatalf("second UpsertProfile: %v", err)
	}
	p, err = repo.GetMe(ctx, userID)
	if err != nil {
		t.Fatalf("GetMe après second upsert: %v", err)
	}
	if p.Pseudo != "Encore un autre" {
		t.Errorf("pseudo = %q, want %q", p.Pseudo, "Encore un autre")
	}

	var lignes int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM profiles WHERE user_id = $1`, userID).Scan(&lignes); err != nil {
		t.Fatalf("comptage: %v", err)
	}
	if lignes != 1 {
		t.Errorf("%d lignes de profil, want exactement 1", lignes)
	}
}

// Une valeur hors de l'énumération doit être refusée par le CHECK du schéma,
// et non silencieusement enregistrée.
func TestRepository_UpsertProfile_ValeurHorsEnumeration(t *testing.T) {
	pool := pgtest.Pool(t)
	repo := NewRepository(pool)
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "user")

	err := repo.UpsertProfile(context.Background(), userID, UpdateProfileInput{
		Theme:        "fluorescent",
		AudioQuality: "normal",
	})
	if err == nil {
		t.Error("un thème hors de l'énumération doit être refusé par la base")
	}
}
