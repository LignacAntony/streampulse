package httpmw

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/rs/zerolog"

	"github.com/LignacAntony/streampulse/internal/shared/httpjson"
)

const requestIDHeader = "X-Request-ID"

// incomingRequestIDPattern borne les X-Request-ID acceptés d'un client :
// tout id hors format est régénéré (anti log-injection, cardinalité bornée).
var incomingRequestIDPattern = regexp.MustCompile(`^[A-Za-z0-9-]{8,64}$`)

type userRecorderKey struct{}

// userRecorder est le réceptacle mutable posé dans le context par AccessLog
// et rempli par auth.RequireAuth/OptionalAuth une fois le JWT validé. Le
// mux (Go 1.22) passe une copie de la requête aux handlers : une valeur
// immuable posée en aval serait invisible du middleware — d'où ce pointeur
// partagé, écrit et lu séquentiellement dans la goroutine de la requête.
type userRecorder struct {
	userID string
}

// RecordUserID attache l'identité authentifiée à l'access log de la requête
// courante. No-op si AccessLog n'entoure pas la route (tests unitaires).
func RecordUserID(ctx context.Context, userID string) {
	if rec, ok := ctx.Value(userRecorderKey{}).(*userRecorder); ok {
		rec.userID = userID
	}
}

// statusRecorder capture status et volume écrits, en préservant http.Flusher
// (SSE STR-77, streaming HLS).
type statusRecorder struct {
	http.ResponseWriter
	status int
	bytes  int
}

func (sr *statusRecorder) WriteHeader(status int) {
	if sr.status == 0 {
		sr.status = status
	}
	sr.ResponseWriter.WriteHeader(status)
}

func (sr *statusRecorder) Write(p []byte) (int, error) {
	if sr.status == 0 {
		sr.status = http.StatusOK
	}
	n, err := sr.ResponseWriter.Write(p)
	sr.bytes += n
	return n, err
}

func (sr *statusRecorder) Flush() {
	if f, ok := sr.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

// Unwrap permet à http.ResponseController d'atteindre le writer sous-jacent.
func (sr *statusRecorder) Unwrap() http.ResponseWriter { return sr.ResponseWriter }

// AccessLog émet une ligne JSON par requête HTTP terminée (STR-169) et
// attache au context un logger corrélé par request_id, récupérable en aval
// via zerolog.Ctx(r.Context()).
//
// Règles de bruit : /health et /metrics ne sont jamais loggés ; les succès
// HLS (playlist + segments, ~1 req/s par auditeur) sont émis au niveau
// debug. Niveau selon status : 5xx=error, 4xx=warn, sinon info.
func AccessLog(logger zerolog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/health" || r.URL.Path == "/metrics" {
			next.ServeHTTP(w, r)
			return
		}

		reqID := requestID(r)
		w.Header().Set(requestIDHeader, reqID)

		reqLogger := logger.With().Str("request_id", reqID).Logger()
		recorder := &userRecorder{}
		ctx := reqLogger.WithContext(r.Context())
		ctx = context.WithValue(ctx, userRecorderKey{}, recorder)

		sr := &statusRecorder{ResponseWriter: w}
		start := time.Now()

		defer func() {
			panicked := recover()
			status := sr.status
			if panicked != nil && status == 0 {
				status = http.StatusInternalServerError
			}

			event := reqLogger.WithLevel(levelFor(r, status, panicked != nil)).
				Str("method", r.Method).
				Str("path", httpjson.LoggablePath(r)).
				Int("status", status).
				Int64("duration_ms", time.Since(start).Milliseconds()).
				Int("bytes", sr.bytes).
				Str("remote_addr", r.RemoteAddr)
			if recorder.userID != "" {
				event = event.Str("user_id", recorder.userID)
			}
			if panicked != nil {
				event = event.Interface("panic", panicked)
			}
			event.Msg("requête http")

			if panicked != nil {
				panic(panicked) // le serveur net/http garde son comportement par défaut
			}
		}()

		next.ServeHTTP(sr, r.WithContext(ctx))
	})
}

// requestID réutilise un X-Request-ID client bien formé, sinon génère
// 8 octets aléatoires en hexadécimal (16 caractères).
func requestID(r *http.Request) string {
	if id := r.Header.Get(requestIDHeader); incomingRequestIDPattern.MatchString(id) {
		return id
	}
	var b [8]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "0000000000000000"
	}
	return hex.EncodeToString(b[:])
}

func levelFor(r *http.Request, status int, panicked bool) zerolog.Level {
	switch {
	case panicked || status >= http.StatusInternalServerError:
		return zerolog.ErrorLevel
	case status >= http.StatusBadRequest:
		return zerolog.WarnLevel
	case isHLSPath(r.URL.Path):
		return zerolog.DebugLevel
	default:
		return zerolog.InfoLevel
	}
}

// isHLSPath identifie les routes de lecture HLS (STR-108) dont le volume
// par auditeur rendrait le niveau info inexploitable.
func isHLSPath(path string) bool {
	return strings.HasPrefix(path, "/api/streams/") &&
		(strings.HasSuffix(path, "/playlist.m3u8") || strings.Contains(path, "/segments/"))
}
