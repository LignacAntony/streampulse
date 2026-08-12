// Package track porte le domaine des pistes audio de la bibliothèque personnelle
// de l'utilisateur : upload d'un fichier (MP3/AAC/OGG) et listing (US-05-01).
//
// Il a été extrait du domaine playlist, où GET /api/tracks vivait temporairement
// (cf. ADR 029 §7 / ADR 032). Le fichier est stocké hors répertoire servi (via
// Storage), et seule sa référence + ses métadonnées vivent en base.
package track

import (
	"context"
	"errors"
	"io"
	"math"
	"net/http"
	"strings"
	"unicode/utf8"

	"github.com/gabriel-vasile/mimetype"
	"github.com/google/uuid"
	"github.com/rs/zerolog"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
	"github.com/LignacAntony/streampulse/internal/shared/httpjson"
)

// MaxUploadBytes borne la taille du fichier audio accepté (50 Mo, critère
// d'acceptation de l'US-05-01). L'US fige cette valeur : pas de variable d'env.
const MaxUploadBytes int64 = 50 << 20

// MaxUserStorageBytes borne la taille CUMULÉE des fichiers d'un même compte
// (500 Mo). Sans ce quota, un utilisateur pourrait boucler des uploads jusqu'à
// saturer le volume — et donc le disque du VPS, qui héberge aussi la base. Une
// constante suffit ici ; on pourra la passer en variable d'env si besoin.
const MaxUserStorageBytes int64 = 500 << 20

// Contraintes de validation du titre (aligné sur la logique playlist).
const (
	MinTitleLen = 1
	MaxTitleLen = 200
)

// sniffLen est le nombre d'octets lus en tête de fichier pour détecter le vrai
// type MIME. mimetype recommande ~3 Kio pour couvrir les conteneurs (OGG…).
const sniffLen = 3072

// Track est une piste de la bibliothèque de l'utilisateur. Artist et DurationS
// sont nullables (la table tracks les autorise nuls). file_path/mime_type/
// file_size restent en base et ne fuient pas hors du domaine.
type Track struct {
	ID        string
	Title     string
	Artist    *string
	DurationS *int
}

// CreateTrackInput porte les données d'un upload. Content est repositionnable :
// le service lit d'abord l'en-tête pour sniffer le MIME, puis rembobine pour
// écrire le fichier complet. Size vient de l'en-tête multipart (contrôle de
// taille secondaire, le handler borne déjà le corps).
type CreateTrackInput struct {
	UserID    string
	Title     string
	Artist    *string
	DurationS *int
	Size      int64
	Content   io.ReadSeeker
}

// CreateTrackParams est la demande de persistance adressée au Repository (champs
// validés + chemin/MIME/taille déterminés côté serveur).
type CreateTrackParams struct {
	UserID    string
	Title     string
	Artist    *string
	DurationS *int
	FilePath  string
	MimeType  string
	FileSize  int64
}

// Repository persiste les pistes (implémenté par pgRepository).
type Repository interface {
	CreateTrack(ctx context.Context, p CreateTrackParams) (Track, error)
	ListTracksByUser(ctx context.Context, userID string) ([]Track, error)
	// SumFileSizeByUser retourne la taille cumulée des fichiers du user (quota).
	SumFileSizeByUser(ctx context.Context, userID string) (int64, error)
	// ListFilePathsByUser retourne les chemins disque des fichiers du user, pour
	// les supprimer du stockage à la suppression de son compte.
	ListFilePathsByUser(ctx context.Context, userID string) ([]string, error)
}

// Storage écrit/supprime le binaire audio hors de la base et hors répertoire
// servi (implémenté par FileStorage). Save renvoie le chemin persistant.
type Storage interface {
	Save(ctx context.Context, id, ext string, r io.Reader) (string, error)
	Remove(path string) error
}

// Service porte la logique métier du domaine track.
type Service struct {
	repo    Repository
	storage Storage
}

func NewService(repo Repository, storage Storage) *Service {
	return &Service{repo: repo, storage: storage}
}

// Create valide l'entrée, contrôle le VRAI type MIME du contenu (défense contre
// un fichier non-audio renommé en .mp3), écrit le fichier via Storage puis
// enregistre la piste. Si l'INSERT échoue, le fichier écrit est supprimé pour ne
// pas laisser d'orphelin sur disque. Un titre déjà utilisé -> 409 (repo).
func (s *Service) Create(ctx context.Context, in CreateTrackInput) (Track, error) {
	title, err := normalizeTitle(in.Title)
	if err != nil {
		return Track{}, err
	}
	artist, err := normalizeArtist(in.Artist)
	if err != nil {
		return Track{}, err
	}
	duration, err := normalizeDuration(in.DurationS)
	if err != nil {
		return Track{}, err
	}
	if in.Size <= 0 {
		return Track{}, apperror.InvalidArgument("empty file")
	}

	// Le vrai type MIME est contrôlé AVANT le quota : un fichier non-audio doit
	// recevoir 415 (le bon diagnostic) même si l'utilisateur est au-dessus du
	// quota — ré-uploader un PDF ne franchira jamais le quota de toute façon.
	mimeType, ext, err := detectAudio(in.Content)
	if err != nil {
		return Track{}, err
	}

	// Quota de stockage par compte, vérifié AVANT d'écrire le fichier : borne le
	// remplissage du volume (best-effort — deux uploads concurrents peuvent tous
	// deux passer, une borne de concurrence globale suivra dans un ticket dédié).
	// 403 (et non 507) : c'est une condition côté client que réessayer ne résout
	// pas (il faut libérer de l'espace), et ça garde la réponse hors du bucket 5xx
	// qui déclenche l'alerte critique (ADR 021).
	used, err := s.repo.SumFileSizeByUser(ctx, in.UserID)
	if err != nil {
		return Track{}, err
	}
	if used+in.Size > MaxUserStorageBytes {
		return Track{}, httpjson.StatusError(
			http.StatusForbidden,
			"storage_quota_exceeded",
			"quota de stockage atteint",
		)
	}

	id := uuid.NewString()
	path, err := s.storage.Save(ctx, id, ext, in.Content)
	if err != nil {
		return Track{}, apperror.Internal("track: save file", err)
	}

	track, err := s.repo.CreateTrack(ctx, CreateTrackParams{
		UserID:    in.UserID,
		Title:     title,
		Artist:    artist,
		DurationS: duration,
		FilePath:  path,
		MimeType:  mimeType,
		FileSize:  in.Size,
	})
	if err != nil {
		// Le fichier est déjà sur disque : on le retire pour ne pas laisser
		// d'orphelin (best-effort, l'erreur d'origine prime).
		_ = s.storage.Remove(path)
		return Track{}, err
	}
	return track, nil
}

// PurgeUserTracks orchestre la suppression du compte pour ne laisser NI fichier
// orphelin NI ligne fantôme. En trois temps :
//  1. relève les chemins des fichiers du user (avant que la cascade DB ne les
//     rende introuvables) ;
//  2. exécute deleteUser (le hard-delete, qui déclenche la cascade sur tracks) ;
//  3. seulement si (2) a réussi, supprime les fichiers du stockage.
//
// Si deleteUser échoue, on ne supprime aucun fichier : lignes et fichiers restent
// cohérents (mieux qu'une bibliothèque listant des pistes au binaire disparu).
// La suppression des fichiers est best-effort (un échec est journalisé, pas
// propagé) ; un échec du listing (1) n'empêche pas la suppression du compte.
func (s *Service) PurgeUserTracks(ctx context.Context, userID string, deleteUser func() error) error {
	paths, err := s.repo.ListFilePathsByUser(ctx, userID)
	if err != nil {
		// On n'a pas pu relever les chemins : on privilégie la suppression du
		// compte (les fichiers resteront orphelins, journalisés).
		zerolog.Ctx(ctx).Warn().Err(err).Str("user_id", userID).
			Msg("track: chemins introuvables avant la purge du compte")
		return deleteUser()
	}
	if err := deleteUser(); err != nil {
		return err
	}
	for _, p := range paths {
		if err := s.storage.Remove(p); err != nil {
			zerolog.Ctx(ctx).Warn().Err(err).Str("path", p).
				Msg("track: fichier orphelin non supprimé à la purge du compte")
		}
	}
	return nil
}

// ListUserTracks retourne la bibliothèque de pistes du demandeur (le filtre
// porte sur le porteur du JWT — aucune piste d'un tiers n'y figure).
func (s *Service) ListUserTracks(ctx context.Context, requesterID string) ([]Track, error) {
	return s.repo.ListTracksByUser(ctx, requesterID)
}

// normalizeTitle trime le titre et valide sa longueur (1-200).
func normalizeTitle(raw string) (string, error) {
	title := strings.TrimSpace(raw)
	if n := utf8.RuneCountInString(title); n < MinTitleLen || n > MaxTitleLen {
		return "", apperror.InvalidArgument("invalid title")
	}
	return title, nil
}

// normalizeArtist trime l'artiste (vide -> nil) et valide sa longueur.
func normalizeArtist(raw *string) (*string, error) {
	if raw == nil {
		return nil, nil
	}
	a := strings.TrimSpace(*raw)
	if a == "" {
		return nil, nil
	}
	if utf8.RuneCountInString(a) > MaxTitleLen {
		return nil, apperror.InvalidArgument("artist too long")
	}
	return &a, nil
}

// normalizeDuration valide la durée fournie par le client : positive et tenant
// dans la colonne int4 si présente (la table impose CHECK duration_s > 0). La
// borne haute écarte une valeur absurde qui déborderait la conversion int32.
func normalizeDuration(d *int) (*int, error) {
	if d == nil {
		return nil, nil
	}
	if *d <= 0 || *d > math.MaxInt32 {
		return nil, apperror.InvalidArgument("invalid duration")
	}
	return d, nil
}

// detectAudio lit l'en-tête du contenu, en déduit le vrai type MIME et le mappe
// vers la valeur canonique attendue par le CHECK DB. Rembobine ensuite le lecteur
// pour que l'écriture reparte du début. Tout ce qui n'est pas de l'audio autorisé
// (PDF renommé, image…) est rejeté en 415.
func detectAudio(rs io.ReadSeeker) (mimeType, ext string, err error) {
	head := make([]byte, sniffLen)
	n, readErr := io.ReadFull(rs, head)
	if readErr != nil && !errors.Is(readErr, io.ErrUnexpectedEOF) && !errors.Is(readErr, io.EOF) {
		return "", "", apperror.Internal("track: read upload header", readErr)
	}
	if _, err := rs.Seek(0, io.SeekStart); err != nil {
		return "", "", apperror.Internal("track: rewind upload", err)
	}

	mtype := mimetype.Detect(head[:n])
	canonical, canonicalExt, ok := canonicalAudio(mtype)
	if !ok {
		return "", "", httpjson.StatusError(
			http.StatusUnsupportedMediaType,
			"unsupported_media_type",
			"seuls les fichiers audio MP3, AAC ou OGG sont acceptés",
		)
	}
	return canonical, canonicalExt, nil
}

// canonicalAudio parcourt le type détecté et ses parents (mimetype expose une
// hiérarchie : un OGG audio a pour parent application/ogg) et renvoie la valeur
// canonique exigée par le CHECK de la table tracks, plus l'extension de fichier.
func canonicalAudio(m *mimetype.MIME) (mimeType, ext string, ok bool) {
	for t := m; t != nil; t = t.Parent() {
		switch t.String() {
		case "audio/mpeg":
			return "audio/mpeg", ".mp3", true
		case "audio/aac":
			return "audio/aac", ".aac", true
		case "audio/ogg", "application/ogg":
			return "audio/ogg", ".ogg", true
		}
	}
	return "", "", false
}
