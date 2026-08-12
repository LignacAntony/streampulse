package track

import (
	"bytes"
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"testing"
)

func TestFileStorage_Save(t *testing.T) {
	// root inexistant au départ : Save doit le créer (MkdirAll).
	root := filepath.Join(t.TempDir(), "tracks")
	s := NewFileStorage(root)
	content := []byte("fake audio bytes")

	path, err := s.Save(context.Background(), "abc-123", ".mp3", bytes.NewReader(content))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Le nom est dérivé de l'id + ext (jamais d'un nom client) → anti-traversal.
	if got := filepath.Base(path); got != "abc-123.mp3" {
		t.Errorf("filename: got %q, want abc-123.mp3", got)
	}
	if filepath.Dir(path) != root {
		t.Errorf("dir: got %q, want %q", filepath.Dir(path), root)
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read back: %v", err)
	}
	if !bytes.Equal(got, content) {
		t.Errorf("content mismatch: got %q", got)
	}
}

func TestFileStorage_Open(t *testing.T) {
	root := t.TempDir()
	s := NewFileStorage(root)
	content := []byte("fake audio bytes")
	path, err := s.Save(context.Background(), "readable", ".mp3", bytes.NewReader(content))
	if err != nil {
		t.Fatalf("save: %v", err)
	}

	f, err := s.Open(path)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer func() { _ = f.Close() }()

	// Seek : http.ServeContent en dépend pour honorer les requêtes Range.
	if _, err := f.Seek(5, io.SeekStart); err != nil {
		t.Fatalf("seek: %v", err)
	}
	got, err := io.ReadAll(f)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if !bytes.Equal(got, content[5:]) {
		t.Errorf("content from offset 5: got %q, want %q", got, content[5:])
	}
}

// TestFileStorage_OpenMissing : un fichier absent doit remonter os.ErrNotExist,
// que le service traduit en 404 (et non en 500).
func TestFileStorage_OpenMissing(t *testing.T) {
	s := NewFileStorage(t.TempDir())

	_, err := s.Open(filepath.Join(t.TempDir(), "nope.mp3"))
	if !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("expected os.ErrNotExist, got %v", err)
	}
}

func TestFileStorage_Remove(t *testing.T) {
	root := t.TempDir()
	s := NewFileStorage(root)
	path, err := s.Save(context.Background(), "to-delete", ".ogg", bytes.NewReader([]byte("x")))
	if err != nil {
		t.Fatalf("save: %v", err)
	}
	if err := s.Remove(path); err != nil {
		t.Fatalf("remove: %v", err)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Errorf("file must be gone, stat err: %v", err)
	}
}
