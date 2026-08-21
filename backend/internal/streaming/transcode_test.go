package streaming

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestResolveIngestFormat(t *testing.T) {
	cases := []struct {
		contentType string
		wantOK      bool
		wantPass    bool
		wantDemuxer string
	}{
		// Chemin historique : AAC brut ou client sans Content-Type.
		{contentType: "", wantOK: true, wantPass: true},
		{contentType: "audio/aac", wantOK: true, wantPass: true},
		{contentType: "AUDIO/AAC", wantOK: true, wantPass: true},
		{contentType: "audio/aac; charset=binary", wantOK: true, wantPass: true},

		// Formats transcodés (US-09-05).
		{contentType: "audio/mpeg", wantOK: true, wantDemuxer: "mp3"},
		{contentType: "audio/mp3", wantOK: true, wantDemuxer: "mp3"},
		{contentType: "audio/ogg", wantOK: true, wantDemuxer: "ogg"},
		{contentType: "audio/wav", wantOK: true, wantDemuxer: "wav"},
		{contentType: "audio/x-wav", wantOK: true, wantDemuxer: "wav"},
		{contentType: "audio/flac", wantOK: true, wantDemuxer: "flac"},

		// audio/* inconnu : accepté, ffmpeg sondera l'entrée (demuxer vide).
		{contentType: "audio/exotique", wantOK: true, wantDemuxer: ""},

		// Non-audio ou en-tête illisible : refusé avant tout process ffmpeg.
		{contentType: "application/x-www-form-urlencoded", wantOK: false},
		{contentType: "video/mp4", wantOK: false},
		{contentType: "text/plain", wantOK: false},
		{contentType: "audio/", wantOK: false},
		{contentType: "@@@", wantOK: false},
	}

	for _, tc := range cases {
		got, ok := resolveIngestFormat(tc.contentType)
		if ok != tc.wantOK {
			t.Errorf("resolveIngestFormat(%q): ok = %v, want %v", tc.contentType, ok, tc.wantOK)
			continue
		}
		if !ok {
			continue
		}
		if got.passthrough != tc.wantPass {
			t.Errorf("resolveIngestFormat(%q): passthrough = %v, want %v",
				tc.contentType, got.passthrough, tc.wantPass)
		}
		if !tc.wantPass && got.demuxer != tc.wantDemuxer {
			t.Errorf("resolveIngestFormat(%q): demuxer = %q, want %q",
				tc.contentType, got.demuxer, tc.wantDemuxer)
		}
	}
}

// resolveIngestFormat ne doit jamais annoncer un passthrough pour un conteneur :
// l'audio irait tel quel dans un segmenteur en `-c:a copy` incapable de le muxer.
func TestResolveIngestFormat_ContainersAreTranscoded(t *testing.T) {
	for _, ct := range []string{"audio/mp4", "audio/x-m4a", "audio/webm", "audio/ogg"} {
		got, ok := resolveIngestFormat(ct)
		if !ok {
			t.Fatalf("%s devrait être accepté", ct)
		}
		if got.passthrough {
			t.Errorf("%s: passthrough = true, un conteneur doit être démuxé", ct)
		}
	}
}

// syncWriter sérialise les écritures reçues du transcodeur : la recopie de la
// sortie ffmpeg se fait dans une goroutine, le test lit le buffer après close.
type syncWriter struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (w *syncWriter) Write(p []byte) (int, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.buf.Write(p)
}

func (w *syncWriter) Bytes() []byte {
	w.mu.Lock()
	defer w.mu.Unlock()
	return append([]byte(nil), w.buf.Bytes()...)
}

// isADTS vérifie la présence du sync word ADTS (12 bits à 1) en tête de flux :
// c'est ce que le segmenteur attend en `-c:a copy`.
func isADTS(b []byte) bool {
	return len(b) >= 2 && b[0] == 0xFF && b[1]&0xF0 == 0xF0
}

func requireFFmpeg(t *testing.T) {
	t.Helper()
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg absent du PATH : test de transcodage ignoré")
	}
}

// generateTestAudio synthétise `seconds` secondes d'audio dans le format
// demandé (muxer ffmpeg + codec), pour alimenter le transcodeur sans embarquer
// de fichier binaire dans le dépôt.
func generateTestAudio(t *testing.T, muxer, codec string, seconds int) []byte {
	t.Helper()
	var buf bytes.Buffer
	cmd := exec.Command("ffmpeg", "-hide_banner", "-loglevel", "error",
		"-f", "lavfi", "-i", fmt.Sprintf("sine=frequency=440:duration=%d", seconds),
		"-c:a", codec, "-b:a", "128k", "-f", muxer, "pipe:1")
	cmd.Stdout = &buf
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		t.Fatalf("génération de l'audio de test (%s/%s): %v", muxer, codec, err)
	}
	if buf.Len() == 0 {
		t.Fatalf("audio de test vide (%s/%s)", muxer, codec)
	}
	return buf.Bytes()
}

// TestTranscoder_ConvertsToAAC exerce le transcodage des formats visés par
// l'US-09-05 : chaque entrée non-AAC doit ressortir en AAC/ADTS, prête pour le
// segmenteur en `-c:a copy`.
func TestTranscoder_ConvertsToAAC(t *testing.T) {
	requireFFmpeg(t)

	cases := []struct {
		name    string
		muxer   string
		codec   string
		demuxer string
	}{
		{name: "mp3", muxer: "mp3", codec: "libmp3lame", demuxer: "mp3"},
		{name: "ogg", muxer: "ogg", codec: "libopus", demuxer: "ogg"},
		{name: "wav", muxer: "wav", codec: "pcm_s16le", demuxer: "wav"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			src := generateTestAudio(t, tc.muxer, tc.codec, 3)

			var dst syncWriter
			tr, err := newTranscoder(&dst, tc.demuxer)
			if err != nil {
				t.Fatalf("newTranscoder: %v", err)
			}
			if _, err := io.Copy(tr, bytes.NewReader(src)); err != nil {
				t.Fatalf("copie vers le transcodeur: %v", err)
			}
			if err := tr.close(); err != nil {
				t.Fatalf("close: %v", err)
			}

			out := dst.Bytes()
			if len(out) == 0 {
				t.Fatal("aucun octet AAC produit")
			}
			if tr.produced() != int64(len(out)) {
				t.Errorf("produced() = %d, écrit = %d", tr.produced(), len(out))
			}
			if !isADTS(out) {
				t.Errorf("la sortie n'est pas de l'ADTS (premiers octets %x)", out[:min(4, len(out))])
			}
		})
	}
}

// Un corps qui ne correspond pas au format annoncé ne doit produire aucun octet :
// c'est ce que le handler traduit en 415 plutôt qu'en 500 opaque.
func TestTranscoder_UndecodablePayloadProducesNothing(t *testing.T) {
	requireFFmpeg(t)

	var dst syncWriter
	tr, err := newTranscoder(&dst, "mp3")
	if err != nil {
		t.Fatalf("newTranscoder: %v", err)
	}
	// L'écriture peut échouer (ffmpeg meurt sur l'entrée invalide) : c'est
	// attendu, seul le résultat du transcodage nous intéresse ici.
	_, _ = io.Copy(tr, strings.NewReader(strings.Repeat("ceci n'est pas de l'audio", 4096)))
	if err := tr.close(); err == nil {
		t.Error("close: une entrée indécodable doit remonter l'échec de ffmpeg")
	}
	if tr.produced() != 0 {
		t.Errorf("produced() = %d, want 0 pour une entrée indécodable", tr.produced())
	}
}

// Les entrées conteneur sont annoncées best-effort : l'ingest est un pipe non
// seekable. Ce test fixe l'invariant qui compte — le push se termine, il ne
// bloque pas — et documente le comportement réel, qui est meilleur qu'attendu :
// ffmpeg démuxe un MP4 non fragmenté (index `moov` en fin) tant qu'il tient
// dans ce qu'il peut bufferiser, et produit bien de l'ADTS. Le cas où ça casse
// (entrée trop grande pour être bufferisée) ressort en 415, couvert par
// TestTranscoder_UndecodablePayloadProducesNothing.
func TestTranscoder_NonStreamableContainerTerminates(t *testing.T) {
	requireFFmpeg(t)

	// -f mp4 vers un fichier : l'index `moov` est écrit à la fin, donc illisible
	// en flux. C'est exactement ce qu'enverrait un diffuseur qui pousse un .m4a.
	path := filepath.Join(t.TempDir(), "sample.m4a")
	cmd := exec.Command("ffmpeg", "-hide_banner", "-loglevel", "error",
		"-f", "lavfi", "-i", "sine=frequency=440:duration=3",
		"-c:a", "aac", "-b:a", "128k", "-f", "mp4", path)
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		t.Fatalf("génération du mp4 de test: %v", err)
	}
	src, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("lecture du mp4 de test: %v", err)
	}

	var dst syncWriter
	tr, err := newTranscoder(&dst, "mp4")
	if err != nil {
		t.Fatalf("newTranscoder: %v", err)
	}

	done := make(chan struct{})
	go func() {
		defer close(done)
		_, _ = io.Copy(tr, bytes.NewReader(src))
		_ = tr.close()
	}()
	select {
	case <-done:
	case <-time.After(30 * time.Second):
		t.Fatal("le push d'un conteneur non seekable a bloqué au lieu de se terminer")
	}

	// Rien produit = échec propre, que le handler traduit en 415. Sinon, ce qui
	// sort doit être de l'ADTS : le segmenteur tourne en `-c:a copy`, un
	// conteneur relayé tel quel le casserait.
	if out := dst.Bytes(); len(out) > 0 && !isADTS(out) {
		t.Fatalf("sortie non-ADTS pour un conteneur mp4 (premiers octets %x)", out[:min(4, len(out))])
	}
}

// Le relais vers le segmenteur peut se bloquer en ÉCRITURE (segmenteur vivant
// qui ne consomme plus) : tuer ffmpeg ne débloque que la LECTURE de son stdout.
// close() doit alors rendre la main sur un délai borné, sinon le handler ne
// retourne jamais et le slot d'ingest du flux reste pris.
func TestTranscoder_StalledRelayDoesNotHangClose(t *testing.T) {
	requireFFmpeg(t)

	release := make(chan struct{})
	t.Cleanup(func() { close(release) }) // libère la goroutine de recopie en fin de test

	blocked := make(chan struct{}, 1)
	dst := writerFunc(func(p []byte) (int, error) {
		select {
		case blocked <- struct{}{}:
		default:
		}
		<-release // ne consomme jamais : simule un segmenteur figé
		return len(p), nil
	})

	tr, err := newTranscoder(dst, "wav")
	if err != nil {
		t.Fatalf("newTranscoder: %v", err)
	}
	tr.relayTimeout = 300 * time.Millisecond // évite d'attendre la borne de production

	if _, err := io.Copy(tr, bytes.NewReader(generateTestAudio(t, "wav", "pcm_s16le", 2))); err != nil {
		t.Fatalf("copie vers le transcodeur: %v", err)
	}
	select {
	case <-blocked:
	case <-time.After(10 * time.Second):
		t.Fatal("le transcodeur n'a rien écrit vers le segmenteur : test non concluant")
	}

	closed := make(chan error, 1)
	go func() { closed <- tr.close() }()

	select {
	case err := <-closed:
		if !errors.Is(err, errTranscodeRelayStalled) {
			t.Fatalf("close: want errTranscodeRelayStalled, got %v", err)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("close() ne rend pas la main sur un relais bloqué (slot d'ingest tenu)")
	}
}

func TestTranscoder_CloseIsIdempotent(t *testing.T) {
	requireFFmpeg(t)

	var dst syncWriter
	tr, err := newTranscoder(&dst, "wav")
	if err != nil {
		t.Fatalf("newTranscoder: %v", err)
	}
	if _, err := io.Copy(tr, bytes.NewReader(generateTestAudio(t, "wav", "pcm_s16le", 1))); err != nil {
		t.Fatalf("copie vers le transcodeur: %v", err)
	}
	first := tr.close()
	// Comparaison d'identité volontaire, d'où le nolint : close() mémorise son
	// résultat sous un sync.Once, et c'est exactement ce qu'on vérifie. errors.Is
	// passerait aussi si le second appel fabriquait une erreur *enveloppant* la
	// première — soit précisément le cas non idempotent que ce test doit exclure.
	//nolint:errorlint // l'identité du résultat est l'objet du test
	if second := tr.close(); second != first {
		t.Fatalf("close non idempotent: %v puis %v", first, second)
	}
}

// TestTranscoder_AddedLatency mesure le critère d'acceptation de l'US-09-05 :
// le délai entre le premier octet poussé par le diffuseur et le premier octet
// AAC transmis au segmenteur doit rester sous 2 secondes.
func TestTranscoder_AddedLatency(t *testing.T) {
	requireFFmpeg(t)

	src := generateTestAudio(t, "mp3", "libmp3lame", 10)

	firstOut := make(chan time.Time, 1)
	dst := writerFunc(func(p []byte) (int, error) {
		select {
		case firstOut <- time.Now():
		default:
		}
		return len(p), nil
	})

	tr, err := newTranscoder(dst, "mp3")
	if err != nil {
		t.Fatalf("newTranscoder: %v", err)
	}
	defer func() { _ = tr.close() }()

	start := time.Now()
	// Pousser en petits blocs, comme un diffuseur en direct : ffmpeg ne doit pas
	// attendre la fin de l'entrée pour commencer à produire.
	go func() {
		for off := 0; off < len(src); off += 4096 {
			end := min(off+4096, len(src))
			if _, err := tr.Write(src[off:end]); err != nil {
				return
			}
		}
	}()

	select {
	case at := <-firstOut:
		d := at.Sub(start)
		t.Logf("latence ajoutée par le transcodage: %v", d)
		if d >= 2*time.Second {
			t.Fatalf("latence de transcodage %v, budget de l'US = 2s", d)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("aucun octet AAC produit dans les 5 s")
	}
}

type writerFunc func([]byte) (int, error)

func (f writerFunc) Write(p []byte) (int, error) { return f(p) }

// TestTranscodePipeline_MP3ToHLS exerce la chaîne complète de l'US-09-05 :
// MP3 du diffuseur -> transcodeur -> segmenteur HLS -> manifeste + segments, et
// vérifie que les auditeurs reçoivent bien de l'AAC (et non du MP3 remuxé).
func TestTranscodePipeline_MP3ToHLS(t *testing.T) {
	requireFFmpeg(t)
	if _, err := exec.LookPath("ffprobe"); err != nil {
		t.Skip("ffprobe absent du PATH : vérification du codec de sortie ignorée")
	}

	mp3 := generateTestAudio(t, "mp3", "libmp3lame", 25)

	seg, err := newHLSSegmenter("stream-test")
	if err != nil {
		t.Fatalf("newHLSSegmenter: %v", err)
	}
	defer seg.close()

	tr, err := newTranscoder(seg.input(), "mp3")
	if err != nil {
		t.Fatalf("newTranscoder: %v", err)
	}
	if _, err := io.Copy(tr, bytes.NewReader(mp3)); err != nil {
		t.Fatalf("copie du MP3 vers le transcodeur: %v", err)
	}
	if err := tr.close(); err != nil {
		t.Fatalf("close du transcodeur: %v", err)
	}

	// Fin du direct : fermer l'entrée du segmenteur pour qu'il finalise.
	if err := seg.stdin.Close(); err != nil {
		t.Fatalf("close stdin du segmenteur: %v", err)
	}
	select {
	case <-seg.done:
	case <-time.After(30 * time.Second):
		t.Fatal("le segmenteur n'a pas terminé après la fin de l'entrée")
	}

	manifest, err := os.ReadFile(seg.playlistPath())
	if err != nil {
		t.Fatalf("lecture du manifeste: %v", err)
	}
	if n := strings.Count(string(manifest), ".ts"); n < 2 {
		t.Fatalf("attendu >= 2 segments pour 25 s de MP3, obtenu %d:\n%s", n, manifest)
	}

	first := filepath.Join(seg.dir, "seg_00000.ts")
	if codec := probeAudioCodec(t, first); codec != "aac" {
		t.Fatalf("les auditeurs doivent recevoir de l'AAC, segment encodé en %q", codec)
	}
}

// probeAudioCodec retourne le codec de la première piste audio d'un fichier.
// ffprobe peut lister le même flux deux fois sur un segment MPEG-TS (programme +
// flux élémentaire) : on ne garde que la première ligne.
func probeAudioCodec(t *testing.T, path string) string {
	t.Helper()
	out, err := exec.Command("ffprobe", "-v", "error",
		"-select_streams", "a:0", "-show_entries", "stream=codec_name",
		"-of", "default=nokey=1:noprint_wrappers=1", path).Output()
	if err != nil {
		t.Fatalf("ffprobe %s: %v", path, err)
	}
	first, _, _ := strings.Cut(strings.TrimSpace(string(out)), "\n")
	return strings.TrimSpace(first)
}
