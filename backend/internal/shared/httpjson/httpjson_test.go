package httpjson

import (
	"bytes"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"

	"strings"
	"testing"

	"github.com/rs/zerolog"

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
			logger := zerolog.New(&buf)

			rec := httptest.NewRecorder()
			req := httptest.NewRequest(http.MethodPost, tt.path, nil)
			req = req.WithContext(logger.WithContext(req.Context()))
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

func TestAnonymizeIP(t *testing.T) {
	cas := []struct {
		nom  string
		in   string
		want string
	}{
		{"IPv4 avec port", "203.0.113.7:1234", "203.0.113.0/24"},
		{"IPv4 nue", "198.51.100.42", "198.51.100.0/24"},
		{"IPv4 déjà en .0", "192.0.2.0", "192.0.2.0/24"},
		{"IPv6 avec port et crochets", "[2001:db8:1234:5678::1]:443", "2001:db8:1234::/48"},
		{"IPv6 nue", "2001:db8:abcd:ef01::9", "2001:db8:abcd::/48"},
		{"IPv4 encodée en IPv6", "::ffff:203.0.113.7", "203.0.113.0/24"},
		{"boucle locale", "127.0.0.1:8080", "127.0.0.0/24"},
		{"vide", "", "unknown"},
		{"non analysable", "pas-une-ip", "unknown"},
		// Une valeur venue du réseau ne doit pas ressortir telle quelle dans un
		// journal, même échappée : elle rendrait le champ imprévisible.
		{"injection", "1.2.3.4 evil\nlog=inject", "unknown"},
	}
	for _, tc := range cas {
		t.Run(tc.nom, func(t *testing.T) {
			if got := AnonymizeIP(tc.in); got != tc.want {
				t.Errorf("AnonymizeIP(%q) = %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}

// Le dernier octet v4 et les 80 bits bas v6 doivent réellement disparaître :
// deux adresses du même réseau se réduisent à la même valeur, deux réseaux
// distincts restent distincts.
func TestAnonymizeIP_ReduitAuReseau(t *testing.T) {
	if a, b := AnonymizeIP("203.0.113.7"), AnonymizeIP("203.0.113.250"); a != b {
		t.Errorf("même /24 doit donner la même valeur: %q vs %q", a, b)
	}
	if a, b := AnonymizeIP("203.0.113.7"), AnonymizeIP("203.0.114.7"); a == b {
		t.Errorf("deux /24 distincts ne doivent pas se confondre: %q", a)
	}
}

// Le mapping code applicatif → statut HTTP est le contrat de sortie de toute
// l'API : une entrée oubliée renverrait un 500 là où le client attend un 404,
// et le mobile afficherait « erreur serveur » sur une ressource absente.
func TestStatusFromCode(t *testing.T) {
	cas := []struct {
		code apperror.Code
		want int
	}{
		{apperror.CodeInvalidArgument, http.StatusBadRequest},
		{apperror.CodeUnauthorized, http.StatusUnauthorized},
		{apperror.CodeForbidden, http.StatusForbidden},
		{apperror.CodeNotFound, http.StatusNotFound},
		{apperror.CodeConflict, http.StatusConflict},
		{apperror.CodeUnsupportedMedia, http.StatusUnsupportedMediaType},
		{apperror.CodeInternal, http.StatusInternalServerError},
		// Un code inconnu doit valoir 500, jamais 200 : une erreur non
		// répertoriée reste une erreur.
		{apperror.Code("inconnu"), http.StatusInternalServerError},
	}
	for _, tc := range cas {
		t.Run(string(tc.code), func(t *testing.T) {
			if got := statusFromCode(tc.code); got != tc.want {
				t.Errorf("statusFromCode(%q) = %d, want %d", tc.code, got, tc.want)
			}
		})
	}
}

func TestError_MessageEtUnwrap(t *testing.T) {
	sans := &Error{Status: 400, Code: "bad_request", Message: "corps illisible"}
	if got, want := sans.Error(), "bad_request: corps illisible"; got != want {
		t.Errorf("Error() = %q, want %q", got, want)
	}
	if sans.Unwrap() != nil {
		t.Error("Unwrap() sans cause doit rendre nil")
	}

	cause := errors.New("EOF")
	avec := &Error{Status: 400, Code: "bad_request", Message: "corps illisible", Err: cause}
	if got, want := avec.Error(), "bad_request: corps illisible: EOF"; got != want {
		t.Errorf("Error() = %q, want %q", got, want)
	}
	if !errors.Is(avec, cause) {
		t.Error("la cause doit rester atteignable par errors.Is")
	}

	// Nil typé : Error() est appelé à travers une interface, où le nil passe
	// inaperçu jusqu'à la panique.
	var nul *Error
	if got := nul.Error(); got != "" {
		t.Errorf("Error() sur nil = %q, want vide", got)
	}
	if nul.Unwrap() != nil {
		t.Error("Unwrap() sur nil doit rendre nil")
	}
}
