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
-- JOIN users pour exposer le username du diffuseur (affiché côté auditeur).
SELECT s.id::text AS id, s.user_id::text AS user_id, s.title, s.description, s.category,
       s.status, s.is_public, s.started_at, s.ended_at, s.created_at, s.updated_at,
       u.username AS broadcaster_username
FROM streams s
JOIN users u ON u.id = s.user_id
WHERE s.is_public = true AND s.status = 'live' AND s.archived_at IS NULL
ORDER BY s.started_at DESC NULLS LAST, s.created_at DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: ListStreamsByOwner :many
-- Flux d'un diffuseur pour son tableau de bord (STR-153) : tous statuts
-- (idle/live/ended), archivés exclus. Contrairement à ListPublicLiveStreams, le
-- stream_key EST sélectionné : le filtre sur user_id garantit que l'appelant est
-- le propriétaire, seul destinataire légitime de ce secret.
SELECT id::text AS id, user_id::text AS user_id, title, description, category,
       status, is_public, stream_key, started_at, ended_at, created_at, updated_at
FROM streams
WHERE user_id = sqlc.arg(user_id)::uuid AND archived_at IS NULL
ORDER BY created_at DESC;

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

-- name: ArchiveStream :one
-- Soft delete. Si le flux était en direct, on le termine (status -> ended) pour
-- ne pas laisser de ligne archivée « live » (cf. garde un-seul-live).
UPDATE streams
SET archived_at = NOW(),
    updated_at = NOW(),
    status = CASE WHEN status = 'live' THEN 'ended' ELSE status END
WHERE id = sqlc.arg(id)::uuid AND user_id = sqlc.arg(user_id)::uuid AND archived_at IS NULL
RETURNING id::text AS id;

-- name: StartStream :one
-- Passe un flux idle -> live (propriétaire, non archivé). La règle « un seul live
-- par diffuseur » est garantie atomiquement par l'index unique partiel
-- streams_one_live_per_user (000016) : un 2e live concurrent lève un 23505.
UPDATE streams AS s
SET status = 'live', started_at = NOW(), updated_at = NOW()
WHERE s.id = sqlc.arg(id)::uuid
  AND s.user_id = sqlc.arg(user_id)::uuid
  AND s.status = 'idle'
  AND s.archived_at IS NULL
RETURNING id::text AS id, user_id::text AS user_id, title, description, category,
          status, is_public, stream_key, started_at, ended_at, created_at, updated_at;

-- name: StopStream :one
-- Passe un flux live -> ended. Réservé au propriétaire, statut live, non archivé.
UPDATE streams
SET status = 'ended', ended_at = NOW(), updated_at = NOW()
WHERE id = sqlc.arg(id)::uuid AND user_id = sqlc.arg(user_id)::uuid
  AND status = 'live' AND archived_at IS NULL
RETURNING id::text AS id, user_id::text AS user_id, title, description, category,
          status, is_public, stream_key, started_at, ended_at, created_at, updated_at;

-- name: EndOrphanLiveStreams :execrows
-- Réconciliation au démarrage : les sessions LiveSessions sont en mémoire et
-- reparties vides après un redémarrage ; on termine les flux restés 'live' en
-- base (orphelins sans session ni audio).
UPDATE streams
SET status = 'ended', ended_at = NOW(), updated_at = NOW()
WHERE status = 'live' AND archived_at IS NULL;

-- name: StopLiveStreamsByUser :many
UPDATE streams SET status = 'ended', ended_at = NOW(), updated_at = NOW()
WHERE user_id = sqlc.arg(user_id)::uuid AND status = 'live'
RETURNING id;

-- name: ForceStopLiveStream :one
-- Interruption par un admin (STR-192) : live -> ended SANS contrôle de
-- propriétaire. L'appelant est derrière RequireRole("admin").
UPDATE streams
SET status = 'ended', ended_at = NOW(), updated_at = NOW()
WHERE id = sqlc.arg(id)::uuid AND status = 'live' AND archived_at IS NULL
RETURNING id::text AS id;
