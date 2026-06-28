package broadcaster

import (
	"context"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

const MaxMessageLen = 500

const (
	StatusPending  = "pending"
	StatusApproved = "approved"
	StatusRejected = "rejected"
)

const (
	roleUser        = "user"
	roleBroadcaster = "broadcaster"
	roleAdmin       = "admin"
)

type Request struct {
	ID         string    `json:"id"`
	Status     string    `json:"status"`
	Message    string    `json:"message"`
	ReviewNote string    `json:"review_note"`
	ReviewedBy *string   `json:"reviewed_by"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

type AdminRequest struct {
	Request
	UserID   string `json:"user_id"`
	Email    string `json:"email"`
	Username string `json:"username"`
}

type Repository interface {
	GetUserRole(ctx context.Context, userID string) (string, error)
	Create(ctx context.Context, userID, message string) (Request, error)
	GetLatestByUser(ctx context.Context, userID string) (Request, error)
	List(ctx context.Context, status *string) ([]AdminRequest, error)
	// Review applique le changement de statut dans une transaction ; si promote
	// vaut true, le rôle de l'utilisateur passe à « broadcaster » de façon atomique.
	Review(ctx context.Context, requestID, adminID, status, note string, promote bool) (Request, error)
}

type Service struct {
	repo Repository
}

func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) RequestBroadcaster(ctx context.Context, userID, message string) (Request, error) {
	msg, err := normalizeMessage(message)
	if err != nil {
		return Request{}, err
	}

	role, err := s.repo.GetUserRole(ctx, userID)
	if err != nil {
		return Request{}, err
	}
	switch role {
	case roleBroadcaster, roleAdmin:
		return Request{}, apperror.Conflict("user is already a broadcaster")
	case roleUser:
	default:
		return Request{}, apperror.Forbidden("role not allowed to request broadcaster role")
	}

	return s.repo.Create(ctx, userID, msg)
}

func (s *Service) GetMyRequest(ctx context.Context, userID string) (Request, error) {
	return s.repo.GetLatestByUser(ctx, userID)
}

func (s *Service) ListRequests(ctx context.Context, status string) ([]AdminRequest, error) {
	var filter *string
	if status != "" {
		if !validStatus(status) {
			return nil, apperror.InvalidArgument("invalid status filter")
		}
		filter = &status
	}
	return s.repo.List(ctx, filter)
}

func (s *Service) ApproveRequest(ctx context.Context, requestID, adminID, note string) (Request, error) {
	n, err := normalizeMessage(note)
	if err != nil {
		return Request{}, err
	}
	return s.repo.Review(ctx, requestID, adminID, StatusApproved, n, true)
}

func (s *Service) RejectRequest(ctx context.Context, requestID, adminID, note string) (Request, error) {
	n, err := normalizeMessage(note)
	if err != nil {
		return Request{}, err
	}
	return s.repo.Review(ctx, requestID, adminID, StatusRejected, n, false)
}

func normalizeMessage(raw string) (string, error) {
	m := strings.TrimSpace(raw)
	if utf8.RuneCountInString(m) > MaxMessageLen {
		return "", apperror.InvalidArgument("message too long")
	}
	return m, nil
}

func validStatus(s string) bool {
	switch s {
	case StatusPending, StatusApproved, StatusRejected:
		return true
	default:
		return false
	}
}
