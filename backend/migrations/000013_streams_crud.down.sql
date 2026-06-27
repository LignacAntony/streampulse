DROP INDEX IF EXISTS idx_streams_public_live;
ALTER TABLE streams DROP COLUMN IF EXISTS archived_at;
ALTER TABLE streams ADD CONSTRAINT uq_streams_user_title UNIQUE (user_id, title);
