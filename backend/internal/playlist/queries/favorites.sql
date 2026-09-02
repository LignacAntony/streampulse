-- name: AddPlaylistFavorite :exec
-- Ajout idempotent : un favori déjà présent ne lève pas d'erreur.
INSERT INTO playlist_favorites (user_id, playlist_id)
VALUES (sqlc.arg(user_id)::uuid, sqlc.arg(playlist_id)::uuid)
ON CONFLICT DO NOTHING;

-- name: RemovePlaylistFavorite :exec
-- Suppression idempotente : aucun effet si le favori n'existe pas.
DELETE FROM playlist_favorites
WHERE user_id = sqlc.arg(user_id)::uuid AND playlist_id = sqlc.arg(playlist_id)::uuid;
