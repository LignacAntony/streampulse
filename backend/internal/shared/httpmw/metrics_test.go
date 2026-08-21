package httpmw

import (
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/testutil"
)

// newTestMux reflète les formes de routes de main.go (statiques, segments
// dynamiques, method-scopées, longue durée) sans dupliquer sa table : le
// label path vient du pattern réellement matché par le ServeMux.
func newTestMux(h http.Handler) *http.ServeMux {
	mux := http.NewServeMux()
	mux.Handle("/api/auth/login", h)
	mux.Handle("GET /api/streams", h)
	mux.Handle("GET /api/streams/{id}", h)
	mux.Handle("GET /api/streams/{id}/playlist.m3u8", h)
	mux.Handle("GET /api/streams/{id}/events", h)
	mux.Handle("POST /api/streams/ingest/{stream_key}", h)
	mux.Handle("/health", h)
	mux.Handle("/metrics", h)
	return mux
}

func serve(mw http.Handler, method, path string) {
	req := httptest.NewRequest(method, path, nil)
	mw.ServeHTTP(httptest.NewRecorder(), req)
}

func gatherFamily(t *testing.T, reg *prometheus.Registry, name string) []map[string]string {
	t.Helper()
	families, err := reg.Gather()
	if err != nil {
		t.Fatalf("gather: %v", err)
	}
	var out []map[string]string
	for _, f := range families {
		if f.GetName() != name {
			continue
		}
		for _, m := range f.GetMetric() {
			labels := map[string]string{}
			for _, l := range m.GetLabel() {
				labels[l.GetName()] = l.GetValue()
			}
			out = append(out, labels)
		}
	}
	return out
}

// gatherSum agrège toutes les séries d'une famille de compteurs.
func gatherSum(t *testing.T, reg *prometheus.Registry, name string) float64 {
	t.Helper()
	families, err := reg.Gather()
	if err != nil {
		t.Fatalf("gather: %v", err)
	}
	for _, f := range families {
		if f.GetName() != name {
			continue
		}
		total := 0.0
		for _, m := range f.GetMetric() {
			total += m.GetCounter().GetValue()
		}
		return total
	}
	t.Fatalf("famille %s absente du registre", name)
	return 0
}

func TestMetrics_CountsWithRoutePatternLabels(t *testing.T) {
	reg := prometheus.NewRegistry()
	mw := Metrics(reg, newTestMux(statusHandler(http.StatusOK)))

	serve(mw, http.MethodGet, "/api/streams")
	serve(mw, http.MethodGet, "/api/streams")

	expected := `
		# HELP http_requests_total Nombre total de requêtes HTTP traitées.
		# TYPE http_requests_total counter
		http_requests_total{method="GET",path="/api/streams",status="200"} 2
	`
	if err := testutil.GatherAndCompare(reg, strings.NewReader(expected), "http_requests_total"); err != nil {
		t.Fatalf("compteur inattendu: %v", err)
	}
}

func TestMetrics_PathLabelIsBounded(t *testing.T) {
	reg := prometheus.NewRegistry()
	mw := Metrics(reg, newTestMux(statusHandler(http.StatusOK)))

	// Deux UUID différents → une seule série, labellisée par le pattern du mux.
	serve(mw, http.MethodGet, "/api/streams/3f2a8c1e-0b7d-4e2f-9a51-6c8d0e4b7f21")
	serve(mw, http.MethodGet, "/api/streams/un-autre-id")
	// Secret dans le path → seul le pattern apparaît.
	serve(mw, http.MethodPost, "/api/streams/ingest/SECRETKEY123")

	series := gatherFamily(t, reg, "http_requests_total")
	var byID, ingest int
	for _, labels := range series {
		switch labels["path"] {
		case "/api/streams/{id}":
			byID++
		case "/api/streams/ingest/{stream_key}":
			ingest++
		default:
			if strings.Contains(labels["path"], "SECRET") || strings.Contains(labels["path"], "3f2a8c1e") {
				t.Fatalf("valeur brute du path fuitée dans le label: %v", labels)
			}
		}
	}
	if byID != 1 || ingest != 1 {
		t.Errorf("séries {id}=%d ingest=%d, want 1 et 1 — %v", byID, ingest, series)
	}
}

func TestMetrics_UnknownPathsCollapseToOther(t *testing.T) {
	reg := prometheus.NewRegistry()
	mw := Metrics(reg, newTestMux(statusHandler(http.StatusOK)))

	serve(mw, http.MethodGet, "/wp-admin/setup.php")
	serve(mw, http.MethodGet, "/favicon.ico")
	serve(mw, http.MethodGet, "/api/streams/abc/route-inconnue")

	series := gatherFamily(t, reg, "http_requests_total")
	if len(series) != 1 || series[0]["path"] != "{other}" {
		t.Fatalf("paths inconnus doivent s'agréger en {other}: %v", series)
	}
}

func TestMetrics_MethodLabelIsAllowlisted(t *testing.T) {
	reg := prometheus.NewRegistry()
	mw := Metrics(reg, newTestMux(statusHandler(http.StatusOK)))

	// Méthodes exotiques distinctes (token HTTP valides pour net/http) — ne
	// doivent créer qu'UNE série method="other", sinon un bot fabrique une
	// série par requête.
	serve(mw, "A0", "/api/auth/login")
	serve(mw, "A1", "/api/auth/login")
	serve(mw, "PATCHX", "/api/auth/login")

	series := gatherFamily(t, reg, "http_requests_total")
	if len(series) != 1 || series[0]["method"] != "other" {
		t.Fatalf("méthodes hors allowlist doivent s'agréger en method=\"other\": %v", series)
	}
}

func TestMetrics_StatusLabelReflectsResponse(t *testing.T) {
	for _, status := range []int{http.StatusNotFound, http.StatusInternalServerError} {
		reg := prometheus.NewRegistry()
		mw := Metrics(reg, newTestMux(statusHandler(status)))
		serve(mw, http.MethodGet, "/api/streams")

		series := gatherFamily(t, reg, "http_requests_total")
		if len(series) != 1 || series[0]["status"] != strconv.Itoa(status) {
			t.Fatalf("status %d: séries %v", status, series)
		}
	}
}

func TestMetrics_PanicCountedAs500EvenAfterWriteHeader(t *testing.T) {
	panicAfterHeader := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK) // en-têtes déjà partis…
		panic("boom")                // …puis échec réel
	})
	reg := prometheus.NewRegistry()
	mw := Metrics(reg, newTestMux(panicAfterHeader))

	func() {
		defer func() {
			if p := recover(); p == nil {
				t.Fatal("la panic doit se re-propager après observation")
			}
		}()
		serve(mw, http.MethodGet, "/api/streams")
	}()

	series := gatherFamily(t, reg, "http_requests_total")
	if len(series) != 1 || series[0]["status"] != "500" {
		t.Fatalf("panic doit être métrée status=500 (même après WriteHeader): %v", series)
	}
}

func TestMetrics_LongLivedRoutesSkipDurationHistogram(t *testing.T) {
	reg := prometheus.NewRegistry()
	mw := Metrics(reg, newTestMux(statusHandler(http.StatusOK)))

	serve(mw, http.MethodGet, "/api/streams/42/events")            // SSE
	serve(mw, http.MethodPost, "/api/streams/ingest/SECRETKEY123") // push diffuseur
	serve(mw, http.MethodGet, "/api/streams")                      // requête normale

	// Comptées dans le counter…
	if got := len(gatherFamily(t, reg, "http_requests_total")); got != 3 {
		t.Errorf("counter: %d séries, want 3", got)
	}
	// …mais absentes de l'histogramme (une observation de plusieurs minutes
	// dans le bucket +Inf fausserait le p99 global — revue PR #268).
	for _, labels := range gatherFamily(t, reg, "http_request_duration_seconds") {
		if labels["path"] == "/api/streams/{id}/events" || labels["path"] == "/api/streams/ingest/{stream_key}" {
			t.Errorf("route longue durée observée dans l'histogramme: %v", labels)
		}
	}
}

func TestMetrics_SkipsHealthAndMetrics(t *testing.T) {
	reg := prometheus.NewRegistry()
	mw := Metrics(reg, newTestMux(statusHandler(http.StatusOK)))
	serve(mw, http.MethodGet, "/health")
	serve(mw, http.MethodGet, "/metrics")

	if series := gatherFamily(t, reg, "http_requests_total"); len(series) != 0 {
		t.Errorf("/health et /metrics ne doivent produire aucune série, got %v", series)
	}
}

// bodyHandler écrit un corps de taille fixe, pour vérifier que le compteur
// d'octets suit ce qui part réellement sur le réseau.
func bodyHandler(body string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(body))
	})
}

func TestMetrics_CountsResponseBytesByPath(t *testing.T) {
	reg := prometheus.NewRegistry()
	mw := Metrics(reg, newTestMux(bodyHandler("0123456789"))) // 10 octets

	serve(mw, http.MethodGet, "/api/streams")
	serve(mw, http.MethodGet, "/api/streams")

	expected := `
		# HELP http_response_bytes_total Octets de corps de réponse HTTP écrits vers les clients.
		# TYPE http_response_bytes_total counter
		http_response_bytes_total{path="/api/streams"} 20
	`
	if err := testutil.GatherAndCompare(reg, strings.NewReader(expected), "http_response_bytes_total"); err != nil {
		t.Fatalf("octets inattendus: %v", err)
	}
}

// Le débit doit être mesuré là où il compte : les segments HLS. Ils sont servis
// via un ReadSeeker (http.ServeContent) et non par un simple Write — si le
// recorder était contourné par une optimisation ReadFrom, le compteur resterait
// à zéro précisément sur la route qui transporte tout le volume.
func TestMetrics_CountsResponseBytesOnStreamedContent(t *testing.T) {
	reg := prometheus.NewRegistry()
	payload := strings.Repeat("A", 4096)
	h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.ServeContent(w, r, "seg_00001.ts", time.Time{}, strings.NewReader(payload))
	})
	mw := Metrics(reg, newTestMux(h))

	serve(mw, http.MethodGet, "/api/streams/abc/playlist.m3u8")

	for _, labels := range gatherFamily(t, reg, "http_response_bytes_total") {
		if labels["path"] != "/api/streams/{id}/playlist.m3u8" {
			t.Fatalf("série inattendue: %v", labels)
		}
	}
	if got := gatherSum(t, reg, "http_response_bytes_total"); got != float64(len(payload)) {
		t.Errorf("octets = %v, want %d", got, len(payload))
	}
}

// Une route de longue durée est exclue de l'histogramme de latence mais PAS du
// compteur d'octets : c'est justement sur ces routes que passe le volume.
func TestMetrics_ResponseBytesCoverLongLivedRoutes(t *testing.T) {
	reg := prometheus.NewRegistry()
	mw := Metrics(reg, newTestMux(bodyHandler("event: ended\n\n")))

	serve(mw, http.MethodGet, "/api/streams/42/events")

	series := gatherFamily(t, reg, "http_response_bytes_total")
	if len(series) != 1 || series[0]["path"] != "/api/streams/{id}/events" {
		t.Fatalf("la route SSE doit compter ses octets, got %v", series)
	}
}
