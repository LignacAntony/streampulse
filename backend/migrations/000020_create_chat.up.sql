-- Messages de chat attachés à un flux en direct (US-09-01).
-- Soft-delete via deleted_at pour la modération par le diffuseur.
CREATE TABLE IF NOT EXISTS chat_messages (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    stream_id  UUID        NOT NULL REFERENCES streams(id) ON DELETE CASCADE,
    user_id    UUID        NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
    content    TEXT        NOT NULL CHECK (char_length(content) BETWEEN 1 AND 500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_chat_messages_stream_created ON chat_messages(stream_id, created_at);

-- Bannissements de chat (US-09-01). Un diffuseur bannit un utilisateur de TOUS
-- ses futurs chats (scoped par banned_by, pas par stream_id).
CREATE TABLE IF NOT EXISTS chat_bans (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    banned_user_id UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    banned_by      UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason         TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (banned_user_id, banned_by)
);

CREATE INDEX idx_chat_bans_broadcaster ON chat_bans(banned_by);
