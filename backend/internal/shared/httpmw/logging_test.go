package httpmw

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"

	"github.com/rs/zerolog"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
)

var requestIDPattern = regexp.MustCompile(`^[0-9a-f]{16}$`)

// serveWithAccessLog exécute une requête à travers AccessLog et retourne les
// lignes JSON émises ainsi que la réponse enregistrée.
func serveWithAccessLog(t *testing.T, level zerolog.Level, handler http.Handler, req *http.Request) ([]map[string]any, *httptest.ResponseRecorder) {
	t.Helper()
	var buf bytes.Buffer
	logger := zerolog.New(&buf).Level(level)
	rec := httptest.NewRecorder()

	AccessLog(logger, handler).ServeHTTP(rec, req)

	var entries []map[string]any
	for _, line := range strings.Split(strings.TrimSpace(buf.String()), "\n") {
		if line == "" {
			continue
		}
		var entry map[string]any
		if err := json.Unmarshal([]byte(line), &entry); err != nil {
			t.Fatalf("ligne de log non-JSON: %v — %q", err, line)
		}
		entries = append(entries, entry)
	}
	return entries, rec
}

func statusHandler(status int) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(status)
		_, _ = w.Write([]byte("body"))
	})
}

func TestAccessLog_BasicFields(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/api/streams", nil)
	req.RemoteAddr = "203.0.113.7:1234"

	entries, rec := serveWithAccessLog(t, zerolog.InfoLevel, statusHandler(http.StatusOK), req)

	if len(entries) != 1 {
		t.Fatalf("attendu 1 ligne de log, got %d: %v", len(entries), entries)
	}
	e := entries[0]
	checks := map[string]any{
		"level":       "info",
		"method":      "GET",
		"path":        "/api/streams",
		"remote_addr": "203.0.113.7:1234",
	}
	for k, want := range checks {
		if e[k] != want {
			t.Errorf("champ %q = %v, want %v", k, e[k], want)
		}
	}
	if status, _ := e["status"].(float64); status != http.StatusOK {
		t.Errorf("status = %v, want 200", e["status"])
	}
	if _, ok := e["duration_ms"].(float64); !ok {
		t.Errorf("duration_ms absent ou non numérique: %v", e["duration_ms"])
	}
	if bytesOut, _ := e["bytes"].(float64); bytesOut != 4 {
		t.Errorf("bytes = %v, want 4", e["bytes"])
	}

	id, _ := e["request_id"].(string)
	if !requestIDPattern.MatchString(id) {
		t.Errorf("request_id %q ne matche pas %s", id, requestIDPattern)
	}
	if got := rec.Header().Get("X-Request-ID"); got != id {
		t.Errorf("header X-Request-ID = %q, want %q (identique au log)", got, id)
	}
	if _, present := e["user_id"]; present {
		t.Errorf("user_id présent sans authentification: %v", e["user_id"])
	}
}

func TestAccessLog_IncomingRequestID(t *testing.T) {
	t.Run("id valide réutilisé", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/api/x", nil)
		req.Header.Set("X-Request-ID", "abcdef0123456789")

		entries, rec := serveWithAccessLog(t, zerolog.InfoLevel, statusHandler(200), req)

		if id, _ := entries[0]["request_id"].(string); id != "abcdef0123456789" {
			t.Errorf("request_id = %q, want id entrant réutilisé", id)
		}
		if got := rec.Header().Get("X-Request-ID"); got != "abcdef0123456789" {
			t.Errorf("header X-Request-ID = %q, want id entrant", got)
		}
	})

	t.Run("id invalide régénéré", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/api/x", nil)
		req.Header.Set("X-Request-ID", "évil\nid-très-long-"+strings.Repeat("x", 100))

		entries, _ := serveWithAccessLog(t, zerolog.InfoLevel, statusHandler(200), req)

		id, _ := entries[0]["request_id"].(string)
		if !requestIDPattern.MatchString(id) {
			t.Errorf("request_id %q devrait être régénéré au format 16 hex", id)
		}
	})
}

func TestAccessLog_LevelByStatus(t *testing.T) {
	cases := []struct {
		status    int
		wantLevel string
	}{
		{http.StatusOK, "info"},
		{http.StatusNotFound, "warn"},
		{http.StatusInternalServerError, "error"},
	}
	for _, tc := range cases {
		t.Run(fmt.Sprintf("%d", tc.status), func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/api/x", nil)
			entries, _ := serveWithAccessLog(t, zerolog.InfoLevel, statusHandler(tc.status), req)
			if len(entries) != 1 {
				t.Fatalf("attendu 1 ligne, got %d", len(entries))
			}
			if lvl, _ := entries[0]["level"].(string); lvl != tc.wantLevel {
				t.Errorf("level = %q, want %q pour status %d", lvl, tc.wantLevel, tc.status)
			}
		})
	}
}

func TestAccessLog_ExcludedPaths(t *testing.T) {
	for _, path := range []string{"/health", "/metrics"} {
		t.Run(path, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, path, nil)
			entries, _ := serveWithAccessLog(t, zerolog.DebugLevel, statusHandler(200), req)
			if len(entries) != 0 {
				t.Errorf("%s ne doit produire aucun log, got %v", path, entries)
			}
		})
	}
}

func TestAccessLog_HLSDemotedToDebug(t *testing.T) {
	hlsPaths := []string{
		"/api/streams/42/playlist.m3u8",
		"/api/streams/42/segments/seg001.ts",
	}
	for _, path := range hlsPaths {
		t.Run(path, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, path, nil)

			// En info : succès HLS invisible (anti-bruit, 50 auditeurs en continu).
			entries, _ := serveWithAccessLog(t, zerolog.InfoLevel, statusHandler(200), req)
			if len(entries) != 0 {
				t.Errorf("succès HLS doit être silencieux au niveau info, got %v", entries)
			}

			// En debug : visible.
			entries, _ = serveWithAccessLog(t, zerolog.DebugLevel, statusHandler(200), req)
			if len(entries) != 1 {
				t.Fatalf("succès HLS attendu au niveau debug, got %d lignes", len(entries))
			}
			if lvl, _ := entries[0]["level"].(string); lvl != "debug" {
				t.Errorf("level = %q, want debug", lvl)
			}
		})
	}

	t.Run("erreur HLS reste visible en info", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, hlsPaths[0], nil)
		entries, _ := serveWithAccessLog(t, zerolog.InfoLevel, statusHandler(http.StatusServiceUnavailable), req)
		if len(entries) != 1 {
			t.Fatalf("erreur HLS doit être loggée en info, got %d lignes", len(entries))
		}
		if lvl, _ := entries[0]["level"].(string); lvl != "error" {
			t.Errorf("level = %q, want error pour 503", lvl)
		}
	})
}

func TestAccessLog_StreamKeyRedacted(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "/api/streams/ingest/SUPERSECRETKEY123", nil)

	entries, _ := serveWithAccessLog(t, zerolog.InfoLevel, statusHandler(200), req)

	if len(entries) != 1 {
		t.Fatalf("attendu 1 ligne, got %d", len(entries))
	}
	raw, _ := json.Marshal(entries[0])
	if strings.Contains(string(raw), "SUPERSECRETKEY123") {
		t.Fatalf("stream_key en clair dans le log: %s", raw)
	}
	if path, _ := entries[0]["path"].(string); path != "/api/streams/ingest/[redacted]" {
		t.Errorf("path = %q, want %q", path, "/api/streams/ingest/[redacted]")
	}
}

func TestAccessLog_UserIDRecorded(t *testing.T) {
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Simule auth.RequireAuth qui enregistre l'identité une fois le JWT validé.
		RecordUserID(r.Context(), "user-42")
		w.WriteHeader(http.StatusOK)
	})
	req := httptest.NewRequest(http.MethodGet, "/api/users/me", nil)

	entries, _ := serveWithAccessLog(t, zerolog.InfoLevel, handler, req)

	if got, _ := entries[0]["user_id"].(string); got != "user-42" {
		t.Errorf("user_id = %v, want user-42", entries[0]["user_id"])
	}
}

func TestAccessLog_ContextLoggerCarriesRequestID(t *testing.T) {
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		zerolog.Ctx(r.Context()).Info().Msg("depuis le handler")
		w.WriteHeader(http.StatusOK)
	})
	req := httptest.NewRequest(http.MethodGet, "/api/x", nil)

	entries, _ := serveWithAccessLog(t, zerolog.InfoLevel, handler, req)

	if len(entries) != 2 {
		t.Fatalf("attendu 2 lignes (handler + access log), got %d", len(entries))
	}
	handlerID, _ := entries[0]["request_id"].(string)
	accessID, _ := entries[1]["request_id"].(string)
	if handlerID == "" || handlerID != accessID {
		t.Errorf("request_id handler %q ≠ access log %q — corrélation cassée", handlerID, accessID)
	}
}

func TestAccessLog_PanicLoggedAndRepropagated(t *testing.T) {
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		panic("boom")
	})
	req := httptest.NewRequest(http.MethodGet, "/api/x", nil)

	var buf bytes.Buffer
	logger := zerolog.New(&buf).Level(zerolog.InfoLevel)
	rec := httptest.NewRecorder()

	defer func() {
		if p := recover(); p == nil {
			t.Fatal("panic absorbée — elle doit se propager au serveur")
		}
		if !strings.Contains(buf.String(), `"level":"error"`) {
			t.Errorf("panic non loggée en error: %q", buf.String())
		}
	}()
	AccessLog(logger, handler).ServeHTTP(rec, req)
}

func TestAccessLog_PreservesFlusher(t *testing.T) {
	var isFlusher bool
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, isFlusher = w.(http.Flusher)
		w.WriteHeader(http.StatusOK)
	})
	req := httptest.NewRequest(http.MethodGet, "/api/streams/1/events", nil)

	_, _ = serveWithAccessLog(t, zerolog.InfoLevel, handler, req)

	if !isFlusher {
		t.Error("le ResponseWriter wrappé doit rester un http.Flusher (SSE STR-77)")
	}
}

func TestAccessLog_TraceIDWhenSpanActive(t *testing.T) {
	tp := sdktrace.NewTracerProvider() // recording, sans exporteur
	t.Cleanup(func() { _ = tp.Shutdown(context.Background()) })

	var handlerTraceID string
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		zerolog.Ctx(r.Context()).Info().Msg("depuis le handler")
		w.WriteHeader(http.StatusOK)
	})

	var buf bytes.Buffer
	logger := zerolog.New(&buf)

	// Simule otelhttp posé au-dessus d'AccessLog : le span vit déjà dans le ctx.
	ctx, span := tp.Tracer("test").Start(context.Background(), "GET /api/streams")
	handlerTraceID = span.SpanContext().TraceID().String()
	req := httptest.NewRequest(http.MethodGet, "/api/streams", nil).WithContext(ctx)

	AccessLog(logger, handler).ServeHTTP(httptest.NewRecorder(), req)
	span.End()

	out := buf.String()
	if c := strings.Count(out, `"trace_id":"`+handlerTraceID+`"`); c != 2 {
		t.Errorf("trace_id %s attendu dans la ligne handler ET l'access log (2 occurrences), got %d — sortie: %s", handlerTraceID, c, out)
	}
}

func TestAccessLog_NoTraceIDWithoutSpan(t *testing.T) {
	var buf bytes.Buffer
	logger := zerolog.New(&buf)
	req := httptest.NewRequest(http.MethodGet, "/api/streams", nil)

	AccessLog(logger, statusHandler(http.StatusOK)).ServeHTTP(httptest.NewRecorder(), req)

	if strings.Contains(buf.String(), "trace_id") {
		t.Errorf("pas de span actif → pas de champ trace_id, sortie: %s", buf.String())
	}
}
