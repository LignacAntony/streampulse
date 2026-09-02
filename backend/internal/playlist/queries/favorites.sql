-- name: AddPlaylistFavorite :exec
-- Ajout idempotent : un favori déjà présent ne lève pas d'erreur.
INSERT INTO playlist_favorites (user_id, playlist_id)
VALUES (sqlc.arg(user_id)::uuid, sqlc.arg(playlist_id)::uuid)
ON CONFLICT DO NOTHING;

-- name: RemovePlaylistFavorite :exec
-- Suppression idempotente : aucun effet si le favori n'existe pas.
DELETE FROM playlist_favorites
WHERE user_id = sqlc.arg(user_id)::uuid AND playlist_id = sqlc.arg(playlist_id)::uuid;

-- name: ListFavoritePlaylistsByUser :many
-- Playlists épinglées par le demandeur, avec leur nombre de pistes, triées par
-- date d'ajout du favori (desc). is_favorite est toujours vrai ici.
SELECT p.id::text AS id, p.user_id::text AS user_id, p.name, p.description, p.is_public,
       COUNT(pt.track_id) AS track_count,
       true AS is_favorite,
       p.created_at, p.updated_at
FROM playlist_favorites pf
JOIN playlists p ON p.id = pf.playlist_id
LEFT JOIN playlist_tracks pt ON pt.playlist_id = p.id
WHERE pf.user_id = sqlc.arg(user_id)::uuid
GROUP BY p.id, pf.created_at
ORDER BY pf.created_at DESC;
