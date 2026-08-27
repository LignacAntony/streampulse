package streaming

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

// nopWriteCloser adapte un io.Writer en io.WriteCloser (Close no-op).
type nopWriteCloser struct{ io.Writer }

func (nopWriteCloser) Close() error { return nil }

// fakeSegmenter construit un segmenteur simulé (sans ffmpeg) : répertoire réel
// avec un manifeste + un segment, entrée branchée sur io.Discard, cmd nil (close
// n'attend aucun process). done reste ouvert : la session vit jusqu'au cancel.
func fakeSegmenter(t *testing.T) *hlsSegmenter {
	t.Helper()
	dir := t.TempDir()
	mustWrite(t, filepath.Join(dir, hlsPlaylistName), "#EXTM3U\n")
	mustWrite(t, filepath.Join(dir, "seg_00000.ts"), "fake-ts")
	return &hlsSegmenter{dir: dir, stdin: nopWriteCloser{io.Discard}, done: make(chan struct{})}
}

func mustWrite(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}

// sessionsWithFakeSeg construit un registre dont le segmenteur est simulé.
func sessionsWithFakeSeg(t *testing.T) *LiveSessions {
	t.Helper()
	ls := NewLiveSessions(context.Background())
	ls.newSeg = func(string) (*hlsSegmenter, error) { return fakeSegmenter(t), nil }
	return ls
}

func TestSegmentPath_RejectsTraversal(t *testing.T) {
	s := fakeSegmenter(t)
	valid := []string{"seg_00000.ts", "seg_1.ts", "seg_99999.ts"}
	for _, name := range valid {
		if _, ok := s.segmentPath(name); !ok {
			t.Errorf("nom valide refusé: %q", name)
		}
	}
	invalid := []string{
		"../etc/passwd", "seg_.ts", "seg_1.mp3", "..", "seg_1.ts/../x",
		"/abs/seg_1.ts", "seg_1.TS", "", "playlist.m3u8",
	}
	for _, name := range invalid {
		if _, ok := s.segmentPath(name); ok {
			t.Errorf("nom invalide accepté (traversal possible): %q", name)
		}
	}
}

func TestAttachIngest_RoutesByKeyAndGuards(t *testing.T) {
	ls := sessionsWithFakeSeg(t)
	ls.Start("s1", "KEY1")
	defer ls.StopAll()

	if _, _, err := ls.AttachIngest("inconnue"); !errors.Is(err, errNotLive) {
		t.Fatalf("clé inconnue: want errNotLive, got %v", err)
	}

	w, release, err := ls.AttachIngest("KEY1")
	if err != nil || w == nil {
		t.Fatalf("attach valide: want (writer, nil), got (%v, %v)", w, err)
	}

	if _, _, err := ls.AttachIngest("KEY1"); !errors.Is(err, errIngestInProgress) {
		t.Fatalf("double push: want errIngestInProgress, got %v", err)
	}

	release()
	_, release2, err := ls.AttachIngest("KEY1")
	if err != nil {
		t.Fatalf("ré-attach après release: %v", err)
	}
	release2()
}

// waitFor sonde une condition jusqu'à timeout (pour les transitions asynchrones
// pilotées par la goroutine de session, ex. le reap).
func waitFor(cond func() bool, timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if cond() {
			return true
		}
		time.Sleep(5 * time.Millisecond)
	}
	return cond()
}

// TestSegmenterDeath_ReapsSession vérifie qu'à la mort spontanée de ffmpeg, la
// session est retirée du registre et les abonnés SSE notifiés (fin de flux) — plus
// de session « zombie » servant des 404 jusqu'au stop.
func TestSegmenterDeath_ReapsSession(t *testing.T) {
	ls := NewLiveSessions(context.Background())
	seg := fakeSegmenter(t)
	ls.newSeg = func(string) (*hlsSegmenter, error) { return seg, nil }
	ls.Start("s1", "KEY1")

	if _, avail := ls.Playlist("s1"); avail != hlsServable {
		t.Fatal("le flux devrait être servi tant que le segmenteur est vivant")
	}

	ch, unsub := ls.Subscribe("s1")
	if ch == nil {
		t.Fatal("Subscribe devrait fonctionner tant que le flux est live")
	}
	defer unsub()

	close(seg.done) // simule l'arrêt spontané de ffmpeg

	select {
	case ev, ok := <-ch:
		if ok && ev.Type != "ended" {
			t.Fatalf("event attendu ended, obtenu %+v", ev)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("aucun événement SSE après la mort du segmenteur")
	}

	if !waitFor(func() bool { return !ls.IsLive("s1") }, 2*time.Second) {
		t.Fatal("session non récoltée (toujours live) après la mort du segmenteur")
	}
	// hlsUnavailable et non hlsPending : ffmpeg est mort, il n'y a rien à
	// attendre. Rendre « en démarrage » ici ferait patienter l'auditeur 15 s
	// avant de lui annoncer une fin déjà consommée (STR-229).
	if _, avail := ls.Playlist("s1"); avail != hlsUnavailable {
		t.Fatalf("Playlist après reap: want hlsUnavailable, got %v", avail)
	}
	if _, _, err := ls.AttachIngest("KEY1"); !errors.Is(err, errNotLive) {
		t.Fatalf("AttachIngest après reap: want errNotLive, got %v", err)
	}
}

func TestAttachIngest_AfterStop(t *testing.T) {
	ls := sessionsWithFakeSeg(t)
	ls.Start("s1", "KEY1")
	ls.Stop("s1")

	if _, _, err := ls.AttachIngest("KEY1"); !errors.Is(err, errNotLive) {
		t.Fatalf("après stop: want errNotLive, got %v", err)
	}
}

func TestAttachIngest_SegmenterUnavailable(t *testing.T) {
	ls := NewLiveSessions(context.Background())
	ls.newSeg = func(string) (*hlsSegmenter, error) { return nil, errors.New("ffmpeg absent") }
	ls.Start("s1", "KEY1")
	defer ls.StopAll()

	if _, _, err := ls.AttachIngest("KEY1"); !errors.Is(err, errSegmenterUnavailable) {
		t.Fatalf("segmenteur indisponible: want errSegmenterUnavailable, got %v", err)
	}
}

func TestPlaylistAndSegmentLookup(t *testing.T) {
	ls := sessionsWithFakeSeg(t)
	ls.Start("s1", "KEY1")
	defer ls.StopAll()

	if p, avail := ls.Playlist("s1"); avail != hlsServable || filepath.Base(p) != hlsPlaylistName {
		t.Fatalf("playlist: want (…/%s, hlsServable), got (%q, %v)", hlsPlaylistName, p, avail)
	}
	if _, avail := ls.Playlist("inconnu"); avail != hlsUnavailable {
		t.Fatalf("playlist d'un flux inconnu: want hlsUnavailable, got %v", avail)
	}

	if p, avail := ls.Segment("s1", "seg_00000.ts"); avail != hlsServable || filepath.Base(p) != "seg_00000.ts" {
		t.Fatalf("segment valide: got (%q, %v)", p, avail)
	}
	// Un nom refusé n'est pas une attente : il ne deviendra jamais valide.
	if _, avail := ls.Segment("s1", "../secret"); avail != hlsUnavailable {
		t.Fatalf("segment traversal: want hlsUnavailable, got %v", avail)
	}
	if _, avail := ls.Segment("inconnu", "seg_00000.ts"); avail != hlsUnavailable {
		t.Fatalf("segment d'un flux inconnu: want hlsUnavailable, got %v", avail)
	}
}

// TestPlaylist_SpawnWindowIsPending couvre la fenêtre relevée en revue de la
// PR #358 : `Start` inscrit la session au registre (phase 1) *avant* de forker
// ffmpeg (phase 2, hors verrou et « potentiellement lente »). Un auditeur qui
// voit déjà le flux « en direct » dans Découvrir peut l'ouvrir pendant ce laps.
//
// Le segmenteur y est nil, comme après la mort de ffmpeg — mais les deux états
// sont contraires. Les confondre annonçait « direct terminé » à un auditeur
// arrivé une seconde trop tôt, soit exactement le défaut que STR-229 corrige,
// déplacé une couche plus bas.
func TestPlaylist_SpawnWindowIsPending(t *testing.T) {
	entered := make(chan struct{})
	release := make(chan struct{})

	ls := NewLiveSessions(context.Background())
	ls.newSeg = func(string) (*hlsSegmenter, error) {
		close(entered) // phase 1 terminée : la session est inscrite
		<-release      // …et le segmenteur n'est pas encore publié
		return fakeSegmenter(t), nil
	}
	t.Cleanup(ls.StopAll)

	go ls.Start("s1", "KEY1")
	<-entered

	if _, avail := ls.Playlist("s1"); avail != hlsPending {
		t.Fatalf("pendant le spawn: want hlsPending, got %v", avail)
	}
	if _, avail := ls.Segment("s1", "seg_00000.ts"); avail != hlsPending {
		t.Fatalf("segment pendant le spawn: want hlsPending, got %v", avail)
	}

	close(release)
	if !waitFor(func() bool {
		_, avail := ls.Playlist("s1")
		return avail == hlsServable
	}, 2*time.Second) {
		t.Fatal("le manifeste devrait devenir servable une fois le segmenteur publié")
	}
}

// TestPlaylist_SpawnFailureStaysPending : un spawn ffmpeg qui échoue publie un
// segmenteur nil de façon permanente. C'est indistinguable d'un spawn en cours,
// et ce doit le rester — le flux est bien « live » en base, il ne produira
// simplement jamais d'audio. Le client tranche par ses reprises bornées plutôt
// que par un verdict serveur que rien ne permet de rendre ici.
func TestPlaylist_SpawnFailureStaysPending(t *testing.T) {
	ls := NewLiveSessions(context.Background())
	ls.newSeg = func(string) (*hlsSegmenter, error) { return nil, errors.New("ffmpeg absent") }
	ls.Start("s1", "KEY1")
	t.Cleanup(ls.StopAll)

	if _, avail := ls.Playlist("s1"); avail != hlsPending {
		t.Fatalf("spawn échoué: want hlsPending, got %v", avail)
	}
}

// TestHLSSegmenter_Integration exerce le vrai pipeline ffmpeg de bout en bout :
// on génère ~25 s d'AAC, on les segmente, et on vérifie le manifeste + les
// segments produits. Ignoré si ffmpeg n'est pas installé (dev sans ffmpeg) ;
// exécuté en CI/Docker où ffmpeg est présent (cf. ADR 015).
func TestHLSSegmenter_Integration(t *testing.T) {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg absent du PATH : test d'intégration HLS ignoré")
	}

	aac := generateTestAAC(t, 25)

	seg, err := newHLSSegmenter("stream-test")
	if err != nil {
		t.Fatalf("newHLSSegmenter: %v", err)
	}
	defer seg.close()

	if _, err := io.Copy(seg.input(), bytes.NewReader(aac)); err != nil {
		t.Fatalf("copie de l'audio vers ffmpeg: %v", err)
	}
	// Fin du push : fermer l'entrée pour que ffmpeg finalise le dernier segment.
	if err := seg.stdin.Close(); err != nil {
		t.Fatalf("close stdin: %v", err)
	}
	select {
	case <-seg.done:
	case <-time.After(15 * time.Second):
		t.Fatal("ffmpeg n'a pas terminé après la fin de l'entrée")
	}

	data, err := os.ReadFile(seg.playlistPath())
	if err != nil {
		t.Fatalf("lecture du manifeste: %v", err)
	}
	manifest := string(data)
	if !strings.Contains(manifest, "#EXTM3U") {
		t.Fatalf("manifeste sans en-tête #EXTM3U:\n%s", manifest)
	}
	if n := strings.Count(manifest, ".ts"); n < 2 {
		t.Fatalf("attendu >= 2 segments pour 25 s, obtenu %d:\n%s", n, manifest)
	}
	// hls_base_url : les URI de segments sont préfixées par segments/ (route auditeur).
	if !strings.Contains(manifest, hlsSegmentPrefix+"seg_") {
		t.Fatalf("manifeste sans préfixe %q:\n%s", hlsSegmentPrefix, manifest)
	}
	// Le fichier du premier segment existe sur disque (nom attendu par segmentPath).
	if _, err := os.Stat(filepath.Join(seg.dir, "seg_00000.ts")); err != nil {
		t.Fatalf("premier segment absent du disque: %v", err)
	}
}

// generateTestAAC synthétise `seconds` secondes d'AAC (conteneur ADTS) via
// ffmpeg, pour alimenter le segmenteur sans fichier de test binaire.
func generateTestAAC(t *testing.T, seconds int) []byte {
	t.Helper()
	var buf bytes.Buffer
	cmd := exec.Command("ffmpeg", "-hide_banner", "-loglevel", "error",
		"-f", "lavfi", "-i", fmt.Sprintf("sine=frequency=440:duration=%d", seconds),
		"-c:a", "aac", "-b:a", "64k", "-f", "adts", "pipe:1")
	cmd.Stdout = &buf
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		t.Fatalf("génération de l'AAC de test: %v", err)
	}
	if buf.Len() == 0 {
		t.Fatal("AAC de test vide")
	}
	return buf.Bytes()
}

// --- stderr ffmpeg vers zerolog (STR-244, ADR 041) ---

// captureLogs redirige le logger global vers un tampon le temps du test.
func captureLogs(t *testing.T) *bytes.Buffer {
	t.Helper()
	var buf bytes.Buffer
	previous := log.Logger
	log.Logger = zerolog.New(&buf)
	t.Cleanup(func() { log.Logger = previous })
	return &buf
}

func TestFFmpegLogWriter_EmitsOneJSONLinePerStderrLine(t *testing.T) {
	buf := captureLogs(t)
	w := &ffmpegLogWriter{streamID: "s1"}

	// Deux lignes en une écriture, une troisième coupée en deux écritures :
	// ffmpeg n'a aucune raison d'aligner ses écritures sur ses lignes.
	if _, err := w.Write([]byte("premier avertissement\nsecond\ntroi")); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if _, err := w.Write([]byte("sieme\n")); err != nil {
		t.Fatalf("Write: %v", err)
	}

	lines := strings.Split(strings.TrimSpace(buf.String()), "\n")
	if len(lines) != 3 {
		t.Fatalf("%d lignes de log, want 3:\n%s", len(lines), buf.String())
	}
	for i, want := range []string{"premier avertissement", "second", "troisieme"} {
		var entry map[string]any
		if err := json.Unmarshal([]byte(lines[i]), &entry); err != nil {
			t.Fatalf("ligne %d non JSON (c'est tout le problème que ce code corrige): %v", i, err)
		}
		if entry["message"] != want {
			t.Errorf("message %d = %v, want %q", i, entry["message"], want)
		}
		if entry["stream_id"] != "s1" {
			t.Errorf("stream_id %d = %v, want s1", i, entry["stream_id"])
		}
		if entry["component"] != "ffmpeg-hls" {
			t.Errorf("component %d = %v, want ffmpeg-hls", i, entry["component"])
		}
	}
}

func TestFFmpegLogWriter_FlushEmitsTrailingPartialLine(t *testing.T) {
	buf := captureLogs(t)
	w := &ffmpegLogWriter{streamID: "s1"}

	// ffmpeg tué avant d'avoir terminé sa ligne : sans flush, elle serait perdue.
	if _, err := w.Write([]byte("erreur sans saut de ligne")); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if buf.Len() != 0 {
		t.Fatalf("une ligne incomplète ne doit pas être émise avant flush: %s", buf.String())
	}

	w.flush()
	if !strings.Contains(buf.String(), "erreur sans saut de ligne") {
		t.Errorf("flush n'a pas émis le reliquat: %s", buf.String())
	}
	w.flush() // idempotent : le tampon est vide
	if strings.Count(buf.String(), "erreur sans saut de ligne") != 1 {
		t.Errorf("flush a émis le reliquat deux fois: %s", buf.String())
	}
}

// Sans borne, un ffmpeg qui n'émettrait jamais de saut de ligne ferait grandir
// le tampon aussi longtemps que dure la diffusion.
func TestFFmpegLogWriter_BoundsUnterminatedLine(t *testing.T) {
	buf := captureLogs(t)
	w := &ffmpegLogWriter{streamID: "s1"}

	if _, err := w.Write([]byte(strings.Repeat("x", ffmpegLogLineMax+1))); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if buf.Len() == 0 {
		t.Fatal("dépassement de la borne : la ligne devait être émise sans attendre un saut de ligne")
	}
	if w.buf.Len() != 0 {
		t.Errorf("tampon résiduel = %d octets, want 0", w.buf.Len())
	}
}
