package streaming

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

func strptr(s string) *string { return &s }

func TestCreateStreamInput_validate(t *testing.T) {
	tests := []struct {
		name     string
		in       CreateStreamInput
		wantErr  bool
		checkOut func(t *testing.T, out CreateStreamInput)
	}{
		{
			name: "valide minimal",
			in:   CreateStreamInput{UserID: "u1", Title: "abc", IsPublic: true},
			checkOut: func(t *testing.T, out CreateStreamInput) {
				if out.Title != "abc" || !out.IsPublic {
					t.Errorf("out = %+v", out)
				}
				if out.Description != nil || out.Category != nil {
					t.Errorf("optionnels devraient être nil: %+v", out)
				}
			},
		},
		{
			name: "titre trimé",
			in:   CreateStreamInput{Title: "  Mon flux  "},
			checkOut: func(t *testing.T, out CreateStreamInput) {
				if out.Title != "Mon flux" {
					t.Errorf("title = %q, want %q", out.Title, "Mon flux")
				}
			},
		},
		{
			name:    "titre trop court",
			in:      CreateStreamInput{Title: "ab"},
			wantErr: true,
		},
		{
			name:    "titre espaces uniquement",
			in:      CreateStreamInput{Title: "    "},
			wantErr: true,
		},
		{
			name:    "titre trop long",
			in:      CreateStreamInput{Title: strings.Repeat("a", MaxTitleLen+1)},
			wantErr: true,
		},
		{
			name: "titre longueur max acceptée",
			in:   CreateStreamInput{Title: strings.Repeat("a", MaxTitleLen)},
		},
		{
			name: "description vide ramenée à nil",
			in:   CreateStreamInput{Title: "abc", Description: strptr("   ")},
			checkOut: func(t *testing.T, out CreateStreamInput) {
				if out.Description != nil {
					t.Errorf("description = %v, want nil", *out.Description)
				}
			},
		},
		{
			name: "description valide trimée",
			in:   CreateStreamInput{Title: "abc", Description: strptr("  hello  ")},
			checkOut: func(t *testing.T, out CreateStreamInput) {
				if out.Description == nil || *out.Description != "hello" {
					t.Errorf("description = %v, want hello", out.Description)
				}
			},
		},
		{
			name:    "description trop longue",
			in:      CreateStreamInput{Title: "abc", Description: strptr(strings.Repeat("a", MaxDescriptionLen+1))},
			wantErr: true,
		},
		{
			name: "category valide",
			in:   CreateStreamInput{Title: "abc", Category: strptr("music")},
			checkOut: func(t *testing.T, out CreateStreamInput) {
				if out.Category == nil || *out.Category != "music" {
					t.Errorf("category = %v, want music", out.Category)
				}
			},
		},
		{
			name:    "category hors liste blanche",
			in:      CreateStreamInput{Title: "abc", Category: strptr("politique")},
			wantErr: true,
		},
		{
			name: "category vide ramenée à nil",
			in:   CreateStreamInput{Title: "abc", Category: strptr("  ")},
			checkOut: func(t *testing.T, out CreateStreamInput) {
				if out.Category != nil {
					t.Errorf("category = %v, want nil", *out.Category)
				}
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			out, err := tc.in.validate()
			if tc.wantErr {
				if err == nil {
					t.Fatal("attendu une erreur, obtenu nil")
				}
				if !apperror.IsCode(err, apperror.CodeInvalidArgument) {
					t.Fatalf("code = %v, want invalid_argument", err)
				}
				return
			}
			if err != nil {
				t.Fatalf("erreur inattendue: %v", err)
			}
			if tc.checkOut != nil {
				tc.checkOut(t, out)
			}
		})
	}
}

type fakeRepo struct {
	called    bool
	gotParams CreateParams
	ret       Stream
	err       error

	gotLimit  int32
	gotOffset int32
	listRet   []Stream
	listErr   error

	gotID      string
	getRet     Stream
	getErr     error
	gotUpdate  UpdateParams
	updateRet  Stream
	updateErr  error
	archiveErr error
}

func (f *fakeRepo) Create(_ context.Context, p CreateParams) (Stream, error) {
	f.called = true
	f.gotParams = p
	return f.ret, f.err
}

func (f *fakeRepo) ListPublicLive(_ context.Context, limit, offset int32) ([]Stream, error) {
	f.gotLimit = limit
	f.gotOffset = offset
	return f.listRet, f.listErr
}

func (f *fakeRepo) GetByID(_ context.Context, id string) (Stream, error) {
	f.gotID = id
	return f.getRet, f.getErr
}

func (f *fakeRepo) Update(_ context.Context, p UpdateParams) (Stream, error) {
	f.gotUpdate = p
	return f.updateRet, f.updateErr
}

func (f *fakeRepo) Archive(_ context.Context, id, _ string) error {
	f.gotID = id
	return f.archiveErr
}

type fakeKeys struct {
	key string
	err error
}

func (f fakeKeys) NewStreamKey() (string, error) { return f.key, f.err }

func TestService_CreateStream_Success(t *testing.T) {
	repo := &fakeRepo{ret: Stream{ID: "s1", Title: "Mon flux"}}
	svc := NewService(repo, fakeKeys{key: "SECRET_KEY"})

	got, err := svc.CreateStream(context.Background(), CreateStreamInput{
		UserID:   "u1",
		Title:    "  Mon flux  ",
		IsPublic: true,
	})
	if err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if !repo.called {
		t.Fatal("repo.Create n'a pas été appelé")
	}
	if repo.gotParams.Status != StatusIdle {
		t.Errorf("status = %q, want idle", repo.gotParams.Status)
	}
	if repo.gotParams.StreamKey != "SECRET_KEY" {
		t.Errorf("stream_key = %q, want SECRET_KEY", repo.gotParams.StreamKey)
	}
	if repo.gotParams.Title != "Mon flux" {
		t.Errorf("title = %q (devrait être trimé)", repo.gotParams.Title)
	}
	if repo.gotParams.UserID != "u1" {
		t.Errorf("user_id = %q, want u1", repo.gotParams.UserID)
	}
	if got.ID != "s1" {
		t.Errorf("stream renvoyé = %+v", got)
	}
}

func TestService_CreateStream_ValidationError_NoRepoCall(t *testing.T) {
	repo := &fakeRepo{}
	svc := NewService(repo, fakeKeys{key: "K"})

	_, err := svc.CreateStream(context.Background(), CreateStreamInput{Title: "ab"})
	if !apperror.IsCode(err, apperror.CodeInvalidArgument) {
		t.Fatalf("code = %v, want invalid_argument", err)
	}
	if repo.called {
		t.Error("repo.Create ne devrait pas être appelé si la validation échoue")
	}
}

func TestService_CreateStream_KeyGenError(t *testing.T) {
	repo := &fakeRepo{}
	svc := NewService(repo, fakeKeys{err: errors.New("rand failed")})

	_, err := svc.CreateStream(context.Background(), CreateStreamInput{Title: "abc"})
	if !apperror.IsCode(err, apperror.CodeInternal) {
		t.Fatalf("code = %v, want internal", err)
	}
	if repo.called {
		t.Error("repo.Create ne devrait pas être appelé si la génération de clé échoue")
	}
}

func TestService_CreateStream_RepoErrorPropagated(t *testing.T) {
	repo := &fakeRepo{err: apperror.Conflict("title already used")}
	svc := NewService(repo, fakeKeys{key: "K"})

	_, err := svc.CreateStream(context.Background(), CreateStreamInput{Title: "abc"})
	if !apperror.IsCode(err, apperror.CodeConflict) {
		t.Fatalf("code = %v, want conflict", err)
	}
}

func TestService_ListPublicLive_DelegatesToRepo(t *testing.T) {
	repo := &fakeRepo{listRet: []Stream{{ID: "s1"}, {ID: "s2"}}}
	svc := NewService(repo, fakeKeys{})

	got, err := svc.ListPublicLive(context.Background(), 20, 40)
	if err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if len(got) != 2 {
		t.Errorf("len = %d, want 2", len(got))
	}
	if repo.gotLimit != 20 || repo.gotOffset != 40 {
		t.Errorf("pagination transmise = (%d, %d), want (20, 40)", repo.gotLimit, repo.gotOffset)
	}
}

func TestService_GetStream_Owner(t *testing.T) {
	repo := &fakeRepo{getRet: Stream{ID: "s1", UserID: "u1", IsPublic: false}}
	svc := NewService(repo, fakeKeys{})

	s, isOwner, err := svc.GetStream(context.Background(), "s1", "u1")
	if err != nil || !isOwner || s.ID != "s1" {
		t.Fatalf("owner: (%+v, %v, %v)", s, isOwner, err)
	}
}

func TestService_GetStream_PublicNonOwner(t *testing.T) {
	repo := &fakeRepo{getRet: Stream{ID: "s1", UserID: "u1", IsPublic: true}}
	svc := NewService(repo, fakeKeys{})

	_, isOwner, err := svc.GetStream(context.Background(), "s1", "u2")
	if err != nil || isOwner {
		t.Fatalf("public non-owner: isOwner=%v err=%v", isOwner, err)
	}
}

func TestService_GetStream_PrivateNonOwner_NotFound(t *testing.T) {
	repo := &fakeRepo{getRet: Stream{ID: "s1", UserID: "u1", IsPublic: false}}
	svc := NewService(repo, fakeKeys{})

	_, _, err := svc.GetStream(context.Background(), "s1", "u2")
	if !apperror.IsCode(err, apperror.CodeNotFound) {
		t.Fatalf("code = %v, want not_found", err)
	}
}

func TestService_UpdateStream_ValidationError(t *testing.T) {
	repo := &fakeRepo{}
	svc := NewService(repo, fakeKeys{})

	_, err := svc.UpdateStream(context.Background(), "s1", "u1", UpdateStreamInput{Title: "ab"})
	if !apperror.IsCode(err, apperror.CodeInvalidArgument) {
		t.Fatalf("code = %v, want invalid_argument", err)
	}
	if repo.gotUpdate.ID != "" {
		t.Error("repo.Update ne devrait pas être appelé si la validation échoue")
	}
}

func TestService_UpdateStream_DelegatesOwnerScope(t *testing.T) {
	repo := &fakeRepo{updateRet: Stream{ID: "s1"}}
	svc := NewService(repo, fakeKeys{})

	_, err := svc.UpdateStream(context.Background(), "s1", "u1", UpdateStreamInput{Title: "Nouveau", IsPublic: true})
	if err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if repo.gotUpdate.ID != "s1" || repo.gotUpdate.UserID != "u1" || repo.gotUpdate.Title != "Nouveau" {
		t.Errorf("update transmis = %+v", repo.gotUpdate)
	}
}

func TestService_ArchiveStream_Delegates(t *testing.T) {
	repo := &fakeRepo{archiveErr: apperror.NotFound("stream not found")}
	svc := NewService(repo, fakeKeys{})

	err := svc.ArchiveStream(context.Background(), "s1", "u1")
	if !apperror.IsCode(err, apperror.CodeNotFound) {
		t.Fatalf("code = %v, want not_found", err)
	}
	if repo.gotID != "s1" {
		t.Errorf("id transmis = %q, want s1", repo.gotID)
	}
}
