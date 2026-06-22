CREATE TABLE IF NOT EXISTS broadcaster_requests (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status      TEXT        NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending', 'approved', 'rejected')),
    message     TEXT        NOT NULL DEFAULT '',
    reviewed_by UUID        REFERENCES users(id) ON DELETE SET NULL,
    review_note TEXT        NOT NULL DEFAULT '',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS broadcaster_requests_one_pending
    ON broadcaster_requests (user_id)
    WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS broadcaster_requests_status_created_idx
    ON broadcaster_requests (status, created_at DESC);
