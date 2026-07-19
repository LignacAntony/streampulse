// Package admin implémente la gestion des utilisateurs par un administrateur
// (US-08-01) : recherche/liste paginée, activation/désactivation, suppression
// définitive. Le rôle n'est pas modifiable ici (hors scope, cf. STR-51).
package admin

import (
	"context"
	"time"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

// AdminUser est la vue d'un utilisateur telle qu'exposée à un admin. Le hash
// du mot de passe n'est jamais inclus.
type AdminUser struct {
	ID        string    `json:"id"`
	Email     string    `json:"email"`
	Username  string    `json:"username"`
	Role      string    `json:"role"`
	IsActive  bool      `json:"is_active"`
	CreatedAt time.Time `json:"created_at"`
}

// ListUsersInput porte les filtres et la pagination de la recherche admin.
// Search/Role/Status vides désactivent le filtre correspondant (cf. admin.sql).
type ListUsersInput struct {
	Search string
	Role   string
	Status string
	Limit  int32
	Offset int32
}

// LiveStopper arrête tous les lives en cours d'un utilisateur. Implémentée par
// streaming.Service (STR-191 Task 2) ; interface étroite (ISP) pour ne pas
// coupler le domaine admin au domaine streaming.
type LiveStopper interface {
	StopLiveForUser(ctx context.Context, userID string) error
}

// Repository est le miroir des requêtes SQL du domaine admin (queries/admin.sql).
type Repository interface {
	ListUsers(ctx context.Context, in ListUsersInput) ([]AdminUser, int64, error)
	GetUser(ctx context.Context, userID string) (AdminUser, error)
	SetUserActive(ctx context.Context, userID string, active bool) (AdminUser, error)
	CountActiveAdmins(ctx context.Context) (int64, error)
	DeleteUser(ctx context.Context, userID string) error
}

type Service struct {
	repo    Repository
	stopper LiveStopper
}

func NewService(repo Repository, stopper LiveStopper) *Service {
	return &Service{repo: repo, stopper: stopper}
}

// ListUsers délègue entièrement au repository : filtres et pagination sont
// déjà validés/bornés en amont (handler), le service ne fait que transmettre
// et renvoyer le total (pagination UI).
func (s *Service) ListUsers(ctx context.Context, in ListUsersInput) ([]AdminUser, int64, error) {
	return s.repo.ListUsers(ctx, in)
}

// SetUserActive active/désactive un compte. Un admin ne peut pas s'auto-modifier
// (self-action), et on ne peut jamais désactiver le dernier admin actif restant.
func (s *Service) SetUserActive(ctx context.Context, targetID, requesterID string, active bool) (AdminUser, error) {
	if targetID == requesterID {
		return AdminUser{}, apperror.Conflict("cannot modify your own account")
	}
	target, err := s.repo.GetUser(ctx, targetID)
	if err != nil {
		return AdminUser{}, err
	}
	if !active && target.Role == "admin" && target.IsActive {
		n, err := s.repo.CountActiveAdmins(ctx)
		if err != nil {
			return AdminUser{}, err
		}
		if n <= 1 {
			return AdminUser{}, apperror.Conflict("cannot deactivate the last active admin")
		}
	}
	return s.repo.SetUserActive(ctx, targetID, active)
}

// DeleteUser supprime définitivement un compte (hard delete). Mêmes gardes que
// SetUserActive (self-action, dernier admin actif), puis arrête les lives en
// cours du user AVANT de le supprimer (une session en mémoire ne doit jamais
// survivre à la disparition de son propriétaire).
func (s *Service) DeleteUser(ctx context.Context, targetID, requesterID string) error {
	if targetID == requesterID {
		return apperror.Conflict("cannot delete your own account")
	}
	target, err := s.repo.GetUser(ctx, targetID)
	if err != nil {
		return err
	}
	if target.Role == "admin" && target.IsActive {
		n, err := s.repo.CountActiveAdmins(ctx)
		if err != nil {
			return err
		}
		if n <= 1 {
			return apperror.Conflict("cannot delete the last active admin")
		}
	}
	if err := s.stopper.StopLiveForUser(ctx, targetID); err != nil {
		return err
	}
	return s.repo.DeleteUser(ctx, targetID)
}
