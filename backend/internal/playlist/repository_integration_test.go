//go:build integration

// Tests d'intégration du repository playlist contre un vrai PostgreSQL.
//
// Ce domaine est celui qui justifie le plus une exécution sur SQL réel : trois
// de ses règles ne vivent **que** dans le schéma, et un fake en mémoire les
// laisserait toutes passer.
//
//   - `uq_playlists_user_name` — deux playlists de même nom pour un même
//     utilisateur doivent être refusées par la base, pas par le service.
//   - `UNIQUE (playlist_id, position)` **DEFERRABLE INITIALLY DEFERRED** — un
//     réordonnancement réécrit toutes les positions et passe forcément par des
//     états intermédiaires en doublon ; seule une contrainte différée, dans une
//     transaction, le permet.
//   - `ON CONFLICT (playlist_id, track_id)` doit **nommer ses colonnes** : une
//     contrainte différée ne peut pas servir d'arbitre, et un `ON CONFLICT DO
//     NOTHING` nu échouerait en SQLSTATE 55000.
//
// Lancement : cf. l'en-tête de internal/testsupport/pgtest.
package playlist

import (
	"context"
	"testing"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
	"github.com/LignacAntony/streampulse/internal/testsupport/pgtest"
)

func newRepo(t *testing.T) (Repository, string) {
	t.Helper()
	pool := pgtest.Pool(t)
	tag := pgtest.UniqueTag(t)
	userID := pgtest.InsertUser(t, pool, tag, "user")
	return NewRepository(pool), userID
}

func TestRepository_CreateAndGet(t *testing.T) {
	repo, userID := newRepo(t)
	ctx := context.Background()
	desc := "ma description"

	created, err := repo.Create(ctx, CreateParams{UserID: userID, Name: "Matin", Description: &desc})
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	if created.ID == "" || created.UserID != userID || created.Name != "Matin" {
		t.Fatalf("playlist créée incohérente: %+v", created)
	}
	if created.Description == nil || *created.Description != desc {
		t.Errorf("description = %v, want %q", created.Description, desc)
	}

	got, err := repo.GetByID(ctx, created.ID)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if got.ID != created.ID || got.Name != "Matin" {
		t.Errorf("GetByID = %+v, want la playlist créée", got)
	}
}

// La contrainte uq_playlists_user_name vit dans le schéma : aucun test à base
// de fake ne peut la vérifier.
func TestRepository_Create_NomDejaPrisParLeMemeUtilisateur(t *testing.T) {
	repo, userID := newRepo(t)
	ctx := context.Background()

	if _, err := repo.Create(ctx, CreateParams{UserID: userID, Name: "Doublon"}); err != nil {
		t.Fatalf("première création: %v", err)
	}
	_, err := repo.Create(ctx, CreateParams{UserID: userID, Name: "Doublon"})
	if err == nil {
		t.Fatal("un nom déjà pris doit être refusé")
	}
	if !apperror.IsCode(err, apperror.CodeConflict) {
		t.Errorf("erreur = %v, want un conflit apperror", err)
	}
}

// Le même nom chez deux utilisateurs différents doit passer : la contrainte
// porte sur le couple (user_id, name), pas sur le nom seul.
func TestRepository_Create_MemeNomChezDeuxUtilisateurs(t *testing.T) {
	pool := pgtest.Pool(t)
	repo := NewRepository(pool)
	ctx := context.Background()

	a := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"a", "user")
	b := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"b", "user")

	if _, err := repo.Create(ctx, CreateParams{UserID: a, Name: "Partagé"}); err != nil {
		t.Fatalf("création chez a: %v", err)
	}
	if _, err := repo.Create(ctx, CreateParams{UserID: b, Name: "Partagé"}); err != nil {
		t.Fatalf("création chez b doit être permise: %v", err)
	}
}

func TestRepository_ListByUser_CompteLesPistes(t *testing.T) {
	pool := pgtest.Pool(t)
	repo := NewRepository(pool)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "user")

	vide, err := repo.Create(ctx, CreateParams{UserID: userID, Name: "Vide"})
	if err != nil {
		t.Fatalf("Create vide: %v", err)
	}
	pleine, err := repo.Create(ctx, CreateParams{UserID: userID, Name: "Pleine"})
	if err != nil {
		t.Fatalf("Create pleine: %v", err)
	}
	for _, titre := range []string{"p1", "p2"} {
		trackID := pgtest.InsertTrack(t, pool, userID, pgtest.UniqueTag(t)+titre)
		if err := repo.AddTrack(ctx, AddTrackParams{PlaylistID: pleine.ID, TrackID: trackID, UserID: userID}); err != nil {
			t.Fatalf("AddTrack %s: %v", titre, err)
		}
	}

	liste, err := repo.ListByUser(ctx, userID)
	if err != nil {
		t.Fatalf("ListByUser: %v", err)
	}
	compte := map[string]int{}
	for _, p := range liste {
		compte[p.ID] = p.TrackCount
	}
	// LEFT JOIN : une playlist sans piste doit apparaître avec un compte à 0,
	// et non disparaître de la liste.
	if got, ok := compte[vide.ID]; !ok || got != 0 {
		t.Errorf("playlist vide: présente=%v compte=%d, want présente avec 0", ok, got)
	}
	if got := compte[pleine.ID]; got != 2 {
		t.Errorf("playlist pleine: compte=%d, want 2", got)
	}
}

func TestRepository_Update(t *testing.T) {
	repo, userID := newRepo(t)
	ctx := context.Background()
	desc := "avant"

	p, err := repo.Create(ctx, CreateParams{UserID: userID, Name: "Avant", Description: &desc})
	if err != nil {
		t.Fatalf("Create: %v", err)
	}

	// Remplacement total : omettre la description doit l'effacer.
	maj, err := repo.Update(ctx, UpdateParams{ID: p.ID, UserID: userID, Name: "Après"})
	if err != nil {
		t.Fatalf("Update: %v", err)
	}
	if maj.Name != "Après" {
		t.Errorf("nom = %q, want %q", maj.Name, "Après")
	}
	if maj.Description != nil {
		t.Errorf("description = %v, want nil après remplacement total", *maj.Description)
	}
}

// Le filtre porte sur (id, user_id) en SQL : la playlist d'un tiers ne doit ni
// être modifiée ni être supprimée, et l'appel doit le signaler.
func TestRepository_UpdateEtDelete_IsolentParUtilisateur(t *testing.T) {
	pool := pgtest.Pool(t)
	repo := NewRepository(pool)
	ctx := context.Background()

	proprio := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"o", "user")
	tiers := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"t", "user")

	p, err := repo.Create(ctx, CreateParams{UserID: proprio, Name: "Privée"})
	if err != nil {
		t.Fatalf("Create: %v", err)
	}

	if _, err := repo.Update(ctx, UpdateParams{ID: p.ID, UserID: tiers, Name: "Volée"}); err == nil {
		t.Error("un tiers ne doit pas pouvoir renommer la playlist")
	}
	if err := repo.Delete(ctx, p.ID, tiers); err == nil {
		t.Error("un tiers ne doit pas pouvoir supprimer la playlist")
	}

	// La playlist est intacte.
	got, err := repo.GetByID(ctx, p.ID)
	if err != nil {
		t.Fatalf("GetByID après tentatives: %v", err)
	}
	if got.Name != "Privée" {
		t.Errorf("nom = %q, la playlist a été modifiée par un tiers", got.Name)
	}

	if err := repo.Delete(ctx, p.ID, proprio); err != nil {
		t.Fatalf("le propriétaire doit pouvoir supprimer: %v", err)
	}
	if _, err := repo.GetByID(ctx, p.ID); err == nil {
		t.Error("la playlist supprimée reste lisible")
	}
}

func TestRepository_AddTrack_RefusePisteDunTiers(t *testing.T) {
	pool := pgtest.Pool(t)
	repo := NewRepository(pool)
	ctx := context.Background()

	proprio := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"o", "user")
	tiers := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"t", "user")

	p, err := repo.Create(ctx, CreateParams{UserID: proprio, Name: "À moi"})
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	pisteDunTiers := pgtest.InsertTrack(t, pool, tiers, pgtest.UniqueTag(t))

	if err := repo.AddTrack(ctx, AddTrackParams{PlaylistID: p.ID, TrackID: pisteDunTiers, UserID: proprio}); err == nil {
		t.Error("ajouter la piste d'un tiers doit échouer")
	}
}

func TestRepository_AddTrack_DejaPresente(t *testing.T) {
	pool := pgtest.Pool(t)
	repo := NewRepository(pool)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "user")

	p, err := repo.Create(ctx, CreateParams{UserID: userID, Name: "Doublons"})
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	trackID := pgtest.InsertTrack(t, pool, userID, pgtest.UniqueTag(t))

	if err := repo.AddTrack(ctx, AddTrackParams{PlaylistID: p.ID, TrackID: trackID, UserID: userID}); err != nil {
		t.Fatalf("premier ajout: %v", err)
	}
	// Le second ajout emprunte le chemin ON CONFLICT (playlist_id, track_id).
	// S'il n'était pas explicitement arbitré, PostgreSQL répondrait 55000 —
	// une erreur de contrainte différée, et non un conflit métier.
	err = repo.AddTrack(ctx, AddTrackParams{PlaylistID: p.ID, TrackID: trackID, UserID: userID})
	if err == nil {
		t.Fatal("ajouter deux fois la même piste doit être refusé")
	}
	if !apperror.IsCode(err, apperror.CodeConflict) {
		t.Errorf("erreur = %v, want un conflit apperror (et non une erreur SQL brute)", err)
	}
}

// Le cœur du domaine : réordonner réécrit toutes les positions dans une
// transaction. Sans contrainte différée, l'état intermédiaire (deux pistes en
// position 0) violerait UNIQUE (playlist_id, position).
func TestRepository_Reorder(t *testing.T) {
	pool := pgtest.Pool(t)
	repo := NewRepository(pool)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "user")

	p, err := repo.Create(ctx, CreateParams{UserID: userID, Name: "Ordre"})
	if err != nil {
		t.Fatalf("Create: %v", err)
	}

	ids := make([]string, 3)
	for i := range ids {
		ids[i] = pgtest.InsertTrack(t, pool, userID, pgtest.UniqueTag(t)+string(rune('a'+i)))
		if err := repo.AddTrack(ctx, AddTrackParams{PlaylistID: p.ID, TrackID: ids[i], UserID: userID}); err != nil {
			t.Fatalf("AddTrack %d: %v", i, err)
		}
	}

	positions := func() []string {
		t.Helper()
		pistes, err := repo.ListTracks(ctx, p.ID)
		if err != nil {
			t.Fatalf("ListTracks: %v", err)
		}
		out := make([]string, len(pistes))
		for i, pt := range pistes {
			if pt.Position != i {
				t.Errorf("position %d attendue à l'index %d, got %d", i, i, pt.Position)
			}
			out[i] = pt.ID
		}
		return out
	}

	if got := positions(); got[0] != ids[0] || got[2] != ids[2] {
		t.Fatalf("ordre initial = %v, want %v", got, ids)
	}

	inverse := []string{ids[2], ids[1], ids[0]}
	if err := repo.Reorder(ctx, p.ID, inverse); err != nil {
		t.Fatalf("Reorder: %v", err)
	}
	if got := positions(); got[0] != ids[2] || got[1] != ids[1] || got[2] != ids[0] {
		t.Errorf("ordre après inversion = %v, want %v", got, inverse)
	}
}

// Retirer une piste doit **recompacter** les positions en 0..n-1 : un trou
// laisserait le réordonnancement suivant en échec.
func TestRepository_RemoveTrack_RecompacteLesPositions(t *testing.T) {
	pool := pgtest.Pool(t)
	repo := NewRepository(pool)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "user")

	p, err := repo.Create(ctx, CreateParams{UserID: userID, Name: "Compactage"})
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	ids := make([]string, 3)
	for i := range ids {
		ids[i] = pgtest.InsertTrack(t, pool, userID, pgtest.UniqueTag(t)+string(rune('x'+i)))
		if err := repo.AddTrack(ctx, AddTrackParams{PlaylistID: p.ID, TrackID: ids[i], UserID: userID}); err != nil {
			t.Fatalf("AddTrack %d: %v", i, err)
		}
	}

	if err := repo.RemoveTrack(ctx, p.ID, ids[0]); err != nil {
		t.Fatalf("RemoveTrack: %v", err)
	}

	pistes, err := repo.ListTracks(ctx, p.ID)
	if err != nil {
		t.Fatalf("ListTracks: %v", err)
	}
	if len(pistes) != 2 {
		t.Fatalf("%d pistes restantes, want 2", len(pistes))
	}
	for i, pt := range pistes {
		if pt.Position != i {
			t.Errorf("piste %d en position %d, want %d — positions non recompactées", i, pt.Position, i)
		}
	}
}

func TestRepository_RemoveTrack_PisteAbsente(t *testing.T) {
	pool := pgtest.Pool(t)
	repo := NewRepository(pool)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "user")

	p, err := repo.Create(ctx, CreateParams{UserID: userID, Name: "Absente"})
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	orpheline := pgtest.InsertTrack(t, pool, userID, pgtest.UniqueTag(t))

	if err := repo.RemoveTrack(ctx, p.ID, orpheline); err == nil {
		t.Error("retirer une piste absente doit être signalé")
	}
}
