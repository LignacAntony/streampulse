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
}

func (f *fakeRepo) Create(_ context.Context, p CreateParams) (Stream, error) {
	f.called = true
	f.gotParams = p
	return f.ret, f.err
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
