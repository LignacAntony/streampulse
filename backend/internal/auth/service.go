package auth

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"net/mail"
	"regexp"
	"strings"
	"time"

	"unicode/utf8"

	"github.com/rs/zerolog"

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

// GoogleLoginInput porte l'ID token émis par Google côté client mobile.
type GoogleLoginInput struct {
	IDToken string
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

type DeleteAccountInput struct {
	UserID   string
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
	CreateOAuthUser(ctx context.Context, email, username string) (User, error)
	GetUserByEmail(ctx context.Context, email string) (UserWithHash, error)
	GetUserByID(ctx context.Context, userID string) (UserWithHash, error)
	StoreRefreshToken(ctx context.Context, userID, tokenHash string, expiresAt time.Time) error
	GetUserByRefreshToken(ctx context.Context, tokenHash string) (User, error)
	RotateRefreshToken(ctx context.Context, oldHash, newHash, userID string, expiresAt time.Time) error
	RevokeRefreshToken(ctx context.Context, tokenHash string) error
	StorePasswordResetToken(ctx context.Context, userID, tokenHash string, expiresAt time.Time) error
	DeletePendingPasswordResetsByUser(ctx context.Context, userID string) error
	CheckPasswordResetToken(ctx context.Context, tokenHash string) error
	ResetPassword(ctx context.Context, tokenHash, passwordHash string) error
	DeleteUserByID(ctx context.Context, userID string) error
}

// Mailer envoie des emails transactionnels liés à l'authentification.
type Mailer interface {
	SendPasswordResetEmail(ctx context.Context, to, rawToken string) error
}

// UserTrackPurger orchestre la suppression du compte pour supprimer aussi les
// fichiers audio du user. deleteUser est le hard-delete lui-même : le purger
// relève les chemins, exécute deleteUser, puis supprime les fichiers (les
// fichiers ne partent qu'après un delete réussi → pas de ligne fantôme).
// Implémentée par track.Service ; injectée en setter (SetTrackPurger).
type UserTrackPurger interface {
	PurgeUserTracks(ctx context.Context, userID string, deleteUser func() error) error
}

type Service struct {
	repo      Repository
	jwtSecret string
	mailer    Mailer
	// purger est optionnel (injecté en setter) : nil dans les tests.
	purger UserTrackPurger
	// googleVerifier est optionnel (injecté en setter) : nil quand la connexion
	// Google n'est pas configurée (GOOGLE_CLIENT_ID vide) ou dans les tests.
	googleVerifier GoogleVerifier
}

func NewService(repo Repository, jwtSecret string, mailer Mailer) *Service {
	return &Service{repo: repo, jwtSecret: jwtSecret, mailer: mailer}
}

// SetTrackPurger branche la suppression des fichiers audio à la suppression du
// compte (câblé dans main.go), même motif que le domaine admin.
func (s *Service) SetTrackPurger(p UserTrackPurger) {
	s.purger = p
}

// SetGoogleVerifier branche la validation des ID tokens Google (câblé dans
// main.go uniquement si GOOGLE_CLIENT_ID est renseigné), même motif que le purger.
func (s *Service) SetGoogleVerifier(v GoogleVerifier) {
	s.googleVerifier = v
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

	return s.issueTokenPair(ctx, uwh.ID, uwh.Role)
}

// LoginWithGoogle valide un ID token Google, retrouve ou crée le compte associé
// (première connexion = création automatique, rôle user), puis émet le couple de
// jetons StreamPulse habituel. L'identité de confiance vient de Google : jamais
// de mot de passe côté StreamPulse pour ces comptes.
func (s *Service) LoginWithGoogle(ctx context.Context, in GoogleLoginInput) (TokenPair, error) {
	if s.googleVerifier == nil {
		return TokenPair{}, apperror.Internal("google sign-in not configured", nil)
	}
	if strings.TrimSpace(in.IDToken) == "" {
		return TokenPair{}, apperror.InvalidArgument("id_token required")
	}

	claims, err := s.googleVerifier.Verify(ctx, in.IDToken)
	if err != nil {
		return TokenPair{}, err
	}
	if !claims.EmailVerified {
		return TokenPair{}, apperror.Unauthorized("google email not verified")
	}

	email, err := normalizeEmail(claims.Email)
	if err != nil {
		return TokenPair{}, apperror.Unauthorized("invalid google account")
	}

	user, err := s.findOrCreateGoogleUser(ctx, email, claims.Name)
	if err != nil {
		return TokenPair{}, err
	}

	return s.issueTokenPair(ctx, user.ID, user.Role)
}

// issueTokenPair produit un access token signé + un refresh token persisté haché.
// Partagé par Login (mot de passe) et LoginWithGoogle.
func (s *Service) issueTokenPair(ctx context.Context, userID, role string) (TokenPair, error) {
	now := time.Now().UTC()
	accessToken, err := GenerateAccessToken(userID, role, s.jwtSecret, now)
	if err != nil {
		return TokenPair{}, apperror.Internal("could not issue token", err)
	}

	rawRefresh, hashRefresh, err := GenerateRefreshToken()
	if err != nil {
		return TokenPair{}, apperror.Internal("could not generate refresh token", err)
	}

	if err := s.repo.StoreRefreshToken(ctx, userID, hashRefresh, now.Add(RefreshTokenDuration)); err != nil {
		return TokenPair{}, apperror.Internal("could not store refresh token", err)
	}

	return TokenPair{AccessToken: accessToken, RefreshToken: rawRefresh}, nil
}

// findOrCreateGoogleUser retrouve le compte par email, ou le crée sans mot de
// passe. En cas de collision de username, réessaie avec un suffixe aléatoire ;
// une course sur l'email (compte créé entre-temps) est rattrapée en relisant.
func (s *Service) findOrCreateGoogleUser(ctx context.Context, email, name string) (User, error) {
	uwh, err := s.repo.GetUserByEmail(ctx, email)
	if err == nil {
		return uwh.User, nil
	}
	if !apperror.IsCode(err, apperror.CodeNotFound) {
		return User{}, err
	}

	base := googleUsernameBase(email, name)
	for attempt := 0; attempt < 5; attempt++ {
		username := base
		if attempt > 0 {
			username = base + randomSuffix()
		}

		user, cerr := s.repo.CreateOAuthUser(ctx, email, username)
		if cerr == nil {
			return user, nil
		}
		if apperror.IsCode(cerr, apperror.CodeConflict) {
			// Soit l'email existe déjà (course), soit le username est pris. On
			// relit l'email : s'il existe, on l'utilise ; sinon on retente avec
			// un autre username.
			if existing, gerr := s.repo.GetUserByEmail(ctx, email); gerr == nil {
				return existing.User, nil
			}
			continue
		}
		return User{}, cerr
	}
	return User{}, apperror.Internal("could not create google account", nil)
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

	if err := s.repo.DeletePendingPasswordResetsByUser(ctx, uwh.ID); err != nil {
		zerolog.Ctx(ctx).Warn().Err(err).Str("user_id", uwh.ID).Msg("auth: purge des resets de mot de passe en attente")
	}

	raw, hash, err := GenerateRefreshToken()
	if err != nil {
		return apperror.Internal("could not generate reset token", err)
	}

	expiresAt := time.Now().UTC().Add(PasswordResetTokenDuration)
	if err := s.repo.StorePasswordResetToken(ctx, uwh.ID, hash, expiresAt); err != nil {
		return apperror.Internal("could not store reset token", err)
	}

	if err := s.mailer.SendPasswordResetEmail(ctx, uwh.Email, raw); err != nil {
		return apperror.Internal("could not send reset email", err)
	}

	return nil
}

func (s *Service) ResetPassword(ctx context.Context, in ResetPasswordInput) error {
	if err := validatePassword(in.Password); err != nil {
		return err
	}

	tokenHash := hashToken(in.Token)

	if err := s.repo.CheckPasswordResetToken(ctx, tokenHash); err != nil {
		return err
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(in.Password), BcryptCost)
	if err != nil {
		return apperror.Internal("could not hash password", err)
	}

	return s.repo.ResetPassword(ctx, tokenHash, string(hash))
}

func (s *Service) DeleteAccount(ctx context.Context, in DeleteAccountInput) error {
	if in.Password == "" {
		return apperror.InvalidArgument("password required")
	}

	uwh, err := s.repo.GetUserByID(ctx, in.UserID)
	if err != nil {
		return err
	}

	if err := bcrypt.CompareHashAndPassword([]byte(uwh.PasswordHash), []byte(in.Password)); err != nil {
		return apperror.Unauthorized("invalid credentials")
	}

	// Le purger séquence : relève les chemins → hard-delete (cascade) → supprime
	// les fichiers du volume. Les fichiers ne sont retirés qu'après un delete
	// réussi (pas de ligne fantôme). Si aucun purger n'est câblé, delete direct.
	deleteUser := func() error {
		if err := s.repo.DeleteUserByID(ctx, in.UserID); err != nil {
			return apperror.Internal("could not delete account", err)
		}
		return nil
	}
	if s.purger != nil {
		if err := s.purger.PurgeUserTracks(ctx, in.UserID, deleteUser); err != nil {
			return err
		}
	} else if err := deleteUser(); err != nil {
		return err
	}

	zerolog.Ctx(ctx).Info().Str("user_id", in.UserID).Msg("auth: compte supprimé")
	return nil
}

func normalizeEmail(raw string) (string, error) {
	addr, err := mail.ParseAddress(strings.TrimSpace(raw))
	if err != nil || addr.Address == "" {
		return "", apperror.InvalidArgument("invalid email")
	}
	return strings.ToLower(addr.Address), nil
}

// googleUsernameBase dérive un username valide (3-30, [a-zA-Z0-9_]) depuis la
// partie locale de l'email, à défaut le nom Google, à défaut « user ». Tronqué
// pour laisser la place à un suffixe de désambiguïsation.
func googleUsernameBase(email, name string) string {
	local := email
	if at := strings.IndexByte(email, '@'); at > 0 {
		local = email[:at]
	}

	base := sanitizeUsername(local)
	if utf8.RuneCountInString(base) < MinUsernameLen {
		base = sanitizeUsername(name)
	}
	if utf8.RuneCountInString(base) < MinUsernameLen {
		base = "user"
	}

	// Laisse 6 caractères pour un éventuel suffixe hexadécimal (randomSuffix).
	const maxBase = MaxUsernameLen - 6
	if len(base) > maxBase {
		base = base[:maxBase]
	}
	return base
}

// sanitizeUsername ne conserve que les caractères autorisés par usernameRe.
func sanitizeUsername(s string) string {
	var b strings.Builder
	for _, r := range s {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '_':
			b.WriteRune(r)
		}
	}
	return b.String()
}

// randomSuffix renvoie 6 caractères hexadécimaux aléatoires.
func randomSuffix() string {
	b := make([]byte, 3)
	if _, err := rand.Read(b); err != nil {
		// crypto/rand ne devrait jamais échouer ; repli sur un horodatage.
		return hex.EncodeToString([]byte(time.Now().Format("150405")))[:6]
	}
	return hex.EncodeToString(b)
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
