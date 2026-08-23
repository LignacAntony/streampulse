package observability

import (
	"context"
	"fmt"
	"net/url"
	"strings"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	sdkresource "go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.43.0"

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

	// OTEL_EXPORTER_OTLP_ENDPOINT est la variable *générique* de la spec OTLP :
	// la valeur est une base à laquelle le chemin /v1/traces s'ajoute. On la
	// normalise nous-mêmes (slash final, préfixe de chemin d'un reverse proxy)
	// puis on passe l'URL complète à WithEndpointURL, qui en déduit aussi le
	// TLS — WithEndpoint attendait un host:port nu et cassait silencieusement
	// dès qu'un chemin traînait (revue PR #269).
	base, err := url.Parse(cfg.OTELExporterOTLPEndpoint)
	if err != nil || base.Host == "" {
		return nil, fmt.Errorf("observability: OTEL_EXPORTER_OTLP_ENDPOINT invalide %q", cfg.OTELExporterOTLPEndpoint)
	}
	base.Path = strings.TrimSuffix(base.Path, "/") + "/v1/traces"

	exporter, err := otlptracehttp.New(ctx, otlptracehttp.WithEndpointURL(base.String()))
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
