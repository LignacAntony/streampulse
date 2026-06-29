# ADR 007 — Accès base de données : sqlc (SQL → Go typé)

## Statut

Accepté — 2026-05-05

## Contexte

L'API accumule des requêtes SQL dans les fichiers `repository.go`. Jusqu'ici, chaque méthode contenait :

1. Une constante SQL en string littérale.
2. Un appel `pool.QueryRow(ctx, sql, args...)`.
3. Un `row.Scan(&field1, &field2, ...)` manuel.

Cette approche fonctionne mais présente des frictions :
- **Aucune vérification à la compilation** : une faute de frappe dans le SQL ou un `Scan` avec le mauvais nombre de colonnes n'est détecté qu'à l'exécution.
- **Boilerplate répétitif** : chaque query nécessite ~10 lignes identiques (const SQL + struct params + Scan).
- **Désynchronisation silencieuse** : si une colonne est ajoutée en migration, le `Scan` explose en prod sans alerte de build.

La question est : quel outil adopter pour réduire ce boilerplate tout en gardant le contrôle total du SQL ?

## Décision

Adopter **sqlc** (`github.com/sqlc-dev/sqlc`) comme générateur de code SQL → Go.

### Principe

Tu écris le SQL, sqlc génère le Go :

```sql
-- internal/auth/queries/auth.sql

-- name: GetUserByEmail :one
SELECT id::text, email, username, role, created_at, password_hash
FROM users
WHERE email = $1 AND is_active = true;
```

Génère automatiquement :

```go
// internal/auth/db/auth.sql.go — NE PAS ÉDITER

type GetUserByEmailRow struct {
    ID           string
    Email        string
    Username     string
    Role         string
    CreatedAt    time.Time
    PasswordHash string
}

func (q *Queries) GetUserByEmail(ctx context.Context, email string) (GetUserByEmailRow, error) { ... }
```

### Organisation des fichiers

```
internal/<feature>/
├── queries/        ← SQL annoté (seul fichier à éditer)
│   └── <feature>.sql
├── db/             ← Code généré (NE PAS ÉDITER)
│   ├── db.go
│   ├── models.go
│   └── <feature>.sql.go
└── repository.go   ← Utilise les fonctions générées
```

### Configuration (`backend/sqlc.yaml`)

```yaml
version: "2"
sql:
  - engine: "postgresql"
    queries: "internal/auth/queries/"
    schema: "migrations/"          # lit les *.up.sql existants
    gen:
      go:
        package: "authdb"
        out: "internal/auth/db"
        sql_package: "pgx/v5"     # compatible avec le pool pgx déjà en place
        overrides:
          - db_type: "timestamptz"
            go_type: "time.Time"
```

### Transactions avec `WithTx`

sqlc génère une méthode `WithTx(tx pgx.Tx) *Queries` qui permet d'utiliser les mêmes fonctions générées dans une transaction :

```go
tx, _ := r.pool.Begin(ctx)
defer tx.Rollback(ctx)
qtx := r.q.WithTx(tx)
qtx.DeleteRefreshToken(ctx, oldHash)
qtx.InsertRefreshToken(ctx, ...)
tx.Commit(ctx)
```

### Workflow

```bash
# Après toute modification dans internal/*/queries/*.sql :
cd backend && sqlc generate
```

## Alternatives considérées

### SQL brut dans repository.go (statu quo)

- **Avantage :** aucune dépendance outillage, full contrôle.
- **Rejet :** boilerplate croissant, désynchronisation schéma/code silencieuse. Acceptable pour 1-2 queries, pas pour un projet qui en aura des dizaines.

### GORM

- **Avantage :** zero SQL à écrire, migrations auto, associations.
- **Rejet :** génère du SQL imprévisible (N+1 fréquent), masque la complexité, incompatible avec SOLID (les struct models accumulent des tags et de la logique). Adapté au prototypage, pas à un projet qui tient à la lisibilité du SQL.

### `database/sql` + `sqlx`

- **Avantage :** plus léger que sqlc, pas de génération de code.
- **Rejet :** `Scan` toujours manuel, pas de vérification au build. sqlx améliore l'ergonomie mais n'apporte pas la sécurité des types que donne sqlc.

### Ent (ORM avec génération de schéma)

- **Avantage :** schéma défini en Go, génération complète.
- **Rejet :** inverse la logique (Go → SQL au lieu de SQL → Go), migrations moins prévisibles, courbe d'apprentissage élevée.

## Conséquences

### Avantages

- **Erreurs au build** : si le schéma change et qu'une query devient invalide, `sqlc generate` échoue avant que le code parte en prod.
- **Zéro boilerplate** : plus de `Scan` à la main, plus de structs params manuelles.
- **SQL lisible** : les queries sont dans des fichiers `.sql` dédiés — elles sont lues comme du SQL, pas comme des strings Go.
- **Compatible pgx/v5** : l'interface `DBTX` générée est satisfaite à la fois par `*pgxpool.Pool` et `pgx.Tx` → transactions transparentes.

### Inconvénients

- **Étape de génération** : tout changement SQL nécessite `sqlc generate` avant le build. À ajouter dans la CI et dans les hooks de dev.
- **Code généré à ne pas éditer** : les fichiers `internal/*/db/*.go` ne doivent jamais être modifiés manuellement — ils sont écrasés à la prochaine génération.
- **Types UUID** : les colonnes UUID PostgreSQL génèrent `pgtype.UUID` pour les paramètres d'entrée. Un helper `uuidParam(string) pgtype.UUID` dans `repository.go` fait la conversion.

### À faire lors de l'ajout d'une nouvelle feature

1. Créer `internal/<feature>/queries/<feature>.sql` avec les queries annotées.
2. Ajouter un bloc `sql` dans `sqlc.yaml` pointant vers ce nouveau dossier.
3. Lancer `sqlc generate`.
4. Implémenter `repository.go` en utilisant le package `db/` généré.

## Références

- ADR 005 : [Architecture handler / service / repository](005-architecture-handler-service-repository.md) — sqlc s'intègre dans la couche repository.
- `backend/sqlc.yaml` — configuration sqlc du projet.
- `internal/auth/queries/auth.sql` — exemple de queries annotées.
- Documentation officielle : https://docs.sqlc.dev
