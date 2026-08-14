package admin

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/LignacAntony/streampulse/internal/auth"
	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

const (
	testHandlerSecret   = "test-secret-which-is-at-least-32-bytes!!"
	testAdminID         = "00000000-0000-0000-0000-0000000000ad"
	testHandlerUserID   = "00000000-0000-0000-0000-000000000001"
	testHandlerStreamID = "00000000-0000-0000-0000-000000000042"
)

// stubAdminService est un AdminService stub (pas de logique, juste des valeurs
// et paramètres capturés), à l'image de stubService dans streaming/handler_test.go.
type stubAdminService struct {
	listUsers    []AdminUser
	listTotal    int64
	listErr      error
	gotListInput ListUsersInput

	setActiveRet          AdminUser
	setActiveErr          error
	gotSetActiveTarget    string
	gotSetActiveRequester string
	gotSetActiveValue     bool

	deleteErr          error
	gotDeleteTarget    string
	gotDeleteRequester string

	listStreams          []AdminStream
	listStreamsTotal     int64
	listStreamsErr       error
	gotListStreamsLimit  int32
	gotListStreamsOffset int32

	stopStreamErr      error
	gotStopStreamID    string
	gotStopStreamActor string
}

func (s *stubAdminService) ListUsers(_ context.Context, in ListUsersInput) ([]AdminUser, int64, error) {
	s.gotListInput = in
	return s.listUsers, s.listTotal, s.listErr
}

func (s *stubAdminService) SetUserActive(_ context.Context, targetID, requesterID string, active bool) (AdminUser, error) {
	s.gotSetActiveTarget = targetID
	s.gotSetActiveRequester = requesterID
	s.gotSetActiveValue = active
	return s.setActiveRet, s.setActiveErr
}

func (s *stubAdminService) DeleteUser(_ context.Context, targetID, requesterID string) error {
	s.gotDeleteTarget = targetID
	s.gotDeleteRequester = requesterID
	return s.deleteErr
}

func (s *stubAdminService) ListLiveStreams(_ context.Context, limit, offset int32) ([]AdminStream, int64, error) {
	s.gotListStreamsLimit = limit
	s.gotListStreamsOffset = offset
	return s.listStreams, s.listStreamsTotal, s.listStreamsErr
}

func (s *stubAdminService) StopStream(_ context.Context, streamID, actorID string) error {
	s.gotStopStreamID = streamID
	s.gotStopStreamActor = actorID
	return s.stopStreamErr
}

// doList exécute GET /api/admin/users via RequireAuth + RequireRole(admin), comme
// le câblage réel (main.go).
func doList(t *testing.T, h *Handler, query string, role string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/api/admin/users"+query, nil)
	token, err := auth.GenerateAccessToken(testAdminID, role, testHandlerSecret, time.Now().UTC())
	if err != nil {
		t.Fatalf("generate token: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	auth.RequireAuth(testHandlerSecret, auth.RequireRole("admin", http.HandlerFunc(h.List))).ServeHTTP(rec, req)
	return rec
}

func TestHandler_List_OK(t *testing.T) {
	stub := &stubAdminService{
		listUsers: []AdminUser{{ID: testHandlerUserID, Email: "user1@streampulse.dev", Username: "user1", Role: "user", IsActive: true}},
		listTotal: 1,
	}
	h := NewHandler(stub)

	rec := doList(t, h, "", "admin")

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	body := rec.Body.String()
	if !strings.Contains(body, `"total":1`) || !strings.Contains(body, `"email":"user1@streampulse.dev"`) {
		t.Errorf("body incomplet: %s", body)
	}
}

func TestHandler_List_EmptyUsersIsEmptyArrayNotNull(t *testing.T) {
	h := NewHandler(&stubAdminService{})
	rec := doList(t, h, "", "admin")

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	if !strings.Contains(rec.Body.String(), `"users":[]`) {
		t.Errorf(`liste vide devrait sérialiser "users":[] et non null: %s`, rec.Body)
	}
}

func TestHandler_List_InvalidRole(t *testing.T) {
	h := NewHandler(&stubAdminService{})
	rec := doList(t, h, "?role=superadmin", "admin")

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_List_InvalidStatus(t *testing.T) {
	h := NewHandler(&stubAdminService{})
	rec := doList(t, h, "?status=archived", "admin")

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_List_PaginationClamp(t *testing.T) {
	stub := &stubAdminService{}
	h := NewHandler(stub)

	doList(t, h, "?limit=1000&offset=-5", "admin")
	if stub.gotListInput.Limit != maxListLimit {
		t.Errorf("limit = %d, want clamp à %d", stub.gotListInput.Limit, maxListLimit)
	}
	if stub.gotListInput.Offset != 0 {
		t.Errorf("offset = %d, want 0", stub.gotListInput.Offset)
	}

	doList(t, h, "", "admin")
	if stub.gotListInput.Limit != defaultListLimit {
		t.Errorf("limit par défaut = %d, want %d", stub.gotListInput.Limit, defaultListLimit)
	}
}

func TestHandler_List_ForbiddenForNonAdmin(t *testing.T) {
	stub := &stubAdminService{}
	h := NewHandler(stub)

	rec := doList(t, h, "", "user")

	if rec.Code != http.StatusForbidden {
		t.Fatalf("want 403, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_List_RequiresToken(t *testing.T) {
	h := NewHandler(&stubAdminService{})
	req := httptest.NewRequest(http.MethodGet, "/api/admin/users", nil)
	rec := httptest.NewRecorder()
	auth.RequireAuth(testHandlerSecret, auth.RequireRole("admin", http.HandlerFunc(h.List))).ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d: %s", rec.Code, rec.Body)
	}
}

// doPatch exécute PATCH /api/admin/users/{id} via RequireAuth (le rôle admin est
// vérifié au niveau du câblage réel, pas re-testé ici : cf. doList).
func doPatch(t *testing.T, h *Handler, id, body string, withToken bool) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPatch, "/api/admin/users/"+id, strings.NewReader(body))
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	req.SetPathValue("id", id)
	if withToken {
		token, err := auth.GenerateAccessToken(testAdminID, "admin", testHandlerSecret, time.Now().UTC())
		if err != nil {
			t.Fatalf("generate token: %v", err)
		}
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	auth.RequireAuth(testHandlerSecret, http.HandlerFunc(h.SetActive)).ServeHTTP(rec, req)
	return rec
}

func TestHandler_SetActive_OK(t *testing.T) {
	stub := &stubAdminService{setActiveRet: AdminUser{ID: testHandlerUserID, Email: "user1@streampulse.dev", Username: "user1", Role: "user", IsActive: false}}
	h := NewHandler(stub)

	rec := doPatch(t, h, testHandlerUserID, `{"is_active":false}`, true)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	if stub.gotSetActiveTarget != testHandlerUserID || stub.gotSetActiveRequester != testAdminID || stub.gotSetActiveValue {
		t.Errorf("params transmis = (%q, %q, %v)", stub.gotSetActiveTarget, stub.gotSetActiveRequester, stub.gotSetActiveValue)
	}
	if !strings.Contains(rec.Body.String(), `"is_active":false`) {
		t.Errorf("body incomplet: %s", rec.Body)
	}
}

func TestHandler_SetActive_MissingIsActive(t *testing.T) {
	h := NewHandler(&stubAdminService{})
	rec := doPatch(t, h, testHandlerUserID, `{}`, true)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d: %s", rec.Code, rec.Body)
	}
	if !strings.Contains(rec.Body.String(), "is_active") {
		t.Errorf("erreur devrait nommer is_active: %s", rec.Body)
	}
}

func TestHandler_SetActive_Conflict(t *testing.T) {
	stub := &stubAdminService{setActiveErr: apperror.Conflict("cannot modify your own account")}
	h := NewHandler(stub)

	rec := doPatch(t, h, testAdminID, `{"is_active":false}`, true)

	if rec.Code != http.StatusConflict {
		t.Fatalf("want 409, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_SetActive_NotFound(t *testing.T) {
	stub := &stubAdminService{setActiveErr: apperror.NotFound("user not found")}
	h := NewHandler(stub)

	rec := doPatch(t, h, "unknown", `{"is_active":true}`, true)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("want 404, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_SetActive_RequiresToken(t *testing.T) {
	h := NewHandler(&stubAdminService{})
	rec := doPatch(t, h, testHandlerUserID, `{"is_active":true}`, false)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d: %s", rec.Code, rec.Body)
	}
}

// doDelete exécute DELETE /api/admin/users/{id} via RequireAuth.
func doDelete(t *testing.T, h *Handler, id string, withToken bool) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodDelete, "/api/admin/users/"+id, nil)
	req.SetPathValue("id", id)
	if withToken {
		token, err := auth.GenerateAccessToken(testAdminID, "admin", testHandlerSecret, time.Now().UTC())
		if err != nil {
			t.Fatalf("generate token: %v", err)
		}
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	auth.RequireAuth(testHandlerSecret, http.HandlerFunc(h.Delete)).ServeHTTP(rec, req)
	return rec
}

func TestHandler_Delete_NoContent(t *testing.T) {
	stub := &stubAdminService{}
	h := NewHandler(stub)

	rec := doDelete(t, h, testHandlerUserID, true)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("want 204, got %d: %s", rec.Code, rec.Body)
	}
	if stub.gotDeleteTarget != testHandlerUserID || stub.gotDeleteRequester != testAdminID {
		t.Errorf("params transmis = (%q, %q)", stub.gotDeleteTarget, stub.gotDeleteRequester)
	}
}

func TestHandler_Delete_Conflict(t *testing.T) {
	stub := &stubAdminService{deleteErr: apperror.Conflict("cannot delete the last active admin")}
	h := NewHandler(stub)

	rec := doDelete(t, h, testAdminID, true)

	if rec.Code != http.StatusConflict {
		t.Fatalf("want 409, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Delete_NotFound(t *testing.T) {
	stub := &stubAdminService{deleteErr: apperror.NotFound("user not found")}
	h := NewHandler(stub)

	rec := doDelete(t, h, "unknown", true)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("want 404, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Delete_RequiresToken(t *testing.T) {
	h := NewHandler(&stubAdminService{})
	rec := doDelete(t, h, testHandlerUserID, false)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d: %s", rec.Code, rec.Body)
	}
}

// doListStreams exécute GET /api/admin/streams via RequireAuth + RequireRole(admin),
// comme le câblage réel (main.go). Même pattern que doList.
func doListStreams(t *testing.T, h *Handler, query string, role string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/api/admin/streams"+query, nil)
	token, err := auth.GenerateAccessToken(testAdminID, role, testHandlerSecret, time.Now().UTC())
	if err != nil {
		t.Fatalf("generate token: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	auth.RequireAuth(testHandlerSecret, auth.RequireRole("admin", http.HandlerFunc(h.ListStreams))).ServeHTTP(rec, req)
	return rec
}

func TestHandler_ListStreams_OK(t *testing.T) {
	stub := &stubAdminService{
		listStreams:      []AdminStream{{ID: testHandlerStreamID, Title: "Morning Jazz", IsPublic: true, UserID: testHandlerUserID, Username: "user1"}},
		listStreamsTotal: 1,
	}
	h := NewHandler(stub)

	rec := doListStreams(t, h, "", "admin")

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	body := rec.Body.String()
	if !strings.Contains(body, `"total":1`) || !strings.Contains(body, `"title":"Morning Jazz"`) {
		t.Errorf("body incomplet: %s", body)
	}
}

func TestHandler_ListStreams_EmptyStreamsIsEmptyArrayNotNull(t *testing.T) {
	h := NewHandler(&stubAdminService{})
	rec := doListStreams(t, h, "", "admin")

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	if !strings.Contains(rec.Body.String(), `"streams":[]`) {
		t.Errorf(`liste vide devrait sérialiser "streams":[] et non null: %s`, rec.Body)
	}
}

func TestHandler_ListStreams_PaginationClamp(t *testing.T) {
	stub := &stubAdminService{}
	h := NewHandler(stub)

	doListStreams(t, h, "?limit=1000&offset=-5", "admin")
	if stub.gotListStreamsLimit != maxListLimit {
		t.Errorf("limit = %d, want clamp à %d", stub.gotListStreamsLimit, maxListLimit)
	}
	if stub.gotListStreamsOffset != 0 {
		t.Errorf("offset = %d, want 0", stub.gotListStreamsOffset)
	}

	doListStreams(t, h, "", "admin")
	if stub.gotListStreamsLimit != defaultListLimit {
		t.Errorf("limit par défaut = %d, want %d", stub.gotListStreamsLimit, defaultListLimit)
	}
}

func TestHandler_ListStreams_ForbiddenForNonAdmin(t *testing.T) {
	stub := &stubAdminService{}
	h := NewHandler(stub)

	rec := doListStreams(t, h, "", "user")

	if rec.Code != http.StatusForbidden {
		t.Fatalf("want 403, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_ListStreams_RequiresToken(t *testing.T) {
	h := NewHandler(&stubAdminService{})
	req := httptest.NewRequest(http.MethodGet, "/api/admin/streams", nil)
	rec := httptest.NewRecorder()
	auth.RequireAuth(testHandlerSecret, auth.RequireRole("admin", http.HandlerFunc(h.ListStreams))).ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d: %s", rec.Code, rec.Body)
	}
}

// doStopStream exécute POST /api/admin/streams/{id}/stop via RequireAuth (le
// rôle admin est vérifié au niveau du câblage réel, pas re-testé ici : cf. doListStreams).
func doStopStream(t *testing.T, h *Handler, id string, withToken bool) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/api/admin/streams/"+id+"/stop", nil)
	req.SetPathValue("id", id)
	if withToken {
		token, err := auth.GenerateAccessToken(testAdminID, "admin", testHandlerSecret, time.Now().UTC())
		if err != nil {
			t.Fatalf("generate token: %v", err)
		}
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	auth.RequireAuth(testHandlerSecret, http.HandlerFunc(h.StopStream)).ServeHTTP(rec, req)
	return rec
}

func TestHandler_StopStream_NoContent(t *testing.T) {
	stub := &stubAdminService{}
	h := NewHandler(stub)

	rec := doStopStream(t, h, testHandlerStreamID, true)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("want 204, got %d: %s", rec.Code, rec.Body)
	}
	if stub.gotStopStreamID != testHandlerStreamID || stub.gotStopStreamActor != testAdminID {
		t.Errorf("params transmis = (%q, %q)", stub.gotStopStreamID, stub.gotStopStreamActor)
	}
}

func TestHandler_StopStream_Conflict(t *testing.T) {
	stub := &stubAdminService{stopStreamErr: apperror.Conflict("stream is not live")}
	h := NewHandler(stub)

	rec := doStopStream(t, h, testHandlerStreamID, true)

	if rec.Code != http.StatusConflict {
		t.Fatalf("want 409, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_StopStream_NotFound(t *testing.T) {
	stub := &stubAdminService{stopStreamErr: apperror.NotFound("stream not found")}
	h := NewHandler(stub)

	rec := doStopStream(t, h, "unknown", true)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("want 404, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_StopStream_RequiresToken(t *testing.T) {
	h := NewHandler(&stubAdminService{})
	rec := doStopStream(t, h, testHandlerStreamID, false)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d: %s", rec.Code, rec.Body)
	}
}
