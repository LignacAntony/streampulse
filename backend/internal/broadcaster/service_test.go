package broadcaster

import (
	"context"
	"strings"
	"testing"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

const (
	testUserID  = "00000000-0000-0000-0000-000000000001"
	testAdminID = "00000000-0000-0000-0000-0000000000ad"
	testReqID   = "00000000-0000-0000-0000-0000000000a1"
)

type fakeRepo struct {
	role        string
	createCalls int
	created     Request
	createErr   error

	reviewCalls   int
	lastStatus    string
	lastPromote   bool
	lastReviewer  string
	lastRequestID string
}

func (f *fakeRepo) GetUserRole(_ context.Context, _ string) (string, error) {
	if f.role == "" {
		return roleUser, nil
	}
	return f.role, nil
}

func (f *fakeRepo) Create(_ context.Context, _, message string) (Request, error) {
	f.createCalls++
	if f.createErr != nil {
		return Request{}, f.createErr
	}
	return Request{ID: testReqID, Status: StatusPending, Message: message}, nil
}

func (f *fakeRepo) GetLatestByUser(_ context.Context, _ string) (Request, error) {
	return Request{ID: testReqID, Status: StatusPending}, nil
}

func (f *fakeRepo) List(_ context.Context, _ *string) ([]AdminRequest, error) {
	return nil, nil
}

func (f *fakeRepo) Review(_ context.Context, requestID, adminID, status, _ string, promote bool) (Request, error) {
	f.reviewCalls++
	f.lastRequestID = requestID
	f.lastReviewer = adminID
	f.lastStatus = status
	f.lastPromote = promote
	return Request{ID: requestID, Status: status}, nil
}

func TestRequestBroadcaster_Success(t *testing.T) {
	repo := &fakeRepo{role: roleUser}
	req, err := NewService(repo).RequestBroadcaster(context.Background(), testUserID, "  je veux diffuser  ")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if repo.createCalls != 1 {
		t.Fatalf("want 1 create call, got %d", repo.createCalls)
	}
	if req.Message != "je veux diffuser" {
		t.Errorf("message not trimmed: %q", req.Message)
	}
}

func TestRequestBroadcaster_AlreadyBroadcasterOrAdmin(t *testing.T) {
	for _, role := range []string{roleBroadcaster, roleAdmin} {
		t.Run(role, func(t *testing.T) {
			repo := &fakeRepo{role: role}
			_, err := NewService(repo).RequestBroadcaster(context.Background(), testUserID, "x")
			if !apperror.IsCode(err, apperror.CodeConflict) {
				t.Fatalf("want conflict, got %v", err)
			}
			if repo.createCalls != 0 {
				t.Errorf("repo must not be called when already privileged")
			}
		})
	}
}

func TestRequestBroadcaster_RejectsUnexpectedRole(t *testing.T) {
	repo := &fakeRepo{role: "anonymous"}
	_, err := NewService(repo).RequestBroadcaster(context.Background(), testUserID, "x")
	if !apperror.IsCode(err, apperror.CodeForbidden) {
		t.Fatalf("want forbidden, got %v", err)
	}
	if repo.createCalls != 0 {
		t.Errorf("repo must not be called for an unexpected role")
	}
}

func TestRequestBroadcaster_MessageTooLong(t *testing.T) {
	repo := &fakeRepo{role: roleUser}
	long := strings.Repeat("a", MaxMessageLen+1)
	_, err := NewService(repo).RequestBroadcaster(context.Background(), testUserID, long)
	if !apperror.IsCode(err, apperror.CodeInvalidArgument) {
		t.Fatalf("want invalid_argument, got %v", err)
	}
	if repo.createCalls != 0 {
		t.Errorf("repo must not be called on invalid message")
	}
}

func TestListRequests_InvalidStatus(t *testing.T) {
	repo := &fakeRepo{}
	if _, err := NewService(repo).ListRequests(context.Background(), "bogus"); !apperror.IsCode(err, apperror.CodeInvalidArgument) {
		t.Fatalf("want invalid_argument, got %v", err)
	}
}

func TestApproveRequest_PromotesUser(t *testing.T) {
	repo := &fakeRepo{}
	if _, err := NewService(repo).ApproveRequest(context.Background(), testReqID, testAdminID, "ok"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if repo.reviewCalls != 1 || repo.lastStatus != StatusApproved || !repo.lastPromote {
		t.Fatalf("approve must review with promote=true status=approved: %+v", repo)
	}
	if repo.lastReviewer != testAdminID || repo.lastRequestID != testReqID {
		t.Errorf("reviewer/request id not propagated: %+v", repo)
	}
}

func TestRejectRequest_DoesNotPromote(t *testing.T) {
	repo := &fakeRepo{}
	if _, err := NewService(repo).RejectRequest(context.Background(), testReqID, testAdminID, "non"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if repo.reviewCalls != 1 || repo.lastStatus != StatusRejected || repo.lastPromote {
		t.Fatalf("reject must review with promote=false status=rejected: %+v", repo)
	}
}
