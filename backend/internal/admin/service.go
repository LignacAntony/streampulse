// Package admin implémente la gestion des utilisateurs par un administrateur
// (US-08-01) : recherche/liste paginée, activation/désactivation, suppression
// définitive. Le rôle n'est pas modifiable ici (hors scope, cf. STR-51).
package admin

import (
	"context"
	"log"
	"strings"
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

// AdminStream est la vue d'un flux en direct telle qu'exposée à un admin pour
// la modération (STR-192) : identité du diffuseur incluse (jointure users),
// secrets (stream_key, stream_source_url) absents — un modérateur n'a jamais
// besoin de pousser de l'audio sur le flux d'un autre.
type AdminStream struct {
	ID        string     `json:"id"`
	Title     string     `json:"title"`
	IsPublic  bool       `json:"is_public"`
	StartedAt *time.Time `json:"started_at"`
	UserID    string     `json:"user_id"`
	Username  string     `json:"username"`
}

// LiveStopper arrête tous les lives en cours d'un utilisateur. Implémentée par
// streaming.Service (STR-191 Task 2) ; interface étroite (ISP) pour ne pas
// coupler le domaine admin au domaine streaming.
type LiveStopper interface {
	StopLiveForUser(ctx context.Context, userID string) error
}

// StreamModerator expose au domaine admin l'interruption d'un flux par un
// modérateur. Implémentée par streaming.Service (ISP, même logique que LiveStopper).
type StreamModerator interface {
	ForceStopStream(ctx context.Context, streamID string) error
}

// Repository est le miroir des requêtes SQL du domaine admin (queries/admin.sql).
type Repository interface {
	ListUsers(ctx context.Context, in ListUsersInput) ([]AdminUser, int64, error)
	GetUser(ctx context.Context, userID string) (AdminUser, error)
	SetUserActive(ctx context.Context, userID string, active bool) (AdminUser, error)
	CountActiveAdmins(ctx context.Context) (int64, error)
	DeleteUser(ctx context.Context, userID string) error
	ListLiveStreams(ctx context.Context, limit, offset int32) ([]AdminStream, int64, error)
	InsertAuditLog(ctx context.Context, actorID, action, targetType, targetID string) error
}

type Service struct {
	repo      Repository
	stopper   LiveStopper
	moderator StreamModerator
}

func NewService(repo Repository, stopper LiveStopper, moderator StreamModerator) *Service {
	return &Service{repo: repo, stopper: stopper, moderator: moderator}
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
	// Le dernier-admin-actif n'est en jeu que si active désactive un compte : une
	// activation ne peut jamais faire baisser le nombre d'admins actifs.
	if err := s.guardMutableAdmin(ctx, targetID, requesterID, !active,
		"cannot modify your own account", "cannot deactivate the last active admin"); err != nil {
		return AdminUser{}, err
	}
	return s.repo.SetUserActive(ctx, targetID, active)
}

// DeleteUser supprime définitivement un compte (hard delete). Mêmes gardes que
// SetUserActive (self-action, dernier admin actif — ici toujours vérifié, une
// suppression fait toujours baisser le nombre d'admins actifs), puis arrête
// les lives en cours du user AVANT de le supprimer (une session en mémoire ne
// doit jamais survivre à la disparition de son propriétaire).
func (s *Service) DeleteUser(ctx context.Context, targetID, requesterID string) error {
	if err := s.guardMutableAdmin(ctx, targetID, requesterID, true,
		"cannot delete your own account", "cannot delete the last active admin"); err != nil {
		return err
	}
	if err := s.stopper.StopLiveForUser(ctx, targetID); err != nil {
		return err
	}
	return s.repo.DeleteUser(ctx, targetID)
}

// ListLiveStreams retourne la liste de modération (tous les live) + total.
func (s *Service) ListLiveStreams(ctx context.Context, limit, offset int32) ([]AdminStream, int64, error) {
	return s.repo.ListLiveStreams(ctx, limit, offset)
}

// StopStream interrompt un flux (modération) puis journalise l'action.
// L'audit est best-effort : l'interruption est l'action critique, un échec
// d'écriture du journal est loggé sans faire échouer la requête.
func (s *Service) StopStream(ctx context.Context, streamID, actorID string) error {
	if err := s.moderator.ForceStopStream(ctx, streamID); err != nil {
		return err
	}
	if err := s.repo.InsertAuditLog(ctx, actorID, "stream.stopped", "stream", streamID); err != nil {
		log.Printf("admin: audit stream.stopped %s par %s non journalisé: %v", streamID, actorID, err)
	}
	return nil
}

// guardMutableAdmin factorise les gardes partagées par SetUserActive et
// DeleteUser (fix #5 revue PR #264, ex-code dupliqué à l'identique près des
// messages) : self-action (UUID normalisé, cf. sameUUID) puis, si
// checkLastActiveAdmin, dernier-admin-actif. selfActionMsg/lastAdminMsg
// portent les messages distincts de chaque appelant. Ne renvoie que l'erreur :
// ni SetUserActive ni DeleteUser n'ont besoin de la cible chargée au-delà de
// la garde elle-même (cf. #6 : GetUser reste nécessaire ici, avant le count).
func (s *Service) guardMutableAdmin(ctx context.Context, targetID, requesterID string, checkLastActiveAdmin bool, selfActionMsg, lastAdminMsg string) error {
	if sameUUID(targetID, requesterID) {
		return apperror.Conflict(selfActionMsg)
	}
	target, err := s.repo.GetUser(ctx, targetID)
	if err != nil {
		return err
	}
	if checkLastActiveAdmin && target.Role == "admin" && target.IsActive {
		n, err := s.repo.CountActiveAdmins(ctx)
		if err != nil {
			return err
		}
		// Garde non transactionnel : deux requêtes concurrentes visant deux admins
		// différents peuvent théoriquement passer toutes deux le count — fenêtre
		// minuscule, assumée à cette échelle (cf. ADR 017).
		if n <= 1 {
			return apperror.Conflict(lastAdminMsg)
		}
	}
	return nil
}

// sameUUID compare deux identifiants représentant potentiellement le même
// UUID sous une graphie différente (avec/sans tirets, casse différente).
// Fix #1 revue PR #264 : strings.EqualFold seul ne détecte que la casse — un
// admin pouvait contourner la garde self-action en soumettant son propre id
// sans les tirets (32 caractères) alors que le requesterID (sub JWT) est sous
// sa forme canonique (36 caractères) ; GetUser normalisait ensuite les deux
// vers la même ligne. Si l'une des deux chaînes ne parse pas comme un UUID,
// ce n'est pas une self-action : la garde laisse passer et c'est GetUser (via
// pgtype.UUID) qui traduira l'ID invalide en NotFound.
func sameUUID(a, b string) bool {
	na, oka := normalizeUUID(a)
	nb, okb := normalizeUUID(b)
	return oka && okb && na == nb
}

// normalizeUUID renvoie la forme canonique (minuscules, sans tirets) d'un
// UUID, et false si s n'a pas la forme d'un UUID (32 caractères hexadécimaux
// une fois les tirets retirés). Ne valide pas le positionnement RFC 4122 des
// tirets : seule la forme réellement rencontrée ici importe (path param HTTP
// / sub JWT), pas l'exhaustivité d'un parseur UUID générique — cette
// validation complète reste la responsabilité du repository (pgtype.UUID).
func normalizeUUID(s string) (string, bool) {
	s = strings.ToLower(strings.ReplaceAll(s, "-", ""))
	if len(s) != 32 {
		return "", false
	}
	for _, r := range s {
		if (r < '0' || r > '9') && (r < 'a' || r > 'f') {
			return "", false
		}
	}
	return s, true
}
