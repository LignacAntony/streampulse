package auth

import (
	"context"
	"log"
	"net/mail"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"

	"golang.org/x/crypto/bcrypt"
)

const (
	// MinPasswordLen est la taille minimale.
	MinPasswordLen = 8
	// MaxPasswordLen évite de dépasser la limite bcrypt (72 bytes) qui
	// tronque silencieusement les mots de passe trop longs.
	MaxPasswordLen = 72
	// BcryptCost est le coût exigé par STR-35 (≥ 12).
	BcryptCost     = 12
	MinUsernameLen = 3
	MaxUsernameLen = 30

	PasswordResetTokenDuration = time.Hour
)

var usernameRe = regexp.MustCompile(`^[a-zA-Z0-9_]+$`)

type RegisterInput struct {
	Email    string
	Username string
	Password string
}

type LoginInput struct {
	Email    string
	Password string
}

type RefreshInput struct {
	RefreshToken string
}

type LogoutInput struct {
	RefreshToken string
}

type ForgotPasswordInput struct {
	Email string
}

type ResetPasswordInput struct {
	Token    string
	Password string
}

type TokenPair struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
}

// User est la représentation publique d'un compte.
// password_hash n'est jamais exposé.
type User struct {
	ID        string    `json:"id"`
	Email     string    `json:"email"`
	Username  string    `json:"username"`
	Role      string    `json:"role"`
	CreatedAt time.Time `json:"created_at"`
}

// UserWithHash est une projection interne.
// Elle n'est jamais sérialisée en JSON.
type UserWithHash struct {
	User
	PasswordHash string
}

type Repository interface {
	CreateUser(ctx context.Context, email, username, passwordHash string) (User, error)
	GetUserByEmail(ctx context.Context, email string) (UserWithHash, error)
	StoreRefreshToken(ctx context.Context, userID, tokenHash string, expiresAt time.Time) error
	GetUserByRefreshToken(ctx context.Context, tokenHash string) (User, error)
	RotateRefreshToken(ctx context.Context, oldHash, newHash, userID string, expiresAt time.Time) error
	RevokeRefreshToken(ctx context.Context, tokenHash string) error
	StorePasswordResetToken(ctx context.Context, userID, tokenHash string, expiresAt time.Time) error
	DeletePendingPasswordResetsByUser(ctx context.Context, userID string) error
	ResetPassword(ctx context.Context, tokenHash, passwordHash string) error
}

type Service struct {
	repo      Repository
	jwtSecret string
}

func NewService(repo Repository, jwtSecret string) *Service {
	return &Service{repo: repo, jwtSecret: jwtSecret}
}

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

func (s *Service) Login(ctx context.Context, in LoginInput) (TokenPair, error) {
	email, err := normalizeEmail(in.Email)
	if err != nil {
		return TokenPair{}, apperror.Unauthorized("invalid credentials")
	}

	uwh, err := s.repo.GetUserByEmail(ctx, email)
	if err != nil {
		return TokenPair{}, apperror.Unauthorized("invalid credentials")
	}

	if err := bcrypt.CompareHashAndPassword([]byte(uwh.PasswordHash), []byte(in.Password)); err != nil {
		return TokenPair{}, apperror.Unauthorized("invalid credentials")
	}

	now := time.Now().UTC()
	accessToken, err := GenerateAccessToken(uwh.ID, uwh.Role, s.jwtSecret, now)
	if err != nil {
		return TokenPair{}, apperror.Internal("could not issue token", err)
	}

	rawRefresh, hashRefresh, err := GenerateRefreshToken()
	if err != nil {
		return TokenPair{}, apperror.Internal("could not generate refresh token", err)
	}

	if err := s.repo.StoreRefreshToken(ctx, uwh.ID, hashRefresh, now.Add(RefreshTokenDuration)); err != nil {
		return TokenPair{}, apperror.Internal("could not store refresh token", err)
	}

	return TokenPair{AccessToken: accessToken, RefreshToken: rawRefresh}, nil
}

func (s *Service) Refresh(ctx context.Context, in RefreshInput) (TokenPair, error) {
	oldHash := hashToken(in.RefreshToken)

	user, err := s.repo.GetUserByRefreshToken(ctx, oldHash)
	if err != nil {
		return TokenPair{}, apperror.Unauthorized("invalid or expired refresh token")
	}

	now := time.Now().UTC()
	accessToken, err := GenerateAccessToken(user.ID, user.Role, s.jwtSecret, now)
	if err != nil {
		return TokenPair{}, apperror.Internal("could not issue token", err)
	}

	rawRefresh, newHash, err := GenerateRefreshToken()
	if err != nil {
		return TokenPair{}, apperror.Internal("could not generate refresh token", err)
	}

	if err := s.repo.RotateRefreshToken(ctx, oldHash, newHash, user.ID, now.Add(RefreshTokenDuration)); err != nil {
		return TokenPair{}, apperror.Unauthorized("invalid or expired refresh token")
	}

	return TokenPair{AccessToken: accessToken, RefreshToken: rawRefresh}, nil
}

func (s *Service) Logout(ctx context.Context, in LogoutInput) error {
	return s.repo.RevokeRefreshToken(ctx, hashToken(in.RefreshToken))
}

// ForgotPassword génère un token de réinitialisation sécurisé et le stocke en BDD.
// Retourne toujours nil même si l'email est inconnu (évite l'énumération).
func (s *Service) ForgotPassword(ctx context.Context, in ForgotPasswordInput) error {
	email, err := normalizeEmail(in.Email)
	if err != nil {
		return nil
	}

	uwh, err := s.repo.GetUserByEmail(ctx, email)
	if err != nil {
		return nil
	}

	// Supprime les tokens en attente existants avant d'en créer un nouveau.
	_ = s.repo.DeletePendingPasswordResetsByUser(ctx, uwh.ID)

	raw, hash, err := GenerateRefreshToken()
	if err != nil {
		return apperror.Internal("could not generate reset token", err)
	}

	expiresAt := time.Now().UTC().Add(PasswordResetTokenDuration)
	if err := s.repo.StorePasswordResetToken(ctx, uwh.ID, hash, expiresAt); err != nil {
		return apperror.Internal("could not store reset token", err)
	}

	// TODO STR-57 : remplacer ce log par un envoi d'email (SMTP).
	log.Printf("[password-reset] token for %s (expires %s): %s", email, expiresAt.Format(time.RFC3339), raw)

	return nil
}

func (s *Service) ResetPassword(ctx context.Context, in ResetPasswordInput) error {
	if err := validatePassword(in.Password); err != nil {
		return err
	}

	tokenHash := hashToken(in.Token)

	hash, err := bcrypt.GenerateFromPassword([]byte(in.Password), BcryptCost)
	if err != nil {
		return apperror.Internal("could not hash password", err)
	}

	return s.repo.ResetPassword(ctx, tokenHash, string(hash))
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
