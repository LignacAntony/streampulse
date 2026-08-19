# ADR 037 — Initialisation de la base de données : schéma, migrations et seed

> **Renumérotée (STR-237)** : cette ADR portait le numéro **003**, déjà attribué à
> [ADR 003 — Choix de GitHub Actions pour la CI/CD](003-choix-cicd-github-actions.md).

## Statut

Accepté — 2026-05-03

## Contexte

StreamPulse nécessite une base de données PostgreSQL structurée pour persister les entités
métier : utilisateurs, flux live, pistes audio, playlists et files d'attente.

Trois besoins distincts ont été identifiés :

1. **Schéma reproductible** : la structure de la base doit être identique entre les environnements
   (dev local, CI, production) et recréable depuis zéro en une commande.
2. **Évolutivité** : le schéma va évoluer au fil des sprints. Chaque modification doit être
   versionnée, réversible et applicable sans intervention manuelle.
3. **Données de développement** : les développeurs ont besoin de données initiales cohérentes
   (utilisateurs de test, flux, pistes) pour travailler sans créer manuellement chaque entrée.

## Décision

### Schéma de données

Six tables ont été définies en respectant l'ordre des dépendances (clés étrangères) :

| Table | Dépendances | Rôle |
|---|---|---|
| `users` | — | Comptes utilisateurs, 4 rôles (anonymous, user, broadcaster, admin) |
| `streams` | `users` | Flux audio live créés par les broadcasters |
| `tracks` | `users` | Pistes audio uploadées |
| `playlists` | `users` | Collections personnelles de pistes |
| `playlist_tracks` | `playlists`, `tracks` | Table de jointure ordonnée playlist ↔ piste |
| `queue_items` | `users`, `tracks` | File d'attente de lecture par utilisateur |

**Choix techniques du schéma :**
- **UUID** partout (`gen_random_uuid()`) — pas de `serial`/`bigserial` pour éviter les collisions lors de futures migrations ou fusions de données
- **TIMESTAMPTZ** pour toutes les dates — stockage en UTC, conversion au niveau applicatif
- **CHECK constraints** sur les énumérations (`role`, `status`, `mime_type`) plutôt qu'un type `ENUM` PostgreSQL — plus simple à faire évoluer sans migration complexe
- **ON DELETE CASCADE** sur toutes les FK — la suppression d'un utilisateur nettoie automatiquement toutes ses données

**Index créés :**

| Index | Table | Colonnes | Justification |
|---|---|---|---|
| `idx_streams_user_id` | `streams` | `user_id` | Récupérer les flux d'un diffuseur |
| `idx_streams_status` | `streams` | `status` | Filtrer les flux live publics (homepage) |
| `idx_tracks_user_id` | `tracks` | `user_id` | Récupérer les pistes d'un utilisateur |
| `idx_playlists_user_id` | `playlists` | `user_id` | Récupérer les playlists d'un utilisateur |
| `idx_pt_playlist_pos` | `playlist_tracks` | `(playlist_id, position)` | Ordre des pistes dans une playlist |
| `idx_queue_user_pos` | `queue_items` | `(user_id, position)` | File d'attente ordonnée par utilisateur |

### Migrations versionnées avec golang-migrate

Adoption de **golang-migrate v4** avec le driver `pgx/v5` pour gérer les migrations SQL.

**Principe de fonctionnement :**
- Chaque migration = une paire de fichiers `NNNNNN_description.up.sql` / `NNNNNN_description.down.sql`
- golang-migrate maintient une table `schema_migrations` en base pour tracker les versions appliquées
- Au démarrage de l'API, `migrator.Run()` applique automatiquement les migrations en attente
- Idempotent : si toutes les migrations sont déjà appliquées, `ErrNoChange` est ignoré

**Intégration :** le `migrator` est appelé dans `cmd/api/main.go` avant le démarrage du serveur HTTP, garantissant que la base est toujours à jour avant de servir les requêtes.

### Seeder de données de développement

Un package `internal/infrastructure/seeder` insère des données de test cohérentes au démarrage
de l'API, **uniquement si `GO_ENV=development`**.

**Données insérées :**
- 4 utilisateurs : 1 admin, 1 broadcaster, 2 users (mot de passe `Password123!` hashé bcrypt coût 12)
- 3 streams : 1 live, 1 ended, 1 idle
- 5 tracks audio
- 1 playlist avec 3 tracks associées

**Idempotence :** chaque INSERT utilise `ON CONFLICT DO NOTHING` sur les contraintes UNIQUE,
garantissant que le seed peut tourner plusieurs fois sans créer de doublons.

## Alternatives considérées

### GORM AutoMigrate

- **Pourquoi rejeté** : `AutoMigrate` génère le schéma depuis les structs Go mais ne supporte pas
  les CHECK constraints, les index composites, ni les migrations `down`. En production, il peut
  altérer silencieusement des colonnes. Pas adapté pour un projet où le contrôle du SQL est requis.
  GORM reste utilisable pour les requêtes, mais pas pour la gestion du schéma.

### Atlas (ariga.io/atlas)

- **Pourquoi rejeté** : outil moderne et puissant (diff de schéma automatique) mais plus complexe
  à configurer. La courbe d'apprentissage n'est pas justifiée pour la taille du projet. golang-migrate
  est suffisant et plus répandu dans l'écosystème Go.

### Fichier SQL unique exécuté au démarrage

- **Pourquoi rejeté** : pas de versionnage, pas de rollback possible, pas de tracking des migrations
  appliquées. Fragile dès qu'on modifie le schéma — impossible de savoir quelle version est en base.

### Type ENUM PostgreSQL pour les rôles et statuts

- **Pourquoi rejeté** : les ENUM PostgreSQL nécessitent une migration `ALTER TYPE` pour ajouter
  une valeur, ce qui bloque les transactions. Les CHECK constraints sur TEXT sont plus simples
  à faire évoluer et suffisantes pour les cas d'usage de StreamPulse.

## Conséquences

### Avantages

- **Reproductibilité** : `docker compose down -v && docker compose up` recrée une base propre et seedée en une commande
- **Traçabilité** : chaque évolution du schéma est un fichier versionné dans git, reviewable en PR
- **Rollback possible** : chaque migration a son `.down.sql`, permettant de revenir en arrière
- **Onboarding rapide** : un nouveau développeur clone le repo et a une base fonctionnelle sans manipulation manuelle
- **Séparation des responsabilités** : `migrator`, `seeder` et `database` sont des packages indépendants dans `internal/infrastructure`

### Inconvénients

- **Verbosité** : un fichier par migration — le dossier `migrations/` grossit avec le temps
- **Connexion simple** : le seeder et le migrator utilisent `*pgx.Conn` (connexion simple). L'API devra passer à `*pgxpool.Pool` pour gérer la concurrence des requêtes simultanées
- **Seed non transactionnel** : si le seed échoue à mi-chemin, des données partielles peuvent être insérées. À améliorer avec une transaction globale en V2

## Structure des fichiers

```
backend/
├── migrations/
│   ├── 000001_create_users.{up,down}.sql
│   ├── 000002_create_streams.{up,down}.sql
│   ├── 000003_create_tracks.{up,down}.sql
│   ├── 000004_create_playlists.{up,down}.sql
│   ├── 000005_create_queue_items.{up,down}.sql
│   └── 000006_add_unique_constraints.{up,down}.sql
├── cmd/
│   ├── api/main.go                   ← orchestre migrator + seeder + serveur
│   └── seed/main.go                  ← lancement manuel du seed
└── internal/infrastructure/
    ├── database/database.go           ← Connect() via DATABASE_URL
    ├── migrator/migrator.go           ← Run() golang-migrate
    └── seeder/
        ├── seeder.go                  ← Run() orchestration
        ├── users.go
        ├── streams.go
        ├── tracks.go
        └── playlists.go
```

## Références

- [golang-migrate — GitHub](https://github.com/golang-migrate/migrate)
- [pgx v5 — GitHub](https://github.com/jackc/pgx)
- [PostgreSQL — UUID functions](https://www.postgresql.org/docs/current/functions-uuid.html)
- [PostgreSQL — CHECK constraints](https://www.postgresql.org/docs/current/ddl-constraints.html)
- ADR 002 : [Conteneurisation avec Docker Compose](002-choix-conteneurisation-docker.md)
