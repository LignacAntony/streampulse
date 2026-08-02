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
