package streaming

import (
	"context"
	"io"
	"sync"
	"time"

	"github.com/rs/zerolog/log"
)

// SessionEvent est un événement poussé aux abonnés SSE d'un flux en direct.
type SessionEvent struct {
	Type string `json:"type"` // ex. "ended"
}

// session représente une diffusion en cours : le context d'annulation de sa
// goroutine, son segmenteur HLS (STR-70), et l'ensemble des abonnés SSE (STR-85).
type session struct {
	streamID  string
	streamKey string // secret de push (index d'ingest) ; "" si non routable
	cancel    context.CancelFunc

	mu           sync.Mutex
	closed       bool
	dead         bool          // ffmpeg s'est arrêté seul : segmenteur inexploitable
	ingesting    bool          // un seul push audio à la fois
	expiring     bool          // bail expiré : arrêt en cours, plus aucun ingest accepté
	ingestExpiry *time.Timer   // arrêt différé si aucun push ne revient
	hls          *hlsSegmenter // publié après le spawn ; protégé par mu
	subscribers  map[chan SessionEvent]struct{}

	// Suivi d'audience (STR-154) : dernière requête de manifeste par client, et
	// pic observé. Détail du raisonnement dans listeners.go.
	listeners     map[string]time.Time
	peakListeners int
}

// segmenter retourne le segmenteur si la session est exploitable (segmenteur
// présent et process vivant), nil sinon. Sérialise l'accès à s.hls / s.dead.
func (s *session) segmenter() *hlsSegmenter {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.dead {
		return nil
	}
	return s.hls
}

// LiveSessions est le registre in-memory des flux en direct (une session par
// flux live). Protégé par mutex. Chaque session porte l'annulation de sa
// goroutine (STR-84), son segmenteur HLS (STR-70) et ses abonnés SSE (STR-85).
type LiveSessions struct {
	base   context.Context
	newSeg func(streamID string) (*hlsSegmenter, error) // injectable (tests sans ffmpeg)

	mu      sync.Mutex
	byID    map[string]*session // id public -> session (SSE, lecture HLS, stop)
	byKey   map[string]*session // stream_key secret -> session (ingest)
	wg      sync.WaitGroup
	metrics MetricsRecorder // jamais nil : noopRecorder par défaut (STR-166)

	ingestGrace     time.Duration
	onIngestExpired func(streamID string) error
}

// SetIngestDisconnectHandler arme le bail audio des directs. Un flux qui ne
// reçoit aucun ingest pendant grace est confié au handler, qui termine son état
// persistant. Appelé une fois au démarrage, avant les requêtes HTTP.
func (ls *LiveSessions) SetIngestDisconnectHandler(
	grace time.Duration,
	handler func(streamID string) error,
) {
	ls.mu.Lock()
	defer ls.mu.Unlock()
	ls.ingestGrace = grace
	ls.onIngestExpired = handler
}

// NewLiveSessions construit le registre. base est le context de cycle de vie du
// serveur : son annulation (shutdown) propage l'arrêt à toutes les sessions.
func NewLiveSessions(base context.Context) *LiveSessions {
	return &LiveSessions{
		base:    base,
		newSeg:  newHLSSegmenter,
		byID:    make(map[string]*session),
		byKey:   make(map[string]*session),
		metrics: noopRecorder{},
	}
}

// SetMetrics injecte le collecteur de métriques métier (STR-166). Appelé
// une fois au démarrage, avant que le serveur HTTP n'accepte des requêtes.
func (ls *LiveSessions) SetMetrics(rec MetricsRecorder) {
	if rec == nil {
		rec = noopRecorder{}
	}
	ls.mu.Lock()
	defer ls.mu.Unlock()
	ls.metrics = rec
}

// ActiveCount retourne le nombre de sessions live en cours. Lu à chaque
// scrape Prometheus via un GaugeFunc : la gauge dérive de l'état réel du
// registre, elle ne peut pas diverger (ADR 022).
func (ls *LiveSessions) ActiveCount() int {
	ls.mu.Lock()
	defer ls.mu.Unlock()
	return len(ls.byID)
}

// recorder retourne le collecteur courant sous verrou.
func (ls *LiveSessions) recorder() MetricsRecorder {
	ls.mu.Lock()
	defer ls.mu.Unlock()
	return ls.metrics
}

// Start enregistre une session pour streamID (indexée aussi par streamKey pour
// l'ingest) puis démarre son segmenteur HLS et lance sa goroutine. Idempotent :
// si une session existe déjà, rien n'est fait. Le spawn ffmpeg (MkdirTemp + fork,
// potentiellement lents) se fait HORS du verrou du registre pour ne pas bloquer
// les autres sessions ; le segmenteur est publié ensuite sous le verrou de session.
func (ls *LiveSessions) Start(streamID, streamKey string) {
	// Phase 1 — réserver l'entrée dans le registre sous verrou (aucune I/O).
	ls.mu.Lock()
	if _, ok := ls.byID[streamID]; ok {
		ls.mu.Unlock()
		return
	}
	// #nosec G118 -- cancel n'est pas perdu : il est stocké dans s.cancel et
	// appelé par reap() et StopAll(). gosec ne suit pas un CancelFunc rangé dans
	// une structure ; ici la fuite qu'il redoute n'existe pas.
	ctx, cancel := context.WithCancel(ls.base)
	s := &session{
		streamID:    streamID,
		streamKey:   streamKey,
		cancel:      cancel,
		subscribers: make(map[chan SessionEvent]struct{}),
	}
	ls.byID[streamID] = s
	if streamKey != "" {
		ls.byKey[streamKey] = s
	}
	ls.wg.Add(1)
	ls.mu.Unlock()

	// Phase 2 — spawn du segmenteur HORS verrou (le flux est déjà 'live' en base ;
	// en cas d'échec ffmpeg, la session reste enregistrée mais sans audio — stop/SSE
	// fonctionnent. En pratique ffmpeg est présent dans l'image, ADR 015).
	seg, err := ls.newSeg(streamID)
	if err != nil {
		log.Error().Err(err).Str("stream_id", streamID).Msg("streaming: segmenteur HLS indisponible")
		seg = nil
	}

	// Phase 3 — publier le segmenteur puis lancer la goroutine de session.
	s.mu.Lock()
	s.hls = seg
	s.mu.Unlock()
	ls.armIngestExpiry(s)

	go func() {
		defer ls.wg.Done()
		if s.run(ctx) {
			// ffmpeg est mort seul : on récolte la session (retrait + notif).
			ls.reap(streamID, s)
		}
	}()
}

// run est la goroutine de session : elle vit jusqu'à l'annulation du context
// (stop diffuseur ou shutdown) ou l'arrêt spontané de ffmpeg (entrée terminée /
// erreur), puis libère le segmenteur (process + répertoire de travail). Retourne
// true si ffmpeg s'est arrêté seul (la session doit alors être récoltée).
func (s *session) run(ctx context.Context) bool {
	seg := s.segmenter()
	if seg == nil {
		<-ctx.Done()
		return false
	}
	select {
	case <-ctx.Done():
		seg.close()
		return false
	case <-seg.done:
		// Marquer la session inexploitable AVANT le nettoyage pour que
		// Playlist/Segment/AttachIngest cessent immédiatement de servir un flux mort.
		s.mu.Lock()
		s.dead = true
		s.mu.Unlock()
		seg.close()
		return true
	}
}

// reap retire du registre une session dont le segmenteur est mort seul, notifie
// ses abonnés SSE (fin de flux) et termine l'état persistant du flux. No-op si
// la session a déjà été remplacée/retirée entre-temps.
//
// La transition en base emprunte le handler du bail d'ingest : sans elle la
// ligne resterait 'live' jusqu'au stop du diffuseur, et le flux continuerait
// d'apparaître en direct dans GET /api/streams alors que plus rien n'est servi —
// un auditeur qui clique tombe sur une erreur. Le bail ne referme que le cas où
// le push cesse aussi ; ffmpeg peut mourir seul pendant que le diffuseur
// continue d'émettre.
func (ls *LiveSessions) reap(streamID string, s *session) {
	ls.mu.Lock()
	handler := ls.onIngestExpired
	if ls.byID[streamID] == s {
		delete(ls.byID, streamID)
		if s.streamKey != "" {
			delete(ls.byKey, s.streamKey)
		}
	}
	ls.mu.Unlock()
	rec := ls.recorder()
	rec.RecordStreamInterruption(InterruptionSegmenterFailed)
	rec.ForgetStream(streamID)
	s.publish(SessionEvent{Type: "ended"})
	s.closeSubscribers()

	// Hors verrou : le handler repasse par Service, qui peut rappeler Stop.
	// Best-effort — la session mémoire est déjà retirée, donc plus rien n'est
	// servi ; un échec ici ne laisse qu'une ligne à réconcilier au prochain boot
	// (ADR 013 §7). Le handler journalise sa propre erreur.
	if handler != nil {
		if err := handler(streamID); err != nil {
			log.Warn().Err(err).Str("stream_id", streamID).
				Msg("streaming: segmenteur mort, état persistant non terminé (réconciliation au boot)")
		}
	}
}

// Stop retire la session, publie l'événement "ended" (best-effort) à ses abonnés,
// PUIS ferme leurs canaux (signal de fin de flux faisant autorité) et annule la
// goroutine (qui libère le segmenteur). No-op si aucune session active.
func (ls *LiveSessions) Stop(streamID string) {
	ls.mu.Lock()
	s, ok := ls.byID[streamID]
	if ok {
		delete(ls.byID, streamID)
		if s.streamKey != "" {
			delete(ls.byKey, s.streamKey)
		}
	}
	ls.mu.Unlock()
	if !ok {
		return
	}
	ls.recorder().ForgetStream(streamID)
	s.publish(SessionEvent{Type: "ended"})
	s.closeSubscribers()
	s.cancel()
}

// armIngestExpiry (ré)arme le délai de grâce d'une session sans ingest. Le
// callback est appelé hors verrou ; il peut donc repasser par Service puis Stop
// sans interblocage.
func (ls *LiveSessions) armIngestExpiry(s *session) {
	ls.mu.Lock()
	grace := ls.ingestGrace
	handler := ls.onIngestExpired
	ls.mu.Unlock()
	if grace <= 0 || handler == nil {
		return
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed || s.dead || s.ingesting {
		return
	}
	if s.ingestExpiry != nil {
		s.ingestExpiry.Stop()
	}
	var timer *time.Timer
	timer = time.AfterFunc(grace, func() {
		s.mu.Lock()
		if s.ingestExpiry != timer || s.closed || s.dead || s.ingesting || s.expiring {
			s.mu.Unlock()
			return
		}
		s.ingestExpiry = nil
		// Marquer l'arrêt AVANT de relâcher le verrou : le handler termine la
		// session sans le tenir, et un diffuseur qui se reconnecterait dans cet
		// intervalle passerait sinon tous les gardes d'AttachIngest pour
		// obtenir un ingest aussitôt cassé par Stop.
		s.expiring = true
		s.mu.Unlock()
		// Compté ici et non dans le handler : à ce point la diffusion est
		// perdue quoi qu'il advienne de l'écriture en base, et c'est cette
		// perte — pas son enregistrement — que la métrique décrit (STR-244).
		ls.recorder().RecordStreamInterruption(InterruptionIngestTimeout)
		if err := handler(s.streamID); err != nil {
			// Une indisponibilité transitoire de la base ne doit pas désarmer le
			// garde-fou : tant que la session existe, une nouvelle tentative sera
			// faite après le même délai de grâce — et l'ingest redevient
			// acceptable entre-temps, la session n'ayant pas été terminée.
			s.mu.Lock()
			s.expiring = false
			s.mu.Unlock()
			ls.armIngestExpiry(s)
		}
	})
	s.ingestExpiry = timer
}

// AttachIngest réserve la session live identifiée par streamKey pour un unique
// push audio, et retourne l'entrée où copier le flux + une fonction de
// détachement. Erreurs : errNotLive (clé inconnue / flux pas en direct / segmenteur
// mort / bail d'ingest expiré), errSegmenterUnavailable, errIngestInProgress (un
// push est déjà en cours).
func (ls *LiveSessions) AttachIngest(streamKey string) (io.Writer, func(), error) {
	ls.mu.Lock()
	s, ok := ls.byKey[streamKey]
	ls.mu.Unlock()
	if !ok {
		return nil, nil, errNotLive
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed || s.dead || s.expiring {
		// Session arrêtée (entre la lecture de la map et ici), segmenteur mort,
		// ou bail expiré dont l'arrêt est déjà lancé.
		return nil, nil, errNotLive
	}
	if s.hls == nil {
		return nil, nil, errSegmenterUnavailable
	}
	if s.ingesting {
		return nil, nil, errIngestInProgress
	}
	if s.ingestExpiry != nil {
		s.ingestExpiry.Stop()
		s.ingestExpiry = nil
	}
	s.ingesting = true
	var once sync.Once
	release := func() {
		once.Do(func() {
			s.mu.Lock()
			s.ingesting = false
			s.mu.Unlock()
			ls.armIngestExpiry(s)
		})
	}
	return s.hls.input(), release, nil
}

// Playlist retourne le chemin disque du manifeste .m3u8 du flux en direct
// (identifié par son id public). ("", false) si le flux n'est pas en direct ou
// n'a pas de segmenteur exploitable.
func (ls *LiveSessions) Playlist(streamID string) (string, bool) {
	ls.mu.Lock()
	s, ok := ls.byID[streamID]
	ls.mu.Unlock()
	if !ok {
		return "", false
	}
	seg := s.segmenter()
	if seg == nil {
		return "", false
	}
	return seg.playlistPath(), true
}

// Segment retourne le chemin disque d'un segment .ts du flux en direct, après
// validation stricte du nom (anti path-traversal, cf. hlsSegmenter.segmentPath).
func (ls *LiveSessions) Segment(streamID, name string) (string, bool) {
	ls.mu.Lock()
	s, ok := ls.byID[streamID]
	ls.mu.Unlock()
	if !ok {
		return "", false
	}
	seg := s.segmenter()
	if seg == nil {
		return "", false
	}
	return seg.segmentPath(name)
}

// Subscribe abonne un client SSE aux événements du flux. Retourne le canal de
// réception et une fonction de désabonnement, ou (nil, nil) si le flux n'est pas
// en direct.
func (ls *LiveSessions) Subscribe(streamID string) (<-chan SessionEvent, func()) {
	ls.mu.Lock()
	s, ok := ls.byID[streamID]
	ls.mu.Unlock()
	if !ok {
		return nil, nil
	}

	ch := make(chan SessionEvent, 1)
	s.mu.Lock()
	if s.closed {
		// La session a été arrêtée entre la lecture de la map et ici : ne pas
		// ajouter un abonné qui ne serait jamais notifié ni fermé.
		s.mu.Unlock()
		return nil, nil
	}
	s.subscribers[ch] = struct{}{}
	s.mu.Unlock()

	unsub := func() {
		s.mu.Lock()
		if _, present := s.subscribers[ch]; present {
			delete(s.subscribers, ch)
			close(ch)
		}
		s.mu.Unlock()
	}
	return ch, unsub
}

// IsLive indique si une session est active pour ce flux.
func (ls *LiveSessions) IsLive(streamID string) bool {
	ls.mu.Lock()
	defer ls.mu.Unlock()
	_, ok := ls.byID[streamID]
	return ok
}

// TouchListener enregistre qu'un client vient de demander le manifeste d'un
// flux (STR-154). No-op si le flux n'est plus en direct.
//
// clientKey identifie le lecteur : HLS n'ouvre pas de connexion persistante et
// les lecteurs natifs ne portent pas le Bearer (cf. serveHLSFile), on ne peut
// donc pas s'appuyer sur l'identité authentifiée.
func (ls *LiveSessions) TouchListener(streamID, clientKey string) {
	ls.mu.Lock()
	s, ok := ls.byID[streamID]
	ls.mu.Unlock()
	if !ok {
		return
	}
	s.mu.Lock()
	departed := s.touchListener(clientKey, time.Now())
	s.mu.Unlock()
	// Garde volontaire : TouchListener est sur le chemin chaud HLS et le cas
	// courant est departed == 0. Sans elle, chaque manifeste paierait une prise
	// du verrou du registre pour publier un zéro.
	if departed > 0 {
		ls.recorder().RecordListenerDepartures(departed)
	}
}

// Stats retourne l'audience courante d'un flux en direct. Le second retour est
// faux si le flux n'a pas de session active — l'appelant décide alors quoi
// afficher (zéro plutôt qu'une erreur, cf. handler).
func (ls *LiveSessions) Stats(streamID string) (SessionStats, bool) {
	ls.mu.Lock()
	s, ok := ls.byID[streamID]
	ls.mu.Unlock()
	if !ok {
		return SessionStats{}, false
	}
	s.mu.Lock()
	snapshot, departed := s.stats(time.Now())
	s.mu.Unlock()
	ls.recorder().RecordListenerDepartures(departed)
	return snapshot, true
}

// TotalListeners retourne l'audience estimée cumulée de tous les directs, sans
// purger : la valeur est lue par le résumé admin (STR-244) et par les scrapes,
// deux chemins qui ne doivent pas produire d'effet de bord sur le compteur de
// départs. Le balayage périodique garde ce total frais.
func (ls *LiveSessions) TotalListeners() int {
	ls.mu.Lock()
	sessions := make([]*session, 0, len(ls.byID))
	for _, s := range ls.byID {
		sessions = append(sessions, s)
	}
	ls.mu.Unlock()

	total := 0
	for _, s := range sessions {
		s.mu.Lock()
		total += len(s.listeners)
		s.mu.Unlock()
	}
	return total
}

// SweepListeners purge les auditeurs expirés de toutes les sessions vivantes et
// publie les départs constatés. Retourne le total, pour les tests.
//
// Le balayage prend le verrou du registre le temps de copier les sessions, puis
// celui de chaque session à tour de rôle : jamais les deux ensemble, et jamais
// pendant l'appel au recorder.
func (ls *LiveSessions) SweepListeners(now time.Time) int {
	ls.mu.Lock()
	sessions := make([]*session, 0, len(ls.byID))
	for _, s := range ls.byID {
		sessions = append(sessions, s)
	}
	ls.mu.Unlock()

	departed := 0
	for _, s := range sessions {
		s.mu.Lock()
		departed += s.pruneListeners(now)
		s.mu.Unlock()
	}
	ls.recorder().RecordListenerDepartures(departed)
	return departed
}

// StartListenerSweep lance le balayage périodique jusqu'à la fermeture de done.
// Même forme que httpmw.RateLimit.StartEviction : une goroutine, un ticker, un
// canal d'arrêt.
//
// Sans lui, la purge n'aurait lieu qu'à la lecture de Stats — le compteur de
// départs n'avancerait donc que pendant qu'un diffuseur consulte son tableau de
// bord, et une diffusion abandonnée garderait indéfiniment ses derniers
// auditeurs dans l'audience affichée.
func (ls *LiveSessions) StartListenerSweep(done <-chan struct{}, interval time.Duration) {
	if interval <= 0 {
		return
	}
	go func() {
		ticker := time.NewTicker(interval)
		defer ticker.Stop()
		for {
			select {
			case <-done:
				return
			case now := <-ticker.C:
				ls.SweepListeners(now)
			}
		}
	}()
}

// StopAll annule toutes les sessions (arrêt serveur) et libère les goroutines
// (qui libèrent chacune leur segmenteur).
func (ls *LiveSessions) StopAll() {
	ls.mu.Lock()
	sessions := ls.byID
	ls.byID = make(map[string]*session)
	ls.byKey = make(map[string]*session)
	ls.mu.Unlock()

	rec := ls.recorder()
	for id, s := range sessions {
		rec.ForgetStream(id)
		s.closeSubscribers()
		s.cancel()
	}
}

// Wait bloque jusqu'à la terminaison de toutes les goroutines de session (après
// Stop/StopAll ou annulation du context de base). Permet un drain déterministe
// (arrêt gracieux, tests).
func (ls *LiveSessions) Wait() { ls.wg.Wait() }

// publish diffuse un événement aux abonnés en best-effort (non bloquant). La
// livraison n'est PAS garantie pour un abonné lent ; le signal de fin de flux
// faisant autorité est la fermeture du canal par closeSubscribers (cf. Stop).
func (s *session) publish(ev SessionEvent) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for ch := range s.subscribers {
		select {
		case ch <- ev:
		default: // abonné lent : on ne bloque pas la diffusion
		}
	}
}

func (s *session) closeSubscribers() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.closed = true
	if s.ingestExpiry != nil {
		s.ingestExpiry.Stop()
		s.ingestExpiry = nil
	}
	for ch := range s.subscribers {
		close(ch)
		delete(s.subscribers, ch)
	}
}
