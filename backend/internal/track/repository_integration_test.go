//go:build integration

// Tests d'intégration du repository track contre un vrai PostgreSQL.
//
// Deux propriétés de ce domaine ne vivent que dans le schéma :
//
//   - `uq_tracks_user_title` — deux pistes de même titre pour un même
//     utilisateur sont refusées par la base ;
//   - le quota de stockage repose sur une agrégation SQL (`SumFileSizeByUser`)
//     qu'aucun fake ne calcule vraiment.
//
// S'y ajoute la règle d'isolation : la piste d'un tiers doit être introuvable,
// et non refusée — c'est ce qui évite de révéler son existence.
//
// Lancement : cf. l'en-tête de internal/testsupport/pgtest.
package track

import (
	"context"
	"testing"

	"github.com/LignacAntony/streampulse/internal/testsupport/pgtest"
)

func newTrackRepo(t *testing.T) (Repository, string) {
	t.Helper()
	pool := pgtest.Pool(t)
	return NewRepository(pool), pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "user")
}

func params(userID, titre string, taille int64) CreateTrackParams {
	return CreateTrackParams{
		UserID:   userID,
		Title:    titre,
		FilePath: "/data/tracks/" + titre + ".mp3",
		MimeType: "audio/mpeg",
		FileSize: taille,
	}
}

func TestRepository_CreateTrack_EtListe(t *testing.T) {
	repo, userID := newTrackRepo(t)
	ctx := context.Background()

	artiste := "Un artiste"
	duree := 210
	p := params(userID, "Titre A", 4096)
	p.Artist = &artiste
	p.DurationS = &duree

	cree, err := repo.CreateTrack(ctx, p)
	if err != nil {
		t.Fatalf("CreateTrack: %v", err)
	}
	if cree.ID == "" || cree.Title != "Titre A" {
		t.Fatalf("piste créée incohérente: %+v", cree)
	}
	if cree.Artist == nil || *cree.Artist != artiste {
		t.Errorf("artiste = %v, want %q", cree.Artist, artiste)
	}
	if cree.DurationS == nil || *cree.DurationS != duree {
		t.Errorf("durée = %v, want %d", cree.DurationS, duree)
	}

	liste, err := repo.ListTracksByUser(ctx, userID)
	if err != nil {
		t.Fatalf("ListTracksByUser: %v", err)
	}
	if len(liste) != 1 || liste[0].ID != cree.ID {
		t.Errorf("liste = %+v, want la seule piste créée", liste)
	}
}

func TestRepository_CreateTrack_TitreDejaPris(t *testing.T) {
	repo, userID := newTrackRepo(t)
	ctx := context.Background()

	if _, err := repo.CreateTrack(ctx, params(userID, "Doublon", 1024)); err != nil {
		t.Fatalf("première création: %v", err)
	}
	if _, err := repo.CreateTrack(ctx, params(userID, "Doublon", 2048)); err == nil {
		t.Error("un titre déjà pris par le même utilisateur doit être refusé")
	}
}

func TestRepository_CreateTrack_MemeTitreChezDeuxUtilisateurs(t *testing.T) {
	pool := pgtest.Pool(t)
	repo := NewRepository(pool)
	ctx := context.Background()

	a := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"a", "user")
	b := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"b", "user")

	if _, err := repo.CreateTrack(ctx, params(a, "Partagé", 1024)); err != nil {
		t.Fatalf("création chez a: %v", err)
	}
	if _, err := repo.CreateTrack(ctx, params(b, "Partagé", 1024)); err != nil {
		t.Fatalf("le même titre chez un autre utilisateur doit passer: %v", err)
	}
}

// Le quota s'appuie sur cette somme : si elle ne comptait pas juste, un compte
// pourrait dépasser les 500 Mo sans que rien ne le signale.
func TestRepository_SumFileSizeByUser(t *testing.T) {
	repo, userID := newTrackRepo(t)
	ctx := context.Background()

	// Un utilisateur sans piste doit rendre 0, et non une erreur : c'est le
	// cas du tout premier upload.
	somme, err := repo.SumFileSizeByUser(ctx, userID)
	if err != nil {
		t.Fatalf("SumFileSizeByUser sur compte vide: %v", err)
	}
	if somme != 0 {
		t.Errorf("somme initiale = %d, want 0", somme)
	}

	for i, taille := range []int64{1000, 2500} {
		if _, err := repo.CreateTrack(ctx, params(userID, string(rune('A'+i)), taille)); err != nil {
			t.Fatalf("CreateTrack %d: %v", i, err)
		}
	}

	somme, err = repo.SumFileSizeByUser(ctx, userID)
	if err != nil {
		t.Fatalf("SumFileSizeByUser: %v", err)
	}
	if somme != 3500 {
		t.Errorf("somme = %d, want 3500", somme)
	}
}

// La propriété est filtrée en SQL : la piste d'un tiers est **introuvable**,
// ce qui ne révèle pas son existence.
func TestRepository_GetTrackFileByUser_IsolationParUtilisateur(t *testing.T) {
	pool := pgtest.Pool(t)
	repo := NewRepository(pool)
	ctx := context.Background()

	proprio := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"o", "user")
	tiers := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"t", "user")

	cree, err := repo.CreateTrack(ctx, params(proprio, "Privée", 1024))
	if err != nil {
		t.Fatalf("CreateTrack: %v", err)
	}

	fichier, err := repo.GetTrackFileByUser(ctx, cree.ID, proprio)
	if err != nil {
		t.Fatalf("le propriétaire doit pouvoir lire sa piste: %v", err)
	}
	if fichier.MimeType != "audio/mpeg" {
		t.Errorf("mime = %q, want audio/mpeg — il doit venir de la base, jamais être deviné", fichier.MimeType)
	}

	if _, err := repo.GetTrackFileByUser(ctx, cree.ID, tiers); err == nil {
		t.Error("la piste d'un tiers doit être introuvable")
	}
}

// Utilisé par la purge des fichiers à la suppression d'un compte : si la liste
// des chemins était incomplète, des fichiers resteraient orphelins sur le
// volume après la suppression en cascade.
func TestRepository_ListFilePathsByUser(t *testing.T) {
	repo, userID := newTrackRepo(t)
	ctx := context.Background()

	attendus := map[string]bool{}
	for i := 0; i < 3; i++ {
		p := params(userID, string(rune('P'+i)), 1024)
		attendus[p.FilePath] = true
		if _, err := repo.CreateTrack(ctx, p); err != nil {
			t.Fatalf("CreateTrack %d: %v", i, err)
		}
	}

	chemins, err := repo.ListFilePathsByUser(ctx, userID)
	if err != nil {
		t.Fatalf("ListFilePathsByUser: %v", err)
	}
	if len(chemins) != len(attendus) {
		t.Fatalf("%d chemins, want %d", len(chemins), len(attendus))
	}
	for _, c := range chemins {
		if !attendus[c] {
			t.Errorf("chemin inattendu: %s", c)
		}
	}
}
