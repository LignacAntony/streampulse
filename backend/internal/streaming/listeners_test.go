package streaming

import (
	"testing"
	"time"
)

func TestSession_TouchListener_CountsDistinctClients(t *testing.T) {
	s := &session{}
	now := time.Now()

	s.touchListener("10.0.0.1", now)
	s.touchListener("10.0.0.2", now)
	s.touchListener("10.0.0.1", now) // même client : ne compte pas deux fois

	got := s.stats(now)
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

	got := s.stats(later)
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

	// Tout le monde part : le compte courant retombe, le pic reste.
	later := start.Add(listenerWindow + time.Second)
	got := s.stats(later)

	if got.Listeners != 0 {
		t.Errorf("Listeners = %d, want 0", got.Listeners)
	}
	if got.Peak != 3 {
		t.Errorf("Peak = %d, want 3", got.Peak)
	}
}

func TestSession_Listeners_Capped(t *testing.T) {
	s := &session{}
	now := time.Now()

	for i := 0; i < maxTrackedListeners+50; i++ {
		s.touchListener(string(rune(i))+"-client", now)
	}

	if got := s.stats(now).Listeners; got > maxTrackedListeners {
		t.Errorf("Listeners = %d, dépasse le plafond %d", got, maxTrackedListeners)
	}
}

func TestSession_Listeners_CapDoesNotFreezeKnownClients(t *testing.T) {
	s := &session{}
	start := time.Now()
	s.listeners = make(map[string]time.Time)

	// Saturer la map, puis rafraîchir un client déjà suivi : son horodatage
	// doit être mis à jour malgré le plafond, sinon il expirerait à tort.
	for i := 0; i < maxTrackedListeners; i++ {
		s.listeners[string(rune(i))+"-x"] = start
	}
	known := string(rune(0)) + "-x"

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
