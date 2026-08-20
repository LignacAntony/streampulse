//go:build loadtest

// Package loadtest exerce le moteur HLS sous charge réaliste (STR-90) :
// un diffuseur ffmpeg réel + N auditeurs HTTP simulés, critères STR-87.
// Exclu de `go test ./...` par le build tag ; lancé via `make loadtest`.
package loadtest

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os/exec"
	"regexp"
	"runtime"
	"runtime/pprof"
	"sort"
	"sync"
	"testing"
	"time"

	"github.com/LignacAntony/streampulse/internal/auth"
	"github.com/LignacAntony/streampulse/internal/streaming"
)

const (
	listeners        = 50
	listenDuration   = 60 * time.Second
	pollInterval     = 2 * time.Second
	p95Budget        = 300 * time.Millisecond
	memPerConnBudget = 2 << 20 // 2 Mo/connexion (STR-87)

	streamID  = "loadtest-stream"
	streamKey = "loadtest-key"
	jwtSecret = "loadtest-secret-0123456789abcdef" // ≥ 32 chars comme en prod
)

// stubService satisfait streaming.StreamService sans DB : seul GetStream est
// réellement utilisé par les routes HLS (contrôle de visibilité auditeur).
type stubService struct{}

func (stubService) CreateStream(context.Context, streaming.CreateStreamInput) (streaming.Stream, error) {
	return streaming.Stream{}, nil
}
func (stubService) ListPublicLive(context.Context, int32, int32) ([]streaming.Stream, error) {
	return nil, nil
}
func (stubService) GetStream(_ context.Context, id, _ string) (streaming.Stream, bool, error) {
	return streaming.Stream{ID: id, Status: "live", IsPublic: true}, false, nil
}
func (stubService) UpdateStream(context.Context, string, string, streaming.UpdateStreamInput) (streaming.Stream, error) {
	return streaming.Stream{}, nil
}
func (stubService) ArchiveStream(context.Context, string, string) error { return nil }
func (stubService) StartStream(context.Context, string, string) (streaming.Stream, error) {
	return streaming.Stream{}, nil
}
func (stubService) StopStream(context.Context, string, string) (streaming.Stream, error) {
	return streaming.Stream{}, nil
}
func (stubService) AddFavorite(context.Context, string, string) error    { return nil }
func (stubService) RemoveFavorite(context.Context, string, string) error { return nil }
func (stubService) ListFavorites(context.Context, string) ([]streaming.Stream, error) {
	return nil, nil
}
func (stubService) ListMyStreams(context.Context, string) ([]streaming.Stream, error) {
	return nil, nil
}
func (stubService) RotateStreamKey(context.Context, string, string) (streaming.Stream, error) {
	return streaming.Stream{}, nil
}

// L'assertion de compilation manquait : sans elle, une méthode ajoutée à
// StreamService ne casse ce harnais qu'au moment où quelqu'un lance
// `make loadtest`. C'est ce qui s'est produit — le stub est resté incomplet
// trois semaines et demie, le build tag `loadtest` excluant ce fichier de
// `go build ./...` comme de `go test ./...` (STR-241).
var _ streaming.StreamService = stubService{}

// startServer monte les 3 routes HLS comme cmd/api/main.go les monte : ingest
// sans JWT, playlist/segments en lecture publique (OptionalAuth, STR-108) sous
// le limiteur de charge partagé (STR-88). L'auditeur simulé présente quand même
// un Bearer valide — OptionalAuth l'accepte comme un propriétaire authentifié.
func startServer(t *testing.T, ls *streaming.LiveSessions) *httptest.Server {
	t.Helper()
	h := streaming.NewHandler(stubService{}, "http://loadtest.invalid", ls)
	mux := http.NewServeMux()
	mux.Handle("POST /api/streams/ingest/{stream_key}", http.HandlerFunc(h.Ingest))
	hlsLimit := streaming.NewMaxInFlight(256)
	mux.Handle("GET /api/streams/{id}/playlist.m3u8", hlsLimit(auth.OptionalAuth(jwtSecret, http.HandlerFunc(h.Playlist))))
	mux.Handle("GET /api/streams/{id}/segments/{segment}", hlsLimit(auth.OptionalAuth(jwtSecret, http.HandlerFunc(h.Segment))))
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return srv
}

// mintToken fabrique un JWT auditeur valide (le middleware réel le vérifie,
// comme en prod).
func mintToken(t *testing.T) string {
	t.Helper()
	tok, err := auth.GenerateAccessToken("loadtest-user", "user", jwtSecret, time.Now())
	if err != nil {
		t.Fatalf("GenerateAccessToken: %v", err)
	}
	return tok
}

// startBroadcast lance ffmpeg (sine AAC temps réel, ~90 s de matière) et pousse
// sa sortie ADTS sur l'ingest via un POST chunké — le chemin exact d'un vrai
// diffuseur. L'annulation de ctx tue ffmpeg (CommandContext) et coupe le POST.
func startBroadcast(t *testing.T, ctx context.Context, ingestURL string) {
	t.Helper()
	cmd := exec.CommandContext(ctx, "ffmpeg", "-hide_banner", "-loglevel", "error",
		"-re", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100",
		"-t", "90", "-c:a", "aac", "-b:a", "128k", "-f", "adts", "-")
	out, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatalf("StdoutPipe: %v", err)
	}
	if err := cmd.Start(); err != nil {
		t.Fatalf("démarrage ffmpeg: %v", err)
	}
	// La goroutine POST lit `out` (stdout ffmpeg) : os/exec interdit d'appeler
	// Wait avant la fin des lectures du pipe. On attend donc la fin de la
	// goroutine (via done) AVANT de laisser le cleanup appeler Wait.
	done := make(chan struct{})
	t.Cleanup(func() {
		<-done
		_ = cmd.Wait() // récolte le process après cancel + fin des lectures du pipe
	})
	go func() {
		defer close(done)
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, ingestURL, out)
		if err != nil {
			return
		}
		req.Header.Set("Content-Type", "audio/aac")
		resp, err := http.DefaultClient.Do(req)
		if err == nil {
			_, _ = io.Copy(io.Discard, resp.Body)
			_ = resp.Body.Close()
		}
	}()
}

// waitFirstManifest bloque jusqu'à ce que la playlist réponde 200 (premier
// segment produit par ffmpeg, ~10-12 s) — deadline 30 s.
func waitFirstManifest(t *testing.T, client *http.Client, url, token string) {
	t.Helper()
	deadline := time.Now().Add(30 * time.Second)
	for time.Now().Before(deadline) {
		req, _ := http.NewRequest(http.MethodGet, url, nil)
		req.Header.Set("Authorization", "Bearer "+token)
		resp, err := client.Do(req)
		if err == nil {
			_, _ = io.Copy(io.Discard, resp.Body)
			_ = resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				return
			}
		}
		time.Sleep(500 * time.Millisecond)
	}
	t.Fatal("aucun manifeste disponible après 30 s (ffmpeg n'a rien produit)")
}

// sample : une requête auditeur mesurée.
type sample struct {
	kind   string // "playlist" | "segment"
	dur    time.Duration
	status int
	size   int64
}

// collector agrège les mesures des 50 goroutines auditeurs.
type collector struct {
	mu      sync.Mutex
	samples []sample
}

func (c *collector) add(s sample) {
	c.mu.Lock()
	c.samples = append(c.samples, s)
	c.mu.Unlock()
}

// durations retourne les latences d'un type, triées (prêtes pour percentile).
func (c *collector) durations(kind string) []time.Duration {
	c.mu.Lock()
	defer c.mu.Unlock()
	var out []time.Duration
	for _, s := range c.samples {
		if s.kind == kind {
			out = append(out, s.dur)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i] < out[j] })
	return out
}

func (c *collector) failures() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	n := 0
	for _, s := range c.samples {
		if s.status != http.StatusOK {
			n++
		}
	}
	return n
}

func (c *collector) bytes() int64 {
	c.mu.Lock()
	defer c.mu.Unlock()
	var n int64
	for _, s := range c.samples {
		n += s.size
	}
	return n
}

// percentile : sorted doit être trié ; p dans (0,100]. Index par la méthode
// « nearest rank » : ceil(p/100·N)-1.
func percentile(sorted []time.Duration, p float64) time.Duration {
	if len(sorted) == 0 {
		return 0
	}
	idx := int(float64(len(sorted))*p/100+0.9999999) - 1
	if idx < 0 {
		idx = 0
	}
	if idx >= len(sorted) {
		idx = len(sorted) - 1
	}
	return sorted[idx]
}

var segmentRe = regexp.MustCompile(`seg_\d+\.ts`)

// timedGet mesure un GET authentifié et l'enregistre dans le collecteur.
// Retourne le corps (nil si erreur transport, comptée comme échec status 0).
func timedGet(ctx context.Context, client *http.Client, url, token, kind string, col *collector) []byte {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil
	}
	req.Header.Set("Authorization", "Bearer "+token)
	start := time.Now()
	resp, err := client.Do(req)
	if err != nil {
		if ctx.Err() != nil {
			return nil // arrêt du test : pas un échec
		}
		col.add(sample{kind: kind, dur: time.Since(start), status: 0})
		return nil
	}
	body, _ := io.ReadAll(resp.Body)
	_ = resp.Body.Close()
	col.add(sample{kind: kind, dur: time.Since(start), status: resp.StatusCode, size: int64(len(body))})
	return body
}

// listen est la boucle d'un auditeur : GET playlist → GET des segments pas
// encore vus → pause pollInterval, jusqu'à annulation du contexte.
func listen(ctx context.Context, base, token string, col *collector) {
	client := &http.Client{Timeout: 10 * time.Second}
	seen := make(map[string]bool)
	playlistURL := fmt.Sprintf("%s/api/streams/%s/playlist.m3u8", base, streamID)
	for ctx.Err() == nil {
		if body := timedGet(ctx, client, playlistURL, token, "playlist", col); body != nil {
			for _, seg := range segmentRe.FindAllString(string(body), -1) {
				if seen[seg] {
					continue
				}
				seen[seg] = true
				segURL := fmt.Sprintf("%s/api/streams/%s/segments/%s", base, streamID, seg)
				timedGet(ctx, client, segURL, token, "segment", col)
			}
		}
		select {
		case <-ctx.Done():
		case <-time.After(pollInterval):
		}
	}
}

// waitSessionsDrained : LiveSessions.Wait borné (même approche déterministe que
// waitDrained dans session_pprof_test.go, non exporté par le package streaming).
func waitSessionsDrained(t *testing.T, ls *streaming.LiveSessions) {
	t.Helper()
	done := make(chan struct{})
	go func() { ls.Wait(); close(done) }()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("goroutines de session non libérées après stop (fuite)")
	}
}

// dumpGoroutines rend le profil pprof "goroutine" (debug=1) : en cas de fuite,
// le rapport de test contient directement les stacks fuyardes (STR-89).
func dumpGoroutines() string {
	var buf bytes.Buffer
	if err := pprof.Lookup("goroutine").WriteTo(&buf, 1); err != nil {
		return fmt.Sprintf("profil goroutine indisponible: %v", err)
	}
	return buf.String()
}

// TestLoad_50Listeners : voir les tasks suivantes — à ce stade, smoke du harnais.
func TestLoad_50Listeners(t *testing.T) {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg absent du PATH : test de charge ignoré")
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	ls := streaming.NewLiveSessions(ctx)
	t.Cleanup(ls.StopAll)
	srv := startServer(t, ls)
	token := mintToken(t)

	ls.Start(streamID, streamKey)
	startBroadcast(t, ctx, srv.URL+"/api/streams/ingest/"+streamKey)

	playlistURL := fmt.Sprintf("%s/api/streams/%s/playlist.m3u8", srv.URL, streamID)
	waitFirstManifest(t, http.DefaultClient, playlistURL, token)

	loadCtx, stopLoad := context.WithTimeout(ctx, listenDuration)
	defer stopLoad()

	runtime.GC()
	var before runtime.MemStats
	runtime.ReadMemStats(&before)
	goroutinesBefore := runtime.NumGoroutine()

	// Échantillonneur du pic mémoire pendant la charge (1 Hz).
	peakHeap := before.HeapAlloc
	samplerDone := make(chan struct{})
	go func() {
		defer close(samplerDone)
		tick := time.NewTicker(time.Second)
		defer tick.Stop()
		for {
			select {
			case <-loadCtx.Done():
				return
			case <-tick.C:
				var m runtime.MemStats
				runtime.ReadMemStats(&m)
				if m.HeapAlloc > peakHeap {
					peakHeap = m.HeapAlloc
				}
			}
		}
	}()

	col := &collector{}
	var wg sync.WaitGroup
	for i := 0; i < listeners; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			listen(loadCtx, srv.URL, token, col)
		}()
	}
	wg.Wait()

	playlists, segments := col.durations("playlist"), col.durations("segment")
	if len(playlists) == 0 || len(segments) == 0 {
		t.Fatalf("aucune mesure collectée (playlists=%d, segments=%d)", len(playlists), len(segments))
	}
	t.Logf("requêtes: %d playlists, %d segments, %d échecs, %.1f Mo servis",
		len(playlists), len(segments), col.failures(), float64(col.bytes())/(1<<20))

	<-samplerDone

	// Arrêt : fin du diffuseur (cancel ctx tue ffmpeg), stop session, drain.
	cancel()
	ls.Stop(streamID)
	waitSessionsDrained(t, ls)

	// 1) Latence (STR-87 : p95 < 300 ms).
	for kind, durs := range map[string][]time.Duration{"playlist": playlists, "segment": segments} {
		p50, p95, p99 := percentile(durs, 50), percentile(durs, 95), percentile(durs, 99)
		t.Logf("%s: n=%d p50=%s p95=%s p99=%s", kind, len(durs), p50, p95, p99)
		if p95 > p95Budget {
			t.Errorf("p95 %s = %s > budget %s", kind, p95, p95Budget)
		}
	}

	// 2) Zéro échec après le premier manifeste.
	if n := col.failures(); n > 0 {
		t.Errorf("%d requêtes en échec (attendu 0)", n)
	}

	// 3) Mémoire (STR-87 : < 2 Mo/connexion, sur le pic de charge).
	perConn := (peakHeap - before.HeapAlloc) / listeners
	t.Logf("mémoire: base=%.1f Mo pic=%.1f Mo soit %.2f Mo/connexion",
		float64(before.HeapAlloc)/(1<<20), float64(peakHeap)/(1<<20), float64(perConn)/(1<<20))
	if perConn > memPerConnBudget {
		t.Errorf("mémoire/connexion = %d octets > budget %d", perConn, memPerConnBudget)
	}

	// 4) Goroutines : retour au niveau initial (tolérance 3, retries GC).
	deadline := time.Now().Add(5 * time.Second)
	goroutinesAfter := runtime.NumGoroutine()
	for time.Now().Before(deadline) && goroutinesAfter > goroutinesBefore+3 {
		runtime.GC()
		time.Sleep(100 * time.Millisecond)
		goroutinesAfter = runtime.NumGoroutine()
	}
	t.Logf("goroutines: avant=%d après=%d", goroutinesBefore, goroutinesAfter)
	if goroutinesAfter > goroutinesBefore+3 {
		t.Errorf("fuite suspecte: %d goroutines avant charge, %d après drain\nprofil pprof:\n%s",
			goroutinesBefore, goroutinesAfter, dumpGoroutines())
	}
}
