-- name: CreateStream :one
INSERT INTO streams (user_id, title, description, category, status, is_public, stream_key)
VALUES (
    sqlc.arg(user_id)::uuid,
    sqlc.arg(title)::text,
    sqlc.narg(description)::text,
    sqlc.narg(category)::text,
    sqlc.arg(status)::text,
    sqlc.arg(is_public)::boolean,
    sqlc.arg(stream_key)::text
)
RETURNING id::text AS id, user_id::text AS user_id, title, description, category,
          status, is_public, stream_key, created_at, updated_at;

-- name: ListPublicLiveStreams :many
-- Flux publics en direct, non archivés. Le stream_key n'est jamais exposé ici.
SELECT id::text AS id, user_id::text AS user_id, title, description, category,
       status, is_public, started_at, ended_at, created_at, updated_at
FROM streams
WHERE is_public = true AND status = 'live' AND archived_at IS NULL
ORDER BY started_at DESC NULLS LAST, created_at DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);
