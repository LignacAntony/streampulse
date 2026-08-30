ALTER TABLE tracks ADD COLUMN is_public BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX idx_tracks_public ON tracks (created_at DESC) WHERE is_public = true;
