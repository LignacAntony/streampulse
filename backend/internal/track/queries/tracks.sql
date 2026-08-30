-- name: CreateTrack :one
-- Enregistre une piste uploadée dans la bibliothèque du demandeur. Le fichier est
-- déjà écrit sur disque (file_path). mime_type est validé côté serveur et doit
-- appartenir au CHECK de la table (audio/mpeg|aac|ogg). La contrainte
-- uq_tracks_user_title (000006) rend un titre en doublon -> 23505 -> 409 au repo.
INSERT INTO tracks (user_id, title, artist, duration_s, file_path, mime_type, file_size, is_public)
VALUES (
    sqlc.arg(user_id)::uuid,
    sqlc.arg(title)::text,
    sqlc.narg(artist)::text,
    sqlc.narg(duration_s)::int,
    sqlc.arg(file_path)::text,
    sqlc.arg(mime_type)::text,
    sqlc.arg(file_size)::bigint,
    sqlc.arg(is_public)::boolean
)
RETURNING id::text AS id, title, artist, duration_s, is_public;

-- name: ListTracksByUser :many
-- Bibliothèque de pistes du demandeur (source du sélecteur « ajouter une piste »
-- côté mobile). Les plus récentes d'abord.
SELECT id::text AS id, title, artist, duration_s, is_public
FROM tracks
WHERE user_id = sqlc.arg(user_id)::uuid
ORDER BY created_at DESC;

-- name: ListPublicTracks :many
-- Pistes publiques de tous les utilisateurs, pour l'écran de découverte.
-- Paginé par curseur (created_at DESC, id DESC).
SELECT t.id::text AS id, t.title, t.artist, t.duration_s,
       t.created_at, u.username AS owner_name
FROM tracks t
JOIN users u ON u.id = t.user_id
WHERE t.is_public = true
  AND (t.created_at, t.id) < (sqlc.narg(cursor_created_at)::timestamptz, sqlc.narg(cursor_id)::uuid)
ORDER BY t.created_at DESC, t.id DESC
LIMIT sqlc.arg(page_size)::int;

-- name: ListPublicTracksFirst :many
-- Première page de pistes publiques (pas de curseur).
SELECT t.id::text AS id, t.title, t.artist, t.duration_s,
       t.created_at, u.username AS owner_name
FROM tracks t
JOIN users u ON u.id = t.user_id
WHERE t.is_public = true
ORDER BY t.created_at DESC, t.id DESC
LIMIT sqlc.arg(page_size)::int;

-- name: UpdateTrackVisibility :execrows
-- Modifie la visibilité d'une piste. Filtre sur (id, user_id) : seul le
-- propriétaire peut changer la visibilité de sa piste.
UPDATE tracks
SET is_public = sqlc.arg(is_public)::boolean, updated_at = NOW()
WHERE id = sqlc.arg(id)::uuid
  AND user_id = sqlc.arg(user_id)::uuid;

-- name: GetTrackFileByUser :one
-- Localise le binaire d'une piste **du demandeur**, pour le servir en lecture
-- (US-05-04). Le filtre porte sur (id, user_id) : la piste d'un tiers ne se
-- distingue pas d'une piste inexistante (0 ligne -> 404), donc l'API ne révèle
-- pas l'existence de la bibliothèque d'autrui.
SELECT file_path, mime_type
FROM tracks
WHERE id = sqlc.arg(id)::uuid
  AND user_id = sqlc.arg(user_id)::uuid;

-- name: GetTrackFileForStream :one
-- Localise le binaire d'une piste accessible au demandeur : soit sa propre piste,
-- soit une piste publique d'un tiers.
SELECT file_path, mime_type
FROM tracks
WHERE id = sqlc.arg(id)::uuid
  AND (user_id = sqlc.arg(user_id)::uuid OR is_public = true);

-- name: DeleteTrack :one
-- Suppression d'une piste par son propriétaire. Retourne le chemin du fichier
-- pour le supprimer du stockage après le DELETE. La FK ON DELETE CASCADE sur
-- playlist_tracks retire automatiquement la piste de toutes les playlists.
-- 0 ligne = piste inexistante ou d'un tiers -> 404 au repo.
DELETE FROM tracks
WHERE id = sqlc.arg(id)::uuid
  AND user_id = sqlc.arg(user_id)::uuid
RETURNING file_path;

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
