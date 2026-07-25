package httpmw

import (
	"net/http"
	"testing"

	"go.opentelemetry.io/otel"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/sdk/trace/tracetest"
)

// spansFor exécute une requête à travers Tracing et retourne les spans exportés.
func spansFor(t *testing.T, method, path string) []string {
	t.Helper()
	exporter := tracetest.NewInMemoryExporter()
	tp := sdktrace.NewTracerProvider(sdktrace.WithSyncer(exporter))
	otel.SetTracerProvider(tp)
	t.Cleanup(func() {
		_ = tp.Shutdown(t.Context())
		otel.SetTracerProvider(nil)
	})

	mux := newTestMux(statusHandler(http.StatusOK))
	serve(Tracing(mux, mux), method, path)

	var names []string
	for _, s := range exporter.GetSpans() {
		names = append(names, s.Name)
	}
	return names
}

func TestTracing_NamesSpansByRoutePattern(t *testing.T) {
	spans := spansFor(t, http.MethodGet, "/api/streams/3f2a8c1e-0b7d-4e2f-9a51-6c8d0e4b7f21")

	if len(spans) != 1 || spans[0] != "GET /api/streams/{id}" {
		t.Fatalf("spans = %v, want [GET /api/streams/{id}] (pattern, pas l'UUID)", spans)
	}
}

func TestTracing_SkipsObservabilityPaths(t *testing.T) {
	for _, path := range []string{"/health", "/metrics"} {
		t.Run(path, func(t *testing.T) {
			if spans := spansFor(t, http.MethodGet, path); len(spans) != 0 {
				t.Errorf("%s ne doit produire aucun span, got %v", path, spans)
			}
		})
	}
}

func TestTracing_SkipsIngestPush(t *testing.T) {
	// L'ingest diffuseur reste ouvert toute la durée de la diffusion : un span
	// serveur y vivrait des heures avant export, pour une route qui ne fait
	// aucune requête SQL (AttachIngest est 100 % mémoire, ADR 015) — rien à
	// corréler, donc rien à tracer (revue PR #269).
	spans := spansFor(t, http.MethodPost, "/api/streams/ingest/SECRETKEY123")

	if len(spans) != 0 {
		t.Errorf("le push d'ingest ne doit pas être tracé, got %v", spans)
	}
}

func TestTracing_TracesSSEEvents(t *testing.T) {
	// À l'inverse, le SSE interroge la base avant de streamer (GetStream) :
	// sans span serveur cette requête SQL deviendrait une trace racine
	// orpheline dans Tempo.
	spans := spansFor(t, http.MethodGet, "/api/streams/42/events")

	if len(spans) != 1 || spans[0] != "GET /api/streams/{id}/events" {
		t.Fatalf("le SSE doit rester tracé, spans = %v", spans)
	}
}
