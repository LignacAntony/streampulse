package streaming

import (
	"context"
	"fmt"
	"runtime"
	"testing"
	"time"
)

// waitGoroutines attend que le nombre de goroutines redescende à target (ou en
// dessous), le temps que les goroutines annulées se terminent.
func waitGoroutines(target int, timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if runtime.NumGoroutine() <= target {
			return true
		}
		runtime.Gosched()
		time.Sleep(5 * time.Millisecond)
	}
	return runtime.NumGoroutine() <= target
}

// TestLiveSessions_NoGoroutineLeak_OnStop vérifie qu'un Stop libère la goroutine
// de session (STR-86) : aucune fuite après start puis stop de N sessions.
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

	if !waitGoroutines(before, 2*time.Second) {
		t.Fatalf("fuite de goroutines : avant=%d, après=%d", before, runtime.NumGoroutine())
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

	if !waitGoroutines(before, 2*time.Second) {
		t.Fatalf("fuite de goroutines après StopAll : avant=%d, après=%d", before, runtime.NumGoroutine())
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

	if !waitGoroutines(before, 2*time.Second) {
		t.Fatalf("fuite de goroutines après annulation du context : avant=%d, après=%d", before, runtime.NumGoroutine())
	}
}
