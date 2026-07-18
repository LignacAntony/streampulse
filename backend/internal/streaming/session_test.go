package streaming

import (
	"context"
	"sync"
	"testing"
	"time"
)

// newTestSessions construit un registre dont le segmenteur HLS est désactivé :
// les tests de cycle de vie (SSE, goroutines) n'exercent pas ffmpeg.
func newTestSessions(ctx context.Context) *LiveSessions {
	ls := NewLiveSessions(ctx)
	ls.newSeg = func() (*hlsSegmenter, error) { return nil, nil }
	return ls
}

func TestLiveSessions_StartRegisters_StopRemoves(t *testing.T) {
	ls := newTestSessions(context.Background())

	if ls.IsLive("s1") {
		t.Fatal("aucune session ne devrait être active au départ")
	}
	ls.Start("s1", "")
	if !ls.IsLive("s1") {
		t.Fatal("s1 devrait être live après Start")
	}
	ls.Stop("s1")
	if ls.IsLive("s1") {
		t.Fatal("s1 ne devrait plus être live après Stop")
	}
}

func TestLiveSessions_StartIdempotent(t *testing.T) {
	ls := newTestSessions(context.Background())
	ls.Start("s1", "")
	ls.Start("s1", "") // ne doit pas créer de doublon ni paniquer
	if !ls.IsLive("s1") {
		t.Fatal("s1 devrait être live")
	}
	ls.Stop("s1")
}

func TestLiveSessions_SubscribeReceivesEnded(t *testing.T) {
	ls := newTestSessions(context.Background())
	ls.Start("s1", "")

	ch, unsub := ls.Subscribe("s1")
	if ch == nil {
		t.Fatal("Subscribe sur un flux live devrait retourner un canal")
	}
	defer unsub()

	ls.Stop("s1")

	ev, ok := <-ch
	if !ok || ev.Type != "ended" {
		t.Fatalf("attendu event ended, obtenu (%+v, ok=%v)", ev, ok)
	}
	if _, ok := <-ch; ok {
		t.Fatal("le canal devrait être fermé après Stop")
	}
}

func TestLiveSessions_SubscribeNoSession(t *testing.T) {
	ls := newTestSessions(context.Background())
	ch, unsub := ls.Subscribe("inconnu")
	if ch != nil || unsub != nil {
		t.Fatal("Subscribe sur un flux non live devrait retourner (nil, nil)")
	}
}

func TestLiveSessions_StopAll(t *testing.T) {
	ls := newTestSessions(context.Background())
	ls.Start("s1", "")
	ls.Start("s2", "")

	ls.StopAll()

	if ls.IsLive("s1") || ls.IsLive("s2") {
		t.Fatal("aucune session ne devrait rester après StopAll")
	}
}

func TestLiveSessions_SlowSubscriberStillCloses(t *testing.T) {
	ls := newTestSessions(context.Background())
	ls.Start("s1", "")

	ch, unsub := ls.Subscribe("s1")
	if ch == nil {
		t.Fatal("Subscribe sur un flux live devrait retourner un canal")
	}
	defer unsub()

	ls.Stop("s1") // ne lit pas l'event avant : simule un consommateur lent

	// Le canal doit finir fermé (fin de flux garantie) même sans lecture de l'event.
	deadline := time.After(2 * time.Second)
	for {
		select {
		case _, ok := <-ch:
			if !ok {
				return // canal fermé : contrat respecté
			}
		case <-deadline:
			t.Fatal("le canal de l'abonné n'a jamais été fermé après Stop")
		}
	}
}

func TestLiveSessions_SubscribeAfterStop(t *testing.T) {
	ls := newTestSessions(context.Background())
	ls.Start("s1", "")
	ls.Stop("s1")

	ch, unsub := ls.Subscribe("s1")
	if ch != nil || unsub != nil {
		t.Fatal("Subscribe après Stop devrait retourner (nil, nil)")
	}
}

// TestLiveSessions_SubscribeStopRace exerce Subscribe et Stop en parallèle : sous
// `-race`, garantit l'absence de course sur l'état de la session (flag closed +
// abonnés) et qu'aucun abonné tardif ne reste ouvert sans être fermé.
func TestLiveSessions_SubscribeStopRace(t *testing.T) {
	for iter := 0; iter < 100; iter++ {
		ls := newTestSessions(context.Background())
		ls.Start("s1", "")

		var wg sync.WaitGroup
		wg.Add(2)
		go func() {
			defer wg.Done()
			ch, unsub := ls.Subscribe("s1")
			if ch == nil {
				return // session déjà arrêtée : acceptable
			}
			defer unsub()
			// Si on a un canal, il doit finir fermé (jamais bloquer indéfiniment).
			select {
			case <-ch:
			case <-time.After(time.Second):
				t.Errorf("abonné jamais notifié/fermé (fuite)")
			}
		}()
		go func() {
			defer wg.Done()
			ls.Stop("s1")
		}()
		wg.Wait()
	}
}
