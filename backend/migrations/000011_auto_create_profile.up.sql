-- Crée automatiquement une ligne profiles à la création d'un utilisateur,
-- afin que chaque compte dispose toujours d'un profil (quel que soit le chemin
-- de création : inscription, seeder, admin…). Garde auth et profiles découplés.
CREATE OR REPLACE FUNCTION create_profile_for_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO profiles (user_id) VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_create_profile_for_user
    AFTER INSERT ON users
    FOR EACH ROW
    EXECUTE FUNCTION create_profile_for_user();

-- Backfill : crée les profils manquants pour les utilisateurs déjà existants.
INSERT INTO profiles (user_id)
SELECT id FROM users
ON CONFLICT (user_id) DO NOTHING;
