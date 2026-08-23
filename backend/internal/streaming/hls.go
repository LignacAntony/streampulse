package streaming

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"time"

	"github.com/rs/zerolog/log"
)

// Paramètres de segmentation HLS (cf. ADR 015).
const (
	hlsSegmentSeconds = 10 // durée cible d'un segment .ts
	hlsListSize       = 6  // fenêtre glissante du manifeste (~1 min)
	hlsPlaylistName   = "playlist.m3u8"
	hlsSegmentPattern = "seg_%05d.ts" // nom de fichier des segments (sur disque)
	hlsSegmentPrefix  = "segments/"   // préfixe des URI de segments dans le manifeste
	hlsShutdownGrace  = 5 * time.Second

	// ffmpegLogLineMax borne une « ligne » de stderr avant émission forcée. Sous
	// -loglevel warning ffmpeg n'écrit pas de barre de progression (celle-ci est
	// séparée par des \r, pas des \n), mais un flux corrompu peut produire une
	// avalanche : la borne garantit que le tampon ne grandit pas sans fin.
	ffmpegLogLineMax = 4 << 10 // 4 Ko
)

// Erreurs d'ingest, mappées vers un status HTTP par le handler.
var (
	errNotLive              = errors.New("streaming: no live session for this key")
	errSegmenterUnavailable = errors.New("streaming: hls segmenter unavailable")
	errIngestInProgress     = errors.New("streaming: ingest already in progress")
)

// segmentNamePattern valide le nom d'un segment demandé par un auditeur
// (anti path-traversal) : exactement seg_<chiffres>.ts, rien d'autre.
var segmentNamePattern = regexp.MustCompile(`^seg_\d+\.ts$`)

// hlsSegmenter pilote un process ffmpeg qui lit de l'AAC sur stdin et écrit un
// manifeste HLS + des segments MPEG-TS dans un répertoire temporaire dédié.
// L'audio est remuxé sans ré-encodage (-c:a copy).
type hlsSegmenter struct {
	dir    string           // répertoire de travail (manifeste + segments)
	cmd    *exec.Cmd        // nil dans les tests (segmenteur simulé)
	stdin  io.WriteCloser   // entrée où copier l'audio du diffuseur
	done   chan struct{}    // fermé quand le process ffmpeg a terminé
	stderr *ffmpegLogWriter // nil dans les tests ; vidé de son reliquat à close()
}

// ffmpegLogWriter route le stderr d'un ffmpeg de segmentation vers zerolog,
// une ligne de log JSON par ligne de sortie (STR-244, ADR 041).
//
// Avant, hls.go faisait `cmd.Stderr = os.Stderr` : les lignes partaient en clair
// dans la sortie du conteneur, où Alloy les transmettait telles quelles à Loki.
// Or tous les panneaux du dashboard « Logs & Erreurs » filtrent avec `| json` —
// ces lignes étaient donc écartées en JSONParserErr. Une erreur ffmpeg pendant
// une diffusion était invisible dans Grafana.
//
// Le transcodeur d'ingest (transcode.go) résout le même problème avec un
// tailBuffer, qui convient à un process court dont on lit la fin après coup.
// Le segmenteur, lui, vit toute la diffusion : ses erreurs doivent apparaître
// quand elles surviennent, d'où l'émission au fil de l'eau.
//
// os/exec n'appelle Write que depuis la goroutine de recopie qu'il crée pour un
// Stderr non-*os.File, et cmd.Wait() l'attend : aucun accès concurrent, donc
// pas de verrou. Le reliquat sans saut de ligne final est vidé par close(),
// après la terminaison du process.
type ffmpegLogWriter struct {
	streamID string
	buf      bytes.Buffer
}

func (w *ffmpegLogWriter) Write(p []byte) (int, error) {
	w.buf.Write(p)
	for {
		line, err := w.buf.ReadBytes('\n')
		if err != nil {
			// Pas de saut de ligne : garder en tampon jusqu'au prochain Write,
			// sauf si le tampon dépasse la borne — sinon un ffmpeg qui n'en
			// émettrait jamais ferait grandir la mémoire sans limite.
			if len(line) >= ffmpegLogLineMax {
				w.emit(line)
			} else {
				w.buf.Write(line)
			}
			return len(p), nil
		}
		w.emit(line)
	}
}

// emit journalise une ligne de stderr. Niveau warn et non error : ffmpeg écrit
// à ce flux des avertissements bénins (paquets non monotones, ré-horodatage)
// aussi bien que des erreurs fatales, et il ne les distingue pas dans un format
// exploitable. Les faire toutes passer en error déclencherait l'alerte 5xx sur
// du bruit ; warn les rend cherchables sans mentir sur leur gravité.
func (w *ffmpegLogWriter) emit(line []byte) {
	msg := string(bytes.TrimRight(line, "\r\n"))
	if msg == "" {
		return
	}
	log.Warn().Str("stream_id", w.streamID).Str("component", "ffmpeg-hls").Msg(msg)
}

// flush vide le reliquat resté sans saut de ligne. Appelé après la terminaison
// du process : plus aucun Write ne peut survenir.
func (w *ffmpegLogWriter) flush() {
	if w.buf.Len() > 0 {
		w.emit(w.buf.Bytes())
		w.buf.Reset()
	}
}

// newHLSSegmenter crée le répertoire de travail et démarre ffmpeg. En cas
// d'échec (ffmpeg absent, etc.) le répertoire est nettoyé et l'erreur remontée.
// streamID ne sert qu'à étiqueter les logs de stderr : plusieurs diffusions
// coexistent, une ligne ffmpeg anonyme serait inexploitable.
func newHLSSegmenter(streamID string) (*hlsSegmenter, error) {
	dir, err := os.MkdirTemp("", "streampulse-hls-")
	if err != nil {
		return nil, fmt.Errorf("hls: create work dir: %w", err)
	}

	// Arguments ffmpeg : uniquement des constantes et des chemins dérivés de `dir`
	// (os.MkdirTemp, généré côté serveur). AUCUNE entrée diffuseur/auditeur ne
	// transite par la ligne de commande — le stream_key est un lookup mémoire et
	// l'audio arrive par stdin (pipe:0). Le G204 de gosec est donc un faux positif.
	args := []string{
		"-hide_banner", "-loglevel", "warning",
		"-i", "pipe:0", // audio lu sur stdin
		"-c:a", "copy", // remux AAC -> TS, pas de transcodage
		"-f", "hls",
		"-hls_time", strconv.Itoa(hlsSegmentSeconds),
		"-hls_list_size", strconv.Itoa(hlsListSize),
		"-hls_flags", "delete_segments+append_list+omit_endlist",
		"-hls_segment_type", "mpegts",
		"-hls_base_url", hlsSegmentPrefix, // les URI du manifeste pointent vers segments/…
		"-hls_segment_filename", filepath.Join(dir, hlsSegmentPattern),
		filepath.Join(dir, hlsPlaylistName),
	}
	// noctx voudrait exec.CommandContext. Inadapté : ce ffmpeg vit le temps de la
	// session live, pas d'une requête, et son arrêt est déjà piloté par close() —
	// fermeture de stdin pour qu'il finalise son dernier segment, puis kill au
	// bout de hlsShutdownGrace. Le rattacher à un context le tuerait sèchement à
	// l'annulation, avant cette finalisation : dernier segment perdu à chaque
	// diffusion.
	//nolint:noctx // arrêt géré explicitement par close(), cf. ci-dessus
	cmd := exec.Command("ffmpeg", args...) // #nosec G204 -- args 100% statiques/serveur (os.MkdirTemp), aucune entrée utilisateur
	stderr := &ffmpegLogWriter{streamID: streamID}
	cmd.Stderr = stderr // warnings/erreurs ffmpeg en JSON structuré (STR-244)

	stdin, err := cmd.StdinPipe()
	if err != nil {
		_ = os.RemoveAll(dir)
		return nil, fmt.Errorf("hls: stdin pipe: %w", err)
	}
	if err := cmd.Start(); err != nil {
		_ = stdin.Close()
		_ = os.RemoveAll(dir)
		return nil, fmt.Errorf("hls: start ffmpeg: %w", err)
	}

	s := &hlsSegmenter{dir: dir, cmd: cmd, stdin: stdin, done: make(chan struct{}), stderr: stderr}
	go func() {
		_ = cmd.Wait()
		close(s.done)
	}()
	return s, nil
}

// input expose l'entrée stdin de ffmpeg : le handler d'ingest y copie l'audio.
func (s *hlsSegmenter) input() io.Writer { return s.stdin }

// playlistPath retourne le chemin disque du manifeste .m3u8.
func (s *hlsSegmenter) playlistPath() string { return filepath.Join(s.dir, hlsPlaylistName) }

// segmentPath retourne le chemin disque d'un segment après validation stricte du
// nom (anti-traversal). ("", false) si le nom ne correspond pas au motif attendu.
func (s *hlsSegmenter) segmentPath(name string) (string, bool) {
	if !segmentNamePattern.MatchString(name) {
		return "", false
	}
	return filepath.Join(s.dir, name), true
}

// close ferme stdin (ffmpeg finalise le dernier segment et s'arrête), attend sa
// terminaison (bornée par hlsShutdownGrace, sinon kill) puis supprime le
// répertoire de travail. Idempotence non requise : appelé une fois par session.
func (s *hlsSegmenter) close() {
	_ = s.stdin.Close()
	if s.cmd != nil {
		select {
		case <-s.done:
		case <-time.After(hlsShutdownGrace):
			_ = s.cmd.Process.Kill()
			<-s.done
		}
	}
	// Après <-s.done : cmd.Wait() a rendu la main, donc la recopie de stderr est
	// terminée et plus aucun Write ne viendra. Vider le reliquat ici est le seul
	// moyen de ne pas perdre une dernière ligne sans saut de ligne final.
	if s.stderr != nil {
		s.stderr.flush()
	}
	_ = os.RemoveAll(s.dir)
}
