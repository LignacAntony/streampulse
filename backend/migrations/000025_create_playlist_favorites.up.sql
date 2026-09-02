-- Favoris utilisateur → playlist (STR-250). Même patron que la table `favorites`
-- des flux (000018) : table de jointure many-to-many, clé primaire composite qui
-- garantit l'unicité (ajout idempotent via ON CONFLICT DO NOTHING), et
-- ON DELETE CASCADE pour nettoyer la ligne si l'utilisateur ou la playlist est
-- supprimé. Les playlists étant personnelles, un utilisateur n'épingle que les
-- siennes — la contrôle de propriété reste fait par le service.
CREATE TABLE IF NOT EXISTS playlist_favorites (
    user_id     UUID        NOT NULL REFERENCES users(id)     ON DELETE CASCADE,
    playlist_id UUID        NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, playlist_id)
);

-- Sert la vitrine « playlists favorites » (accueil), triée par date d'ajout desc.
CREATE INDEX idx_playlist_favorites_user_created
    ON playlist_favorites(user_id, created_at DESC);
