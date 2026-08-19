package streaming

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"time"
)

// Paramètres de segmentation HLS (cf. ADR 015).
const (
	hlsSegmentSeconds = 10 // durée cible d'un segment .ts
	hlsListSize       = 6  // fenêtre glissante du manifeste (~1 min)
	hlsPlaylistName   = "playlist.m3u8"
	hlsSegmentPattern = "seg_%05d.ts" // nom de fichier des segments (sur disque)
	hlsSegmentPrefix  = "segments/"   // préfixe des URI de segments dans le manifeste
	hlsShutdownGrace  = 5 * time.Second
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
	dir   string         // répertoire de travail (manifeste + segments)
	cmd   *exec.Cmd      // nil dans les tests (segmenteur simulé)
	stdin io.WriteCloser // entrée où copier l'audio du diffuseur
	done  chan struct{}  // fermé quand le process ffmpeg a terminé
}

// newHLSSegmenter crée le répertoire de travail et démarre ffmpeg. En cas
// d'échec (ffmpeg absent, etc.) le répertoire est nettoyé et l'erreur remontée.
func newHLSSegmenter() (*hlsSegmenter, error) {
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
	cmd.Stderr = os.Stderr                 // warnings/erreurs ffmpeg vers les logs du conteneur

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

	s := &hlsSegmenter{dir: dir, cmd: cmd, stdin: stdin, done: make(chan struct{})}
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
	_ = os.RemoveAll(s.dir)
}
