-- Journal d'audit des actions d'administration (STR-198). Générique : seule
-- l'action 'stream.stopped' est écrite aujourd'hui, la forme couvre les
-- prochaines actions admin sans nouvelle migration.
CREATE TABLE IF NOT EXISTS audit_logs (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    -- SET NULL : la trace survit à la suppression (hard delete) de l'admin.
    actor_id    UUID        REFERENCES users(id) ON DELETE SET NULL,
    action      TEXT        NOT NULL,
    target_type TEXT        NOT NULL,
    target_id   UUID        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs (created_at DESC);
