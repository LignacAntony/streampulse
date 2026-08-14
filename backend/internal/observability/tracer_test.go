package observability

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"go.opentelemetry.io/otel"

	"github.com/LignacAntony/streampulse/internal/config"
)

func tracerConfig(endpoint string) *config.Config {
	return &config.Config{GoEnv: "test", LogLevel: "info", OTELExporterOTLPEndpoint: endpoint}
}

func TestNewTracer_EmptyEndpointIsNoop(t *testing.T) {
	shutdown, err := NewTracer(context.Background(), tracerConfig(""))
	if err != nil {
		t.Fatalf("NewTracer(endpoint vide) error = %v", err)
	}
	t.Cleanup(func() { _ = shutdown(context.Background()) })

	_, span := otel.Tracer("test").Start(context.Background(), "op")
	defer span.End()
	if span.IsRecording() {
		t.Error("sans endpoint le tracing doit être noop (aucun span enregistré)")
	}
	if err := shutdown(context.Background()); err != nil {
		t.Errorf("shutdown noop doit être sans erreur: %v", err)
	}
}

func TestNewTracer_ExportsSpansOverOTLPHTTP(t *testing.T) {
	var received atomic.Int32
	var body atomic.Value
	collector := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/v1/traces" {
			received.Add(1)
			buf := make([]byte, r.ContentLength)
			_, _ = r.Body.Read(buf)
			body.Store(string(buf))
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer collector.Close()

	shutdown, err := NewTracer(context.Background(), tracerConfig(collector.URL))
	if err != nil {
		t.Fatalf("NewTracer error = %v", err)
	}
	t.Cleanup(func() {
		_ = shutdown(context.Background())
		otel.SetTracerProvider(nil) // évite la pollution des autres tests
	})

	_, span := otel.Tracer("test").Start(context.Background(), "operation-de-test")
	if !span.IsRecording() {
		t.Fatal("avec endpoint le span doit être recording (AlwaysSample)")
	}
	if !span.SpanContext().TraceID().IsValid() {
		t.Fatal("trace_id invalide")
	}
	span.End()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := shutdown(ctx); err != nil {
		t.Fatalf("shutdown (flush) error = %v", err)
	}
	if received.Load() == 0 {
		t.Fatal("aucun POST /v1/traces reçu par le collecteur — export OTLP/HTTP absent")
	}
	// Le protobuf OTLP encode les strings en clair : la resource doit porter
	// le nom de service aligné sur le label des logs (corrélation Grafana).
	if raw, _ := body.Load().(string); !strings.Contains(raw, "streampulse-api") {
		t.Error("resource service.name=streampulse-api absente de l'export")
	}
}

func TestNewTracer_EndpointNormalization(t *testing.T) {
	// OTEL_EXPORTER_OTLP_ENDPOINT est la variable *générique* : la spec OTLP
	// veut que le chemin /v1/traces soit ajouté à la base fournie. Le slash
	// final ou un préfixe de chemin (reverse proxy) doivent être gérés
	// proprement (revue PR #269).
	cases := []struct {
		suffix   string
		wantPath string
	}{
		{"", "/v1/traces"},
		{"/", "/v1/traces"},
		{"/otlp", "/otlp/v1/traces"},
	}
	for _, tc := range cases {
		t.Run("base"+tc.suffix, func(t *testing.T) {
			var gotPath atomic.Value
			collector := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				gotPath.Store(r.URL.Path)
				w.WriteHeader(http.StatusOK)
			}))
			defer collector.Close()

			endpoint := collector.URL + tc.suffix
			shutdown, err := NewTracer(context.Background(), tracerConfig(endpoint))
			if err != nil {
				t.Fatalf("NewTracer(%q) error = %v", endpoint, err)
			}
			t.Cleanup(func() { otel.SetTracerProvider(nil) })

			_, span := otel.Tracer("test").Start(context.Background(), "op")
			span.End()

			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			if err := shutdown(ctx); err != nil {
				t.Fatalf("shutdown error = %v", err)
			}
			if got, _ := gotPath.Load().(string); got != tc.wantPath {
				t.Errorf("endpoint %q → POST %q, want %q", endpoint, got, tc.wantPath)
			}
		})
	}
}

func TestNewTracer_InvalidEndpointRejected(t *testing.T) {
	if _, err := NewTracer(context.Background(), tracerConfig("://pas-une-url")); err == nil {
		t.Fatal("un endpoint invalide doit remonter une erreur au démarrage, pas être ignoré")
	}
}
