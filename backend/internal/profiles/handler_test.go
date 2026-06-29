package profiles

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/LignacAntony/streampulse/internal/auth"
)

const testSecret = "test-secret-which-is-at-least-32-bytes!!"

type stubReader struct{ profile Profile }

func (s *stubReader) GetMe(_ context.Context, _ string) (Profile, error) { return s.profile, nil }

type stubUpdater struct{}

func (s *stubUpdater) UpdateMe(_ context.Context, _ string, _ UpdateProfileInput) (Profile, error) {
	return Profile{}, nil
}

func TestHandler_GetMe_OK(t *testing.T) {
	h := NewHandler(&stubReader{profile: Profile{ID: testUserID, Pseudo: "user1"}}, &stubUpdater{})

	token, err := auth.GenerateAccessToken(testUserID, "user", testSecret, time.Now().UTC())
	if err != nil {
		t.Fatalf("generate token: %v", err)
	}
	req := httptest.NewRequest(http.MethodGet, "/api/users/me", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret, http.HandlerFunc(h.Me)).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	if !strings.Contains(rec.Body.String(), `"pseudo":"user1"`) {
		t.Errorf("body missing pseudo: %s", rec.Body)
	}
}

func putMeRequest(t *testing.T, body string) *httptest.ResponseRecorder {
	t.Helper()
	h := NewHandler(&stubReader{}, &stubUpdater{})

	token, err := auth.GenerateAccessToken(testUserID, "user", testSecret, time.Now().UTC())
	if err != nil {
		t.Fatalf("generate token: %v", err)
	}
	req := httptest.NewRequest(http.MethodPut, "/api/users/me", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret, http.HandlerFunc(h.Me)).ServeHTTP(rec, req)
	return rec
}

func TestHandler_UpdateMe_MissingRequiredField(t *testing.T) {
	// notifications_enabled absent : ne doit pas être interprété comme false.
	body := `{"pseudo":"user1","bio":"hi","theme":"dark","audio_quality":"high"}`
	rec := putMeRequest(t, body)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d: %s", rec.Code, rec.Body)
	}
	if !strings.Contains(rec.Body.String(), "notifications_enabled") {
		t.Errorf("error should name the missing field: %s", rec.Body)
	}
}

func TestHandler_UpdateMe_AllFieldsOK(t *testing.T) {
	body := `{"pseudo":"user1","bio":"hi","theme":"dark","notifications_enabled":false,"audio_quality":"high"}`
	rec := putMeRequest(t, body)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Me_RequiresToken(t *testing.T) {
	h := NewHandler(&stubReader{}, &stubUpdater{})

	req := httptest.NewRequest(http.MethodGet, "/api/users/me", nil)
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret, http.HandlerFunc(h.Me)).ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d: %s", rec.Code, rec.Body)
	}
}
