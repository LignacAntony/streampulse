package streaming

import (
	"context"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

// Contraintes de validation du titre et de la description.
const (
	MinTitleLen       = 3
	MaxTitleLen       = 120
	MaxDescriptionLen = 500
)

// Statuts d'un flux (miroir du CHECK SQL sur streams.status).
// 'idle' = inactif : flux créé mais pas encore diffusé.
const (
	StatusIdle  = "idle"
	StatusLive  = "live"
	StatusEnded = "ended"
)

// validCategories est la liste blanche des catégories autorisées.
var validCategories = map[string]bool{
	"music":      true,
	"talk":       true,
	"technology": true,
	"gaming":     true,
	"news":       true,
	"sport":      true,
	"other":      true,
}

// Stream est le type domaine d'un flux live. Description, Category, StartedAt
// et EndedAt sont des pointeurs pour pouvoir être nuls.
type Stream struct {
	ID          string
	UserID      string
	Title       string
	Description *string
	Category    *string
	Status      string
	IsPublic    bool
	StreamKey   string
	StartedAt   *time.Time
	EndedAt     *time.Time
	CreatedAt   time.Time
	UpdatedAt   time.Time
}

// CreateStreamInput porte les champs fournis par le diffuseur à la création.
// UserID provient du JWT (source de confiance), pas du payload.
type CreateStreamInput struct {
	UserID      string
	Title       string
	Description *string
	Category    *string
	IsPublic    bool
}

// validate applique les règles métier de création et retourne une copie
// normalisée (titre/description trimés, optionnels vides ramenés à nil).
func (in CreateStreamInput) validate() (CreateStreamInput, error) {
	title := strings.TrimSpace(in.Title)
	if n := utf8.RuneCountInString(title); n < MinTitleLen || n > MaxTitleLen {
		return CreateStreamInput{}, apperror.InvalidArgument("invalid title")
	}

	out := CreateStreamInput{
		UserID:   in.UserID,
		Title:    title,
		IsPublic: in.IsPublic,
	}

	if in.Description != nil {
		desc := strings.TrimSpace(*in.Description)
		if utf8.RuneCountInString(desc) > MaxDescriptionLen {
			return CreateStreamInput{}, apperror.InvalidArgument("description too long")
		}
		if desc != "" {
			out.Description = &desc
		}
	}

	if in.Category != nil {
		cat := strings.TrimSpace(*in.Category)
		if cat != "" {
			if !validCategories[cat] {
				return CreateStreamInput{}, apperror.InvalidArgument("invalid category")
			}
			out.Category = &cat
		}
	}

	return out, nil
}

// CreateParams est la demande de persistance adressée au Repository (champs
// validés + statut initial + stream_key généré).
type CreateParams struct {
	UserID      string
	Title       string
	Description *string
	Category    *string
	IsPublic    bool
	Status      string
	StreamKey   string
}

// Repository est l'interface de persistance (implémentée par pgRepository).
type Repository interface {
	Create(ctx context.Context, p CreateParams) (Stream, error)
}

// KeyGenerator génère le secret de stream source (implémenté par keyGenerator).
type KeyGenerator interface {
	NewStreamKey() (string, error)
}

// Service porte la logique métier du domaine streaming.
type Service struct {
	repo Repository
	keys KeyGenerator
}

func NewService(repo Repository, keys KeyGenerator) *Service {
	return &Service{repo: repo, keys: keys}
}

// CreateStream valide l'entrée, génère le stream_key et persiste le flux avec
// le statut initial 'idle'.
func (s *Service) CreateStream(ctx context.Context, in CreateStreamInput) (Stream, error) {
	validated, err := in.validate()
	if err != nil {
		return Stream{}, err
	}

	key, err := s.keys.NewStreamKey()
	if err != nil {
		return Stream{}, apperror.Internal("generate stream key", err)
	}

	return s.repo.Create(ctx, CreateParams{
		UserID:      validated.UserID,
		Title:       validated.Title,
		Description: validated.Description,
		Category:    validated.Category,
		IsPublic:    validated.IsPublic,
		Status:      StatusIdle,
		StreamKey:   key,
	})
}
