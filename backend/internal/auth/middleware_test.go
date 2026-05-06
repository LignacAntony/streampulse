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
