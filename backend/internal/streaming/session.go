package streaming

import (
	"context"
	"io"
	"sync"

	"github.com/rs/zerolog/log"
)

// SessionEvent est un événement poussé aux abonnés SSE d'un flux en direct.
type SessionEvent struct {
	Type string `json:"type"` // ex. "ended"
}

// session représente une diffusion en cours : le context d'annulation de sa
// goroutine, son segmenteur HLS (STR-70), et l'ensemble des abonnés SSE (STR-85).
type session struct {
	streamKey string // secret de push (index d'ingest) ; "" si non routable
	cancel    context.CancelFunc

	mu          sync.Mutex
	closed      bool
	dead        bool          // ffmpeg s'est arrêté seul : segmenteur inexploitable
	ingesting   bool          // un seul push audio à la fois
	hls         *hlsSegmenter // publié après le spawn ; protégé par mu
	subscribers map[chan SessionEvent]struct{}
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
	newSeg func() (*hlsSegmenter, error) // injectable (tests sans ffmpeg)

	mu    sync.Mutex
	byID  map[string]*session // id public -> session (SSE, lecture HLS, stop)
	byKey map[string]*session // stream_key secret -> session (ingest)
	wg    sync.WaitGroup
}

// NewLiveSessions construit le registre. base est le context de cycle de vie du
// serveur : son annulation (shutdown) propage l'arrêt à toutes les sessions.
func NewLiveSessions(base context.Context) *LiveSessions {
	return &LiveSessions{
		base:   base,
		newSeg: newHLSSegmenter,
		byID:   make(map[string]*session),
		byKey:  make(map[string]*session),
	}
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
	ctx, cancel := context.WithCancel(ls.base)
	s := &session{
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
	seg, err := ls.newSeg()
	if err != nil {
		log.Error().Err(err).Str("stream_id", streamID).Msg("streaming: segmenteur HLS indisponible")
		seg = nil
	}

	// Phase 3 — publier le segmenteur puis lancer la goroutine de session.
	s.mu.Lock()
	s.hls = seg
	s.mu.Unlock()

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

// reap retire du registre une session dont le segmenteur est mort seul et notifie
// ses abonnés SSE (fin de flux). La ligne DB reste 'live' jusqu'au stop du
// diffuseur (réconciliée au boot, cf. ADR 013 §7). No-op si la session a déjà été
// remplacée/retirée entre-temps.
func (ls *LiveSessions) reap(streamID string, s *session) {
	ls.mu.Lock()
	if ls.byID[streamID] == s {
		delete(ls.byID, streamID)
		if s.streamKey != "" {
			delete(ls.byKey, s.streamKey)
		}
	}
	ls.mu.Unlock()
	s.publish(SessionEvent{Type: "ended"})
	s.closeSubscribers()
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
	s.publish(SessionEvent{Type: "ended"})
	s.closeSubscribers()
	s.cancel()
}

// AttachIngest réserve la session live identifiée par streamKey pour un unique
// push audio, et retourne l'entrée où copier le flux + une fonction de
// détachement. Erreurs : errNotLive (clé inconnue / flux pas en direct / segmenteur
// mort), errSegmenterUnavailable, errIngestInProgress (un push est déjà en cours).
func (ls *LiveSessions) AttachIngest(streamKey string) (io.Writer, func(), error) {
	ls.mu.Lock()
	s, ok := ls.byKey[streamKey]
	ls.mu.Unlock()
	if !ok {
		return nil, nil, errNotLive
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed || s.dead {
		// Session arrêtée (entre la lecture de la map et ici) ou segmenteur mort.
		return nil, nil, errNotLive
	}
	if s.hls == nil {
		return nil, nil, errSegmenterUnavailable
	}
	if s.ingesting {
		return nil, nil, errIngestInProgress
	}
	s.ingesting = true
	release := func() {
		s.mu.Lock()
		s.ingesting = false
		s.mu.Unlock()
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

// StopAll annule toutes les sessions (arrêt serveur) et libère les goroutines
// (qui libèrent chacune leur segmenteur).
func (ls *LiveSessions) StopAll() {
	ls.mu.Lock()
	sessions := ls.byID
	ls.byID = make(map[string]*session)
	ls.byKey = make(map[string]*session)
	ls.mu.Unlock()

	for _, s := range sessions {
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
	for ch := range s.subscribers {
		close(ch)
		delete(s.subscribers, ch)
	}
}
