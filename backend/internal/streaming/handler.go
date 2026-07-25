package streaming

import (
	"context"
	"errors"
	"fmt"
	"io"
	"mime"
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
}

// StreamSessions expose au handler les opérations sur les sessions live :
// abonnement SSE (STR-85), ingest audio et service des fichiers HLS (STR-70).
// *LiveSessions l'implémente. Le handler utilise l'ensemble de ces méthodes.
type StreamSessions interface {
	Subscribe(streamID string) (<-chan SessionEvent, func())
	AttachIngest(streamKey string) (io.Writer, func(), error)
	Playlist(streamID string) (string, bool)
	Segment(streamID, name string) (string, bool)
}

// Handler expose le domaine streaming en HTTP. ingestBaseURL sert à construire
// l'URL de stream source renvoyée au diffuseur.
type Handler struct {
	svc           StreamService
	ingestBaseURL string
	sessions      StreamSessions
}

func NewHandler(svc StreamService, ingestBaseURL string, sessions StreamSessions) *Handler {
	return &Handler{svc: svc, ingestBaseURL: strings.TrimRight(ingestBaseURL, "/"), sessions: sessions}
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
	ID          string     `json:"id"`
	UserID      string     `json:"user_id"`
	Title       string     `json:"title"`
	Description *string    `json:"description"`
	Category    *string    `json:"category"`
	Status      string     `json:"status"`
	IsPublic    bool       `json:"is_public"`
	StartedAt   *time.Time `json:"started_at"`
	CreatedAt   time.Time  `json:"created_at"`
}

func toSummary(s Stream) streamSummaryResponse {
	return streamSummaryResponse{
		ID:          s.ID,
		UserID:      s.UserID,
		Title:       s.Title,
		Description: s.Description,
		Category:    s.Category,
		Status:      s.Status,
		IsPublic:    s.IsPublic,
		StartedAt:   s.StartedAt,
		CreatedAt:   s.CreatedAt,
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

	// Push long : neutraliser les deadlines read/write posées par http.Server
	// (ReadTimeout/WriteTimeout couperaient une diffusion de plusieurs minutes).
	rc := http.NewResponseController(w)
	_ = rc.SetReadDeadline(time.Time{})
	_ = rc.SetWriteDeadline(time.Time{})

	// Copie bloquante jusqu'à la fin du push (EOF = diffuseur déconnecté). On ne
	// ferme PAS l'entrée du segmenteur : la session reste live (fenêtre de
	// segments disponible) jusqu'au stop explicite.
	if _, err := io.Copy(writer, r.Body); err != nil {
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
	h.serveHLSFile(w, r, "application/vnd.apple.mpegurl",
		func(id string) (string, bool) { return h.sessions.Playlist(id) },
		apperror.Conflict("stream is not live"))
}

// Segment gère GET /api/streams/{id}/segments/{segment} : sert un segment .ts d'un
// flux public (lecture publique, cf. serveHLSFile). Le nom du segment est validé
// (anti path-traversal) dans la couche session ; nom invalide ou segment absent -> 404.
func (h *Handler) Segment(w http.ResponseWriter, r *http.Request) {
	h.serveHLSFile(w, r, "video/mp2t",
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
func (h *Handler) serveHLSFile(w http.ResponseWriter, r *http.Request, contentType string, lookup func(id string) (string, bool), unavailable error) {
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
