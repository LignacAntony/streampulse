package auth

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
	"golang.org/x/crypto/bcrypt"
)

type fakeRepo struct {
	createCalls int
	emails      map[string]UserWithHash
	// inactiveEmails simule des comptes désactivés : absents de emails (donc
	// GetUserByEmail renvoie NotFound) mais bien enregistrés (IsEmailRegistered).
	inactiveEmails      map[string]struct{}
	usernames           map[string]struct{}
	lastHash            string
	refreshTokens       map[string]fakeRefreshToken
	passwordResetTokens map[string]fakePasswordResetToken
	deleteUserErr       error
}

type fakeRefreshToken struct {
	userID    string
	expiresAt time.Time
}

type fakePasswordResetToken struct {
	userID    string
	expiresAt time.Time
	usedAt    *time.Time
}

func newFakeRepo() *fakeRepo {
	return &fakeRepo{
		emails:              map[string]UserWithHash{},
		inactiveEmails:      map[string]struct{}{},
		usernames:           map[string]struct{}{},
		refreshTokens:       map[string]fakeRefreshToken{},
		passwordResetTokens: map[string]fakePasswordResetToken{},
	}
}

func (f *fakeRepo) CreateUser(_ context.Context, email, username, hash string) (User, error) {
	f.createCalls++
	if _, ok := f.emails[email]; ok {
		return User{}, apperror.Conflict("email or username already taken")
	}
	if _, ok := f.usernames[username]; ok {
		return User{}, apperror.Conflict("email or username already taken")
	}
	u := User{ID: "00000000-0000-0000-0000-000000000001", Email: email, Username: username, Role: "user", CreatedAt: time.Now().UTC()}
	f.emails[email] = UserWithHash{User: u, PasswordHash: hash}
	f.usernames[username] = struct{}{}
	f.lastHash = hash
	return u, nil
}

func (f *fakeRepo) CreateOAuthUser(_ context.Context, email, username string) (User, error) {
	f.createCalls++
	if _, ok := f.emails[email]; ok {
		return User{}, apperror.Conflict("email or username already taken")
	}
	if _, ok := f.usernames[username]; ok {
		return User{}, apperror.Conflict("email or username already taken")
	}
	u := User{ID: "00000000-0000-0000-0000-000000000002", Email: email, Username: username, Role: "user", CreatedAt: time.Now().UTC()}
	// Compte OAuth : aucun mot de passe local (hash vide).
	f.emails[email] = UserWithHash{User: u, PasswordHash: ""}
	f.usernames[username] = struct{}{}
	return u, nil
}

func (f *fakeRepo) IsEmailRegistered(_ context.Context, email string) (bool, error) {
	if _, ok := f.emails[email]; ok {
		return true, nil
	}
	_, ok := f.inactiveEmails[email]
	return ok, nil
}

func (f *fakeRepo) GetUserByEmail(_ context.Context, email string) (UserWithHash, error) {
	uwh, ok := f.emails[email]
	if !ok {
		return UserWithHash{}, apperror.NotFound("user not found")
	}
	return uwh, nil
}

func (f *fakeRepo) StoreRefreshToken(_ context.Context, userID, tokenHash string, expiresAt time.Time) error {
	f.refreshTokens[tokenHash] = fakeRefreshToken{userID: userID, expiresAt: expiresAt}
	return nil
}

func (f *fakeRepo) GetUserByRefreshToken(_ context.Context, tokenHash string) (User, error) {
	rt, ok := f.refreshTokens[tokenHash]
	if !ok || time.Now().After(rt.expiresAt) {
		return User{}, apperror.Unauthorized("invalid or expired refresh token")
	}
	for _, uwh := range f.emails {
		if uwh.ID == rt.userID {
			return uwh.User, nil
		}
	}
	return User{}, apperror.Unauthorized("invalid or expired refresh token")
}

func (f *fakeRepo) RotateRefreshToken(_ context.Context, oldHash, newHash, userID string, expiresAt time.Time) error {
	rt, ok := f.refreshTokens[oldHash]
	if !ok || time.Now().After(rt.expiresAt) {
		return apperror.Unauthorized("invalid or expired refresh token")
	}
	delete(f.refreshTokens, oldHash)
	f.refreshTokens[newHash] = fakeRefreshToken{userID: userID, expiresAt: expiresAt}
	return nil
}

func (f *fakeRepo) RevokeRefreshToken(_ context.Context, tokenHash string) error {
	delete(f.refreshTokens, tokenHash)
	return nil
}

func (f *fakeRepo) StorePasswordResetToken(_ context.Context, userID, tokenHash string, expiresAt time.Time) error {
	f.passwordResetTokens[tokenHash] = fakePasswordResetToken{userID: userID, expiresAt: expiresAt}
	return nil
}

func (f *fakeRepo) DeletePendingPasswordResetsByUser(_ context.Context, userID string) error {
	for hash, prt := range f.passwordResetTokens {
		if prt.userID == userID {
			delete(f.passwordResetTokens, hash)
		}
	}
	return nil
}

func (f *fakeRepo) CheckPasswordResetToken(_ context.Context, tokenHash string) error {
	prt, ok := f.passwordResetTokens[tokenHash]
	if !ok || time.Now().After(prt.expiresAt) || prt.usedAt != nil {
		return apperror.InvalidArgument("invalid or expired reset token")
	}
	return nil
}

type fakeMailer struct {
	lastTo    string
	lastToken string
}

func (f *fakeMailer) SendPasswordResetEmail(_ context.Context, to, rawToken string) error {
	f.lastTo = to
	f.lastToken = rawToken
	return nil
}

func TestRegister_HappyPath(t *testing.T) {
	repo := newFakeRepo()
	svc := NewService(repo, testSecret, &fakeMailer{})

	user, err := svc.Register(context.Background(), RegisterInput{
		Email: "Alice@Example.COM", Username: "alice_42", Password: "hunter2hunter",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if user.Email != "alice@example.com" {
		t.Errorf("email not normalized: %q", user.Email)
	}
	if !strings.HasPrefix(repo.lastHash, "$2a$12$") && !strings.HasPrefix(repo.lastHash, "$2b$12$") {
		t.Errorf("bcrypt cost not 12, got prefix: %s", repo.lastHash[:7])
	}
	if err := bcrypt.CompareHashAndPassword([]byte(repo.lastHash), []byte("hunter2hunter")); err != nil {
		t.Errorf("hash mismatch: %v", err)
	}
}

func TestRegister_InvalidInput(t *testing.T) {
	cases := []struct {
		name     string
		input    RegisterInput
		wantCode apperror.Code
	}{
		{"bad email", RegisterInput{Email: "not-an-email", Username: "alice", Password: "hunter2hunter"}, apperror.CodeInvalidArgument},
		{"short password", RegisterInput{Email: "a@b.co", Username: "alice", Password: "abc"}, apperror.CodeInvalidArgument},
		{"long password", RegisterInput{Email: "a@b.co", Username: "alice", Password: strings.Repeat("x", MaxPasswordLen+1)}, apperror.CodeInvalidArgument},
		{"short username", RegisterInput{Email: "a@b.co", Username: "ab", Password: "hunter2hunter"}, apperror.CodeInvalidArgument},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := NewService(newFakeRepo(), testSecret, &fakeMailer{}).Register(context.Background(), tc.input)
			if !apperror.IsCode(err, tc.wantCode) {
				t.Errorf("want %s, got %v", tc.wantCode, err)
			}
		})
	}
}

func TestRegister_DuplicateEmail(t *testing.T) {
	repo := newFakeRepo()
	svc := NewService(repo, testSecret, &fakeMailer{})
	base := RegisterInput{Email: "bob@example.com", Username: "bob", Password: "hunter2hunter"}
	if _, err := svc.Register(context.Background(), base); err != nil {
		t.Fatal(err)
	}
	_, err := svc.Register(context.Background(), RegisterInput{Email: "bob@example.com", Username: "bob2", Password: "hunter2hunter"})
	assertAppError(t, err, apperror.CodeConflict, "email or username already taken")
}

func TestLogin_HappyPath(t *testing.T) {
	repo := newFakeRepo()
	svc := NewService(repo, testSecret, &fakeMailer{})
	if _, err := svc.Register(context.Background(), RegisterInput{Email: "alice@example.com", Username: "alice", Password: "hunter2hunter"}); err != nil {
		t.Fatal(err)
	}

	pair, err := svc.Login(context.Background(), LoginInput{Email: "alice@example.com", Password: "hunter2hunter"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if pair.AccessToken == "" || pair.RefreshToken == "" {
		t.Error("tokens should not be empty")
	}
	claims, err := ParseAccessToken(pair.AccessToken, testSecret)
	if err != nil {
		t.Fatalf("invalid access token: %v", err)
	}
	if claims.Role != "user" {
		t.Errorf("role = %q, want user", claims.Role)
	}
}

func TestLogin_InvalidCredentials(t *testing.T) {
	repo := newFakeRepo()
	svc := NewService(repo, testSecret, &fakeMailer{})
	if _, err := svc.Register(context.Background(), RegisterInput{Email: "alice@example.com", Username: "alice", Password: "hunter2hunter"}); err != nil {
		t.Fatal(err)
	}

	cases := []LoginInput{
		{Email: "nobody@example.com", Password: "hunter2hunter"},
		{Email: "alice@example.com", Password: "wrongpassword"},
	}
	for _, in := range cases {
		_, err := svc.Login(context.Background(), in)
		// Doit toujours retourner Unauthorized, jamais NotFound (pas de fuite d'info).
		assertAppError(t, err, apperror.CodeUnauthorized, "invalid credentials")
	}
}

func TestRefresh_HappyPath(t *testing.T) {
	repo := newFakeRepo()
	svc := NewService(repo, testSecret, &fakeMailer{})
	if _, err := svc.Register(context.Background(), RegisterInput{Email: "alice@example.com", Username: "alice", Password: "hunter2hunter"}); err != nil {
		t.Fatal(err)
	}
	loginPair, err := svc.Login(context.Background(), LoginInput{Email: "alice@example.com", Password: "hunter2hunter"})
	if err != nil {
		t.Fatal(err)
	}

	refreshPair, err := svc.Refresh(context.Background(), RefreshInput{RefreshToken: loginPair.RefreshToken})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if refreshPair.AccessToken == "" || refreshPair.RefreshToken == "" {
		t.Error("tokens should not be empty")
	}
}

func TestRefresh_TokenReuse_Rejected(t *testing.T) {
	repo := newFakeRepo()
	svc := NewService(repo, testSecret, &fakeMailer{})
	if _, err := svc.Register(context.Background(), RegisterInput{Email: "alice@example.com", Username: "alice", Password: "hunter2hunter"}); err != nil {
		t.Fatal(err)
	}
	loginPair, _ := svc.Login(context.Background(), LoginInput{Email: "alice@example.com", Password: "hunter2hunter"})

	if _, err := svc.Refresh(context.Background(), RefreshInput{RefreshToken: loginPair.RefreshToken}); err != nil {
		t.Fatalf("first refresh: %v", err)
	}
	// Réutiliser le même token doit échouer (rotation).
	_, err := svc.Refresh(context.Background(), RefreshInput{RefreshToken: loginPair.RefreshToken})
	assertAppError(t, err, apperror.CodeUnauthorized, "invalid or expired refresh token")
}

func TestLogout_HappyPath(t *testing.T) {
	repo := newFakeRepo()
	svc := NewService(repo, testSecret, &fakeMailer{})
	if _, err := svc.Register(context.Background(), RegisterInput{Email: "alice@example.com", Username: "alice", Password: "hunter2hunter"}); err != nil {
		t.Fatal(err)
	}
	loginPair, err := svc.Login(context.Background(), LoginInput{Email: "alice@example.com", Password: "hunter2hunter"})
	if err != nil {
		t.Fatal(err)
	}

	if err := svc.Logout(context.Background(), LogoutInput{RefreshToken: loginPair.RefreshToken}); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// Le refresh token doit être révoqué.
	_, err = svc.Refresh(context.Background(), RefreshInput{RefreshToken: loginPair.RefreshToken})
	assertAppError(t, err, apperror.CodeUnauthorized, "invalid or expired refresh token")
}

func TestLogout_UnknownToken_IsIdempotent(t *testing.T) {
	svc := NewService(newFakeRepo(), testSecret, &fakeMailer{})
	if err := svc.Logout(context.Background(), LogoutInput{RefreshToken: "unknown-token"}); err != nil {
		t.Errorf("logout with unknown token should not error, got: %v", err)
	}
}

func TestForgotPassword_KnownEmail_StoresToken(t *testing.T) {
	repo := newFakeRepo()
	mailer := &fakeMailer{}
	svc := NewService(repo, testSecret, mailer)
	if _, err := svc.Register(context.Background(), RegisterInput{
		Email: "alice@example.com", Username: "alice", Password: "hunter2hunter",
	}); err != nil {
		t.Fatal(err)
	}

	if err := svc.ForgotPassword(context.Background(), ForgotPasswordInput{Email: "alice@example.com"}); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(repo.passwordResetTokens) != 1 {
		t.Errorf("expected 1 password reset token stored, got %d", len(repo.passwordResetTokens))
	}
	for _, prt := range repo.passwordResetTokens {
		if prt.expiresAt.Before(time.Now().UTC()) {
			t.Error("token already expired")
		}
	}
	if mailer.lastTo != "alice@example.com" {
		t.Errorf("email sent to %q, want alice@example.com", mailer.lastTo)
	}
	if mailer.lastToken == "" {
		t.Error("email sent with empty token")
	}
}

func TestForgotPassword_UnknownEmail_ReturnsNil(t *testing.T) {
	svc := NewService(newFakeRepo(), testSecret, &fakeMailer{})
	if err := svc.ForgotPassword(context.Background(), ForgotPasswordInput{Email: "nobody@example.com"}); err != nil {
		t.Errorf("unknown email should not error, got: %v", err)
	}
}

func TestForgotPassword_InvalidEmail_ReturnsNil(t *testing.T) {
	svc := NewService(newFakeRepo(), testSecret, &fakeMailer{})
	if err := svc.ForgotPassword(context.Background(), ForgotPasswordInput{Email: "not-an-email"}); err != nil {
		t.Errorf("invalid email should not error, got: %v", err)
	}
}

func TestForgotPassword_ReplacesExistingToken(t *testing.T) {
	repo := newFakeRepo()
	svc := NewService(repo, testSecret, &fakeMailer{})
	if _, err := svc.Register(context.Background(), RegisterInput{
		Email: "alice@example.com", Username: "alice", Password: "hunter2hunter",
	}); err != nil {
		t.Fatal(err)
	}

	// Deux demandes successives → un seul token en BDD.
	_ = svc.ForgotPassword(context.Background(), ForgotPasswordInput{Email: "alice@example.com"})
	_ = svc.ForgotPassword(context.Background(), ForgotPasswordInput{Email: "alice@example.com"})

	if len(repo.passwordResetTokens) != 1 {
		t.Errorf("expected 1 token after double request, got %d", len(repo.passwordResetTokens))
	}
}

func (f *fakeRepo) ResetPassword(_ context.Context, tokenHash, passwordHash string) error {
	prt, ok := f.passwordResetTokens[tokenHash]
	if !ok || time.Now().After(prt.expiresAt) || prt.usedAt != nil {
		return apperror.InvalidArgument("invalid or expired reset token")
	}
	for email, uwh := range f.emails {
		if uwh.ID == prt.userID {
			uwh.PasswordHash = passwordHash
			f.emails[email] = uwh
			break
		}
	}
	now := time.Now().UTC()
	prt.usedAt = &now
	f.passwordResetTokens[tokenHash] = prt
	for hash, rt := range f.refreshTokens {
		if rt.userID == prt.userID {
			delete(f.refreshTokens, hash)
		}
	}
	return nil
}

func (f *fakeRepo) GetUserByID(_ context.Context, userID string) (UserWithHash, error) {
	for _, uwh := range f.emails {
		if uwh.ID == userID {
			return uwh, nil
		}
	}
	return UserWithHash{}, apperror.NotFound("user not found")
}

func (f *fakeRepo) DeleteUserByID(_ context.Context, userID string) error {
	if f.deleteUserErr != nil {
		return f.deleteUserErr
	}
	for email, uwh := range f.emails {
		if uwh.ID == userID {
			delete(f.usernames, uwh.Username)
			delete(f.emails, email)
			return nil
		}
	}
	return nil
}

func TestResetPassword_HappyPath(t *testing.T) {
	repo := newFakeRepo()
	svc := NewService(repo, testSecret, &fakeMailer{})
	user, err := svc.Register(context.Background(), RegisterInput{
		Email: "alice@example.com", Username: "alice", Password: "oldpassword",
	})
	if err != nil {
		t.Fatal(err)
	}

	const rawToken = "known-raw-reset-token"
	tokenHash := hashToken(rawToken)
	repo.passwordResetTokens[tokenHash] = fakePasswordResetToken{
		userID:    user.ID,
		expiresAt: time.Now().UTC().Add(time.Hour),
	}

	if err := svc.ResetPassword(context.Background(), ResetPasswordInput{Token: rawToken, Password: "newpassword1"}); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	uwh := repo.emails["alice@example.com"]
	if err := bcrypt.CompareHashAndPassword([]byte(uwh.PasswordHash), []byte("newpassword1")); err != nil {
		t.Errorf("password not updated: %v", err)
	}
	if repo.passwordResetTokens[tokenHash].usedAt == nil {
		t.Error("token not marked as used")
	}
}

func TestResetPassword_RevokesAllRefreshTokens(t *testing.T) {
	repo := newFakeRepo()
	svc := NewService(repo, testSecret, &fakeMailer{})
	if _, err := svc.Register(context.Background(), RegisterInput{
		Email: "alice@example.com", Username: "alice", Password: "oldpassword",
	}); err != nil {
		t.Fatal(err)
	}

	loginPair, err := svc.Login(context.Background(), LoginInput{Email: "alice@example.com", Password: "oldpassword"})
	if err != nil {
		t.Fatal(err)
	}
	if len(repo.refreshTokens) == 0 {
		t.Fatal("expected at least one refresh token before reset")
	}

	const rawToken = "reset-token-for-revoke-test"
	tokenHash := hashToken(rawToken)
	userID := repo.emails["alice@example.com"].ID
	repo.passwordResetTokens[tokenHash] = fakePasswordResetToken{
		userID:    userID,
		expiresAt: time.Now().UTC().Add(time.Hour),
	}

	if err := svc.ResetPassword(context.Background(), ResetPasswordInput{Token: rawToken, Password: "newpassword1"}); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(repo.refreshTokens) != 0 {
		t.Errorf("expected all refresh tokens to be revoked after password reset, got %d", len(repo.refreshTokens))
	}

	_, err = svc.Refresh(context.Background(), RefreshInput{RefreshToken: loginPair.RefreshToken})
	assertAppError(t, err, apperror.CodeUnauthorized, "invalid or expired refresh token")
}

func TestResetPassword_InvalidToken_Errors(t *testing.T) {
	svc := NewService(newFakeRepo(), testSecret, &fakeMailer{})
	err := svc.ResetPassword(context.Background(), ResetPasswordInput{Token: "unknowntoken", Password: "newpassword1"})
	if !apperror.IsCode(err, apperror.CodeInvalidArgument) {
		t.Errorf("want invalid_argument, got %v", err)
	}
}

func TestResetPassword_ExpiredToken_Errors(t *testing.T) {
	repo := newFakeRepo()
	svc := NewService(repo, testSecret, &fakeMailer{})
	if _, err := svc.Register(context.Background(), RegisterInput{
		Email: "alice@example.com", Username: "alice", Password: "oldpassword",
	}); err != nil {
		t.Fatal(err)
	}
	past := time.Now().UTC().Add(-time.Hour)
	repo.passwordResetTokens["expiredhash"] = fakePasswordResetToken{
		userID: "00000000-0000-0000-0000-000000000001", expiresAt: past,
	}
	err := svc.ResetPassword(context.Background(), ResetPasswordInput{Token: "expiredhash", Password: "newpassword1"})
	if !apperror.IsCode(err, apperror.CodeInvalidArgument) {
		t.Errorf("want invalid_argument, got %v", err)
	}
}

func TestResetPassword_UsedToken_Errors(t *testing.T) {
	repo := newFakeRepo()
	svc := NewService(repo, testSecret, &fakeMailer{})
	if _, err := svc.Register(context.Background(), RegisterInput{
		Email: "alice@example.com", Username: "alice", Password: "oldpassword",
	}); err != nil {
		t.Fatal(err)
	}
	now := time.Now().UTC()
	repo.passwordResetTokens["usedhash"] = fakePasswordResetToken{
		userID: "00000000-0000-0000-0000-000000000001", expiresAt: now.Add(time.Hour), usedAt: &now,
	}
	err := svc.ResetPassword(context.Background(), ResetPasswordInput{Token: "usedhash", Password: "newpassword1"})
	if !apperror.IsCode(err, apperror.CodeInvalidArgument) {
		t.Errorf("want invalid_argument, got %v", err)
	}
}

func TestResetPassword_ShortPassword_Errors(t *testing.T) {
	svc := NewService(newFakeRepo(), testSecret, &fakeMailer{})
	err := svc.ResetPassword(context.Background(), ResetPasswordInput{Token: "anytoken", Password: "short"})
	if !apperror.IsCode(err, apperror.CodeInvalidArgument) {
		t.Errorf("want invalid_argument, got %v", err)
	}
}

func TestDeleteAccount_HappyPath(t *testing.T) {
	repo := newFakeRepo()
	svc := NewService(repo, testSecret, &fakeMailer{})
	user, err := svc.Register(context.Background(), RegisterInput{
		Email: "alice@example.com", Username: "alice", Password: "hunter2hunter",
	})
	if err != nil {
		t.Fatal(err)
	}

	if err := svc.DeleteAccount(context.Background(), DeleteAccountInput{
		UserID: user.ID, Password: "hunter2hunter",
	}); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if _, ok := repo.emails["alice@example.com"]; ok {
		t.Error("user still present in repo after deletion")
	}
}

func TestDeleteAccount_WrongPassword(t *testing.T) {
	repo := newFakeRepo()
	svc := NewService(repo, testSecret, &fakeMailer{})
	user, err := svc.Register(context.Background(), RegisterInput{
		Email: "alice@example.com", Username: "alice", Password: "hunter2hunter",
	})
	if err != nil {
		t.Fatal(err)
	}

	err = svc.DeleteAccount(context.Background(), DeleteAccountInput{
		UserID: user.ID, Password: "wrongpassword",
	})
	assertAppError(t, err, apperror.CodeUnauthorized, "invalid credentials")
}

func TestDeleteAccount_EmptyPassword(t *testing.T) {
	svc := NewService(newFakeRepo(), testSecret, &fakeMailer{})
	err := svc.DeleteAccount(context.Background(), DeleteAccountInput{
		UserID: "00000000-0000-0000-0000-000000000001", Password: "",
	})
	assertAppError(t, err, apperror.CodeInvalidArgument, "password required")
}

func TestDeleteAccount_UserNotFound(t *testing.T) {
	svc := NewService(newFakeRepo(), testSecret, &fakeMailer{})
	err := svc.DeleteAccount(context.Background(), DeleteAccountInput{
		UserID: "00000000-0000-0000-0000-000000000099", Password: "hunter2hunter",
	})
	if !apperror.IsCode(err, apperror.CodeNotFound) {
		t.Errorf("want not_found, got %v", err)
	}
}

func TestDeleteAccount_RepoDeleteError(t *testing.T) {
	repo := newFakeRepo()
	svc := NewService(repo, testSecret, &fakeMailer{})
	user, err := svc.Register(context.Background(), RegisterInput{
		Email: "alice@example.com", Username: "alice", Password: "hunter2hunter",
	})
	if err != nil {
		t.Fatal(err)
	}

	repo.deleteUserErr = fmt.Errorf("db unavailable")
	err = svc.DeleteAccount(context.Background(), DeleteAccountInput{
		UserID: user.ID, Password: "hunter2hunter",
	})
	if !apperror.IsCode(err, apperror.CodeInternal) {
		t.Errorf("want internal, got %v", err)
	}
}

func assertAppError(t *testing.T, err error, code apperror.Code, message string) {
	t.Helper()
	appErr, ok := apperror.As(err)
	if !ok {
		t.Fatalf("want app error %s, got %v", code, err)
	}
	if appErr.Code != code {
		t.Fatalf("code: want %s, got %s", code, appErr.Code)
	}
	if appErr.Message != message {
		t.Fatalf("message: want %q, got %q", message, appErr.Message)
	}
}

// fakeTrackPurger simule track.Service : il enrobe le hard-delete (deleteUser)
// et le relaie, comme le vrai purger le ferait après avoir relevé les chemins.
type fakeTrackPurger struct {
	called bool
	gotID  string
}

func (f *fakeTrackPurger) PurgeUserTracks(_ context.Context, userID string, deleteUser func() error) error {
	f.called = true
	f.gotID = userID
	return deleteUser()
}

// DeleteAccount purge les fichiers audio du user avant le hard-delete (US-05-01,
// ADR 032) : sans ça, supprimer son propre compte laisserait des orphelins.
func TestService_DeleteAccount_PurgesTracks(t *testing.T) {
	repo := newFakeRepo()
	hash, err := bcrypt.GenerateFromPassword([]byte("Password123!"), bcrypt.DefaultCost)
	if err != nil {
		t.Fatalf("hash: %v", err)
	}
	u, err := repo.CreateUser(context.Background(), "self@x.dev", "selfuser", string(hash))
	if err != nil {
		t.Fatalf("seed user: %v", err)
	}

	svc := NewService(repo, testSecret, &fakeMailer{})
	purger := &fakeTrackPurger{}
	svc.SetTrackPurger(purger)

	if err := svc.DeleteAccount(context.Background(), DeleteAccountInput{
		UserID: u.ID, Password: "Password123!",
	}); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !purger.called || purger.gotID != u.ID {
		t.Fatalf("purger not called with user id, got %q (called=%v)", purger.gotID, purger.called)
	}
	if _, ok := repo.emails["self@x.dev"]; ok {
		t.Error("user should have been deleted")
	}
}

// --- Connexion Google (LoginWithGoogle) ---

type fakeGoogleVerifier struct {
	claims GoogleClaims
	err    error
}

func (f fakeGoogleVerifier) Verify(_ context.Context, _ string) (GoogleClaims, error) {
	return f.claims, f.err
}

func TestLoginWithGoogle_CreatesNewUser(t *testing.T) {
	repo := newFakeRepo()
	svc := NewService(repo, testSecret, &fakeMailer{})
	svc.SetGoogleVerifier(fakeGoogleVerifier{claims: GoogleClaims{
		Sub: "g-123", Email: "New.User@Gmail.com", EmailVerified: true, Name: "New User",
	}})

	pair, err := svc.LoginWithGoogle(context.Background(), GoogleLoginInput{IDToken: "tok"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if pair.AccessToken == "" || pair.RefreshToken == "" {
		t.Fatal("tokens should not be empty")
	}
	// Email normalisé en minuscules à la création.
	if _, ok := repo.emails["new.user@gmail.com"]; !ok {
		t.Fatalf("google user should have been created, got emails=%v", repo.emails)
	}
	if repo.createCalls != 1 {
		t.Errorf("want 1 creation, got %d", repo.createCalls)
	}
}

func TestLoginWithGoogle_ExistingUserNotRecreated(t *testing.T) {
	repo := newFakeRepo()
	svc := NewService(repo, testSecret, &fakeMailer{})
	// Compte email/mot de passe déjà présent avec le même email.
	if _, err := svc.Register(context.Background(), RegisterInput{
		Email: "bob@example.com", Username: "bob", Password: "hunter2hunter",
	}); err != nil {
		t.Fatal(err)
	}
	before := repo.createCalls

	svc.SetGoogleVerifier(fakeGoogleVerifier{claims: GoogleClaims{
		Sub: "g-9", Email: "bob@example.com", EmailVerified: true, Name: "Bob",
	}})

	pair, err := svc.LoginWithGoogle(context.Background(), GoogleLoginInput{IDToken: "tok"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if pair.AccessToken == "" {
		t.Fatal("token should not be empty")
	}
	if repo.createCalls != before {
		t.Errorf("existing user should not be recreated, createCalls went %d -> %d", before, repo.createCalls)
	}
}

func TestLoginWithGoogle_DisabledAccountRejected(t *testing.T) {
	repo := newFakeRepo()
	// Compte désactivé : enregistré, mais masqué par le filtre is_active.
	repo.inactiveEmails["banned@example.com"] = struct{}{}
	svc := NewService(repo, testSecret, &fakeMailer{})
	svc.SetGoogleVerifier(fakeGoogleVerifier{claims: GoogleClaims{
		Sub: "g-x", Email: "banned@example.com", EmailVerified: true, Name: "Banned",
	}})

	_, err := svc.LoginWithGoogle(context.Background(), GoogleLoginInput{IDToken: "tok"})
	if !apperror.IsCode(err, apperror.CodeForbidden) {
		t.Fatalf("want forbidden, got %v", err)
	}
	// Aucun INSERT n'a dû être tenté.
	if repo.createCalls != 0 {
		t.Errorf("no creation should be attempted for a disabled account, got %d", repo.createCalls)
	}
}

func TestLoginWithGoogle_UnverifiedEmailRejected(t *testing.T) {
	svc := NewService(newFakeRepo(), testSecret, &fakeMailer{})
	svc.SetGoogleVerifier(fakeGoogleVerifier{claims: GoogleClaims{
		Email: "x@y.dev", EmailVerified: false,
	}})
	_, err := svc.LoginWithGoogle(context.Background(), GoogleLoginInput{IDToken: "tok"})
	if !apperror.IsCode(err, apperror.CodeUnauthorized) {
		t.Errorf("want unauthorized, got %v", err)
	}
}

func TestLoginWithGoogle_VerifierErrorPropagated(t *testing.T) {
	svc := NewService(newFakeRepo(), testSecret, &fakeMailer{})
	svc.SetGoogleVerifier(fakeGoogleVerifier{err: apperror.Unauthorized("invalid google token")})
	_, err := svc.LoginWithGoogle(context.Background(), GoogleLoginInput{IDToken: "bad"})
	if !apperror.IsCode(err, apperror.CodeUnauthorized) {
		t.Errorf("want unauthorized, got %v", err)
	}
}

func TestLoginWithGoogle_EmptyToken(t *testing.T) {
	svc := NewService(newFakeRepo(), testSecret, &fakeMailer{})
	svc.SetGoogleVerifier(fakeGoogleVerifier{})
	_, err := svc.LoginWithGoogle(context.Background(), GoogleLoginInput{IDToken: "  "})
	if !apperror.IsCode(err, apperror.CodeInvalidArgument) {
		t.Errorf("want invalid_argument, got %v", err)
	}
}

func TestLoginWithGoogle_NotConfigured(t *testing.T) {
	svc := NewService(newFakeRepo(), testSecret, &fakeMailer{})
	// Aucun verifier injecté : la fonctionnalité est désactivée.
	_, err := svc.LoginWithGoogle(context.Background(), GoogleLoginInput{IDToken: "tok"})
	if !apperror.IsCode(err, apperror.CodeInternal) {
		t.Errorf("want internal, got %v", err)
	}
}

func TestGoogleUsernameBase(t *testing.T) {
	cases := []struct {
		email, name, want string
	}{
		{"john.doe@gmail.com", "John Doe", "johndoe"},
		{"a@b.co", "Alice Wonderland", "AliceWonderland"}, // partie locale trop courte -> nom
		{"x@y.co", "", "user"},                            // rien d'exploitable -> user
	}
	for _, tc := range cases {
		if got := googleUsernameBase(tc.email, tc.name); got != tc.want {
			t.Errorf("googleUsernameBase(%q,%q) = %q, want %q", tc.email, tc.name, got, tc.want)
		}
	}
}
