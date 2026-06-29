package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"time"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
	"github.com/golang-jwt/jwt/v5"
)

const (
	AccessTokenDuration  = 15 * time.Minute
	RefreshTokenDuration = 7 * 24 * time.Hour
	refreshTokenBytes    = 32
)

type AccessTokenClaims struct {
	UserID string `json:"sub"`
	Role   string `json:"role"`
	jwt.RegisteredClaims
}

func GenerateAccessToken(userID, role, secret string, now time.Time) (string, error) {
	claims := AccessTokenClaims{
		UserID: userID,
		Role:   role,
		RegisteredClaims: jwt.RegisteredClaims{
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(AccessTokenDuration)),
		},
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := tok.SignedString([]byte(secret))
	if err != nil {
		return "", fmt.Errorf("token: sign access token: %w", err)
	}
	return signed, nil
}

// ParseAccessToken retourne apperror.Unauthorized sur toute erreur de validation.
func ParseAccessToken(tokenStr, secret string) (AccessTokenClaims, error) {
	var claims AccessTokenClaims
	tok, err := jwt.ParseWithClaims(tokenStr, &claims, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return []byte(secret), nil
	}, jwt.WithExpirationRequired())
	if err != nil || !tok.Valid {
		return AccessTokenClaims{}, apperror.Unauthorized("invalid or expired token")
	}
	return claims, nil
}

func GenerateRefreshToken() (raw string, hash string, err error) {
	b := make([]byte, refreshTokenBytes)
	if _, err := rand.Read(b); err != nil {
		return "", "", fmt.Errorf("token: generate refresh token: %w", err)
	}
	raw = hex.EncodeToString(b)
	hash = hashToken(raw)
	return raw, hash, nil
}

func hashToken(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}
