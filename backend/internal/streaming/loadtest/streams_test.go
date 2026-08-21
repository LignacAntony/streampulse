//go:build loadtest

// Coût CPU de N flux SIMULTANÉS (STR-243).
//
// L'ADR 016 mesure N auditeurs sur UN flux. Le sujet pose l'autre question :
// « combien nous coûte en CPU le streaming de 100 flux simultanés ? ». La
// dimension coûteuse n'est pas la même — un auditeur est une requête HTTP qui
// sert un fichier déjà écrit, un flux est un process ffmpeg qui tourne en
// permanence (deux si l'ingest n'est pas de l'AAC, cf. ADR 030).
//
// Protocole : la durée de diffusion est IDENTIQUE pour tous les N, si bien que
// les frais fixes (démarrage du serveur, du test) sont les mêmes partout. Le
// coût marginal d'un flux se lit alors dans la PENTE de la droite CPU = f(N),
// pas dans une valeur absolue — ce qui rend l'extrapolation à 100 flux motivée
// plutôt que devinée.
package loadtest

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/LignacAntony/streampulse/internal/streaming"
)

// ingestProfile décrit un chemin d'ingest à mesurer. Les deux existent en
// production et ne coûtent pas la même chose : ADR 030 intercale un second
// ffmpeg devant le segmenteur dès que le Content-Type n'est pas de l'AAC.
type ingestProfile struct {
	name        string
	contentType string
	// encodeArgs : sortie du ffmpeg GÉNÉRATEUR (côté diffuseur simulé). Son
	// coût est défalqué de la mesure — en production le diffuseur encode sur sa
	// propre machine.
	encodeArgs []string
	// serverFFmpeg : nombre de process ffmpeg que le SERVEUR démarre par flux.
	serverFFmpeg int
}

var (
	profileAAC = ingestProfile{
		name:         "aac",
		contentType:  "audio/aac",
		encodeArgs:   []string{"-c:a", "aac", "-b:a", "128k", "-f", "adts"},
		serverFFmpeg: 1, // segmenteur seul, en -c:a copy
	}
	profileMP3 = ingestProfile{
		name:         "mp3",
		contentType:  "audio/mpeg",
		encodeArgs:   []string{"-c:a", "libmp3lame", "-b:a", "128k", "-f", "mp3"},
		serverFFmpeg: 2, // transcodeur + segmenteur (ADR 030)
	}
)

// Paramètres du balayage, surchargeables pour rejouer un point isolé sans
// relancer les huit.
const (
	defaultStreamCounts    = "1,5,10,20"
	defaultBroadcastWindow = 45 * time.Second
)

// generator est un diffuseur simulé : un ffmpeg qui fabrique de l'audio en
// temps réel (`-re`) et le pousse sur l'ingest par un POST chunké — le chemin
// exact d'un vrai diffuseur.
type generator struct {
	cmd     *exec.Cmd
	drained chan struct{} // fermé quand la goroutine POST a fini de lire stdout

	once   sync.Once
	cpu    time.Duration
	status int
}

// startGenerator démarre le ffmpeg diffuseur et le POST associé. L'annulation
// de ctx tue ffmpeg et coupe le POST.
func startGenerator(t *testing.T, ctx context.Context, ingestURL string, p ingestProfile, d time.Duration) *generator {
	t.Helper()
	args := []string{
		"-hide_banner", "-loglevel", "error",
		"-re", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100",
		"-t", strconv.Itoa(int(d.Seconds())),
	}
	args = append(args, p.encodeArgs...)
	args = append(args, "-")

	cmd := exec.CommandContext(ctx, "ffmpeg", args...)
	out, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatalf("StdoutPipe: %v", err)
	}
	if err := cmd.Start(); err != nil {
		t.Fatalf("démarrage ffmpeg générateur: %v", err)
	}

	g := &generator{cmd: cmd, drained: make(chan struct{})}
	go func() {
		defer close(g.drained)
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, ingestURL, out)
		if err != nil {
			return
		}
		req.Header.Set("Content-Type", p.contentType)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			return
		}
		_, _ = io.Copy(io.Discard, resp.Body)
		_ = resp.Body.Close()
		g.status = resp.StatusCode
	}()
	t.Cleanup(g.wait)
	return g
}

// wait récolte le process. Idempotent : le corps du test l'appelle pour lire le
// CPU du générateur AVANT que la mesure ne soit prise, et t.Cleanup le rappelle
// en filet de sécurité si le test échoue avant.
//
// L'ordre importe : os/exec interdit `Wait` avant la fin des lectures du pipe
// stdout, d'où l'attente de `drained` en premier.
func (g *generator) wait() {
	g.once.Do(func() {
		<-g.drained
		_ = g.cmd.Wait()
		g.cpu = processCPU(g.cmd)
	})
}

// measurement : un point du balayage.
type measurement struct {
	streams  int
	wall     time.Duration
	server   cpuUsage      // CPU serveur, générateurs défalqués
	genCPU   time.Duration // CPU des générateurs, pour mémoire
	childRSS int64         // pic RSS du plus gros process fils (octets)
	ready    int           // flux dont le manifeste a répondu 200
	pushOK   int           // POST d'ingest terminés en 2xx
	requests int           // requêtes auditeur émises (0 si aucun auditeur)
	failures int           // parmi elles, celles qui n'ont pas rendu 200
}

func (m measurement) cores() float64 { return cores(m.server.total(), m.wall) }

// measureStreams diffuse `n` flux en parallèle pendant `window`, avec
// `listenersPer` auditeurs sur chacun, puis rend le CPU consommé par le
// serveur seul.
func measureStreams(t *testing.T, p ingestProfile, n, listenersPer int, window time.Duration) measurement {
	t.Helper()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	ls := streaming.NewLiveSessions(ctx)
	t.Cleanup(ls.StopAll)
	srv := startServer(t, ls)
	token := mintToken(t)

	before, err := readCPU()
	if err != nil {
		t.Fatalf("readCPU (avant): %v", err)
	}
	start := time.Now()

	gens := make([]*generator, n)
	ids := make([]string, n)
	for i := 0; i < n; i++ {
		id := fmt.Sprintf("%s-%s-%03d", streamID, p.name, i)
		key := fmt.Sprintf("%s-%s-%03d", streamKey, p.name, i)
		ids[i] = id
		ls.Start(id, key)
		gens[i] = startGenerator(t, ctx, srv.URL+"/api/streams/ingest/"+key, p, window)
	}

	// Attente des manifestes, en parallèle : à N élevé, les faire l'un après
	// l'autre consommerait la fenêtre de mesure en file d'attente.
	//
	// Un manifeste manquant n'interrompt PAS le balayage : c'est un résultat.
	// Le point de rupture cherché par STR-243 se manifestera exactement comme
	// ça — des flux qui ne démarrent plus dans le temps imparti.
	m := measurement{streams: n}
	var wg sync.WaitGroup
	var mu sync.Mutex
	for _, id := range ids {
		wg.Add(1)
		go func(id string) {
			defer wg.Done()
			url := fmt.Sprintf("%s/api/streams/%s/playlist.m3u8", srv.URL, id)
			if err := waitManifest(ctx, url, token, 40*time.Second); err != nil {
				t.Logf("flux %s: %v", id, err)
				return
			}
			mu.Lock()
			m.ready++
			mu.Unlock()
		}(id)
	}
	wg.Wait()

	// Auditeurs, s'il y en a. Ils démarrent APRÈS les manifestes : un auditeur
	// qui boucle sur des 409 mesurerait le coût d'un flux pas encore prêt.
	listenCtx, stopListen := context.WithCancel(ctx)
	col := &collector{}
	var lwg sync.WaitGroup
	for i := 0; i < listenersPer*n; i++ {
		id := ids[i%n]
		lwg.Add(1)
		go func(id string) {
			defer lwg.Done()
			listen(listenCtx, srv.URL, id, token, col)
		}(id)
	}

	// Laisser la diffusion se terminer d'elle-même : le générateur s'arrête au
	// bout de `window` de matière. Marge pour la finalisation du dernier segment.
	deadline := start.Add(window + 20*time.Second)
	for _, g := range gens {
		select {
		case <-g.drained:
		case <-time.After(time.Until(deadline)):
		}
	}

	stopListen()
	lwg.Wait()
	m.requests, m.failures = col.count(), col.failures()

	// Arrêt et récolte AVANT la lecture du CPU : RUSAGE_CHILDREN ne compte que
	// les fils déjà attendus (cf. readCPU).
	cancel()
	ls.StopAll()
	waitSessionsDrained(t, ls)
	for _, g := range gens {
		g.wait()
		m.genCPU += g.cpu
		if g.status >= 200 && g.status < 300 {
			m.pushOK++
		}
	}

	after, err := readCPU()
	if err != nil {
		t.Fatalf("readCPU (après): %v", err)
	}
	m.wall = time.Since(start)
	m.server = after.sub(before)
	m.server.children -= m.genCPU
	m.childRSS = childMaxRSS()

	srv.Close()
	return m
}

// waitManifest bloque jusqu'au premier 200 sur la playlist, ou rend une erreur
// à l'échéance.
func waitManifest(ctx context.Context, url, token string, timeout time.Duration) error {
	client := &http.Client{Timeout: 10 * time.Second}
	deadline := time.Now().Add(timeout)
	var last int
	for time.Now().Before(deadline) {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
		if err != nil {
			return err
		}
		req.Header.Set("Authorization", "Bearer "+token)
		resp, err := client.Do(req)
		if err == nil {
			last = resp.StatusCode
			_, _ = io.Copy(io.Discard, resp.Body)
			_ = resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				return nil
			}
		}
		time.Sleep(500 * time.Millisecond)
	}
	return fmt.Errorf("aucun manifeste après %s (dernier statut %d)", timeout, last)
}

// childMaxRSS rend le pic de RSS du plus gros process fils.
//
// ⚠️ getrusage ne rend PAS la somme des fils : ru_maxrss est le maximum d'un
// seul d'entre eux. C'est exactement ce qu'on veut ici — le coût RAM d'UN
// ffmpeg, que l'on multiplie ensuite par le nombre de process du modèle. Et
// l'unité change avec l'OS : octets sur darwin, kibioctets sur linux. Une
// conversion implicite ferait un facteur 1024 dans un dimensionnement de VPS.
func childMaxRSS() int64 {
	var ru syscall.Rusage
	if err := syscall.Getrusage(syscall.RUSAGE_CHILDREN, &ru); err != nil {
		return 0
	}
	if runtime.GOOS == "linux" {
		return int64(ru.Maxrss) * 1024
	}
	return int64(ru.Maxrss)
}

// leastSquares ajuste y = a·x + b. Rend (a, b).
func leastSquares(xs, ys []float64) (float64, float64) {
	n := float64(len(xs))
	if n < 2 {
		return 0, 0
	}
	var sx, sy, sxy, sxx float64
	for i := range xs {
		sx += xs[i]
		sy += ys[i]
		sxy += xs[i] * ys[i]
		sxx += xs[i] * xs[i]
	}
	den := n*sxx - sx*sx
	if den == 0 {
		return 0, 0
	}
	a := (n*sxy - sx*sy) / den
	return a, (sy - a*sx) / n
}

func streamCounts(t *testing.T) []int {
	t.Helper()
	raw := os.Getenv("LOADTEST_STREAMS")
	if raw == "" {
		raw = defaultStreamCounts
	}
	var out []int
	for _, f := range strings.Split(raw, ",") {
		n, err := strconv.Atoi(strings.TrimSpace(f))
		if err != nil || n <= 0 {
			t.Fatalf("LOADTEST_STREAMS invalide: %q", raw)
		}
		out = append(out, n)
	}
	return out
}

func broadcastWindow(t *testing.T) time.Duration {
	t.Helper()
	raw := os.Getenv("LOADTEST_BROADCAST_SECONDS")
	if raw == "" {
		return defaultBroadcastWindow
	}
	s, err := strconv.Atoi(raw)
	if err != nil || s < 10 {
		t.Fatalf("LOADTEST_BROADCAST_SECONDS invalide: %q (minimum 10)", raw)
	}
	return time.Duration(s) * time.Second
}

// TestStreamCPU_Sweep produit le tableau CPU × nombre de flux et le modèle
// d'extrapolation à 100 flux exigés par STR-243.
//
// Nommé hors du préfixe `TestLoad` À DESSEIN : `make loadtest` filtre sur
// `-run TestLoad` et compile avec `-race`, ce qui fausserait la mesure. Cible
// dédiée `make loadtest-cpu`.
func TestStreamCPU_Sweep(t *testing.T) {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg absent du PATH : mesure CPU ignorée")
	}
	// Un modèle de coût mesuré sous `-race` serait faux d'un ordre de grandeur
	// sur sa composante Go — et faux de façon invisible, puisque le CPU des
	// ffmpeg (non instrumentés) resterait juste. Refuser plutôt que publier.
	if raceEnabled {
		t.Fatal("mesure CPU compilée avec -race : chiffres inexploitables, utiliser `make loadtest-cpu`")
	}

	counts := streamCounts(t)
	window := broadcastWindow(t)
	t.Logf("machine: GOOS=%s GOARCH=%s NumCPU=%d — fenêtre de diffusion %s, N ∈ %v",
		runtime.GOOS, runtime.GOARCH, runtime.NumCPU(), window, counts)

	for _, p := range []ingestProfile{profileAAC, profileMP3} {
		p := p
		t.Run(p.name, func(t *testing.T) {
			var xs, ys []float64
			for _, n := range counts {
				m := measureStreams(t, p, n, 0, window)
				t.Logf("N=%-3d ffmpeg=%-3d prêts=%d/%d push2xx=%d/%d wall=%5.1fs "+
					"CPU serveur=%6.2fs (go=%5.2fs ffmpeg=%6.2fs) => %.2f cœurs "+
					"| générateurs défalqués=%6.2fs | pic RSS d'un fils=%.0f Mo",
					n, n*p.serverFFmpeg, m.ready, n, m.pushOK, n, m.wall.Seconds(),
					m.server.total().Seconds(), m.server.self.Seconds(), m.server.children.Seconds(),
					m.cores(), m.genCPU.Seconds(), float64(m.childRSS)/(1<<20))
				if m.ready == n {
					xs = append(xs, float64(n))
					ys = append(ys, m.cores())
				}
			}
			if len(xs) < 2 {
				t.Fatalf("profil %s: moins de deux points exploitables, aucun modèle possible", p.name)
			}
			slope, intercept := leastSquares(xs, ys)
			t.Logf("modèle %s: cœurs ≈ %.4f·N + %.4f  →  N=100 : %.2f cœurs (%.1f vCPU)",
				p.name, slope, intercept, slope*100+intercept, slope*100+intercept)
		})
	}
}

// TestStreamCPU_Listeners chiffre le SECOND terme du modèle de coût : ce que
// coûte un auditeur, à nombre de flux constant.
//
// Le balayage ci-dessus mesure des flux sans auditeur — il isole le coût de la
// segmentation. Un modèle de dimensionnement a besoin des deux termes, sinon
// « 100 flux » ne dit rien du parc d'auditeurs qui les écoute. La différence
// entre les deux points, sur une fenêtre identique, donne le coût marginal d'un
// auditeur.
func TestStreamCPU_Listeners(t *testing.T) {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg absent du PATH : mesure CPU ignorée")
	}
	if raceEnabled {
		t.Fatal("mesure CPU compilée avec -race : chiffres inexploitables, utiliser `make loadtest-cpu`")
	}

	window := broadcastWindow(t)
	idle := measureStreams(t, profileAAC, 1, 0, window)
	loaded := measureStreams(t, profileAAC, 1, listeners, window)

	t.Logf("1 flux, 0 auditeur   : CPU=%6.2fs sur %5.1fs => %.3f cœurs",
		idle.server.total().Seconds(), idle.wall.Seconds(), idle.cores())
	t.Logf("1 flux, %d auditeurs : CPU=%6.2fs sur %5.1fs => %.3f cœurs (%d requêtes, %d échecs)",
		listeners, loaded.server.total().Seconds(), loaded.wall.Seconds(), loaded.cores(),
		loaded.requests, loaded.failures)

	if loaded.requests == 0 {
		t.Fatal("aucune requête auditeur collectée : mesure sans objet")
	}
	perListener := (loaded.cores() - idle.cores()) / float64(listeners)
	t.Logf("coût marginal d'un auditeur : %.5f cœur (%.2f mcœur), soit %.0f auditeurs par cœur",
		perListener, perListener*1000, 1/perListener)
}
