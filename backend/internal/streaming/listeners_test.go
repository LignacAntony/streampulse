package streaming

import (
	"fmt"
	"testing"
	"time"
)

func TestSession_TouchListener_CountsDistinctClients(t *testing.T) {
	s := &session{}
	now := time.Now()

	s.touchListener("10.0.0.1", now)
	s.touchListener("10.0.0.2", now)
	s.touchListener("10.0.0.1", now) // même client : ne compte pas deux fois

	got, _ := s.stats(now)
	if got.Listeners != 2 {
		t.Errorf("Listeners = %d, want 2", got.Listeners)
	}
	if got.Peak != 2 {
		t.Errorf("Peak = %d, want 2", got.Peak)
	}
}

func TestSession_Listeners_ExpireAfterWindow(t *testing.T) {
	s := &session{}
	start := time.Now()

	s.touchListener("10.0.0.1", start)
	s.touchListener("10.0.0.2", start)

	// Un seul des deux redemande le manifeste plus tard : l'autre doit sortir
	// du compte, sans quoi un flux abandonné afficherait ses auditeurs à vie.
	later := start.Add(listenerWindow + time.Second)
	s.touchListener("10.0.0.1", later)

	got, _ := s.stats(later)
	if got.Listeners != 1 {
		t.Errorf("Listeners = %d, want 1", got.Listeners)
	}
}

func TestSession_Peak_SurvivesDepartures(t *testing.T) {
	s := &session{}
	start := time.Now()

	s.touchListener("a", start)
	s.touchListener("b", start)
	s.touchListener("c", start)

	// Le pic est celui OBSERVÉ aux instants de lecture : il se fige au moment
	// où l'audience est mesurée, pas à l'insertion — sans quoi chaque requête
	// de manifeste devrait balayer toute la map (cf. touchListener).
	if got, _ := s.stats(start); got.Peak != 3 {
		t.Fatalf("Peak à la mesure = %d, want 3", got.Peak)
	}

	// Tout le monde part : le compte courant retombe, le pic reste.
	later := start.Add(listenerWindow + time.Second)
	got, _ := s.stats(later)

	if got.Listeners != 0 {
		t.Errorf("Listeners = %d, want 0", got.Listeners)
	}
	if got.Peak != 3 {
		t.Errorf("Peak = %d, want 3", got.Peak)
	}
}

func TestSession_TouchListener_DoesNotScanOnHotPath(t *testing.T) {
	// Le chemin chaud HLS ne doit pas purger : la purge est un balayage complet
	// sous le mutex de session, et toutes les requêtes de playlist d'un flux
	// s'y sérialiseraient. Vérifié par l'observable : une entrée expirée reste
	// présente tant que personne n'a lu les stats.
	s := &session{}
	start := time.Now()
	s.touchListener("parti", start)

	later := start.Add(listenerWindow + time.Second)
	s.touchListener("nouveau", later)

	if _, still := s.listeners["parti"]; !still {
		t.Error("touchListener a purgé sur le chemin chaud")
	}
	// La lecture, elle, purge.
	if got, _ := s.stats(later); got.Listeners != 1 {
		t.Errorf("après stats: Listeners = %d, want 1", got.Listeners)
	}
}

func TestSession_CapPurgesExpiredBeforeRejecting(t *testing.T) {
	// Une map saturée d'entrées EXPIRÉES ne doit pas faire rejeter un auditeur
	// légitime : purger d'abord libère les créneaux morts.
	s := &session{listeners: make(map[string]time.Time)}
	start := time.Now()
	for i := 0; i < maxTrackedListeners; i++ {
		s.listeners[fmt.Sprintf("vieux-%d", i)] = start
	}

	later := start.Add(listenerWindow + time.Second)
	s.touchListener("legitime", later)

	if _, ok := s.listeners["legitime"]; !ok {
		t.Error("auditeur légitime rejeté alors que la map était pleine d'expirés")
	}
}

func TestSession_CapStillSaturatesWhenGenuinelyFull(t *testing.T) {
	// Plafond atteint par des clients TOUS actifs : là, on sature pour de bon.
	s := &session{listeners: make(map[string]time.Time)}
	now := time.Now()
	for i := 0; i < maxTrackedListeners; i++ {
		s.listeners[fmt.Sprintf("actif-%d", i)] = now
	}

	s.touchListener("de-trop", now)

	if _, ok := s.listeners["de-trop"]; ok {
		t.Error("le plafond doit tenir quand tous les clients suivis sont actifs")
	}
	if got := len(s.listeners); got > maxTrackedListeners {
		t.Errorf("len = %d, dépasse le plafond %d", got, maxTrackedListeners)
	}
}

func TestSession_Listeners_Capped(t *testing.T) {
	s := &session{}
	now := time.Now()

	for i := 0; i < maxTrackedListeners+50; i++ {
		s.touchListener(fmt.Sprintf("client-%d", i), now)
	}

	if snapshot, _ := s.stats(now); snapshot.Listeners > maxTrackedListeners {
		t.Errorf("Listeners = %d, dépasse le plafond %d", snapshot.Listeners, maxTrackedListeners)
	}
}

func TestSession_Listeners_CapDoesNotFreezeKnownClients(t *testing.T) {
	s := &session{listeners: make(map[string]time.Time)}
	start := time.Now()

	// Saturer la map de clients ACTIFS, puis rafraîchir l'un d'eux : son
	// horodatage doit être mis à jour malgré le plafond, sinon il expirerait
	// à tort alors qu'il écoute toujours.
	for i := 0; i < maxTrackedListeners; i++ {
		s.listeners[fmt.Sprintf("x-%d", i)] = start
	}
	const known = "x-0"

	later := start.Add(10 * time.Second)
	s.touchListener(known, later)

	if got := s.listeners[known]; !got.Equal(later) {
		t.Errorf("client connu non rafraîchi : %v, want %v", got, later)
	}
}

func TestLiveSessions_Stats_NoSession(t *testing.T) {
	ls := NewLiveSessions(t.Context())

	if _, ok := ls.Stats("inconnu"); ok {
		t.Error("un flux sans session ne doit pas rapporter de stats")
	}
}

func TestLiveSessions_TouchListener_UnknownStreamIsNoop(t *testing.T) {
	ls := NewLiveSessions(t.Context())

	// Ne doit pas paniquer ni créer d'entrée fantôme.
	ls.TouchListener("inconnu", "10.0.0.1")

	if _, ok := ls.Stats("inconnu"); ok {
		t.Error("TouchListener ne doit pas créer de session")
	}
}

func TestBroadcastDuration(t *testing.T) {
	start := time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)
	end := start.Add(90 * time.Second)
	now := start.Add(5 * time.Minute)

	tests := []struct {
		name   string
		stream Stream
		want   int64
	}{
		{
			name:   "jamais démarré",
			stream: Stream{Status: StatusIdle},
			want:   0,
		},
		{
			name:   "en direct : compté jusqu'à maintenant",
			stream: Stream{Status: StatusLive, StartedAt: &start},
			want:   300,
		},
		{
			name:   "terminé : compté jusqu'à ended_at",
			stream: Stream{Status: StatusEnded, StartedAt: &start, EndedAt: &end},
			want:   90,
		},
		{
			name: "horloge en avance : borné à zéro",
			stream: Stream{
				Status:    StatusLive,
				StartedAt: func() *time.Time { t := now.Add(time.Minute); return &t }(),
			},
			want: 0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := broadcastDuration(tt.stream, now); got != tt.want {
				t.Errorf("broadcastDuration = %d, want %d", got, tt.want)
			}
		})
	}
}
