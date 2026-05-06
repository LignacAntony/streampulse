-- name: InsertPasswordResetToken :exec
INSERT INTO password_reset_tokens (user_id, token_hash, expires_at)
VALUES (sqlc.arg(user_id)::uuid, sqlc.arg(token_hash), sqlc.arg(expires_at));

-- name: DeletePendingPasswordResetsByUser :exec
DELETE FROM password_reset_tokens
WHERE user_id = sqlc.arg(user_id)::uuid
  AND used_at IS NULL;
