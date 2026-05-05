package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

// stubRegistrar permet de piloter la réponse du service depuis les tests.
type stubRegistrar struct {
	user User
	err  error
}

func (s *stubRegistrar) Register(_ context.Context, _ RegisterInput) (User, error) {
	return s.user, s.err
}

func newRequest(t *testing.T, body string) *http.Request {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/api/auth/register", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	return req
}

func decodeJSON(t *testing.T, r io.Reader) map[string]any {
	t.Helper()
	out := map[string]any{}
	if err := json.NewDecoder(r).Decode(&out); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	return out
}

func decodeError(t *testing.T, r io.Reader) (string, string) {
	t.Helper()
	out := struct {
		Error struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	}{}
	if err := json.NewDecoder(r).Decode(&out); err != nil {
		t.Fatalf("decode error response: %v", err)
	}
	return out.Error.Code, out.Error.Message
}

func TestHandler_Register_Created(t *testing.T) {
	stub := &stubRegistrar{
		user: User{
			ID:        "11111111-2222-3333-4444-555555555555",
			Email:     "alice@example.com",
			Username:  "alice",
			Role:      "user",
			CreatedAt: time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC),
		},
	}
	h := NewHandler(stub)

	req := newRequest(t, `{"email":"alice@example.com","username":"alice","password":"hunter2hunter"}`)
	rec := httptest.NewRecorder()
	h.Register(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("status: want 201, got %d (body=%s)", rec.Code, rec.Body.String())
	}
	body := rec.Body.Bytes()
	if bytes.Contains(body, []byte("password")) {
		t.Errorf("response leaks password field: %s", body)
	}
	got := decodeJSON(t, bytes.NewReader(body))
	if got["email"] != "alice@example.com" {
		t.Errorf("email: got %v", got["email"])
	}
	if got["role"] != "user" {
		t.Errorf("role: got %v", got["role"])
	}
}

func TestHandler_Register_InvalidJSON(t *testing.T) {
	stub := &stubRegistrar{}
	h := NewHandler(stub)

	req := newRequest(t, `{"email":`)
	rec := httptest.NewRecorder()
	h.Register(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status: want 400, got %d", rec.Code)
	}
}

func TestHandler_Register_TrailingJSON(t *testing.T) {
	stub := &stubRegistrar{}
	h := NewHandler(stub)

	req := newRequest(t, `{"email":"alice@example.com","username":"alice","password":"hunter2hunter"} {}`)
	rec := httptest.NewRecorder()
	h.Register(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status: want 400, got %d", rec.Code)
	}
}

func TestHandler_Register_PasswordTooShort(t *testing.T) {
	stub := &stubRegistrar{err: apperror.InvalidArgument("password too short")}
	h := NewHandler(stub)

	req := newRequest(t, `{"email":"a@b.co","username":"alice","password":"abc"}`)
	rec := httptest.NewRecorder()
	h.Register(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status: want 400, got %d", rec.Code)
	}
	code, message := decodeError(t, rec.Body)
	if code != "invalid_argument" {
		t.Errorf("error code: got %q", code)
	}
	if message != "password too short" {
		t.Errorf("error message: got %q", message)
	}
}

func TestHandler_Register_InvalidEmail(t *testing.T) {
	stub := &stubRegistrar{err: apperror.InvalidArgument("invalid email")}
	h := NewHandler(stub)

	req := newRequest(t, `{"email":"nope","username":"alice","password":"hunter2hunter"}`)
	rec := httptest.NewRecorder()
	h.Register(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status: want 400, got %d", rec.Code)
	}
}

func TestHandler_Register_DuplicateEmail(t *testing.T) {
	stub := &stubRegistrar{err: apperror.Conflict("email or username already taken")}
	h := NewHandler(stub)

	req := newRequest(t, `{"email":"alice@example.com","username":"alice","password":"hunter2hunter"}`)
	rec := httptest.NewRecorder()
	h.Register(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("status: want 409, got %d", rec.Code)
	}
}

func TestHandler_Register_InternalError(t *testing.T) {
	stub := &stubRegistrar{err: errors.New("boom")}
	h := NewHandler(stub)

	req := newRequest(t, `{"email":"alice@example.com","username":"alice","password":"hunter2hunter"}`)
	rec := httptest.NewRecorder()
	h.Register(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status: want 500, got %d", rec.Code)
	}
}

func TestHandler_Register_MethodNotAllowed(t *testing.T) {
	stub := &stubRegistrar{}
	h := NewHandler(stub)

	req := httptest.NewRequest(http.MethodGet, "/api/auth/register", nil)
	rec := httptest.NewRecorder()
	h.Register(rec, req)

	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status: want 405, got %d", rec.Code)
	}
	if got := rec.Header().Get("Allow"); got != http.MethodPost {
		t.Errorf("allow header: got %q", got)
	}
}

func TestHandler_Register_UnsupportedMediaType(t *testing.T) {
	stub := &stubRegistrar{}
	h := NewHandler(stub)

	req := httptest.NewRequest(http.MethodPost, "/api/auth/register", strings.NewReader(""))
	req.Header.Set("Content-Type", "text/plain")
	rec := httptest.NewRecorder()
	h.Register(rec, req)

	if rec.Code != http.StatusUnsupportedMediaType {
		t.Fatalf("status: want 415, got %d", rec.Code)
	}
}

func TestHandler_Register_ContentTypeParsing(t *testing.T) {
	tests := []struct {
		name        string
		contentType string
		wantStatus  int
	}{
		{
			name:        "case insensitive with charset",
			contentType: "Application/JSON; charset=utf-8",
			wantStatus:  http.StatusCreated,
		},
		{
			name:        "invalid suffix",
			contentType: "application/jsonx",
			wantStatus:  http.StatusUnsupportedMediaType,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			stub := &stubRegistrar{
				user: User{
					ID:        "11111111-2222-3333-4444-555555555555",
					Email:     "alice@example.com",
					Username:  "alice",
					Role:      "user",
					CreatedAt: time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC),
				},
			}
			h := NewHandler(stub)

			req := httptest.NewRequest(http.MethodPost, "/api/auth/register", strings.NewReader(
				`{"email":"alice@example.com","username":"alice","password":"hunter2hunter"}`,
			))
			req.Header.Set("Content-Type", tt.contentType)
			rec := httptest.NewRecorder()
			h.Register(rec, req)

			if rec.Code != tt.wantStatus {
				t.Fatalf("status: want %d, got %d (body=%s)", tt.wantStatus, rec.Code, rec.Body.String())
			}
		})
	}
}
