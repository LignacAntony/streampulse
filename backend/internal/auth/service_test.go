package auth

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"

	"golang.org/x/crypto/bcrypt"
)

// fakeRepo implémente Repository en mémoire pour tester le service sans DB.
type fakeRepo struct {
	createCalls  int
	emails       map[string]struct{}
	usernames    map[string]struct{}
	lastEmail    string
	lastUsername string
	lastHash     string
	returnErr    error
}

func newFakeRepo() *fakeRepo {
	return &fakeRepo{
		emails:    map[string]struct{}{},
		usernames: map[string]struct{}{},
	}
}

func (f *fakeRepo) CreateUser(_ context.Context, email, username, hash string) (User, error) {
	f.createCalls++
	if f.returnErr != nil {
		return User{}, f.returnErr
	}
	if _, ok := f.emails[email]; ok {
		return User{}, apperror.Conflict("email or username already taken")
	}
	if _, ok := f.usernames[username]; ok {
		return User{}, apperror.Conflict("email or username already taken")
	}
	f.emails[email] = struct{}{}
	f.usernames[username] = struct{}{}
	f.lastEmail = email
	f.lastUsername = username
	f.lastHash = hash
	return User{
		ID:        "00000000-0000-0000-0000-000000000001",
		Email:     email,
		Username:  username,
		Role:      "user",
		CreatedAt: time.Now().UTC(),
	}, nil
}

func TestRegister_HappyPath(t *testing.T) {
	repo := newFakeRepo()
	svc := NewService(repo)

	user, err := svc.Register(context.Background(), RegisterInput{
		Email:    "Alice@Example.COM",
		Username: "alice_42",
		Password: "hunter2hunter",
	})
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if user.Email != "alice@example.com" {
		t.Errorf("email not normalized: got %q", user.Email)
	}
	if user.Username != "alice_42" {
		t.Errorf("username altered: got %q", user.Username)
	}
	if user.Role != "user" {
		t.Errorf("role: want user, got %q", user.Role)
	}
	if repo.createCalls != 1 {
		t.Errorf("createCalls: want 1, got %d", repo.createCalls)
	}
	if !strings.HasPrefix(repo.lastHash, "$2a$12$") && !strings.HasPrefix(repo.lastHash, "$2b$12$") {
		t.Errorf("bcrypt hash cost not 12: got prefix %s", repo.lastHash[:7])
	}
	if err := bcrypt.CompareHashAndPassword([]byte(repo.lastHash), []byte("hunter2hunter")); err != nil {
		t.Errorf("hash does not match plaintext: %v", err)
	}
}

func TestRegister_InvalidEmail(t *testing.T) {
	cases := []string{"", "not-an-email", "alice@", "@example.com", "alice example.com"}
	for _, raw := range cases {
		raw := raw
		t.Run(raw, func(t *testing.T) {
			repo := newFakeRepo()
			svc := NewService(repo)
			_, err := svc.Register(context.Background(), RegisterInput{
				Email:    raw,
				Username: "alice",
				Password: "hunter2hunter",
			})
			assertAppError(t, err, apperror.CodeInvalidArgument, "invalid email")
			if repo.createCalls != 0 {
				t.Errorf("repo touched on invalid email: %d", repo.createCalls)
			}
		})
	}
}

func TestRegister_PasswordTooShort(t *testing.T) {
	cases := []string{"", "a", "abcdefg"} // < 8
	for _, p := range cases {
		p := p
		t.Run(p, func(t *testing.T) {
			repo := newFakeRepo()
			svc := NewService(repo)
			_, err := svc.Register(context.Background(), RegisterInput{
				Email:    "alice@example.com",
				Username: "alice",
				Password: p,
			})
			assertAppError(t, err, apperror.CodeInvalidArgument, "password too short")
		})
	}
}

func TestRegister_PasswordTooLong(t *testing.T) {
	repo := newFakeRepo()
	svc := NewService(repo)
	long := strings.Repeat("x", MaxPasswordLen+1)
	_, err := svc.Register(context.Background(), RegisterInput{
		Email:    "alice@example.com",
		Username: "alice",
		Password: long,
	})
	assertAppError(t, err, apperror.CodeInvalidArgument, "password too long")
}

func TestRegister_InvalidUsername(t *testing.T) {
	cases := []string{"", "ab", "with space", "wîth-dash", strings.Repeat("a", MaxUsernameLen+1)}
	for _, u := range cases {
		u := u
		t.Run(u, func(t *testing.T) {
			repo := newFakeRepo()
			svc := NewService(repo)
			_, err := svc.Register(context.Background(), RegisterInput{
				Email:    "alice@example.com",
				Username: u,
				Password: "hunter2hunter",
			})
			assertAppError(t, err, apperror.CodeInvalidArgument, "invalid username")
		})
	}
}

func TestRegister_DuplicateEmail(t *testing.T) {
	repo := newFakeRepo()
	svc := NewService(repo)
	first := RegisterInput{Email: "bob@example.com", Username: "bob", Password: "hunter2hunter"}
	if _, err := svc.Register(context.Background(), first); err != nil {
		t.Fatalf("first register failed: %v", err)
	}
	// Même email, username différent → contrainte UNIQUE email.
	_, err := svc.Register(context.Background(), RegisterInput{
		Email:    "bob@example.com",
		Username: "bobby",
		Password: "hunter2hunter",
	})
	assertAppError(t, err, apperror.CodeConflict, "email or username already taken")
}

func TestRegister_DuplicateUsername(t *testing.T) {
	repo := newFakeRepo()
	svc := NewService(repo)
	first := RegisterInput{Email: "alice@example.com", Username: "alice", Password: "hunter2hunter"}
	if _, err := svc.Register(context.Background(), first); err != nil {
		t.Fatalf("first register failed: %v", err)
	}
	_, err := svc.Register(context.Background(), RegisterInput{
		Email:    "alice2@example.com",
		Username: "alice",
		Password: "hunter2hunter",
	})
	assertAppError(t, err, apperror.CodeConflict, "email or username already taken")
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
