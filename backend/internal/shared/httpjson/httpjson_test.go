package httpjson

import (
	"bytes"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

func TestWriteError_MapsAppErrors(t *testing.T) {
	tests := []struct {
		name       string
		err        error
		wantStatus int
		wantCode   string
		wantError  string
	}{
		{
			name:       "invalid argument",
			err:        apperror.InvalidArgument("invalid email"),
			wantStatus: http.StatusBadRequest,
			wantCode:   "invalid_argument",
			wantError:  "invalid email",
		},
		{
			name:       "conflict",
			err:        apperror.Conflict("email already taken"),
			wantStatus: http.StatusConflict,
			wantCode:   "conflict",
			wantError:  "email already taken",
		},
		{
			name:       "unknown error",
			err:        errors.New("database password leaked here"),
			wantStatus: http.StatusInternalServerError,
			wantCode:   "internal",
			wantError:  "internal server error",
		},
		{
			name:       "internal app error",
			err:        apperror.Internal("insert user", errors.New("db failed")),
			wantStatus: http.StatusInternalServerError,
			wantCode:   "internal",
			wantError:  "internal server error",
		},
		{
			name:       "http error",
			err:        StatusError(http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed"),
			wantStatus: http.StatusMethodNotAllowed,
			wantCode:   "method_not_allowed",
			wantError:  "method not allowed",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			req := httptest.NewRequest(http.MethodPost, "/test", nil)

			WriteError(rec, req, tt.err)

			if rec.Code != tt.wantStatus {
				t.Fatalf("status: want %d, got %d", tt.wantStatus, rec.Code)
			}
			got := struct {
				Error struct {
					Code    string `json:"code"`
					Message string `json:"message"`
				} `json:"error"`
			}{}
			if err := json.NewDecoder(rec.Body).Decode(&got); err != nil {
				t.Fatalf("decode body: %v", err)
			}
			if got.Error.Code != tt.wantCode {
				t.Fatalf("code: want %q, got %q", tt.wantCode, got.Error.Code)
			}
			if got.Error.Message != tt.wantError {
				t.Fatalf("message: want %q, got %q", tt.wantError, got.Error.Message)
			}
		})
	}
}

func TestWriteError_RedactsStreamKeyInLogs(t *testing.T) {
	tests := []struct {
		name      string
		viaMux    bool
		path      string
		wantInLog string
		notInLog  string
	}{
		{
			name:      "ingest path is redacted without route pattern",
			path:      "/api/streams/ingest/secret-key-123",
			wantInLog: "/api/streams/ingest/[redacted]",
			notInLog:  "secret-key-123",
		},
		{
			name:      "route pattern is preferred when set",
			viaMux:    true,
			path:      "/api/streams/ingest/secret-key-123",
			wantInLog: "/api/streams/ingest/{stream_key}",
			notInLog:  "secret-key-123",
		},
		{
			name:      "non-sensitive path is logged verbatim",
			path:      "/api/auth/login",
			wantInLog: "/api/auth/login",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var buf bytes.Buffer
			prev := log.Writer()
			log.SetOutput(&buf)
			t.Cleanup(func() { log.SetOutput(prev) })

			rec := httptest.NewRecorder()
			req := httptest.NewRequest(http.MethodPost, tt.path, nil)
			ingestErr := apperror.Internal("ingest interrupted", errors.New("unexpected EOF"))

			if tt.viaMux {
				mux := http.NewServeMux()
				mux.Handle("POST /api/streams/ingest/{stream_key}", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					WriteError(w, r, ingestErr)
				}))
				mux.ServeHTTP(rec, req)
			} else {
				WriteError(rec, req, ingestErr)
			}

			logged := buf.String()
			if !strings.Contains(logged, tt.wantInLog) {
				t.Fatalf("log: want %q in %q", tt.wantInLog, logged)
			}
			if tt.notInLog != "" && strings.Contains(logged, tt.notInLog) {
				t.Fatalf("log: secret %q leaked in %q", tt.notInLog, logged)
			}
		})
	}
}

func TestDecode(t *testing.T) {
	tests := []struct {
		name        string
		contentType string
		body        string
		wantErr     bool
		wantStatus  int
		wantCode    string
	}{
		{
			name:        "valid",
			contentType: "Application/JSON; charset=utf-8",
			body:        `{"name":"alice"}`,
		},
		{
			name:        "invalid content type",
			contentType: "application/jsonx",
			body:        `{"name":"alice"}`,
			wantErr:     true,
			wantStatus:  http.StatusUnsupportedMediaType,
			wantCode:    "unsupported_media_type",
		},
		{
			name:        "invalid json",
			contentType: "application/json",
			body:        `{"name":`,
			wantErr:     true,
			wantStatus:  http.StatusBadRequest,
			wantCode:    "invalid_json",
		},
		{
			name:        "trailing json",
			contentType: "application/json",
			body:        `{"name":"alice"} {}`,
			wantErr:     true,
			wantStatus:  http.StatusBadRequest,
			wantCode:    "invalid_json",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/test", strings.NewReader(tt.body))
			req.Header.Set("Content-Type", tt.contentType)
			rec := httptest.NewRecorder()
			dst := struct {
				Name string `json:"name"`
			}{}

			err := Decode(rec, req, &dst, 1024)
			if !tt.wantErr {
				if err != nil {
					t.Fatalf("Decode() unexpected error: %v", err)
				}
				if dst.Name != "alice" {
					t.Fatalf("name: want alice, got %q", dst.Name)
				}
				return
			}

			var httpErr *Error
			if !errors.As(err, &httpErr) {
				t.Fatalf("want httpjson.Error, got %v", err)
			}
			if httpErr.Status != tt.wantStatus {
				t.Fatalf("status: want %d, got %d", tt.wantStatus, httpErr.Status)
			}
			if httpErr.Code != tt.wantCode {
				t.Fatalf("code: want %q, got %q", tt.wantCode, httpErr.Code)
			}
		})
	}
}
