package httpmw

import (
	"net/http"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

// untracedPatterns : routes dont le span serveur n'apporterait rien tout en
// restant ouvert pendant toute la session. Le push d'ingest tient la
// connexion du diffuseur des heures durant et ne touche jamais la base
// (AttachIngest est 100 % mémoire, ADR 015) : le span n'aurait aucun enfant
// à corréler et ne serait exporté qu'à la fin de la diffusion.
//
// Le SSE (/api/streams/{id}/events) reste tracé malgré sa durée : il
// interroge la base avant de streamer, et sans span serveur cette requête
// deviendrait une trace racine orpheline (revue PR #269).
var untracedPatterns = map[string]struct{}{
	"/api/streams/ingest/{stream_key}": {},
}

// Tracing enveloppe le handler d'otelhttp (STR-164, ADR 020) : un span
// serveur par requête, nommé par le pattern de route du mux ("GET
// /api/streams/{id}") — même mécanique et même cardinalité bornée que le
// label des métriques. /health, /metrics et le push d'ingest ne sont pas
// tracés.
//
// À poser AU-DESSUS d'AccessLog dans main.go : le span doit exister quand le
// logger de requête est construit (champ trace_id).
func Tracing(mux *http.ServeMux, next http.Handler) http.Handler {
	return otelhttp.NewHandler(next, "http.server",
		otelhttp.WithSpanNameFormatter(func(_ string, r *http.Request) string {
			return methodLabel(r.Method) + " " + routePattern(mux, r)
		}),
		otelhttp.WithFilter(func(r *http.Request) bool {
			if skipObservability(r.URL.Path) {
				return false
			}
			_, untraced := untracedPatterns[routePattern(mux, r)]
			return !untraced
		}),
	)
}
