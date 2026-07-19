package auth

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func makeToken(t *testing.T, userID, role string, offset time.Duration) string {
	t.Helper()
	tok, err := GenerateAccessToken(userID, role, testSecret, time.Now().Add(offset))
	if err != nil {
		t.Fatalf("makeToken: %v", err)
	}
	return tok
}

var okHandler = http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
})

func TestRequireAuth_ValidToken(t *testing.T) {
	var gotID, gotRole string
	next := http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		gotID, _ = UserIDFromContext(r.Context())
		gotRole, _ = RoleFromContext(r.Context())
	})

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Authorization", "Bearer "+makeToken(t, "user-1", "broadcaster", time.Minute))
	RequireAuth(testSecret, next).ServeHTTP(httptest.NewRecorder(), req)

	if gotID != "user-1" || gotRole != "broadcaster" {
		t.Errorf("context = {%s, %s}, want {user-1, broadcaster}", gotID, gotRole)
	}
}

func TestRequireAuth_InvalidToken(t *testing.T) {
	cases := []struct{ name, header string }{
		{"missing", ""},
		{"no bearer prefix", makeToken(t, "u", "user", time.Minute)},
		{"expired", "Bearer " + makeToken(t, "u", "user", -AccessTokenDuration-time.Second)},
		{"wrong secret", "Bearer " + func() string {
			tok, _ := GenerateAccessToken("u", "user", "other-secret-key-32chars-long!!!!", time.Now())
			return tok
		}()},
		{"malformed", "Bearer garbage.token"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/", nil)
			if tc.header != "" {
				req.Header.Set("Authorization", tc.header)
			}
			rec := httptest.NewRecorder()
			RequireAuth(testSecret, okHandler).ServeHTTP(rec, req)
			if rec.Code != http.StatusUnauthorized {
				t.Errorf("want 401, got %d", rec.Code)
			}
		})
	}
}

func TestRequireRole_Hierarchy(t *testing.T) {
	cases := []struct {
		userRole string
		required string
		wantOK   bool
	}{
		{"admin", "admin", true},
		{"admin", "broadcaster", true},
		{"admin", "user", true},
		{"broadcaster", "broadcaster", true},
		{"broadcaster", "user", true},
		{"broadcaster", "admin", false},
		{"user", "user", true},
		{"user", "broadcaster", false},
		{"user", "admin", false},
	}

	for _, tc := range cases {
		t.Run(tc.userRole+">="+tc.required, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/", nil)
			req.Header.Set("Authorization", "Bearer "+makeToken(t, "u", tc.userRole, time.Minute))
			rec := httptest.NewRecorder()
			RequireAuth(testSecret, RequireRole(tc.required, okHandler)).ServeHTTP(rec, req)

			if tc.wantOK && rec.Code != http.StatusOK {
				t.Errorf("%s should access %s route, got %d", tc.userRole, tc.required, rec.Code)
			}
			if !tc.wantOK && rec.Code != http.StatusForbidden {
				t.Errorf("%s should be forbidden from %s route, got %d", tc.userRole, tc.required, rec.Code)
			}
		})
	}
}

func TestOptionalAuth_NoToken_Anonymous(t *testing.T) {
	var id string
	var present bool
	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id, present = UserIDFromContext(r.Context())
		w.WriteHeader(http.StatusOK)
	})

	req := httptest.NewRequest(http.MethodGet, "/", nil) // aucun header Authorization
	rec := httptest.NewRecorder()
	OptionalAuth(testSecret, next).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200 (anonyme laissé passer), got %d", rec.Code)
	}
	if present || id != "" {
		t.Errorf("anonyme attendu, got id=%q present=%v", id, present)
	}
}

func TestOptionalAuth_ValidToken_InjectsIdentity(t *testing.T) {
	var id, role string
	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id, _ = UserIDFromContext(r.Context())
		role, _ = RoleFromContext(r.Context())
		w.WriteHeader(http.StatusOK)
	})

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Authorization", "Bearer "+makeToken(t, "owner-1", "broadcaster", time.Minute))
	rec := httptest.NewRecorder()
	OptionalAuth(testSecret, next).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d", rec.Code)
	}
	if id != "owner-1" || role != "broadcaster" {
		t.Errorf("identité attendue {owner-1, broadcaster}, got {%s, %s}", id, role)
	}
}

func TestOptionalAuth_InvalidToken_Anonymous(t *testing.T) {
	var present bool
	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, present = UserIDFromContext(r.Context())
		w.WriteHeader(http.StatusOK)
	})

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Authorization", "Bearer not-a-valid-jwt")
	rec := httptest.NewRecorder()
	OptionalAuth(testSecret, next).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200 (token invalide -> anonyme, jamais 401), got %d", rec.Code)
	}
	if present {
		t.Error("token invalide doit être traité comme anonyme (pas d'identité)")
	}
}
