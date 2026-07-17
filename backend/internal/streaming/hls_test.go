package streaming

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
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
	ls.newSeg = func() (*hlsSegmenter, error) { return fakeSegmenter(t), nil }
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
	ls.newSeg = func() (*hlsSegmenter, error) { return seg, nil }
	ls.Start("s1", "KEY1")

	if _, ok := ls.Playlist("s1"); !ok {
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
	if _, ok := ls.Playlist("s1"); ok {
		t.Fatal("Playlist devrait échouer après reap")
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
	ls.newSeg = func() (*hlsSegmenter, error) { return nil, errors.New("ffmpeg absent") }
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

	if p, ok := ls.Playlist("s1"); !ok || filepath.Base(p) != hlsPlaylistName {
		t.Fatalf("playlist: want (…/%s, true), got (%q, %v)", hlsPlaylistName, p, ok)
	}
	if _, ok := ls.Playlist("inconnu"); ok {
		t.Fatal(`playlist d'un flux inconnu doit être ("", false)`)
	}

	if p, ok := ls.Segment("s1", "seg_00000.ts"); !ok || filepath.Base(p) != "seg_00000.ts" {
		t.Fatalf("segment valide: got (%q, %v)", p, ok)
	}
	if _, ok := ls.Segment("s1", "../secret"); ok {
		t.Fatal("segment traversal accepté")
	}
	if _, ok := ls.Segment("inconnu", "seg_00000.ts"); ok {
		t.Fatal(`segment d'un flux inconnu doit être ("", false)`)
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

	seg, err := newHLSSegmenter()
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
