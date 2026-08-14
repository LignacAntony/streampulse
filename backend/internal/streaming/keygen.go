package streaming

import (
	"crypto/rand"
	"encoding/base64"
)

// streamKeyBytes : 32 octets aléatoires → ~43 caractères base64url.
const streamKeyBytes = 32

// keyGenerator implémente KeyGenerator via crypto/rand.
type keyGenerator struct{}

// NewKeyGenerator construit le générateur de stream_key.
func NewKeyGenerator() KeyGenerator { return keyGenerator{} }

func (keyGenerator) NewStreamKey() (string, error) {
	b := make([]byte, streamKeyBytes)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}
