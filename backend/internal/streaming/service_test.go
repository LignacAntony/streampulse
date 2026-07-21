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

	startRet Stream
	startErr error
	stopRet  Stream
	stopErr  error

	orphanEnded int64
	orphanErr   error

	addFavCalled    bool
	removeFavCalled bool
	favUserID       string
	favStreamID     string
	addFavErr       error
	removeFavErr    error
	listFavRet      []Stream
	listFavErr      error

	gotStopLiveForUserID string
	stopLiveForUserIDs   []string
	stopLiveForUserErr   error
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

func (f *fakeRepo) Archive(_ context.Context, id, _ string) (string, error) {
	f.gotID = id
	if f.archiveErr != nil {
		return "", f.archiveErr
	}
	return id, nil
}

func (f *fakeRepo) StartStream(_ context.Context, id, _ string) (Stream, error) {
	f.gotID = id
	return f.startRet, f.startErr
}

func (f *fakeRepo) StopStream(_ context.Context, id, _ string) (Stream, error) {
	f.gotID = id
	return f.stopRet, f.stopErr
}

func (f *fakeRepo) EndOrphanLiveStreams(_ context.Context) (int64, error) {
	return f.orphanEnded, f.orphanErr
}

func (f *fakeRepo) AddFavorite(_ context.Context, userID, streamID string) error {
	f.addFavCalled = true
	f.favUserID = userID
	f.favStreamID = streamID
	return f.addFavErr
}

func (f *fakeRepo) RemoveFavorite(_ context.Context, userID, streamID string) error {
	f.removeFavCalled = true
	f.favUserID = userID
	f.favStreamID = streamID
	return f.removeFavErr
}

func (f *fakeRepo) ListFavorites(_ context.Context, userID string) ([]Stream, error) {
	f.favUserID = userID
	return f.listFavRet, f.listFavErr
}

func (f *fakeRepo) StopLiveStreamsByUser(_ context.Context, userID string) ([]string, error) {
	f.gotStopLiveForUserID = userID
	return f.stopLiveForUserIDs, f.stopLiveForUserErr
}

type fakeKeys struct {
	key string
	err error
}

func (f fakeKeys) NewStreamKey() (string, error) { return f.key, f.err }

type fakeSessions struct {
	started     []string
	startedKeys []string
	stopped     []string
}

func (f *fakeSessions) Start(id, key string) {
	f.started = append(f.started, id)
	f.startedKeys = append(f.startedKeys, key)
}
func (f *fakeSessions) Stop(id string) { f.stopped = append(f.stopped, id) }

func TestService_CreateStream_Success(t *testing.T) {
	repo := &fakeRepo{ret: Stream{ID: "s1", Title: "Mon flux"}}
	svc := NewService(repo, fakeKeys{key: "SECRET_KEY"}, &fakeSessions{})

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
	svc := NewService(repo, fakeKeys{key: "K"}, &fakeSessions{})

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
	svc := NewService(repo, fakeKeys{err: errors.New("rand failed")}, &fakeSessions{})

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
	svc := NewService(repo, fakeKeys{key: "K"}, &fakeSessions{})

	_, err := svc.CreateStream(context.Background(), CreateStreamInput{Title: "abc"})
	if !apperror.IsCode(err, apperror.CodeConflict) {
		t.Fatalf("code = %v, want conflict", err)
	}
}

func TestService_ListPublicLive_DelegatesToRepo(t *testing.T) {
	repo := &fakeRepo{listRet: []Stream{{ID: "s1"}, {ID: "s2"}}}
	svc := NewService(repo, fakeKeys{}, &fakeSessions{})

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
	svc := NewService(repo, fakeKeys{}, &fakeSessions{})

	s, isOwner, err := svc.GetStream(context.Background(), "s1", "u1")
	if err != nil || !isOwner || s.ID != "s1" {
		t.Fatalf("owner: (%+v, %v, %v)", s, isOwner, err)
	}
}

func TestService_GetStream_PublicNonOwner(t *testing.T) {
	repo := &fakeRepo{getRet: Stream{ID: "s1", UserID: "u1", IsPublic: true}}
	svc := NewService(repo, fakeKeys{}, &fakeSessions{})

	_, isOwner, err := svc.GetStream(context.Background(), "s1", "u2")
	if err != nil || isOwner {
		t.Fatalf("public non-owner: isOwner=%v err=%v", isOwner, err)
	}
}

func TestService_GetStream_PrivateNonOwner_NotFound(t *testing.T) {
	repo := &fakeRepo{getRet: Stream{ID: "s1", UserID: "u1", IsPublic: false}}
	svc := NewService(repo, fakeKeys{}, &fakeSessions{})

	_, _, err := svc.GetStream(context.Background(), "s1", "u2")
	if !apperror.IsCode(err, apperror.CodeNotFound) {
		t.Fatalf("code = %v, want not_found", err)
	}
}

// TestService_GetStream_Anonymous : un demandeur anonyme (requesterID = "") — cas
// central de la lecture publique HLS (STR-108) — obtient les flux publics et un 404
// sur les flux privés (jamais propriétaire de "").
func TestService_GetStream_Anonymous(t *testing.T) {
	t.Run("flux public servi", func(t *testing.T) {
		repo := &fakeRepo{getRet: Stream{ID: "s1", UserID: "u1", IsPublic: true}}
		svc := NewService(repo, fakeKeys{}, &fakeSessions{})

		got, isOwner, err := svc.GetStream(context.Background(), "s1", "")
		if err != nil {
			t.Fatalf("flux public anonyme: erreur inattendue %v", err)
		}
		if isOwner {
			t.Error("un anonyme ne doit jamais être propriétaire")
		}
		if got.ID != "s1" {
			t.Errorf("stream = %+v, want id s1", got)
		}
	})

	t.Run("flux privé -> 404", func(t *testing.T) {
		repo := &fakeRepo{getRet: Stream{ID: "s1", UserID: "u1", IsPublic: false}}
		svc := NewService(repo, fakeKeys{}, &fakeSessions{})

		_, _, err := svc.GetStream(context.Background(), "s1", "")
		if !apperror.IsCode(err, apperror.CodeNotFound) {
			t.Fatalf("flux privé anonyme: code = %v, want not_found", err)
		}
	})
}

func TestService_UpdateStream_ValidationError(t *testing.T) {
	repo := &fakeRepo{}
	svc := NewService(repo, fakeKeys{}, &fakeSessions{})

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
	svc := NewService(repo, fakeKeys{}, &fakeSessions{})

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
	svc := NewService(repo, fakeKeys{}, &fakeSessions{})

	err := svc.ArchiveStream(context.Background(), "s1", "u1")
	if !apperror.IsCode(err, apperror.CodeNotFound) {
		t.Fatalf("code = %v, want not_found", err)
	}
	if repo.gotID != "s1" {
		t.Errorf("id transmis = %q, want s1", repo.gotID)
	}
}

func TestService_ArchiveStream_StopsSession(t *testing.T) {
	repo := &fakeRepo{} // archiveErr nil -> succès, renvoie l'id
	sessions := &fakeSessions{}
	svc := NewService(repo, fakeKeys{}, sessions)

	if err := svc.ArchiveStream(context.Background(), "s1", "u1"); err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if len(sessions.stopped) != 1 || sessions.stopped[0] != "s1" {
		t.Errorf("archive doit stopper la session du flux: %v", sessions.stopped)
	}
}

func TestService_StartStream_Success(t *testing.T) {
	repo := &fakeRepo{startRet: Stream{ID: "s1", Status: StatusLive}}
	sessions := &fakeSessions{}
	svc := NewService(repo, fakeKeys{}, sessions)

	got, err := svc.StartStream(context.Background(), "s1", "u1")
	if err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if got.Status != StatusLive {
		t.Errorf("status = %q, want live", got.Status)
	}
	if len(sessions.started) != 1 || sessions.started[0] != "s1" {
		t.Errorf("session non démarrée: %v", sessions.started)
	}
}

func TestService_StartStream_NotIdle_Conflict(t *testing.T) {
	repo := &fakeRepo{startErr: errNoRowAffected, getRet: Stream{UserID: "u1", Status: StatusLive}}
	sessions := &fakeSessions{}
	svc := NewService(repo, fakeKeys{}, sessions)

	_, err := svc.StartStream(context.Background(), "s1", "u1")
	if !apperror.IsCode(err, apperror.CodeConflict) {
		t.Fatalf("code = %v, want conflict", err)
	}
	if len(sessions.started) != 0 {
		t.Error("aucune session ne doit démarrer sur échec")
	}
}

func TestService_StartStream_AlreadyLive_Conflict(t *testing.T) {
	repo := &fakeRepo{startErr: errNoRowAffected, getRet: Stream{UserID: "u1", Status: StatusIdle}}
	svc := NewService(repo, fakeKeys{}, &fakeSessions{})

	_, err := svc.StartStream(context.Background(), "s1", "u1")
	if !apperror.IsCode(err, apperror.CodeConflict) {
		t.Fatalf("code = %v, want conflict (déjà un live)", err)
	}
}

func TestService_StartStream_NotOwner_NotFound(t *testing.T) {
	repo := &fakeRepo{startErr: errNoRowAffected, getRet: Stream{UserID: "autre", Status: StatusIdle}}
	svc := NewService(repo, fakeKeys{}, &fakeSessions{})

	_, err := svc.StartStream(context.Background(), "s1", "u1")
	if !apperror.IsCode(err, apperror.CodeNotFound) {
		t.Fatalf("code = %v, want not_found", err)
	}
}

func TestService_StopStream_Success(t *testing.T) {
	repo := &fakeRepo{stopRet: Stream{ID: "s1", Status: StatusEnded}}
	sessions := &fakeSessions{}
	svc := NewService(repo, fakeKeys{}, sessions)

	if _, err := svc.StopStream(context.Background(), "s1", "u1"); err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if len(sessions.stopped) != 1 || sessions.stopped[0] != "s1" {
		t.Errorf("session non arrêtée: %v", sessions.stopped)
	}
}

func TestService_StopStream_NotLive_Conflict(t *testing.T) {
	repo := &fakeRepo{stopErr: errNoRowAffected, getRet: Stream{UserID: "u1", Status: StatusIdle}}
	svc := NewService(repo, fakeKeys{}, &fakeSessions{})

	_, err := svc.StopStream(context.Background(), "s1", "u1")
	if !apperror.IsCode(err, apperror.CodeConflict) {
		t.Fatalf("code = %v, want conflict", err)
	}
}

func TestService_StartStream_AlreadyLive_UniqueViolation(t *testing.T) {
	// L'index unique partiel rejette un 2e live concurrent -> errStreamAlreadyLive.
	repo := &fakeRepo{startErr: errStreamAlreadyLive}
	sessions := &fakeSessions{}
	svc := NewService(repo, fakeKeys{}, sessions)

	_, err := svc.StartStream(context.Background(), "s1", "u1")
	if !apperror.IsCode(err, apperror.CodeConflict) {
		t.Fatalf("code = %v, want conflict (déjà un live)", err)
	}
	if len(sessions.started) != 0 {
		t.Error("aucune session ne doit démarrer sur échec")
	}
}

func TestService_ReconcileLiveStreams(t *testing.T) {
	repo := &fakeRepo{orphanEnded: 3}
	svc := NewService(repo, fakeKeys{}, &fakeSessions{})

	n, err := svc.ReconcileLiveStreams(context.Background())
	if err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if n != 3 {
		t.Errorf("n = %d, want 3", n)
	}
}

func TestService_AddFavorite_PublicOK(t *testing.T) {
	repo := &fakeRepo{getRet: Stream{ID: "s1", UserID: "u1", IsPublic: true}}
	svc := NewService(repo, fakeKeys{}, &fakeSessions{})

	if err := svc.AddFavorite(context.Background(), "s1", "u2"); err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if !repo.addFavCalled {
		t.Error("repo.AddFavorite devrait être appelé")
	}
	if repo.favUserID != "u2" || repo.favStreamID != "s1" {
		t.Errorf("args = (%q, %q), want (u2, s1)", repo.favUserID, repo.favStreamID)
	}
}

func TestService_AddFavorite_OwnPrivateOK(t *testing.T) {
	repo := &fakeRepo{getRet: Stream{ID: "s1", UserID: "u1", IsPublic: false}}
	svc := NewService(repo, fakeKeys{}, &fakeSessions{})

	if err := svc.AddFavorite(context.Background(), "s1", "u1"); err != nil {
		t.Fatalf("le propriétaire peut favoriser son flux privé: %v", err)
	}
	if !repo.addFavCalled {
		t.Error("repo.AddFavorite devrait être appelé")
	}
}

func TestService_AddFavorite_PrivateThirdParty_NotFound(t *testing.T) {
	repo := &fakeRepo{getRet: Stream{ID: "s1", UserID: "u1", IsPublic: false}}
	svc := NewService(repo, fakeKeys{}, &fakeSessions{})

	err := svc.AddFavorite(context.Background(), "s1", "u2")
	if !apperror.IsCode(err, apperror.CodeNotFound) {
		t.Fatalf("code = %v, want not_found", err)
	}
	if repo.addFavCalled {
		t.Error("repo.AddFavorite ne doit pas être appelé sur flux non visible")
	}
}

func TestService_AddFavorite_UnknownStream_NotFound(t *testing.T) {
	repo := &fakeRepo{getErr: apperror.NotFound("stream not found")}
	svc := NewService(repo, fakeKeys{}, &fakeSessions{})

	err := svc.AddFavorite(context.Background(), "s1", "u2")
	if !apperror.IsCode(err, apperror.CodeNotFound) {
		t.Fatalf("code = %v, want not_found", err)
	}
	if repo.addFavCalled {
		t.Error("repo.AddFavorite ne doit pas être appelé pour un flux inexistant")
	}
}

func TestService_RemoveFavorite_NoVisibilityCheck(t *testing.T) {
	// Le retrait est idempotent et ne vérifie pas la visibilité (pas de GetStream).
	repo := &fakeRepo{}
	svc := NewService(repo, fakeKeys{}, &fakeSessions{})

	if err := svc.RemoveFavorite(context.Background(), "s1", "u2"); err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if !repo.removeFavCalled {
		t.Error("repo.RemoveFavorite devrait être appelé")
	}
	if repo.favUserID != "u2" || repo.favStreamID != "s1" {
		t.Errorf("args = (%q, %q), want (u2, s1)", repo.favUserID, repo.favStreamID)
	}
}

func TestService_ListFavorites(t *testing.T) {
	repo := &fakeRepo{listFavRet: []Stream{{ID: "s1"}, {ID: "s2"}}}
	svc := NewService(repo, fakeKeys{}, &fakeSessions{})

	got, err := svc.ListFavorites(context.Background(), "u1")
	if err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if len(got) != 2 || repo.favUserID != "u1" {
		t.Errorf("got = %+v, favUserID = %q", got, repo.favUserID)
	}
}

// 1. StopLiveForUser avec des lives en cours : transition DB déjà faite par la
// query (repo), puis chaque id renvoyé doit stopper sa session in-memory.
func TestService_StopLiveForUser_StopsSessions(t *testing.T) {
	repo := &fakeRepo{stopLiveForUserIDs: []string{"s1", "s2"}}
	sessions := &fakeSessions{}
	svc := NewService(repo, fakeKeys{}, sessions)

	err := svc.StopLiveForUser(context.Background(), "u1")
	if err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if repo.gotStopLiveForUserID != "u1" {
		t.Errorf("user_id transmis = %q, want u1", repo.gotStopLiveForUserID)
	}
	if len(sessions.stopped) != 2 || sessions.stopped[0] != "s1" || sessions.stopped[1] != "s2" {
		t.Errorf("sessions arrêtées = %v, want [s1 s2]", sessions.stopped)
	}
}

// 2. StopLiveForUser sur un utilisateur sans live : no-op, aucune session stoppée.
func TestService_StopLiveForUser_NoLiveStreams_NoOp(t *testing.T) {
	repo := &fakeRepo{stopLiveForUserIDs: nil}
	sessions := &fakeSessions{}
	svc := NewService(repo, fakeKeys{}, sessions)

	err := svc.StopLiveForUser(context.Background(), "u1")
	if err != nil {
		t.Fatalf("erreur inattendue: %v", err)
	}
	if len(sessions.stopped) != 0 {
		t.Errorf("aucune session ne devrait être stoppée: %v", sessions.stopped)
	}
}

// 3. StopLiveForUser : une erreur du repo est propagée et aucune session n'est
// stoppée (la boucle sur les ids n'est jamais atteinte).
func TestService_StopLiveForUser_RepoError_Propagates(t *testing.T) {
	repoErr := errors.New("db unavailable")
	repo := &fakeRepo{stopLiveForUserErr: repoErr}
	sessions := &fakeSessions{}
	svc := NewService(repo, fakeKeys{}, sessions)

	err := svc.StopLiveForUser(context.Background(), "u1")
	if !errors.Is(err, repoErr) {
		t.Fatalf("erreur non propagée: %v", err)
	}
	if len(sessions.stopped) != 0 {
		t.Errorf("aucune session ne devrait être stoppée sur erreur repo: %v", sessions.stopped)
	}
}
