package recommendation

import (
	"context"
	"errors"
	"testing"
)

// fakeRepo est un Repository en mémoire pour les tests du service.
type fakeRepo struct {
	recorded []recordedPlay
	recErr   error

	scored   []ScoredTrack
	recoErr  error
	gotLimit int
}

type recordedPlay struct{ userID, trackID string }

func (f *fakeRepo) RecordPlay(_ context.Context, userID, trackID string) error {
	f.recorded = append(f.recorded, recordedPlay{userID, trackID})
	return f.recErr
}

func (f *fakeRepo) Recommend(_ context.Context, _ string, limit int) ([]ScoredTrack, error) {
	f.gotLimit = limit
	return f.scored, f.recoErr
}

func strptr(s string) *string { return &s }

func TestRecommendMapsReasons(t *testing.T) {
	repo := &fakeRepo{scored: []ScoredTrack{
		{ID: "1", Title: "A", Artist: strptr("Daft Punk"), ArtistPlays: 5, NeverPlayed: true},
		{ID: "2", Title: "B", Artist: strptr("Inconnu"), ArtistPlays: 0, NeverPlayed: true},
		{ID: "3", Title: "C", Artist: strptr("Inconnu"), ArtistPlays: 0, NeverPlayed: false},
		{ID: "4", Title: "D", Artist: nil, ArtistPlays: 3, NeverPlayed: true},
		// Piste publique d'un tiers, jamais écoutée, artiste sans affinité.
		{ID: "5", Title: "E", Artist: strptr("Autre"), ArtistPlays: 0, NeverPlayed: true, FromOthers: true},
	}}
	svc := NewService(repo)

	got, err := svc.Recommend(context.Background(), "user-1")
	if err != nil {
		t.Fatalf("Recommend: %v", err)
	}
	if len(got) != 5 {
		t.Fatalf("len = %d, want 5", len(got))
	}

	want := []string{
		"Parce que vous écoutez souvent Daft Punk",
		"Nouveauté de votre bibliothèque",
		"À réécouter",
		// artiste nil : l'affinité ne peut pas être nommée, on retombe sur la découverte.
		"Nouveauté de votre bibliothèque",
		// piste publique d'un tiers jamais écoutée -> découverte publique.
		"Découverte publique",
	}
	for i, w := range want {
		if got[i].Reason != w {
			t.Errorf("reason[%d] = %q, want %q", i, got[i].Reason, w)
		}
	}
	// Les champs de piste sont transmis tels quels.
	if got[0].ID != "1" || got[0].Title != "A" || got[0].Artist == nil || *got[0].Artist != "Daft Punk" {
		t.Errorf("track fields not passed through: %+v", got[0])
	}
}

func TestRecommendPassesDefaultLimit(t *testing.T) {
	repo := &fakeRepo{}
	svc := NewService(repo)
	if _, err := svc.Recommend(context.Background(), "user-1"); err != nil {
		t.Fatalf("Recommend: %v", err)
	}
	if repo.gotLimit != defaultLimit {
		t.Errorf("limit = %d, want %d", repo.gotLimit, defaultLimit)
	}
}

func TestRecommendPropagatesError(t *testing.T) {
	repo := &fakeRepo{recoErr: errors.New("boom")}
	svc := NewService(repo)
	if _, err := svc.Recommend(context.Background(), "user-1"); err == nil {
		t.Fatal("expected error, got nil")
	}
}

func TestRecommendEmpty(t *testing.T) {
	svc := NewService(&fakeRepo{scored: nil})
	got, err := svc.Recommend(context.Background(), "user-1")
	if err != nil {
		t.Fatalf("Recommend: %v", err)
	}
	if got == nil {
		t.Fatal("expected non-nil empty slice")
	}
	if len(got) != 0 {
		t.Errorf("len = %d, want 0", len(got))
	}
}

func TestRecordPlayDelegates(t *testing.T) {
	repo := &fakeRepo{}
	svc := NewService(repo)
	if err := svc.RecordPlay(context.Background(), "user-1", "track-9"); err != nil {
		t.Fatalf("RecordPlay: %v", err)
	}
	if len(repo.recorded) != 1 || repo.recorded[0] != (recordedPlay{"user-1", "track-9"}) {
		t.Errorf("recorded = %+v, want one (user-1, track-9)", repo.recorded)
	}
}

func TestRecordPlayPropagatesError(t *testing.T) {
	repo := &fakeRepo{recErr: errors.New("db down")}
	svc := NewService(repo)
	if err := svc.RecordPlay(context.Background(), "u", "t"); err == nil {
		t.Fatal("expected error, got nil")
	}
}
