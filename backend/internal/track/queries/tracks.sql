-- name: CreateTrack :one
-- Enregistre une piste uploadée dans la bibliothèque du demandeur. Le fichier est
-- déjà écrit sur disque (file_path). mime_type est validé côté serveur et doit
-- appartenir au CHECK de la table (audio/mpeg|aac|ogg). La contrainte
-- uq_tracks_user_title (000006) rend un titre en doublon -> 23505 -> 409 au repo.
INSERT INTO tracks (user_id, title, artist, duration_s, file_path, mime_type, file_size)
VALUES (
    sqlc.arg(user_id)::uuid,
    sqlc.arg(title)::text,
    sqlc.narg(artist)::text,
    sqlc.narg(duration_s)::int,
    sqlc.arg(file_path)::text,
    sqlc.arg(mime_type)::text,
    sqlc.arg(file_size)::bigint
)
RETURNING id::text AS id, title, artist, duration_s;

-- name: ListTracksByUser :many
-- Bibliothèque de pistes du demandeur (source du sélecteur « ajouter une piste »
-- côté mobile). Les plus récentes d'abord.
SELECT id::text AS id, title, artist, duration_s
FROM tracks
WHERE user_id = sqlc.arg(user_id)::uuid
ORDER BY created_at DESC;
