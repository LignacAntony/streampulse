package streaming

import (
	"context"
	"errors"
	"fmt"
	"io"
	"mime"
	"net"
	"net/http"

	"os"
	"strconv"
	"strings"
	"time"

	"github.com/rs/zerolog"

	"github.com/LignacAntony/streampulse/internal/auth"
	"github.com/LignacAntony/streampulse/internal/shared/apperror"
	"github.com/LignacAntony/streampulse/internal/shared/httpjson"
)

const maxCreateStreamBodyBytes = 1 << 20 // 1 MiB

// sseKeepAliveInterval : commentaire SSE périodique pour garder les connexions
// idle vivantes à travers proxies/LB (doit rester < aux timeouts idle amont).
const sseKeepAliveInterval = 15 * time.Second

// sseWriteTimeout borne chaque écriture SSE : un lecteur lent/half-open ne doit
// pas pouvoir bloquer indéfiniment le Write (fuite de goroutine/connexion).
const sseWriteTimeout = 10 * time.Second

type ingestDeadlineReader struct {
	body       io.Reader
	controller *http.ResponseController
	timeout    time.Duration
}

// Read renouvelle la deadline avant chaque attente d'octets. Une connexion TCP
// half-open ne peut ainsi pas réserver indéfiniment l'unique slot d'ingest.
func (r ingestDeadlineReader) Read(p []byte) (int, error) {
	if r.timeout > 0 {
		_ = r.controller.SetReadDeadline(time.Now().Add(r.timeout))
	}
	return r.body.Read(p)
}

// StreamService est l'interface requise par le handler (ISP) : *Service la satisfait.
type StreamService interface {
	CreateStream(ctx context.Context, in CreateStreamInput) (Stream, error)
	ListPublicLive(ctx context.Context, limit, offset int32) ([]Stream, error)
	GetStream(ctx context.Context, id, requesterID string) (Stream, bool, error)
	UpdateStream(ctx context.Context, id, requesterID string, in UpdateStreamInput) (Stream, error)
	ArchiveStream(ctx context.Context, id, requesterID string) error
	StartStream(ctx context.Context, id, requesterID string) (Stream, error)
	StopStream(ctx context.Context, id, requesterID string) (Stream, error)
	AddFavorite(ctx context.Context, streamID, requesterID string) error
	RemoveFavorite(ctx context.Context, streamID, requesterID string) error
	ListFavorites(ctx context.Context, requesterID string) ([]Stream, error)
	ListMyStreams(ctx context.Context, requesterID string) ([]Stream, error)
}

// StreamSessions expose au handler les opérations sur les sessions live :
// abonnement SSE (STR-85), ingest audio et service des fichiers HLS (STR-70).
// *LiveSessions l'implémente. Le handler utilise l'ensemble de ces méthodes.
type StreamSessions interface {
	Subscribe(streamID string) (<-chan SessionEvent, func())
	AttachIngest(streamKey string) (io.Writer, func(), error)
	Playlist(streamID string) (string, bool)
	Segment(streamID, name string) (string, bool)
	TouchListener(streamID, clientKey string)
	Stats(streamID string) (SessionStats, bool)
}

// clientKey identifie un lecteur HLS pour le comptage d'auditeurs (STR-154).
//
// L'adresse réseau est le seul discriminant disponible : les lecteurs natifs
// (AVPlayer/ExoPlayer) ne portent pas le Bearer, et rien d'autre dans la
// requête n'est stable. Conséquences assumées : deux lecteurs derrière la même
// IP publique comptent pour un, et un client qui change d'adresse compte
// double le temps que sa fenêtre expire.
//
// X-Forwarded-For n'est lu que si `TRUST_PROXY_HEADERS` est activé. L'en-tête
// est falsifiable : sans reverse proxy qui le réécrit, le lire laisserait
// n'importe qui gonfler le compteur d'un flux en variant sa valeur. Sans lui
// en revanche, tous les auditeurs derrière le proxy de production partagent
// l'adresse de ce dernier et le compteur sature à 1 — d'où le drapeau.
func (h *Handler) clientKey(r *http.Request) string {
	if h.trustProxyHeaders {
		// Premier maillon = client d'origine ; les suivants sont les proxies
		// traversés. Caddy réécrit l'en-tête, la valeur est donc fiable ici.
		if fwd := r.Header.Get("X-Forwarded-For"); fwd != "" {
			if first, _, found := strings.Cut(fwd, ","); found {
				return strings.TrimSpace(first)
			}
			return strings.TrimSpace(fwd)
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// Handler expose le domaine streaming en HTTP. ingestBaseURL sert à construire
// l'URL de stream source renvoyée au diffuseur.
type Handler struct {
	svc           StreamService
	ingestBaseURL string
	sessions      StreamSessions
	metrics       MetricsRecorder // jamais nil : noopRecorder par défaut (STR-166)

	// trustProxyHeaders : cf. clientKey. Faux par défaut, activé par
	// SetTrustProxyHeaders au démarrage quand un reverse proxy est devant.
	trustProxyHeaders    bool
	ingestReconnectGrace time.Duration
}

func NewHandler(svc StreamService, ingestBaseURL string, sessions StreamSessions) *Handler {
	return &Handler{
		svc:           svc,
		ingestBaseURL: strings.TrimRight(ingestBaseURL, "/"),
		sessions:      sessions,
		metrics:       noopRecorder{},
	}
}

// SetTrustProxyHeaders autorise la lecture de X-Forwarded-For pour identifier
// les auditeurs (STR-154). Setter plutôt que paramètre de constructeur : même
// motif que SetMetrics — c'est une donnée de déploiement, pas du domaine.
func (h *Handler) SetTrustProxyHeaders(trust bool) { h.trustProxyHeaders = trust }

// SetIngestReconnectGrace configure la deadline glissante d'un push audio.
// Zéro désactive la deadline, notamment dans les tests unitaires du handler.
func (h *Handler) SetIngestReconnectGrace(grace time.Duration) {
	h.ingestReconnectGrace = grace
}

// SetMetrics injecte le collecteur de métriques métier (STR-166, ADR 022).
// Setter plutôt que paramètre de constructeur : l'observabilité est optionnelle
// (le domaine tourne sans), et le pattern est le même que LiveSessions.SetMetrics.
// Appelé une fois au démarrage, avant que le serveur n'accepte des requêtes.
func (h *Handler) SetMetrics(rec MetricsRecorder) {
	if rec == nil {
		rec = noopRecorder{}
	}
	h.metrics = rec
}

// createStreamRequest : pointeurs pour distinguer « champ absent » de zéro.
// title et is_public sont requis ; description et category sont optionnels.
type createStreamRequest struct {
	Title       *string `json:"title"`
	Description *string `json:"description"`
	Category    *string `json:"category"`
	IsPublic    *bool   `json:"is_public"`
}

func (r createStreamRequest) toInput(userID string) (CreateStreamInput, error) {
	if r.Title == nil {
		return CreateStreamInput{}, apperror.InvalidArgument("missing required field: title")
	}
	if r.IsPublic == nil {
		return CreateStreamInput{}, apperror.InvalidArgument("missing required field: is_public")
	}
	return CreateStreamInput{
		UserID:      userID,
		Title:       *r.Title,
		Description: r.Description,
		Category:    r.Category,
		IsPublic:    *r.IsPublic,
	}, nil
}

// streamResponse est la vue détaillée d'un flux. stream_key et stream_source_url
// sont des pointeurs : ils ne sont remplis que pour le propriétaire et valent
// null pour un tiers (un seul schéma, désérialisable côté client, sans fuite).
type streamResponse struct {
	ID              string     `json:"id"`
	UserID          string     `json:"user_id"`
	Title           string     `json:"title"`
	Description     *string    `json:"description"`
	Category        *string    `json:"category"`
	Status          string     `json:"status"`
	IsPublic        bool       `json:"is_public"`
	StreamKey       *string    `json:"stream_key"`
	StreamSourceURL *string    `json:"stream_source_url"`
	StartedAt       *time.Time `json:"started_at"`
	EndedAt         *time.Time `json:"ended_at"`
	CreatedAt       time.Time  `json:"created_at"`
	UpdatedAt       time.Time  `json:"updated_at"`
}

// Create gère POST /api/streams. L'authentification et le rôle broadcaster
// sont garantis en amont par auth.RequireAuth + auth.RequireRole.
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	var req createStreamRequest
	if err := httpjson.Decode(w, r, &req, maxCreateStreamBodyBytes); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	in, err := req.toInput(userID)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	stream, err := h.svc.CreateStream(r.Context(), in)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusCreated, h.toResponse(stream, true)); err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("streaming: encode create")
	}
}

// toResponse construit la vue détaillée d'un flux. includeSecrets n'est vrai que
// pour le propriétaire : sinon stream_key et stream_source_url restent null.
func (h *Handler) toResponse(s Stream, includeSecrets bool) streamResponse {
	resp := streamResponse{
		ID:          s.ID,
		UserID:      s.UserID,
		Title:       s.Title,
		Description: s.Description,
		Category:    s.Category,
		Status:      s.Status,
		IsPublic:    s.IsPublic,
		StartedAt:   s.StartedAt,
		EndedAt:     s.EndedAt,
		CreatedAt:   s.CreatedAt,
		UpdatedAt:   s.UpdatedAt,
	}
	if includeSecrets {
		key := s.StreamKey
		url := h.ingestBaseURL + "/api/streams/ingest/" + s.StreamKey
		resp.StreamKey = &key
		resp.StreamSourceURL = &url
	}
	return resp
}

// streamSummaryResponse est la vue publique d'un flux : aucun secret
// (stream_key, stream_source_url) n'y figure.
type streamSummaryResponse struct {
	ID                  string     `json:"id"`
	UserID              string     `json:"user_id"`
	Title               string     `json:"title"`
	Description         *string    `json:"description"`
	Category            *string    `json:"category"`
	Status              string     `json:"status"`
	IsPublic            bool       `json:"is_public"`
	StartedAt           *time.Time `json:"started_at"`
	CreatedAt           time.Time  `json:"created_at"`
	BroadcasterUsername string     `json:"broadcaster_username"`
}

func toSummary(s Stream) streamSummaryResponse {
	return streamSummaryResponse{
		ID:                  s.ID,
		UserID:              s.UserID,
		Title:               s.Title,
		Description:         s.Description,
		Category:            s.Category,
		Status:              s.Status,
		IsPublic:            s.IsPublic,
		StartedAt:           s.StartedAt,
		CreatedAt:           s.CreatedAt,
		BroadcasterUsername: s.BroadcasterUsername,
	}
}

// List gère GET /api/streams : flux publics en direct, paginés. Auth requise.
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	limit := parseIntDefault(r.URL.Query().Get("limit"), DefaultListLimit)
	if limit < 1 {
		limit = DefaultListLimit
	}
	if limit > MaxListLimit {
		limit = MaxListLimit
	}
	offset := parseIntDefault(r.URL.Query().Get("offset"), 0)
	if offset < 0 {
		offset = 0
	}
	if offset > 1<<31-1 {
		offset = 1<<31 - 1 // borne haute : évite un débordement int32 (OFFSET négatif → 500)
	}

	streams, err := h.svc.ListPublicLive(r.Context(), int32(limit), int32(offset))
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	out := make([]streamSummaryResponse, 0, len(streams))
	for _, s := range streams {
		out = append(out, toSummary(s))
	}
	if err := httpjson.Write(w, http.StatusOK, out); err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("streaming: encode list")
	}
}

func parseIntDefault(raw string, def int) int {
	if raw == "" {
		return def
	}
	n, err := strconv.Atoi(raw)
	if err != nil {
		return def
	}
	return n
}

// toUpdateInput réutilise la forme de createStreamRequest : title et is_public
// sont requis (PUT = remplacement complet), description et category optionnels.
func (r createStreamRequest) toUpdateInput() (UpdateStreamInput, error) {
	if r.Title == nil {
		return UpdateStreamInput{}, apperror.InvalidArgument("missing required field: title")
	}
	if r.IsPublic == nil {
		return UpdateStreamInput{}, apperror.InvalidArgument("missing required field: is_public")
	}
	return UpdateStreamInput{
		Title:       *r.Title,
		Description: r.Description,
		Category:    r.Category,
		IsPublic:    *r.IsPublic,
	}, nil
}

// Get gère GET /api/streams/{id}. Réponse unique (streamResponse) : le
// propriétaire reçoit stream_key + stream_source_url, un tiers les reçoit à null.
func (h *Handler) Get(w http.ResponseWriter, r *http.Request) {
	requesterID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	stream, isOwner, err := h.svc.GetStream(r.Context(), r.PathValue("id"), requesterID)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusOK, h.toResponse(stream, isOwner)); err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("streaming: encode get")
	}
}

// Update gère PUT /api/streams/{id} : remplacement complet, propriétaire uniquement.
func (h *Handler) Update(w http.ResponseWriter, r *http.Request) {
	requesterID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	var req createStreamRequest
	if err := httpjson.Decode(w, r, &req, maxCreateStreamBodyBytes); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	in, err := req.toUpdateInput()
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	stream, err := h.svc.UpdateStream(r.Context(), r.PathValue("id"), requesterID, in)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusOK, h.toResponse(stream, true)); err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("streaming: encode update")
	}
}

// Delete gère DELETE /api/streams/{id} : soft delete, propriétaire uniquement.
func (h *Handler) Delete(w http.ResponseWriter, r *http.Request) {
	requesterID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	if err := h.svc.ArchiveStream(r.Context(), r.PathValue("id"), requesterID); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// Start gère PATCH /api/streams/{id}/start : passe le flux du diffuseur en direct.
func (h *Handler) Start(w http.ResponseWriter, r *http.Request) {
	requesterID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	stream, err := h.svc.StartStream(r.Context(), r.PathValue("id"), requesterID)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusOK, h.toResponse(stream, true)); err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("streaming: encode start")
	}
}

// Stop gère PATCH /api/streams/{id}/stop : termine le flux du diffuseur.
func (h *Handler) Stop(w http.ResponseWriter, r *http.Request) {
	requesterID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	stream, err := h.svc.StopStream(r.Context(), r.PathValue("id"), requesterID)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusOK, h.toResponse(stream, true)); err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("streaming: encode stop")
	}
}

// AddFavorite gère POST /api/streams/{id}/favorite : ajoute le flux aux favoris
// du demandeur (US-04-05). Idempotent → 204. Un flux non visible renvoie 404.
func (h *Handler) AddFavorite(w http.ResponseWriter, r *http.Request) {
	requesterID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}
	if err := h.svc.AddFavorite(r.Context(), r.PathValue("id"), requesterID); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// RemoveFavorite gère DELETE /api/streams/{id}/favorite : retire le flux des
// favoris du demandeur. Idempotent → 204.
func (h *Handler) RemoveFavorite(w http.ResponseWriter, r *http.Request) {
	requesterID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}
	if err := h.svc.RemoveFavorite(r.Context(), r.PathValue("id"), requesterID); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ListFavorites gère GET /api/users/me/favorites : liste des flux favoris du
// demandeur (vue publique sans secret), triée par date d'ajout décroissante.
func (h *Handler) ListFavorites(w http.ResponseWriter, r *http.Request) {
	requesterID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}
	streams, err := h.svc.ListFavorites(r.Context(), requesterID)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}
	out := make([]streamSummaryResponse, 0, len(streams))
	for _, s := range streams {
		out = append(out, toSummary(s))
	}
	if err := httpjson.Write(w, http.StatusOK, out); err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("streaming: encode favorites")
	}
}

// ListMine gère GET /api/users/me/streams : les flux du diffuseur connecté,
// tous statuts, pour son tableau de bord (STR-153).
//
// Seule route de liste qui renvoie `stream_key` et `stream_source_url` : la
// requête filtre sur l'identité du porteur du JWT, il n'existe donc aucun
// chemin par lequel un tiers recevrait le secret d'un autre. Un utilisateur
// sans flux — ou sans le rôle diffuseur — reçoit `[]`, pas un 403.
func (h *Handler) ListMine(w http.ResponseWriter, r *http.Request) {
	requesterID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}
	streams, err := h.svc.ListMyStreams(r.Context(), requesterID)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}
	out := make([]streamResponse, 0, len(streams))
	for _, s := range streams {
		out = append(out, h.toResponse(s, true))
	}
	if err := httpjson.Write(w, http.StatusOK, out); err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("streaming: encode my streams")
	}
}

// streamStatsResponse est l'instantané d'audience d'un flux (STR-154).
//
// `listeners` et `peak_listeners` sont des **estimations** issues d'un suivi en
// mémoire des requêtes de manifeste (cf. listeners.go) : elles repartent de
// zéro au redémarrage du process et ne survivent pas à l'arrêt du flux.
type streamStatsResponse struct {
	StreamID        string     `json:"stream_id"`
	Status          string     `json:"status"`
	Listeners       int        `json:"listeners"`
	PeakListeners   int        `json:"peak_listeners"`
	StartedAt       *time.Time `json:"started_at"`
	DurationSeconds int64      `json:"duration_seconds"`
}

// Stats gère GET /api/streams/{id}/stats : audience et durée d'un flux, pour
// son tableau de bord (STR-154). Propriétaire uniquement — 404 sinon, comme
// partout ailleurs, pour ne pas divulguer l'existence du flux.
//
// Un flux qui n'est pas en direct répond 200 avec des compteurs à zéro plutôt
// qu'une erreur : le client poll pendant toute la vie de l'écran et n'a pas à
// distinguer « pas encore démarré » de « échec ».
func (h *Handler) Stats(w http.ResponseWriter, r *http.Request) {
	requesterID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}
	id := r.PathValue("id")

	stream, isOwner, err := h.svc.GetStream(r.Context(), id, requesterID)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}
	if !isOwner {
		httpjson.WriteError(w, r, apperror.NotFound("stream not found"))
		return
	}

	// Absence de session = flux pas en direct : compteurs à zéro.
	stats, _ := h.sessions.Stats(id)

	if err := httpjson.Write(w, http.StatusOK, streamStatsResponse{
		StreamID:        stream.ID,
		Status:          stream.Status,
		Listeners:       stats.Listeners,
		PeakListeners:   stats.Peak,
		StartedAt:       stream.StartedAt,
		DurationSeconds: broadcastDuration(stream, time.Now()),
	}); err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("streaming: encode stats")
	}
}

// broadcastDuration retourne la durée de diffusion en secondes : depuis
// started_at jusqu'à maintenant si le flux est en direct, jusqu'à ended_at
// sinon. Zéro si le flux n'a jamais démarré, ou si l'horloge donne un écart
// négatif (started_at dans le futur).
func broadcastDuration(s Stream, now time.Time) int64 {
	if s.StartedAt == nil {
		return 0
	}
	if s.Status != StatusLive {
		// Diffusion terminée sans `ended_at` : la borne manque. Compter jusqu'à
		// maintenant ferait croître indéfiniment la durée d'un flux pourtant
		// arrêté, à chaque poll. `ArchiveStream` pose justement `status='ended'`
		// sans renseigner `ended_at` — inatteignable ici aujourd'hui (les flux
		// archivés sont exclus par GetStreamByID), mais on ne s'appuie pas
		// là-dessus.
		if s.EndedAt == nil {
			return 0
		}
		return durationBetween(*s.StartedAt, *s.EndedAt)
	}
	return durationBetween(*s.StartedAt, now)
}

// durationBetween retourne l'écart en secondes, borné à zéro : une horloge en
// avance (started_at dans le futur) ne doit pas produire de durée négative.
func durationBetween(from, to time.Time) int64 {
	elapsed := to.Sub(from)
	if elapsed < 0 {
		return 0
	}
	return int64(elapsed.Seconds())
}

// Events gère GET /api/streams/{id}/events : flux SSE d'événements du direct.
// L'abonné reçoit un event "ended" quand le diffuseur arrête le flux.
func (h *Handler) Events(w http.ResponseWriter, r *http.Request) {
	requesterID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}
	id := r.PathValue("id")

	// Réutilise la visibilité de GetStream (404 si absent ou privé non-propriétaire).
	if _, _, err := h.svc.GetStream(r.Context(), id, requesterID); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	ch, unsub := h.sessions.Subscribe(id)
	if ch == nil {
		httpjson.WriteError(w, r, apperror.Conflict("stream is not live"))
		return
	}
	defer unsub()

	flusher, ok := w.(http.Flusher)
	if !ok {
		httpjson.WriteError(w, r, apperror.Internal("streaming unsupported", nil))
		return
	}
	rc := http.NewResponseController(w)

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.WriteHeader(http.StatusOK)
	_ = rc.SetWriteDeadline(time.Now().Add(sseWriteTimeout))
	flusher.Flush()

	ticker := time.NewTicker(sseKeepAliveInterval)
	defer ticker.Stop()

	// write borne chaque écriture par une deadline puis flush ; retourne false si
	// l'écriture échoue (client déconnecté ou lecteur bloqué au-delà du délai).
	write := func(payload string) bool {
		_ = rc.SetWriteDeadline(time.Now().Add(sseWriteTimeout))
		if _, err := fmt.Fprint(w, payload); err != nil {
			return false
		}
		flusher.Flush()
		return true
	}

	for {
		select {
		case <-r.Context().Done():
			return
		case <-ticker.C:
			if !write(": keepalive\n\n") {
				return
			}
		case ev, ok := <-ch:
			if !ok {
				return // session terminée : le canal est fermé
			}
			if !write(fmt.Sprintf("event: %s\ndata: {\"type\":%q}\n\n", ev.Type, ev.Type)) {
				return // client déconnecté ou écriture expirée
			}
		}
	}
}

// Ingest gère POST /api/streams/ingest/{stream_key} : réception du flux audio du
// diffuseur (STR-71). L'authentification se fait par le stream_key du path (pas de
// JWT) ; le corps est un flux continu copié dans le segmenteur HLS de la session.
func (h *Handler) Ingest(w http.ResponseWriter, r *http.Request) {
	key := r.PathValue("stream_key")

	writer, release, err := h.sessions.AttachIngest(key)
	if err != nil {
		httpjson.WriteError(w, r, ingestError(err))
		return
	}
	defer release()

	// Validation légère du Content-Type (après résolution de la clé pour préserver
	// le 404 sur clé inconnue, avant io.Copy pour qu'aucun octet n'atteigne ffmpeg).
	// Si présent, il doit être audio/* : coupe tôt un push manifestement non-audio
	// (ex. curl --data-binary → application/x-www-form-urlencoded) qui ferait tourner
	// ffmpeg dans le vide (le demuxer ADTS cherche des sync words sans jamais mourir).
	// Un Content-Type absent reste accepté (clients bruts, cf. ADR 015).
	if ct := r.Header.Get("Content-Type"); ct != "" {
		if mt, _, perr := mime.ParseMediaType(ct); perr != nil || !strings.HasPrefix(mt, "audio/") {
			httpjson.WriteError(w, r, httpjson.StatusError(
				http.StatusUnsupportedMediaType, "unsupported_media_type", "content-type must be audio/aac"))
			return
		}
	}

	// Push long : la deadline de lecture est glissante (renouvelée à chaque bloc
	// audio) et la deadline d'écriture est neutralisée. Une connexion active peut
	// durer des heures, mais une socket half-open libère l'ingest après le délai
	// de grâce pour laisser le mobile se reconnecter.
	rc := http.NewResponseController(w)
	_ = rc.SetWriteDeadline(time.Time{})

	// Copie bloquante jusqu'à la fin du push (EOF = diffuseur déconnecté). On ne
	// ferme PAS l'entrée du segmenteur : la session reste live (fenêtre de
	// segments disponible) jusqu'au stop explicite.
	reader := ingestDeadlineReader{
		body:       r.Body,
		controller: rc,
		timeout:    h.ingestReconnectGrace,
	}
	if _, err := io.Copy(writer, reader); err != nil {
		// Push interrompu par une erreur : refléter l'échec plutôt qu'un 204
		// trompeur (un broadcast avorté ≠ déconnexion propre). Ne jamais logger le
		// stream_key (secret). Si le client est déjà parti, l'écriture est un no-op.
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("streaming: ingest interrompu")
		httpjson.WriteError(w, r, apperror.Internal("ingest interrupted", err))
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ingestError mappe les erreurs d'ingest vers un status HTTP.
func ingestError(err error) error {
	switch {
	case errors.Is(err, errIngestInProgress):
		return apperror.Conflict("ingest already in progress")
	case errors.Is(err, errSegmenterUnavailable):
		return apperror.Internal("hls segmenter unavailable", err)
	default: // errNotLive : clé inconnue ou flux pas en direct (on ne divulgue pas la différence)
		return apperror.NotFound("no live stream for this key")
	}
}

// Playlist gère GET /api/streams/{id}/playlist.m3u8 : sert le manifeste HLS d'un
// flux public (lecture publique, cf. serveHLSFile). 409 si le flux n'est pas en
// direct ou si le manifeste n'est pas encore prêt.
func (h *Handler) Playlist(w http.ResponseWriter, r *http.Request) {
	h.serveHLSFile(w, r, HLSKindPlaylist, "application/vnd.apple.mpegurl",
		func(id string) (string, bool) { return h.sessions.Playlist(id) },
		apperror.Conflict("stream is not live"))
}

// Segment gère GET /api/streams/{id}/segments/{segment} : sert un segment .ts d'un
// flux public (lecture publique, cf. serveHLSFile). Le nom du segment est validé
// (anti path-traversal) dans la couche session ; nom invalide ou segment absent -> 404.
func (h *Handler) Segment(w http.ResponseWriter, r *http.Request) {
	h.serveHLSFile(w, r, HLSKindSegment, "video/mp2t",
		func(id string) (string, bool) { return h.sessions.Segment(id, r.PathValue("segment")) },
		apperror.NotFound("segment not found"))
}

// serveHLSFile factorise le service d'un fichier HLS (manifeste ou segment) à un
// auditeur : contrôle de visibilité (GetStream, 404 si absent/privé), lookup de la
// session (unavailable si le flux n'est pas en direct), en-têtes puis ServeFile.
// lookup renvoie le chemin disque et sa validité.
//
// Lecture PUBLIQUE (STR-108) : pas d'authentification requise — le player natif
// (just_audio → AVPlayer/ExoPlayer) ne peut pas porter le Bearer. Un auditeur
// anonyme a requesterID = "" ; la visibilité de GetStream sert alors les flux
// publics et renvoie 404 pour un flux privé (jamais propriétaire de "").
func (h *Handler) serveHLSFile(w http.ResponseWriter, r *http.Request, kind, contentType string, lookup func(id string) (string, bool), unavailable error) {
	requesterID, _ := auth.UserIDFromContext(r.Context()) // "" si anonyme (pas de JWT)
	id := r.PathValue("id")

	if _, _, err := h.svc.GetStream(r.Context(), id, requesterID); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	path, ok := lookup(id)
	if !ok {
		httpjson.WriteError(w, r, unavailable)
		return
	}

	// À partir d'ici seulement, le flux a une session vivante : ses séries
	// seront nettoyées par ForgetStream à l'arrêt. Compter plus tôt laisserait
	// un client créer une série permanente par identifiant inventé — cardinalité
	// illimitée et DoS mémoire (revue PR #272).
	//
	// Les métriques par flux alimentent l'estimation d'auditeurs (débit de
	// requêtes de playlist) et le taux d'erreurs .ts, d'où la capture du status
	// réellement rendu — http.ServeFile écrit l'en-tête lui-même.
	sr := &hlsStatusRecorder{ResponseWriter: w}
	w = sr
	defer func() {
		h.metrics.RecordHLSRequest(id, kind, sr.statusText())
		// Un manifeste servi = un lecteur vivant (STR-154). Seules les
		// playlists comptent : un lecteur en récupère une régulièrement tant
		// qu'il écoute, alors que les segments arrivent par rafales et
		// gonfleraient le compte. Les réponses non-200 ne comptent pas : une
		// requête refusée n'est pas un auditeur.
		if kind == HLSKindPlaylist && sr.statusText() == "200" {
			h.sessions.TouchListener(id, h.clientKey(r))
		}
	}()

	// Le fichier peut ne pas exister encore (fenêtre entre le start et le premier
	// segment, ou push dont ffmpeg n'a encore rien produit) ou avoir été retiré
	// (fenêtre glissante) : renvoyer l'erreur JSON documentée plutôt que le
	// `404 page not found` text/plain brut de http.ServeFile (hors contrat).
	if _, err := os.Stat(path); err != nil {
		httpjson.WriteError(w, r, unavailable)
		return
	}

	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Cache-Control", "no-cache")
	http.ServeFile(w, r, path)
}
