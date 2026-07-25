-- name: AddFavorite :exec
-- Ajout idempotent : un favori déjà présent ne lève pas d'erreur.
INSERT INTO favorites (user_id, stream_id)
VALUES (sqlc.arg(user_id)::uuid, sqlc.arg(stream_id)::uuid)
ON CONFLICT DO NOTHING;

-- name: RemoveFavorite :exec
-- Suppression idempotente : aucun effet si le favori n'existe pas.
DELETE FROM favorites
WHERE user_id = sqlc.arg(user_id)::uuid AND stream_id = sqlc.arg(stream_id)::uuid;

-- name: ListFavoritesByUser :many
-- Flux favoris de l'utilisateur, tous statuts, non archivés. On ne renvoie que
-- les flux encore visibles pour le demandeur (publics, ou lui appartenant) : un
-- flux passé en privé par un tiers après coup disparaît de la liste. Le
-- stream_key n'est jamais exposé ici. Trié par date d'ajout du favori (desc).
SELECT s.id::text AS id, s.user_id::text AS user_id, s.title, s.description, s.category,
       s.status, s.is_public, s.started_at, s.ended_at, s.created_at, s.updated_at
FROM favorites f
JOIN streams s ON s.id = f.stream_id
WHERE f.user_id = sqlc.arg(user_id)::uuid
  AND s.archived_at IS NULL
  AND (s.is_public = true OR s.user_id = sqlc.arg(user_id)::uuid)
ORDER BY f.created_at DESC;
