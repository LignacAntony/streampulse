-- Restaure la contrainte NOT NULL. Les comptes OAuth sans mot de passe
-- (password_hash NULL) doivent être purgés au préalable, sinon l'ALTER échoue.
ALTER TABLE users ALTER COLUMN password_hash SET NOT NULL;
