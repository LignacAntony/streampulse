package playlist

import (
	"context"
	"testing"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

// fakeRepo est une implémentation en mémoire de Repository pour les tests service.
type fakeRepo struct {
	createRet  Playlist
	createErr  error
	createCall bool
	gotCreate  CreateParams

	listRet []Playlist
	listErr error

	getRet Playlist
	getErr error

	updateRet  Playlist
	updateErr  error
	updateCall bool
	gotUpdate  UpdateParams

	deleteErr  error
	deleteCall bool
	gotDelID   string
	gotDelUser string

	tracksRet  []PlaylistTrack
	tracksErr  error
	tracksCall bool
}

func (f *fakeRepo) Create(_ context.Context, p CreateParams) (Playlist, error) {
	f.createCall = true
	f.gotCreate = p
	return f.createRet, f.createErr
}

func (f *fakeRepo) ListByUser(_ context.Context, _ string) ([]Playlist, error) {
	return f.listRet, f.listErr
}

func (f *fakeRepo) GetByID(_ context.Context, _ string) (Playlist, error) {
	return f.getRet, f.getErr
}

func (f *fakeRepo) Update(_ context.Context, p UpdateParams) (Playlist, error) {
	f.updateCall = true
	f.gotUpdate = p
	return f.updateRet, f.updateErr
}

func (f *fakeRepo) Delete(_ context.Context, id, userID string) error {
	f.deleteCall = true
	f.gotDelID = id
	f.gotDelUser = userID
	return f.deleteErr
}

func (f *fakeRepo) ListTracks(_ context.Context, _ string) ([]PlaylistTrack, error) {
	f.tracksCall = true
	return f.tracksRet, f.tracksErr
}

const (
	ownerID = "00000000-0000-0000-0000-000000000001"
	otherID = "00000000-0000-0000-0000-000000000002"
)

func TestCreatePlaylist_TrimsAndPersists(t *testing.T) {
	repo := &fakeRepo{createRet: Playlist{ID: "p1", Name: "Rock"}}
	svc := NewService(repo)

	_, err := svc.CreatePlaylist(context.Background(), CreateInput{UserID: ownerID, Name: "  Rock  "})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !repo.createCall {
		t.Fatal("expected repo.Create to be called")
	}
	if repo.gotCreate.Name != "Rock" {
		t.Errorf("name not trimmed: got %q", repo.gotCreate.Name)
	}
	if repo.gotCreate.UserID != ownerID {
		t.Errorf("user id: got %q", repo.gotCreate.UserID)
	}
}

func TestCreatePlaylist_EmptyName_InvalidArgument(t *testing.T) {
	repo := &fakeRepo{}
	svc := NewService(repo)

	_, err := svc.CreatePlaylist(context.Background(), CreateInput{UserID: ownerID, Name: "   "})
	if !apperror.IsCode(err, apperror.CodeInvalidArgument) {
		t.Fatalf("expected InvalidArgument, got %v", err)
	}
	if repo.createCall {
		t.Error("repo.Create must not be called on invalid input")
	}
}

func TestCreatePlaylist_DuplicateName_Conflict(t *testing.T) {
	repo := &fakeRepo{createErr: apperror.Conflict("une playlist porte déjà ce nom")}
	svc := NewService(repo)

	_, err := svc.CreatePlaylist(context.Background(), CreateInput{UserID: ownerID, Name: "Rock"})
	if !apperror.IsCode(err, apperror.CodeConflict) {
		t.Fatalf("expected Conflict, got %v", err)
	}
}

func TestGetPlaylist_ThirdParty_NotFound(t *testing.T) {
	repo := &fakeRepo{getRet: Playlist{ID: "p1", UserID: otherID}}
	svc := NewService(repo)

	_, err := svc.GetPlaylist(context.Background(), "p1", ownerID)
	if !apperror.IsCode(err, apperror.CodeNotFound) {
		t.Fatalf("expected NotFound, got %v", err)
	}
}

func TestUpdatePlaylist_EmptyName_InvalidArgument(t *testing.T) {
	repo := &fakeRepo{}
	svc := NewService(repo)

	_, err := svc.UpdatePlaylist(context.Background(), "p1", ownerID, UpdateInput{Name: ""})
	if !apperror.IsCode(err, apperror.CodeInvalidArgument) {
		t.Fatalf("expected InvalidArgument, got %v", err)
	}
	if repo.updateCall {
		t.Error("repo.Update must not be called on invalid input")
	}
}

func TestUpdatePlaylist_DuplicateName_Conflict(t *testing.T) {
	repo := &fakeRepo{updateErr: apperror.Conflict("une playlist porte déjà ce nom")}
	svc := NewService(repo)

	_, err := svc.UpdatePlaylist(context.Background(), "p1", ownerID, UpdateInput{Name: "Jazz"})
	if !apperror.IsCode(err, apperror.CodeConflict) {
		t.Fatalf("expected Conflict, got %v", err)
	}
	if repo.gotUpdate.UserID != ownerID {
		t.Errorf("update must be scoped to requester: got %q", repo.gotUpdate.UserID)
	}
}

func TestListTracks_ThirdParty_NotFound(t *testing.T) {
	repo := &fakeRepo{getRet: Playlist{ID: "p1", UserID: otherID}}
	svc := NewService(repo)

	_, err := svc.ListTracks(context.Background(), "p1", ownerID)
	if !apperror.IsCode(err, apperror.CodeNotFound) {
		t.Fatalf("expected NotFound, got %v", err)
	}
	if repo.tracksCall {
		t.Error("repo.ListTracks must not be called for a third-party playlist")
	}
}

func TestListTracks_Owner_ReturnsTracks(t *testing.T) {
	repo := &fakeRepo{
		getRet:    Playlist{ID: "p1", UserID: ownerID},
		tracksRet: []PlaylistTrack{{ID: "t1", Title: "Song", Position: 0}},
	}
	svc := NewService(repo)

	tracks, err := svc.ListTracks(context.Background(), "p1", ownerID)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(tracks) != 1 || tracks[0].Title != "Song" {
		t.Errorf("unexpected tracks: %+v", tracks)
	}
}

func TestDeletePlaylist_ScopedToRequester(t *testing.T) {
	repo := &fakeRepo{}
	svc := NewService(repo)

	if err := svc.DeletePlaylist(context.Background(), "p1", ownerID); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !repo.deleteCall || repo.gotDelID != "p1" || repo.gotDelUser != ownerID {
		t.Errorf("delete not scoped correctly: id=%q user=%q", repo.gotDelID, repo.gotDelUser)
	}
}
