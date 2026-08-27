package chat

import (
	"sync"
)

const clientSendBuf = 32

// ChatHub gère les salons de chat in-memory, un par flux en direct.
type ChatHub struct {
	mu    sync.Mutex
	rooms map[string]*room
}

// NewChatHub construit le registre de salons.
func NewChatHub() *ChatHub {
	return &ChatHub{rooms: make(map[string]*room)}
}

// Room retourne le salon pour un flux, le créant si absent.
func (h *ChatHub) Room(streamID string) *room {
	h.mu.Lock()
	defer h.mu.Unlock()
	r, ok := h.rooms[streamID]
	if !ok {
		r = &room{clients: make(map[*client]struct{})}
		h.rooms[streamID] = r
	}
	return r
}

// CloseRoom ferme un salon et déconnecte tous les clients.
func (h *ChatHub) CloseRoom(streamID string) {
	h.mu.Lock()
	r, ok := h.rooms[streamID]
	if ok {
		delete(h.rooms, streamID)
	}
	h.mu.Unlock()

	if ok {
		r.closeAll()
	}
}

// DisconnectUserFromAll déconnecte un utilisateur de tous les salons actifs.
func (h *ChatHub) DisconnectUserFromAll(userID string) {
	h.mu.Lock()
	rooms := make([]*room, 0, len(h.rooms))
	for _, r := range h.rooms {
		rooms = append(rooms, r)
	}
	h.mu.Unlock()

	for _, r := range rooms {
		r.DisconnectUser(userID)
	}
}

// CloseAll ferme tous les salons (shutdown propre).
func (h *ChatHub) CloseAll() {
	h.mu.Lock()
	rooms := make(map[string]*room, len(h.rooms))
	for k, v := range h.rooms {
		rooms[k] = v
	}
	h.rooms = make(map[string]*room)
	h.mu.Unlock()

	for _, r := range rooms {
		r.closeAll()
	}
}

// room est un salon de chat pour un flux.
type room struct {
	mu      sync.Mutex
	clients map[*client]struct{}
}

// client représente une connexion WebSocket d'un utilisateur.
type client struct {
	userID   string
	username string
	send     chan []byte
	done     chan struct{}
	once     sync.Once
}

// Join ajoute un client au salon.
func (r *room) Join(c *client) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.clients[c] = struct{}{}
}

// Leave retire un client du salon et ferme son canal.
func (r *room) Leave(c *client) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if _, ok := r.clients[c]; ok {
		delete(r.clients, c)
		c.close()
	}
}

// Broadcast envoie un message à tous les clients du salon (non-bloquant :
// un client lent est ignoré plutôt que de bloquer les autres).
func (r *room) Broadcast(msg []byte) {
	r.mu.Lock()
	defer r.mu.Unlock()
	for c := range r.clients {
		select {
		case c.send <- msg:
		default:
		}
	}
}

// DisconnectUser ferme la connexion d'un utilisateur spécifique (ban).
func (r *room) DisconnectUser(userID string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	for c := range r.clients {
		if c.userID == userID {
			delete(r.clients, c)
			c.close()
		}
	}
}

func (r *room) closeAll() {
	r.mu.Lock()
	defer r.mu.Unlock()
	for c := range r.clients {
		c.close()
	}
	r.clients = make(map[*client]struct{})
}

func (c *client) close() {
	c.once.Do(func() { close(c.done) })
}

func newClient(userID, username string) *client {
	return &client{
		userID:   userID,
		username: username,
		send:     make(chan []byte, clientSendBuf),
		done:     make(chan struct{}),
	}
}
