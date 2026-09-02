//go:build integration

// Tests d'intégration du repository streaming contre un vrai PostgreSQL.
//
// C'est le repository le plus dense du projet, et l'essentiel de ses règles
// vit dans le schéma plutôt que dans le code Go :
//
//   - **un seul flux en direct par diffuseur** — index partiel unique posé par
//     la migration 000016 ; aucun fake ne peut le reproduire ;
//   - la suppression est un **soft delete** (`archived_at`), donc un flux
//     archivé doit disparaître des lectures sans disparaître de la table ;
//   - `start`/`stop` sont des transitions gardées : `idle|ended→live`,
//     `live→ended`, et rien d'autre ;
//   - les favoris sont **idempotents** côté SQL.
//
// Lancement : cf. l'en-tête de internal/testsupport/pgtest.
package streaming

import (
	"context"
	"testing"

	"github.com/LignacAntony/streampulse/internal/testsupport/pgtest"
	"github.com/jackc/pgx/v5/pgxpool"
)

func newStreamingRepo(t *testing.T) (Repository, *pgxpool.Pool) {
	t.Helper()
	pool := pgtest.Pool(t)
	return NewRepository(pool), pool
}

// creerFlux insère un flux `idle` appartenant à userID.
func creerFlux(t *testing.T, repo Repository, userID, titre string, public bool) Stream {
	t.Helper()
	s, err := repo.Create(context.Background(), CreateParams{
		UserID:    userID,
		Title:     titre,
		IsPublic:  public,
		Status:    StatusIdle,
		StreamKey: pgtest.UniqueTag(t) + titre,
	})
	if err != nil {
		t.Fatalf("Create %s: %v", titre, err)
	}
	return s
}

func TestRepository_CreateEtGetByID(t *testing.T) {
	repo, pool := newStreamingRepo(t)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "broadcaster")

	s := creerFlux(t, repo, userID, "Mon direct", true)
	if s.ID == "" || s.Status != StatusIdle || !s.IsPublic {
		t.Fatalf("flux créé incohérent: %+v", s)
	}

	got, err := repo.GetByID(ctx, s.ID)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if got.ID != s.ID || got.StreamKey != s.StreamKey {
		t.Errorf("GetByID = %+v, want le flux créé avec sa clé", got)
	}
}

func TestRepository_GetByID_Inconnu(t *testing.T) {
	repo, _ := newStreamingRepo(t)
	if _, err := repo.GetByID(context.Background(), "00000000-0000-0000-0000-000000000000"); err == nil {
		t.Error("un flux inconnu doit produire une erreur")
	}
}

func TestRepository_Update(t *testing.T) {
	repo, pool := newStreamingRepo(t)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "broadcaster")
	s := creerFlux(t, repo, userID, "Avant", true)

	desc := "une description"
	maj, err := repo.Update(ctx, UpdateParams{
		ID: s.ID, UserID: userID, Title: "Après", Description: &desc, IsPublic: false,
	})
	if err != nil {
		t.Fatalf("Update: %v", err)
	}
	if maj.Title != "Après" || maj.IsPublic {
		t.Errorf("flux mis à jour = %+v", maj)
	}

	// Un tiers ne doit rien pouvoir modifier : le filtre porte sur (id, user_id).
	tiers := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"t", "broadcaster")
	if _, err := repo.Update(ctx, UpdateParams{ID: s.ID, UserID: tiers, Title: "Volé"}); err == nil {
		t.Error("un tiers ne doit pas pouvoir modifier le flux")
	}
}

// Suppression = archivage : la ligne reste, mais sort de toutes les lectures.
func TestRepository_Archive_EstUnSoftDelete(t *testing.T) {
	repo, pool := newStreamingRepo(t)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "broadcaster")
	s := creerFlux(t, repo, userID, "À archiver", true)

	if _, err := repo.Archive(ctx, s.ID, userID); err != nil {
		t.Fatalf("Archive: %v", err)
	}
	if _, err := repo.GetByID(ctx, s.ID); err == nil {
		t.Error("un flux archivé ne doit plus être lisible")
	}

	var archived *string
	if err := pool.QueryRow(ctx,
		`SELECT archived_at::text FROM streams WHERE id = $1`, s.ID).Scan(&archived); err != nil {
		t.Fatalf("la ligne doit subsister en base: %v", err)
	}
	if archived == nil {
		t.Error("archived_at doit être renseigné — la suppression est logique, pas physique")
	}
}

func TestRepository_Archive_ParUnTiers(t *testing.T) {
	repo, pool := newStreamingRepo(t)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"o", "broadcaster")
	tiers := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"t", "broadcaster")
	s := creerFlux(t, repo, userID, "Protégé", true)

	if _, err := repo.Archive(ctx, s.ID, tiers); err == nil {
		t.Error("un tiers ne doit pas pouvoir archiver le flux")
	}
}

// Les transitions sont gardées en SQL : seul idle→live et live→ended passent.
func TestRepository_StartStop_TransitionsGardees(t *testing.T) {
	repo, pool := newStreamingRepo(t)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "broadcaster")
	s := creerFlux(t, repo, userID, "Cycle", true)

	live, err := repo.StartStream(ctx, s.ID, userID)
	if err != nil {
		t.Fatalf("StartStream: %v", err)
	}
	if live.Status != StatusLive || live.StartedAt == nil {
		t.Fatalf("flux démarré = %+v, want live avec started_at", live)
	}

	if _, err := repo.StartStream(ctx, s.ID, userID); err == nil {
		t.Error("démarrer un flux déjà live doit échouer")
	}

	ended, err := repo.StopStream(ctx, s.ID, userID)
	if err != nil {
		t.Fatalf("StopStream: %v", err)
	}
	if ended.Status != StatusEnded || ended.EndedAt == nil {
		t.Fatalf("flux arrêté = %+v, want ended avec ended_at", ended)
	}

	if _, err := repo.StopStream(ctx, s.ID, userID); err == nil {
		t.Error("arrêter un flux déjà terminé doit échouer")
	}
}

// Un flux terminé est un canal réutilisable, pas un enregistrement à usage
// unique (ADR 048) : le relancer doit repartir proprement — statut `live`,
// `started_at` rafraîchi et `ended_at` remis à NULL. Sans cette transition, un
// direct coupé par l'expiration du bail d'ingest condamnait la tuile.
func TestRepository_StartStream_RelanceUnFluxTermine(t *testing.T) {
	repo, pool := newStreamingRepo(t)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "broadcaster")
	s := creerFlux(t, repo, userID, "Relance", true)

	if _, err := repo.StartStream(ctx, s.ID, userID); err != nil {
		t.Fatalf("premier StartStream: %v", err)
	}
	ended, err := repo.StopStream(ctx, s.ID, userID)
	if err != nil {
		t.Fatalf("StopStream: %v", err)
	}
	if ended.EndedAt == nil {
		t.Fatalf("flux arrêté = %+v, want ended_at renseigné", ended)
	}

	relance, err := repo.StartStream(ctx, s.ID, userID)
	if err != nil {
		t.Fatalf("relancer un flux terminé doit réussir, got %v", err)
	}
	if relance.Status != StatusLive {
		t.Errorf("status = %q, want live", relance.Status)
	}
	if relance.StartedAt == nil {
		t.Error("started_at doit être rafraîchi à la relance")
	}
	// Un `live` qui porte encore une date de fin est une contradiction que ni
	// l'API ni les tuiles du tableau de bord ne savent présenter.
	if relance.EndedAt != nil {
		t.Errorf("ended_at = %v, want nil après relance", relance.EndedAt)
	}
}

// L'index partiel unique de la migration 000016 : un diffuseur ne peut pas
// avoir deux flux en direct. C'est la règle que rien d'autre ne garantit.
func TestRepository_UnSeulFluxLiveParDiffuseur(t *testing.T) {
	repo, pool := newStreamingRepo(t)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "broadcaster")

	premier := creerFlux(t, repo, userID, "Premier", true)
	second := creerFlux(t, repo, userID, "Second", true)

	if _, err := repo.StartStream(ctx, premier.ID, userID); err != nil {
		t.Fatalf("démarrage du premier: %v", err)
	}
	if _, err := repo.StartStream(ctx, second.ID, userID); err == nil {
		t.Error("un second flux en direct pour le même diffuseur doit être refusé")
	}

	// Une fois le premier arrêté, le second doit pouvoir démarrer.
	if _, err := repo.StopStream(ctx, premier.ID, userID); err != nil {
		t.Fatalf("arrêt du premier: %v", err)
	}
	if _, err := repo.StartStream(ctx, second.ID, userID); err != nil {
		t.Errorf("le second doit pouvoir démarrer une fois le premier arrêté: %v", err)
	}
}

func TestRepository_ListPublicLive(t *testing.T) {
	repo, pool := newStreamingRepo(t)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "broadcaster")

	public := creerFlux(t, repo, userID, "Public", true)
	prive := creerFlux(t, repo, userID, "Privé", false)
	if _, err := repo.StartStream(ctx, public.ID, userID); err != nil {
		t.Fatalf("démarrage du public: %v", err)
	}

	liste, err := repo.ListPublicLive(ctx, 100, 0)
	if err != nil {
		t.Fatalf("ListPublicLive: %v", err)
	}
	var vuPublic, vuPrive, vuIdle bool
	for _, s := range liste {
		switch s.ID {
		case public.ID:
			vuPublic = true
			if s.BroadcasterUsername == "" {
				t.Error("la liste publique doit porter le nom du diffuseur (jointure users)")
			}
		case prive.ID:
			vuPrive = true
		}
		if s.Status != StatusLive {
			vuIdle = true
		}
	}
	if !vuPublic {
		t.Error("un flux public en direct doit apparaître")
	}
	if vuPrive {
		t.Error("un flux privé ne doit jamais apparaître dans la liste publique")
	}
	if vuIdle {
		t.Error("la liste publique ne doit contenir que des flux live")
	}
}

func TestRepository_RotateStreamKey(t *testing.T) {
	repo, pool := newStreamingRepo(t)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "broadcaster")
	s := creerFlux(t, repo, userID, "Clé", true)

	neuve := pgtest.UniqueTag(t) + "-neuve"
	maj, err := repo.RotateStreamKey(ctx, s.ID, userID, neuve)
	if err != nil {
		t.Fatalf("RotateStreamKey: %v", err)
	}
	if maj.StreamKey != neuve {
		t.Errorf("clé = %q, want %q", maj.StreamKey, neuve)
	}

	tiers := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"t", "broadcaster")
	if _, err := repo.RotateStreamKey(ctx, s.ID, tiers, "peu-importe"); err == nil {
		t.Error("un tiers ne doit pas pouvoir renouveler la clé")
	}
}

func TestRepository_Favoris_SontIdempotents(t *testing.T) {
	repo, pool := newStreamingRepo(t)
	ctx := context.Background()
	diffuseur := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"d", "broadcaster")
	auditeur := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"a", "user")
	s := creerFlux(t, repo, diffuseur, "Favori", true)

	for i := 0; i < 2; i++ {
		if err := repo.AddFavorite(ctx, auditeur, s.ID); err != nil {
			t.Fatalf("AddFavorite (passage %d): %v", i+1, err)
		}
	}

	favoris, err := repo.ListFavorites(ctx, auditeur)
	if err != nil {
		t.Fatalf("ListFavorites: %v", err)
	}
	compte := 0
	for _, f := range favoris {
		if f.ID == s.ID {
			compte++
		}
		if f.StreamKey != "" {
			t.Error("la liste des favoris ne doit pas exposer la clé de diffusion")
		}
	}
	if compte != 1 {
		t.Errorf("le flux apparaît %d fois dans les favoris, want 1", compte)
	}

	for i := 0; i < 2; i++ {
		if err := repo.RemoveFavorite(ctx, auditeur, s.ID); err != nil {
			t.Fatalf("RemoveFavorite (passage %d): %v", i+1, err)
		}
	}
	favoris, err = repo.ListFavorites(ctx, auditeur)
	if err != nil {
		t.Fatalf("ListFavorites après retrait: %v", err)
	}
	for _, f := range favoris {
		if f.ID == s.ID {
			t.Error("le flux retiré reste dans les favoris")
		}
	}
}

// Tableau de bord du diffuseur : ses flux, tous statuts, avec les secrets —
// le filtre porte sur le porteur du jeton.
func TestRepository_ListByOwner_PorteLesSecrets(t *testing.T) {
	repo, pool := newStreamingRepo(t)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"o", "broadcaster")
	tiers := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"t", "broadcaster")

	s := creerFlux(t, repo, userID, "À moi", false)
	_ = creerFlux(t, repo, tiers, "À lui", true)

	miens, err := repo.ListByOwner(ctx, userID)
	if err != nil {
		t.Fatalf("ListByOwner: %v", err)
	}
	if len(miens) != 1 || miens[0].ID != s.ID {
		t.Fatalf("ListByOwner = %+v, want uniquement le flux du demandeur", miens)
	}
	if miens[0].StreamKey == "" {
		t.Error("le propriétaire doit voir sa propre clé de diffusion")
	}

	// Un diffuseur sans flux obtient une liste vide, jamais une erreur.
	vierge := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"v", "broadcaster")
	vide, err := repo.ListByOwner(ctx, vierge)
	if err != nil {
		t.Fatalf("ListByOwner sur compte sans flux: %v", err)
	}
	if len(vide) != 0 {
		t.Errorf("%d flux, want 0", len(vide))
	}
}

// Utilisé à la suppression d'un compte par un administrateur : les directs de
// la personne doivent être coupés avant que la ligne users disparaisse.
func TestRepository_StopLiveStreamsByUser(t *testing.T) {
	repo, pool := newStreamingRepo(t)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "broadcaster")

	s := creerFlux(t, repo, userID, "En direct", true)
	if _, err := repo.StartStream(ctx, s.ID, userID); err != nil {
		t.Fatalf("StartStream: %v", err)
	}

	arretes, err := repo.StopLiveStreamsByUser(ctx, userID)
	if err != nil {
		t.Fatalf("StopLiveStreamsByUser: %v", err)
	}
	if len(arretes) != 1 || arretes[0] != s.ID {
		t.Fatalf("flux arrêtés = %v, want [%s]", arretes, s.ID)
	}

	got, err := repo.GetByID(ctx, s.ID)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if got.Status != StatusEnded {
		t.Errorf("statut = %q, want ended", got.Status)
	}

	// Aucun direct restant : la liste est vide, sans erreur.
	encore, err := repo.StopLiveStreamsByUser(ctx, userID)
	if err != nil {
		t.Fatalf("second appel: %v", err)
	}
	if len(encore) != 0 {
		t.Errorf("second appel = %v, want vide", encore)
	}
}

// Interruption par un administrateur : sans contrôle de propriétaire.
func TestRepository_ForceStopLiveStream(t *testing.T) {
	repo, pool := newStreamingRepo(t)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "broadcaster")

	s := creerFlux(t, repo, userID, "Modéré", true)
	if _, err := repo.StartStream(ctx, s.ID, userID); err != nil {
		t.Fatalf("StartStream: %v", err)
	}

	if _, err := repo.ForceStopLiveStream(ctx, s.ID); err != nil {
		t.Fatalf("ForceStopLiveStream: %v", err)
	}
	got, err := repo.GetByID(ctx, s.ID)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if got.Status != StatusEnded {
		t.Errorf("statut = %q, want ended", got.Status)
	}

	if _, err := repo.ForceStopLiveStream(ctx, s.ID); err == nil {
		t.Error("interrompre un flux déjà terminé doit être signalé")
	}
}

// Filet de sécurité au démarrage : un flux resté `live` après un arrêt brutal
// du serveur n'a plus de segmenteur derrière lui et doit être clos.
func TestRepository_EndOrphanLiveStreams(t *testing.T) {
	repo, pool := newStreamingRepo(t)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "broadcaster")

	s := creerFlux(t, repo, userID, "Orphelin", true)
	if _, err := repo.StartStream(ctx, s.ID, userID); err != nil {
		t.Fatalf("StartStream: %v", err)
	}

	n, err := repo.EndOrphanLiveStreams(ctx)
	if err != nil {
		t.Fatalf("EndOrphanLiveStreams: %v", err)
	}
	if n < 1 {
		t.Errorf("%d flux clos, want au moins 1", n)
	}

	got, err := repo.GetByID(ctx, s.ID)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if got.Status != StatusEnded {
		t.Errorf("statut = %q, want ended", got.Status)
	}
}
