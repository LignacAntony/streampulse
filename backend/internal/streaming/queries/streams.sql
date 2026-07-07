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

-- name: GetStreamByID :one
SELECT id::text AS id, user_id::text AS user_id, title, description, category,
       status, is_public, stream_key, started_at, ended_at, created_at, updated_at
FROM streams
WHERE id = sqlc.arg(id)::uuid AND archived_at IS NULL;

-- name: UpdateStream :one
UPDATE streams
SET title = sqlc.arg(title)::text,
    description = sqlc.narg(description)::text,
    category = sqlc.narg(category)::text,
    is_public = sqlc.arg(is_public)::boolean,
    updated_at = NOW()
WHERE id = sqlc.arg(id)::uuid AND user_id = sqlc.arg(user_id)::uuid AND archived_at IS NULL
RETURNING id::text AS id, user_id::text AS user_id, title, description, category,
          status, is_public, stream_key, started_at, ended_at, created_at, updated_at;

-- name: ArchiveStream :execrows
UPDATE streams
SET archived_at = NOW(), updated_at = NOW()
WHERE id = sqlc.arg(id)::uuid AND user_id = sqlc.arg(user_id)::uuid AND archived_at IS NULL;

-- name: StartStream :one
-- Passe un flux idle -> live. Garde atomique : réservé au propriétaire, flux non
-- archivé, statut idle, ET le diffuseur ne doit avoir aucun autre flux live
-- (règle un-seul-live-à-la-fois). Aucune ligne mise à jour sinon.
UPDATE streams AS s
SET status = 'live', started_at = NOW(), updated_at = NOW()
WHERE s.id = sqlc.arg(id)::uuid
  AND s.user_id = sqlc.arg(user_id)::uuid
  AND s.status = 'idle'
  AND s.archived_at IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM streams o
    WHERE o.user_id = sqlc.arg(user_id)::uuid AND o.status = 'live'
  )
RETURNING id::text AS id, user_id::text AS user_id, title, description, category,
          status, is_public, stream_key, started_at, ended_at, created_at, updated_at;

-- name: StopStream :one
-- Passe un flux live -> ended. Réservé au propriétaire, statut live.
UPDATE streams
SET status = 'ended', ended_at = NOW(), updated_at = NOW()
WHERE id = sqlc.arg(id)::uuid AND user_id = sqlc.arg(user_id)::uuid AND status = 'live'
RETURNING id::text AS id, user_id::text AS user_id, title, description, category,
          status, is_public, stream_key, started_at, ended_at, created_at, updated_at;
