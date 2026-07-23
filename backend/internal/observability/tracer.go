package observability

import (
	"context"
	"fmt"
	"strings"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	sdkresource "go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.41.0"

	"github.com/LignacAntony/streampulse/internal/config"
)

// NewTracer configure le tracing OpenTelemetry (STR-164, ADR 020) : export
// OTLP/HTTP vers Tempo, échantillonnage ParentBased(AlwaysSample), resource
// alignée sur les labels de logs (service.name = streampulse-api).
//
// Endpoint vide (cfg.OTELExporterOTLPEndpoint) → aucun provider posé : le
// global OTEL reste noop, zéro bruit réseau en `go run` local. La fonction
// retournée flushe et arrête proprement l'exporteur (à défer dans main).
func NewTracer(ctx context.Context, cfg *config.Config) (func(context.Context) error, error) {
	if cfg.OTELExporterOTLPEndpoint == "" {
		return func(context.Context) error { return nil }, nil
	}

	// otlptracehttp attend host:port sans schéma ; l'option Insecure reflète
	// le http:// interne (streampulse-net, jamais exposé).
	endpoint := strings.TrimPrefix(strings.TrimPrefix(cfg.OTELExporterOTLPEndpoint, "https://"), "http://")
	opts := []otlptracehttp.Option{otlptracehttp.WithEndpoint(endpoint)}
	if !strings.HasPrefix(cfg.OTELExporterOTLPEndpoint, "https://") {
		opts = append(opts, otlptracehttp.WithInsecure())
	}

	exporter, err := otlptracehttp.New(ctx, opts...)
	if err != nil {
		return nil, fmt.Errorf("observability: exporteur OTLP: %w", err)
	}

	res, err := sdkresource.Merge(sdkresource.Default(), sdkresource.NewWithAttributes(
		semconv.SchemaURL,
		semconv.ServiceName(serviceName),
		semconv.DeploymentEnvironmentNameKey.String(cfg.GoEnv),
	))
	if err != nil {
		return nil, fmt.Errorf("observability: resource OTEL: %w", err)
	}

	provider := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
		sdktrace.WithSampler(sdktrace.ParentBased(sdktrace.AlwaysSample())),
	)
	otel.SetTracerProvider(provider)
	// Propagation W3C traceparent : un client déjà tracé (mobile futur,
	// service tiers) voit son contexte poursuivi au lieu d'être recréé.
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{}, propagation.Baggage{},
	))

	return provider.Shutdown, nil
}
