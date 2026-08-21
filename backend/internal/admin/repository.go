package admin

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	admindb "github.com/LignacAntony/streampulse/internal/admin/db"
	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

type pgRepository struct {
	pool *pgxpool.Pool
	q    *admindb.Queries
}

// NewRepository construit le repository PostgreSQL du domaine admin.
func NewRepository(pool *pgxpool.Pool) Repository {
	return &pgRepository{pool: pool, q: admindb.New(pool)}
}

// ListUsers renvoie la page demandée et le total de correspondances (toutes
// pages confondues), via deux requêtes séparées (fix #2 revue PR #264) : un
// COUNT(*) OVER() porté par les lignes renvoyées retomberait à 0 dès que
// l'offset dépasse le nombre de lignes filtrées (page vide), alors que le
// total réel n'a pas changé. AdminCountUsers applique les mêmes filtres,
// sans LIMIT/OFFSET.
func (r *pgRepository) ListUsers(ctx context.Context, in ListUsersInput) ([]AdminUser, int64, error) {
	search := escapeLikePattern(in.Search)

	rows, err := r.q.AdminListUsers(ctx, admindb.AdminListUsersParams{
		Search:       search,
		RoleFilter:   in.Role,
		StatusFilter: in.Status,
		Lim:          in.Limit,
		Off:          in.Offset,
	})
	if err != nil {
		return nil, 0, fmt.Errorf("repo: list users: %w", err)
	}

	users := make([]AdminUser, 0, len(rows))
	for _, row := range rows {
		users = append(users, AdminUser{
			ID:        row.ID.String(),
			Email:     row.Email,
			Username:  row.Username,
			Role:      row.Role,
			IsActive:  row.IsActive,
			CreatedAt: row.CreatedAt,
		})
	}

	total, err := r.q.AdminCountUsers(ctx, admindb.AdminCountUsersParams{
		Search:       search,
		RoleFilter:   in.Role,
		StatusFilter: in.Status,
	})
	if err != nil {
		return nil, 0, fmt.Errorf("repo: count users: %w", err)
	}

	return users, total, nil
}

func (r *pgRepository) GetUser(ctx context.Context, userID string) (AdminUser, error) {
	uid, ok := parseUUID(userID)
	if !ok {
		return AdminUser{}, apperror.NotFound("user not found")
	}
	row, err := r.q.AdminGetUser(ctx, uid)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return AdminUser{}, apperror.NotFound("user not found")
		}
		return AdminUser{}, fmt.Errorf("repo: get user: %w", err)
	}
	return AdminUser{
		ID:        row.ID.String(),
		Email:     row.Email,
		Username:  row.Username,
		Role:      row.Role,
		IsActive:  row.IsActive,
		CreatedAt: row.CreatedAt,
	}, nil
}

func (r *pgRepository) SetUserActive(ctx context.Context, userID string, active bool) (AdminUser, error) {
	uid, ok := parseUUID(userID)
	if !ok {
		return AdminUser{}, apperror.NotFound("user not found")
	}
	row, err := r.q.AdminSetUserActive(ctx, admindb.AdminSetUserActiveParams{
		UserID: uid,
		Active: active,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return AdminUser{}, apperror.NotFound("user not found")
		}
		return AdminUser{}, fmt.Errorf("repo: set user active: %w", err)
	}
	return AdminUser{
		ID:        row.ID.String(),
		Email:     row.Email,
		Username:  row.Username,
		Role:      row.Role,
		IsActive:  row.IsActive,
		CreatedAt: row.CreatedAt,
	}, nil
}

func (r *pgRepository) CountActiveAdmins(ctx context.Context) (int64, error) {
	n, err := r.q.AdminCountActiveAdmins(ctx)
	if err != nil {
		return 0, fmt.Errorf("repo: count active admins: %w", err)
	}
	return n, nil
}

// UserCounts retourne la population de comptes pour le résumé admin (STR-244).
func (r *pgRepository) UserCounts(ctx context.Context) (UserCounts, error) {
	row, err := r.q.AdminUserCounts(ctx)
	if err != nil {
		return UserCounts{}, fmt.Errorf("repo: user counts: %w", err)
	}
	return UserCounts{
		Total:        row.Total,
		Active:       row.Active,
		Broadcasters: row.Broadcasters,
		Admins:       row.Admins,
	}, nil
}

// DeleteUser traduit une suppression de 0 ligne (id inconnu, ou déjà supprimé)
// en NotFound, au même titre qu'un UUID invalide.
func (r *pgRepository) DeleteUser(ctx context.Context, userID string) error {
	uid, ok := parseUUID(userID)
	if !ok {
		return apperror.NotFound("user not found")
	}
	n, err := r.q.AdminDeleteUser(ctx, uid)
	if err != nil {
		return fmt.Errorf("repo: delete user: %w", err)
	}
	if n == 0 {
		return apperror.NotFound("user not found")
	}
	return nil
}

// ListLiveStreams renvoie la liste de modération (tous les live, publics et
// privés confondus) + le total, via deux requêtes séparées — même raison que
// ListUsers : un COUNT(*) OVER() porté par les lignes renvoyées retomberait à
// 0 dès qu'une page est vide (offset au-delà du total réel), cf. AdminCountUsers.
func (r *pgRepository) ListLiveStreams(ctx context.Context, limit, offset int32) ([]AdminStream, int64, error) {
	rows, err := r.q.AdminListLiveStreams(ctx, admindb.AdminListLiveStreamsParams{
		Lim: limit,
		Off: offset,
	})
	if err != nil {
		return nil, 0, fmt.Errorf("repo: list live streams: %w", err)
	}

	streams := make([]AdminStream, 0, len(rows))
	for _, row := range rows {
		streams = append(streams, AdminStream{
			ID:        row.ID.String(),
			Title:     row.Title,
			IsPublic:  row.IsPublic,
			StartedAt: timestamptzToTimePtr(row.StartedAt),
			UserID:    row.UserID.String(),
			Username:  row.Username,
		})
	}

	total, err := r.q.AdminCountLiveStreams(ctx)
	if err != nil {
		return nil, 0, fmt.Errorf("repo: count live streams: %w", err)
	}

	return streams, total, nil
}

// InsertAuditLog journalise une action de modération. actorID/targetID sont
// parsés défensivement (parseUUID), mais contrairement aux ID de path HTTP
// traités ailleurs dans ce repository, un échec de parse ici serait un bug
// interne plutôt qu'une entrée utilisateur invalide : actorID vient du sub JWT
// (déjà vérifié par auth.RequireAuth) et streamID a déjà été validé par
// ForceStopStream (le moderator échoue et StopStream renvoie avant d'atteindre
// cet appel, cf. service.go) — une erreur wrappée suffit, pas de traduction
// NotFound-style.
func (r *pgRepository) InsertAuditLog(ctx context.Context, actorID, action, targetType, targetID string) error {
	actor, ok := parseUUID(actorID)
	if !ok {
		return fmt.Errorf("repo: insert audit log: invalid actor id %q", actorID)
	}
	target, ok := parseUUID(targetID)
	if !ok {
		return fmt.Errorf("repo: insert audit log: invalid target id %q", targetID)
	}
	if err := r.q.InsertAuditLog(ctx, admindb.InsertAuditLogParams{
		ActorID:    actor,
		Action:     action,
		TargetType: targetType,
		TargetID:   target,
	}); err != nil {
		return fmt.Errorf("repo: insert audit log: %w", err)
	}
	return nil
}

// timestamptzToTimePtr convertit un timestamptz nullable (pgx) en *time.Time
// domaine : nil si NULL en base (started_at d'un flux jamais passé live),
// pointeur vers la valeur sinon. Miroir de parseUUID (traduction pgx ->
// domaine) : ce domaine n'a pas d'override sqlc pour les timestamptz
// nullables (contrairement à internal/streaming/sqlc.yaml, qui mappe déjà
// vers *time.Time), la conversion est donc explicite ici plutôt que déléguée
// à la génération de code.
func timestamptzToTimePtr(t pgtype.Timestamptz) *time.Time {
	if !t.Valid {
		return nil
	}
	v := t.Time
	return &v
}

// likeEscaper échappe les métacaractères ILIKE ('\', '%', '_') d'un terme de
// recherche utilisateur avant de l'insérer dans un motif LIKE/ILIKE (cf.
// admin.sql, ESCAPE '\'). '\' doit être remplacé en premier pour ne pas
// ré-échapper les '\' qu'on vient d'insérer ; strings.Replacer applique tous
// ses remplacements en un seul passage sur la chaîne d'origine, donc l'ordre
// des paires n'introduit pas de double échappement.
var likeEscaper = strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`)

// escapeLikePattern échappe s pour qu'un '_' ou '%' tapé par l'utilisateur
// soit traité comme littéral, et non comme joker SQL, une fois inséré entre
// deux '%' par AdminListUsers/AdminCountUsers (fix #4 revue PR #264 : une
// recherche "a_b" ne doit matcher que "a_b", pas "axb").
func escapeLikePattern(s string) string {
	return likeEscaper.Replace(s)
}

// parseUUID convertit un UUID fourni par l'appelant (ex. path param du handler)
// sans paniquer : un format invalide est traité comme "utilisateur introuvable".
func parseUUID(s string) (pgtype.UUID, bool) {
	var u pgtype.UUID
	if err := u.Scan(s); err != nil {
		return u, false
	}
	return u, true
}
