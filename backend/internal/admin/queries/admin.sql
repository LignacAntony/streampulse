-- name: AdminListUsers :many
-- Le terme de recherche est échappé côté repository (escapeLikePattern) avant
-- d'arriver ici : '\' est le caractère d'échappement explicite (ESCAPE '\'),
-- pour que '_' et '%' tapés par l'utilisateur soient littéraux, pas des
-- jokers ILIKE (cf. revue PR #264 fix #4).
SELECT id, email, username, role, is_active, created_at
FROM users
WHERE (sqlc.arg(search)::text = '' OR email ILIKE '%' || sqlc.arg(search) || '%' ESCAPE '\' OR username ILIKE '%' || sqlc.arg(search) || '%' ESCAPE '\')
  AND (sqlc.arg(role_filter)::text = '' OR role = sqlc.arg(role_filter))
  AND (sqlc.arg(status_filter)::text = ''
       OR (sqlc.arg(status_filter) = 'active' AND is_active)
       OR (sqlc.arg(status_filter) = 'inactive' AND NOT is_active))
ORDER BY created_at DESC, id DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: AdminCountUsers :one
-- Total de pagination indépendant de LIMIT/OFFSET (cf. revue PR #264 fix #2) :
-- COUNT(*) OVER() n'est porté que par les lignes renvoyées par AdminListUsers,
-- donc une page vide (offset au-delà du nombre de lignes filtrées) renvoyait
-- total=0 au lieu du vrai total de correspondances. Mêmes filtres que
-- AdminListUsers, sans LIMIT/OFFSET.
SELECT COUNT(*)
FROM users
WHERE (sqlc.arg(search)::text = '' OR email ILIKE '%' || sqlc.arg(search) || '%' ESCAPE '\' OR username ILIKE '%' || sqlc.arg(search) || '%' ESCAPE '\')
  AND (sqlc.arg(role_filter)::text = '' OR role = sqlc.arg(role_filter))
  AND (sqlc.arg(status_filter)::text = ''
       OR (sqlc.arg(status_filter) = 'active' AND is_active)
       OR (sqlc.arg(status_filter) = 'inactive' AND NOT is_active));

-- name: AdminGetUser :one
SELECT id, email, username, role, is_active, created_at FROM users WHERE id = sqlc.arg(user_id)::uuid;

-- name: AdminSetUserActive :one
UPDATE users SET is_active = sqlc.arg(active), updated_at = NOW()
WHERE id = sqlc.arg(user_id)::uuid
RETURNING id, email, username, role, is_active, created_at;

-- name: AdminCountActiveAdmins :one
SELECT COUNT(*) FROM users WHERE role = 'admin' AND is_active = true;

-- name: AdminDeleteUser :execrows
DELETE FROM users WHERE id = sqlc.arg(user_id)::uuid;

-- name: AdminListLiveStreams :many
-- Liste de modération (STR-192) : TOUS les flux en direct, publics ET privés,
-- avec l'identité du diffuseur. Tri stable (started_at puis id).
SELECT s.id, s.title, s.is_public, s.started_at, s.user_id, u.username
FROM streams s
JOIN users u ON u.id = s.user_id
WHERE s.status = 'live' AND s.archived_at IS NULL
ORDER BY s.started_at DESC, s.id DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: AdminCountLiveStreams :one
-- Total séparé (COUNT(*) OVER() renvoie 0 sur page vide — cf. review STR-191).
SELECT COUNT(*) FROM streams s
WHERE s.status = 'live' AND s.archived_at IS NULL;

-- name: InsertAuditLog :exec
INSERT INTO audit_logs (actor_id, action, target_type, target_id)
VALUES (sqlc.arg(actor_id)::uuid, sqlc.arg(action), sqlc.arg(target_type), sqlc.arg(target_id)::uuid);
