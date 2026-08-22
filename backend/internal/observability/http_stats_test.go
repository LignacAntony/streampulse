package observability

import (
	"errors"
	"testing"

	"github.com/prometheus/client_golang/prometheus"
	dto "github.com/prometheus/client_model/go"
)

// seedHTTPMetrics remplit un registre comme le ferait httpmw.Metrics.
func seedHTTPMetrics(t *testing.T) *prometheus.Registry {
	t.Helper()
	reg := prometheus.NewRegistry()

	requests := prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: httpRequestsMetric, Help: ".",
	}, []string{"method", "path", "status"})
	bytesTotal := prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: httpResponseBytesMetric, Help: ".",
	}, []string{"path"})
	reg.MustRegister(requests, bytesTotal)

	requests.WithLabelValues("GET", "/api/streams", "200").Add(10)
	requests.WithLabelValues("GET", "/api/streams", "404").Add(3)
	requests.WithLabelValues("POST", "/api/streams", "500").Add(2)
	requests.WithLabelValues("GET", "/api/streams/{id}", "304").Add(5)
	bytesTotal.WithLabelValues("/api/streams").Add(4096)
	bytesTotal.WithLabelValues("/api/streams/{id}/segments/{segment}").Add(1_000_000)

	return reg
}

func TestHTTPStats_Totals(t *testing.T) {
	stats := NewHTTPStats(seedHTTPMetrics(t))

	got, err := stats.Totals()
	if err != nil {
		t.Fatalf("Totals: %v", err)
	}
	if got.Requests != 20 {
		t.Errorf("Requests = %d, want 20", got.Requests)
	}
	if got.ClientErrors != 3 {
		t.Errorf("ClientErrors = %d, want 3", got.ClientErrors)
	}
	if got.ServerErrors != 2 {
		t.Errorf("ServerErrors = %d, want 2", got.ServerErrors)
	}
	if got.ResponseBytes != 1_004_096 {
		t.Errorf("ResponseBytes = %d, want 1004096", got.ResponseBytes)
	}
}

// Un registre vide n'est pas une anomalie : au démarrage, aucune requête n'a
// encore été servie et les séries n'existent pas. Rendre une erreur ferait
// échouer le résumé admin pendant les premières secondes de vie du process.
func TestHTTPStats_EmptyRegistryIsNotAnError(t *testing.T) {
	got, err := NewHTTPStats(prometheus.NewRegistry()).Totals()
	if err != nil {
		t.Fatalf("Totals sur registre vide: %v", err)
	}
	if got != (HTTPTotals{}) {
		t.Errorf("Totals = %+v, want zéro", got)
	}
}

// Les collectors Go (go_goroutines, go_memstats_*) partagent le registre par
// défaut : le lecteur ne doit prendre que les deux familles qui le concernent.
func TestHTTPStats_IgnoresUnrelatedFamilies(t *testing.T) {
	reg := seedHTTPMetrics(t)
	reg.MustRegister(prometheus.NewCounter(prometheus.CounterOpts{
		Name: "un_autre_compteur_total", Help: ".",
	}))

	got, err := NewHTTPStats(reg).Totals()
	if err != nil {
		t.Fatalf("Totals: %v", err)
	}
	if got.Requests != 20 {
		t.Errorf("Requests = %d, want 20 (familles étrangères ignorées)", got.Requests)
	}
}

type failingGatherer struct{}

func (failingGatherer) Gather() ([]*dto.MetricFamily, error) {
	return nil, errors.New("registre indisponible")
}

func TestHTTPStats_PropagatesGatherError(t *testing.T) {
	if _, err := NewHTTPStats(failingGatherer{}).Totals(); err == nil {
		t.Fatal("une erreur de collecte doit remonter à l'appelant")
	}
}
