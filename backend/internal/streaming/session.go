package streaming

import (
	"context"
	"sync"
)

// SessionEvent est un événement poussé aux abonnés SSE d'un flux en direct.
type SessionEvent struct {
	Type string `json:"type"` // ex. "ended"
}

// session représente une diffusion en cours : le context d'annulation de sa
// goroutine et l'ensemble des abonnés SSE.
type session struct {
	cancel context.CancelFunc

	mu          sync.Mutex
	closed      bool
	subscribers map[chan SessionEvent]struct{}
}

// LiveSessions est le registre in-memory des flux en direct (une session par
// flux live). Protégé par mutex. Chaque session porte l'annulation de sa
// goroutine (STR-84) et ses abonnés SSE (STR-85).
type LiveSessions struct {
	base context.Context

	mu   sync.Mutex
	byID map[string]*session
	wg   sync.WaitGroup
}

// NewLiveSessions construit le registre. base est le context de cycle de vie du
// serveur : son annulation (shutdown) propage l'arrêt à toutes les sessions.
func NewLiveSessions(base context.Context) *LiveSessions {
	return &LiveSessions{base: base, byID: make(map[string]*session)}
}

// Start enregistre une session pour streamID et lance sa goroutine. Idempotent :
// si une session existe déjà, rien n'est fait.
func (ls *LiveSessions) Start(streamID string) {
	ls.mu.Lock()
	defer ls.mu.Unlock()
	if _, ok := ls.byID[streamID]; ok {
		return
	}
	ctx, cancel := context.WithCancel(ls.base)
	s := &session{cancel: cancel, subscribers: make(map[chan SessionEvent]struct{})}
	ls.byID[streamID] = s
	ls.wg.Add(1)
	go func() {
		defer ls.wg.Done()
		s.run(ctx)
	}()
}

// run est la goroutine de session. Placeholder : elle vit jusqu'à l'annulation
// du context (stop ou shutdown). STR-70/71 y brancheront la segmentation HLS.
func (s *session) run(ctx context.Context) {
	<-ctx.Done()
}

// Stop retire la session, publie l'événement "ended" (best-effort) à ses abonnés,
// PUIS ferme leurs canaux (signal de fin de flux faisant autorité) et annule la
// goroutine. No-op si aucune session active.
func (ls *LiveSessions) Stop(streamID string) {
	ls.mu.Lock()
	s, ok := ls.byID[streamID]
	if ok {
		delete(ls.byID, streamID)
	}
	ls.mu.Unlock()
	if !ok {
		return
	}
	s.publish(SessionEvent{Type: "ended"})
	s.closeSubscribers()
	s.cancel()
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

// StopAll annule toutes les sessions (arrêt serveur) et libère les goroutines.
func (ls *LiveSessions) StopAll() {
	ls.mu.Lock()
	sessions := ls.byID
	ls.byID = make(map[string]*session)
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
