package streaming

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

// stubRecorder capture les appels du domaine vers l'infra métriques.
type stubRecorder struct {
	mu        sync.Mutex
	requests  []string // "streamID|kind|status"
	forgotten []string
}

func (s *stubRecorder) RecordHLSRequest(streamID, kind, status string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.requests = append(s.requests, streamID+"|"+kind+"|"+status)
}

func (s *stubRecorder) ForgetStream(streamID string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.forgotten = append(s.forgotten, streamID)
}

func (s *stubRecorder) forgottenIDs() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]string(nil), s.forgotten...)
}

func TestLiveSessions_ActiveCount(t *testing.T) {
	ls := NewLiveSessions(context.Background())
	ls.newSeg = func() (*hlsSegmenter, error) { return nil, errors.New("pas de ffmpeg en test") }

	if got := ls.ActiveCount(); got != 0 {
		t.Fatalf("ActiveCount() au repos = %d, want 0", got)
	}

	ls.Start("stream-a", "key-a")
	ls.Start("stream-b", "key-b")
	if got := ls.ActiveCount(); got != 2 {
		t.Errorf("ActiveCount() après 2 démarrages = %d, want 2", got)
	}

	ls.Stop("stream-a")
	if got := ls.ActiveCount(); got != 1 {
		t.Errorf("ActiveCount() après arrêt = %d, want 1", got)
	}

	ls.StopAll()
	if got := ls.ActiveCount(); got != 0 {
		t.Errorf("ActiveCount() après StopAll = %d, want 0", got)
	}
}

func TestLiveSessions_ForgetsStreamOnStop(t *testing.T) {
	rec := &stubRecorder{}
	ls := NewLiveSessions(context.Background())
	ls.newSeg = func() (*hlsSegmenter, error) { return nil, errors.New("pas de ffmpeg en test") }
	ls.SetMetrics(rec)

	ls.Start("stream-a", "key-a")
	ls.Stop("stream-a")

	// Les séries labellisées par stream_id doivent disparaître à l'arrêt,
	// sinon la cardinalité croît à chaque diffusion (ADR 022).
	if got := rec.forgottenIDs(); len(got) != 1 || got[0] != "stream-a" {
		t.Errorf("ForgetStream = %v, want [stream-a]", got)
	}
}

func TestLiveSessions_ForgetsAllStreamsOnStopAll(t *testing.T) {
	rec := &stubRecorder{}
	ls := NewLiveSessions(context.Background())
	ls.newSeg = func() (*hlsSegmenter, error) { return nil, errors.New("pas de ffmpeg en test") }
	ls.SetMetrics(rec)

	ls.Start("stream-a", "key-a")
	ls.Start("stream-b", "key-b")
	ls.StopAll()

	if got := rec.forgottenIDs(); len(got) != 2 {
		t.Errorf("ForgetStream appelé %d fois (%v), want 2", len(got), got)
	}
}

func TestLiveSessions_NilRecorderIsSafe(t *testing.T) {
	// Aucun recorder injecté (tests existants, binaires sans métriques) :
	// le domaine ne doit pas paniquer.
	ls := NewLiveSessions(context.Background())
	ls.newSeg = func() (*hlsSegmenter, error) { return nil, errors.New("pas de ffmpeg en test") }

	ls.Start("stream-a", "key-a")
	ls.Stop("stream-a")
	ls.StopAll()
}

func TestHandler_RecordsHLSRequests(t *testing.T) {
	rec := &stubRecorder{}
	ls := sessionsWithFakeSeg(t)
	ls.SetMetrics(rec)
	ls.Start("sid", "KEY-sid")
	t.Cleanup(ls.StopAll)
	h := NewHandler(&stubService{getRet: Stream{ID: "sid", UserID: "owner", IsPublic: true}}, testIngestURL, ls)
	h.SetMetrics(rec)

	// Playlist servie (manifeste présent) puis segment inexistant : les deux
	// sont comptés, avec le status réellement rendu à l'auditeur.
	reqPlaylist := httptest.NewRequest(http.MethodGet, "/api/streams/sid/playlist.m3u8", nil)
	reqPlaylist.SetPathValue("id", "sid")
	h.Playlist(httptest.NewRecorder(), reqPlaylist)

	reqSegment := httptest.NewRequest(http.MethodGet, "/api/streams/sid/segments/seg_99999.ts", nil)
	reqSegment.SetPathValue("id", "sid")
	reqSegment.SetPathValue("segment", "seg_99999.ts")
	h.Segment(httptest.NewRecorder(), reqSegment)

	rec.mu.Lock()
	got := append([]string(nil), rec.requests...)
	rec.mu.Unlock()

	if len(got) != 2 {
		t.Fatalf("requêtes comptées = %v, want 2 entrées", got)
	}
	if got[0] != "sid|playlist|200" {
		t.Errorf("playlist servie comptée %q, want sid|playlist|200", got[0])
	}
	// Le segment absent alimente le taux d'erreurs .ts du dashboard.
	if !strings.HasPrefix(got[1], "sid|segment|") || strings.HasSuffix(got[1], "|200") {
		t.Errorf("segment absent compté %q, want sid|segment|<4xx/5xx>", got[1])
	}
}
