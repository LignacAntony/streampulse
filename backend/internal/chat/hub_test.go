package chat

import (
	"testing"
	"time"
)

func TestRoom_JoinLeave(t *testing.T) {
	hub := NewChatHub()
	rm := hub.Room("stream-1")

	c1 := newClient("u1", "alice")
	c2 := newClient("u2", "bob")
	rm.Join(c1)
	rm.Join(c2)

	rm.mu.Lock()
	n := len(rm.clients)
	rm.mu.Unlock()
	if n != 2 {
		t.Fatalf("room has %d clients, want 2", n)
	}

	rm.Leave(c1)
	rm.mu.Lock()
	n = len(rm.clients)
	rm.mu.Unlock()
	if n != 1 {
		t.Fatalf("room has %d clients after leave, want 1", n)
	}
}

func TestRoom_Broadcast(t *testing.T) {
	hub := NewChatHub()
	rm := hub.Room("stream-1")

	c1 := newClient("u1", "alice")
	c2 := newClient("u2", "bob")
	rm.Join(c1)
	rm.Join(c2)

	rm.Broadcast([]byte(`{"type":"message","content":"hello"}`))

	select {
	case msg := <-c1.send:
		if string(msg) != `{"type":"message","content":"hello"}` {
			t.Errorf("c1 got %q", msg)
		}
	case <-time.After(100 * time.Millisecond):
		t.Error("c1 did not receive broadcast")
	}

	select {
	case msg := <-c2.send:
		if string(msg) != `{"type":"message","content":"hello"}` {
			t.Errorf("c2 got %q", msg)
		}
	case <-time.After(100 * time.Millisecond):
		t.Error("c2 did not receive broadcast")
	}
}

func TestRoom_DisconnectUser(t *testing.T) {
	hub := NewChatHub()
	rm := hub.Room("stream-1")

	c1 := newClient("u1", "alice")
	c2 := newClient("u1", "alice-phone")
	c3 := newClient("u2", "bob")
	rm.Join(c1)
	rm.Join(c2)
	rm.Join(c3)

	rm.DisconnectUser("u1")

	rm.mu.Lock()
	n := len(rm.clients)
	rm.mu.Unlock()
	if n != 1 {
		t.Fatalf("room has %d clients after disconnect, want 1", n)
	}

	select {
	case <-c1.done:
	default:
		t.Error("c1 done channel not closed")
	}
	select {
	case <-c2.done:
	default:
		t.Error("c2 done channel not closed")
	}
}

func TestHub_CloseRoom(t *testing.T) {
	hub := NewChatHub()
	rm := hub.Room("stream-1")
	c := newClient("u1", "alice")
	rm.Join(c)

	hub.CloseRoom("stream-1")

	select {
	case <-c.done:
	default:
		t.Error("client done not closed after CloseRoom")
	}

	hub.mu.Lock()
	_, exists := hub.rooms["stream-1"]
	hub.mu.Unlock()
	if exists {
		t.Error("room still exists after CloseRoom")
	}
}

func TestHub_CloseAll(t *testing.T) {
	hub := NewChatHub()
	rm1 := hub.Room("s1")
	rm2 := hub.Room("s2")
	c1 := newClient("u1", "a")
	c2 := newClient("u2", "b")
	rm1.Join(c1)
	rm2.Join(c2)

	hub.CloseAll()

	select {
	case <-c1.done:
	default:
		t.Error("c1 not closed after CloseAll")
	}
	select {
	case <-c2.done:
	default:
		t.Error("c2 not closed after CloseAll")
	}

	hub.mu.Lock()
	n := len(hub.rooms)
	hub.mu.Unlock()
	if n != 0 {
		t.Errorf("hub has %d rooms after CloseAll, want 0", n)
	}
}

func TestHub_DisconnectUserFromAll(t *testing.T) {
	hub := NewChatHub()
	rm1 := hub.Room("s1")
	rm2 := hub.Room("s2")
	c1 := newClient("u1", "alice")
	c2 := newClient("u1", "alice2")
	c3 := newClient("u2", "bob")
	rm1.Join(c1)
	rm2.Join(c2)
	rm2.Join(c3)

	hub.DisconnectUserFromAll("u1")

	select {
	case <-c1.done:
	default:
		t.Error("c1 not disconnected from room s1")
	}
	select {
	case <-c2.done:
	default:
		t.Error("c2 not disconnected from room s2")
	}

	rm2.mu.Lock()
	n := len(rm2.clients)
	rm2.mu.Unlock()
	if n != 1 {
		t.Errorf("room s2 has %d clients, want 1 (bob)", n)
	}
}

func TestHub_CloseRoom_NonExistent(t *testing.T) {
	hub := NewChatHub()
	hub.CloseRoom("nonexistent")

	hub.mu.Lock()
	n := len(hub.rooms)
	hub.mu.Unlock()
	if n != 0 {
		t.Errorf("hub has %d rooms, want 0", n)
	}
}

func TestRoom_LeaveNonMember(t *testing.T) {
	hub := NewChatHub()
	rm := hub.Room("s1")
	c := newClient("u1", "alice")

	rm.Leave(c)

	rm.mu.Lock()
	n := len(rm.clients)
	rm.mu.Unlock()
	if n != 0 {
		t.Errorf("room has %d clients, want 0", n)
	}
}

func TestRoom_BroadcastFullBuffer(t *testing.T) {
	hub := NewChatHub()
	rm := hub.Room("s1")
	c := newClient("u1", "alice")
	rm.Join(c)

	for i := 0; i < clientSendBuf+5; i++ {
		rm.Broadcast([]byte(`{"type":"message"}`))
	}

	rm.mu.Lock()
	n := len(rm.clients)
	rm.mu.Unlock()
	if n != 1 {
		t.Error("client should not be evicted on full buffer")
	}
}

func TestClient_CloseIdempotent(t *testing.T) {
	c := newClient("u1", "alice")
	c.close()
	c.close()

	select {
	case <-c.done:
	default:
		t.Error("done channel should be closed")
	}
}

func TestHub_RoomReuse(t *testing.T) {
	hub := NewChatHub()
	rm1 := hub.Room("s1")
	rm2 := hub.Room("s1")

	if rm1 != rm2 {
		t.Error("Room should return the same room for the same streamID")
	}
}
