-- STR-XXX : connexion via Google (OAuth).
-- Un compte créé par « Sign in with Google » n'a pas de mot de passe local :
-- password_hash devient nullable. Les comptes email/mot de passe existants
-- restent inchangés (valeur non nulle). La connexion par mot de passe reste
-- sûre pour un compte sans hash : bcrypt échoue face à une chaîne vide
-- (COALESCE côté requête), jamais de connexion sans identifiant.
ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL;
