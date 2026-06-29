package broadcaster

import (
	"context"
	"testing"

	"github.com/jackc/pgx/v5/pgtype"

	broadcasterdb "github.com/LignacAntony/streampulse/internal/broadcaster/db"
	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

type fakeReviewQueries struct {
	current         broadcasterdb.GetRequestForReviewRow
	promoteAffected int64
	reviewCalled    bool
}

func (f *fakeReviewQueries) GetRequestForReview(_ context.Context, _ pgtype.UUID) (broadcasterdb.GetRequestForReviewRow, error) {
	return f.current, nil
}

func (f *fakeReviewQueries) PromoteUserToBroadcaster(_ context.Context, _ pgtype.UUID) (int64, error) {
	return f.promoteAffected, nil
}

func (f *fakeReviewQueries) ReviewRequest(_ context.Context, _ broadcasterdb.ReviewRequestParams) (broadcasterdb.ReviewRequestRow, error) {
	f.reviewCalled = true
	return broadcasterdb.ReviewRequestRow{ID: testReqID, UserID: testUserID, Status: StatusApproved}, nil
}

func pendingRow() broadcasterdb.GetRequestForReviewRow {
	return broadcasterdb.GetRequestForReviewRow{ID: testReqID, UserID: testUserID, Status: StatusPending}
}

func TestReviewWithQueries_PromotionNoLongerEligible(t *testing.T) {
	q := &fakeReviewQueries{current: pendingRow(), promoteAffected: 0}

	_, err := reviewWithQueries(context.Background(), q, testReqID, testAdminID, StatusApproved, "", true)

	if !apperror.IsCode(err, apperror.CodeConflict) {
		t.Fatalf("want conflict, got %v", err)
	}
	if q.reviewCalled {
		t.Error("la demande ne doit pas être marquée approved si la promotion échoue")
	}
}

func TestReviewWithQueries_ApprovePromotes(t *testing.T) {
	q := &fakeReviewQueries{current: pendingRow(), promoteAffected: 1}

	res, err := reviewWithQueries(context.Background(), q, testReqID, testAdminID, StatusApproved, "", true)

	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !q.reviewCalled || res.Status != StatusApproved {
		t.Fatalf("attendu demande approved : called=%v status=%q", q.reviewCalled, res.Status)
	}
}

func TestReviewWithQueries_RejectSkipsPromotion(t *testing.T) {
	q := &fakeReviewQueries{current: pendingRow(), promoteAffected: 0}

	_, err := reviewWithQueries(context.Background(), q, testReqID, testAdminID, StatusRejected, "non", false)

	if err != nil {
		t.Fatalf("le refus ne doit pas dépendre de la promotion : %v", err)
	}
	if !q.reviewCalled {
		t.Error("le refus doit tout de même marquer la demande")
	}
}

func TestReviewWithQueries_AlreadyReviewed(t *testing.T) {
	q := &fakeReviewQueries{
		current: broadcasterdb.GetRequestForReviewRow{ID: testReqID, UserID: testUserID, Status: StatusApproved},
	}

	_, err := reviewWithQueries(context.Background(), q, testReqID, testAdminID, StatusApproved, "", true)

	if !apperror.IsCode(err, apperror.CodeConflict) {
		t.Fatalf("want conflict, got %v", err)
	}
	if q.reviewCalled {
		t.Error("une demande déjà traitée ne doit pas être re-marquée")
	}
}
