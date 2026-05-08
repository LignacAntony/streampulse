-- name: InsertPasswordResetToken :exec
INSERT INTO password_reset_tokens (user_id, token_hash, expires_at)
VALUES (sqlc.arg(user_id)::uuid, sqlc.arg(token_hash), sqlc.arg(expires_at));

-- name: DeletePendingPasswordResetsByUser :exec
DELETE FROM password_reset_tokens
WHERE user_id = sqlc.arg(user_id)::uuid
  AND used_at IS NULL;

-- name: GetValidPasswordResetToken :one
SELECT user_id::text
FROM password_reset_tokens
WHERE token_hash = $1
  AND expires_at > NOW()
  AND used_at IS NULL;

-- name: MarkPasswordResetTokenUsed :exec
UPDATE password_reset_tokens
SET used_at = NOW()
WHERE token_hash = $1;

-- name: UpdateUserPasswordHash :exec
UPDATE users
SET password_hash = sqlc.arg(password_hash)
WHERE id = sqlc.arg(id)::uuid;
