CREATE TABLE IF NOT EXISTS playlists (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name        TEXT        NOT NULL,
    description TEXT,
    is_public   BOOLEAN     NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS playlist_tracks (
    playlist_id UUID        NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
    track_id    UUID        NOT NULL REFERENCES tracks(id)    ON DELETE CASCADE,
    position    INTEGER     NOT NULL CHECK (position >= 0),
    added_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (playlist_id, track_id)
);

CREATE INDEX idx_playlists_user_id ON playlists(user_id);
CREATE INDEX idx_pt_playlist_pos   ON playlist_tracks(playlist_id, position);
