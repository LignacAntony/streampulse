-- Favoris utilisateur → flux (US-04-05). Table de jointure many-to-many :
-- un utilisateur peut mettre en favori plusieurs flux, un flux peut être en
-- favori chez plusieurs utilisateurs. La clé primaire composite garantit
-- l'unicité (pas de doublon) et rend l'ajout idempotent (ON CONFLICT DO NOTHING).
-- ON DELETE CASCADE nettoie automatiquement la ligne si l'utilisateur ou le flux
-- est supprimé.
CREATE TABLE IF NOT EXISTS favorites (
    user_id    UUID        NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
    stream_id  UUID        NOT NULL REFERENCES streams(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, stream_id)
);

-- Sert la liste « mes favoris » triée par date d'ajout décroissante.
CREATE INDEX idx_favorites_user_created ON favorites(user_id, created_at DESC);
