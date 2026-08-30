DROP INDEX IF EXISTS idx_tracks_public;

ALTER TABLE tracks DROP COLUMN IF EXISTS is_public;
