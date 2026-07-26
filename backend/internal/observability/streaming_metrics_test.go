package observability

import (
	"strings"
	"testing"

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

func trimFloat(f float64) string {
	switch f {
	case 0:
		return "0"
	case 1:
		return "1"
	case 3:
		return "3"
	default:
		t := int(f)
		return string(rune('0' + t))
	}
}
