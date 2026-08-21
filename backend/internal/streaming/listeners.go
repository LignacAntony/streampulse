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

// touchListener enregistre une requête de manifeste. Appelé sous le mutex de la
// session, sur le chemin chaud HLS : l'opération doit rester O(1).
//
// La purge n'a donc PAS lieu ici. Elle coûte un balayage de toute la map, et la
// faire à chaque manifeste sérialiserait derrière `s.mu` toutes les requêtes
// concurrentes d'un flux très suivi. Elle est portée par [LiveSessions.StartListenerSweep]
// et par [stats] — et déclenchée ici en dernier recours quand le plafond est atteint.
//
// Retourne le nombre d'auditeurs expirés au passage (0 dans le cas courant) :
// l'appelant les publie en métrique hors du mutex de session.
func (s *session) touchListener(key string, now time.Time) int {
	if s.listeners == nil {
		s.listeners = make(map[string]time.Time)
	}
	// Un client déjà connu est toujours rafraîchi : le plafond ne doit pas
	// figer la fenêtre de ceux qu'on suit déjà.
	if _, known := s.listeners[key]; !known && len(s.listeners) >= maxTrackedListeners {
		// Purger AVANT d'appliquer le plafond : une map saturée d'entrées déjà
		// expirées (churn d'adresses) rejetterait sinon un auditeur légitime,
		// et sous-compterait l'audience jusqu'au prochain stats().
		departed := s.pruneListeners(now)
		if len(s.listeners) >= maxTrackedListeners {
			return departed // réellement plein : le compteur sature
		}
		s.listeners[key] = now
		return departed
	}
	s.listeners[key] = now
	return 0
}

// pruneListeners retire les clients dont la dernière requête est trop ancienne
// et retourne combien ont été retirés. Appelé sous le mutex de la session.
//
// Ce retour est la source unique de streampulse_listener_departures_total
// (STR-244) : un auditeur n'est compté comme parti qu'ici, c'est-à-dire tant
// que la session vit. L'arrêt d'un flux détruit la map sans passer par cette
// fonction — les auditeurs d'une diffusion qui se termine normalement ne sont
// donc jamais comptés comme des départs.
func (s *session) pruneListeners(now time.Time) int {
	cutoff := now.Add(-listenerWindow)
	departed := 0
	for key, seen := range s.listeners {
		if seen.Before(cutoff) {
			delete(s.listeners, key)
			departed++
		}
	}
	return departed
}

// stats purge les clients expirés puis retourne l'instantané courant et le
// nombre de départs constatés au passage. Sans la purge, un flux abandonné
// afficherait éternellement ses derniers auditeurs. Appelé sous le mutex de la
// session.
//
// Depuis STR-244 la purge ne dépend plus de cet appel : [LiveSessions.StartListenerSweep]
// balaie toutes les sessions à intervalle régulier. Sans ce balayage, le compteur
// de départs n'aurait avancé que pendant qu'un diffuseur regardait son tableau
// de bord — une métrique dont la valeur dépend de qui l'observe.
//
// C'est aussi ici que le pic est mis à jour : le compte n'est exact qu'après
// purge, et le faire à l'insertion imposerait un balayage par requête (cf.
// [touchListener]). Conséquence assumée : le pic est celui **observé** aux
// instants de lecture, à 5 s près, pas un maximum instantané continu.
func (s *session) stats(now time.Time) (SessionStats, int) {
	departed := s.pruneListeners(now)
	if n := len(s.listeners); n > s.peakListeners {
		s.peakListeners = n
	}
	return SessionStats{Listeners: len(s.listeners), Peak: s.peakListeners}, departed
}
