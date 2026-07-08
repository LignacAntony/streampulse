package streaming

import (
	"context"
	"fmt"
	"runtime"
	"testing"
)

// TestLiveSessions_NoGoroutineLeak_OnStop vérifie qu'un Stop libère la goroutine
// de session (STR-86). LiveSessions.Wait rend l'assertion déterministe (pas de
// poll) : il attend la fin réelle des goroutines avant de compter.
func TestLiveSessions_NoGoroutineLeak_OnStop(t *testing.T) {
	before := runtime.NumGoroutine()

	ls := NewLiveSessions(context.Background())
	const n = 20
	for i := 0; i < n; i++ {
		ls.Start(fmt.Sprintf("s%d", i))
	}
	for i := 0; i < n; i++ {
		ls.Stop(fmt.Sprintf("s%d", i))
	}

	ls.Wait()
	if after := runtime.NumGoroutine(); after > before {
		t.Fatalf("fuite de goroutines : avant=%d, après=%d", before, after)
	}
}

// TestLiveSessions_NoGoroutineLeak_OnStopAll vérifie que StopAll (arrêt serveur)
// libère toutes les goroutines de session.
func TestLiveSessions_NoGoroutineLeak_OnStopAll(t *testing.T) {
	before := runtime.NumGoroutine()

	ls := NewLiveSessions(context.Background())
	const n = 20
	for i := 0; i < n; i++ {
		ls.Start(fmt.Sprintf("s%d", i))
	}
	ls.StopAll()

	ls.Wait()
	if after := runtime.NumGoroutine(); after > before {
		t.Fatalf("fuite de goroutines après StopAll : avant=%d, après=%d", before, after)
	}
}

// TestLiveSessions_NoGoroutineLeak_OnContextCancel vérifie que l'annulation du
// context de base (shutdown serveur) termine les goroutines de session (STR-84).
func TestLiveSessions_NoGoroutineLeak_OnContextCancel(t *testing.T) {
	before := runtime.NumGoroutine()

	ctx, cancel := context.WithCancel(context.Background())
	ls := NewLiveSessions(ctx)
	for i := 0; i < 20; i++ {
		ls.Start(fmt.Sprintf("s%d", i))
	}
	cancel() // annule le context de base -> toutes les goroutines run() retournent

	ls.Wait()
	if after := runtime.NumGoroutine(); after > before {
		t.Fatalf("fuite de goroutines après annulation du context : avant=%d, après=%d", before, after)
	}
}
