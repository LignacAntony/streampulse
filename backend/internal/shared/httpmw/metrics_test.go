package httpmw

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/testutil"
)

func serve(mw http.Handler, path string) {
	req := httptest.NewRequest(http.MethodGet, path, nil)
	mw.ServeHTTP(httptest.NewRecorder(), req)
}

func TestMetrics_CountsRequestsWithLabels(t *testing.T) {
	reg := prometheus.NewRegistry()
	mw := Metrics(reg, statusHandler(http.StatusOK))

	req := httptest.NewRequest(http.MethodGet, "/api/streams", nil)
	mw.ServeHTTP(httptest.NewRecorder(), req)
	mw.ServeHTTP(httptest.NewRecorder(), req)

	expected := `
		# HELP http_requests_total Nombre total de requêtes HTTP traitées.
		# TYPE http_requests_total counter
		http_requests_total{method="GET",path="/api/streams",status="200"} 2
	`
	if err := testutil.GatherAndCompare(reg, strings.NewReader(expected), "http_requests_total"); err != nil {
		t.Fatalf("compteur inattendu: %v", err)
	}
}

func TestMetrics_ObservesDuration(t *testing.T) {
	reg := prometheus.NewRegistry()
	serve(Metrics(reg, statusHandler(http.StatusOK)), "/api/auth/login")

	families, err := reg.Gather()
	if err != nil {
		t.Fatalf("gather: %v", err)
	}
	for _, f := range families {
		if f.GetName() == "http_request_duration_seconds" {
			m := f.GetMetric()[0]
			if m.GetHistogram().GetSampleCount() != 1 {
				t.Errorf("sample_count = %d, want 1", m.GetHistogram().GetSampleCount())
			}
			return
		}
	}
	t.Fatal("histogramme http_request_duration_seconds absent")
}

func TestMetrics_NormalizesDynamicPaths(t *testing.T) {
	reg := prometheus.NewRegistry()
	mw := Metrics(reg, statusHandler(http.StatusOK))
	serve(mw, "/api/streams/3f2a8c1e-0b7d-4e2f-9a51-6c8d0e4b7f21")
	serve(mw, "/api/streams/autre-uuid-different")

	// Deux UUID différents → UNE seule série {id}.
	families, err := reg.Gather()
	if err != nil {
		t.Fatalf("gather: %v", err)
	}
	for _, f := range families {
		if f.GetName() == "http_requests_total" {
			if len(f.GetMetric()) != 1 {
				t.Fatalf("séries = %d, want 1 (cardinalité bornée)", len(f.GetMetric()))
			}
			if v := f.GetMetric()[0].GetCounter().GetValue(); v != 2 {
				t.Errorf("valeur série {id} = %v, want 2", v)
			}
			return
		}
	}
	t.Fatal("famille http_requests_total absente")
}

func TestMetrics_SkipsHealthAndMetrics(t *testing.T) {
	reg := prometheus.NewRegistry()
	mw := Metrics(reg, statusHandler(http.StatusOK))
	serve(mw, "/health")
	serve(mw, "/metrics")

	families, err := reg.Gather()
	if err != nil {
		t.Fatalf("gather: %v", err)
	}
	for _, f := range families {
		if f.GetName() == "http_requests_total" && len(f.GetMetric()) > 0 {
			t.Errorf("/health et /metrics ne doivent produire aucune série, got %v", f)
		}
	}
}
