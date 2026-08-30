-- name: RecordPlay :exec
-- Enregistre un événement d'écoute (US-09-04). Appelé best-effort depuis la
-- lecture d'une piste : un échec ne doit jamais casser la lecture (le handler
-- l'avale et le journalise).
INSERT INTO listening_history (user_id, track_id)
VALUES (sqlc.arg(user_id)::uuid, sqlc.arg(track_id)::uuid);

-- name: RecommendTracks :many
-- Recommandation « simple » basée sur l'historique d'écoute (US-09-04). Le vivier
-- de candidats = les pistes que le demandeur peut LIRE : les siennes (toute
-- visibilité) + les pistes PUBLIQUES des autres (STR-248 a rendu la lecture
-- cross-user possible pour les pistes publiques). Classement :
--   1. les pistes jamais écoutées d'abord (à découvrir) ;
--   2. puis par affinité : plus l'artiste a été écouté, plus il remonte ;
--   3. puis les moins récemment écoutées (redécouverte) ;
--   4. puis les plus récemment ajoutées.
-- Cold-start (aucun historique) : toutes les affinités valent 0 et toutes les
-- pistes sont « jamais écoutées » → l'ordre retombe sur les ajouts récents (mêlant
-- ma bibliothèque et le catalogue public), un résultat utile plutôt qu'une liste
-- vide. `from_others` distingue une piste publique d'un tiers pour en dériver la
-- raison côté service.
WITH artist_affinity AS (
    SELECT t.artist AS artist, COUNT(*) AS plays
    FROM listening_history lh
    JOIN tracks t ON t.id = lh.track_id
    WHERE lh.user_id = sqlc.arg(user_id)::uuid
      AND t.artist IS NOT NULL
    GROUP BY t.artist
),
last_play AS (
    SELECT track_id, MAX(played_at) AS last_played_at
    FROM listening_history
    WHERE user_id = sqlc.arg(user_id)::uuid
    GROUP BY track_id
)
SELECT
    c.id::text                    AS id,
    c.title                       AS title,
    c.artist                      AS artist,
    c.duration_s                  AS duration_s,
    COALESCE(aa.plays, 0)::bigint AS artist_plays,
    (lp.track_id IS NULL)::boolean AS never_played,
    (c.user_id <> sqlc.arg(user_id)::uuid)::boolean AS from_others
FROM tracks c
LEFT JOIN artist_affinity aa ON aa.artist = c.artist
LEFT JOIN last_play       lp ON lp.track_id = c.id
WHERE c.user_id = sqlc.arg(user_id)::uuid
   OR c.is_public = true
ORDER BY
    (lp.track_id IS NULL) DESC,
    COALESCE(aa.plays, 0) DESC,
    lp.last_played_at ASC NULLS FIRST,
    c.created_at DESC
LIMIT sqlc.arg(lim)::int;
