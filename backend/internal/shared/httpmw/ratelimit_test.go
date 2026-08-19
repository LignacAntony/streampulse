package httpmw

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func rateLimitTestHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
}

func do(h http.Handler, remote, forwarded string) *httptest.ResponseRecorder {
	return doPath(h, remote, forwarded, "/api/auth/login")
}

func doPath(h http.Handler, remote, forwarded, path string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, path, nil)
	req.RemoteAddr = remote
	if forwarded != "" {
		req.Header.Set("X-Forwarded-For", forwarded)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestRateLimit_RefuseAuDelaDeLaCapacite(t *testing.T) {
	rl := NewRateLimit(3, time.Second, false)
	h := rl.Middleware(rateLimitTestHandler())

	for i := range 3 {
		if rec := do(h, "192.0.2.10:1234", ""); rec.Code != http.StatusOK {
			t.Fatalf("requête %d: got %d, want 200", i+1, rec.Code)
		}
	}

	rec := do(h, "192.0.2.10:1234", "")
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("4e requête: got %d, want 429", rec.Code)
	}
	if rec.Header().Get("Retry-After") == "" {
		t.Error("Retry-After absent : le client ne sait pas quand réessayer")
	}
}

func TestRateLimit_IsoleLesClients(t *testing.T) {
	rl := NewRateLimit(1, time.Second, false)
	h := rl.Middleware(rateLimitTestHandler())

	if rec := do(h, "192.0.2.10:1", ""); rec.Code != http.StatusOK {
		t.Fatalf("client A: got %d, want 200", rec.Code)
	}
	if rec := do(h, "192.0.2.10:1", ""); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("client A épuisé: got %d, want 429", rec.Code)
	}
	// Un autre client ne doit pas payer pour le premier.
	if rec := do(h, "198.51.100.20:1", ""); rec.Code != http.StatusOK {
		t.Fatalf("client B: got %d, want 200", rec.Code)
	}
}

func TestRateLimit_SeauSeReconstitue(t *testing.T) {
	rl := NewRateLimit(1, 100*time.Millisecond, false)
	now := time.Now()
	rl.now = func() time.Time { return now }
	h := rl.Middleware(rateLimitTestHandler())

	if rec := do(h, "192.0.2.10:1", ""); rec.Code != http.StatusOK {
		t.Fatalf("1re: got %d, want 200", rec.Code)
	}
	if rec := do(h, "192.0.2.10:1", ""); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("2e immédiate: got %d, want 429", rec.Code)
	}

	now = now.Add(150 * time.Millisecond)
	if rec := do(h, "192.0.2.10:1", ""); rec.Code != http.StatusOK {
		t.Fatalf("après reconstitution: got %d, want 200", rec.Code)
	}
}

// TestRateLimit_ForgedForwardedForNeDonnePasUnSeauNeuf est le test de sécurité :
// un client qui varie X-Forwarded-For ne doit pas obtenir une clé différente à
// chaque requête, sinon le limiteur ne limite plus rien.
func TestRateLimit_ForgedForwardedForNeDonnePasUnSeauNeuf(t *testing.T) {
	rl := NewRateLimit(2, time.Minute, true) // derrière proxy
	h := rl.Middleware(rateLimitTestHandler())

	// Caddy transmet « valeur du client, IP réelle ». Le client forge la sienne.
	forged := []string{"1.2.3.4", "5.6.7.8", "9.10.11.12"}
	codes := make([]int, 0, len(forged))
	for _, f := range forged {
		codes = append(codes, do(h, "10.0.0.1:1", f+", 203.0.113.7").Code)
	}

	if codes[2] != http.StatusTooManyRequests {
		t.Errorf("3e requête avec un X-Forwarded-For forgé différent: got %d, want 429 — le limiteur est contournable", codes[2])
	}
}

func TestRateLimit_EvictionPurgeLesSeauxInactifs(t *testing.T) {
	rl := NewRateLimit(2, time.Second, false)
	now := time.Now()
	rl.now = func() time.Time { return now }
	h := rl.Middleware(rateLimitTestHandler())

	do(h, "192.0.2.10:1", "")
	if len(rl.buckets) != 1 {
		t.Fatalf("seaux: got %d, want 1", len(rl.buckets))
	}

	now = now.Add(time.Hour)
	rl.evict()
	if len(rl.buckets) != 0 {
		t.Errorf("après purge: got %d seaux, want 0 — la table croîtrait avec le nombre d'IP vues", len(rl.buckets))
	}
}

// TestRateLimit_IsoleLesRoutes : derrière un NAT, tous les utilisateurs
// partagent l'adresse publique. Si la clé ne portait que l'adresse, un
// renouvellement de jeton automatique assécherait le budget de la connexion pour
// tout le monde.
func TestRateLimit_IsoleLesRoutes(t *testing.T) {
	rl := NewRateLimit(1, time.Minute, false)
	h := rl.Middleware(rateLimitTestHandler())

	if rec := doPath(h, "192.0.2.10:1", "", "/api/auth/login"); rec.Code != http.StatusOK {
		t.Fatalf("login: got %d, want 200", rec.Code)
	}
	if rec := doPath(h, "192.0.2.10:1", "", "/api/auth/login"); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("login épuisé: got %d, want 429", rec.Code)
	}
	// Même adresse, autre route : budget distinct.
	if rec := doPath(h, "192.0.2.10:1", "", "/api/auth/register"); rec.Code != http.StatusOK {
		t.Errorf("register après épuisement de login: got %d, want 200 — les routes partagent un seau", rec.Code)
	}
}
