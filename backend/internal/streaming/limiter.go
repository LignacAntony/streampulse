package streaming

import (
	"net/http"

	"github.com/LignacAntony/streampulse/internal/shared/httpjson"
)

// NewMaxInFlight fabrique un middleware bornant le nombre de requêtes servies
// simultanément par TOUTES les routes qu'il enveloppe (budget partagé) — STR-88.
// Au-delà de limit : refus immédiat 503 + Retry-After, pas de file d'attente
// (sous un pic d'auditeurs, un refus net vaut mieux qu'une dégradation générale).
// limit <= 0 désactive la borne.
func NewMaxInFlight(limit int) func(http.Handler) http.Handler {
	if limit <= 0 {
		return func(next http.Handler) http.Handler { return next }
	}
	slots := make(chan struct{}, limit)
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			select {
			case slots <- struct{}{}:
				defer func() { <-slots }()
				next.ServeHTTP(w, r)
			default:
				w.Header().Set("Retry-After", "2")
				httpjson.WriteError(w, r, httpjson.StatusError(
					http.StatusServiceUnavailable, "server_overloaded",
					"too many concurrent listeners, retry later"))
			}
		})
	}
}
