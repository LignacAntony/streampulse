-- name: CreateUser :one
INSERT INTO users (email, username, password_hash)
VALUES ($1, $2, $3)
RETURNING id::text, email, username, role, created_at;

-- name: CreateOAuthUser :one
-- Compte créé par un fournisseur externe (Google) : aucun mot de passe local,
-- password_hash reste NULL. Même RETURNING que CreateUser.
INSERT INTO users (email, username, password_hash)
VALUES ($1, $2, NULL)
RETURNING id::text, email, username, role, created_at;

-- name: GetUserByEmail :one
-- COALESCE(password_hash, '') : la colonne est nullable (comptes OAuth), mais
-- le code Go continue de recevoir une chaîne. bcrypt échoue face au vide → un
-- compte sans mot de passe ne peut pas être connecté par mot de passe.
SELECT id::text, email, username, role, created_at, COALESCE(password_hash, '')::text AS password_hash
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

-- name: DeleteAllRefreshTokensByUser :exec
DELETE FROM refresh_tokens WHERE user_id = sqlc.arg(user_id)::uuid;

-- name: GetUserByID :one
SELECT id::text, email, username, role, created_at, COALESCE(password_hash, '')::text AS password_hash
FROM users
WHERE id = sqlc.arg(user_id)::uuid AND is_active = true;

-- name: DeleteUserByID :exec
DELETE FROM users WHERE id = sqlc.arg(user_id)::uuid;
