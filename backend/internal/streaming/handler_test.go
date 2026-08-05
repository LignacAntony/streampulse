package streaming

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/LignacAntony/streampulse/internal/auth"
	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

const (
	testSecret    = "test-secret-which-is-at-least-32-bytes!!"
	testUserID    = "00000000-0000-0000-0000-000000000001"
	testIngestURL = "http://localhost:8080"
)

type stubService struct {
	ret      Stream
	err      error
	called   bool
	gotInput CreateStreamInput

	listRet   []Stream
	listErr   error
	gotLimit  int32
	gotOffset int32

	getRet         Stream
	getOwner       bool
	getErr         error
	updateRet      Stream
	updateErr      error
	gotUpdateInput UpdateStreamInput
	archiveErr     error
	gotID          string
	gotRequester   string

	startRet Stream
	startErr error
	stopRet  Stream
	stopErr  error

	addFavErr    error
	removeFavErr error
	listFavRet   []Stream
	listFavErr   error
	listMineRet  []Stream
	listMineErr  error
}

func (s *stubService) CreateStream(_ context.Context, in CreateStreamInput) (Stream, error) {
	s.called = true
	s.gotInput = in
	return s.ret, s.err
}

func (s *stubService) ListPublicLive(_ context.Context, limit, offset int32) ([]Stream, error) {
	s.gotLimit = limit
	s.gotOffset = offset
	return s.listRet, s.listErr
}

func (s *stubService) GetStream(_ context.Context, id, requesterID string) (Stream, bool, error) {
	s.gotID = id
	s.gotRequester = requesterID
	return s.getRet, s.getOwner, s.getErr
}

func (s *stubService) UpdateStream(_ context.Context, id, requesterID string, in UpdateStreamInput) (Stream, error) {
	s.gotID = id
	s.gotRequester = requesterID
	s.gotUpdateInput = in
	return s.updateRet, s.updateErr
}

func (s *stubService) ArchiveStream(_ context.Context, id, requesterID string) error {
	s.gotID = id
	s.gotRequester = requesterID
	return s.archiveErr
}

func (s *stubService) StartStream(_ context.Context, id, requesterID string) (Stream, error) {
	s.gotID = id
	s.gotRequester = requesterID
	return s.startRet, s.startErr
}

func (s *stubService) StopStream(_ context.Context, id, requesterID string) (Stream, error) {
	s.gotID = id
	s.gotRequester = requesterID
	return s.stopRet, s.stopErr
}

func (s *stubService) AddFavorite(_ context.Context, streamID, requesterID string) error {
	s.gotID = streamID
	s.gotRequester = requesterID
	return s.addFavErr
}

func (s *stubService) RemoveFavorite(_ context.Context, streamID, requesterID string) error {
	s.gotID = streamID
	s.gotRequester = requesterID
	return s.removeFavErr
}

func (s *stubService) ListFavorites(_ context.Context, requesterID string) ([]Stream, error) {
	s.gotRequester = requesterID
	return s.listFavRet, s.listFavErr
}

func (s *stubService) ListMyStreams(_ context.Context, requesterID string) ([]Stream, error) {
	s.gotRequester = requesterID
	return s.listMineRet, s.listMineErr
}

// doCreate exécute la requête à travers la chaîne réelle RequireAuth + RequireRole(broadcaster).
func doCreate(t *testing.T, h *Handler, method, role, body string, withToken bool) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, "/api/streams", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if withToken {
		token, err := auth.GenerateAccessToken(testUserID, role, testSecret, time.Now().UTC())
		if err != nil {
			t.Fatalf("generate token: %v", err)
		}
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret,
		auth.RequireRole("broadcaster", http.HandlerFunc(h.Create)),
	).ServeHTTP(rec, req)
	return rec
}

func TestHandler_Create_OK(t *testing.T) {
	stub := &stubService{ret: Stream{
		ID:        "s1",
		UserID:    testUserID,
		Title:     "Mon flux",
		Status:    StatusIdle,
		IsPublic:  true,
		StreamKey: "KEY123",
		CreatedAt: time.Now().UTC(),
	}}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	rec := doCreate(t, h, http.MethodPost, "broadcaster", `{"title":"Mon flux","is_public":true}`, true)

	if rec.Code != http.StatusCreated {
		t.Fatalf("want 201, got %d: %s", rec.Code, rec.Body)
	}
	if !stub.called {
		t.Fatal("service non appelé")
	}
	if stub.gotInput.UserID != testUserID || stub.gotInput.Title != "Mon flux" || !stub.gotInput.IsPublic {
		t.Errorf("input transmis = %+v", stub.gotInput)
	}
	body := rec.Body.String()
	for _, want := range []string{
		`"status":"idle"`,
		`"stream_key":"KEY123"`,
		`"stream_source_url":"http://localhost:8080/api/streams/ingest/KEY123"`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("body manque %s: %s", want, body)
		}
	}
}

func TestHandler_Create_MissingTitle(t *testing.T) {
	stub := &stubService{}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	rec := doCreate(t, h, http.MethodPost, "broadcaster", `{"is_public":true}`, true)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d: %s", rec.Code, rec.Body)
	}
	if !strings.Contains(rec.Body.String(), "title") {
		t.Errorf("erreur devrait nommer title: %s", rec.Body)
	}
	if stub.called {
		t.Error("service ne devrait pas être appelé")
	}
}

func TestHandler_Create_MissingIsPublic(t *testing.T) {
	h := NewHandler(&stubService{}, testIngestURL, NewLiveSessions(context.Background()))
	rec := doCreate(t, h, http.MethodPost, "broadcaster", `{"title":"Mon flux"}`, true)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d: %s", rec.Code, rec.Body)
	}
	if !strings.Contains(rec.Body.String(), "is_public") {
		t.Errorf("erreur devrait nommer is_public: %s", rec.Body)
	}
}

func TestHandler_Create_UnknownField(t *testing.T) {
	h := NewHandler(&stubService{}, testIngestURL, NewLiveSessions(context.Background()))
	rec := doCreate(t, h, http.MethodPost, "broadcaster", `{"title":"x","is_public":true,"foo":1}`, true)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Create_RequiresToken(t *testing.T) {
	h := NewHandler(&stubService{}, testIngestURL, NewLiveSessions(context.Background()))
	rec := doCreate(t, h, http.MethodPost, "broadcaster", `{"title":"x","is_public":true}`, false)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Create_ForbiddenForUser(t *testing.T) {
	stub := &stubService{}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	rec := doCreate(t, h, http.MethodPost, "user", `{"title":"x","is_public":true}`, true)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("want 403, got %d: %s", rec.Code, rec.Body)
	}
	if stub.called {
		t.Error("service ne devrait pas être appelé pour un rôle insuffisant")
	}
}

// doList exécute GET /api/streams via RequireAuth (sans rôle).
func doList(t *testing.T, h *Handler, query string, withToken bool) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/api/streams"+query, nil)
	if withToken {
		token, err := auth.GenerateAccessToken(testUserID, "user", testSecret, time.Now().UTC())
		if err != nil {
			t.Fatalf("generate token: %v", err)
		}
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret, http.HandlerFunc(h.List)).ServeHTTP(rec, req)
	return rec
}

func TestHandler_List_OK_NoStreamKey(t *testing.T) {
	stub := &stubService{listRet: []Stream{
		{ID: "s1", UserID: "u9", Title: "En direct", Status: StatusLive, IsPublic: true, StreamKey: "SECRET_KEY"},
	}}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	rec := doList(t, h, "", true)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	body := rec.Body.String()
	if !strings.Contains(body, `"title":"En direct"`) {
		t.Errorf("body manque le flux: %s", body)
	}
	// Sécurité : aucun secret ne doit fuiter dans la liste.
	if strings.Contains(body, "SECRET_KEY") || strings.Contains(body, "stream_key") || strings.Contains(body, "stream_source_url") {
		t.Errorf("la liste ne doit pas exposer la clé/URL source: %s", body)
	}
}

func TestHandler_List_RequiresToken(t *testing.T) {
	h := NewHandler(&stubService{}, testIngestURL, NewLiveSessions(context.Background()))
	rec := doList(t, h, "", false)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_List_PaginationClamp(t *testing.T) {
	stub := &stubService{}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	doList(t, h, "?limit=999&offset=-5", true)
	if stub.gotLimit != MaxListLimit {
		t.Errorf("limit = %d, want clamp à %d", stub.gotLimit, MaxListLimit)
	}
	if stub.gotOffset != 0 {
		t.Errorf("offset = %d, want 0", stub.gotOffset)
	}

	doList(t, h, "", true)
	if stub.gotLimit != DefaultListLimit {
		t.Errorf("limit par défaut = %d, want %d", stub.gotLimit, DefaultListLimit)
	}
}

// doID exécute GET/PUT/DELETE /api/streams/{id} via RequireAuth, avec le path
// value renseigné (comme le ferait le ServeMux).
func doID(t *testing.T, method, id, body string, h http.Handler, withToken bool) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, "/api/streams/"+id, strings.NewReader(body))
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	req.SetPathValue("id", id)
	if withToken {
		token, err := auth.GenerateAccessToken(testUserID, "user", testSecret, time.Now().UTC())
		if err != nil {
			t.Fatalf("generate token: %v", err)
		}
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret, h).ServeHTTP(rec, req)
	return rec
}

func TestHandler_Get_OwnerFull(t *testing.T) {
	stub := &stubService{
		getOwner: true,
		getRet:   Stream{ID: "s1", UserID: testUserID, Title: "Mon flux", Status: StatusIdle, StreamKey: "KEY123"},
	}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	rec := doID(t, http.MethodGet, "s1", "", http.HandlerFunc(h.Get), true)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	body := rec.Body.String()
	if !strings.Contains(body, `"stream_key":"KEY123"`) || !strings.Contains(body, "stream_source_url") {
		t.Errorf("le propriétaire doit recevoir la clé + URL source: %s", body)
	}
}

func TestHandler_Get_NonOwnerNoSecrets(t *testing.T) {
	stub := &stubService{
		getOwner: false,
		getRet:   Stream{ID: "s1", UserID: "autre", Title: "Public", IsPublic: true, StreamKey: "SECRET"},
	}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	rec := doID(t, http.MethodGet, "s1", "", http.HandlerFunc(h.Get), true)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	body := rec.Body.String()
	// Réponse parsable par le client (même schéma), mais secrets à null et
	// jamais la valeur réelle de la clé.
	if !strings.Contains(body, `"stream_key":null`) || !strings.Contains(body, `"stream_source_url":null`) {
		t.Errorf("un tiers doit recevoir stream_key/stream_source_url à null: %s", body)
	}
	if strings.Contains(body, "SECRET") {
		t.Errorf("la valeur du stream_key ne doit jamais fuiter: %s", body)
	}
	// Le reste des métadonnées publiques reste présent.
	if !strings.Contains(body, `"title":"Public"`) {
		t.Errorf("body manque les métadonnées: %s", body)
	}
}

func TestHandler_Get_NotFound(t *testing.T) {
	stub := &stubService{getErr: apperror.NotFound("stream not found")}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	rec := doID(t, http.MethodGet, "s1", "", http.HandlerFunc(h.Get), true)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("want 404, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Update_OK(t *testing.T) {
	stub := &stubService{updateRet: Stream{ID: "s1", UserID: testUserID, Title: "Nouveau", StreamKey: "KEY123"}}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	rec := doID(t, http.MethodPut, "s1", `{"title":"Nouveau","is_public":false}`, http.HandlerFunc(h.Update), true)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	if stub.gotID != "s1" || stub.gotRequester != testUserID {
		t.Errorf("scope owner = (%q, %q)", stub.gotID, stub.gotRequester)
	}
	if !strings.Contains(rec.Body.String(), `"stream_key":"KEY123"`) {
		t.Errorf("le propriétaire doit recevoir la clé: %s", rec.Body)
	}
}

func TestHandler_Update_MissingTitle(t *testing.T) {
	h := NewHandler(&stubService{}, testIngestURL, NewLiveSessions(context.Background()))
	rec := doID(t, http.MethodPut, "s1", `{"is_public":true}`, http.HandlerFunc(h.Update), true)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Update_NotFound(t *testing.T) {
	stub := &stubService{updateErr: apperror.NotFound("stream not found")}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	rec := doID(t, http.MethodPut, "s1", `{"title":"Nouveau","is_public":true}`, http.HandlerFunc(h.Update), true)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("want 404, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Delete_NoContent(t *testing.T) {
	stub := &stubService{}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	rec := doID(t, http.MethodDelete, "s1", "", http.HandlerFunc(h.Delete), true)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("want 204, got %d: %s", rec.Code, rec.Body)
	}
	if stub.gotID != "s1" {
		t.Errorf("id transmis = %q, want s1", stub.gotID)
	}
}

func TestHandler_Delete_NotFound(t *testing.T) {
	stub := &stubService{archiveErr: apperror.NotFound("stream not found")}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	rec := doID(t, http.MethodDelete, "s1", "", http.HandlerFunc(h.Delete), true)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("want 404, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Delete_RequiresToken(t *testing.T) {
	h := NewHandler(&stubService{}, testIngestURL, NewLiveSessions(context.Background()))
	rec := doID(t, http.MethodDelete, "s1", "", http.HandlerFunc(h.Delete), false)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Start_OK(t *testing.T) {
	stub := &stubService{startRet: Stream{ID: "s1", UserID: testUserID, Status: StatusLive, StreamKey: "KEY123"}}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	rec := doID(t, http.MethodPatch, "s1", "", http.HandlerFunc(h.Start), true)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	body := rec.Body.String()
	if !strings.Contains(body, `"status":"live"`) || !strings.Contains(body, `"stream_key":"KEY123"`) {
		t.Errorf("réponse start incomplète (status live + clé): %s", body)
	}
	if stub.gotID != "s1" || stub.gotRequester != testUserID {
		t.Errorf("scope owner = (%q, %q)", stub.gotID, stub.gotRequester)
	}
}

func TestHandler_Start_Conflict(t *testing.T) {
	stub := &stubService{startErr: apperror.Conflict("you already have a live stream")}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	rec := doID(t, http.MethodPatch, "s1", "", http.HandlerFunc(h.Start), true)

	if rec.Code != http.StatusConflict {
		t.Fatalf("want 409, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Start_NotFound(t *testing.T) {
	stub := &stubService{startErr: apperror.NotFound("stream not found")}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	rec := doID(t, http.MethodPatch, "s1", "", http.HandlerFunc(h.Start), true)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("want 404, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Start_RequiresToken(t *testing.T) {
	h := NewHandler(&stubService{}, testIngestURL, NewLiveSessions(context.Background()))
	rec := doID(t, http.MethodPatch, "s1", "", http.HandlerFunc(h.Start), false)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Stop_OK(t *testing.T) {
	stub := &stubService{stopRet: Stream{ID: "s1", UserID: testUserID, Status: StatusEnded, StreamKey: "KEY123"}}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	rec := doID(t, http.MethodPatch, "s1", "", http.HandlerFunc(h.Stop), true)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	if !strings.Contains(rec.Body.String(), `"status":"ended"`) {
		t.Errorf("statut ended attendu: %s", rec.Body)
	}
}

func TestHandler_Stop_Conflict(t *testing.T) {
	stub := &stubService{stopErr: apperror.Conflict("stream is not live")}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	rec := doID(t, http.MethodPatch, "s1", "", http.HandlerFunc(h.Stop), true)

	if rec.Code != http.StatusConflict {
		t.Fatalf("want 409, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Events_NotLive_Conflict(t *testing.T) {
	// Flux visible mais sans session active -> 409.
	stub := &stubService{getOwner: true, getRet: Stream{ID: "s1", UserID: testUserID, IsPublic: true}}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	rec := doID(t, http.MethodGet, "s1", "", http.HandlerFunc(h.Events), true)

	if rec.Code != http.StatusConflict {
		t.Fatalf("want 409, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Events_NotFound(t *testing.T) {
	stub := &stubService{getErr: apperror.NotFound("stream not found")}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	rec := doID(t, http.MethodGet, "s1", "", http.HandlerFunc(h.Events), true)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("want 404, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Events_RequiresToken(t *testing.T) {
	h := NewHandler(&stubService{}, testIngestURL, NewLiveSessions(context.Background()))
	rec := doID(t, http.MethodGet, "s1", "", http.HandlerFunc(h.Events), false)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d: %s", rec.Code, rec.Body)
	}
}

// flushSignalRecorder ferme `flushed` au premier Flush du handler (= headers
// envoyés, donc handler abonné et dans sa boucle) — permet un test SSE
// déterministe sans sleep.
type flushSignalRecorder struct {
	*httptest.ResponseRecorder
	once    sync.Once
	flushed chan struct{}
}

func (f *flushSignalRecorder) Flush() {
	f.once.Do(func() { close(f.flushed) })
	f.ResponseRecorder.Flush()
}

func TestHandler_Events_StreamsEndedThenCloses(t *testing.T) {
	sessions := newTestSessions(context.Background())
	sessions.Start("s1", "")
	stub := &stubService{getOwner: true, getRet: Stream{ID: "s1", UserID: testUserID, IsPublic: true}}
	h := NewHandler(stub, testIngestURL, sessions)

	token, err := auth.GenerateAccessToken(testUserID, "user", testSecret, time.Now().UTC())
	if err != nil {
		t.Fatalf("generate token: %v", err)
	}
	req := httptest.NewRequest(http.MethodGet, "/api/streams/s1/events", nil)
	req.SetPathValue("id", "s1")
	req.Header.Set("Authorization", "Bearer "+token)
	sw := &flushSignalRecorder{ResponseRecorder: httptest.NewRecorder(), flushed: make(chan struct{})}

	done := make(chan struct{})
	go func() {
		auth.RequireAuth(testSecret, http.HandlerFunc(h.Events)).ServeHTTP(sw, req)
		close(done)
	}()

	// Attendre que le handler ait envoyé les headers (donc soit abonné), sans sleep.
	select {
	case <-sw.flushed:
	case <-time.After(2 * time.Second):
		t.Fatal("le handler SSE ne s'est pas initialisé")
	}
	sessions.Stop("s1") // publie "ended" + ferme le canal

	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("le handler SSE n'a pas terminé après Stop")
	}

	if sw.Code != http.StatusOK {
		t.Fatalf("want 200, got %d", sw.Code)
	}
	if !strings.Contains(sw.Body.String(), "event: ended") {
		t.Errorf("le flux SSE doit contenir l'event ended: %s", sw.Body.String())
	}
}

func TestHandler_Ingest_RejectsNonAudioContentType(t *testing.T) {
	ls := sessionsWithFakeSeg(t)
	ls.Start("sid-415", "KEY415")
	defer ls.StopAll()
	h := NewHandler(&stubService{}, testIngestURL, ls)

	req := httptest.NewRequest(http.MethodPost, "/api/streams/ingest/KEY415", strings.NewReader("garbage"))
	req.SetPathValue("stream_key", "KEY415")
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	rec := httptest.NewRecorder()

	h.Ingest(rec, req)

	if rec.Code != http.StatusUnsupportedMediaType {
		t.Fatalf("want 415 pour un content-type non-audio, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Ingest_AllowsAbsentContentType(t *testing.T) {
	ls := sessionsWithFakeSeg(t)
	ls.Start("sid-noct", "KEYNOCT")
	defer ls.StopAll()
	h := NewHandler(&stubService{}, testIngestURL, ls)

	req := httptest.NewRequest(http.MethodPost, "/api/streams/ingest/KEYNOCT", strings.NewReader(""))
	req.SetPathValue("stream_key", "KEYNOCT")
	req.Header.Del("Content-Type") // absent -> accepté (lenient, cf. ADR 015)
	rec := httptest.NewRecorder()

	h.Ingest(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("want 204 (content-type absent accepté), got %d: %s", rec.Code, rec.Body)
	}
}

// Le push d'ingest dure tout le direct : il doit échapper au ReadTimeout court
// d'http.Server. Sans bail configuré (grace = 0), la deadline de lecture doit
// être explicitement neutralisée, sinon un push lent mais parfaitement sain se
// ferait couper au bout de quelques secondes.
func TestHandler_Ingest_SurvivesServerReadTimeoutWithoutGrace(t *testing.T) {
	ls := sessionsWithFakeSeg(t)
	ls.Start("sid-slow", "KEYSLOW")
	defer ls.StopAll()
	h := NewHandler(&stubService{}, testIngestURL, ls)

	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/streams/ingest/{stream_key}", h.Ingest)
	srv := httptest.NewUnstartedServer(mux)
	srv.Config.ReadTimeout = 100 * time.Millisecond
	srv.Start()
	defer srv.Close()

	// Corps envoyé en deux morceaux séparés par plus que le ReadTimeout.
	body, writer := io.Pipe()
	go func() {
		_, _ = writer.Write([]byte{0xff, 0xf1})
		time.Sleep(300 * time.Millisecond)
		_, _ = writer.Write([]byte{0x50, 0x80})
		_ = writer.Close()
	}()

	req, err := http.NewRequest(http.MethodPost, srv.URL+"/api/streams/ingest/KEYSLOW", body)
	if err != nil {
		t.Fatalf("build request: %v", err)
	}
	req.Header.Set("Content-Type", "audio/aac")
	resp, err := srv.Client().Do(req)
	if err != nil {
		t.Fatalf("push interrompu par le ReadTimeout du serveur: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("want 204, got %d", resp.StatusCode)
	}
}

// TestHandler_Playlist_NotReadyReturnsJSON409 : session vivante mais manifeste pas
// encore écrit sur disque -> 409 JSON (contrat) et non un 404 text/plain brut.
func TestHandler_Playlist_NotReadyReturnsJSON409(t *testing.T) {
	seg := fakeSegmenter(t)
	if err := os.Remove(filepath.Join(seg.dir, hlsPlaylistName)); err != nil {
		t.Fatalf("remove playlist: %v", err)
	}
	ls := NewLiveSessions(context.Background())
	ls.newSeg = func() (*hlsSegmenter, error) { return seg, nil }
	ls.Start("sid-nr", "KEYNR")
	defer ls.StopAll()

	stub := &stubService{getRet: Stream{ID: "sid-nr", UserID: testUserID, IsPublic: true}}
	h := NewHandler(stub, testIngestURL, ls)

	token, err := auth.GenerateAccessToken(testUserID, "user", testSecret, time.Now().UTC())
	if err != nil {
		t.Fatalf("token: %v", err)
	}
	req := httptest.NewRequest(http.MethodGet, "/api/streams/sid-nr/playlist.m3u8", nil)
	req.SetPathValue("id", "sid-nr")
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()

	auth.RequireAuth(testSecret, http.HandlerFunc(h.Playlist)).ServeHTTP(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("want 409 (manifeste pas encore écrit), got %d: %s", rec.Code, rec.Body)
	}
	if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "application/json") {
		t.Fatalf("l'erreur doit rester JSON, content-type=%q", ct)
	}
}

// newLiveHandler construit un handler dont le flux `id` a une session live
// (segmenteur simulé), avec le service stubbé fourni. La session est nettoyée en
// fin de test.
func newLiveHandler(t *testing.T, id string, svc StreamService) *Handler {
	t.Helper()
	ls := sessionsWithFakeSeg(t)
	ls.Start(id, "KEY-"+id)
	t.Cleanup(ls.StopAll)
	return NewHandler(svc, testIngestURL, ls)
}

// TestHandler_Playlist_PublicNoAuth : lecture publique (STR-108) — le handler sert
// un flux public sans identité dans le context (anonyme).
func TestHandler_Playlist_PublicNoAuth(t *testing.T) {
	h := newLiveHandler(t, "pub", &stubService{getRet: Stream{ID: "pub", UserID: "owner-uuid", IsPublic: true}})

	req := httptest.NewRequest(http.MethodGet, "/api/streams/pub/playlist.m3u8", nil)
	req.SetPathValue("id", "pub")
	rec := httptest.NewRecorder()

	h.Playlist(rec, req) // aucune identité dans le context

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200 (lecture publique), got %d: %s", rec.Code, rec.Body)
	}
	if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "application/vnd.apple.mpegurl") {
		t.Fatalf("content-type manifeste attendu, got %q", ct)
	}
}

func TestHandler_Segment_PublicNoAuth(t *testing.T) {
	h := newLiveHandler(t, "pub2", &stubService{getRet: Stream{ID: "pub2", UserID: "owner-uuid", IsPublic: true}})

	req := httptest.NewRequest(http.MethodGet, "/api/streams/pub2/segments/seg_00000.ts", nil)
	req.SetPathValue("id", "pub2")
	req.SetPathValue("segment", "seg_00000.ts")
	rec := httptest.NewRecorder()

	h.Segment(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200 (segment public), got %d: %s", rec.Code, rec.Body)
	}
}

// TestHandler_Playlist_PrivateNoAuth_Returns404 : un anonyme sur un flux privé/absent
// reçoit 404 (visibilité gérée par GetStream), jamais 401. Aucune session live n'est
// nécessaire : le handler sort sur GetStream avant le lookup de session.
func TestHandler_Playlist_PrivateNoAuth_Returns404(t *testing.T) {
	h := NewHandler(&stubService{getErr: apperror.NotFound("stream not found")}, testIngestURL, NewLiveSessions(context.Background()))

	req := httptest.NewRequest(http.MethodGet, "/api/streams/priv/playlist.m3u8", nil)
	req.SetPathValue("id", "priv")
	rec := httptest.NewRecorder()

	h.Playlist(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("want 404 (flux privé/absent, anonyme), got %d: %s", rec.Code, rec.Body)
	}
}

// TestHandler_Playlist_ViaOptionalAuth exerce la vraie chaîne middleware (comme
// main.go) : anonyme sur flux public -> 200 ; propriétaire authentifié sur flux
// privé -> 200 (préserve la lecture propriétaire — régression corrigée).
func TestHandler_Playlist_ViaOptionalAuth(t *testing.T) {
	// Anonyme (aucun header Authorization), flux public -> 200.
	pub := newLiveHandler(t, "pubc", &stubService{getRet: Stream{ID: "pubc", UserID: testUserID, IsPublic: true}})
	req := httptest.NewRequest(http.MethodGet, "/api/streams/pubc/playlist.m3u8", nil)
	req.SetPathValue("id", "pubc")
	rec := httptest.NewRecorder()
	auth.OptionalAuth(testSecret, http.HandlerFunc(pub.Playlist)).ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("anonyme/flux public via OptionalAuth: want 200, got %d: %s", rec.Code, rec.Body)
	}

	// Propriétaire authentifié (token valide), flux privé -> 200.
	owner := newLiveHandler(t, "prvc", &stubService{getRet: Stream{ID: "prvc", UserID: testUserID, IsPublic: false}, getOwner: true})
	token, err := auth.GenerateAccessToken(testUserID, "broadcaster", testSecret, time.Now().UTC())
	if err != nil {
		t.Fatalf("token: %v", err)
	}
	req2 := httptest.NewRequest(http.MethodGet, "/api/streams/prvc/playlist.m3u8", nil)
	req2.SetPathValue("id", "prvc")
	req2.Header.Set("Authorization", "Bearer "+token)
	rec2 := httptest.NewRecorder()
	auth.OptionalAuth(testSecret, http.HandlerFunc(owner.Playlist)).ServeHTTP(rec2, req2)
	if rec2.Code != http.StatusOK {
		t.Fatalf("propriétaire/flux privé via OptionalAuth: want 200, got %d: %s", rec2.Code, rec2.Body)
	}
}

func TestHandler_AddFavorite_NoContent(t *testing.T) {
	stub := &stubService{}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	rec := doID(t, http.MethodPut, "s1", "", http.HandlerFunc(h.AddFavorite), true)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("want 204, got %d: %s", rec.Code, rec.Body)
	}
	if stub.gotID != "s1" || stub.gotRequester != testUserID {
		t.Errorf("service reçu (id=%q, requester=%q)", stub.gotID, stub.gotRequester)
	}
}

func TestHandler_AddFavorite_NotVisible_NotFound(t *testing.T) {
	stub := &stubService{addFavErr: apperror.NotFound("stream not found")}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	rec := doID(t, http.MethodPut, "s1", "", http.HandlerFunc(h.AddFavorite), true)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("want 404, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_AddFavorite_Unauthenticated(t *testing.T) {
	stub := &stubService{}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	rec := doID(t, http.MethodPut, "s1", "", http.HandlerFunc(h.AddFavorite), false)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_RemoveFavorite_NoContent(t *testing.T) {
	stub := &stubService{}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	rec := doID(t, http.MethodDelete, "s1", "", http.HandlerFunc(h.RemoveFavorite), true)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("want 204, got %d: %s", rec.Code, rec.Body)
	}
	if stub.gotID != "s1" || stub.gotRequester != testUserID {
		t.Errorf("service reçu (id=%q, requester=%q)", stub.gotID, stub.gotRequester)
	}
}

func TestHandler_ListFavorites_OK(t *testing.T) {
	stub := &stubService{listFavRet: []Stream{
		{ID: "s1", UserID: "u9", Title: "Flux A", Status: StatusLive, IsPublic: true, StreamKey: "SECRET"},
		{ID: "s2", UserID: testUserID, Title: "Flux B", Status: StatusIdle, IsPublic: false},
	}}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	req := httptest.NewRequest(http.MethodGet, "/api/users/me/favorites", nil)
	token, err := auth.GenerateAccessToken(testUserID, "user", testSecret, time.Now().UTC())
	if err != nil {
		t.Fatalf("token: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret, http.HandlerFunc(h.ListFavorites)).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	if stub.gotRequester != testUserID {
		t.Errorf("requester = %q, want %q", stub.gotRequester, testUserID)
	}
	body := rec.Body.String()
	if !strings.Contains(body, `"id":"s1"`) || !strings.Contains(body, `"id":"s2"`) {
		t.Errorf("body manque des flux: %s", body)
	}
	if strings.Contains(body, "stream_key") || strings.Contains(body, "SECRET") {
		t.Errorf("la liste des favoris ne doit jamais exposer de secret: %s", body)
	}
}

func TestHandler_Stats_OwnerOK(t *testing.T) {
	started := time.Now().Add(-2 * time.Minute)
	stub := &stubService{
		getOwner: true,
		getRet: Stream{
			ID: "s1", UserID: testUserID, Title: "Mon flux",
			Status: StatusLive, StartedAt: &started,
		},
	}
	sessions := NewLiveSessions(t.Context())
	h := NewHandler(stub, testIngestURL, sessions)

	rec := doID(t, http.MethodGet, "s1", "", http.HandlerFunc(h.Stats), true)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	body := rec.Body.String()
	// Aucune session active : compteurs à zéro, mais la durée reste calculée
	// depuis started_at.
	if !strings.Contains(body, `"listeners":0`) || !strings.Contains(body, `"peak_listeners":0`) {
		t.Errorf("compteurs attendus à zéro sans session: %s", body)
	}
	if !strings.Contains(body, `"duration_seconds":12`) {
		t.Errorf("durée attendue autour de 120 s: %s", body)
	}
}

func TestHandler_Stats_CountsListeners(t *testing.T) {
	started := time.Now().Add(-time.Minute)
	stub := &stubService{
		getOwner: true,
		getRet: Stream{
			ID: "s1", UserID: testUserID, Status: StatusLive, StartedAt: &started,
		},
	}
	sessions := NewLiveSessions(t.Context())
	sessions.Start("s1", "KEY")
	t.Cleanup(func() { sessions.Stop("s1") })
	sessions.TouchListener("s1", "10.0.0.1")
	sessions.TouchListener("s1", "10.0.0.2")

	h := NewHandler(stub, testIngestURL, sessions)
	rec := doID(t, http.MethodGet, "s1", "", http.HandlerFunc(h.Stats), true)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	body := rec.Body.String()
	if !strings.Contains(body, `"listeners":2`) || !strings.Contains(body, `"peak_listeners":2`) {
		t.Errorf("deux auditeurs distincts attendus: %s", body)
	}
}

func TestHandler_Stats_NotOwnerIs404(t *testing.T) {
	// Un tiers ne doit pas apprendre l'audience d'un flux, ni même son
	// existence : 404 et non 403.
	stub := &stubService{
		getOwner: false,
		getRet:   Stream{ID: "s1", UserID: "autre", Status: StatusLive},
	}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(t.Context()))

	rec := doID(t, http.MethodGet, "s1", "", http.HandlerFunc(h.Stats), true)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("want 404, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_Stats_Unauthenticated(t *testing.T) {
	h := NewHandler(&stubService{}, testIngestURL, NewLiveSessions(t.Context()))

	rec := doID(t, http.MethodGet, "s1", "", http.HandlerFunc(h.Stats), false)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d: %s", rec.Code, rec.Body)
	}
}

func TestHandler_ClientKey_IgnoresForwardedForByDefault(t *testing.T) {
	// X-Forwarded-For est falsifiable : sans reverse proxy devant, le lire
	// laisserait n'importe qui gonfler le compteur en variant sa valeur.
	h := NewHandler(&stubService{}, testIngestURL, NewLiveSessions(t.Context()))
	req := httptest.NewRequest(http.MethodGet, "/api/streams/s1/playlist.m3u8", nil)
	req.RemoteAddr = "192.0.2.10:54321"
	req.Header.Set("X-Forwarded-For", "1.2.3.4")

	if got := h.clientKey(req); got != "192.0.2.10" {
		t.Errorf("clientKey = %q, want %q", got, "192.0.2.10")
	}
}

func TestHandler_ClientKey_UsesFirstForwardedHopWhenTrusted(t *testing.T) {
	h := NewHandler(&stubService{}, testIngestURL, NewLiveSessions(t.Context()))
	h.SetTrustProxyHeaders(true)
	req := httptest.NewRequest(http.MethodGet, "/api/streams/s1/playlist.m3u8", nil)
	req.RemoteAddr = "192.0.2.10:54321"
	// Premier maillon = client d'origine, les suivants sont les proxies.
	req.Header.Set("X-Forwarded-For", "1.2.3.4, 10.0.0.1")

	if got := h.clientKey(req); got != "1.2.3.4" {
		t.Errorf("clientKey = %q, want %q", got, "1.2.3.4")
	}
}

func TestHandler_ListMine_OK(t *testing.T) {
	stub := &stubService{listMineRet: []Stream{
		{ID: "s1", UserID: testUserID, Title: "En direct", Status: StatusLive, IsPublic: true, StreamKey: "SECRET1"},
		{ID: "s2", UserID: testUserID, Title: "Prêt", Status: StatusIdle, IsPublic: false, StreamKey: "SECRET2"},
	}}
	h := NewHandler(stub, testIngestURL, NewLiveSessions(context.Background()))

	rec := doListMine(t, h, true)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	if stub.gotRequester != testUserID {
		t.Errorf("requester = %q, want %q", stub.gotRequester, testUserID)
	}
	body := rec.Body.String()
	if !strings.Contains(body, `"id":"s1"`) || !strings.Contains(body, `"id":"s2"`) {
		t.Errorf("body manque des flux: %s", body)
	}
	// Contrairement à toutes les autres listes, celle-ci DOIT porter les secrets :
	// c'est ce qui permet au diffuseur de configurer son encodeur.
	if !strings.Contains(body, `"stream_key":"SECRET1"`) {
		t.Errorf("le propriétaire doit recevoir sa stream_key: %s", body)
	}
	if !strings.Contains(body, testIngestURL+"/api/streams/ingest/SECRET2") {
		t.Errorf("le propriétaire doit recevoir son stream_source_url: %s", body)
	}
}

func TestHandler_ListMine_EmptyIsArrayNotNull(t *testing.T) {
	// Un non-diffuseur (ou un diffuseur sans flux) reçoit [] et non null : le
	// client n'a aucun cas particulier à traiter (ADR 024).
	h := NewHandler(&stubService{}, testIngestURL, NewLiveSessions(context.Background()))

	rec := doListMine(t, h, true)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body)
	}
	if got := strings.TrimSpace(rec.Body.String()); got != "[]" {
		t.Errorf("body = %q, want %q", got, "[]")
	}
}

func TestHandler_ListMine_Unauthenticated(t *testing.T) {
	h := NewHandler(&stubService{}, testIngestURL, NewLiveSessions(context.Background()))

	rec := doListMine(t, h, false)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d: %s", rec.Code, rec.Body)
	}
}

// doListMine exécute GET /api/users/me/streams à travers RequireAuth réel.
func doListMine(t *testing.T, h *Handler, withToken bool) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/api/users/me/streams", nil)
	if withToken {
		token, err := auth.GenerateAccessToken(testUserID, "broadcaster", testSecret, time.Now().UTC())
		if err != nil {
			t.Fatalf("token: %v", err)
		}
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret, http.HandlerFunc(h.ListMine)).ServeHTTP(rec, req)
	return rec
}

func TestHandler_ListFavorites_Unauthenticated(t *testing.T) {
	h := NewHandler(&stubService{}, testIngestURL, NewLiveSessions(context.Background()))

	req := httptest.NewRequest(http.MethodGet, "/api/users/me/favorites", nil)
	rec := httptest.NewRecorder()
	auth.RequireAuth(testSecret, http.HandlerFunc(h.ListFavorites)).ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d: %s", rec.Code, rec.Body)
	}
}
