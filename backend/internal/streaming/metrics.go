package streaming

import "time"

// MetricsRecorder est l'interface étroite (ISP) par laquelle le domaine
// streaming publie ses métriques métier — le domaine ignore Prometheus,
// l'implémentation vit dans internal/observability et est injectée par
// main.go (STR-166, ADR 022).
//
// Les implémentations doivent être sûres en concurrence : les requêtes HLS
// arrivent depuis les goroutines des handlers.
type MetricsRecorder interface {
	// RecordHLSRequest compte une requête de lecture HLS. kind vaut
	// "playlist" ou "segment" ; status est le code HTTP rendu à l'auditeur.
	RecordHLSRequest(streamID, kind, status string)

	// RecordListenerDepartures compte n auditeurs dont la fenêtre d'activité a
	// expiré alors que le flux diffusait toujours (STR-244, ADR 041).
	RecordListenerDepartures(n int)

	// RecordStreamInterruption compte une diffusion terminée autrement que par
	// un arrêt volontaire du diffuseur. reason est une valeur close
	// (InterruptionIngestTimeout, InterruptionSegmenterFailed).
	RecordStreamInterruption(reason string)

	// RecordIngestRecovery compte une coupure d'ingest **rétablie** : le
	// diffuseur a perdu sa connexion puis l'a retrouvée avant l'expiration du
	// bail, et `outage` mesure la durée pendant laquelle plus rien n'était
	// poussé.
	//
	// Sans elle, une coupure qui se résorbe ne laisse aucune trace : seul
	// l'échec définitif est compté (InterruptionIngestTimeout). Un incident
	// survenait, le système s'en remettait, et aucun instrument ne
	// l'enregistrait — alors que c'est précisément le cas le plus fréquent en
	// mobilité, et celui qui fait perdre de l'audio au diffuseur sans qu'il
	// puisse le quantifier.
	RecordIngestRecovery(outage time.Duration)

	// ForgetStream supprime les séries portant ce stream_id : sans cet
	// oubli, chaque diffusion terminée laisserait une série résiduelle.
	ForgetStream(streamID string)
}

// Kinds de requête HLS (label `kind` des métriques).
const (
	HLSKindPlaylist = "playlist"
	HLSKindSegment  = "segment"
)

// Raisons d'interruption d'une diffusion (label `reason`). Table close : le
// label ne prend jamais de valeur dérivée d'une entrée externe.
const (
	// InterruptionIngestTimeout : plus aucun push audio pendant le délai de
	// grâce — connexion du diffuseur coupée, application fermée, réseau perdu.
	InterruptionIngestTimeout = "ingest_timeout"

	// InterruptionSegmenterFailed : ffmpeg s'est arrêté seul alors que la
	// diffusion était en cours. Panne côté serveur, pas côté diffuseur.
	InterruptionSegmenterFailed = "segmenter_failed"
)

// noopRecorder est utilisé tant qu'aucun recorder n'est injecté (tests du
// domaine, binaires sans métriques) : le domaine ne doit jamais paniquer.
type noopRecorder struct{}

func (noopRecorder) RecordHLSRequest(string, string, string) {}
func (noopRecorder) RecordListenerDepartures(int)            {}
func (noopRecorder) RecordStreamInterruption(string)         {}
func (noopRecorder) RecordIngestRecovery(time.Duration)      {}
func (noopRecorder) ForgetStream(string)                     {}
