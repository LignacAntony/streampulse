CREATE TABLE IF NOT EXISTS profiles (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID        NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    pseudo     TEXT,
    bio        TEXT        NOT NULL DEFAULT '',
    avatar_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_profiles_user_id ON profiles(user_id);
