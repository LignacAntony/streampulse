CREATE TABLE IF NOT EXISTS streams (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title       TEXT        NOT NULL,
    description TEXT,
    category    TEXT,
    status      TEXT        NOT NULL DEFAULT 'idle'
                            CHECK (status IN ('idle', 'live', 'ended')),
    is_public   BOOLEAN     NOT NULL DEFAULT true,
    started_at  TIMESTAMPTZ,
    ended_at    TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_streams_user_id ON streams(user_id);
CREATE INDEX idx_streams_status  ON streams(status);
