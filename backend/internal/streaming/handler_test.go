package streaming

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/LignacAntony/streampulse/internal/auth"
)

const (
	testSecret    = "test-secret-which-is-at-least-32-bytes!!"
	testUserID    = "00000000-0000-0000-0000-000000000001"
	testIngestURL = "http://localhost:8080"
)

type stubCreator struct {
	ret      Stream
	err      error
	called   bool
	gotInput CreateStreamInput
}

func (s *stubCreator) CreateStream(_ context.Context, in CreateStreamInput) (Stream, error) {
	s.called = true
	s.gotInput = in
	return s.ret, s.err
}

// doCreate exécute la requête à travers la chaîne réelle RequireAuth + RequireRole(broadcaster).
func doCreate(t *testing.T, h *Handler, method, role, body string, withToken bool) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, "/api/streams", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if withToken {
		token, err := auth.GenerateAccessToken(testUserID, role, testSecret, time.Now().UTC())
		if err != nil {
			t.Fatalf("generate token: %v", err)
		}
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret,
		auth.RequireRole("broadcaster", http.HandlerFunc(h.Create)),
	).ServeHTTP(rec, req)
	return rec
}

func TestHandler_Create_OK(t *testing.T) {
	stub := &stubCreator{ret: Stream{
		ID:        "s1",
		UserID:    testUserID,
		Title:     "Mon flux",
		Status:    StatusIdle,
		IsPublic:  true,
		StreamKey: "KEY123",
		CreatedAt: time.Now().UTC(),
	}}
	h := NewHandler(stub, testIngestURL)

	rec := doCreate(t, h, http.MethodPost, "broadcaster", `{"title":"Mon flux","is_public":true}`, true)

	if rec.Code != http.StatusCreated {
		t.Fatalf("want 201, got %d: %s", rec.Code, rec.Body)
	}
	if !stub.called {
		t.Fatal("service non appelé")
	}
	if stub.gotInput.UserID != testUserID || stub.gotInput.Title != "Mon flux" || !stub.gotInput.IsPublic {
		t.Errorf("input transmis = %+v", stub.gotInput)
	}
	body := rec.Body.String()
	for _, want := range []string{
		`"status":"idle"`,
		`"stream_key":"KEY123"`,
		`"stream_source_url":"http://localhost:8080/api/streams/ingest/KEY123"`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("body manque %s: %s", want, body)
		}
	}
}

func TestHandler_Create_MissingTitle(t *testing.T) {
	stub := &stubCreator{}
	h := NewHandler(stub, testIngestURL)

	rec := doCreate(t, h, http.MethodPost, "broadcaster", `{"is_public":true}`, true)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d: %s", rec.Code, rec.Body)
	}
	if !strings.Contains(rec.Body.String(), "title") {
		t.Errorf("erreur devrait nommer title: %s", rec.Body)
	}
	if stub.called {
		t.Error("service ne devrait pas être appelé")
	}
}

func TestHandler_Create_MissingIsPublic(t *testing.T) {
	h := NewHandler(&stubCreator{}, testIngestURL)
	rec := doCreate(t, h, http.MethodPost, "broadcaster", `{"title":"Mon flux"}`, true)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d: %s", rec.Code, rec.Body)
	}
	if !strings.Contains(rec.Body.String(), "is_public") {
		t.Errorf("erreur devrait nommer is_public: %s", rec.Body)
	}
}

func TestHandler_Create_UnknownField(t *testing.T) {
	h := NewHandler(&stubCreator{}, testIngestURL)
	rec := doCreate(t, h, http.MethodPost, "broadcaster", `{"title":"x","is_public":true,"foo":1}`, true)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Create_RequiresToken(t *testing.T) {
	h := NewHandler(&stubCreator{}, testIngestURL)
	rec := doCreate(t, h, http.MethodPost, "broadcaster", `{"title":"x","is_public":true}`, false)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Create_ForbiddenForUser(t *testing.T) {
	stub := &stubCreator{}
	h := NewHandler(stub, testIngestURL)

	rec := doCreate(t, h, http.MethodPost, "user", `{"title":"x","is_public":true}`, true)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("want 403, got %d: %s", rec.Code, rec.Body)
	}
	if stub.called {
		t.Error("service ne devrait pas être appelé pour un rôle insuffisant")
	}
}

func TestHandler_Create_MethodNotAllowed(t *testing.T) {
	h := NewHandler(&stubCreator{}, testIngestURL)
	rec := doCreate(t, h, http.MethodGet, "broadcaster", "", true)

	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("want 405, got %d: %s", rec.Code, rec.Body)
	}
}
