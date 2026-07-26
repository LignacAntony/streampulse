package observability

import (
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

// StreamingMetrics implémente streaming.MetricsRecorder côté infrastructure
// (STR-166, ADR 022) : le domaine ne connaît que son interface étroite.
//
// Le label stream_id est volontairement porté par cette seule famille de
// séries — les métriques HTTP génériques (ADR 019) restent agrégées par
// pattern de route. Les séries d'un flux sont supprimées à son arrêt, si
// bien que la cardinalité active suit le nombre de directs simultanés.
type StreamingMetrics struct {
	requests *prometheus.CounterVec
}

// NewStreamingMetrics enregistre les métriques métier du streaming.
func NewStreamingMetrics(reg prometheus.Registerer) *StreamingMetrics {
	return &StreamingMetrics{
		requests: promauto.With(reg).NewCounterVec(prometheus.CounterOpts{
			Name: "streampulse_hls_requests_total",
			Help: "Requêtes de lecture HLS servies aux auditeurs, par flux.",
		}, []string{"stream_id", "kind", "status"}),
	}
}

// RecordHLSRequest compte une lecture HLS (kind = playlist|segment).
func (m *StreamingMetrics) RecordHLSRequest(streamID, kind, status string) {
	m.requests.WithLabelValues(streamID, kind, status).Inc()
}

// ForgetStream supprime toutes les séries d'un flux terminé.
func (m *StreamingMetrics) ForgetStream(streamID string) {
	m.requests.DeletePartialMatch(prometheus.Labels{"stream_id": streamID})
}

// RegisterLiveStreamsGauge expose le nombre de directs en cours. La valeur
// est lue à chaque scrape via le registre de sessions (GaugeFunc) plutôt
// qu'incrémentée/décrémentée : la métrique dérive de l'état réel et ne peut
// pas diverger, y compris si un flux meurt par un chemin imprévu (ADR 022).
func RegisterLiveStreamsGauge(reg prometheus.Registerer, count func() int) {
	promauto.With(reg).NewGaugeFunc(prometheus.GaugeOpts{
		Name: "streampulse_live_streams_active",
		Help: "Nombre de flux actuellement en direct.",
	}, func() float64 { return float64(count()) })
}
