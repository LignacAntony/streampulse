package profiles

import (
	"context"
	"testing"
	"time"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

type fakeRepo struct {
	profiles    map[string]Profile
	upsertCalls int
}

func (f *fakeRepo) GetMe(_ context.Context, userID string) (Profile, error) {
	p, ok := f.profiles[userID]
	if !ok {
		return Profile{}, apperror.NotFound("user not found")
	}
	return p, nil
}

func (f *fakeRepo) UpsertProfile(_ context.Context, userID string, in UpdateProfileInput) error {
	f.upsertCalls++
	p := f.profiles[userID]
	p.Pseudo = in.Pseudo
	p.Bio = in.Bio
	p.Theme = in.Theme
	p.NotificationsEnabled = in.NotificationsEnabled
	p.AudioQuality = in.AudioQuality
	f.profiles[userID] = p
	return nil
}

const testUserID = "00000000-0000-0000-0000-000000000001"

func seededRepo() *fakeRepo {
	return &fakeRepo{profiles: map[string]Profile{
		testUserID: {ID: testUserID, Email: "user1@streampulse.dev", Role: "user", Pseudo: "user1", Theme: "dark", AudioQuality: "normal", CreatedAt: time.Now().UTC()},
	}}
}

func validInput() UpdateProfileInput {
	return UpdateProfileInput{Pseudo: "Nova", Bio: "Lo-fi", Theme: "light", AudioQuality: "high"}
}

func TestService_UpdateMe_Success(t *testing.T) {
	repo := seededRepo()
	p, err := NewService(repo).UpdateMe(context.Background(), testUserID, validInput())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if repo.upsertCalls != 1 || p.Pseudo != "Nova" || p.Theme != "light" || p.AudioQuality != "high" {
		t.Fatalf("profile not updated: %+v (upsertCalls=%d)", p, repo.upsertCalls)
	}
}

func TestService_UpdateMe_Validation(t *testing.T) {
	tests := map[string]func(*UpdateProfileInput){
		"pseudo invalide": func(in *UpdateProfileInput) { in.Pseudo = "bad@name" },
		"theme invalide":  func(in *UpdateProfileInput) { in.Theme = "neon" },
		"audio invalide":  func(in *UpdateProfileInput) { in.AudioQuality = "ultra" },
	}
	for name, mutate := range tests {
		t.Run(name, func(t *testing.T) {
			repo := seededRepo()
			in := validInput()
			mutate(&in)
			if _, err := NewService(repo).UpdateMe(context.Background(), testUserID, in); !apperror.IsCode(err, apperror.CodeInvalidArgument) {
				t.Fatalf("want invalid_argument, got %v", err)
			}
			if repo.upsertCalls != 0 {
				t.Errorf("repo must not be called on invalid input")
			}
		})
	}
}
