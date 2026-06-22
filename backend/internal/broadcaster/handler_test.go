package broadcaster

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/LignacAntony/streampulse/internal/auth"
)

const testSecret = "test-secret-which-is-at-least-32-bytes!!"

type stubService struct {
	requestErr error
	reviewErr  error
	lastNote   string
	lastReqID  string
}

func (s *stubService) RequestBroadcaster(_ context.Context, _, message string) (Request, error) {
	if s.requestErr != nil {
		return Request{}, s.requestErr
	}
	return Request{ID: testReqID, Status: StatusPending, Message: message}, nil
}

func (s *stubService) GetMyRequest(_ context.Context, _ string) (Request, error) {
	return Request{ID: testReqID, Status: StatusPending}, nil
}

func (s *stubService) ListRequests(_ context.Context, _ string) ([]AdminRequest, error) {
	return []AdminRequest{{Request: Request{ID: testReqID, Status: StatusPending}, UserID: testUserID}}, nil
}

func (s *stubService) ApproveRequest(_ context.Context, requestID, _, note string) (Request, error) {
	s.lastReqID, s.lastNote = requestID, note
	if s.reviewErr != nil {
		return Request{}, s.reviewErr
	}
	return Request{ID: requestID, Status: StatusApproved}, nil
}

func (s *stubService) RejectRequest(_ context.Context, requestID, _, note string) (Request, error) {
	s.lastReqID, s.lastNote = requestID, note
	return Request{ID: requestID, Status: StatusRejected}, nil
}

func newHandler(s *stubService) *Handler { return NewHandler(s, s, s, s) }

func userToken(t *testing.T, role string) string {
	t.Helper()
	tok, err := auth.GenerateAccessToken(testUserID, role, testSecret, time.Now().UTC())
	if err != nil {
		t.Fatalf("generate token: %v", err)
	}
	return tok
}

func TestHandler_Create_Created(t *testing.T) {
	h := newHandler(&stubService{})
	req := httptest.NewRequest(http.MethodPost, "/api/broadcaster-requests", strings.NewReader(`{"message":"hello"}`))
	req.Header.Set("Authorization", "Bearer "+userToken(t, "user"))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret, http.HandlerFunc(h.Create)).ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("want 201, got %d: %s", rec.Code, rec.Body)
	}
	if !strings.Contains(rec.Body.String(), `"status":"pending"`) {
		t.Errorf("body missing status: %s", rec.Body)
	}
}

func TestHandler_Create_RequiresToken(t *testing.T) {
	h := newHandler(&stubService{})
	req := httptest.NewRequest(http.MethodPost, "/api/broadcaster-requests", strings.NewReader(`{}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret, http.HandlerFunc(h.Create)).ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_GetMine_OK(t *testing.T) {
	h := newHandler(&stubService{})
	req := httptest.NewRequest(http.MethodGet, "/api/broadcaster-requests/me", nil)
	req.Header.Set("Authorization", "Bearer "+userToken(t, "user"))
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret, http.HandlerFunc(h.GetMine)).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Create_WrongMethod(t *testing.T) {
	h := newHandler(&stubService{})
	req := httptest.NewRequest(http.MethodGet, "/api/broadcaster-requests", nil)
	req.Header.Set("Authorization", "Bearer "+userToken(t, "user"))
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret, http.HandlerFunc(h.Create)).ServeHTTP(rec, req)

	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("want 405, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Approve_UsesPathID(t *testing.T) {
	stub := &stubService{}
	// Routage via un ServeMux pour peupler r.PathValue("id").
	mux := http.NewServeMux()
	mux.Handle("/api/admin/broadcaster-requests/{id}/approve",
		auth.RequireAuth(testSecret, auth.RequireRole("admin", http.HandlerFunc(newHandler(stub).Approve))))

	req := httptest.NewRequest(http.MethodPost, "/api/admin/broadcaster-requests/"+testReqID+"/approve", nil)
	req.Header.Set("Authorization", "Bearer "+userToken(t, "admin"))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	if stub.lastReqID != testReqID {
		t.Errorf("path id not propagated: got %q", stub.lastReqID)
	}
}

func TestHandler_Approve_ForbiddenForNonAdmin(t *testing.T) {
	stub := &stubService{}
	mux := http.NewServeMux()
	mux.Handle("/api/admin/broadcaster-requests/{id}/approve",
		auth.RequireAuth(testSecret, auth.RequireRole("admin", http.HandlerFunc(newHandler(stub).Approve))))

	req := httptest.NewRequest(http.MethodPost, "/api/admin/broadcaster-requests/"+testReqID+"/approve", nil)
	req.Header.Set("Authorization", "Bearer "+userToken(t, "user"))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("want 403, got %d: %s", rec.Code, rec.Body)
	}
}
