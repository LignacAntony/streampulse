package httpjson

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"mime"
	"net/http"
	"strings"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

type errorResponse struct {
	Error responseError `json:"error"`
}

type responseError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type Error struct {
	Status  int
	Code    string
	Message string
	Err     error
}

func (e *Error) Error() string {
	if e == nil {
		return ""
	}
	if e.Err != nil {
		return fmt.Sprintf("%s: %s: %v", e.Code, e.Message, e.Err)
	}
	return fmt.Sprintf("%s: %s", e.Code, e.Message)
}

func (e *Error) Unwrap() error {
	if e == nil {
		return nil
	}
	return e.Err
}

func StatusError(status int, code, message string) *Error {
	return &Error{Status: status, Code: code, Message: message}
}

func Decode(w http.ResponseWriter, r *http.Request, dst any, maxBytes int64) error {
	mediaType, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if err != nil || !strings.EqualFold(mediaType, "application/json") {
		return StatusError(http.StatusUnsupportedMediaType, "unsupported_media_type", "content-type must be application/json")
	}

	r.Body = http.MaxBytesReader(w, r.Body, maxBytes)
	defer func() {
		if err := r.Body.Close(); err != nil {
			log.Printf("http: close request body: %v", err)
		}
	}()

	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()

	if err := dec.Decode(dst); err != nil {
		return StatusError(http.StatusBadRequest, "invalid_json", "invalid json body")
	}
	if err := dec.Decode(&struct{}{}); err != io.EOF {
		return StatusError(http.StatusBadRequest, "invalid_json", "invalid json body")
	}

	return nil
}

func Write(w http.ResponseWriter, status int, payload any) error {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	return json.NewEncoder(w).Encode(payload)
}

func WriteError(w http.ResponseWriter, r *http.Request, err error) {
	var httpErr *Error
	if errors.As(err, &httpErr) {
		_ = Write(w, httpErr.Status, errorResponse{Error: responseError{
			Code:    httpErr.Code,
			Message: httpErr.Message,
		}})
		return
	}

	appErr, ok := apperror.As(err)
	if !ok {
		logRequestError(r, err)
		_ = writeInternalError(w)
		return
	}

	status := statusFromCode(appErr.Code)
	message := appErr.Message
	code := string(appErr.Code)
	if status >= http.StatusInternalServerError {
		logRequestError(r, err)
		message = "internal server error"
		code = "internal"
	}

	_ = Write(w, status, errorResponse{Error: responseError{
		Code:    code,
		Message: message,
	}})
}

func statusFromCode(code apperror.Code) int {
	switch code {
	case apperror.CodeInvalidArgument:
		return http.StatusBadRequest
	case apperror.CodeUnauthorized:
		return http.StatusUnauthorized
	case apperror.CodeForbidden:
		return http.StatusForbidden
	case apperror.CodeNotFound:
		return http.StatusNotFound
	case apperror.CodeConflict:
		return http.StatusConflict
	default:
		return http.StatusInternalServerError
	}
}

func writeInternalError(w http.ResponseWriter) error {
	return Write(w, http.StatusInternalServerError, errorResponse{Error: responseError{
		Code:    "internal",
		Message: "internal server error",
	}})
}

// ingestPathPrefix marks the route whose last path segment is the secret
// stream_key — it must never appear in logs.
const ingestPathPrefix = "/api/streams/ingest/"

// loggablePath returns a log-safe representation of the request path: the
// route pattern (which holds placeholders, never path values) when the mux
// populated it, otherwise the raw path with the stream_key segment redacted.
func loggablePath(r *http.Request) string {
	if p := r.Pattern; p != "" {
		if _, after, ok := strings.Cut(p, " "); ok {
			return after
		}
		return p
	}
	if rest, ok := strings.CutPrefix(r.URL.Path, ingestPathPrefix); ok && rest != "" {
		return ingestPathPrefix + "[redacted]"
	}
	return r.URL.Path
}

func logRequestError(r *http.Request, err error) {
	if r == nil {
		log.Printf("http: %v", err)
		return
	}
	sanitize := func(s string) string {
		return strings.NewReplacer("\n", "", "\r", "").Replace(s)
	}
	log.Printf("http: %s %s %s: %v", r.Method, sanitize(loggablePath(r)), sanitize(r.RemoteAddr), err) // #nosec G706 -- path and remoteAddr stripped of newlines by sanitize()
}
