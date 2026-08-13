package track

import (
	"bytes"
	"context"
	"errors"
	"io"
	"math"
	"net/http"
	"testing"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
	"github.com/LignacAntony/streampulse/internal/shared/httpjson"
)

const testUserID = "00000000-0000-0000-0000-000000000001"

// mp3Header : un frame sync MPEG audio (0xFF 0xFB) que mimetype classe en
// audio/mpeg. Complété d'octets nuls pour dépasser le seuil de sniff.
var mp3Header = append([]byte{0xFF, 0xFB, 0x90, 0x00}, make([]byte, 64)...)

// pdfHeader : un vrai fichier PDF (magic %PDF-). Sert au test de sécurité « PDF
// renommé .mp3 » — le sniff doit le rejeter.
var pdfHeader = []byte("%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n")

type fakeRepo struct {
	createCalled bool
	gotCreate    CreateTrackParams
	createRet    Track
	createErr    error
	listRet      []Track
	sumRet       int64
	sumErr       error
	pathsRet     []string
	pathsErr     error
}

func (f *fakeRepo) CreateTrack(_ context.Context, p CreateTrackParams) (Track, error) {
	f.createCalled = true
	f.gotCreate = p
	if f.createErr != nil {
		return Track{}, f.createErr
	}
	if f.createRet.ID != "" {
		return f.createRet, nil
	}
	return Track{ID: "new-id", Title: p.Title, Artist: p.Artist, DurationS: p.DurationS}, nil
}

func (f *fakeRepo) ListTracksByUser(_ context.Context, _ string) ([]Track, error) {
	return f.listRet, nil
}

func (f *fakeRepo) SumFileSizeByUser(_ context.Context, _ string) (int64, error) {
	return f.sumRet, f.sumErr
}

func (f *fakeRepo) ListFilePathsByUser(_ context.Context, _ string) ([]string, error) {
	return f.pathsRet, f.pathsErr
}

type stubStorage struct {
	saveCalled   bool
	savedExt     string
	savedContent []byte
	saveErr      error
	savePath     string
	removeCalled bool
	removedPath  string
}

func (s *stubStorage) Save(_ context.Context, id, ext string, r io.Reader) (string, error) {
	s.saveCalled = true
	s.savedExt = ext
	b, _ := io.ReadAll(r)
	s.savedContent = b
	if s.saveErr != nil {
		return "", s.saveErr
	}
	if s.savePath == "" {
		s.savePath = "/tmp/" + id + ext
	}
	return s.savePath, nil
}

func (s *stubStorage) Remove(path string) error {
	s.removeCalled = true
	s.removedPath = path
	return nil
}

func ptr[T any](v T) *T { return &v }

func TestCreate_OK(t *testing.T) {
	repo := &fakeRepo{}
	storage := &stubStorage{}
	svc := NewService(repo, storage)

	got, err := svc.Create(context.Background(), CreateTrackInput{
		UserID:    testUserID,
		Title:     "  Midnight Drive  ",
		Artist:    ptr("Neon Lights"),
		DurationS: ptr(180),
		Size:      int64(len(mp3Header)),
		Content:   bytes.NewReader(mp3Header),
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !storage.saveCalled {
		t.Fatal("storage.Save must be called")
	}
	if storage.savedExt != ".mp3" {
		t.Errorf("ext: got %q, want .mp3", storage.savedExt)
	}
	if !bytes.Equal(storage.savedContent, mp3Header) {
		t.Error("stored content must equal the uploaded bytes (reader rewound after sniff)")
	}
	if !repo.createCalled {
		t.Fatal("repo.CreateTrack must be called")
	}
	if repo.gotCreate.MimeType != "audio/mpeg" {
		t.Errorf("mime: got %q, want audio/mpeg", repo.gotCreate.MimeType)
	}
	if repo.gotCreate.Title != "Midnight Drive" {
		t.Errorf("title must be trimmed, got %q", repo.gotCreate.Title)
	}
	if repo.gotCreate.FileSize != int64(len(mp3Header)) {
		t.Errorf("size: got %d, want %d", repo.gotCreate.FileSize, len(mp3Header))
	}
	if repo.gotCreate.FilePath != storage.savePath {
		t.Errorf("file_path must be the stored path, got %q", repo.gotCreate.FilePath)
	}
	if got.Title != "Midnight Drive" {
		t.Errorf("returned track title: got %q", got.Title)
	}
}

// TestCreate_RejectsNonAudio couvre le test de sécurité : un contenu non-audio
// (ici un vrai PDF) est refusé en 415, aucun fichier n'est écrit ni référencé.
func TestCreate_RejectsNonAudio(t *testing.T) {
	repo := &fakeRepo{}
	storage := &stubStorage{}
	svc := NewService(repo, storage)

	_, err := svc.Create(context.Background(), CreateTrackInput{
		UserID:  testUserID,
		Title:   "Malware",
		Size:    int64(len(pdfHeader)),
		Content: bytes.NewReader(pdfHeader),
	})
	if err == nil {
		t.Fatal("expected an error for non-audio content")
	}
	var he *httpjson.Error
	if !errors.As(err, &he) || he.Status != http.StatusUnsupportedMediaType {
		t.Fatalf("expected 415 httpjson.Error, got %v", err)
	}
	if storage.saveCalled {
		t.Error("storage.Save must NOT be called for rejected content")
	}
	if repo.createCalled {
		t.Error("repo.CreateTrack must NOT be called for rejected content")
	}
}

func TestCreate_EmptyTitle(t *testing.T) {
	svc := NewService(&fakeRepo{}, &stubStorage{})
	_, err := svc.Create(context.Background(), CreateTrackInput{
		UserID:  testUserID,
		Title:   "   ",
		Size:    int64(len(mp3Header)),
		Content: bytes.NewReader(mp3Header),
	})
	if !apperror.IsCode(err, apperror.CodeInvalidArgument) {
		t.Fatalf("expected InvalidArgument, got %v", err)
	}
}

func TestCreate_InvalidDuration(t *testing.T) {
	svc := NewService(&fakeRepo{}, &stubStorage{})
	_, err := svc.Create(context.Background(), CreateTrackInput{
		UserID:    testUserID,
		Title:     "Song",
		DurationS: ptr(0),
		Size:      int64(len(mp3Header)),
		Content:   bytes.NewReader(mp3Header),
	})
	if !apperror.IsCode(err, apperror.CodeInvalidArgument) {
		t.Fatalf("expected InvalidArgument for duration<=0, got %v", err)
	}
}

// Une durée qui déborde int4 (int32) doit être rejetée en amont (400) plutôt que
// convertie en un int32 wrappé (négatif) qui violerait le CHECK duration_s > 0.
func TestCreate_DurationTooLarge(t *testing.T) {
	svc := NewService(&fakeRepo{}, &stubStorage{})
	_, err := svc.Create(context.Background(), CreateTrackInput{
		UserID:    testUserID,
		Title:     "Song",
		DurationS: ptr(math.MaxInt32 + 1),
		Size:      int64(len(mp3Header)),
		Content:   bytes.NewReader(mp3Header),
	})
	if !apperror.IsCode(err, apperror.CodeInvalidArgument) {
		t.Fatalf("expected InvalidArgument for duration>MaxInt32, got %v", err)
	}
}

func TestCreate_EmptyFile(t *testing.T) {
	svc := NewService(&fakeRepo{}, &stubStorage{})
	_, err := svc.Create(context.Background(), CreateTrackInput{
		UserID:  testUserID,
		Title:   "Song",
		Size:    0,
		Content: bytes.NewReader(nil),
	})
	if !apperror.IsCode(err, apperror.CodeInvalidArgument) {
		t.Fatalf("expected InvalidArgument for empty file, got %v", err)
	}
}

// TestCreate_RemovesOrphanOnRepoError : si l'INSERT échoue après l'écriture du
// fichier, le fichier orphelin est supprimé et l'erreur d'origine remonte.
func TestCreate_RemovesOrphanOnRepoError(t *testing.T) {
	repo := &fakeRepo{createErr: apperror.Conflict("Une piste porte déjà ce titre")}
	storage := &stubStorage{savePath: "/tmp/orphan.mp3"}
	svc := NewService(repo, storage)

	_, err := svc.Create(context.Background(), CreateTrackInput{
		UserID:  testUserID,
		Title:   "Dup",
		Size:    int64(len(mp3Header)),
		Content: bytes.NewReader(mp3Header),
	})
	if !apperror.IsCode(err, apperror.CodeConflict) {
		t.Fatalf("expected Conflict, got %v", err)
	}
	if !storage.removeCalled || storage.removedPath != "/tmp/orphan.mp3" {
		t.Errorf("orphan file must be removed, removeCalled=%v path=%q", storage.removeCalled, storage.removedPath)
	}
}

// TestCreate_QuotaExceeded : le cumul existant + le nouveau fichier dépasse le
// quota → 403 (hors bucket 5xx), rien n'est écrit ni persisté.
func TestCreate_QuotaExceeded(t *testing.T) {
	repo := &fakeRepo{sumRet: MaxUserStorageBytes} // déjà au quota
	storage := &stubStorage{}
	svc := NewService(repo, storage)

	_, err := svc.Create(context.Background(), CreateTrackInput{
		UserID:  testUserID,
		Title:   "Over quota",
		Size:    int64(len(mp3Header)),
		Content: bytes.NewReader(mp3Header),
	})
	var he *httpjson.Error
	if !errors.As(err, &he) || he.Status != http.StatusForbidden {
		t.Fatalf("expected 403 httpjson.Error, got %v", err)
	}
	if he.Code != "storage_quota_exceeded" {
		t.Errorf("code: got %q, want storage_quota_exceeded", he.Code)
	}
	if storage.saveCalled || repo.createCalled {
		t.Error("nothing must be stored when quota is exceeded")
	}
}

// TestCreate_NonAudioWinsOverQuota : au-dessus du quota, un fichier non-audio doit
// recevoir 415 (le bon diagnostic), pas 403 — detectAudio passe avant le quota.
func TestCreate_NonAudioWinsOverQuota(t *testing.T) {
	repo := &fakeRepo{sumRet: MaxUserStorageBytes} // déjà au quota
	svc := NewService(repo, &stubStorage{})

	_, err := svc.Create(context.Background(), CreateTrackInput{
		UserID:  testUserID,
		Title:   "PDF over quota",
		Size:    int64(len(pdfHeader)),
		Content: bytes.NewReader(pdfHeader),
	})
	var he *httpjson.Error
	if !errors.As(err, &he) || he.Status != http.StatusUnsupportedMediaType {
		t.Fatalf("expected 415 (not audio) to win over 403 (quota), got %v", err)
	}
}

// TestPurgeUserTracks_RemovesAfterDelete : ordre list → delete → remove. Les
// fichiers ne sont supprimés qu'APRÈS un delete réussi.
func TestPurgeUserTracks_RemovesAfterDelete(t *testing.T) {
	repo := &fakeRepo{pathsRet: []string{"/data/tracks/a.mp3", "/data/tracks/b.ogg"}}
	storage := &recordingStorage{}
	svc := NewService(repo, storage)

	deleted := false
	err := svc.PurgeUserTracks(context.Background(), testUserID, func() error {
		// Au moment du delete, aucun fichier ne doit encore avoir été supprimé.
		if len(storage.removed) != 0 {
			t.Error("files must not be removed before the account delete")
		}
		deleted = true
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !deleted {
		t.Fatal("deleteUser must be called")
	}
	if len(storage.removed) != 2 {
		t.Fatalf("expected 2 files removed after delete, got %v", storage.removed)
	}
}

// TestPurgeUserTracks_DeleteFails_KeepsFiles : si le delete échoue, aucun fichier
// n'est supprimé (pas de ligne fantôme) et l'erreur remonte.
func TestPurgeUserTracks_DeleteFails_KeepsFiles(t *testing.T) {
	repo := &fakeRepo{pathsRet: []string{"/data/tracks/a.mp3"}}
	storage := &recordingStorage{}
	svc := NewService(repo, storage)

	wantErr := errors.New("delete failed")
	err := svc.PurgeUserTracks(context.Background(), testUserID, func() error {
		return wantErr
	})
	if !errors.Is(err, wantErr) {
		t.Fatalf("delete error must propagate, got %v", err)
	}
	if len(storage.removed) != 0 {
		t.Errorf("no file must be removed when delete fails, got %v", storage.removed)
	}
}

// recordingStorage capture les chemins supprimés (Save non utilisé ici).
type recordingStorage struct {
	removed []string
}

func (s *recordingStorage) Save(_ context.Context, _, _ string, _ io.Reader) (string, error) {
	return "", nil
}

func (s *recordingStorage) Remove(path string) error {
	s.removed = append(s.removed, path)
	return nil
}
