# StreamPulse

> Plateforme StreamPulse — backend Go, application Flutter, déploiement conteneurisé.

[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://conventionalcommits.org)
[![Release](https://img.shields.io/github/v/release/LignacAntony/streampulse)](https://github.com/LignacAntony/streampulse/releases)
---

## Sommaire

- [StreamPulse](#streampulse)
  - [](#)
  - [Sommaire](#sommaire)
  - [Stack technique](#stack-technique)
  - [Structure du repository](#structure-du-repository)
  - [Prérequis](#prérequis)
  - [Installation \& lancement](#installation--lancement)
  - [Documentation API](#documentation-api)
  - [Variables d'environnement](#variables-denvironnement)
  - [Workflow Git](#workflow-git)
  - [Conventions de commit](#conventions-de-commit)
  - [Contribuer](#contribuer)

---

## Stack technique

| Couche | Technologie |
| --- | --- |
| Backend / API | **Go** |
| Application | **Flutter** (iOS, Android) |
| Conteneurisation | **Docker** + Docker Compose |
| CI/CD | GitHub Actions |
| Gestion projet | Linear ([projet StreamPulse](https://linear.app/streampulse)) |

## Structure du repository

```
streampulse/
├── backend/         # API Go
├── mobile/          # Application Flutter (iOS + Android)
├── docker/          # Configs Docker (prometheus, grafana, loki, tempo)
├── docs/            # Documentation technique
└── .github/         # Workflows CI/CD & templates
```

## Prérequis

- [Go](https://go.dev/dl/) ≥ 1.22
- [Flutter](https://docs.flutter.dev/get-started/install) ≥ 3.22
- [Docker](https://docs.docker.com/get-docker/) + Docker Compose
- [Git](https://git-scm.com/) avec signature SSH/GPG configurée (les commits sur `main` doivent être signés)

## Installation & lancement

```bash
# 1. Cloner le repo
git clone git@github.com:LignacAntony/streampulse.git
cd streampulse

# 2. Copier le fichier d'environnement et renseigner les valeurs
cp .env.example .env
$EDITOR .env  # remplacer JWT_SECRET et les mots de passe

# 3. Lancer la stack via Docker
docker compose up -d

# 4. (Backend) Lancer l'API Go en local (hors Docker)
cd backend && go run ./cmd/api

# 5. (App) Lancer l'app Flutter
cd mobile && flutter run
```

## Documentation API

L'API expose sa documentation OpenAPI via Swagger UI :

- Interface interactive : `http://localhost:8080/swagger/`
- Spécification YAML brute : `http://localhost:8080/swagger/openapi.yaml`

> ⚠️ Ces endpoints ne sont **pas exposés en production** (`GO_ENV=production`) afin
> de ne pas publier la surface de l'API ; ils restent disponibles en dev et en test.

Le client Dart/Dio utilisé par l'application Flutter est généré depuis cette
spécification :

```bash
make generate-openapi-client
```

La commande utilise l'image Docker `openapitools/openapi-generator-cli:v7.23.0`,
écrase `mobile/packages/streampulse_api`, puis régénère les serializers Dart.

## Variables d'environnement

Le projet suit la méthodologie [**12-Factor App**](https://12factor.net/fr/config) : toute la configuration est externalisée via variables d'environnement, **aucune valeur n'est codée en dur** dans le code source.

### Setup

1. Copier le template : `cp .env.example .env`
2. Renseigner les valeurs sensibles (`JWT_SECRET`, mots de passe…)
3. **Ne jamais committer** `.env` — il est dans `.gitignore` et un check CI (gitleaks + grep) bloque tout secret hardcodé

### Variables disponibles

| Variable | Description | Défaut | Requis | Exemple |
| --- | --- | --- | --- | --- |
| `GO_ENV` | Environnement d'exécution (`development`, `production`, `test`) | `development` | non | `production` |
| `API_PORT` | Port d'écoute HTTP de l'API Go | `8080` | non | `8080` |
| `JWT_SECRET` | Clé de signature des JWT — **min. 32 caractères** | — | **oui** | `<chaîne aléatoire ≥ 32 chars>` |
| `DB_HOST` | Hôte PostgreSQL | `localhost` | non | `postgres` (en compose) |
| `DB_PORT` | Port PostgreSQL | `5432` | non | `5432` |
| `DB_USER` | Utilisateur PostgreSQL | — | **oui** | `streampulse` |
| `DB_PASSWORD` | Mot de passe PostgreSQL | — | **oui** | `<mot de passe fort>` |
| `DB_NAME` | Nom de la base PostgreSQL | — | **oui** | `streampulse_db` |
| `INGEST_RECONNECT_GRACE_SECONDS` | Délai sans audio avant l'arrêt automatique d'un live | `45` | non | `45` |
| `INGEST_STOP_TIMEOUT_SECONDS` | Timeout d'une tentative d'arrêt automatique en base | `10` | non | `10` |
| `POSTGRES_USER` | Alias compose pour `DB_USER` (init du conteneur Postgres) | — | **oui (compose)** | `streampulse` |
| `POSTGRES_PASSWORD` | Alias compose pour `DB_PASSWORD` | — | **oui (compose)** | `<mot de passe fort>` |
| `POSTGRES_DB` | Alias compose pour `DB_NAME` | — | **oui (compose)** | `streampulse_db` |
| `GRAFANA_ADMIN_PASSWORD` | Mot de passe admin Grafana | — | **oui (compose)** | `<mot de passe fort>` |

### Implémentation

Le chargement est centralisé dans le package [`backend/internal/config`](./backend/internal/config). Il utilise [Viper](https://github.com/spf13/viper) pour :

- Charger un fichier `.env` à la racine du repo si présent (dev local)
- Lire les variables d'environnement (priorité maximale en prod)
- Appliquer les valeurs par défaut documentées ci-dessus
- **Valider en fail-fast** au démarrage : variables requises manquantes ou `JWT_SECRET` trop court → l'API refuse de démarrer

```go
cfg, err := config.Load()
if err != nil {
    log.Fatalf("config: %v", err)
}
```

## Workflow Git

Le repository suit un modèle **Git Flow simplifié** :

| Branche | Rôle |
| --- | --- |
| `main` | Code de production. Protégée — merge uniquement via PR approuvée. |
| `develop` | Branche d'intégration. Toutes les features y sont mergées. |
| `feature/<ticket>-<slug>` | Branches de feature, partent de `develop`. |
| `fix/<ticket>-<slug>` | Branches de correctifs. |
| `hotfix/<ticket>-<slug>` | Correctifs urgents partant de `main`. |

**Règles** :

- Aucun push direct sur `main` ni `develop`
- Toute PR nécessite **au moins 1 review approuvée**
- Pas de force-push (non-fast-forward bloqué)
- Les commits sur `main` doivent être **signés**

## Conventions de commit

Le projet utilise [**Conventional Commits**](https://www.conventionalcommits.org/fr/v1.0.0/). Format :

```
<type>(<scope>): <description>

[corps optionnel]

[footer optionnel]
```

**Types** : `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.

Exemples :

```
feat(api): ajouter l'endpoint /streams
fix(mobile): corriger le crash au lancement sur Android 14
docs(readme): documenter le workflow Git
```

Les **titres de PR** sont validés automatiquement via GitHub Actions. Voir [CONTRIBUTING.md](./CONTRIBUTING.md) pour le détail.

## Contribuer

Lire [CONTRIBUTING.md](./CONTRIBUTING.md) avant d'ouvrir une PR.
