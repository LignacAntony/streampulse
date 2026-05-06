package auth

import (
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

type stubRegistrar struct {
	user User
	err  error
}

func (s *stubRegistrar) Register(_ context.Context, _ RegisterInput) (User, error) {
	return s.user, s.err
}

type stubAuthenticator struct {
	pair TokenPair
	err  error
}

func (s *stubAuthenticator) Login(_ context.Context, _ LoginInput) (TokenPair, error) {
	return s.pair, s.err
}

type stubRefresher struct {
	pair TokenPair
	err  error
}

func (s *stubRefresher) Refresh(_ context.Context, _ RefreshInput) (TokenPair, error) {
	return s.pair, s.err
}

type stubLogouter struct{ err error }

func (s *stubLogouter) Logout(_ context.Context, _ LogoutInput) error { return s.err }

type stubResetter struct{ err error }

func (s *stubResetter) ForgotPassword(_ context.Context, _ ForgotPasswordInput) error { return s.err }

func post(t *testing.T, path, body string) *http.Request {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	return req
}

func decodeError(t *testing.T, r io.Reader) (code, message string) {
	t.Helper()
	var out struct {
		Error struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.NewDecoder(r).Decode(&out); err != nil {
		t.Fatalf("decode error response: %v", err)
	}
	return out.Error.Code, out.Error.Message
}

func TestHandler_Register_Created(t *testing.T) {
	stub := &stubRegistrar{user: User{
		ID: "1", Email: "alice@example.com", Username: "alice", Role: "user", CreatedAt: time.Now(),
	}}
	rec := httptest.NewRecorder()
	NewHandler(stub, nil, nil, nil, nil).Register(rec, post(t, "/api/auth/register",
		`{"email":"alice@example.com","username":"alice","password":"hunter2hunter"}`))

	if rec.Code != http.StatusCreated {
		t.Fatalf("want 201, got %d: %s", rec.Code, rec.Body)
	}
	if strings.Contains(rec.Body.String(), "password") {
		t.Error("response leaks password field")
	}
}

func TestHandler_Register_InvalidJSON(t *testing.T) {
	rec := httptest.NewRecorder()
	NewHandler(&stubRegistrar{}, nil, nil, nil, nil).Register(rec, post(t, "/api/auth/register", `{"email":`))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d", rec.Code)
	}
}

func TestHandler_Register_Conflict(t *testing.T) {
	rec := httptest.NewRecorder()
	NewHandler(&stubRegistrar{err: apperror.Conflict("email or username already taken")}, nil, nil, nil, nil).Register(
		rec, post(t, "/api/auth/register", `{"email":"a@b.co","username":"a","password":"hunter2hunter"}`))
	if rec.Code != http.StatusConflict {
		t.Fatalf("want 409, got %d", rec.Code)
	}
}

func TestHandler_Register_MethodNotAllowed(t *testing.T) {
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/api/auth/register", nil)
	NewHandler(&stubRegistrar{}, nil, nil, nil, nil).Register(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("want 405, got %d", rec.Code)
	}
}

func TestHandler_Register_InternalError(t *testing.T) {
	rec := httptest.NewRecorder()
	NewHandler(&stubRegistrar{err: errors.New("boom")}, nil, nil, nil, nil).Register(
		rec, post(t, "/api/auth/register", `{"email":"a@b.co","username":"a","password":"hunter2hunter"}`))
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("want 500, got %d", rec.Code)
	}
}

func TestHandler_Login_OK(t *testing.T) {
	stub := &stubAuthenticator{pair: TokenPair{AccessToken: "acc", RefreshToken: "ref"}}
	rec := httptest.NewRecorder()
	NewHandler(nil, stub, nil, nil, nil).Login(rec, post(t, "/api/auth/login",
		`{"email":"alice@example.com","password":"hunter2hunter"}`))

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Login_Unauthorized(t *testing.T) {
	rec := httptest.NewRecorder()
	NewHandler(nil, &stubAuthenticator{err: apperror.Unauthorized("invalid credentials")}, nil, nil, nil).Login(
		rec, post(t, "/api/auth/login", `{"email":"a@b.co","password":"wrong"}`))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d", rec.Code)
	}
	code, _ := decodeError(t, rec.Body)
	if code != "unauthorized" {
		t.Errorf("error code = %q, want unauthorized", code)
	}
}

func TestHandler_Refresh_OK(t *testing.T) {
	stub := &stubRefresher{pair: TokenPair{AccessToken: "new-acc", RefreshToken: "new-ref"}}
	rec := httptest.NewRecorder()
	NewHandler(nil, nil, stub, nil, nil).Refresh(rec, post(t, "/api/auth/refresh", `{"refresh_token":"old"}`))
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Refresh_MissingToken(t *testing.T) {
	rec := httptest.NewRecorder()
	NewHandler(nil, nil, &stubRefresher{}, nil, nil).Refresh(rec, post(t, "/api/auth/refresh", `{"refresh_token":""}`))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d", rec.Code)
	}
}

func TestHandler_Refresh_Unauthorized(t *testing.T) {
	rec := httptest.NewRecorder()
	NewHandler(nil, nil, &stubRefresher{err: apperror.Unauthorized("invalid or expired refresh token")}, nil, nil).Refresh(
		rec, post(t, "/api/auth/refresh", `{"refresh_token":"expired"}`))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d", rec.Code)
	}
}

// -- Logout ------------------------------------------------------------------

func TestHandler_Logout_OK(t *testing.T) {
	rec := httptest.NewRecorder()
	NewHandler(nil, nil, nil, &stubLogouter{}, nil).Logout(rec, post(t, "/api/auth/logout", `{"refresh_token":"tok"}`))
	if rec.Code != http.StatusNoContent {
		t.Fatalf("want 204, got %d", rec.Code)
	}
}

func TestHandler_Logout_MissingToken(t *testing.T) {
	rec := httptest.NewRecorder()
	NewHandler(nil, nil, nil, &stubLogouter{}, nil).Logout(rec, post(t, "/api/auth/logout", `{"refresh_token":""}`))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d", rec.Code)
	}
}

func TestHandler_Logout_MethodNotAllowed(t *testing.T) {
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/api/auth/logout", nil)
	NewHandler(nil, nil, nil, &stubLogouter{}, nil).Logout(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("want 405, got %d", rec.Code)
	}
}

// -- ForgotPassword ----------------------------------------------------------

func TestHandler_ForgotPassword_OK(t *testing.T) {
	rec := httptest.NewRecorder()
	NewHandler(nil, nil, nil, nil, &stubResetter{}).ForgotPassword(rec,
		post(t, "/api/auth/forgot-password", `{"email":"alice@example.com"}`))
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_ForgotPassword_InvalidJSON(t *testing.T) {
	rec := httptest.NewRecorder()
	NewHandler(nil, nil, nil, nil, &stubResetter{}).ForgotPassword(rec,
		post(t, "/api/auth/forgot-password", `{"email":`))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d", rec.Code)
	}
}

func TestHandler_ForgotPassword_MethodNotAllowed(t *testing.T) {
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/api/auth/forgot-password", nil)
	NewHandler(nil, nil, nil, nil, &stubResetter{}).ForgotPassword(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("want 405, got %d", rec.Code)
	}
}
