package track

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// FileStorage écrit les fichiers audio sur le système de fichiers local, sous un
// répertoire racine configuré (STORAGE_PATH) qui n'est jamais servi en HTTP.
//
// Le nom de fichier est dérivé d'un UUID généré côté serveur + une extension
// canonique (jamais du nom fourni par le client) : il n'y a donc aucun risque de
// traversée de répertoire par un nom malveillant (même discipline que hls.go).
type FileStorage struct {
	root string
}

// NewFileStorage construit un stockage fichier enraciné sur root.
func NewFileStorage(root string) *FileStorage {
	return &FileStorage{root: root}
}

// Save écrit le contenu sous {root}/{id}{ext} et renvoie le chemin persistant.
// Le répertoire racine est créé si besoin. O_EXCL garantit qu'on n'écrase jamais
// un fichier existant (l'id est un UUID neuf, une collision signalerait un bug).
func (s *FileStorage) Save(_ context.Context, id, ext string, r io.Reader) (string, error) {
	if err := os.MkdirAll(s.root, 0o750); err != nil {
		return "", fmt.Errorf("track: create storage dir: %w", err)
	}

	path := filepath.Join(s.root, id+ext)
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o640)
	if err != nil {
		return "", fmt.Errorf("track: open file: %w", err)
	}

	if _, err := io.Copy(f, r); err != nil {
		_ = f.Close()
		_ = os.Remove(path)
		return "", fmt.Errorf("track: write file: %w", err)
	}
	if err := f.Close(); err != nil {
		_ = os.Remove(path)
		return "", fmt.Errorf("track: close file: %w", err)
	}
	return path, nil
}

// Remove supprime un fichier précédemment écrit (best-effort côté service, pour
// nettoyer un orphelin quand l'INSERT en base échoue après l'écriture disque).
func (s *FileStorage) Remove(path string) error {
	return os.Remove(path)
}
