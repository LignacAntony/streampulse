# StreamPulse

> Plateforme StreamPulse — backend Go, application Flutter, déploiement conteneurisé.

> 🇬🇧 **English version: [README.en.md](README.en.md)** — see the
> [bilingual scope](docs/README.md#périmètre-bilingue).

[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://conventionalcommits.org)
[![Release](https://img.shields.io/github/v/release/LignacAntony/streampulse)](https://github.com/LignacAntony/streampulse/releases)
---

## Sommaire

- [Fonctionnalités](#fonctionnalités)
- [Stack technique](#stack-technique)
- [Structure du repository](#structure-du-repository)
- [Prérequis](#prérequis)
- [Installation \& lancement](#installation--lancement)
- [Architecture](#architecture)
- [Tests](#tests)
- [Déploiement](#déploiement)
- [Documentation API](#documentation-api)
- [Variables d'environnement](#variables-denvironnement)
- [Workflow Git](#workflow-git)
- [Conventions de commit](#conventions-de-commit)
- [Équipe et répartition des tâches](#équipe-et-répartition-des-tâches)
- [Contribuer](#contribuer)
- [Licence](#licence)

---

## Fonctionnalités

StreamPulse permet à un **diffuseur** de lancer un direct audio depuis son mobile et à des
**auditeurs** de l'écouter en temps réel, avec en complément une bibliothèque de pistes
personnelles et des playlists.

| Domaine | Fonctionnalités |
| --- | --- |
| **Comptes** | Inscription, connexion JWT (access + refresh avec rotation), réinitialisation de mot de passe par email, gestion du profil, suppression de compte (RGPD) |
| **Diffusion** | Création d'un flux, capture du micro et push AAC, segmentation HLS via ffmpeg, démarrage/arrêt du direct, rotation de la clé de diffusion, statistiques d'audience en temps réel |
| **Écoute** | Découverte des flux publics, lecteur HLS (play/pause/volume), lecture en arrière-plan avec contrôles système, gestion des interruptions (appel, casque débranché), favoris |
| **Bibliothèque** | Upload de pistes audio (MP3/AAC/OGG, quota par compte), playlists, réorganisation des pistes, file d'attente, modes aléatoire et répétition |
| **Administration** | Tableau de bord utilisateurs (activation/suppression), supervision et interruption des flux actifs, journal d'audit, validation des demandes de rôle diffuseur |
| **Observabilité** | Logs structurés JSON (Loki), métriques Prometheus, traces OpenTelemetry (Tempo), dashboards et alertes Grafana provisionnés |

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

## Architecture

Vue d'ensemble, schéma des composants, flux d'une requête et chaîne d'observabilité :
**[docs/architecture.md](./docs/architecture.md)** — *point de départ recommandé*.

| Couche | Principe |
| --- | --- |
| **Backend Go** | `net/http` + `http.ServeMux`, **sans framework**. Un package par domaine métier (`auth`, `streaming`, `playlist`, `track`, `admin`…), découpé en `handler` / `service` / `repository` ([ADR 008](./docs/adr/008-architecture-handler-service-repository.md)). Accès SQL typé généré par [sqlc](./docs/adr/007-sqlc-generation-code-sql.md). |
| **Mobile Flutter** | **Clean Architecture** (`domain` / `data` / `presentation`) + `provider` pour l'état ([ADR 005](./docs/adr/005-architecture-flutter-clean.md)). Le client HTTP est **généré** depuis la spec OpenAPI. |
| **Contrat HTTP** | La spec OpenAPI est la **source de vérité** ([ADR 012](./docs/adr/012-openapi-source-de-verite.md)) : le client Dart en est dérivé, jamais écrit à la main. |
| **Observabilité** | Stack LGTM — Loki (logs), Grafana (dashboards + alertes), Tempo (traces), Prometheus (métriques) ([ADR 001](./docs/adr/001-choix-stack-observabilite.md)). |

Toutes les décisions d'architecture significatives sont consignées sous forme d'**ADR**
(*Architecture Decision Records*) — 38 à ce jour, chacune reliée à son ticket Linear :

- **[Index complet de la documentation](./docs/README.md)** — ordre de lecture recommandé
- **[Index des ADR](./docs/adr/)** — une décision par fichier, numérotée

Le code applique les **principes SOLID** de bout en bout : interfaces étroites côté handler Go
(ISP), injection systématique des dépendances (DIP), entités du domaine sans dépendance infra.

## Tests

Le projet compte **40 fichiers de tests Go** et **36 fichiers de tests Flutter**. Les tests sont
**colocalisés avec le code** qu'ils couvrent (`*_test.go` à côté du package, `mobile/test/`
en miroir de `mobile/lib/`).

```bash
# Backend Go — tous les tests, avec détecteur de data race
cd backend && go test -race ./...
```

```bash
# Backend Go — couverture (même commande qu'en CI)
cd backend && go test -race -coverprofile=coverage.txt ./... && go tool cover -func=coverage.txt
```

```bash
# Backend Go — un seul package
cd backend && go test ./internal/streaming/...
```

```bash
# Mobile Flutter — tests unitaires et widgets
cd mobile && flutter test
```

```bash
# Test de charge HLS — 50 auditeurs simultanés (STR-90, requiert ffmpeg)
make loadtest
```

**Conventions** : tests Go en **stdlib uniquement** (pas de testify), stubs légers pour les
handlers et `fakeRepo` en mémoire pour les services ; côté Flutter, les abstractions du domaine
permettent de substituer des fakes (ex. `fake_audio_playback_service.dart`).

### Couverture actuelle (backend Go)

**48,8 %** des instructions sur l'ensemble du module — **54,4 %** en excluant les packages
`internal/*/db` générés par sqlc, qui ne sont pas censés être testés directement.

| Package | Couverture | | Package | Couverture |
| --- | --- | --- | --- | --- |
| `observability` | 94,1 % | | `streaming` | 65,6 % |
| `shared/httpmw` | 94,0 % | | `auth` | 62,7 % |
| `config` | 81,3 % | | `track` | 57,4 % |
| `shared/httpjson` | 75,8 % | | `profiles` | 54,0 % |
| `openapi` | 73,3 % | | `admin` | 52,4 % |
| | | | `broadcaster` | 44,8 % |
| | | | `shared/apperror` | 40,9 % |
| | | | `playlist` | 40,0 % |

> Chiffres obtenus avec `go test -coverprofile` sur le module complet. Les packages
> `infrastructure/*` (migrator, seeder, pool) et `cmd/api` sont à 0 % : ils sont couverts par
> les tests d'intégration sous build tag `integration`, exclus de `go test ./...`.

### Intégration continue

La **CI rejoue lint → tests → build à chaque PR** (et sur `develop` / `main`) et publie
`coverage.txt` en artefact téléchargeable depuis l'onglet *Actions*.

Le **test de charge ne tourne pas sur les PR** : le harnais vivant sous *build tag*, la CI
garantit seulement qu'il **compile** (`go vet -tags loadtest`). Son exécution réelle est un
workflow distinct ([`loadtest.yml`](./.github/workflows/loadtest.yml)), déclenché
**chaque lundi à 05h00 UTC** ou manuellement, qui publie son rapport en artefact.

## Déploiement

L'API est déployée en continu sur un **VPS Hetzner**, derrière **Caddy** (HTTPS automatique) :

| | |
| --- | --- |
| **API de production** | **<https://api.streampulse.win>** — [health](https://api.streampulse.win/health) |
| **Déclencheur** | **Fin de la CI sur `main`** (`workflow_run`), uniquement si elle est verte — un push ne déploie donc jamais des tests rouges. Aussi déclenchable à la main (`workflow_dispatch`) |
| **Pipeline** | Build de l'image Docker multi-stage → push sur **GHCR** → déploiement SSH sur le VPS |
| **Releases** | Automatiques via **release-please** : les Conventional Commits déterminent la version semver, le tag et le [CHANGELOG](./CHANGELOG.md) |

> `/metrics` et les endpoints Swagger ne sont **pas exposés en production** ; le port de l'API
> est bindé sur `127.0.0.1` et tout transite par Caddy.

**Procédures détaillées** — secrets GitHub à configurer, mise à jour manuelle du compose et des
configs d'infra, vérifications post-déploiement, troubleshooting :
**[docs/infrastructure.md](./docs/infrastructure.md)**.

Les **6 workflows** GitHub Actions du projet :

| Workflow | Fichier | Déclenchement | Rôle |
| --- | --- | --- | --- |
| **CI** | [`ci.yml`](./.github/workflows/ci.yml) | PR + push `develop`/`main` | Lint Go, tests + couverture, build, analyse Flutter |
| **CD** | [`cd.yml`](./.github/workflows/cd.yml) | Fin de CI verte sur `main` | Build & push GHCR, déploiement VPS, release-please |
| **Security** | [`security.yml`](./.github/workflows/security.yml) | Push `develop`/`main` + cron lundi | Scan Trivy (SARIF) + analyse statique gosec |
| **Check hardcoded** | [`check-hardcoded.yml`](./.github/workflows/check-hardcoded.yml) | PR + push `develop`/`main` | Bloque tout secret ou valeur codée en dur (gitleaks + grep) |
| **Lint PR title** | [`lint-pr-title.yml`](./.github/workflows/lint-pr-title.yml) | Ouverture/édition de PR | Valide le titre de PR contre les Conventional Commits |
| **Load Test** | [`loadtest.yml`](./.github/workflows/loadtest.yml) | Cron lundi 05h00 UTC + manuel | Test de charge HLS 50 auditeurs, rapport en artefact |

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
| `INGEST_RECONNECT_GRACE_SECONDS` | Délai sans audio avant l'arrêt automatique d'un live (doit dépasser 30 s, le backoff mobile max — refusé au démarrage sinon) | `45` | non | `45` |
| `INGEST_STOP_TIMEOUT_SECONDS` | Timeout d'une tentative d'arrêt automatique en base | `10` | non | `10` |
| `POSTGRES_USER` | Alias compose pour `DB_USER` (init du conteneur Postgres) | — | **oui (compose)** | `streampulse` |
| `POSTGRES_PASSWORD` | Alias compose pour `DB_PASSWORD` | — | **oui (compose)** | `<mot de passe fort>` |
| `POSTGRES_DB` | Alias compose pour `DB_NAME` | — | **oui (compose)** | `streampulse_db` |
| `DATABASE_URL` | DSN PostgreSQL complète. Utilisée par le **migrator** au démarrage, et en **fallback** du pool si les `DB_*` ne sont pas résolues | — | **oui (compose)** | `pgx5://user:pwd@postgres:5432/streampulse_db?sslmode=disable` |
| `GRAFANA_ADMIN_PASSWORD` | Mot de passe admin Grafana | — | **oui (compose)** | `<mot de passe fort>` |

**Email (réinitialisation de mot de passe, alertes)** — laisser `SMTP_HOST` vide affiche les
tokens dans les logs (mode dev) ; en local, `mailpit` sert de relay de test (UI sur
`http://localhost:8025`).

| Variable | Description | Défaut | Requis | Exemple |
| --- | --- | --- | --- | --- |
| `SMTP_HOST` | Serveur SMTP. **Vide = mode log stdout** (aucun email envoyé) | — | non | `mailpit` (dev) / `smtp-relay.brevo.com` |
| `SMTP_PORT` | Port SMTP (STARTTLS) | — (`587` dans `.env.example`) | non | `1025` (mailpit) / `587` |
| `SMTP_USERNAME` | Utilisateur du relay SMTP | — | non | `postmaster@streampulse.com` |
| `SMTP_PASSWORD` | Mot de passe du relay SMTP | — | non | `<mot de passe smtp>` |
| `SMTP_FROM` | Adresse expéditeur des emails | — (`noreply@streampulse.com` dans `.env.example`) | non | `noreply@streampulse.com` |
| `APP_BASE_URL` | Schéma d'URL des liens contenus dans les emails — **deep link** vers l'app Flutter | — (`streampulse://app` dans `.env.example`) | non | `streampulse://app` |

**Réseau, streaming et stockage**

| Variable | Description | Défaut | Requis | Exemple |
| --- | --- | --- | --- | --- |
| `CORS_ALLOWED_ORIGINS` | Origines CORS autorisées, séparées par des virgules. En dev, `localhost` / `127.0.0.1` sont autorisés d'office quel que soit le port | — | non | `https://app.streampulse.com` |
| `STREAM_INGEST_BASE_URL` | Préfixe de l'URL d'ingest renvoyée au diffuseur : `{base}/api/streams/ingest/{stream_key}` ([ADR 013](./docs/adr/013-domaine-streaming.md)) | `http://localhost:8080` | non | `https://api.streampulse.win` |
| `STORAGE_PATH` | Répertoire racine des fichiers audio uploadés, **hors répertoire servi** ([ADR 032](./docs/adr/032-domaine-track-upload-audio.md)) | `./data/tracks` | non | `/data/tracks` (volume Docker) |
| `HLS_MAX_CONCURRENT` | Nombre max de requêtes HLS servies simultanément aux auditeurs. `0` = illimité ([ADR 016](./docs/adr/016-scalabilite-test-de-charge-et-limiteur-hls.md)) | `256` | non | `256` |
| `TRUST_PROXY_HEADERS` | Lire `X-Forwarded-For` pour identifier les auditeurs (comptage d'audience). **`true` uniquement derrière un reverse proxy** — sinon l'en-tête est falsifiable, et sans proxy le compteur sature à 1 ([ADR 025](./docs/adr/025-statistiques-daudience-en-temps-reel.md)) | `false` | non | `true` (prod) |

**Observabilité**

| Variable | Description | Défaut | Requis | Exemple |
| --- | --- | --- | --- | --- |
| `LOG_LEVEL` | Niveau minimal des logs JSON : `trace`, `debug`, `info`, `warn`, `error` ([ADR 018](./docs/adr/018-logs-structures-zerolog-collecte-loki-alloy.md)) | `info` | non | `info` |
| `LOG_PRETTY` | Sortie console lisible — réservée au `go run` local. **Jamais en conteneur** : la collecte Loki attend du JSON | `false` | non | `true` (dev natif) |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Endpoint OTLP/HTTP de Tempo pour les traces. **Vide = tracing désactivé** ([ADR 020](./docs/adr/020-traces-opentelemetry-otlp-tempo.md)) | — | non | `http://tempo:4318` |

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

## Équipe et répartition des tâches

Projet réalisé par **3 développeurs**. Chacun a porté ses fonctionnalités de bout en bout —
backend, mobile, documentation et ADR — plutôt qu'une séparation stricte par couche technique.

| Contributeur | GitHub | Périmètre principal |
| --- | --- | --- |
| **Antony Lignac** | [@LignacAntony](https://github.com/LignacAntony) | Backend Go, infrastructure, observabilité, streaming, administration |
| **Thierry Maignan** | [@thierrymgn](https://github.com/thierrymgn) | Moteur HLS, lecteur audio mobile, authentification, CI/CD |
| **Baptiste Ballesteros** | [@Oceloott](https://github.com/Oceloott) | Bibliothèque, playlists, favoris, profil utilisateur |

### Détail par domaine

**Antony Lignac** — *fondations du projet et de l'infra*

- Initialisation du dépôt et configuration 12-Factor via Viper ([#88](https://github.com/LignacAntony/streampulse/pull/88), [#101](https://github.com/LignacAntony/streampulse/pull/101))
- Domaine **streaming** : création/configuration d'un flux, démarrage et arrêt du direct, rotation de la clé de diffusion, transcodage à la volée des formats d'ingest ([#128](https://github.com/LignacAntony/streampulse/pull/128), [#257](https://github.com/LignacAntony/streampulse/pull/257), [#279](https://github.com/LignacAntony/streampulse/pull/279), [#281](https://github.com/LignacAntony/streampulse/pull/281))
- **Observabilité complète** : logs structurés zerolog + Loki/Alloy, métriques Prometheus + node_exporter, traces OpenTelemetry vers Tempo, dashboards et alertes Grafana provisionnés ([#265](https://github.com/LignacAntony/streampulse/pull/265), [#268](https://github.com/LignacAntony/streampulse/pull/268), [#269](https://github.com/LignacAntony/streampulse/pull/269), [#271](https://github.com/LignacAntony/streampulse/pull/271), [#272](https://github.com/LignacAntony/streampulse/pull/272))
- **Administration** : tableau de bord utilisateurs, supervision et interruption des flux, journal d'audit ([#264](https://github.com/LignacAntony/streampulse/pull/264), [#267](https://github.com/LignacAntony/streampulse/pull/267))
- Scalabilité : test de charge 50 auditeurs et limiteur HLS ([#261](https://github.com/LignacAntony/streampulse/pull/261))
- Mobile : capture micro et push AAC, tableau de bord diffuseur, file d'attente de lecture, modes aléatoire/répétition, barre de progression ([#274](https://github.com/LignacAntony/streampulse/pull/274), [#278](https://github.com/LignacAntony/streampulse/pull/278), [#287](https://github.com/LignacAntony/streampulse/pull/287), [#289](https://github.com/LignacAntony/streampulse/pull/289), [#292](https://github.com/LignacAntony/streampulse/pull/292))
- OpenAPI comme source de vérité + client Dart généré ([#126](https://github.com/LignacAntony/streampulse/pull/126))

**Thierry Maignan** — *chaîne audio et pipeline*

- **Moteur HLS** : segmentation ffmpeg et génération du manifeste, lecture publique sans authentification ([#259](https://github.com/LignacAntony/streampulse/pull/259), [#263](https://github.com/LignacAntony/streampulse/pull/263))
- **Lecteur audio mobile** : play/pause/volume, lecture en arrière-plan avec contrôles système, gestion des interruptions (appel, casque débranché) ([#273](https://github.com/LignacAntony/streampulse/pull/273), [#282](https://github.com/LignacAntony/streampulse/pull/282), [#286](https://github.com/LignacAntony/streampulse/pull/286))
- **Infrastructure Docker** : stack LGTM et pipeline CI/CD GitHub Actions + GHCR ([#89](https://github.com/LignacAntony/streampulse/pull/89), [#90](https://github.com/LignacAntony/streampulse/pull/90))
- Réinitialisation de mot de passe, demande de rôle diffuseur, suppression de compte RGPD ([#120](https://github.com/LignacAntony/streampulse/pull/120), [#129](https://github.com/LignacAntony/streampulse/pull/129), [#130](https://github.com/LignacAntony/streampulse/pull/130))
- Durcissement sécurité : correction des alertes gosec, timeouts du serveur HTTP ([#93](https://github.com/LignacAntony/streampulse/pull/93), [#288](https://github.com/LignacAntony/streampulse/pull/288))

**Baptiste Ballesteros** — *bibliothèque et expérience utilisateur*

- **Authentification JWT** : access + refresh token avec rotation (backend et mobile) ([#119](https://github.com/LignacAntony/streampulse/pull/119), [#121](https://github.com/LignacAntony/streampulse/pull/121))
- **Playlists** : création et gestion ([#276](https://github.com/LignacAntony/streampulse/pull/276))
- **Upload de pistes** dans la bibliothèque, avec quota et validation MIME ([#284](https://github.com/LignacAntony/streampulse/pull/284))
- **Découverte des flux** en direct et **favoris** ([#256](https://github.com/LignacAntony/streampulse/pull/256), [#266](https://github.com/LignacAntony/streampulse/pull/266))
- Gestion du profil utilisateur ([#127](https://github.com/LignacAntony/streampulse/pull/127))
- Initialisation de la base PostgreSQL ([#95](https://github.com/LignacAntony/streampulse/pull/95))

### Statistiques de contribution

Un fichier [`.mailmap`](./.mailmap) fusionne les identités git multiples (chaque contributeur
ayant committé sous plusieurs emails), afin que les statistiques reflètent la réalité :

```bash
git shortlog -sne --all
```

Les [`CODEOWNERS`](./.github/CODEOWNERS) reprennent cette répartition : toute PR touchant un
périmètre y demande automatiquement la review de son responsable.

## Contribuer

Lire [CONTRIBUTING.md](./CONTRIBUTING.md) avant d'ouvrir une PR.

## Licence

Ce projet est distribué sous licence **MIT** — voir [LICENSE](./LICENSE).
