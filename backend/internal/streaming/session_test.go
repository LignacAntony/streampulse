package streaming

import (
	"context"
	"testing"
)

func TestLiveSessions_StartRegisters_StopRemoves(t *testing.T) {
	ls := NewLiveSessions(context.Background())

	if ls.IsLive("s1") {
		t.Fatal("aucune session ne devrait être active au départ")
	}
	ls.Start("s1")
	if !ls.IsLive("s1") {
		t.Fatal("s1 devrait être live après Start")
	}
	ls.Stop("s1")
	if ls.IsLive("s1") {
		t.Fatal("s1 ne devrait plus être live après Stop")
	}
}

func TestLiveSessions_StartIdempotent(t *testing.T) {
	ls := NewLiveSessions(context.Background())
	ls.Start("s1")
	ls.Start("s1") // ne doit pas créer de doublon ni paniquer
	if !ls.IsLive("s1") {
		t.Fatal("s1 devrait être live")
	}
	ls.Stop("s1")
}

func TestLiveSessions_SubscribeReceivesEnded(t *testing.T) {
	ls := NewLiveSessions(context.Background())
	ls.Start("s1")

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
	ls := NewLiveSessions(context.Background())
	ch, unsub := ls.Subscribe("inconnu")
	if ch != nil || unsub != nil {
		t.Fatal("Subscribe sur un flux non live devrait retourner (nil, nil)")
	}
}

func TestLiveSessions_StopAll(t *testing.T) {
	ls := NewLiveSessions(context.Background())
	ls.Start("s1")
	ls.Start("s2")

	ls.StopAll()

	if ls.IsLive("s1") || ls.IsLive("s2") {
		t.Fatal("aucune session ne devrait rester après StopAll")
	}
}
