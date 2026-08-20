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
	listErr    error
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
	if s.listErr != nil {
		return nil, s.listErr
	}
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

func TestHandler_Approve_InvalidID(t *testing.T) {
	stub := &stubService{}
	mux := http.NewServeMux()
	mux.Handle("/api/admin/broadcaster-requests/{id}/approve",
		auth.RequireAuth(testSecret, auth.RequireRole("admin", http.HandlerFunc(newHandler(stub).Approve))))

	req := httptest.NewRequest(http.MethodPost, "/api/admin/broadcaster-requests/not-a-uuid/approve", nil)
	req.Header.Set("Authorization", "Bearer "+userToken(t, "admin"))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d: %s", rec.Code, rec.Body)
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

// La liste d'administration n'était couverte par aucun test : ni le chemin
// nominal, ni le refus de méthode, ni la propagation d'erreur du service.
func TestHandler_List(t *testing.T) {
	h := newHandler(&stubService{})

	req := httptest.NewRequest(http.MethodGet, "/api/admin/broadcaster-requests?status=pending", nil)
	req.Header.Set("Authorization", "Bearer "+userToken(t, "admin"))
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret, auth.RequireRole("admin", http.HandlerFunc(h.List))).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	// La réponse est enveloppée dans un objet et non un tableau nu : ajouter un
	// champ plus tard ne cassera pas le client.
	if body := rec.Body.String(); !strings.Contains(body, `"requests":[`) {
		t.Errorf("corps = %s, want une enveloppe {\"requests\": [...]}", body)
	}
}

func TestHandler_List_MethodeRefusee(t *testing.T) {
	h := newHandler(&stubService{})

	req := httptest.NewRequest(http.MethodPost, "/api/admin/broadcaster-requests", nil)
	req.Header.Set("Authorization", "Bearer "+userToken(t, "admin"))
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret, auth.RequireRole("admin", http.HandlerFunc(h.List))).ServeHTTP(rec, req)

	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("want 405, got %d", rec.Code)
	}
	if allow := rec.Header().Get("Allow"); allow != http.MethodGet {
		t.Errorf("Allow = %q, want %q", allow, http.MethodGet)
	}
}

func TestHandler_List_ErreurDuService(t *testing.T) {
	h := newHandler(&stubService{listErr: context.DeadlineExceeded})

	req := httptest.NewRequest(http.MethodGet, "/api/admin/broadcaster-requests", nil)
	req.Header.Set("Authorization", "Bearer "+userToken(t, "admin"))
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret, auth.RequireRole("admin", http.HandlerFunc(h.List))).ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Errorf("want 500, got %d: %s", rec.Code, rec.Body)
	}
}

// Reject partage `review` avec Approve mais n'était jamais exercé : rien ne
// garantissait que le refus passe bien `approve=false` au service.
func TestHandler_Reject(t *testing.T) {
	stub := &stubService{}
	h := newHandler(stub)

	req := httptest.NewRequest(http.MethodPost,
		"/api/admin/broadcaster-requests/"+testReqID+"/reject",
		strings.NewReader(`{"review_note":"motif insuffisant"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+userToken(t, "admin"))
	req.SetPathValue("id", testReqID)
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret, auth.RequireRole("admin", http.HandlerFunc(h.Reject))).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	if stub.lastReqID != testReqID {
		t.Errorf("identifiant transmis = %q, want %q", stub.lastReqID, testReqID)
	}
	if stub.lastNote != "motif insuffisant" {
		t.Errorf("note transmise = %q, want %q", stub.lastNote, "motif insuffisant")
	}
	if body := rec.Body.String(); !strings.Contains(body, StatusRejected) {
		t.Errorf("corps = %s, want le statut %q", body, StatusRejected)
	}
}

func TestHandler_Reject_MethodeRefusee(t *testing.T) {
	h := newHandler(&stubService{})

	req := httptest.NewRequest(http.MethodGet, "/api/admin/broadcaster-requests/"+testReqID+"/reject", nil)
	req.Header.Set("Authorization", "Bearer "+userToken(t, "admin"))
	req.SetPathValue("id", testReqID)
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret, auth.RequireRole("admin", http.HandlerFunc(h.Reject))).ServeHTTP(rec, req)

	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("want 405, got %d", rec.Code)
	}
}
