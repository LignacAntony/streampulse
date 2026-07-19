package streaming

import (
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
)

// TestNewMaxInFlight_RejetAuDelaDeLaLimite : limite 1 partagée, une requête
// bloquée dans le handler → la 2e reçoit 503 + Retry-After, puis le slot
// libéré resert normalement.
func TestNewMaxInFlight_RejetAuDelaDeLaLimite(t *testing.T) {
	entered := make(chan struct{})
	var enteredOnce sync.Once
	release := make(chan struct{})
	mw := NewMaxInFlight(1)
	h := mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		enteredOnce.Do(func() { close(entered) })
		<-release
		w.WriteHeader(http.StatusOK)
	}))

	var wg sync.WaitGroup
	wg.Add(1)
	first := httptest.NewRecorder()
	go func() {
		defer wg.Done()
		h.ServeHTTP(first, httptest.NewRequest(http.MethodGet, "/x", nil))
	}()
	<-entered // la 1re requête occupe le seul slot

	second := httptest.NewRecorder()
	h.ServeHTTP(second, httptest.NewRequest(http.MethodGet, "/x", nil))
	if second.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, attendu 503", second.Code)
	}
	if got := second.Header().Get("Retry-After"); got != "2" {
		t.Fatalf("Retry-After = %q, attendu \"2\"", got)
	}

	close(release)
	wg.Wait()
	if first.Code != http.StatusOK {
		t.Fatalf("première requête = %d, attendu 200", first.Code)
	}

	third := httptest.NewRecorder()
	h.ServeHTTP(third, httptest.NewRequest(http.MethodGet, "/x", nil))
	if third.Code != http.StatusOK {
		t.Fatalf("après libération = %d, attendu 200", third.Code)
	}
}

// TestNewMaxInFlight_BudgetPartage : deux handlers enveloppés par la même
// instance partagent le budget (celui des routes playlist + segments).
func TestNewMaxInFlight_BudgetPartage(t *testing.T) {
	entered := make(chan struct{})
	release := make(chan struct{})
	mw := NewMaxInFlight(1)
	blocking := mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		close(entered)
		<-release
		w.WriteHeader(http.StatusOK)
	}))
	other := mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		blocking.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/a", nil))
	}()
	<-entered
	defer func() { close(release); wg.Wait() }()

	rec := httptest.NewRecorder()
	other.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/b", nil))
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, attendu 503 (budget partagé)", rec.Code)
	}
}

// TestNewMaxInFlight_Desactive : limit <= 0 → passthrough sans borne.
func TestNewMaxInFlight_Desactive(t *testing.T) {
	mw := NewMaxInFlight(0)
	h := mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/x", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, attendu 200", rec.Code)
	}
}
