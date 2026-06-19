package streaming

import (
	"encoding/base64"
	"testing"
)

func TestNewStreamKey(t *testing.T) {
	g := NewKeyGenerator()

	k1, err := g.NewStreamKey()
	if err != nil {
		t.Fatalf("NewStreamKey: %v", err)
	}

	b, err := base64.RawURLEncoding.DecodeString(k1)
	if err != nil {
		t.Fatalf("clé non base64url: %v", err)
	}
	if len(b) != streamKeyBytes {
		t.Errorf("longueur décodée = %d, want %d", len(b), streamKeyBytes)
	}

	k2, err := g.NewStreamKey()
	if err != nil {
		t.Fatalf("NewStreamKey: %v", err)
	}
	if k1 == k2 {
		t.Error("deux clés générées devraient être différentes")
	}
}
