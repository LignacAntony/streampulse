package openapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/getkin/kin-openapi/openapi3"
)

func TestSpecYAML_ValidOpenAPI(t *testing.T) {
	loader := openapi3.NewLoader()
	doc, err := loader.LoadFromData(SpecYAML())
	if err != nil {
		t.Fatalf("load openapi spec: %v", err)
	}
	if err := doc.Validate(context.Background()); err != nil {
		t.Fatalf("validate openapi spec: %v", err)
	}
}

func TestSpecHandler_ServesYAML(t *testing.T) {
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, SpecPath, nil)

	SpecHandler().ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: want 200, got %d", rec.Code)
	}
	if got := rec.Header().Get("Content-Type"); !strings.HasPrefix(got, "application/yaml") {
		t.Fatalf("content-type: want application/yaml, got %q", got)
	}
	if !strings.Contains(rec.Body.String(), "openapi: 3.0.3") {
		t.Fatalf("body does not look like openapi yaml: %q", rec.Body.String())
	}
}

func TestRedirectHandler_RedirectsToSwaggerSlash(t *testing.T) {
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/swagger", nil)

	RedirectHandler().ServeHTTP(rec, req)

	if rec.Code != http.StatusPermanentRedirect {
		t.Fatalf("status: want 308, got %d", rec.Code)
	}
	if got := rec.Header().Get("Location"); got != SwaggerPath {
		t.Fatalf("location: want %q, got %q", SwaggerPath, got)
	}
}

func TestSwaggerHandler_ServesUI(t *testing.T) {
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, SwaggerPath, nil)

	SwaggerHandler().ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: want 200, got %d", rec.Code)
	}
	if got := rec.Header().Get("Content-Type"); !strings.HasPrefix(got, "text/html") {
		t.Fatalf("content-type: want text/html, got %q", got)
	}
	if !strings.Contains(rec.Body.String(), SpecPath) {
		t.Fatalf("swagger ui does not reference spec path %q", SpecPath)
	}
}
