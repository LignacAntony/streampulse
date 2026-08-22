-- name: InsertChatMessage :one
INSERT INTO chat_messages (stream_id, user_id, content)
VALUES (@stream_id::uuid, @user_id::uuid, @content::text)
RETURNING id::text, stream_id::text, user_id::text, content, created_at;

-- name: SoftDeleteChatMessage :execresult
UPDATE chat_messages SET deleted_at = NOW()
WHERE id = @id::uuid AND deleted_at IS NULL
  AND stream_id IN (SELECT s.id FROM streams s WHERE s.user_id = @broadcaster_id::uuid);

-- name: InsertChatBan :exec
INSERT INTO chat_bans (banned_user_id, banned_by, reason)
VALUES (@banned_user_id::uuid, @banned_by::uuid, sqlc.narg(reason)::text)
ON CONFLICT (banned_user_id, banned_by) DO NOTHING;

-- name: IsChatBanned :one
SELECT EXISTS(
    SELECT 1 FROM chat_bans
    WHERE banned_user_id = @user_id::uuid AND banned_by = @broadcaster_id::uuid
) AS banned;

-- name: ListRecentChatMessages :many
SELECT m.id::text AS id, m.stream_id::text AS stream_id,
       m.user_id::text AS user_id, u.username AS username,
       m.content AS content, m.created_at AS created_at
FROM chat_messages m
JOIN users u ON u.id = m.user_id
WHERE m.stream_id = @stream_id::uuid AND m.deleted_at IS NULL
ORDER BY m.created_at DESC
LIMIT @lim;

-- name: DeleteChatBan :execresult
DELETE FROM chat_bans
WHERE banned_user_id = @banned_user_id::uuid AND banned_by = @banned_by::uuid;

-- name: ListChatBans :many
SELECT b.banned_user_id::text AS banned_user_id, u.username AS username,
       b.reason AS reason, b.created_at AS created_at
FROM chat_bans b
JOIN users u ON u.id = b.banned_user_id
WHERE b.banned_by = @banned_by::uuid
ORDER BY b.created_at DESC;

-- name: GetUsername :one
SELECT username FROM users WHERE id = @user_id::uuid;
