package observability

import (
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

// defaultDrainDelay laisse aux requêtes déjà en cours de service le temps de
// s'achever avant d'effacer les séries d'un flux arrêté : leur enregistrement
// différé recréerait sinon une série que plus aucun arrêt ne nettoierait
// (revue PR #272). Largement au-dessus du temps de service d'un segment.
const defaultDrainDelay = 30 * time.Second

// StreamingMetrics implémente streaming.MetricsRecorder côté infrastructure
// (STR-166, ADR 022) : le domaine ne connaît que son interface étroite.
//
// Le label stream_id est volontairement porté par cette seule famille de
// séries — les métriques HTTP génériques (ADR 019) restent agrégées par
// pattern de route. Les séries d'un flux sont supprimées à son arrêt, si
// bien que la cardinalité active suit le nombre de directs simultanés.
type StreamingMetrics struct {
	requests   *prometheus.CounterVec
	drainDelay time.Duration // injectable en test
}

// NewStreamingMetrics enregistre les métriques métier du streaming.
func NewStreamingMetrics(reg prometheus.Registerer) *StreamingMetrics {
	return &StreamingMetrics{
		requests: promauto.With(reg).NewCounterVec(prometheus.CounterOpts{
			Name: "streampulse_hls_requests_total",
			Help: "Requêtes de lecture HLS servies aux auditeurs, par flux.",
		}, []string{"stream_id", "kind", "status"}),
		drainDelay: defaultDrainDelay,
	}
}

// RecordHLSRequest compte une lecture HLS (kind = playlist|segment).
func (m *StreamingMetrics) RecordHLSRequest(streamID, kind, status string) {
	m.requests.WithLabelValues(streamID, kind, status).Inc()
}

// ForgetStream supprime les séries d'un flux terminé, après un délai de drain :
// une requête encore en vol au moment de l'arrêt enregistre sa métrique un
// instant plus tard, et la suppression doit passer après elle — sinon la série
// ressuscitée resterait orpheline (revue PR #272).
func (m *StreamingMetrics) ForgetStream(streamID string) {
	labels := prometheus.Labels{"stream_id": streamID}
	m.requests.DeletePartialMatch(labels) // effacement immédiat des séries connues
	time.AfterFunc(m.drainDelay, func() {
		m.requests.DeletePartialMatch(labels) // puis des retardataires
	})
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
