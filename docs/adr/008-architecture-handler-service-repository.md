# ADR 008 — Architecture en couches : handler / service / repository

## Statut

Accepté — 2026-05-05

## Contexte

STR-33 introduit le premier endpoint HTTP métier de l'API StreamPulse : `POST /api/auth/register`. Jusqu'ici, `cmd/api/main.go` ne servait que `/health` et `/metrics` — aucune logique métier, aucune persistence côté requête. À partir de ce ticket, l'API va accumuler des endpoints (login, profil, streams, playlists) qui partagent tous trois préoccupations distinctes :

1. **Décodage HTTP** : parser un body JSON, valider le `Content-Type`, mapper des codes statut.
2. **Logique métier** : valider les entrées au sens domaine, hacher des secrets, orchestrer plusieurs écritures.
3. **Persistence** : exécuter des requêtes SQL contre PostgreSQL via le pool `pgx`.

Mélanger ces préoccupations dans un même fichier rend la base de code rapidement illisible et impossible à tester sans base de données.

## Décision

Adopter le pattern **handler / service / repository** comme structure par défaut pour chaque package fonctionnel placé dans `backend/internal/<feature>/`. Concrètement, chaque feature suit le même squelette :

```
internal/<feature>/
├── handler.go        ← couche HTTP : décodage, validation surface, codes statut
├── service.go        ← couche métier : règles, validation domaine, orchestration
├── repository.go     ← couche persistence : SQL + mapping pgx
├── errors.go         ← erreurs de domaine partagées entre couches
└── *_test.go         ← tests unitaires par couche
```

**Règles d'inversion de dépendance :**

- Le service dépend d'une **interface** `Repository`, pas d'une struct concrète. Permet de mocker le stockage en test sans Docker.
- Le handler dépend d'une **interface** `Registrar` (sous-ensemble du service utile au handler). Permet de tester les codes HTTP avec un stub.
- Le câblage concret est fait dans `cmd/api/main.go` : `NewRepository(pool) → NewService(repo) → NewHandler(svc)`.

**Mapping des erreurs :**

- Les erreurs de domaine (`ErrInvalidEmail`, `ErrDuplicate`, …) sont définies dans `errors.go` du package feature.
- Le handler les mappe vers des codes HTTP via `errors.Is`. Toute erreur non reconnue → `500` + log.
- Le repository convertit les erreurs basses (ex : `pgerrcode.UniqueViolation`) en erreurs de domaine avant de les remonter.

## Alternatives considérées

### Tout mettre dans le handler

- **Avantage :** un seul fichier, démarrage rapide.
- **Rejet :** chaque endpoint ré-implémente la validation, le hachage, l'accès DB. Duplication garantie au deuxième endpoint. Tests unitaires impossibles sans tourner Postgres.

### Hexagonal / Ports & Adapters strict

- **Avantage :** découplage maximal, support multi-base théorique.
- **Rejet :** verbosité disproportionnée pour un projet de cette taille. La règle « interface dans le package métier, implémentation à côté » suffit.

### Service unique global

- **Avantage :** un seul singleton à câbler dans `main.go`.
- **Rejet :** explose en god-object dès qu'on dépasse 3 features. Préférer un package par domaine fonctionnel.

## Conséquences

### Avantages

- **Testabilité** : `service_test.go` tourne sans DB grâce à un fake repo en mémoire ; `handler_test.go` tourne sans service grâce à un stub. Les tests unitaires sont rapides (< 1s) et déterministes.
- **Lisibilité** : un développeur qui ouvre `internal/auth/` voit immédiatement où est la validation HTTP, où est la règle métier, où est le SQL.
- **Évolutivité** : ajouter un endpoint `POST /api/auth/login` revient à compléter les trois fichiers existants — pas de nouvelle architecture à inventer.
- **Réutilisation** : la même interface `Repository` peut être implémentée par un repo en mémoire (tests intégration légers) ou un repo SQLite (CI sans Postgres) si besoin futur.

### Inconvénients

- **Boilerplate** : ~3 fichiers et 2 interfaces par feature, même pour un endpoint trivial. Acceptable au vu du gain en testabilité.
- **Rigidité initiale** : le pattern impose une discipline ; un développeur tenté de raccourcir doit résister. Garde-fou : revues de PR.

### Suivi

- À chaque nouvelle feature backend, créer le triplet `handler/service/repository` dans un nouveau package `internal/<feature>/`.
- Si une feature partage une dépendance avec une autre (ex : `auth` consomme `users`), la feature consommée expose un service public ; la feature consommatrice l'injecte via interface.

## Références

- ADR 037 : [Initialisation de la base de données](037-initialisation-base-de-donnees.md) — pose le pool `pgxpool` réutilisé ici.
- ADR 004 : [Configuration 12-Factor](004-config-12-factor-viper.md) — le câblage dans `main.go` lit la config via `config.Load()`.
- Linear : [STR-33](https://linear.app/streampulse/issue/STR-33) — premier ticket à appliquer ce pattern.
