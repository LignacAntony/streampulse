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
	requests      *prometheus.CounterVec
	departures    prometheus.Counter
	interruptions *prometheus.CounterVec
	recoveries    prometheus.Counter
	outage        prometheus.Histogram
	drainDelay    time.Duration // injectable en test
}

// NewStreamingMetrics enregistre les métriques métier du streaming.
func NewStreamingMetrics(reg prometheus.Registerer) *StreamingMetrics {
	return &StreamingMetrics{
		requests: promauto.With(reg).NewCounterVec(prometheus.CounterOpts{
			Name: "streampulse_hls_requests_total",
			Help: "Requêtes de lecture HLS servies aux auditeurs, par flux.",
		}, []string{"stream_id", "kind", "status"}),

		// Départs d'auditeurs et interruptions de diffusion (STR-244, ADR 041) :
		// le versant « métier / expérience » que le sujet oppose aux 5xx.
		//
		// Ni l'un ni l'autre ne porte de stream_id, à la différence de la famille
		// ci-dessus. Un second porteur de ce label doublerait la surface de purge
		// que l'ADR 022 a mise en place pour borner la cardinalité, alors que le
		// détail par flux est déjà lisible sur streampulse_hls_requests_total.
		departures: promauto.With(reg).NewCounter(prometheus.CounterOpts{
			Name: "streampulse_listener_departures_total",
			Help: "Auditeurs dont la fenêtre d'activité HLS a expiré pendant que le flux diffusait encore.",
		}),
		interruptions: promauto.With(reg).NewCounterVec(prometheus.CounterOpts{
			Name: "streampulse_stream_interruptions_total",
			Help: "Diffusions terminées autrement que par un arrêt volontaire du diffuseur.",
		}, []string{"reason"}),

		// Le pendant *rétabli* des interruptions ci-dessus. Une coupure qui se
		// résorbe avant l'expiration du bail ne terminait aucune diffusion,
		// donc n'incrémentait rien : l'incident le plus fréquent en mobilité
		// était le seul à n'avoir aucun instrument.
		//
		// Deux séries plutôt qu'une : le compteur répond à « combien de fois ? »
		// et alimente une alerte sur la fréquence ; l'histogramme répond à
		// « combien de temps perdu ? », qui est ce que le diffuseur constate.
		// Une moyenne les confondrait.
		recoveries: promauto.With(reg).NewCounter(prometheus.CounterOpts{
			Name: "streampulse_ingest_recoveries_total",
			Help: "Coupures d'ingest rétablies avant l'expiration du bail (le diffuseur a retrouvé sa connexion).",
		}),
		// Bornes taillées sur le bail d'ingest (45 s par défaut) : au-delà, la
		// diffusion se termine et relève des interruptions, pas des reprises.
		outage: promauto.With(reg).NewHistogram(prometheus.HistogramOpts{
			Name:    "streampulse_ingest_outage_seconds",
			Help:    "Durée des coupures d'ingest rétablies : temps pendant lequel plus aucun audio n'était poussé.",
			Buckets: []float64{1, 2, 5, 10, 20, 30, 45},
		}),

		drainDelay: defaultDrainDelay,
	}
}

// RecordListenerDepartures compte n auditeurs sortis du suivi d'audience.
//
// C'est une estimation, comme le compte d'auditeurs dont elle dérive : HLS
// n'ayant pas de connexion persistante, un lecteur fermé proprement et un
// lecteur coupé par le réseau expirent exactement de la même façon. La métrique
// mesure donc des **départs**, pas des « déconnexions brutales » — l'inverse
// serait une affirmation que le protocole ne permet pas (ADR 041 §3).
func (m *StreamingMetrics) RecordListenerDepartures(n int) {
	if n <= 0 {
		return
	}
	m.departures.Add(float64(n))
}

// RecordStreamInterruption compte une diffusion qui s'est arrêtée sans que le
// diffuseur l'ait demandé.
func (m *StreamingMetrics) RecordStreamInterruption(reason string) {
	m.interruptions.WithLabelValues(reason).Inc()
}

// RecordIngestRecovery compte une coupure d'ingest rétablie et enregistre sa
// durée. Ni l'une ni l'autre ne porte de stream_id : ce serait un second
// porteur du label à purger, alors que l'ADR 022 en a délibérément gardé un
// seul.
func (m *StreamingMetrics) RecordIngestRecovery(outage time.Duration) {
	m.recoveries.Inc()
	m.outage.Observe(outage.Seconds())
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
