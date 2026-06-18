package httpmw

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func okHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
}

func TestCORS_PreflightShortCircuited(t *testing.T) {
	h := CORS(nil, true, okHandler())

	req := httptest.NewRequest(http.MethodOptions, "/api/users/me", nil)
	req.Header.Set("Origin", "http://127.0.0.1:5173")
	req.Header.Set("Access-Control-Request-Method", http.MethodGet)
	rec := httptest.NewRecorder()

	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("preflight status = %d, want %d", rec.Code, http.StatusNoContent)
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "http://127.0.0.1:5173" {
		t.Errorf("Allow-Origin = %q, want echoed dev origin", got)
	}
	if got := rec.Header().Get("Access-Control-Allow-Methods"); got != allowMethods {
		t.Errorf("Allow-Methods = %q, want %q", got, allowMethods)
	}
}

func TestCORS_DevAllowsLocalhostAnyPort(t *testing.T) {
	h := CORS(nil, true, okHandler())

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	req.Header.Set("Origin", "http://localhost:9999")
	rec := httptest.NewRecorder()

	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "http://localhost:9999" {
		t.Errorf("Allow-Origin = %q, want echoed origin", got)
	}
}

func TestCORS_ProdRejectsUnlistedOrigin(t *testing.T) {
	h := CORS([]string{"https://app.streampulse.dev"}, false, okHandler())

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	req.Header.Set("Origin", "http://localhost:5173")
	rec := httptest.NewRecorder()

	h.ServeHTTP(rec, req)

	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Errorf("Allow-Origin = %q, want empty (origin not allowed)", got)
	}
}

func TestCORS_ProdAllowsConfiguredOrigin(t *testing.T) {
	const origin = "https://app.streampulse.dev"
	h := CORS([]string{origin}, false, okHandler())

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	req.Header.Set("Origin", origin)
	rec := httptest.NewRecorder()

	h.ServeHTTP(rec, req)

	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != origin {
		t.Errorf("Allow-Origin = %q, want %q", got, origin)
	}
}

func TestCORS_NoOriginPassesThrough(t *testing.T) {
	h := CORS(nil, true, okHandler())

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()

	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Errorf("Allow-Origin = %q, want empty (no Origin header)", got)
	}
}
