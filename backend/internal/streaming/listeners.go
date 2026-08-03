package streaming

import "time"

// listenerWindow est la fenêtre pendant laquelle un client reste compté comme
// auditeur après sa dernière requête de playlist.
//
// HLS est sans connexion persistante : un lecteur récupère le manifeste, puis
// les segments, et rien ne signale son départ. On ne peut donc qu'estimer
// l'audience à partir de la fraîcheur des requêtes. La fenêtre est calée sur
// ~3x la durée d'un segment (hlsSegmentSeconds) : un lecteur sain redemande le
// manifeste bien plus souvent, et un lecteur parti sort du compte en une
// demi-minute.
const listenerWindow = 3 * hlsSegmentSeconds * time.Second

// maxTrackedListeners borne la mémoire du suivi par flux. Au-delà, les
// nouveaux clients ne sont plus enregistrés : le compteur sature au lieu de
// laisser une diffusion très suivie — ou un attaquant qui ferait varier son
// adresse — faire enfler la map sans limite. Le limiteur HLS_MAX_CONCURRENT
// (STR-88) borne déjà les requêtes simultanées, ce plafond n'est qu'un filet.
const maxTrackedListeners = 10_000

// SessionStats est l'instantané d'audience d'une diffusion en cours.
type SessionStats struct {
	// Listeners est le nombre de clients distincts ayant demandé le manifeste
	// dans la dernière [listenerWindow]. C'est une **estimation** : deux
	// lecteurs derrière la même adresse comptent pour un, et un lecteur qui
	// vient de fermer reste compté jusqu'à l'expiration de sa fenêtre.
	Listeners int

	// Peak est le maximum de [Listeners] observé depuis le début de la
	// diffusion. Vit en mémoire : remis à zéro au redémarrage du process et
	// perdu à l'arrêt du flux (l'historique persistant est STR-162).
	Peak int
}

// touchListener enregistre une requête de manifeste et met à jour le pic.
// Appelé sous le mutex de la session.
func (s *session) touchListener(key string, now time.Time) {
	if s.listeners == nil {
		s.listeners = make(map[string]time.Time)
	}
	// Un client déjà connu est toujours rafraîchi : le plafond ne doit pas
	// figer la fenêtre de ceux qu'on suit déjà.
	if _, known := s.listeners[key]; !known && len(s.listeners) >= maxTrackedListeners {
		return
	}
	s.listeners[key] = now
	s.pruneListeners(now)
	if n := len(s.listeners); n > s.peakListeners {
		s.peakListeners = n
	}
}

// pruneListeners retire les clients dont la dernière requête est trop ancienne.
// Appelé sous le mutex de la session.
func (s *session) pruneListeners(now time.Time) {
	cutoff := now.Add(-listenerWindow)
	for key, seen := range s.listeners {
		if seen.Before(cutoff) {
			delete(s.listeners, key)
		}
	}
}

// stats retourne l'instantané courant, après purge des clients expirés — sans
// quoi un flux abandonné afficherait éternellement ses derniers auditeurs.
// Appelé sous le mutex de la session.
func (s *session) stats(now time.Time) SessionStats {
	s.pruneListeners(now)
	return SessionStats{Listeners: len(s.listeners), Peak: s.peakListeners}
}
