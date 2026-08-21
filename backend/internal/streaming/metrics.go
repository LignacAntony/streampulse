package streaming

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
func (noopRecorder) ForgetStream(string)                     {}
