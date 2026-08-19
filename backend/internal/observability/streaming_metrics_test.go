package observability

import (
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/testutil"
)

func TestStreamingMetrics_CountsHLSRequestsPerStream(t *testing.T) {
	reg := prometheus.NewRegistry()
	m := NewStreamingMetrics(reg)

	m.RecordHLSRequest("stream-a", "playlist", "200")
	m.RecordHLSRequest("stream-a", "playlist", "200")
	m.RecordHLSRequest("stream-a", "segment", "404")
	m.RecordHLSRequest("stream-b", "playlist", "200")

	expected := `
		# HELP streampulse_hls_requests_total Requêtes de lecture HLS servies aux auditeurs, par flux.
		# TYPE streampulse_hls_requests_total counter
		streampulse_hls_requests_total{kind="playlist",status="200",stream_id="stream-a"} 2
		streampulse_hls_requests_total{kind="playlist",status="200",stream_id="stream-b"} 1
		streampulse_hls_requests_total{kind="segment",status="404",stream_id="stream-a"} 1
	`
	if err := testutil.GatherAndCompare(reg, strings.NewReader(expected), "streampulse_hls_requests_total"); err != nil {
		t.Fatalf("séries inattendues: %v", err)
	}
}

func TestStreamingMetrics_ForgetStreamDropsSeries(t *testing.T) {
	reg := prometheus.NewRegistry()
	m := NewStreamingMetrics(reg)

	m.RecordHLSRequest("stream-a", "playlist", "200")
	m.RecordHLSRequest("stream-a", "segment", "200")
	m.RecordHLSRequest("stream-b", "playlist", "200")

	m.ForgetStream("stream-a")

	// Sans cet oubli, chaque diffusion terminée laisserait ses séries
	// derrière elle et la cardinalité croîtrait sans borne (ADR 022).
	got := testutil.CollectAndCount(m.requests)
	if got != 1 {
		t.Fatalf("séries restantes = %d, want 1 (seul stream-b)", got)
	}
	families, err := reg.Gather()
	if err != nil {
		t.Fatalf("gather: %v", err)
	}
	for _, f := range families {
		for _, metric := range f.GetMetric() {
			for _, l := range metric.GetLabel() {
				if l.GetName() == "stream_id" && l.GetValue() == "stream-a" {
					t.Errorf("série de stream-a encore exposée: %v", metric)
				}
			}
		}
	}
}

func TestStreamingMetrics_ActiveStreamsGaugeReadsLiveState(t *testing.T) {
	reg := prometheus.NewRegistry()
	active := 0
	RegisterLiveStreamsGauge(reg, func() int { return active })

	expectGauge := func(want float64) {
		t.Helper()
		expected := `
			# HELP streampulse_live_streams_active Nombre de flux actuellement en direct.
			# TYPE streampulse_live_streams_active gauge
			streampulse_live_streams_active ` + trimFloat(want) + `
		`
		if err := testutil.GatherAndCompare(reg, strings.NewReader(expected), "streampulse_live_streams_active"); err != nil {
			t.Fatalf("gauge inattendue: %v", err)
		}
	}

	expectGauge(0)
	// La gauge lit l'état réel à chaque scrape : aucune dérive possible.
	active = 3
	expectGauge(3)
	active = 1
	expectGauge(1)
}

// trimFloat rend un float64 dans la notation courte du format texte Prometheus
// (0, 1, 3 — pas 0.000000), pour composer les fixtures attendues.
//
// L'implémentation précédente enchaînait un switch sur trois valeurs puis
// string(rune('0'+int(f))) : au-delà de 9 elle produisait ':' ou ';' au lieu
// d'un nombre, et gosec la signalait (G115, conversion int -> rune non bornée).
// strconv.FormatFloat fait le même travail sans borne implicite.
func trimFloat(f float64) string {
	return strconv.FormatFloat(f, 'g', -1, 64)
}

func TestStreamingMetrics_ForgetStreamDrainsInFlightRequests(t *testing.T) {
	// Une requête déjà en cours de service quand le flux s'arrête enregistre
	// sa métrique APRÈS ForgetStream : sans délai de drain, elle recréerait
	// une série que plus aucun arrêt ne viendrait nettoyer (revue PR #272).
	reg := prometheus.NewRegistry()
	m := NewStreamingMetrics(reg)
	m.drainDelay = 60 * time.Millisecond

	m.RecordHLSRequest("stream-a", "playlist", "200")
	m.ForgetStream("stream-a")

	// Requête en vol, terminée juste après l'arrêt.
	m.RecordHLSRequest("stream-a", "segment", "200")

	deadline := time.Now().Add(2 * time.Second)
	for {
		if testutil.CollectAndCount(m.requests) == 0 {
			return // séries drainées, y compris celle de la requête en vol
		}
		if time.Now().After(deadline) {
			t.Fatalf("séries encore présentes après le drain: %d", testutil.CollectAndCount(m.requests))
		}
		time.Sleep(10 * time.Millisecond)
	}
}
