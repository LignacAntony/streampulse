package streaming

import (
	"context"
	"fmt"
	"testing"
	"time"
)

// waitDrained vérifie de façon déterministe que toutes les goroutines de session
// se sont terminées : LiveSessions.Wait ne débloque que lorsque le WaitGroup est
// à zéro (une fuite ferait expirer le timeout). Contrairement à
// runtime.NumGoroutine, cette approche n'est pas polluée par les goroutines des
// autres tests du binaire.
func waitDrained(t *testing.T, ls *LiveSessions) {
	t.Helper()
	done := make(chan struct{})
	go func() { ls.Wait(); close(done) }()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("goroutines de session non libérées (fuite)")
	}
}

// TestLiveSessions_NoGoroutineLeak_OnStop vérifie qu'un Stop libère la goroutine
// de session (STR-86).
func TestLiveSessions_NoGoroutineLeak_OnStop(t *testing.T) {
	ls := newTestSessions(context.Background())
	const n = 20
	for i := 0; i < n; i++ {
		ls.Start(fmt.Sprintf("s%d", i), "")
	}
	for i := 0; i < n; i++ {
		ls.Stop(fmt.Sprintf("s%d", i))
	}
	waitDrained(t, ls)
}

// TestLiveSessions_NoGoroutineLeak_OnStopAll vérifie que StopAll (arrêt serveur)
// libère toutes les goroutines de session.
func TestLiveSessions_NoGoroutineLeak_OnStopAll(t *testing.T) {
	ls := newTestSessions(context.Background())
	const n = 20
	for i := 0; i < n; i++ {
		ls.Start(fmt.Sprintf("s%d", i), "")
	}
	ls.StopAll()
	waitDrained(t, ls)
}

// TestLiveSessions_NoGoroutineLeak_OnContextCancel vérifie que l'annulation du
// context de base (shutdown serveur) termine les goroutines de session (STR-84).
func TestLiveSessions_NoGoroutineLeak_OnContextCancel(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	ls := newTestSessions(ctx)
	for i := 0; i < 20; i++ {
		ls.Start(fmt.Sprintf("s%d", i), "")
	}
	cancel() // annule le context de base -> toutes les goroutines run() retournent
	waitDrained(t, ls)
}
