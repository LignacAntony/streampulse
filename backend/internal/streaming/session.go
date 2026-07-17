package streaming

import (
	"context"
	"io"
	"log"
	"sync"
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
	hls       *hlsSegmenter // nil si le segmenteur n'a pas pu démarrer

	mu          sync.Mutex
	closed      bool
	ingesting   bool // un seul push audio à la fois
	subscribers map[chan SessionEvent]struct{}
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
// l'ingest) et lance sa goroutine, après avoir démarré le segmenteur HLS.
// Idempotent : si une session existe déjà, rien n'est fait.
func (ls *LiveSessions) Start(streamID, streamKey string) {
	ls.mu.Lock()
	defer ls.mu.Unlock()
	if _, ok := ls.byID[streamID]; ok {
		return
	}
	ctx, cancel := context.WithCancel(ls.base)

	seg, err := ls.newSeg()
	if err != nil {
		// Le flux est déjà 'live' en base : on enregistre quand même la session
		// (stop/SSE fonctionnent) mais sans audio. En pratique ffmpeg est présent
		// dans l'image (ADR 015) ; ce chemin couvre son absence en dev.
		log.Printf("streaming: segmenteur HLS indisponible pour %s: %v", streamID, err)
		seg = nil
	}

	s := &session{
		streamKey:   streamKey,
		cancel:      cancel,
		hls:         seg,
		subscribers: make(map[chan SessionEvent]struct{}),
	}
	ls.byID[streamID] = s
	if streamKey != "" {
		ls.byKey[streamKey] = s
	}
	ls.wg.Add(1)
	go func() {
		defer ls.wg.Done()
		s.run(ctx)
	}()
}

// run est la goroutine de session : elle vit jusqu'à l'annulation du context
// (stop diffuseur ou shutdown) ou l'arrêt spontané de ffmpeg (entrée terminée /
// erreur), puis libère le segmenteur (process + répertoire de travail).
func (s *session) run(ctx context.Context) {
	if s.hls == nil {
		<-ctx.Done()
		return
	}
	select {
	case <-ctx.Done():
	case <-s.hls.done:
	}
	s.hls.close()
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
// détachement. Erreurs : errNotLive (clé inconnue / flux pas en direct),
// errSegmenterUnavailable, errIngestInProgress (un push est déjà en cours).
func (ls *LiveSessions) AttachIngest(streamKey string) (io.Writer, func(), error) {
	ls.mu.Lock()
	s, ok := ls.byKey[streamKey]
	ls.mu.Unlock()
	if !ok {
		return nil, nil, errNotLive
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		// La session a été arrêtée entre la lecture de la map et ici.
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
// n'a pas de segmenteur.
func (ls *LiveSessions) Playlist(streamID string) (string, bool) {
	ls.mu.Lock()
	s, ok := ls.byID[streamID]
	ls.mu.Unlock()
	if !ok || s.hls == nil {
		return "", false
	}
	return s.hls.playlistPath(), true
}

// Segment retourne le chemin disque d'un segment .ts du flux en direct, après
// validation stricte du nom (anti path-traversal, cf. hlsSegmenter.segmentPath).
func (ls *LiveSessions) Segment(streamID, name string) (string, bool) {
	ls.mu.Lock()
	s, ok := ls.byID[streamID]
	ls.mu.Unlock()
	if !ok || s.hls == nil {
		return "", false
	}
	return s.hls.segmentPath(name)
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
