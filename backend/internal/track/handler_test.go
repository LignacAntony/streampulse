package track

import (
	"bytes"
	"encoding/json"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/LignacAntony/streampulse/internal/auth"
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
