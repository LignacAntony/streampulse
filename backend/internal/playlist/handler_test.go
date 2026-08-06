package playlist

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/LignacAntony/streampulse/internal/auth"
	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

const testSecret = "test-secret-which-is-at-least-32-bytes!!"

type stubService struct {
	createRet Playlist
	createErr error
	gotInput  CreateInput

	listRet []Playlist
	listErr error

	getRet Playlist
	getErr error

	updateRet      Playlist
	updateErr      error
	gotUpdateInput UpdateInput

	deleteErr error

	tracksRet []PlaylistTrack
	tracksErr error

	userTracksRet []Track
	userTracksErr error

	addRet     []PlaylistTrack
	addErr     error
	addCall    bool
	gotTrackID string

	removeErr  error
	removeCall bool

	reorderRet    []PlaylistTrack
	reorderErr    error
	reorderCall   bool
	gotTrackOrder []string

	gotID        string
	gotRequester string
}

func (s *stubService) CreatePlaylist(_ context.Context, in CreateInput) (Playlist, error) {
	s.gotInput = in
	s.gotRequester = in.UserID
	return s.createRet, s.createErr
}

func (s *stubService) ListPlaylists(_ context.Context, requesterID string) ([]Playlist, error) {
	s.gotRequester = requesterID
	return s.listRet, s.listErr
}

func (s *stubService) GetPlaylist(_ context.Context, id, requesterID string) (Playlist, error) {
	s.gotID = id
	s.gotRequester = requesterID
	return s.getRet, s.getErr
}

func (s *stubService) UpdatePlaylist(_ context.Context, id, requesterID string, in UpdateInput) (Playlist, error) {
	s.gotID = id
	s.gotRequester = requesterID
	s.gotUpdateInput = in
	return s.updateRet, s.updateErr
}

func (s *stubService) DeletePlaylist(_ context.Context, id, requesterID string) error {
	s.gotID = id
	s.gotRequester = requesterID
	return s.deleteErr
}

func (s *stubService) ListTracks(_ context.Context, id, requesterID string) ([]PlaylistTrack, error) {
	s.gotID = id
	s.gotRequester = requesterID
	return s.tracksRet, s.tracksErr
}

func (s *stubService) ListUserTracks(_ context.Context, requesterID string) ([]Track, error) {
	s.gotRequester = requesterID
	return s.userTracksRet, s.userTracksErr
}

func (s *stubService) AddTrack(_ context.Context, playlistID, trackID, requesterID string) ([]PlaylistTrack, error) {
	s.addCall = true
	s.gotID = playlistID
	s.gotTrackID = trackID
	s.gotRequester = requesterID
	return s.addRet, s.addErr
}

func (s *stubService) RemoveTrack(_ context.Context, playlistID, trackID, requesterID string) error {
	s.removeCall = true
	s.gotID = playlistID
	s.gotTrackID = trackID
	s.gotRequester = requesterID
	return s.removeErr
}

func (s *stubService) ReorderTracks(_ context.Context, playlistID, requesterID string, trackIDs []string) ([]PlaylistTrack, error) {
	s.reorderCall = true
	s.gotID = playlistID
	s.gotRequester = requesterID
	s.gotTrackOrder = trackIDs
	return s.reorderRet, s.reorderErr
}

const testUserID = "00000000-0000-0000-0000-000000000001"

// do exécute une requête à travers la vraie chaîne RequireAuth vers handler h.
// id, s'il est non vide, est posé comme path value {id}.
func do(t *testing.T, handler http.HandlerFunc, method, target, id, body string, withToken bool) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, target, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if id != "" {
		req.SetPathValue("id", id)
	}
	if withToken {
		token, err := auth.GenerateAccessToken(testUserID, "user", testSecret, time.Now().UTC())
		if err != nil {
			t.Fatalf("generate token: %v", err)
		}
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret, handler).ServeHTTP(rec, req)
	return rec
}

func TestCreate_OK(t *testing.T) {
	svc := &stubService{createRet: Playlist{ID: "p1", Name: "Rock", TrackCount: 0}}
	h := NewHandler(svc)

	rec := do(t, h.Create, http.MethodPost, "/api/playlists", "", `{"name":"Rock"}`, true)

	if rec.Code != http.StatusCreated {
		t.Fatalf("status: got %d, want 201", rec.Code)
	}
	if svc.gotInput.Name != "Rock" || svc.gotInput.UserID != testUserID {
		t.Errorf("input not forwarded: %+v", svc.gotInput)
	}
	var resp playlistResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.ID != "p1" || resp.TrackCount != 0 {
		t.Errorf("unexpected response: %+v", resp)
	}
}

func TestCreate_MissingName_400(t *testing.T) {
	h := NewHandler(&stubService{})
	rec := do(t, h.Create, http.MethodPost, "/api/playlists", "", `{}`, true)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status: got %d, want 400", rec.Code)
	}
}

func TestCreate_Unauthenticated_401(t *testing.T) {
	h := NewHandler(&stubService{})
	rec := do(t, h.Create, http.MethodPost, "/api/playlists", "", `{"name":"Rock"}`, false)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d, want 401", rec.Code)
	}
}

func TestCreate_DuplicateName_409(t *testing.T) {
	svc := &stubService{createErr: apperror.Conflict("une playlist porte déjà ce nom")}
	h := NewHandler(svc)
	rec := do(t, h.Create, http.MethodPost, "/api/playlists", "", `{"name":"Rock"}`, true)
	if rec.Code != http.StatusConflict {
		t.Fatalf("status: got %d, want 409", rec.Code)
	}
}

func TestList_OK(t *testing.T) {
	svc := &stubService{listRet: []Playlist{{ID: "p1", Name: "Rock", TrackCount: 3}}}
	h := NewHandler(svc)

	rec := do(t, h.List, http.MethodGet, "/api/playlists", "", "", true)
	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d, want 200", rec.Code)
	}
	var resp []playlistResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(resp) != 1 || resp[0].TrackCount != 3 {
		t.Errorf("unexpected response: %+v", resp)
	}
}

func TestGet_ThirdParty_404(t *testing.T) {
	svc := &stubService{getErr: apperror.NotFound("playlist not found")}
	h := NewHandler(svc)
	rec := do(t, h.Get, http.MethodGet, "/api/playlists/p1", "p1", "", true)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status: got %d, want 404", rec.Code)
	}
}

func TestUpdate_OK(t *testing.T) {
	svc := &stubService{updateRet: Playlist{ID: "p1", Name: "Jazz"}}
	h := NewHandler(svc)
	rec := do(t, h.Update, http.MethodPut, "/api/playlists/p1", "p1", `{"name":"Jazz"}`, true)
	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d, want 200", rec.Code)
	}
	if svc.gotID != "p1" || svc.gotUpdateInput.Name != "Jazz" {
		t.Errorf("input not forwarded: id=%q input=%+v", svc.gotID, svc.gotUpdateInput)
	}
}

func TestUpdate_DuplicateName_409(t *testing.T) {
	svc := &stubService{updateErr: apperror.Conflict("une playlist porte déjà ce nom")}
	h := NewHandler(svc)
	rec := do(t, h.Update, http.MethodPut, "/api/playlists/p1", "p1", `{"name":"Jazz"}`, true)
	if rec.Code != http.StatusConflict {
		t.Fatalf("status: got %d, want 409", rec.Code)
	}
}

func TestDelete_OK_204(t *testing.T) {
	svc := &stubService{}
	h := NewHandler(svc)
	rec := do(t, h.Delete, http.MethodDelete, "/api/playlists/p1", "p1", "", true)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status: got %d, want 204", rec.Code)
	}
	if svc.gotID != "p1" || svc.gotRequester != testUserID {
		t.Errorf("not scoped: id=%q requester=%q", svc.gotID, svc.gotRequester)
	}
}

func TestDelete_ThirdParty_404(t *testing.T) {
	svc := &stubService{deleteErr: apperror.NotFound("playlist not found")}
	h := NewHandler(svc)
	rec := do(t, h.Delete, http.MethodDelete, "/api/playlists/p1", "p1", "", true)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status: got %d, want 404", rec.Code)
	}
}

func TestListTracks_OK(t *testing.T) {
	artist := "Neon Lights"
	dur := 214
	svc := &stubService{tracksRet: []PlaylistTrack{
		{ID: "t1", Title: "Midnight Drive", Artist: &artist, DurationS: &dur, Position: 0},
	}}
	h := NewHandler(svc)
	rec := do(t, h.ListTracks, http.MethodGet, "/api/playlists/p1/tracks", "p1", "", true)
	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d, want 200", rec.Code)
	}
	var resp []trackResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(resp) != 1 || resp[0].Title != "Midnight Drive" || *resp[0].Artist != artist {
		t.Errorf("unexpected response: %+v", resp)
	}
}

const testTrackID = "00000000-0000-0000-0000-0000000000aa"

func TestAddTrack_OK_201(t *testing.T) {
	svc := &stubService{addRet: []PlaylistTrack{{ID: testTrackID, Title: "Midnight Drive", Position: 0}}}
	h := NewHandler(svc)

	rec := do(t, h.AddTrack, http.MethodPost, "/api/playlists/p1/tracks", "p1",
		`{"track_id":"`+testTrackID+`"}`, true)
	if rec.Code != http.StatusCreated {
		t.Fatalf("status: got %d, want 201", rec.Code)
	}
	if svc.gotID != "p1" || svc.gotTrackID != testTrackID || svc.gotRequester != testUserID {
		t.Errorf("not forwarded: id=%q track=%q requester=%q", svc.gotID, svc.gotTrackID, svc.gotRequester)
	}
	var resp []trackResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(resp) != 1 || resp[0].Position != 0 {
		t.Errorf("unexpected response: %+v", resp)
	}
}

func TestAddTrack_MissingTrackID_400(t *testing.T) {
	svc := &stubService{}
	h := NewHandler(svc)

	rec := do(t, h.AddTrack, http.MethodPost, "/api/playlists/p1/tracks", "p1", `{}`, true)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status: got %d, want 400", rec.Code)
	}
	if svc.addCall {
		t.Error("service must not be called without track_id")
	}
}

func TestAddTrack_AlreadyPresent_409(t *testing.T) {
	svc := &stubService{addErr: apperror.Conflict("cette piste est déjà dans la playlist")}
	h := NewHandler(svc)

	rec := do(t, h.AddTrack, http.MethodPost, "/api/playlists/p1/tracks", "p1",
		`{"track_id":"`+testTrackID+`"}`, true)
	if rec.Code != http.StatusConflict {
		t.Fatalf("status: got %d, want 409", rec.Code)
	}
}

func TestAddTrack_Unauthenticated_401(t *testing.T) {
	svc := &stubService{}
	h := NewHandler(svc)

	rec := do(t, h.AddTrack, http.MethodPost, "/api/playlists/p1/tracks", "p1",
		`{"track_id":"`+testTrackID+`"}`, false)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d, want 401", rec.Code)
	}
	if svc.addCall {
		t.Error("service must not be called without a token")
	}
}

func TestRemoveTrack_OK_204(t *testing.T) {
	svc := &stubService{}
	h := NewHandler(svc)

	rec := doTrack(t, h.RemoveTrack, http.MethodDelete,
		"/api/playlists/p1/tracks/"+testTrackID, "p1", testTrackID, "")
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status: got %d, want 204", rec.Code)
	}
	if svc.gotID != "p1" || svc.gotTrackID != testTrackID || svc.gotRequester != testUserID {
		t.Errorf("not scoped: id=%q track=%q requester=%q", svc.gotID, svc.gotTrackID, svc.gotRequester)
	}
}

func TestRemoveTrack_NotInPlaylist_404(t *testing.T) {
	svc := &stubService{removeErr: apperror.NotFound("track not found")}
	h := NewHandler(svc)

	rec := doTrack(t, h.RemoveTrack, http.MethodDelete,
		"/api/playlists/p1/tracks/"+testTrackID, "p1", testTrackID, "")
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status: got %d, want 404", rec.Code)
	}
}

func TestReorderTracks_OK(t *testing.T) {
	svc := &stubService{reorderRet: []PlaylistTrack{
		{ID: "t2", Title: "B", Position: 0},
		{ID: "t1", Title: "A", Position: 1},
	}}
	h := NewHandler(svc)

	rec := do(t, h.ReorderTracks, http.MethodPut, "/api/playlists/p1/tracks", "p1",
		`{"track_ids":["t2","t1"]}`, true)
	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d, want 200", rec.Code)
	}
	if len(svc.gotTrackOrder) != 2 || svc.gotTrackOrder[0] != "t2" {
		t.Errorf("order not forwarded: %+v", svc.gotTrackOrder)
	}
	var resp []trackResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(resp) != 2 || resp[0].ID != "t2" || resp[1].Position != 1 {
		t.Errorf("unexpected response: %+v", resp)
	}
}

func TestReorderTracks_MissingField_400(t *testing.T) {
	svc := &stubService{}
	h := NewHandler(svc)

	rec := do(t, h.ReorderTracks, http.MethodPut, "/api/playlists/p1/tracks", "p1", `{}`, true)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status: got %d, want 400", rec.Code)
	}
	if svc.reorderCall {
		t.Error("service must not be called without track_ids")
	}
}

func TestReorderTracks_StaleOrder_409(t *testing.T) {
	svc := &stubService{reorderErr: apperror.Conflict("l'ordre fourni ne correspond plus à la playlist")}
	h := NewHandler(svc)

	rec := do(t, h.ReorderTracks, http.MethodPut, "/api/playlists/p1/tracks", "p1",
		`{"track_ids":["t1"]}`, true)
	if rec.Code != http.StatusConflict {
		t.Fatalf("status: got %d, want 409", rec.Code)
	}
}

func TestListUserTracks_OK(t *testing.T) {
	artist := "Neon Lights"
	svc := &stubService{userTracksRet: []Track{{ID: testTrackID, Title: "Midnight Drive", Artist: &artist}}}
	h := NewHandler(svc)

	rec := do(t, h.ListUserTracks, http.MethodGet, "/api/tracks", "", "", true)
	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d, want 200", rec.Code)
	}
	if svc.gotRequester != testUserID {
		t.Errorf("requester: got %q, want %q", svc.gotRequester, testUserID)
	}
	var resp []libraryTrackResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(resp) != 1 || resp[0].Title != "Midnight Drive" || resp[0].DurationS != nil {
		t.Errorf("unexpected response: %+v", resp)
	}
}

func TestListUserTracks_EmptyLibrary_ReturnsEmptyArray(t *testing.T) {
	h := NewHandler(&stubService{})

	rec := do(t, h.ListUserTracks, http.MethodGet, "/api/tracks", "", "", true)
	if body := strings.TrimSpace(rec.Body.String()); body != "[]" {
		t.Errorf("body: got %q, want %q", body, "[]")
	}
}

// doTrack exécute une requête authentifiée portant les deux path values
// {id} et {trackId} (routes .../tracks/{trackId}).
func doTrack(t *testing.T, handler http.HandlerFunc, method, target, id, trackID, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, target, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.SetPathValue("id", id)
	req.SetPathValue("trackId", trackID)
	token, err := auth.GenerateAccessToken(testUserID, "user", testSecret, time.Now().UTC())
	if err != nil {
		t.Fatalf("generate token: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret, handler).ServeHTTP(rec, req)
	return rec
}
