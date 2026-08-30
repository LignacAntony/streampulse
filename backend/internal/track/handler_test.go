package track

import (
	"bytes"
	"encoding/json"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/LignacAntony/streampulse/internal/auth"
	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

const testSecret = "test-secret-which-is-at-least-32-bytes!!"

// upload construit une requête multipart POST /api/tracks et la fait passer par
// la vraie chaîne RequireAuth vers h.Upload. Un content nil omet la partie
// fichier (test « fichier manquant »).
func upload(t *testing.T, h *Handler, fields map[string]string, filename string, content []byte, withToken bool) *httptest.ResponseRecorder {
	t.Helper()
	body := &bytes.Buffer{}
	mw := multipart.NewWriter(body)
	for k, v := range fields {
		if err := mw.WriteField(k, v); err != nil {
			t.Fatalf("write field: %v", err)
		}
	}
	if content != nil {
		fw, err := mw.CreateFormFile("file", filename)
		if err != nil {
			t.Fatalf("create form file: %v", err)
		}
		if _, err := fw.Write(content); err != nil {
			t.Fatalf("write file: %v", err)
		}
	}
	if err := mw.Close(); err != nil {
		t.Fatalf("close writer: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "/api/tracks", body)
	req.Header.Set("Content-Type", mw.FormDataContentType())
	if withToken {
		token, err := auth.GenerateAccessToken(testUserID, "user", testSecret, time.Now().UTC())
		if err != nil {
			t.Fatalf("generate token: %v", err)
		}
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret, http.HandlerFunc(h.Upload)).ServeHTTP(rec, req)
	return rec
}

func TestUpload_OK(t *testing.T) {
	repo := &fakeRepo{}
	h := NewHandler(NewService(repo, &stubStorage{}))

	rec := upload(t, h, map[string]string{
		"title":      "Demo",
		"artist":     "Neon Lights",
		"duration_s": "200",
	}, "demo.mp3", mp3Header, true)

	if rec.Code != http.StatusCreated {
		t.Fatalf("status: got %d, want 201 (body=%s)", rec.Code, rec.Body.String())
	}
	var resp libraryTrackResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.Title != "Demo" {
		t.Errorf("title: got %q, want Demo", resp.Title)
	}
	if repo.gotCreate.MimeType != "audio/mpeg" {
		t.Errorf("mime: got %q, want audio/mpeg", repo.gotCreate.MimeType)
	}
	if repo.gotCreate.DurationS == nil || *repo.gotCreate.DurationS != 200 {
		t.Errorf("duration: got %v, want 200", repo.gotCreate.DurationS)
	}
}

// TestUpload_RejectsDisguisedFile est le test de sécurité : un PDF renommé en
// .mp3 doit être refusé en 415, rien n'est persisté.
func TestUpload_RejectsDisguisedFile(t *testing.T) {
	repo := &fakeRepo{}
	storage := &stubStorage{}
	h := NewHandler(NewService(repo, storage))

	rec := upload(t, h, map[string]string{"title": "Malware"}, "song.mp3", pdfHeader, true)

	if rec.Code != http.StatusUnsupportedMediaType {
		t.Fatalf("status: got %d, want 415 (body=%s)", rec.Code, rec.Body.String())
	}
	if storage.saveCalled || repo.createCalled {
		t.Error("nothing must be stored for a disguised file")
	}
}

// TestUpload_QuotaExceeded verrouille le contrat HTTP du dépassement de quota :
// 403 — et non 507 — avec le code public `storage_quota_exceeded`.
//
// Les deux comptent. Le statut range la réponse hors du bucket 5xx, donc hors
// des alertes : un utilisateur qui remplit son quota n'est pas un incident
// (ADR 032). Le code, lui, est publié dans openapi.yaml et permet au mobile de
// distinguer ce cas d'un refus d'accès banal — c'est ce que `PublicCode` porte
// depuis que le domaine ne fabrique plus de réponses HTTP lui-même.
func TestUpload_QuotaExceeded(t *testing.T) {
	repo := &fakeRepo{sumRet: MaxUserStorageBytes} // déjà au quota
	storage := &stubStorage{}
	h := NewHandler(NewService(repo, storage))

	rec := upload(t, h, map[string]string{"title": "Over quota"}, "song.mp3", mp3Header, true)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status: got %d, want 403 (body=%s)", rec.Code, rec.Body.String())
	}

	var body struct {
		Error struct {
			Code string `json:"code"`
		} `json:"error"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("réponse illisible: %v (body=%s)", err, rec.Body.String())
	}
	if body.Error.Code != "storage_quota_exceeded" {
		t.Errorf("code: got %q, want storage_quota_exceeded", body.Error.Code)
	}
	if storage.saveCalled || repo.createCalled {
		t.Error("nothing must be stored when quota is exceeded")
	}
}

func TestUpload_MissingFile(t *testing.T) {
	h := NewHandler(NewService(&fakeRepo{}, &stubStorage{}))

	rec := upload(t, h, map[string]string{"title": "Demo"}, "", nil, true)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status: got %d, want 400", rec.Code)
	}
}

// TestUpload_TooLarge abaisse la borne du handler pour éviter de forger 50 Mo :
// un fichier au-dessus de la limite renvoie 413.
func TestUpload_TooLarge(t *testing.T) {
	h := NewHandler(NewService(&fakeRepo{}, &stubStorage{}))
	h.maxUpload = 10 // octets

	rec := upload(t, h, map[string]string{"title": "Big"}, "big.mp3", mp3Header, true)

	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("status: got %d, want 413 (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestUpload_Unauthenticated(t *testing.T) {
	h := NewHandler(NewService(&fakeRepo{}, &stubStorage{}))

	rec := upload(t, h, map[string]string{"title": "Demo"}, "demo.mp3", mp3Header, false)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d, want 401", rec.Code)
	}
}

// streamTrack fait passer GET /api/tracks/{id}/stream par la vraie chaîne
// RequireAuth + ServeMux (le handler lit {id} via PathValue, qui n'est renseigné
// que par le routeur). rangeHeader vide = requête complète.
func streamTrack(t *testing.T, h *Handler, trackID, rangeHeader string, withToken bool) *httptest.ResponseRecorder {
	t.Helper()
	mux := http.NewServeMux()
	mux.Handle("GET /api/tracks/{id}/stream",
		auth.RequireAuth(testSecret, http.HandlerFunc(h.StreamTrack)))

	req := httptest.NewRequest(http.MethodGet, "/api/tracks/"+trackID+"/stream", nil)
	if rangeHeader != "" {
		req.Header.Set("Range", rangeHeader)
	}
	if withToken {
		token, err := auth.GenerateAccessToken(testUserID, "user", testSecret, time.Now().UTC())
		if err != nil {
			t.Fatalf("generate token: %v", err)
		}
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	return rec
}

func TestStreamTrack_OK(t *testing.T) {
	repo := &fakeRepo{fileRet: TrackFile{
		Path:     "/data/tracks/abc.mp3",
		MimeType: "audio/mpeg",
	}}
	storage := &stubStorage{openContent: mp3Header}
	h := NewHandler(NewService(repo, storage))

	rec := streamTrack(t, h, "abc", "", true)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d, want 200 (body=%s)", rec.Code, rec.Body.String())
	}
	if ct := rec.Header().Get("Content-Type"); ct != "audio/mpeg" {
		t.Errorf("content-type must come from the DB, got %q", ct)
	}
	if !bytes.Equal(rec.Body.Bytes(), mp3Header) {
		t.Error("the whole file must be served")
	}
	// Sans Accept-Ranges, le lecteur ne peut ni reprendre ni avancer dans la piste.
	if ar := rec.Header().Get("Accept-Ranges"); ar != "bytes" {
		t.Errorf("Accept-Ranges: got %q, want bytes", ar)
	}
	if cc := rec.Header().Get("Cache-Control"); cc != "private, no-store" {
		t.Errorf("Cache-Control: got %q, want private, no-store", cc)
	}
	if storage.openedFile == nil || !storage.openedFile.closed {
		t.Error("the served file must be closed (descriptor leak otherwise)")
	}
}

// TestStreamTrack_Range : le lecteur audio demande des tranches (reprise, avance).
func TestStreamTrack_Range(t *testing.T) {
	repo := &fakeRepo{fileRet: TrackFile{Path: "/p", MimeType: "audio/mpeg"}}
	h := NewHandler(NewService(repo, &stubStorage{openContent: mp3Header}))

	rec := streamTrack(t, h, "abc", "bytes=4-9", true)

	if rec.Code != http.StatusPartialContent {
		t.Fatalf("status: got %d, want 206 (body=%s)", rec.Code, rec.Body.String())
	}
	if got := rec.Body.Bytes(); !bytes.Equal(got, mp3Header[4:10]) {
		t.Errorf("body: got %v, want the requested slice", got)
	}
}

// TestStreamTrack_NotOwned : la piste d'un tiers renvoie 404 (jamais 403 : le
// code ne doit pas révéler qu'elle existe) et rien n'est lu sur le volume.
func TestStreamTrack_NotOwned(t *testing.T) {
	repo := &fakeRepo{fileErr: apperror.NotFound("track not found")}
	storage := &stubStorage{}
	h := NewHandler(NewService(repo, storage))

	rec := streamTrack(t, h, "abc", "", true)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status: got %d, want 404 (body=%s)", rec.Code, rec.Body.String())
	}
	if storage.openedPath != "" {
		t.Error("no file must be opened for a track the requester does not own")
	}
}

func TestStreamTrack_Unauthenticated(t *testing.T) {
	h := NewHandler(NewService(&fakeRepo{}, &stubStorage{}))

	rec := streamTrack(t, h, "abc", "", false)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d, want 401", rec.Code)
	}
}

func TestListUserTracks_OK(t *testing.T) {
	repo := &fakeRepo{listRet: []Track{{ID: "t1", Title: "Song", DurationS: ptr(120)}}}
	h := NewHandler(NewService(repo, &stubStorage{}))

	req := httptest.NewRequest(http.MethodGet, "/api/tracks", nil)
	token, _ := auth.GenerateAccessToken(testUserID, "user", testSecret, time.Now().UTC())
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret, http.HandlerFunc(h.ListUserTracks)).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d, want 200", rec.Code)
	}
	var resp []libraryTrackResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(resp) != 1 || resp[0].Title != "Song" {
		t.Errorf("unexpected response: %+v", resp)
	}
}

// --- Delete handler tests ---

func deleteTrack(t *testing.T, h *Handler, trackID string, withToken bool) *httptest.ResponseRecorder {
	t.Helper()
	mux := http.NewServeMux()
	mux.Handle("DELETE /api/tracks/{id}",
		auth.RequireAuth(testSecret, http.HandlerFunc(h.Delete)))

	req := httptest.NewRequest(http.MethodDelete, "/api/tracks/"+trackID, nil)
	if withToken {
		token, _ := auth.GenerateAccessToken(testUserID, "user", testSecret, time.Now().UTC())
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	return rec
}

func TestDelete_OK(t *testing.T) {
	repo := &fakeRepo{deleteFound: true, deleteFilePath: "/data/tracks/abc.mp3"}
	h := NewHandler(NewService(repo, &stubStorage{}))

	rec := deleteTrack(t, h, "track-1", true)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status: got %d, want 204 (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestDelete_NotFound(t *testing.T) {
	repo := &fakeRepo{deleteFound: false}
	h := NewHandler(NewService(repo, &stubStorage{}))

	rec := deleteTrack(t, h, "track-1", true)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status: got %d, want 404", rec.Code)
	}
}

func TestDelete_Unauthenticated(t *testing.T) {
	h := NewHandler(NewService(&fakeRepo{}, &stubStorage{}))
	rec := deleteTrack(t, h, "track-1", false)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d, want 401", rec.Code)
	}
}

// --- ListPublicTracks handler tests ---

func listPublicTracks(t *testing.T, h *Handler, query string, withToken bool) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/api/tracks/public"+query, nil)
	if withToken {
		token, _ := auth.GenerateAccessToken(testUserID, "user", testSecret, time.Now().UTC())
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	h.ListPublicTracks(rec, req)
	return rec
}

func TestListPublicTracks_OK(t *testing.T) {
	repo := &fakeRepo{publicTracks: []PublicTrack{
		{ID: "t1", Title: "Song", Artist: ptr("Neon"), DurationS: ptr(120), OwnerName: "Alice"},
	}}
	h := NewHandler(NewService(repo, &stubStorage{}))

	rec := listPublicTracks(t, h, "", true)
	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d, want 200 (body=%s)", rec.Code, rec.Body.String())
	}
	var resp []publicTrackResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(resp) != 1 || resp[0].Title != "Song" || resp[0].OwnerName != "Alice" {
		t.Errorf("unexpected response: %+v", resp)
	}
}

func TestListPublicTracks_InvalidCursorCreatedAt(t *testing.T) {
	h := NewHandler(NewService(&fakeRepo{}, &stubStorage{}))

	rec := listPublicTracks(t, h, "?cursor_id=00000000-0000-0000-0000-000000000001&cursor_created_at=bad", true)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status: got %d, want 400 (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestListPublicTracks_InvalidCursorID(t *testing.T) {
	h := NewHandler(NewService(&fakeRepo{}, &stubStorage{}))

	rec := listPublicTracks(t, h, "?cursor_id=notauuid&cursor_created_at=2026-01-01T00:00:00Z", true)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status: got %d, want 400 (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestListPublicTracks_ResponseContainsCreatedAt(t *testing.T) {
	repo := &fakeRepo{publicTracks: []PublicTrack{
		{ID: "t1", Title: "Song", OwnerName: "Alice", CreatedAt: time.Date(2026, 6, 15, 10, 0, 0, 0, time.UTC)},
	}}
	h := NewHandler(NewService(repo, &stubStorage{}))

	rec := listPublicTracks(t, h, "", true)
	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d, want 200", rec.Code)
	}
	var resp []struct {
		CreatedAt string `json:"created_at"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(resp) != 1 || resp[0].CreatedAt == "" {
		t.Fatalf("created_at must be present in response, got %+v", resp)
	}
}

// --- UpdateVisibility handler tests ---

func updateVisibility(t *testing.T, h *Handler, trackID, body string, withToken bool) *httptest.ResponseRecorder {
	t.Helper()
	mux := http.NewServeMux()
	mux.Handle("PATCH /api/tracks/{id}/visibility",
		auth.RequireAuth(testSecret, http.HandlerFunc(h.UpdateVisibility)))

	req := httptest.NewRequest(http.MethodPatch, "/api/tracks/"+trackID+"/visibility",
		strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if withToken {
		token, _ := auth.GenerateAccessToken(testUserID, "user", testSecret, time.Now().UTC())
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	return rec
}

func TestUpdateVisibility_OK(t *testing.T) {
	repo := &fakeRepo{visibilityUpdated: true}
	h := NewHandler(NewService(repo, &stubStorage{}))

	rec := updateVisibility(t, h, "track-1", `{"is_public":true}`, true)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status: got %d, want 204 (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestUpdateVisibility_MissingField(t *testing.T) {
	h := NewHandler(NewService(&fakeRepo{}, &stubStorage{}))

	rec := updateVisibility(t, h, "track-1", `{}`, true)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status: got %d, want 400 (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestUpdateVisibility_NotFound(t *testing.T) {
	repo := &fakeRepo{visibilityUpdated: false}
	h := NewHandler(NewService(repo, &stubStorage{}))

	rec := updateVisibility(t, h, "track-1", `{"is_public":false}`, true)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status: got %d, want 404 (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestUpdateVisibility_Unauthenticated(t *testing.T) {
	h := NewHandler(NewService(&fakeRepo{}, &stubStorage{}))

	rec := updateVisibility(t, h, "track-1", `{"is_public":true}`, false)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d, want 401", rec.Code)
	}
}
