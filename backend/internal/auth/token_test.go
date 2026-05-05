package auth

import (
	"testing"
	"time"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

const testSecret = "super-secret-key-for-testing-32chars!!"

func TestGenerateParseAccessToken_RoundTrip(t *testing.T) {
	token, err := GenerateAccessToken("user-123", "admin", testSecret, time.Now())
	if err != nil {
		t.Fatalf("generate: %v", err)
	}
	claims, err := ParseAccessToken(token, testSecret)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if claims.UserID != "user-123" || claims.Role != "admin" {
		t.Errorf("claims = {%s, %s}, want {user-123, admin}", claims.UserID, claims.Role)
	}
}

func TestParseAccessToken_Invalid(t *testing.T) {
	cases := []struct {
		name  string
		token string
		// génère un token expiré
		expired bool
	}{
		{"malformed", "not.a.valid.jwt", false},
		{"empty", "", false},
		{"wrong secret", "", false},
		{"expired", "", true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			tok := tc.token
			secret := testSecret
			if tc.expired {
				var err error
				tok, err = GenerateAccessToken("u", "user", testSecret, time.Now().Add(-AccessTokenDuration-time.Second))
				if err != nil {
					t.Fatal(err)
				}
			}
			if tc.name == "wrong secret" {
				var err error
				tok, err = GenerateAccessToken("u", "user", testSecret, time.Now())
				if err != nil {
					t.Fatal(err)
				}
				secret = "completely-different-secret-key!!"
			}
			_, err := ParseAccessToken(tok, secret)
			if err == nil {
				t.Fatal("expected error, got nil")
			}
			if !apperror.IsCode(err, apperror.CodeUnauthorized) {
				t.Errorf("expected Unauthorized, got %v", err)
			}
		})
	}
}
