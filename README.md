# StreamPulse

> Plateforme StreamPulse — backend Go, application Flutter, déploiement conteneurisé.

[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://conventionalcommits.org)
[![Release](https://img.shields.io/github/v/release/thierrymaignan/streampulse)](https://github.com/thierrymaignan/streampulse/releases)
---

## Sommaire

- [Stack technique](#stack-technique)
- [Structure du repository](#structure-du-repository)
- [Prérequis](#prérequis)
- [Installation & lancement](#installation--lancement)
- [Variables d'environnement](#variables-denvironnement)
- [Workflow Git](#workflow-git)
- [Conventions de commit](#conventions-de-commit)
- [Contribuer](#contribuer)

---

## Stack technique

| Couche | Technologie |
| --- | --- |
| Backend / API | **Go** |
| Application | **Flutter** (iOS, Android, Web) |
| Conteneurisation | **Docker** + Docker Compose |
| CI/CD | GitHub Actions |
| Gestion projet | Linear ([projet StreamPulse](https://linear.app/streampulse)) |

## Structure du repository

```
streampulse/
├── backend/         # API Go
├── app/             # Application Flutter
├── docker/          # Dockerfiles & compose
├── docs/            # Documentation technique
└── .github/         # Workflows CI/CD & templates
```

> Cette arborescence sera créée au fur et à mesure des prochaines tâches.

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

# 2. Copier le fichier d'environnement
cp .env.example .env  # à créer dès que des variables seront définies

# 3. Lancer la stack via Docker
docker compose up -d  # à venir

# 4. (Backend) Lancer l'API Go en local
cd backend && go run ./cmd/api  # à venir

# 5. (App) Lancer l'app Flutter
cd app && flutter run  # à venir
```

## Variables d'environnement

Toutes les variables sensibles sont définies dans un fichier `.env` à la racine. **Ne jamais committer** ce fichier — un `.env.example` documentera les variables attendues dès qu'elles seront définies.

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
fix(app): corriger le crash au lancement sur Android 14
docs(readme): documenter le workflow Git
```

Les **titres de PR** sont validés automatiquement via GitHub Actions. Voir [CONTRIBUTING.md](./CONTRIBUTING.md) pour le détail.

## Contribuer

Lire [CONTRIBUTING.md](./CONTRIBUTING.md) avant d'ouvrir une PR.
