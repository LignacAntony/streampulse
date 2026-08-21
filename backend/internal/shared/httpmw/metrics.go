package httpmw

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

// otherLabel agrège tout ce qui sort des valeurs attendues (path hors table
// de routage, méthode exotique) — une requête forgée ne crée jamais de
// nouvelle série Prometheus (revue PR #268).
const otherLabel = "{other}"

// allowedMethods borne le label method : net/http accepte n'importe quel
// token HTTP comme méthode, un label brut serait à cardinalité infinie.
var allowedMethods = map[string]struct{}{
	http.MethodGet: {}, http.MethodHead: {}, http.MethodPost: {},
	http.MethodPut: {}, http.MethodPatch: {}, http.MethodDelete: {},
	http.MethodOptions: {},
}

// longLivedPatterns : routes tenues ouvertes pendant toute une session
// (SSE STR-77, push d'ingest STR-70). Comptées dans http_requests_total mais
// exclues de l'histogramme de latence — une unique observation de plusieurs
// minutes dans le bucket +Inf fausserait les p50/p95/p99 globaux.
var longLivedPatterns = map[string]struct{}{
	"/api/streams/{id}/events":         {},
	"/api/streams/ingest/{stream_key}": {},
}

// skipObservability : paths d'infrastructure jamais loggés ni métrés — le
// healthcheck compose (15 s) et le scrape Prometheus (15 s) noieraient le
// signal. Partagé par AccessLog et Metrics.
func skipObservability(path string) bool {
	return path == "/health" || path == "/metrics"
}

// methodLabel réduit la méthode HTTP à l'allowlist, sinon "other".
func methodLabel(m string) string {
	if _, ok := allowedMethods[m]; ok {
		return m
	}
	return "other"
}

// routePattern retourne le pattern de routage réellement matché par le mux
// (ex. "/api/streams/{id}") — mux.Handler n'exécute pas le handler et
// consulte la vraie table de main.go : pas de copie à synchroniser, valeurs
// dynamiques (UUID, stream_key) jamais présentes dans le label. Pattern vide
// (404, 405, redirections) → {other}.
func routePattern(mux *http.ServeMux, r *http.Request) string {
	_, pattern := mux.Handler(r)
	if pattern == "" {
		return otherLabel
	}
	// "GET /api/streams/{id}" → "/api/streams/{id}" (même règle que LoggablePath).
	if _, after, ok := strings.Cut(pattern, " "); ok {
		return after
	}
	return pattern
}

// Metrics instrumente chaque requête traversant le mux (STR-165, ADR 019) :
// http_requests_total{method,path,status} et
// http_request_duration_seconds{method,path} (buckets par défaut — p50/p95/p99
// via histogram_quantile côté Grafana). Prend le *http.ServeMux et non un
// http.Handler opaque : le label path est dérivé de la table de routage
// elle-même via mux.Handler(r). À composer au plus près du mux dans main.go
// (les préflights CORS ne sont pas comptés).
func Metrics(reg prometheus.Registerer, mux *http.ServeMux) http.Handler {
	requests := promauto.With(reg).NewCounterVec(prometheus.CounterOpts{
		Name: "http_requests_total",
		Help: "Nombre total de requêtes HTTP traitées.",
	}, []string{"method", "path", "status"})

	duration := promauto.With(reg).NewHistogramVec(prometheus.HistogramOpts{
		Name:    "http_request_duration_seconds",
		Help:    "Durée de traitement des requêtes HTTP en secondes.",
		Buckets: prometheus.DefBuckets,
	}, []string{"method", "path"})

	// Débit sortant (STR-244, ADR 041). Le volume écrit est déjà compté par le
	// statusRecorder pour l'access log : il ne restait qu'à le publier. Un seul
	// label `path` — la question posée est « quelle route transporte les octets »
	// (en pratique : les segments .ts), pas « avec quelle méthode ».
	//
	// Ce compteur mesure le sens serveur → auditeur. Le push d'ingest, lui, est
	// du volume ENTRANT : il traverse r.Body, que ce middleware n'enveloppe pas,
	// et n'est donc pas compté ici (cf. ADR 041 §2).
	responseBytes := promauto.With(reg).NewCounterVec(prometheus.CounterOpts{
		Name: "http_response_bytes_total",
		Help: "Octets de corps de réponse HTTP écrits vers les clients.",
	}, []string{"path"})

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if skipObservability(r.URL.Path) {
			mux.ServeHTTP(w, r)
			return
		}

		sr := &statusRecorder{ResponseWriter: w}
		start := time.Now()
		defer func() {
			// recover inconditionnel (même schéma qu'AccessLog) : une panic
			// survenue APRÈS WriteHeader doit être métrée 500, pas avec le
			// status déjà envoyé (revue PR #268).
			panicked := recover()
			status := sr.status
			switch {
			case panicked != nil:
				status = http.StatusInternalServerError
			case status == 0:
				status = http.StatusOK // handler muet → net/http répond 200
			}

			method := methodLabel(r.Method)
			pattern := routePattern(mux, r)
			requests.WithLabelValues(method, pattern, strconv.Itoa(status)).Inc()
			// Add et non Inc : sr.bytes est un volume, pas un événement. Une
			// réponse vide (204, 304) ajoute 0 mais crée quand même la série,
			// ce qui vaut mieux qu'un trou dans le graphe.
			responseBytes.WithLabelValues(pattern).Add(float64(sr.bytes))
			if _, longLived := longLivedPatterns[pattern]; !longLived {
				duration.WithLabelValues(method, pattern).Observe(time.Since(start).Seconds())
			}

			if panicked != nil {
				panic(panicked) // AccessLog loggue puis re-propage à net/http
			}
		}()

		mux.ServeHTTP(sr, r)
	})
}
