package streaming

import (
	"errors"
	"fmt"
	"io"
	"mime"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// Paramètres du transcodage d'ingest (cf. ADR 030).
//
// Le transcodeur est un process ffmpeg intercalé DEVANT le segmenteur : il lit le
// format du diffuseur sur stdin et écrit de l'AAC/ADTS sur stdout, que l'on
// recopie dans l'entrée du segmenteur. Celui-ci reste donc en `-c:a copy` — un
// push AAC ne paie strictement rien (aucun process en plus, aucun ré-encodage).
const (
	transcodeCodec      = "aac"
	transcodeBitrate    = "128k"
	transcodeSampleRate = 44100
	transcodeChannels   = 2

	// Bornes d'analyse de l'entrée. Les valeurs par défaut de ffmpeg (5 Mo /
	// 5 s) suffiraient à faire dépasser le budget de latence de l'US ; 128 Kio
	// et 1 s couvrent largement les en-têtes MP3/OGG/WAV/FLAC.
	transcodeProbeSize       = 128 << 10 // octets
	transcodeAnalyzeDuration = 1_000_000 // microsecondes

	// Taille max du stderr ffmpeg conservé pour le diagnostic (les warnings
	// d'un push de plusieurs heures ne doivent pas gonfler la mémoire).
	transcodeStderrMaxBytes = 8 << 10

	// Borne l'attente de fin du relais stdout -> segmenteur dans close().
	// Tuer ffmpeg ferme son stdout et débloque une recopie coincée en LECTURE,
	// mais pas une recopie coincée en ÉCRITURE vers un segmenteur vivant qui ne
	// consomme plus (le tampon du pipe est plein). Sans cette borne, close() ne
	// rendrait jamais la main : le handler ne retournerait pas, release() ne
	// s'exécuterait pas, et le slot d'ingest du flux resterait pris.
	transcodeRelayTimeout = 2 * hlsShutdownGrace
)

// errTranscodeRelayStalled signale que le relais vers le segmenteur n'a pas pu
// être drainé dans les temps. C'est une défaillance serveur — le corps du
// diffuseur n'est pas en cause — d'où un traitement distinct du payload
// indécodable côté handler.
var errTranscodeRelayStalled = errors.New("transcode: relais vers le segmenteur bloqué")

// ingestFormat décrit comment traiter le corps d'un push d'ingest.
//
// passthrough : l'audio est déjà de l'AAC/ADTS, il part tel quel dans le
// segmenteur (chemin historique, latence ajoutée nulle).
// demuxer : nom du démultiplexeur ffmpeg à forcer via `-f` ; vide = laisser
// ffmpeg sonder l'entrée (formats audio non listés).
type ingestFormat struct {
	passthrough bool
	demuxer     string
	mediaType   string
}

// ingestDemuxers associe les types MIME acceptés au démultiplexeur ffmpeg
// correspondant. Forcer `-f` plutôt que laisser ffmpeg sonder évite une attente
// d'analyse au démarrage du flux, et garantit que la ligne de commande ne
// contient que des constantes serveur (cf. le #nosec de newTranscoder).
//
// Les entrées conteneur (mp4, webm, matroska) sont **best-effort** : l'ingest
// est un pipe non-seekable, seules leurs variantes fragmentées y sont lisibles.
// Un MP4 classique, dont l'index (`moov`) est écrit en fin de fichier, échoue
// donc — proprement, en 415 « audio payload could not be decoded », jamais en
// blocage. C'est le comportement voulu : refuser d'avance ces types priverait
// les diffuseurs qui poussent du fMP4 ou du WebM en direct, cas parfaitement
// courant (cf. ADR 030 § « Formats acceptés »).
var ingestDemuxers = map[string]string{
	"audio/mpeg":     "mp3",
	"audio/mp3":      "mp3",
	"audio/x-mpeg":   "mp3",
	"audio/mpeg3":    "mp3",
	"audio/x-mpeg-3": "mp3",

	"audio/ogg":    "ogg",
	"audio/x-ogg":  "ogg",
	"audio/vorbis": "ogg",
	"audio/opus":   "ogg",

	"audio/wav":        "wav",
	"audio/x-wav":      "wav",
	"audio/wave":       "wav",
	"audio/vnd.wave":   "wav",
	"audio/x-pn-wav":   "wav",
	"audio/flac":       "flac",
	"audio/x-flac":     "flac",
	"audio/aiff":       "aiff",
	"audio/x-aiff":     "aiff",
	"audio/webm":       "webm",
	"audio/mp4":        "mp4",
	"audio/x-m4a":      "mp4",
	"audio/matroska":   "matroska",
	"audio/x-matroska": "matroska",
}

// ingestPassthrough liste les types MIME déjà en AAC brut (ADTS) : ceux-là
// n'ont rien à transcoder. `audio/mp4` en est volontairement absent — c'est un
// conteneur MP4, qui doit être démuxé avant d'atteindre le segmenteur.
var ingestPassthrough = map[string]struct{}{
	"audio/aac":           {},
	"audio/aacp":          {},
	"audio/x-aac":         {},
	"audio/x-hx-aac-adts": {},
}

// resolveIngestFormat décide du traitement à appliquer au corps d'un push à
// partir de son Content-Type.
//
// Content-Type absent -> passthrough : le contrat historique reste celui d'un
// push AAC brut (clients bruts, cf. ADR 015). Un type audio/* inconnu est
// accepté et confié au sondage de ffmpeg, conformément à l'US « accepter
// n'importe quel format entrant ». Tout ce qui n'est pas audio/* est refusé
// avant qu'un seul octet n'atteigne un process ffmpeg.
func resolveIngestFormat(contentType string) (ingestFormat, bool) {
	if contentType == "" {
		return ingestFormat{passthrough: true}, true
	}
	mt, _, err := mime.ParseMediaType(contentType)
	if err != nil {
		return ingestFormat{}, false
	}
	mt = strings.ToLower(mt)
	if !strings.HasPrefix(mt, "audio/") {
		return ingestFormat{}, false
	}
	if _, ok := ingestPassthrough[mt]; ok {
		return ingestFormat{passthrough: true, mediaType: mt}, true
	}
	// demuxer vide pour un audio/* non répertorié : ffmpeg sondera l'entrée.
	return ingestFormat{demuxer: ingestDemuxers[mt], mediaType: mt}, true
}

// transcoder est un process ffmpeg qui convertit à la volée le flux du
// diffuseur en AAC/ADTS et le recopie dans dst (l'entrée du segmenteur HLS).
// Il implémente io.Writer : le handler d'ingest y copie le corps de la requête
// exactement comme il copiait dans le segmenteur.
type transcoder struct {
	cmd    *exec.Cmd
	stdin  io.WriteCloser
	stderr *tailBuffer

	copied chan struct{} // fermé quand la recopie stdout -> dst est terminée
	// Atomique : sur relais bloqué, close() rend la main avant la fin de la
	// goroutine de recopie, et le handler lit produced() pendant qu'elle tourne.
	copyN   atomic.Int64
	copyErr error // écrit avant close(copied), à ne lire qu'ensuite

	// relayTimeout vaut transcodeRelayTimeout ; surchargeable par les tests
	// pour ne pas leur imposer d'attendre le délai de production.
	relayTimeout time.Duration

	closeOnce sync.Once
	closeErr  error
}

// newTranscoder démarre ffmpeg et branche sa sortie sur dst. demuxer force le
// format d'entrée ; vide, ffmpeg sonde l'entrée.
func newTranscoder(dst io.Writer, demuxer string) (*transcoder, error) {
	// Arguments 100 % constants côté serveur : `demuxer` ne peut valoir qu'une
	// des valeurs de la table ingestDemuxers, jamais une chaîne du diffuseur.
	// L'audio arrive par stdin (pipe:0). Le G204 de gosec est un faux positif.
	args := []string{"-hide_banner", "-loglevel", "warning"}
	args = append(args,
		"-fflags", "+nobuffer",
		"-probesize", strconv.Itoa(transcodeProbeSize),
		"-analyzeduration", strconv.Itoa(transcodeAnalyzeDuration),
	)
	if demuxer != "" {
		args = append(args, "-f", demuxer)
	}
	args = append(args,
		"-i", "pipe:0",
		"-vn", // ignore une éventuelle pochette embarquée (ID3 APIC)
		"-c:a", transcodeCodec,
		"-b:a", transcodeBitrate,
		"-ar", strconv.Itoa(transcodeSampleRate),
		"-ac", strconv.Itoa(transcodeChannels),
		"-f", "adts",
		"-flush_packets", "1", // pousser chaque paquet : pas de rétention en sortie
		"pipe:1",
	)

	cmd := exec.Command("ffmpeg", args...) // #nosec G204 -- args constants serveur, aucune entrée diffuseur
	stderr := &tailBuffer{max: transcodeStderrMaxBytes}
	cmd.Stderr = stderr

	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, fmt.Errorf("transcode: stdin pipe: %w", err)
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		_ = stdin.Close()
		return nil, fmt.Errorf("transcode: stdout pipe: %w", err)
	}
	if err := cmd.Start(); err != nil {
		_ = stdin.Close()
		_ = stdout.Close()
		return nil, fmt.Errorf("transcode: start ffmpeg: %w", err)
	}

	t := &transcoder{
		cmd:          cmd,
		stdin:        stdin,
		stderr:       stderr,
		copied:       make(chan struct{}),
		relayTimeout: transcodeRelayTimeout,
	}
	go func() {
		defer close(t.copied)
		n, err := io.Copy(dst, stdout)
		t.copyN.Store(n)
		t.copyErr = err
	}()
	return t, nil
}

// Write pousse l'audio du diffuseur vers ffmpeg. Si le process est mort
// (entrée indécodable), l'écriture échoue — l'io.Copy de l'ingest s'arrête.
func (t *transcoder) Write(p []byte) (int, error) { return t.stdin.Write(p) }

// produced retourne le nombre d'octets AAC effectivement transmis au
// segmenteur. À lire après close ; zéro sur un push non décodable.
func (t *transcoder) produced() int64 { return t.copyN.Load() }

// close termine le transcodage : fermeture de stdin (ffmpeg vide ses tampons et
// s'arrête), attente bornée du process puis de la recopie de sortie. L'entrée du
// segmenteur n'est PAS fermée : la session reste live après la déconnexion du
// diffuseur, comme sur le chemin passthrough. Idempotent.
func (t *transcoder) close() error {
	t.closeOnce.Do(func() {
		_ = t.stdin.Close()

		// cmd.Wait ferme le pipe de sortie : il ne doit être appelé qu'une fois la
		// recopie terminée, sinon les derniers octets AAC seraient tronqués. On
		// attend donc l'EOF de stdout, qu'un ffmpeg bloqué se voit imposer par le
		// kill différé (fermer son stdout débloque la recopie).
		kill := time.AfterFunc(hlsShutdownGrace, func() { _ = t.cmd.Process.Kill() })

		select {
		case <-t.copied:
			kill.Stop()
			err := t.cmd.Wait()
			switch {
			case err != nil:
				t.closeErr = fmt.Errorf("transcode: ffmpeg: %w: %s", err, t.stderr.String())
			case t.copyErr != nil:
				t.closeErr = fmt.Errorf("transcode: relais vers le segmenteur: %w", t.copyErr)
			}

		case <-time.After(t.relayTimeout):
			// Le kill n'a pas suffi : la recopie est bloquée en écriture vers un
			// segmenteur qui ne consomme plus. On rend la main pour libérer le
			// slot d'ingest plutôt que de tenir le handler indéfiniment.
			kill.Stop()
			_ = t.cmd.Process.Kill()
			t.closeErr = errTranscodeRelayStalled
			// Récolte différée : appeler Wait ici fermerait le pipe pendant que
			// la goroutine y lit encore. Le process est récolté dès que
			// l'écriture se débloque (typiquement à la mort du segmenteur).
			go func() {
				<-t.copied
				_ = t.cmd.Wait()
			}()
		}
	})
	return t.closeErr
}

// tailBuffer conserve au plus max octets d'une sortie (les derniers écrits) :
// le stderr d'un ffmpeg qui tourne des heures ne doit pas croître sans borne.
// Sûr en concurrence : cmd.Stderr est écrit par la goroutine de copie d'exec.
type tailBuffer struct {
	mu  sync.Mutex
	max int
	buf []byte
}

func (b *tailBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.buf = append(b.buf, p...)
	if over := len(b.buf) - b.max; over > 0 {
		b.buf = b.buf[over:]
	}
	return len(p), nil
}

func (b *tailBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return strings.TrimSpace(string(b.buf))
}
