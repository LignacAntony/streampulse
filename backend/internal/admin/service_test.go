package admin

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

const (
	testRequesterID   = "00000000-0000-0000-0000-0000000000ad" // admin qui exécute l'action
	testTargetUserID  = "00000000-0000-0000-0000-000000000001" // cible : simple utilisateur
	testTargetAdminID = "00000000-0000-0000-0000-000000000002" // cible : un autre admin actif
	testUnknownID     = "00000000-0000-0000-0000-000000000dea" // cible absente de la map

	// testFoldRequesterID / testFoldTargetIDUpper : même UUID que le requester,
	// mais la cible est fournie en MAJUSCULES (cf. tests self-action insensibles
	// à la casse — pgtype.UUID scanne les deux graphies vers les mêmes octets).
	testFoldRequesterID   = "a1b2c3d4-0000-0000-0000-00000000000f"
	testFoldTargetIDUpper = "A1B2C3D4-0000-0000-0000-00000000000F"

	// testStreamID : flux ciblé par les tests StopStream/ListLiveStreams (STR-192).
	testStreamID = "00000000-0000-0000-0000-000000000042"
)

// fakeRepo est un Repository en mémoire (map indexée par ID) pour les tests du
// service. Les compteurs (getUserCalls, deleteCalls, listCalled) permettent de
// vérifier qu'un appel repo a bien (ou n'a pas) eu lieu.
type fakeRepo struct {
	users            map[string]AdminUser
	activeAdminCount int64

	listCalled int
	listInput  ListUsersInput
	listUsers  []AdminUser
	listTotal  int64

	getUserCalls int

	deleteCalls int

	// listStreamsCalled/Limit/Offset : capture des paramètres transmis à
	// ListLiveStreams (STR-192), même rôle que listCalled/listInput pour ListUsers.
	listStreamsCalled int
	listStreamsLimit  int32
	listStreamsOffset int32
	listStreams       []AdminStream
	listStreamsTotal  int64

	// auditCalls/gotAudit* : capture des paramètres transmis à InsertAuditLog
	// (STR-192) ; auditErr simule un échec d'écriture du journal (cas best-effort).
	auditCalls     int
	auditErr       error
	gotAuditActor  string
	gotAuditAction string
	gotAuditType   string
	gotAuditTarget string

	// order trace, dans l'ordre d'appel, les opérations effectuées par ce repo
	// et par le fakeStopper/fakeModerator partagés dans le même test (cf. cas 7 :
	// stop avant delete ; cas StopStream : moderator avant audit).
	order *[]string
}

func (f *fakeRepo) ListUsers(_ context.Context, in ListUsersInput) ([]AdminUser, int64, error) {
	f.listCalled++
	f.listInput = in
	return f.listUsers, f.listTotal, nil
}

func (f *fakeRepo) GetUser(_ context.Context, userID string) (AdminUser, error) {
	f.getUserCalls++
	u, ok := f.users[userID]
	if !ok {
		return AdminUser{}, apperror.NotFound("user not found")
	}
	return u, nil
}

func (f *fakeRepo) SetUserActive(_ context.Context, userID string, active bool) (AdminUser, error) {
	u, ok := f.users[userID]
	if !ok {
		return AdminUser{}, apperror.NotFound("user not found")
	}
	u.IsActive = active
	f.users[userID] = u
	return u, nil
}

func (f *fakeRepo) CountActiveAdmins(_ context.Context) (int64, error) {
	return f.activeAdminCount, nil
}

func (f *fakeRepo) DeleteUser(_ context.Context, userID string) error {
	f.deleteCalls++
	if f.order != nil {
		*f.order = append(*f.order, "repo.DeleteUser:"+userID)
	}
	delete(f.users, userID)
	return nil
}

// ListLiveStreams (STR-192) : miroir de ListUsers, capture limit/offset et
// renvoie les valeurs préparées par le test.
func (f *fakeRepo) ListLiveStreams(_ context.Context, limit, offset int32) ([]AdminStream, int64, error) {
	f.listStreamsCalled++
	f.listStreamsLimit = limit
	f.listStreamsOffset = offset
	return f.listStreams, f.listStreamsTotal, nil
}

// InsertAuditLog (STR-192) : capture les 4 paramètres et trace l'appel dans
// order (cf. TestService_StopStream_OK_StopsThenAudits) ; auditErr simule un
// échec d'écriture best-effort (cf. TestService_StopStream_AuditError_*).
func (f *fakeRepo) InsertAuditLog(_ context.Context, actorID, action, targetType, targetID string) error {
	f.auditCalls++
	f.gotAuditActor = actorID
	f.gotAuditAction = action
	f.gotAuditType = targetType
	f.gotAuditTarget = targetID
	if f.order != nil {
		*f.order = append(*f.order, "repo.InsertAuditLog:"+targetID)
	}
	return f.auditErr
}

// fakeStopper enregistre l'erreur à renvoyer (cas 8) et participe à la trace
// d'ordre partagée avec fakeRepo (cas 7).
type fakeStopper struct {
	err   error
	order *[]string
}

func (f *fakeStopper) StopLiveForUser(_ context.Context, userID string) error {
	if f.order != nil {
		*f.order = append(*f.order, "stopper.StopLiveForUser:"+userID)
	}
	return f.err
}

// fakeModerator est un StreamModerator en mémoire (STR-192) : err simule un
// échec de ForceStopStream (ex. 409 flux pas live) ; order participe à la
// trace partagée avec fakeRepo pour vérifier l'ordre moderator -> audit.
type fakeModerator struct {
	err   error
	order *[]string

	forceStopCalls int
	gotStreamID    string
}

func (f *fakeModerator) ForceStopStream(_ context.Context, streamID string) error {
	f.forceStopCalls++
	f.gotStreamID = streamID
	if f.order != nil {
		*f.order = append(*f.order, "moderator.ForceStopStream:"+streamID)
	}
	return f.err
}

// seededRepo pré-remplit trois comptes : l'admin requêteur, un simple
// utilisateur cible, et un second admin cible (utile pour les gardes
// dernier-admin-actif). activeAdminCount vaut 2 par défaut (les deux admins).
func seededRepo() *fakeRepo {
	return &fakeRepo{
		users: map[string]AdminUser{
			testRequesterID:   {ID: testRequesterID, Email: "root@streampulse.dev", Username: "root", Role: "admin", IsActive: true},
			testTargetUserID:  {ID: testTargetUserID, Email: "user1@streampulse.dev", Username: "user1", Role: "user", IsActive: true},
			testTargetAdminID: {ID: testTargetAdminID, Email: "admin2@streampulse.dev", Username: "admin2", Role: "admin", IsActive: true},
		},
		activeAdminCount: 2,
	}
}

// 1. ListUsers passe les filtres au repo et renvoie le total.
func TestService_ListUsers_PassesFiltersAndReturnsTotal(t *testing.T) {
	repo := &fakeRepo{
		listUsers: []AdminUser{{ID: testTargetUserID, Username: "user1"}},
		listTotal: 42,
	}
	in := ListUsersInput{Search: "user", Role: "user", Status: "active", Limit: 20, Offset: 10}

	users, total, err := NewService(repo, &fakeStopper{}, &fakeModerator{}).ListUsers(context.Background(), in)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if repo.listCalled != 1 {
		t.Fatalf("want 1 call to repo.ListUsers, got %d", repo.listCalled)
	}
	if repo.listInput != in {
		t.Errorf("filters not passed through: got %+v, want %+v", repo.listInput, in)
	}
	if total != 42 {
		t.Errorf("total not returned: got %d", total)
	}
	if len(users) != 1 || users[0].ID != testTargetUserID {
		t.Errorf("users not returned: %+v", users)
	}
}

// 2. SetUserActive(target==requester) -> Conflict (self-action), sans appel repo.
func TestService_SetUserActive_SelfAction(t *testing.T) {
	repo := seededRepo()
	_, err := NewService(repo, &fakeStopper{}, &fakeModerator{}).SetUserActive(context.Background(), testRequesterID, testRequesterID, false)
	if !apperror.IsCode(err, apperror.CodeConflict) {
		t.Fatalf("want conflict, got %v", err)
	}
	if repo.getUserCalls != 0 {
		t.Errorf("repo must not be called on self-action")
	}
}

// 3. SetUserActive(false) sur le dernier admin actif -> Conflict ; sur un admin
// parmi deux actifs -> OK.
func TestService_SetUserActive_LastActiveAdmin(t *testing.T) {
	t.Run("dernier admin actif", func(t *testing.T) {
		repo := seededRepo()
		repo.activeAdminCount = 1
		_, err := NewService(repo, &fakeStopper{}, &fakeModerator{}).SetUserActive(context.Background(), testTargetAdminID, testRequesterID, false)
		if !apperror.IsCode(err, apperror.CodeConflict) {
			t.Fatalf("want conflict, got %v", err)
		}
	})

	t.Run("un admin parmi deux actifs", func(t *testing.T) {
		repo := seededRepo()
		repo.activeAdminCount = 2
		got, err := NewService(repo, &fakeStopper{}, &fakeModerator{}).SetUserActive(context.Background(), testTargetAdminID, testRequesterID, false)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got.IsActive {
			t.Errorf("user should be deactivated: %+v", got)
		}
	})
}

// 4. SetUserActive sur un utilisateur inconnu -> NotFound (le repo traduit
// l'absence de ligne, ici simulée par l'absence dans la map).
func TestService_SetUserActive_UnknownUser(t *testing.T) {
	repo := seededRepo()
	_, err := NewService(repo, &fakeStopper{}, &fakeModerator{}).SetUserActive(context.Background(), testUnknownID, testRequesterID, false)
	if !apperror.IsCode(err, apperror.CodeNotFound) {
		t.Fatalf("want not_found, got %v", err)
	}
}

// 5. DeleteUser(target==requester) -> Conflict (self-action), sans appel repo.
func TestService_DeleteUser_SelfAction(t *testing.T) {
	repo := seededRepo()
	err := NewService(repo, &fakeStopper{}, &fakeModerator{}).DeleteUser(context.Background(), testRequesterID, testRequesterID)
	if !apperror.IsCode(err, apperror.CodeConflict) {
		t.Fatalf("want conflict, got %v", err)
	}
	if repo.getUserCalls != 0 {
		t.Errorf("repo must not be called on self-action")
	}
}

// 6. DeleteUser sur le dernier admin actif -> Conflict, delete jamais appelé.
func TestService_DeleteUser_LastActiveAdmin(t *testing.T) {
	repo := seededRepo()
	repo.activeAdminCount = 1
	err := NewService(repo, &fakeStopper{}, &fakeModerator{}).DeleteUser(context.Background(), testTargetAdminID, testRequesterID)
	if !apperror.IsCode(err, apperror.CodeConflict) {
		t.Fatalf("want conflict, got %v", err)
	}
	if repo.deleteCalls != 0 {
		t.Errorf("delete must not be called when the last active admin guard trips")
	}
}

// 7. DeleteUser OK -> stopper.StopLiveForUser(target) appelé AVANT le delete
// repo (ordre vérifié via la trace partagée).
func TestService_DeleteUser_StopsLiveBeforeDelete(t *testing.T) {
	var order []string
	repo := seededRepo()
	repo.order = &order
	stopper := &fakeStopper{order: &order}

	err := NewService(repo, stopper, &fakeModerator{}).DeleteUser(context.Background(), testTargetUserID, testRequesterID)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(order) != 2 || order[0] != "stopper.StopLiveForUser:"+testTargetUserID || order[1] != "repo.DeleteUser:"+testTargetUserID {
		t.Fatalf("wrong order: %v", order)
	}
	if repo.deleteCalls != 1 {
		t.Errorf("want 1 delete call, got %d", repo.deleteCalls)
	}
	if _, stillExists := repo.users[testTargetUserID]; stillExists {
		t.Errorf("user should have been deleted from repo")
	}
}

// 8. DeleteUser : une erreur du stopper est propagée et le delete repo n'est
// jamais appelé (on ne supprime pas un compte dont on n'a pas pu couper le live).
func TestService_DeleteUser_StopperError_PropagatesAndSkipsDelete(t *testing.T) {
	repo := seededRepo()
	stopErr := errors.New("ffmpeg kill failed")
	stopper := &fakeStopper{err: stopErr}

	err := NewService(repo, stopper, &fakeModerator{}).DeleteUser(context.Background(), testTargetUserID, testRequesterID)
	if !errors.Is(err, stopErr) {
		t.Fatalf("stopper error not propagated: %v", err)
	}
	if repo.deleteCalls != 0 {
		t.Errorf("delete must not be called when the stopper fails")
	}
}

// 9. DeleteUser sur un utilisateur inconnu -> NotFound (0 ligne), delete jamais appelé.
func TestService_DeleteUser_UnknownUser(t *testing.T) {
	repo := seededRepo()
	err := NewService(repo, &fakeStopper{}, &fakeModerator{}).DeleteUser(context.Background(), testUnknownID, testRequesterID)
	if !apperror.IsCode(err, apperror.CodeNotFound) {
		t.Fatalf("want not_found, got %v", err)
	}
	if repo.deleteCalls != 0 {
		t.Errorf("delete must not be called for an unknown user")
	}
}

// 10. SetUserActive(target==requester) détecté malgré une casse différente de
// l'UUID cible (pgtype.UUID scanne majuscules/minuscules vers les mêmes
// octets) -> Conflict (self-action), sans appel repo.
func TestService_SetUserActive_SelfAction_CaseInsensitive(t *testing.T) {
	repo := seededRepo()
	_, err := NewService(repo, &fakeStopper{}, &fakeModerator{}).SetUserActive(context.Background(), testFoldTargetIDUpper, testFoldRequesterID, false)
	if !apperror.IsCode(err, apperror.CodeConflict) {
		t.Fatalf("want conflict, got %v", err)
	}
	if repo.getUserCalls != 0 {
		t.Errorf("repo must not be called on self-action")
	}
}

// 11. DeleteUser(target==requester) détecté malgré une casse différente de
// l'UUID cible -> Conflict (self-action), sans appel repo.
func TestService_DeleteUser_SelfAction_CaseInsensitive(t *testing.T) {
	repo := seededRepo()
	err := NewService(repo, &fakeStopper{}, &fakeModerator{}).DeleteUser(context.Background(), testFoldTargetIDUpper, testFoldRequesterID)
	if !apperror.IsCode(err, apperror.CodeConflict) {
		t.Fatalf("want conflict, got %v", err)
	}
	if repo.getUserCalls != 0 {
		t.Errorf("repo must not be called on self-action")
	}
}

// 12. SetUserActive(target==requester) détecté même quand la cible est fournie
// SANS TIRETS (32 caractères) alors que le requester est sous sa forme
// canonique (36 caractères, comme le sub JWT) -> Conflict (self-action), sans
// appel repo. Fix #1 revue PR #264 : strings.EqualFold seul ne détecte pas ce
// cas (les deux chaînes diffèrent par autre chose que la casse), ce qui
// laissait un admin contourner la garde en soumettant son propre id sous une
// graphie différente.
func TestService_SetUserActive_SelfAction_DashlessFormat(t *testing.T) {
	repo := seededRepo()
	dashless := strings.ReplaceAll(testFoldRequesterID, "-", "")
	_, err := NewService(repo, &fakeStopper{}, &fakeModerator{}).SetUserActive(context.Background(), dashless, testFoldRequesterID, false)
	if !apperror.IsCode(err, apperror.CodeConflict) {
		t.Fatalf("want conflict, got %v", err)
	}
	if repo.getUserCalls != 0 {
		t.Errorf("repo must not be called on self-action")
	}
}

// 13. DeleteUser(target==requester) détecté même quand la cible est fournie
// SANS TIRETS -> Conflict (self-action), sans appel repo. Même fix que 12.
func TestService_DeleteUser_SelfAction_DashlessFormat(t *testing.T) {
	repo := seededRepo()
	dashless := strings.ReplaceAll(testFoldRequesterID, "-", "")
	err := NewService(repo, &fakeStopper{}, &fakeModerator{}).DeleteUser(context.Background(), dashless, testFoldRequesterID)
	if !apperror.IsCode(err, apperror.CodeConflict) {
		t.Fatalf("want conflict, got %v", err)
	}
	if repo.getUserCalls != 0 {
		t.Errorf("repo must not be called on self-action")
	}
}

// 14. SetUserActive avec un targetID qui n'a pas la forme d'un UUID : la
// comparaison normalisée échoue proprement (pas de panique), ce n'est pas
// traité comme une self-action, et c'est GetUser qui traduit l'ID invalide en
// NotFound (garde-fou pour normalizeUUID/sameUUID).
func TestService_SetUserActive_MalformedTargetID_NotSelfAction(t *testing.T) {
	repo := seededRepo()
	_, err := NewService(repo, &fakeStopper{}, &fakeModerator{}).SetUserActive(context.Background(), "not-a-uuid", testRequesterID, false)
	if !apperror.IsCode(err, apperror.CodeNotFound) {
		t.Fatalf("want not_found (malformed id treated as unknown user, not self-action), got %v", err)
	}
}

// 15. DeleteUser avec un targetID qui n'a pas la forme d'un UUID : même
// garantie que 14.
func TestService_DeleteUser_MalformedTargetID_NotSelfAction(t *testing.T) {
	repo := seededRepo()
	err := NewService(repo, &fakeStopper{}, &fakeModerator{}).DeleteUser(context.Background(), "not-a-uuid", testRequesterID)
	if !apperror.IsCode(err, apperror.CodeNotFound) {
		t.Fatalf("want not_found (malformed id treated as unknown user, not self-action), got %v", err)
	}
}

// 16. DeleteUser sur un admin actif alors qu'il reste 2 admins actifs -> la
// garde dernier-admin-actif laisse passer, stopper puis delete appelés dans
// l'ordre (comme le cas 7, mais en ciblant un admin). Fix #11 revue PR #264 :
// seule la branche n=1 (conflit) était testée, cette branche passante avec une
// cible admin n'était jamais couverte.
func TestService_DeleteUser_ActiveAdmin_EnoughOtherAdmins(t *testing.T) {
	var order []string
	repo := seededRepo()
	repo.order = &order
	repo.activeAdminCount = 2
	stopper := &fakeStopper{order: &order}

	err := NewService(repo, stopper, &fakeModerator{}).DeleteUser(context.Background(), testTargetAdminID, testRequesterID)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(order) != 2 || order[0] != "stopper.StopLiveForUser:"+testTargetAdminID || order[1] != "repo.DeleteUser:"+testTargetAdminID {
		t.Fatalf("wrong order: %v", order)
	}
	if repo.deleteCalls != 1 {
		t.Errorf("want 1 delete call, got %d", repo.deleteCalls)
	}
	if _, stillExists := repo.users[testTargetAdminID]; stillExists {
		t.Errorf("admin should have been deleted from repo")
	}
}

// 17. StopStream OK -> moderator.ForceStopStream appelé PUIS
// repo.InsertAuditLog(actorID, "stream.stopped", "stream", streamID), dans cet
// ordre (trace partagée, même pattern que le cas 7 DeleteUser/stopper+repo).
func TestService_StopStream_OK_StopsThenAudits(t *testing.T) {
	var order []string
	repo := &fakeRepo{order: &order}
	moderator := &fakeModerator{order: &order}

	err := NewService(repo, &fakeStopper{}, moderator).StopStream(context.Background(), testStreamID, testRequesterID)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(order) != 2 || order[0] != "moderator.ForceStopStream:"+testStreamID || order[1] != "repo.InsertAuditLog:"+testStreamID {
		t.Fatalf("wrong order: %v", order)
	}
	if repo.auditCalls != 1 {
		t.Fatalf("want 1 audit call, got %d", repo.auditCalls)
	}
	if repo.gotAuditActor != testRequesterID || repo.gotAuditAction != "stream.stopped" || repo.gotAuditType != "stream" || repo.gotAuditTarget != testStreamID {
		t.Errorf("audit params = (%q, %q, %q, %q), want (%q, %q, %q, %q)",
			repo.gotAuditActor, repo.gotAuditAction, repo.gotAuditType, repo.gotAuditTarget,
			testRequesterID, "stream.stopped", "stream", testStreamID)
	}
}

// 18. StopStream : le moderator échoue (ex. 409 flux pas live) -> l'erreur est
// propagée telle quelle et AUCUN audit n'est inséré (on ne journalise pas une
// interruption qui n'a pas eu lieu).
func TestService_StopStream_ModeratorError_PropagatesAndSkipsAudit(t *testing.T) {
	repo := &fakeRepo{}
	stopErr := apperror.Conflict("stream is not live")
	moderator := &fakeModerator{err: stopErr}

	err := NewService(repo, &fakeStopper{}, moderator).StopStream(context.Background(), testStreamID, testRequesterID)
	if !errors.Is(err, stopErr) {
		t.Fatalf("moderator error not propagated: %v", err)
	}
	if repo.auditCalls != 0 {
		t.Errorf("audit must not be inserted when the moderator fails, got %d calls", repo.auditCalls)
	}
}

// 19. StopStream : l'interruption réussit mais l'écriture de l'audit échoue ->
// StopStream renvoie quand même nil (best-effort : l'action critique a eu
// lieu, un échec du journal ne doit pas faire échouer la requête admin).
func TestService_StopStream_AuditError_StillReturnsNil(t *testing.T) {
	repo := &fakeRepo{auditErr: errors.New("db unreachable")}
	moderator := &fakeModerator{}

	err := NewService(repo, &fakeStopper{}, moderator).StopStream(context.Background(), testStreamID, testRequesterID)
	if err != nil {
		t.Fatalf("audit failure must be swallowed (best-effort), got: %v", err)
	}
	if moderator.forceStopCalls != 1 {
		t.Errorf("want 1 call to moderator, got %d", moderator.forceStopCalls)
	}
	if repo.auditCalls != 1 {
		t.Errorf("want 1 (failed) audit attempt, got %d", repo.auditCalls)
	}
}

// 20. ListLiveStreams délègue au repo et renvoie le total (même contrat que
// ListUsers, cas 1).
func TestService_ListLiveStreams_DelegatesAndReturnsTotal(t *testing.T) {
	repo := &fakeRepo{
		listStreams:      []AdminStream{{ID: testStreamID, Title: "Morning Jazz", IsPublic: true, UserID: testTargetUserID, Username: "user1"}},
		listStreamsTotal: 7,
	}

	streams, total, err := NewService(repo, &fakeStopper{}, &fakeModerator{}).ListLiveStreams(context.Background(), 20, 10)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if repo.listStreamsCalled != 1 {
		t.Fatalf("want 1 call to repo.ListLiveStreams, got %d", repo.listStreamsCalled)
	}
	if repo.listStreamsLimit != 20 || repo.listStreamsOffset != 10 {
		t.Errorf("limit/offset not passed through: got (%d, %d)", repo.listStreamsLimit, repo.listStreamsOffset)
	}
	if total != 7 {
		t.Errorf("total not returned: got %d", total)
	}
	if len(streams) != 1 || streams[0].ID != testStreamID {
		t.Errorf("streams not returned: %+v", streams)
	}
}
