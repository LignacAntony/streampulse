-- name: AdminListUsers :many
SELECT id, email, username, role, is_active, created_at,
       COUNT(*) OVER() AS total_count
FROM users
WHERE (sqlc.arg(search)::text = '' OR email ILIKE '%' || sqlc.arg(search) || '%' OR username ILIKE '%' || sqlc.arg(search) || '%')
  AND (sqlc.arg(role_filter)::text = '' OR role = sqlc.arg(role_filter))
  AND (sqlc.arg(status_filter)::text = ''
       OR (sqlc.arg(status_filter) = 'active' AND is_active)
       OR (sqlc.arg(status_filter) = 'inactive' AND NOT is_active))
ORDER BY created_at DESC, id DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

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
