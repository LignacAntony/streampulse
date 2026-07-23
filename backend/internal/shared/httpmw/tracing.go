package httpmw

import (
	"net/http"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

// Tracing enveloppe le handler d'otelhttp (STR-164, ADR 020) : un span
// serveur par requête, nommé par le pattern de route du mux ("GET
// /api/streams/{id}") — même mécanique et même cardinalité bornée que le
// label des métriques. /health et /metrics ne sont pas tracés.
//
// À poser AU-DESSUS d'AccessLog dans main.go : le span doit exister quand le
// logger de requête est construit (champ trace_id).
func Tracing(mux *http.ServeMux, next http.Handler) http.Handler {
	return otelhttp.NewHandler(next, "http.server",
		otelhttp.WithSpanNameFormatter(func(_ string, r *http.Request) string {
			return methodLabel(r.Method) + " " + routePattern(mux, r)
		}),
		otelhttp.WithFilter(func(r *http.Request) bool {
			return !skipObservability(r.URL.Path)
		}),
	)
}
