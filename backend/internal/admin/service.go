// Package admin implémente la gestion des utilisateurs par un administrateur
// (US-08-01) : recherche/liste paginée, activation/désactivation, suppression
// définitive. Le rôle n'est pas modifiable ici (hors scope, cf. STR-51).
package admin

import (
	"context"
	"strings"
	"time"

	"github.com/rs/zerolog"

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

// UserTrackPurger orchestre la suppression du compte pour supprimer aussi les
// fichiers audio du user (la cascade DB efface les lignes tracks, pas les
// fichiers). deleteUser est le hard-delete lui-même : le purger relève d'abord
// les chemins, exécute deleteUser, puis supprime les fichiers — ainsi un delete
// qui échoue ne laisse pas de lignes pointant vers des fichiers disparus.
// Implémentée par track.Service ; injectée en setter (SetTrackPurger). Interface
// étroite (ISP), même logique que LiveStopper.
type UserTrackPurger interface {
	PurgeUserTracks(ctx context.Context, userID string, deleteUser func() error) error
}

// UserCounts est la population de comptes, telle qu'exposée dans le résumé admin.
type UserCounts struct {
	Total        int64 `json:"total"`
	Active       int64 `json:"active"`
	Broadcasters int64 `json:"broadcasters"`
	Admins       int64 `json:"admins"`
}

// HTTPTotals est le cumul des compteurs HTTP du process, tel que le domaine
// admin en a besoin. Le type vit ici — et non dans internal/observability —
// pour que le domaine ne dépende pas de Prometheus (même règle que
// streaming.MetricsRecorder, ADR 022) ; main.go pose l'adaptateur.
type HTTPTotals struct {
	Requests      int64
	ClientErrors  int64
	ServerErrors  int64
	ResponseBytes int64
}

// HTTPCounters lit les compteurs HTTP cumulés du process. Interface étroite
// (ISP) satisfaite par un adaptateur autour d'observability.HTTPStats.
type HTTPCounters interface {
	HTTPTotals() (HTTPTotals, error)
}

// LiveAudience expose l'état du registre de directs (flux actifs et audience
// estimée). Interface étroite (ISP) satisfaite par streaming.LiveSessions.
type LiveAudience interface {
	ActiveCount() int
	TotalListeners() int
}

// Repository est le miroir des requêtes SQL du domaine admin (queries/admin.sql).
type Repository interface {
	ListUsers(ctx context.Context, in ListUsersInput) ([]AdminUser, int64, error)
	GetUser(ctx context.Context, userID string) (AdminUser, error)
	SetUserActive(ctx context.Context, userID string, active bool) (AdminUser, error)
	CountActiveAdmins(ctx context.Context) (int64, error)
	UserCounts(ctx context.Context) (UserCounts, error)
	DeleteUser(ctx context.Context, userID string) error
	ListLiveStreams(ctx context.Context, limit, offset int32) ([]AdminStream, int64, error)
	InsertAuditLog(ctx context.Context, actorID, action, targetType, targetID string) error
}

type Service struct {
	repo      Repository
	stopper   LiveStopper
	moderator StreamModerator
	// purger est optionnel (injecté en setter) : nil dans les tests qui ne
	// couvrent pas la suppression de fichiers.
	purger UserTrackPurger
	// audience et counters alimentent Overview ; optionnels pour la même raison
	// que purger (les tests des autres méthodes ne les fournissent pas).
	audience LiveAudience
	counters HTTPCounters
	// startedAt date le process, pas le service : Overview publie une durée de
	// fonctionnement, et c'est celle du binaire qui répond.
	startedAt time.Time
}

func NewService(repo Repository, stopper LiveStopper, moderator StreamModerator) *Service {
	return &Service{repo: repo, stopper: stopper, moderator: moderator, startedAt: time.Now()}
}

// SetOverviewSources branche les sources du résumé admin (STR-244). Même motif
// setter que SetTrackPurger : ces collaborateurs sont construits après le
// service dans main.go.
func (s *Service) SetOverviewSources(audience LiveAudience, counters HTTPCounters) {
	s.audience = audience
	s.counters = counters
}

// SetTrackPurger branche la suppression des fichiers audio d'un utilisateur lors
// de la suppression de son compte (câblé dans main.go). Suit le motif setter des
// collaborateurs inter-domaines tardifs (cf. streaming SetMetrics).
func (s *Service) SetTrackPurger(p UserTrackPurger) {
	s.purger = p
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
	// Le purger séquence : relève les chemins → hard-delete (cascade) → supprime
	// les fichiers. La cascade DB efface les lignes tracks mais jamais les fichiers
	// du volume ; supprimer les fichiers seulement après un delete réussi évite les
	// lignes fantômes.
	deleteUser := func() error { return s.repo.DeleteUser(ctx, targetID) }
	if s.purger != nil {
		return s.purger.PurgeUserTracks(ctx, targetID, deleteUser)
	}
	return deleteUser()
}

// Overview est le résumé de supervision rendu par GET /api/admin/metrics.
//
// Les chiffres HTTP sont des **cumuls depuis le démarrage** du process, pas des
// taux glissants : c'est ce que porte le registre Prometheus local, seule source
// consultée (cf. observability.HTTPStats). Les champs le disent dans leur nom
// pour que la différence avec les dashboards Grafana ne se perde pas.
type Overview struct {
	UptimeSeconds int64        `json:"uptime_seconds"`
	Streams       StreamsStats `json:"streams"`
	HTTP          HTTPStats    `json:"http"`
	Users         UserCounts   `json:"users"`
}

// StreamsStats est le volet diffusion du résumé.
type StreamsStats struct {
	Live int `json:"live"`
	// ListenersEstimated est une estimation, comme partout où StreamPulse compte
	// des auditeurs : HLS n'a pas de connexion persistante (ADR 025).
	ListenersEstimated int `json:"listeners_estimated"`
}

// HTTPStats est le volet trafic du résumé.
type HTTPStats struct {
	RequestsTotal      int64 `json:"requests_total"`
	ClientErrorsTotal  int64 `json:"client_errors_total"`
	ServerErrorsTotal  int64 `json:"server_errors_total"`
	ResponseBytesTotal int64 `json:"response_bytes_total"`
	// ServerErrorRate vaut ServerErrorsTotal / RequestsTotal depuis le boot.
	// Zéro tant qu'aucune requête n'a été servie — et non NaN, qui ne survit
	// pas à un encodage JSON.
	ServerErrorRate float64 `json:"server_error_rate"`
}

// Overview assemble le résumé. Les sources absentes (service construit sans
// SetOverviewSources) rendent des zéros plutôt qu'une erreur : le résumé est
// une vue de supervision, pas une transaction — un volet manquant ne doit pas
// priver l'admin des autres.
func (s *Service) Overview(ctx context.Context) (Overview, error) {
	counts, err := s.repo.UserCounts(ctx)
	if err != nil {
		return Overview{}, err
	}

	out := Overview{
		UptimeSeconds: int64(time.Since(s.startedAt).Seconds()),
		Users:         counts,
	}
	if s.audience != nil {
		out.Streams = StreamsStats{
			Live:               s.audience.ActiveCount(),
			ListenersEstimated: s.audience.TotalListeners(),
		}
	}
	if s.counters != nil {
		totals, cerr := s.counters.HTTPTotals()
		if cerr != nil {
			// Le registre local est en mémoire : une erreur ici est anormale et
			// mérite une trace, mais pas de faire échouer tout le résumé.
			zerolog.Ctx(ctx).Warn().Err(cerr).Msg("admin: compteurs HTTP indisponibles pour le résumé")
		} else {
			out.HTTP = HTTPStats{
				RequestsTotal:      totals.Requests,
				ClientErrorsTotal:  totals.ClientErrors,
				ServerErrorsTotal:  totals.ServerErrors,
				ResponseBytesTotal: totals.ResponseBytes,
			}
			if totals.Requests > 0 {
				out.HTTP.ServerErrorRate = float64(totals.ServerErrors) / float64(totals.Requests)
			}
		}
	}
	return out, nil
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
		// Champs structurés plutôt qu'une phrase interpolée : c'est ce qui rend
		// la trace requêtable dans Loki (ADR 018), et `zerolog.Ctx` la corrèle
		// au request_id posé par le middleware d'accès.
		zerolog.Ctx(ctx).Error().Err(err).
			Str("stream_id", streamID).
			Str("actor_id", actorID).
			Msg("admin: interruption de flux non journalisée")
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
