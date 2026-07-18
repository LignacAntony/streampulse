package streaming

import (
	"context"
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
