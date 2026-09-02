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

	addErr  error
	addCall bool
	gotAdd  AddTrackParams

	removeErr     error
	removeCall    bool
	gotRemoveID   string
	gotRemoveTrck string

	reorderErr   error
	reorderCall  bool
	gotReorderID string
	gotOrder     []string

	addFavErr     error
	addFavCall    bool
	gotAddFavID   string
	gotAddFavUser string

	removeFavErr     error
	removeFavCall    bool
	gotRemoveFavID   string
	gotRemoveFavUser string

	listFavRet []Playlist
	listFavErr error
}

func (f *fakeRepo) Create(_ context.Context, p CreateParams) (Playlist, error) {
	f.createCall = true
	f.gotCreate = p
	return f.createRet, f.createErr
}

func (f *fakeRepo) ListByUser(_ context.Context, _ string) ([]Playlist, error) {
	return f.listRet, f.listErr
}

func (f *fakeRepo) GetByID(_ context.Context, _, _ string) (Playlist, error) {
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

func (f *fakeRepo) AddTrack(_ context.Context, p AddTrackParams) error {
	f.addCall = true
	f.gotAdd = p
	return f.addErr
}

func (f *fakeRepo) RemoveTrack(_ context.Context, playlistID, trackID string) error {
	f.removeCall = true
	f.gotRemoveID = playlistID
	f.gotRemoveTrck = trackID
	return f.removeErr
}

func (f *fakeRepo) Reorder(_ context.Context, playlistID string, trackIDs []string) error {
	f.reorderCall = true
	f.gotReorderID = playlistID
	f.gotOrder = trackIDs
	return f.reorderErr
}

func (f *fakeRepo) AddFavorite(_ context.Context, userID, playlistID string) error {
	f.addFavCall = true
	f.gotAddFavUser = userID
	f.gotAddFavID = playlistID
	return f.addFavErr
}

func (f *fakeRepo) RemoveFavorite(_ context.Context, userID, playlistID string) error {
	f.removeFavCall = true
	f.gotRemoveFavUser = userID
	f.gotRemoveFavID = playlistID
	return f.removeFavErr
}

func (f *fakeRepo) ListFavorites(_ context.Context, _ string) ([]Playlist, error) {
	return f.listFavRet, f.listFavErr
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

func TestAddTrack_Owner_ForwardsRequesterAsTrackOwner(t *testing.T) {
	repo := &fakeRepo{
		getRet:    Playlist{ID: "p1", UserID: ownerID},
		tracksRet: []PlaylistTrack{{ID: "t1", Title: "Song", Position: 0}},
	}
	svc := NewService(repo)

	tracks, err := svc.AddTrack(context.Background(), "p1", "t1", ownerID)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if repo.gotAdd.UserID != ownerID || repo.gotAdd.TrackID != "t1" || repo.gotAdd.PlaylistID != "p1" {
		t.Errorf("params not forwarded: %+v", repo.gotAdd)
	}
	// La réponse porte l'ordre relu après insertion.
	if len(tracks) != 1 || tracks[0].Position != 0 {
		t.Errorf("unexpected tracks: %+v", tracks)
	}
}

func TestAddTrack_ThirdPartyPlaylist_NotFound(t *testing.T) {
	repo := &fakeRepo{getRet: Playlist{ID: "p1", UserID: otherID}}
	svc := NewService(repo)

	_, err := svc.AddTrack(context.Background(), "p1", "t1", ownerID)
	if !apperror.IsCode(err, apperror.CodeNotFound) {
		t.Fatalf("expected NotFound, got %v", err)
	}
	if repo.addCall {
		t.Error("repo.AddTrack must not be called for a third-party playlist")
	}
}

func TestRemoveTrack_ThirdPartyPlaylist_NotFound(t *testing.T) {
	repo := &fakeRepo{getRet: Playlist{ID: "p1", UserID: otherID}}
	svc := NewService(repo)

	err := svc.RemoveTrack(context.Background(), "p1", "t1", ownerID)
	if !apperror.IsCode(err, apperror.CodeNotFound) {
		t.Fatalf("expected NotFound, got %v", err)
	}
	if repo.removeCall {
		t.Error("repo.RemoveTrack must not be called for a third-party playlist")
	}
}

func TestRemoveTrack_Owner_ScopedToPlaylist(t *testing.T) {
	repo := &fakeRepo{getRet: Playlist{ID: "p1", UserID: ownerID}}
	svc := NewService(repo)

	if err := svc.RemoveTrack(context.Background(), "p1", "t1", ownerID); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if repo.gotRemoveID != "p1" || repo.gotRemoveTrck != "t1" {
		t.Errorf("remove not scoped: playlist=%q track=%q", repo.gotRemoveID, repo.gotRemoveTrck)
	}
}

func TestReorderTracks_Owner_PersistsOrder(t *testing.T) {
	repo := &fakeRepo{
		getRet: Playlist{ID: "p1", UserID: ownerID},
		tracksRet: []PlaylistTrack{
			{ID: "t2", Title: "B", Position: 0},
			{ID: "t1", Title: "A", Position: 1},
		},
	}
	svc := NewService(repo)

	tracks, err := svc.ReorderTracks(context.Background(), "p1", ownerID, []string{"t2", "t1"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if repo.gotReorderID != "p1" || len(repo.gotOrder) != 2 || repo.gotOrder[0] != "t2" {
		t.Errorf("order not forwarded: id=%q order=%+v", repo.gotReorderID, repo.gotOrder)
	}
	if len(tracks) != 2 || tracks[0].ID != "t2" {
		t.Errorf("unexpected tracks: %+v", tracks)
	}
}

func TestReorderTracks_Duplicate_InvalidArgument(t *testing.T) {
	repo := &fakeRepo{getRet: Playlist{ID: "p1", UserID: ownerID}}
	svc := NewService(repo)

	_, err := svc.ReorderTracks(context.Background(), "p1", ownerID, []string{"t1", "t1"})
	if !apperror.IsCode(err, apperror.CodeInvalidArgument) {
		t.Fatalf("expected InvalidArgument, got %v", err)
	}
	if repo.reorderCall {
		t.Error("repo.Reorder must not be called on a duplicated id")
	}
}

func TestReorderTracks_Empty_InvalidArgument(t *testing.T) {
	repo := &fakeRepo{getRet: Playlist{ID: "p1", UserID: ownerID}}
	svc := NewService(repo)

	_, err := svc.ReorderTracks(context.Background(), "p1", ownerID, nil)
	if !apperror.IsCode(err, apperror.CodeInvalidArgument) {
		t.Fatalf("expected InvalidArgument, got %v", err)
	}
	if repo.reorderCall {
		t.Error("repo.Reorder must not be called on an empty order")
	}
}

func TestReorderTracks_ThirdPartyPlaylist_NotFound(t *testing.T) {
	repo := &fakeRepo{getRet: Playlist{ID: "p1", UserID: otherID}}
	svc := NewService(repo)

	_, err := svc.ReorderTracks(context.Background(), "p1", ownerID, []string{"t1"})
	if !apperror.IsCode(err, apperror.CodeNotFound) {
		t.Fatalf("expected NotFound, got %v", err)
	}
	if repo.reorderCall {
		t.Error("repo.Reorder must not be called for a third-party playlist")
	}
}

func TestAddFavorite_Owner_Persists(t *testing.T) {
	repo := &fakeRepo{getRet: Playlist{ID: "p1", UserID: ownerID}}
	svc := NewService(repo)

	if err := svc.AddFavorite(context.Background(), "p1", ownerID); err != nil {
		t.Fatalf("AddFavorite: %v", err)
	}
	if !repo.addFavCall {
		t.Fatal("AddFavorite du repo non appelé")
	}
	if repo.gotAddFavUser != ownerID || repo.gotAddFavID != "p1" {
		t.Errorf("params = (%q,%q), want (%q,%q)", repo.gotAddFavUser, repo.gotAddFavID, ownerID, "p1")
	}
}

func TestAddFavorite_ThirdParty_NotFound(t *testing.T) {
	repo := &fakeRepo{getRet: Playlist{ID: "p1", UserID: otherID}}
	svc := NewService(repo)

	err := svc.AddFavorite(context.Background(), "p1", ownerID)
	if !apperror.IsCode(err, apperror.CodeNotFound) {
		t.Fatalf("err = %v, want NotFound", err)
	}
	if repo.addFavCall {
		t.Error("une playlist d'un tiers ne doit pas être favorisée")
	}
}

func TestRemoveFavorite_Idempotent(t *testing.T) {
	repo := &fakeRepo{}
	svc := NewService(repo)

	if err := svc.RemoveFavorite(context.Background(), "p1", ownerID); err != nil {
		t.Fatalf("RemoveFavorite: %v", err)
	}
	if !repo.removeFavCall || repo.gotRemoveFavUser != ownerID || repo.gotRemoveFavID != "p1" {
		t.Errorf("RemoveFavorite non transmis correctement: call=%v user=%q id=%q", repo.removeFavCall, repo.gotRemoveFavUser, repo.gotRemoveFavID)
	}
}

func TestListFavorites_Passthrough(t *testing.T) {
	repo := &fakeRepo{listFavRet: []Playlist{{ID: "p1", UserID: ownerID, IsFavorite: true}}}
	svc := NewService(repo)

	got, err := svc.ListFavorites(context.Background(), ownerID)
	if err != nil {
		t.Fatalf("ListFavorites: %v", err)
	}
	if len(got) != 1 || got[0].ID != "p1" || !got[0].IsFavorite {
		t.Errorf("got %+v, want la playlist favorite", got)
	}
}
