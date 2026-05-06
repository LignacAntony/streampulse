-- name: CreateUser :one
INSERT INTO users (email, username, password_hash)
VALUES ($1, $2, $3)
RETURNING id::text, email, username, role, created_at;

-- name: GetUserByEmail :one
SELECT id::text, email, username, role, created_at, password_hash
FROM users
WHERE email = $1 AND is_active = true;

-- name: InsertRefreshToken :exec
INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
VALUES (sqlc.arg(user_id)::uuid, sqlc.arg(token_hash), sqlc.arg(expires_at));

-- name: GetUserByRefreshToken :one
SELECT u.id::text AS id, u.email, u.username, u.role, u.created_at
FROM refresh_tokens rt
JOIN users u ON u.id = rt.user_id
WHERE rt.token_hash = $1
  AND rt.expires_at > NOW()
  AND u.is_active = true;

-- name: DeleteRefreshToken :execresult
DELETE FROM refresh_tokens WHERE token_hash = $1;
