package track

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/rs/zerolog"

	"github.com/LignacAntony/streampulse/internal/auth"
	"github.com/LignacAntony/streampulse/internal/shared/apperror"
	"github.com/LignacAntony/streampulse/internal/shared/httpjson"
)

// maxFormOverhead est la marge accordée au-dessus de la taille du fichier pour
// les autres parties du multipart (limites, en-têtes, champs title/artist…). Le
// corps entier est borné par MaxUploadBytes + cette marge.
const maxFormOverhead int64 = 1 << 20 // 1 Mio

// maxMultipartMemory borne la part gardée EN MÉMOIRE par ParseMultipartForm ;
// au-delà, le corps déborde sur un fichier temporaire (nettoyé par net/http en
// fin de requête). Volontairement bas (1 Mio) : 10 Mio × N uploads concurrents
// saturerait le heap (OOMKill du pod). Le disque temporaire absorbe le reste.
const maxMultipartMemory int64 = 1 << 20 // 1 Mio

// TrackService est l'interface requise par le handler (ISP) : *Service la satisfait.
type TrackService interface {
	Create(ctx context.Context, in CreateTrackInput) (Track, error)
	ListUserTracks(ctx context.Context, requesterID string) ([]Track, error)
	OpenTrackFile(ctx context.Context, trackID, requesterID string) (OpenedTrackFile, error)
}

// Handler expose le domaine track en HTTP.
type Handler struct {
	svc TrackService
	// maxUpload borne la taille du fichier accepté. Champ (et non constante
	// directe) pour être abaissé dans les tests sans forger un corps de 50 Mo.
	maxUpload int64
}

func NewHandler(svc TrackService) *Handler {
	return &Handler{svc: svc, maxUpload: MaxUploadBytes}
}

// libraryTrackResponse est la vue JSON d'une piste de la bibliothèque. artist et
// duration_s sont des pointeurs (null possible).
type libraryTrackResponse struct {
	ID        string  `json:"id"`
	Title     string  `json:"title"`
	Artist    *string `json:"artist"`
	DurationS *int    `json:"duration_s"`
}

// Upload gère POST /api/tracks : upload multipart d'un fichier audio dans la
// bibliothèque du demandeur (201). Le vrai type MIME est validé côté serveur, la
// taille est bornée, et le fichier est stocké hors répertoire servi.
func (h *Handler) Upload(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	// Borne le corps entier avant toute lecture : un upload démesuré est coupé
	// ici (413) plutôt que bufferisé.
	r.Body = http.MaxBytesReader(w, r.Body, h.maxUpload+maxFormOverhead)
	// #nosec G120 -- le corps est déjà borné par MaxBytesReader ci-dessus (pas de
	// parsing non borné) ; maxMultipartMemory ne fait que limiter la part gardée en RAM.
	if err := r.ParseMultipartForm(maxMultipartMemory); err != nil {
		var maxErr *http.MaxBytesError
		if errors.As(err, &maxErr) {
			httpjson.WriteError(w, r, tooLargeError())
			return
		}
		httpjson.WriteError(w, r, apperror.InvalidArgument("invalid multipart form"))
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		httpjson.WriteError(w, r, apperror.InvalidArgument("missing file"))
		return
	}
	defer func() { _ = file.Close() }()

	// Contrôle de taille secondaire sur la seule partie fichier (le MaxBytesReader
	// borne le corps global, marge de formulaire comprise).
	if header.Size > h.maxUpload {
		httpjson.WriteError(w, r, tooLargeError())
		return
	}

	duration, err := parseDuration(r.FormValue("duration_s"))
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	track, err := h.svc.Create(r.Context(), CreateTrackInput{
		UserID:    userID,
		Title:     r.FormValue("title"),
		Artist:    optionalString(r.FormValue("artist")),
		DurationS: duration,
		Size:      header.Size,
		Content:   file,
	})
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusCreated, libraryTrackResponse(track)); err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("track: encode upload response")
	}
}

// ListUserTracks gère GET /api/tracks : bibliothèque de pistes du demandeur (200).
func (h *Handler) ListUserTracks(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	tracks, err := h.svc.ListUserTracks(r.Context(), userID)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	out := make([]libraryTrackResponse, 0, len(tracks))
	for _, t := range tracks {
		out = append(out, libraryTrackResponse(t))
	}
	if err := httpjson.Write(w, http.StatusOK, out); err != nil {
		zerolog.Ctx(r.Context()).Error().Err(err).Msg("track: encode user tracks")
	}
}

// StreamTrack gère GET /api/tracks/{id}/stream : sert le binaire audio d'une
// piste **du demandeur** au lecteur mobile (US-05-04).
//
// Le fichier est délégué à http.ServeContent, qui gère les requêtes Range : le
// lecteur peut reprendre une piste ou y avancer sans retélécharger depuis le
// début, et enchaîner la piste suivante de la file sans à-coup. Le type MIME
// vient de la base (figé à l'upload, déjà validé par sniff) : on ne laisse pas
// ServeContent le deviner depuis un nom de fichier.
func (h *Handler) StreamTrack(w http.ResponseWriter, r *http.Request) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	file, err := h.svc.OpenTrackFile(r.Context(), r.PathValue("id"), userID)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}
	defer func() {
		if err := file.Content.Close(); err != nil {
			zerolog.Ctx(r.Context()).Warn().Err(err).Msg("track: close streamed file")
		}
	}()

	w.Header().Set("Content-Type", file.MimeType)
	// Contenu privé de l'utilisateur : jamais dans un cache partagé, et pas de
	// recompression par un intermédiaire (elle casserait les octets audio).
	w.Header().Set("Cache-Control", "private, no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	// modtime nul : le binaire d'une piste est immuable une fois uploadé, il n'y
	// a pas de revalidation conditionnelle à proposer (ServeContent omet alors
	// Last-Modified et ignore If-Modified-Since).
	http.ServeContent(w, r, "", time.Time{}, file.Content)
}

// tooLargeError construit la réponse 413 commune (dépassement de taille).
func tooLargeError() error {
	return httpjson.StatusError(
		http.StatusRequestEntityTooLarge,
		"file_too_large",
		"le fichier dépasse la taille maximale de 50 Mo",
	)
}

// parseDuration lit le champ optionnel duration_s. Absent -> nil ; présent mais
// non entier -> 400.
func parseDuration(raw string) (*int, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil, nil
	}
	d, err := strconv.Atoi(raw)
	if err != nil {
		return nil, apperror.InvalidArgument("invalid duration_s")
	}
	return &d, nil
}

// optionalString renvoie nil pour une chaîne vide (champ multipart absent).
func optionalString(raw string) *string {
	if strings.TrimSpace(raw) == "" {
		return nil
	}
	return &raw
}
