-- name: CreatePlaylist :one
-- Création d'une playlist vide. La contrainte uq_playlists_user_name (000006)
-- garantit l'unicité (user_id, name) : un doublon lève un 23505 -> 409 au repo.
INSERT INTO playlists (user_id, name, description)
VALUES (
    sqlc.arg(user_id)::uuid,
    sqlc.arg(name)::text,
    sqlc.narg(description)::text
)
RETURNING id::text AS id, user_id::text AS user_id, name, description, is_public,
          0::bigint AS track_count, created_at, updated_at;

-- name: ListPlaylistsByUser :many
-- Playlists de l'utilisateur, avec le nombre de pistes (LEFT JOIN pour compter 0
-- sur une playlist vide). Triées par date de création décroissante.
SELECT p.id::text AS id, p.user_id::text AS user_id, p.name, p.description, p.is_public,
       COUNT(pt.track_id) AS track_count, p.created_at, p.updated_at
FROM playlists p
LEFT JOIN playlist_tracks pt ON pt.playlist_id = p.id
WHERE p.user_id = sqlc.arg(user_id)::uuid
GROUP BY p.id
ORDER BY p.created_at DESC;

-- name: GetPlaylistByID :one
-- Une playlist par id (avec track_count). Le contrôle de propriété est fait par
-- le service à partir du user_id renvoyé.
SELECT p.id::text AS id, p.user_id::text AS user_id, p.name, p.description, p.is_public,
       COUNT(pt.track_id) AS track_count, p.created_at, p.updated_at
FROM playlists p
LEFT JOIN playlist_tracks pt ON pt.playlist_id = p.id
WHERE p.id = sqlc.arg(id)::uuid
GROUP BY p.id;

-- name: UpdatePlaylist :one
-- Renommage/description, restreint au propriétaire (id + user_id). 0 ligne -> le
-- repo renvoie NotFound ; collision de nom -> 23505 -> 409.
UPDATE playlists
SET name = sqlc.arg(name)::text,
    description = sqlc.narg(description)::text,
    updated_at = NOW()
WHERE id = sqlc.arg(id)::uuid AND user_id = sqlc.arg(user_id)::uuid
RETURNING id::text AS id, user_id::text AS user_id, name, description, is_public,
          (SELECT COUNT(*) FROM playlist_tracks pt WHERE pt.playlist_id = playlists.id) AS track_count,
          created_at, updated_at;

-- name: DeletePlaylist :one
-- Suppression définitive, restreinte au propriétaire. playlist_tracks est purgé
-- en cascade (FK ON DELETE CASCADE). 0 ligne -> NotFound.
DELETE FROM playlists
WHERE id = sqlc.arg(id)::uuid AND user_id = sqlc.arg(user_id)::uuid
RETURNING id::text AS id;

-- name: ListPlaylistTracks :many
-- Pistes d'une playlist, ordonnées par position. artist et duration_s sont
-- nullables (cf. table tracks). Le contrôle de propriété de la playlist est fait
-- par le service en amont.
SELECT t.id::text AS id, t.title, t.artist, t.duration_s, pt.position
FROM playlist_tracks pt
JOIN tracks t ON t.id = pt.track_id
WHERE pt.playlist_id = sqlc.arg(playlist_id)::uuid
ORDER BY pt.position;

-- name: AddTrackToPlaylist :one
-- Ajout en fin de playlist. Le SELECT source restreint aux pistes du demandeur
-- OU aux pistes publiques d'un tiers : une piste inconnue, privée d'un tiers,
-- ne produit aucune ligne -> le repo renvoie NotFound. Une piste déjà présente
-- viole la PK -> 23505 -> 409.
INSERT INTO playlist_tracks (playlist_id, track_id, position)
SELECT sqlc.arg(playlist_id)::uuid,
       t.id,
       COALESCE(
           (SELECT MAX(pt.position) + 1
            FROM playlist_tracks pt
            WHERE pt.playlist_id = sqlc.arg(playlist_id)::uuid),
           0
       )
FROM tracks t
WHERE t.id = sqlc.arg(track_id)::uuid
  AND (t.user_id = sqlc.arg(user_id)::uuid OR t.is_public = true)
RETURNING track_id::text AS track_id, position;

-- name: RemoveTrackFromPlaylist :one
-- Retrait d'une piste. 0 ligne -> NotFound (piste absente de la playlist).
DELETE FROM playlist_tracks
WHERE playlist_id = sqlc.arg(playlist_id)::uuid
  AND track_id = sqlc.arg(track_id)::uuid
RETURNING track_id::text AS track_id;

-- name: ResequencePlaylistTracks :exec
-- Recompacte les positions en 0..n-1 après un retrait, pour qu'aucun trou ne
-- subsiste (le réordonnancement suivant repartirait sur des index faussés).
UPDATE playlist_tracks pt
SET position = ranked.rn - 1
FROM (
    SELECT track_id, ROW_NUMBER() OVER (ORDER BY position) AS rn
    FROM playlist_tracks
    WHERE playlist_id = sqlc.arg(playlist_id)::uuid
) ranked
WHERE pt.playlist_id = sqlc.arg(playlist_id)::uuid
  AND pt.track_id = ranked.track_id
  AND pt.position <> ranked.rn - 1;

-- name: CountPlaylistTracks :one
SELECT COUNT(*) AS total
FROM playlist_tracks
WHERE playlist_id = sqlc.arg(playlist_id)::uuid;

-- name: ReorderPlaylistTracks :execrows
-- Réécriture complète de l'ordre : la position de chaque piste vient de son rang
-- dans le tableau fourni (WITH ORDINALITY). Le nombre de lignes touchées est
-- comparé à l'effectif de la playlist par le repo -> un id étranger à la
-- playlist fait échouer l'opération.
UPDATE playlist_tracks pt
SET position = ord.pos
FROM (
    SELECT u.id AS track_id, (u.idx - 1)::int AS pos
    FROM unnest(sqlc.arg(track_ids)::uuid[]) WITH ORDINALITY AS u(id, idx)
) ord
WHERE pt.playlist_id = sqlc.arg(playlist_id)::uuid
  AND pt.track_id = ord.track_id;

-- name: TouchPlaylist :exec
-- Met à jour updated_at de la playlist après une mutation de ses pistes.
UPDATE playlists SET updated_at = NOW() WHERE id = sqlc.arg(id)::uuid;
