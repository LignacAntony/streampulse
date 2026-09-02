package streaming

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

// stubRecorder capture les appels du domaine vers l'infra métriques.
type stubRecorder struct {
	mu            sync.Mutex
	requests      []string // "streamID|kind|status"
	forgotten     []string
	departures    int
	interruptions []string // raisons, dans l'ordre
	recoveries    []time.Duration
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

func (s *stubRecorder) RecordListenerDepartures(n int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.departures += n
}

func (s *stubRecorder) RecordStreamInterruption(reason string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.interruptions = append(s.interruptions, reason)
}

func (s *stubRecorder) RecordIngestRecovery(outage time.Duration) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.recoveries = append(s.recoveries, outage)
}

func (s *stubRecorder) recoveryCount() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.recoveries)
}

func (s *stubRecorder) departureCount() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.departures
}

func (s *stubRecorder) interruptionReasons() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]string(nil), s.interruptions...)
}

func (s *stubRecorder) forgottenIDs() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]string(nil), s.forgotten...)
}

func TestLiveSessions_ActiveCount(t *testing.T) {
	ls := NewLiveSessions(context.Background())
	ls.newSeg = func(string) (*hlsSegmenter, error) { return nil, errors.New("pas de ffmpeg en test") }

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
	ls.newSeg = func(string) (*hlsSegmenter, error) { return nil, errors.New("pas de ffmpeg en test") }
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
	ls.newSeg = func(string) (*hlsSegmenter, error) { return nil, errors.New("pas de ffmpeg en test") }
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
	ls.newSeg = func(string) (*hlsSegmenter, error) { return nil, errors.New("pas de ffmpeg en test") }

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

func TestHandler_DoesNotRecordUnknownStreams(t *testing.T) {
	// Un client anonyme peut marteler /api/streams/<uuid aléatoire>/playlist.m3u8 :
	// si chaque id inventé créait une série, aucune ForgetStream ne la
	// nettoierait jamais (aucune session n'a existé) → cardinalité illimitée,
	// donc DoS mémoire sur Prometheus et l'API (revue PR #272).
	rec := &stubRecorder{}
	ls := sessionsWithFakeSeg(t)
	ls.SetMetrics(rec)
	h := NewHandler(&stubService{getErr: apperror.NotFound("stream not found")}, testIngestURL, ls)
	h.SetMetrics(rec)

	for _, id := range []string{"id-invente-1", "id-invente-2", "id-invente-3"} {
		req := httptest.NewRequest(http.MethodGet, "/api/streams/"+id+"/playlist.m3u8", nil)
		req.SetPathValue("id", id)
		h.Playlist(httptest.NewRecorder(), req)
	}

	rec.mu.Lock()
	got := append([]string(nil), rec.requests...)
	rec.mu.Unlock()
	if len(got) != 0 {
		t.Fatalf("des flux inexistants ont été comptés: %v", got)
	}
}

func TestHandler_DoesNotRecordStreamsThatAreNotLive(t *testing.T) {
	// Flux visible en base mais sans session : aucune série ne doit naître,
	// elle ne serait jamais nettoyée non plus.
	rec := &stubRecorder{}
	ls := sessionsWithFakeSeg(t) // aucun Start
	ls.SetMetrics(rec)
	h := NewHandler(&stubService{getRet: Stream{ID: "idle", UserID: "owner", IsPublic: true}}, testIngestURL, ls)
	h.SetMetrics(rec)

	req := httptest.NewRequest(http.MethodGet, "/api/streams/idle/playlist.m3u8", nil)
	req.SetPathValue("id", "idle")
	h.Playlist(httptest.NewRecorder(), req)

	rec.mu.Lock()
	got := append([]string(nil), rec.requests...)
	rec.mu.Unlock()
	if len(got) != 0 {
		t.Fatalf("un flux non live a été compté: %v", got)
	}
}

func TestHandler_RecordsErrorsOfLiveStreams(t *testing.T) {
	// En revanche, une erreur survenue sur un flux BIEN live doit être
	// comptée : c'est le taux d'erreurs .ts du dashboard (fenêtre glissante).
	rec := &stubRecorder{}
	ls := sessionsWithFakeSeg(t)
	ls.SetMetrics(rec)
	ls.Start("live", "KEY-live")
	t.Cleanup(ls.StopAll)
	h := NewHandler(&stubService{getRet: Stream{ID: "live", UserID: "owner", IsPublic: true}}, testIngestURL, ls)
	h.SetMetrics(rec)

	req := httptest.NewRequest(http.MethodGet, "/api/streams/live/segments/seg_00042.ts", nil)
	req.SetPathValue("id", "live")
	req.SetPathValue("segment", "seg_00042.ts")
	h.Segment(httptest.NewRecorder(), req)

	rec.mu.Lock()
	got := append([]string(nil), rec.requests...)
	rec.mu.Unlock()
	if len(got) != 1 || !strings.HasPrefix(got[0], "live|segment|4") {
		t.Fatalf("erreur d'un flux live = %v, want [live|segment|404]", got)
	}
}

// --- Départs d'auditeurs et interruptions de diffusion (STR-244, ADR 041) ---

func TestLiveSessions_SweepCountsListenerDepartures(t *testing.T) {
	rec := &stubRecorder{}
	ls := NewLiveSessions(context.Background())
	ls.newSeg = func(string) (*hlsSegmenter, error) { return nil, errors.New("pas de ffmpeg en test") }
	ls.SetMetrics(rec)
	ls.Start("stream-a", "key-a")

	ls.TouchListener("stream-a", "10.0.0.1")
	ls.TouchListener("stream-a", "10.0.0.2")
	if got := rec.departureCount(); got != 0 {
		t.Fatalf("aucun départ attendu tant que la fenêtre court, got %d", got)
	}

	// Un balayage postérieur à la fenêtre : les deux auditeurs sont sortis.
	if got := ls.SweepListeners(time.Now().Add(listenerWindow + time.Second)); got != 2 {
		t.Fatalf("SweepListeners = %d, want 2", got)
	}
	if got := rec.departureCount(); got != 2 {
		t.Errorf("départs publiés = %d, want 2", got)
	}

	// Un second balayage ne recompte pas les mêmes : la purge les a retirés.
	ls.SweepListeners(time.Now().Add(2 * listenerWindow))
	if got := rec.departureCount(); got != 2 {
		t.Errorf("départs après second balayage = %d, want 2 (pas de double comptage)", got)
	}
}

// Un flux qui s'arrête normalement emmène ses auditeurs avec lui : ce ne sont
// pas des départs. Compter l'inverse ferait grimper la métrique à chaque fin de
// diffusion réussie, exactement le signal qu'elle est censée ne pas donner.
func TestLiveSessions_StopDoesNotCountListenerDepartures(t *testing.T) {
	rec := &stubRecorder{}
	ls := NewLiveSessions(context.Background())
	ls.newSeg = func(string) (*hlsSegmenter, error) { return nil, errors.New("pas de ffmpeg en test") }
	ls.SetMetrics(rec)
	ls.Start("stream-a", "key-a")

	ls.TouchListener("stream-a", "10.0.0.1")
	ls.TouchListener("stream-a", "10.0.0.2")
	ls.Stop("stream-a")

	if got := rec.departureCount(); got != 0 {
		t.Errorf("départs après un arrêt volontaire = %d, want 0", got)
	}
	// Le balayage qui suit ne trouve plus la session : rien de plus à compter.
	ls.SweepListeners(time.Now().Add(listenerWindow + time.Second))
	if got := rec.departureCount(); got != 0 {
		t.Errorf("départs après balayage post-arrêt = %d, want 0", got)
	}
}

func TestLiveSessions_TotalListeners(t *testing.T) {
	ls := NewLiveSessions(context.Background())
	ls.newSeg = func(string) (*hlsSegmenter, error) { return nil, errors.New("pas de ffmpeg en test") }
	ls.Start("stream-a", "key-a")
	ls.Start("stream-b", "key-b")

	ls.TouchListener("stream-a", "10.0.0.1")
	ls.TouchListener("stream-a", "10.0.0.2")
	ls.TouchListener("stream-b", "10.0.0.3")
	ls.TouchListener("stream-b", "10.0.0.3") // même client : compté une fois

	if got := ls.TotalListeners(); got != 3 {
		t.Errorf("TotalListeners = %d, want 3", got)
	}
}

func TestLiveSessions_CountsInterruptionOnIngestExpiry(t *testing.T) {
	rec := &stubRecorder{}
	ls := NewLiveSessions(context.Background())
	ls.newSeg = func(string) (*hlsSegmenter, error) { return nil, errors.New("pas de ffmpeg en test") }
	ls.SetMetrics(rec)

	ended := make(chan string, 1)
	ls.SetIngestDisconnectHandler(10*time.Millisecond, func(streamID string) error {
		ended <- streamID
		return nil
	})
	ls.Start("stream-a", "key-a")

	select {
	case <-ended:
	case <-time.After(2 * time.Second):
		t.Fatal("le bail d'ingest n'a jamais expiré")
	}

	// La métrique doit être posée AVANT l'appel au handler : à ce point la
	// diffusion est déjà perdue, quel que soit le sort de l'écriture en base.
	if got := rec.interruptionReasons(); len(got) != 1 || got[0] != InterruptionIngestTimeout {
		t.Errorf("interruptions = %v, want [%s]", got, InterruptionIngestTimeout)
	}
}

func TestLiveSessions_StopCountsNoInterruption(t *testing.T) {
	rec := &stubRecorder{}
	ls := NewLiveSessions(context.Background())
	ls.newSeg = func(string) (*hlsSegmenter, error) { return nil, errors.New("pas de ffmpeg en test") }
	ls.SetMetrics(rec)

	ls.Start("stream-a", "key-a")
	ls.Stop("stream-a")

	if got := rec.interruptionReasons(); len(got) != 0 {
		t.Errorf("un arrêt volontaire ne doit pas compter d'interruption, got %v", got)
	}
}

// Mort spontanée de ffmpeg : la diffusion s'arrête sans que le diffuseur l'ait
// demandé, et la raison doit distinguer cette panne serveur d'une perte de
// connexion côté diffuseur — les deux n'appellent pas la même intervention.
func TestLiveSessions_CountsInterruptionOnSegmenterDeath(t *testing.T) {
	rec := &stubRecorder{}
	ls := NewLiveSessions(context.Background())
	seg := fakeSegmenter(t)
	ls.newSeg = func(string) (*hlsSegmenter, error) { return seg, nil }
	ls.SetMetrics(rec)
	ls.Start("s1", "KEY1")

	close(seg.done) // ffmpeg s'arrête seul

	if !waitFor(func() bool { return len(rec.interruptionReasons()) > 0 }, 2*time.Second) {
		t.Fatal("aucune interruption comptée après la mort du segmenteur")
	}
	if got := rec.interruptionReasons(); got[0] != InterruptionSegmenterFailed {
		t.Errorf("raison = %q, want %q", got[0], InterruptionSegmenterFailed)
	}
}

func TestLiveSessions_StartListenerSweep(t *testing.T) {
	rec := &stubRecorder{}
	ls := NewLiveSessions(context.Background())
	ls.newSeg = func(string) (*hlsSegmenter, error) { return nil, errors.New("pas de ffmpeg en test") }
	ls.SetMetrics(rec)
	ls.Start("stream-a", "key-a")

	// Auditeur déjà expiré au moment où le balayage passera.
	ls.mu.Lock()
	s := ls.byID["stream-a"]
	ls.mu.Unlock()
	s.mu.Lock()
	s.listeners = map[string]time.Time{"10.0.0.1": time.Now().Add(-2 * listenerWindow)}
	s.mu.Unlock()

	done := make(chan struct{})
	ls.StartListenerSweep(done, 5*time.Millisecond)
	t.Cleanup(func() { close(done) })

	if !waitFor(func() bool { return rec.departureCount() > 0 }, 2*time.Second) {
		t.Fatal("le balayage périodique n'a jamais publié de départ")
	}
	if got := ls.TotalListeners(); got != 0 {
		t.Errorf("auditeur expiré toujours suivi après balayage: %d", got)
	}
}

// La fermeture du canal doit arrêter la goroutine : sinon elle survivrait à
// l'arrêt du serveur et le test suivant la verrait encore tourner.
func TestLiveSessions_StartListenerSweep_StopsOnDone(t *testing.T) {
	rec := &stubRecorder{}
	ls := NewLiveSessions(context.Background())
	ls.newSeg = func(string) (*hlsSegmenter, error) { return nil, errors.New("pas de ffmpeg en test") }
	ls.SetMetrics(rec)
	ls.Start("stream-a", "key-a")

	done := make(chan struct{})
	ls.StartListenerSweep(done, time.Millisecond)
	close(done)

	// Laisser au ticker le temps de battre plusieurs fois s'il tournait encore,
	// puis vérifier qu'un auditeur expiré n'est PAS purgé — preuve que plus
	// personne ne balaie.
	ls.mu.Lock()
	s := ls.byID["stream-a"]
	ls.mu.Unlock()
	s.mu.Lock()
	s.listeners = map[string]time.Time{"10.0.0.1": time.Now().Add(-2 * listenerWindow)}
	s.mu.Unlock()

	time.Sleep(50 * time.Millisecond)
	if got := ls.TotalListeners(); got != 1 {
		t.Errorf("le balayage tourne encore après la fermeture du canal (auditeurs = %d)", got)
	}
}

// Un intervalle nul ou négatif ne doit pas lancer de goroutine qui tournerait
// en boucle serrée : time.NewTicker panique sur une durée <= 0.
func TestLiveSessions_StartListenerSweep_IgnoresNonPositiveInterval(t *testing.T) {
	ls := NewLiveSessions(context.Background())
	ls.newSeg = func(string) (*hlsSegmenter, error) { return nil, errors.New("pas de ffmpeg en test") }

	ls.StartListenerSweep(make(chan struct{}), 0)
	ls.StartListenerSweep(make(chan struct{}), -time.Second)
	// Absence de panique = succès ; time.NewTicker(0) paniquerait.
}
