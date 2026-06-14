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

func TestHandler_Me_RequiresToken(t *testing.T) {
	h := NewHandler(&stubReader{}, &stubUpdater{})

	req := httptest.NewRequest(http.MethodGet, "/api/users/me", nil)
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret, http.HandlerFunc(h.Me)).ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d: %s", rec.Code, rec.Body)
	}
}
