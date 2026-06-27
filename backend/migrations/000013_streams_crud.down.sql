DROP INDEX IF EXISTS idx_streams_public_live;
ALTER TABLE streams DROP COLUMN IF EXISTS archived_at;

-- Restaure l'ancienne contrainte d'unicité (cf. 000006). ⚠️ Ce rollback ÉCHOUE
-- si des doublons (user_id, title) ont été créés pendant que la contrainte était
-- absente — c'est le comportement attendu : les titres ne sont plus uniques par
-- décision métier (ADR 013), ce down ne sert qu'à revenir à l'état pré-000013 sur
-- une base sans doublon. Dédupliquer manuellement avant de migrer down si besoin.
ALTER TABLE streams ADD CONSTRAINT uq_streams_user_title UNIQUE (user_id, title);
