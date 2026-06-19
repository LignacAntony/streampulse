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
