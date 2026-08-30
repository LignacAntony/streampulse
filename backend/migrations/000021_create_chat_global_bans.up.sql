CREATE TABLE IF NOT EXISTS chat_global_bans (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    banned_user_id UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE UNIQUE,
    banned_by      UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason         TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
