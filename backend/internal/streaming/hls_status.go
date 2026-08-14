package streaming

import (
	"net/http"
	"strconv"
)

// hlsStatusRecorder capture le code HTTP rendu à un auditeur HLS pour le
// label `status` des métriques par flux (STR-166). http.ServeFile écrit
// l'en-tête lui-même : sans capture, le status serait inconnu du handler.
type hlsStatusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *hlsStatusRecorder) WriteHeader(status int) {
	if r.status == 0 {
		r.status = status
	}
	r.ResponseWriter.WriteHeader(status)
}

func (r *hlsStatusRecorder) Write(p []byte) (int, error) {
	if r.status == 0 {
		r.status = http.StatusOK
	}
	return r.ResponseWriter.Write(p)
}

// Unwrap expose le writer sous-jacent à http.ResponseController (ServeFile).
func (r *hlsStatusRecorder) Unwrap() http.ResponseWriter { return r.ResponseWriter }

// statusText retourne le code rendu ; 200 par défaut (handler muet).
func (r *hlsStatusRecorder) statusText() string {
	if r.status == 0 {
		return strconv.Itoa(http.StatusOK)
	}
	return strconv.Itoa(r.status)
}
