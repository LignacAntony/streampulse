//go:build integration

// Tests d'intégration du repository recommendation contre un vrai PostgreSQL.
//
// L'algorithme de recommandation vit **entièrement dans la requête SQL** (CTE
// d'affinité par artiste, exclusion/priorité des pistes jamais écoutées, ordre
// de repli sur les ajouts récents). Aucun fake ne le reproduit : seul un vrai
// moteur valide le classement, le `NULLS FIRST` et le cast booléen.
//
// Lancement : cf. l'en-tête de internal/testsupport/pgtest.
package recommendation

import (
	"context"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/LignacAntony/streampulse/internal/testsupport/pgtest"
)

// insertTrack insère une piste privée (avec artiste optionnel) et rend son id.
func insertTrack(t *testing.T, pool *pgxpool.Pool, userID, title, artist string) string {
	return insertTrackVisibility(t, pool, userID, title, artist, false)
}

// insertTrackVisibility insère une piste en choisissant sa visibilité.
func insertTrackVisibility(t *testing.T, pool *pgxpool.Pool, userID, title, artist string, isPublic bool) string {
	t.Helper()
	var id string
	var artistArg any
	if artist != "" {
		artistArg = artist
	}
	err := pool.QueryRow(context.Background(),
		`INSERT INTO tracks (user_id, title, artist, file_path, mime_type, file_size, is_public)
		 VALUES ($1, $2, $3, $4, 'audio/mpeg', 1024, $5) RETURNING id`,
		userID, title, artistArg, "/dev/null/"+title, isPublic,
	).Scan(&id)
	if err != nil {
		t.Fatalf("integration: insertion piste %s: %v", title, err)
	}
	return id
}

// TestRecommend_PistesPubliquesDesTiers : une piste PUBLIQUE d'un autre
// utilisateur est recommandée (avec from_others=true), une piste PRIVÉE d'un
// tiers ne l'est jamais.
func TestRecommend_PistesPubliquesDesTiers(t *testing.T) {
	pool := pgtest.Pool(t)
	repo := NewRepository(pool)
	ctx := context.Background()

	moi := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"moi", "user")
	autre := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t)+"autre", "user")

	mienne := insertTrack(t, pool, moi, "La mienne", "Artiste M")
	publiqueTiers := insertTrackVisibility(t, pool, autre, "Publique du tiers", "Artiste P", true)
	priveeTiers := insertTrackVisibility(t, pool, autre, "Privée du tiers", "Artiste P", false)

	got, err := repo.Recommend(ctx, moi, 20)
	if err != nil {
		t.Fatalf("Recommend: %v", err)
	}

	ids := map[string]ScoredTrack{}
	for _, s := range got {
		ids[s.ID] = s
	}
	if _, ok := ids[mienne]; !ok {
		t.Error("ma propre piste doit être recommandée")
	}
	pub, ok := ids[publiqueTiers]
	if !ok {
		t.Fatal("la piste publique d'un tiers doit être recommandée")
	}
	if !pub.FromOthers {
		t.Error("la piste publique d'un tiers doit porter from_others=true")
	}
	if _, ok := ids[priveeTiers]; ok {
		t.Error("la piste PRIVÉE d'un tiers ne doit jamais être recommandée")
	}
}

// TestRecommend_ColdStart : sans aucun historique, l'endpoint doit rendre les
// pistes du demandeur (toutes « jamais écoutées ») plutôt qu'une liste vide.
func TestRecommend_ColdStart(t *testing.T) {
	pool := pgtest.Pool(t)
	repo := NewRepository(pool)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "user")

	insertTrack(t, pool, userID, "A", "Artiste 1")
	insertTrack(t, pool, userID, "B", "")

	got, err := repo.Recommend(ctx, userID, 20)
	if err != nil {
		t.Fatalf("Recommend: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("len = %d, want 2", len(got))
	}
	for _, s := range got {
		if !s.NeverPlayed {
			t.Errorf("%s devrait être jamais écoutée en cold-start", s.Title)
		}
		if s.ArtistPlays != 0 {
			t.Errorf("%s: affinité = %d, want 0 en cold-start", s.Title, s.ArtistPlays)
		}
	}
}

// TestRecommend_AffinitéEtExclusion : après avoir écouté un titre d'un artiste,
// les autres titres NON écoutés de ce même artiste doivent remonter en tête, et
// le titre déjà écouté être marqué comme tel.
func TestRecommend_AffinitéEtExclusion(t *testing.T) {
	pool := pgtest.Pool(t)
	repo := NewRepository(pool)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "user")

	x1 := insertTrack(t, pool, userID, "X1", "Artiste X")
	x2 := insertTrack(t, pool, userID, "X2", "Artiste X") // même artiste, jamais écouté
	insertTrack(t, pool, userID, "Y1", "Artiste Y")       // autre artiste, jamais écouté
	insertTrack(t, pool, userID, "Z", "")                 // sans artiste

	// On écoute X1 trois fois → l'artiste X gagne en affinité (3 écoutes).
	for i := 0; i < 3; i++ {
		if err := repo.RecordPlay(ctx, userID, x1); err != nil {
			t.Fatalf("RecordPlay: %v", err)
		}
	}

	got, err := repo.Recommend(ctx, userID, 20)
	if err != nil {
		t.Fatalf("Recommend: %v", err)
	}
	if len(got) != 4 {
		t.Fatalf("len = %d, want 4", len(got))
	}

	// Tête de liste : X2 (jamais écouté + artiste le plus écouté).
	if got[0].ID != x2 {
		t.Errorf("première recommandation = %s (%q), want X2", got[0].ID, got[0].Title)
	}
	if got[0].ArtistPlays != 3 {
		t.Errorf("affinité de X2 = %d, want 3", got[0].ArtistPlays)
	}
	if !got[0].NeverPlayed {
		t.Error("X2 ne doit pas être marqué comme déjà écouté")
	}

	// X1, déjà écouté, doit être en fin (après toutes les jamais-écoutées) et marqué.
	last := got[len(got)-1]
	if last.ID != x1 {
		t.Errorf("dernière recommandation = %s, want X1 (déjà écouté)", last.ID)
	}
	if last.NeverPlayed {
		t.Error("X1 a été écouté : NeverPlayed doit être faux")
	}
}

// TestRecommend_RespecteLaLimite : la limite passée borne la liste.
func TestRecommend_RespecteLaLimite(t *testing.T) {
	pool := pgtest.Pool(t)
	repo := NewRepository(pool)
	ctx := context.Background()
	userID := pgtest.InsertUser(t, pool, pgtest.UniqueTag(t), "user")

	for _, title := range []string{"a", "b", "c", "d", "e"} {
		insertTrack(t, pool, userID, title, "Artiste")
	}

	got, err := repo.Recommend(ctx, userID, 2)
	if err != nil {
		t.Fatalf("Recommend: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("len = %d, want 2 (limite)", len(got))
	}
}
