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
