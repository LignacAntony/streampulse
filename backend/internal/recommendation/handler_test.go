package recommendation

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/LignacAntony/streampulse/internal/auth"
)

const (
	testSecret = "test-secret-which-is-at-least-32-bytes!!"
	testUserID = "11111111-1111-1111-1111-111111111111"
)

// stubService satisfait RecommendationService sans base.
type stubService struct {
	recs []RecommendedTrack
	err  error
}

func (s stubService) Recommend(_ context.Context, _ string) ([]RecommendedTrack, error) {
	return s.recs, s.err
}

// do fait passer GET /api/recommendations/tracks par la vraie chaîne RequireAuth.
func do(t *testing.T, h *Handler, withToken bool) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/api/recommendations/tracks", nil)
	if withToken {
		token, err := auth.GenerateAccessToken(testUserID, "user", testSecret, time.Now().UTC())
		if err != nil {
			t.Fatalf("generate token: %v", err)
		}
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret, http.HandlerFunc(h.Recommend)).ServeHTTP(rec, req)
	return rec
}

func TestRecommendOK(t *testing.T) {
	artist := "Daft Punk"
	dur := 210
	h := NewHandler(stubService{recs: []RecommendedTrack{
		{ID: "1", Title: "One More Time", Artist: &artist, DurationS: &dur, Reason: "Parce que vous écoutez souvent Daft Punk"},
	}})

	rec := do(t, h, true)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body: %s)", rec.Code, rec.Body.String())
	}

	var got []map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("len = %d, want 1", len(got))
	}
	if got[0]["id"] != "1" || got[0]["title"] != "One More Time" {
		t.Errorf("unexpected track: %+v", got[0])
	}
	if got[0]["reason"] != "Parce que vous écoutez souvent Daft Punk" {
		t.Errorf("reason = %v", got[0]["reason"])
	}
	if got[0]["artist"] != "Daft Punk" {
		t.Errorf("artist = %v", got[0]["artist"])
	}
}

func TestRecommendEmptyReturnsArray(t *testing.T) {
	h := NewHandler(stubService{recs: nil})
	rec := do(t, h, true)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	// Jamais `null` : le client itère sur un tableau.
	if body := rec.Body.String(); body != "[]\n" && body != "[]" {
		t.Errorf("body = %q, want []", body)
	}
}

func TestRecommendServiceErrorIs500(t *testing.T) {
	h := NewHandler(stubService{err: errors.New("boom")})
	rec := do(t, h, true)
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", rec.Code)
	}
}

func TestRecommendUnauthenticated(t *testing.T) {
	h := NewHandler(stubService{})
	rec := do(t, h, false)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}
