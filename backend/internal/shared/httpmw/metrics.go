package httpmw

import (
	"net/http"
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

// Metrics instrumente chaque requête HTTP (STR-165, ADR 019) :
// http_requests_total{method,path,status} et
// http_request_duration_seconds{method,path} (buckets par défaut, suffisants
// pour p50/p95/p99 via histogram_quantile côté Grafana).
//
// Le label path passe par normalizePath — cardinalité bornée au nombre de
// routes. /health et /metrics sont exclus (healthcheck compose + scrape
// Prometheus pollueraient les séries), comme pour AccessLog. À enregistrer
// une seule fois, au plus près du mux dans main.go.
func Metrics(reg prometheus.Registerer, next http.Handler) http.Handler {
	requests := promauto.With(reg).NewCounterVec(prometheus.CounterOpts{
		Name: "http_requests_total",
		Help: "Nombre total de requêtes HTTP traitées.",
	}, []string{"method", "path", "status"})

	duration := promauto.With(reg).NewHistogramVec(prometheus.HistogramOpts{
		Name:    "http_request_duration_seconds",
		Help:    "Durée de traitement des requêtes HTTP en secondes.",
		Buckets: prometheus.DefBuckets,
	}, []string{"method", "path"})

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/health" || r.URL.Path == "/metrics" {
			next.ServeHTTP(w, r)
			return
		}

		sr := &statusRecorder{ResponseWriter: w}
		start := time.Now()
		defer func() {
			status := sr.status
			if status == 0 {
				// Handler sorti sans écrire (panic incluse) — net/http aurait
				// renvoyé 200 sur un retour normal, une panic coupe la connexion.
				status = http.StatusOK
				if p := recover(); p != nil {
					status = http.StatusInternalServerError
					defer panic(p) // re-propage après observation
				}
			}
			path := normalizePath(r.URL.Path)
			requests.WithLabelValues(r.Method, path, strconv.Itoa(status)).Inc()
			duration.WithLabelValues(r.Method, path).Observe(time.Since(start).Seconds())
		}()

		next.ServeHTTP(sr, r)
	})
}
