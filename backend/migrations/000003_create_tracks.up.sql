CREATE TABLE IF NOT EXISTS tracks (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title       TEXT        NOT NULL,
    artist      TEXT,
    duration_s  INTEGER     CHECK (duration_s > 0),
    file_path   TEXT        NOT NULL,
    mime_type   TEXT        NOT NULL
                            CHECK (mime_type IN ('audio/mpeg', 'audio/aac', 'audio/ogg')),
    file_size   BIGINT      NOT NULL CHECK (file_size > 0),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_tracks_user_id ON tracks(user_id);
