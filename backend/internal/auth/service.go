package auth

import (
	"context"
	"net/mail"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"

	"golang.org/x/crypto/bcrypt"
)

const (
	// MinPasswordLen est la taille minimale exigée par STR-33.
	MinPasswordLen = 8
	// MaxPasswordLen évite de dépasser la limite bcrypt (72 bytes) qui
	// tronque silencieusement les mots de passe trop longs.
	MaxPasswordLen = 72
	// BcryptCost est le coût exigé par STR-35 (≥ 12).
	BcryptCost = 12
	// MinUsernameLen et MaxUsernameLen bornent le pseudonyme.
	MinUsernameLen = 3
	MaxUsernameLen = 30
)

var usernameRe = regexp.MustCompile(`^[a-zA-Z0-9_]+$`)

// RegisterInput est la commande métier d'inscription, déjà parsée depuis HTTP.
type RegisterInput struct {
	Email    string
	Username string
	Password string
}

// User est la représentation publique d'un compte créé.
// password_hash n'est jamais exposé.
type User struct {
	ID        string    `json:"id"`
	Email     string    `json:"email"`
	Username  string    `json:"username"`
	Role      string    `json:"role"`
	CreatedAt time.Time `json:"created_at"`
}

// Repository définit les écritures attendues par le service.
// L'interface permet de mocker le stockage dans les tests unitaires.
type Repository interface {
	CreateUser(ctx context.Context, email, username, passwordHash string) (User, error)
}

// Service orchestre la validation, le hachage bcrypt et la persistence.
type Service struct {
	repo Repository
}

// NewService construit un service d'inscription.
func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

// Register valide les entrées, hache le mot de passe et crée l'utilisateur.
func (s *Service) Register(ctx context.Context, in RegisterInput) (User, error) {
	email, err := normalizeEmail(in.Email)
	if err != nil {
		return User{}, err
	}

	username, err := normalizeUsername(in.Username)
	if err != nil {
		return User{}, err
	}

	if err := validatePassword(in.Password); err != nil {
		return User{}, err
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(in.Password), BcryptCost)
	if err != nil {
		return User{}, err
	}

	return s.repo.CreateUser(ctx, email, username, string(hash))
}

func normalizeEmail(raw string) (string, error) {
	addr, err := mail.ParseAddress(strings.TrimSpace(raw))
	if err != nil || addr.Address == "" {
		return "", apperror.InvalidArgument("invalid email")
	}
	return strings.ToLower(addr.Address), nil
}

func normalizeUsername(raw string) (string, error) {
	u := strings.TrimSpace(raw)
	n := utf8.RuneCountInString(u)
	if n < MinUsernameLen || n > MaxUsernameLen {
		return "", apperror.InvalidArgument("invalid username")
	}
	if !usernameRe.MatchString(u) {
		return "", apperror.InvalidArgument("invalid username")
	}
	return u, nil
}

func validatePassword(p string) error {
	switch {
	case utf8.RuneCountInString(p) < MinPasswordLen:
		return apperror.InvalidArgument("password too short")
	case len(p) > MaxPasswordLen:
		return apperror.InvalidArgument("password too long")
	default:
		return nil
	}
}
