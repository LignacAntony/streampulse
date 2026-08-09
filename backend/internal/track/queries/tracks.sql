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

-- name: GetTrackFileByUser :one
-- Localise le binaire d'une piste **du demandeur**, pour le servir en lecture
-- (US-05-04). Le filtre porte sur (id, user_id) : la piste d'un tiers ne se
-- distingue pas d'une piste inexistante (0 ligne -> 404), donc l'API ne révèle
-- pas l'existence de la bibliothèque d'autrui.
SELECT file_path, mime_type, file_size
FROM tracks
WHERE id = sqlc.arg(id)::uuid
  AND user_id = sqlc.arg(user_id)::uuid;

-- name: SumTrackSizeByUser :one
-- Taille cumulée des fichiers du demandeur, pour appliquer le quota de stockage
-- par compte avant un nouvel upload (borne le remplissage du volume).
SELECT COALESCE(SUM(file_size), 0)::bigint AS total
FROM tracks
WHERE user_id = sqlc.arg(user_id)::uuid;

-- name: ListFilePathsByUser :many
-- Chemins disque des fichiers du demandeur, pour les supprimer du stockage lors
-- de la suppression de son compte (la cascade DB efface les lignes, pas les
-- fichiers).
SELECT file_path
FROM tracks
WHERE user_id = sqlc.arg(user_id)::uuid;
