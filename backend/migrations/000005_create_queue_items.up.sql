CREATE TABLE IF NOT EXISTS queue_items (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID        NOT NULL REFERENCES users(id)  ON DELETE CASCADE,
    track_id   UUID        NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    position   INTEGER     NOT NULL CHECK (position >= 0),
    added_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_queue_user_pos ON queue_items(user_id, position);
