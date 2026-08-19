# ADR 038 — Gestion du profil utilisateur (table `profiles` dédiée)

> **Renumérotée (STR-237)** : cette ADR portait le numéro **012**, déjà attribué à
> [ADR 012 — OpenAPI source de vérité](012-openapi-source-de-verite.md).

## Statut

Accepté — 2026-06-14

## Contexte

STR-44 introduit la gestion du profil : un utilisateur connecté doit pouvoir **consulter et
modifier ses informations personnelles** (pseudo, bio) et ses **préférences d'application**
(thème, notifications, qualité audio), via `GET` / `PUT /api/users/me`.

La table `users` existante ne porte que les données de **compte** (`email`, `username`,
`password_hash`, `role`, `is_active`) créées à l'inscription. Deux options se présentaient pour
héberger les nouvelles données de profil :

1. Ajouter des colonnes (`bio`, `theme`, …) directement à `users`.
2. Créer une table `profiles` distincte reliée à `users`.

Le `username` est l'identifiant **unique et stable** du compte (contrainte `UNIQUE`, utilisé en
interne) ; on ne veut pas qu'une modification d'affichage du pseudo impacte cette identité.

## Décision

**Créer une table `profiles` séparée, en relation 1-1 avec `users`** (migration `000009`), et
exposer le profil via un nouveau domaine `internal/profiles/` calqué sur `internal/auth/`
(handler / service / repository + sqlc), conformément à l'[ADR 008](008-architecture-handler-service-repository.md).

```sql
CREATE TABLE profiles (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    pseudo     TEXT,                       -- nom d'affichage modifiable (NULL => fallback users.username)
    bio        TEXT NOT NULL DEFAULT '',
    avatar_url TEXT,                       -- nullable, placeholder (upload non implémenté)
    theme                 TEXT NOT NULL DEFAULT 'dark'   CHECK (theme IN ('system','light','dark')),
    notifications_enabled BOOLEAN NOT NULL DEFAULT true,
    audio_quality         TEXT NOT NULL DEFAULT 'normal' CHECK (audio_quality IN ('low','normal','high')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

Points clés de la décision :

- **`users` est immuable côté profil.** Le `PUT /api/users/me` n'écrit **que** dans `profiles`.
  Le pseudo modifiable (`profiles.pseudo`, nom d'affichage **non unique**) est distinct de
  `users.username` (identifiant de compte). `email` et `role` restent en lecture seule.
- **Lecture jointe avec repli.** `GetMe` fait un `LEFT JOIN users + profiles` avec
  `COALESCE(p.pseudo, u.username)` et des valeurs par défaut, donc un compte sans profil reste
  consultable.
- **Création automatique via trigger.** Un trigger `AFTER INSERT ON users` (migration `000011`)
  insère la ligne `profiles`, plus un backfill des comptes existants. Garantit qu'un profil existe
  toujours, **sans coupler `auth` à `profiles`** (la création reste dans la couche SQL).
- **`PUT` = remplacement complet** (sémantique PUT) : le corps porte tous les champs modifiables.
- **Préférences avec `CHECK` SQL** (`theme`, `audio_quality`) + validation applicative miroir dans
  le service, mappée en `400 invalid_argument` via `apperror`.
- **Avatar reporté.** Colonne `avatar_url` nullable préparée mais aucun upload : placeholder
  (initiales) côté mobile, à traiter dans un ticket ultérieur.
- **Sécurité.** L'identité provient **exclusivement** du JWT (`auth.UserIDFromContext`), jamais de
  l'URL ni du body ; la route est protégée par `auth.RequireAuth` et le décodage JSON est strict
  (`DisallowUnknownFields`). Un utilisateur ne peut donc lire/modifier que **son** profil.

## Alternatives considérées

### Étendre la table `users`

- **Avantage :** pas de jointure, une seule table.
- **Rejet :** mélange identité de compte et données d'affichage/préférences ; la table `users`
  devient un fourre-tout et chaque champ de préférence la fait grossir. La séparation 1-1 garde
  `users` focalisée sur l'authentification.

### Création du profil dans le code (à l'inscription, côté `auth`)

- **Avantage :** logique visible en Go.
- **Rejet :** couple `auth` à `profiles` et oblige à gérer tous les chemins de création (seeder,
  admin…). Le trigger SQL garantit l'invariant quel que soit le point d'entrée.

### Préférences stockées localement (mobile uniquement)

- **Avantage :** zéro round-trip réseau.
- **Rejet :** l'utilisateur veut des préférences rattachées au compte et synchronisées ; elles
  doivent donc vivre côté serveur.

## Conséquences

### Avantages

- **Séparation claire** compte (`users`) vs profil/préférences (`profiles`), sans toucher à
  l'authentification existante.
- **Invariant fort** : tout compte possède un profil (trigger + backfill), testé de bout en bout.
- **Cohérence d'architecture** : même squelette que `auth`, aucune dépendance tierce ajoutée.
- **Testabilité** : `service_test.go` (fake repo) et `handler_test.go` (stubs + `RequireAuth` avec
  JWT réel) tournent sans Docker.

### Inconvénients

- **Jointure** sur chaque lecture du profil (négligeable, indexée sur `user_id`).
- **`PUT` complet** : le client doit renvoyer tous les champs modifiables (l'app mobile charge puis
  ré-émet l'ensemble).

### Suivi

- Avatar : prévoir l'upload (stockage + validation MIME) dans un ticket dédié — la colonne
  `avatar_url` est déjà en place.
- « Modifier le mot de passe » connecté et « supprimer le compte » sont des routes encore absentes,
  candidates pour un prochain incrément.

## Références

- ADR 008 : [Architecture handler / service / repository](008-architecture-handler-service-repository.md) — squelette suivi par `internal/profiles/`.
- ADR 006 : [Authentification JWT](006-authentification-jwt.md) — `RequireAuth` / identité issue du token.
- ADR 007 : [Génération de code SQL avec sqlc](007-sqlc-generation-code-sql.md) — workflow des queries `profiles`.
- Linear : [STR-44](https://linear.app/streampulse/issue/STR-44) — gestion du profil utilisateur.
