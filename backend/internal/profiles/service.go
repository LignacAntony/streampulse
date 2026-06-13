package profiles

import (
	"context"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

const (
	MinPseudoLen = 3
	MaxPseudoLen = 30
	MaxBioLen    = 280
)

// pseudoRe autorise lettres, chiffres, underscore et espaces : c'est un nom
// d'affichage (distinct de users.username qui reste l'identifiant unique du compte).
var pseudoRe = regexp.MustCompile(`^[a-zA-Z0-9_ ]+$`)

// validThemes et validAudioQualities reflètent les CHECK SQL de la table profiles.
var (
	validThemes         = map[string]bool{"system": true, "light": true, "dark": true}
	validAudioQualities = map[string]bool{"low": true, "normal": true, "high": true}
)

// Profile est la vue publique du profil d'un utilisateur connecté.
// Email et Role proviennent de users (lecture seule) ; les autres champs de profiles.
// AvatarURL est un pointeur pour pouvoir être null en JSON.
type Profile struct {
	ID                   string    `json:"id"`
	Email                string    `json:"email"`
	Role                 string    `json:"role"`
	Pseudo               string    `json:"pseudo"`
	Bio                  string    `json:"bio"`
	AvatarURL            *string   `json:"avatar_url"`
	Theme                string    `json:"theme"`
	NotificationsEnabled bool      `json:"notifications_enabled"`
	AudioQuality         string    `json:"audio_quality"`
	CreatedAt            time.Time `json:"created_at"`
}

type UpdateProfileInput struct {
	Pseudo               string
	Bio                  string
	Theme                string
	NotificationsEnabled bool
	AudioQuality         string
}

type Repository interface {
	GetMe(ctx context.Context, userID string) (Profile, error)
	UpsertProfile(ctx context.Context, userID string, in UpdateProfileInput) error
}

type Service struct {
	repo Repository
}

func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) GetMe(ctx context.Context, userID string) (Profile, error) {
	return s.repo.GetMe(ctx, userID)
}

// UpdateMe valide puis persiste les champs du profil dans profiles uniquement
// (users n'est jamais modifié), puis relit le profil à jour.
func (s *Service) UpdateMe(ctx context.Context, userID string, in UpdateProfileInput) (Profile, error) {
	pseudo, err := normalizePseudo(in.Pseudo)
	if err != nil {
		return Profile{}, err
	}

	bio, err := normalizeBio(in.Bio)
	if err != nil {
		return Profile{}, err
	}

	if !validThemes[in.Theme] {
		return Profile{}, apperror.InvalidArgument("invalid theme")
	}

	if !validAudioQualities[in.AudioQuality] {
		return Profile{}, apperror.InvalidArgument("invalid audio quality")
	}

	if err := s.repo.UpsertProfile(ctx, userID, UpdateProfileInput{
		Pseudo:               pseudo,
		Bio:                  bio,
		Theme:                in.Theme,
		NotificationsEnabled: in.NotificationsEnabled,
		AudioQuality:         in.AudioQuality,
	}); err != nil {
		return Profile{}, err
	}

	return s.repo.GetMe(ctx, userID)
}

func normalizePseudo(raw string) (string, error) {
	p := strings.TrimSpace(raw)
	n := utf8.RuneCountInString(p)
	if n < MinPseudoLen || n > MaxPseudoLen {
		return "", apperror.InvalidArgument("invalid pseudo")
	}
	if !pseudoRe.MatchString(p) {
		return "", apperror.InvalidArgument("invalid pseudo")
	}
	return p, nil
}

func normalizeBio(raw string) (string, error) {
	b := strings.TrimSpace(raw)
	if utf8.RuneCountInString(b) > MaxBioLen {
		return "", apperror.InvalidArgument("bio too long")
	}
	return b, nil
}
