-- Le titre d'un flux n'a pas à être unique : un diffuseur peut réutiliser un nom
-- dans le temps, et deux diffuseurs peuvent avoir le même titre (on différencie
-- par le diffuseur). On retire donc la contrainte d'unicité (cf. STR-64).
ALTER TABLE streams DROP CONSTRAINT IF EXISTS uq_streams_user_title;

-- Soft delete : un flux supprimé par le diffuseur est archivé (ligne conservée),
-- pas effacé. NULL = actif.
ALTER TABLE streams ADD COLUMN archived_at TIMESTAMPTZ;

-- Index ciblé pour la liste des flux publics en direct et non archivés.
-- L'ordre des colonnes reflète exactement le ORDER BY de ListPublicLiveStreams
-- (started_at DESC NULLS LAST, created_at DESC) pour que l'index le serve.
CREATE INDEX idx_streams_public_live ON streams (started_at DESC NULLS LAST, created_at DESC)
    WHERE is_public AND status = 'live' AND archived_at IS NULL;
