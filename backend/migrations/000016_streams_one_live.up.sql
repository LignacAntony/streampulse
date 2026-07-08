-- Garantit atomiquement « un seul flux live par diffuseur » (invariant STR-77).
-- Le NOT EXISTS de StartStream ne suffit pas sous READ COMMITTED : deux start
-- concurrents sur des flux idle distincts du même diffuseur peuvent voir chacun
-- un snapshot sans le live de l'autre (write-skew). Un index unique partiel rend
-- l'invariant vraiment atomique (la 2e transaction reçoit un 23505).

-- Sécurité : termine d'éventuels doublons live pré-existants (on garde le plus
-- récent) pour que la création de l'index ne bute pas sur des données invalides.
UPDATE streams s
SET status = 'ended', ended_at = NOW(), updated_at = NOW()
WHERE s.status = 'live' AND s.archived_at IS NULL
  AND s.id <> (
    SELECT o.id FROM streams o
    WHERE o.user_id = s.user_id AND o.status = 'live' AND o.archived_at IS NULL
    ORDER BY o.started_at DESC NULLS LAST, o.created_at DESC
    LIMIT 1
  );

CREATE UNIQUE INDEX streams_one_live_per_user
    ON streams (user_id) WHERE status = 'live' AND archived_at IS NULL;
