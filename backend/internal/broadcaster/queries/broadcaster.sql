-- name: GetUserRole :one
SELECT role
FROM users
WHERE id = sqlc.arg(user_id)::uuid AND is_active = true;

-- name: CreateBroadcasterRequest :one
INSERT INTO broadcaster_requests (user_id, message)
VALUES (sqlc.arg(user_id)::uuid, sqlc.arg(message)::text)
RETURNING id::text AS id, user_id::text AS user_id, status, message,
          review_note, reviewed_by, created_at, updated_at;

-- name: GetLatestRequestByUser :one
SELECT id::text AS id, user_id::text AS user_id, status, message,
       review_note, reviewed_by, created_at, updated_at
FROM broadcaster_requests
WHERE user_id = sqlc.arg(user_id)::uuid
ORDER BY created_at DESC
LIMIT 1;

-- name: ListBroadcasterRequests :many
SELECT br.id::text AS id, br.user_id::text AS user_id, u.email, u.username,
       br.status, br.message, br.review_note, br.reviewed_by,
       br.created_at, br.updated_at
FROM broadcaster_requests br
JOIN users u ON u.id = br.user_id
WHERE (sqlc.narg(status)::text IS NULL OR br.status = sqlc.narg(status)::text)
ORDER BY br.created_at DESC;

-- name: GetRequestForReview :one
-- FOR UPDATE : verrouille la ligne pendant la transaction de traitement
-- pour éviter qu'un second admin traite la même demande en parallèle.
SELECT id::text AS id, user_id::text AS user_id, status, message,
       review_note, reviewed_by, created_at, updated_at
FROM broadcaster_requests
WHERE id = sqlc.arg(id)::uuid
FOR UPDATE;

-- name: ReviewRequest :one
UPDATE broadcaster_requests
SET status      = sqlc.arg(status)::text,
    reviewed_by = sqlc.arg(reviewed_by)::uuid,
    review_note = sqlc.arg(review_note)::text,
    updated_at  = NOW()
WHERE id = sqlc.arg(id)::uuid AND status = 'pending'
RETURNING id::text AS id, user_id::text AS user_id, status, message,
          review_note, reviewed_by, created_at, updated_at;

-- name: PromoteUserToBroadcaster :execrows
UPDATE users
SET role = 'broadcaster', updated_at = NOW()
WHERE id = sqlc.arg(user_id)::uuid AND role = 'user' AND is_active = true;
