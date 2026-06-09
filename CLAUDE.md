# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**StreamPulse** is a multi-platform audio streaming application.

- **Backend**: Go ≥ 1.22 — `backend/`
- **Mobile**: Flutter ≥ 3.22 — `mobile/` (iOS + Android)
- **Infra**: Docker + Docker Compose — `docker/`

## Commands

```bash
# Backend (Go) — dans backend/
go run ./cmd/api          # Run dev server
go test ./...             # Run all tests
go test ./path/to/pkg/... # Run a single package's tests
go build -o bin/api ./cmd/api
sqlc generate              # Regénérer le code SQL → Go après modif d'une query

# Mobile (Flutter) — dans mobile/
flutter pub get           # Installer les dépendances
flutter pub run build_runner build --delete-conflicting-outputs  # Générer le code
flutter run               # Lancer sur device/émulateur connecté
flutter test              # Run all tests
flutter test test/path/to_test.dart  # Run a single test file
flutter analyze           # Lint

# Docker
docker compose up -d
docker compose down
docker compose logs -f
```

## Git Workflow

### Branch naming
```
<type>/<linear-ticket>-<slug>
# e.g. feature/str-12-auth-google, fix/str-30-crash-android
```
Types: `feature`, `fix`, `hotfix`, `chore`, `docs`

### Commit messages (Conventional Commits, enforced on PR titles)
```
<type>(<scope>): <description en français>
```
Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`  
Scopes: `api`, `mobile`, `auth`, `db`, `infra`, `docker`, `ci`, `docs`, `deps`

All descriptions must be in **French**.

### Protected branches
- `main` and `develop` require PR + 1 approval
- Commits on `main` must be **signed** (SSH or GPG)
- Merge strategy: **squash & merge**

### Commit signing setup (required for `main`)
```bash
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
```
Add the public key to GitHub under **Settings → SSH and GPG keys → Signing Key**.

## CI

`.github/workflows/lint-pr-title.yml` — validates every PR title against Conventional Commits using `amannn/action-semantic-pull-request@v5`. Invalid titles block the merge.

## CI/CD

Trois workflows GitHub Actions sont définis dans `.github/workflows/` :

| Workflow | Fichier | Déclenchement | Rôle |
|---|---|---|---|
| **CI** | `ci.yml` | `push` / `pull_request` sur `develop` et `main` | Lint Go (golangci-lint) → tests avec couverture → build |
| **CD** | `cd.yml` | `push` sur `main` + `workflow_dispatch` | Build image Docker → push GHCR → déploiement SSH VPS |
| **Security** | `security.yml` | `push` sur `develop` et `main` + cron lundi 06h00 UTC | Scan Trivy (SARIF) + analyse statique gosec |

### Secrets GitHub à configurer

Dans **Settings → Secrets and variables → Actions** du dépôt :

| Secret | Description |
|---|---|
| `VPS_HOST` | IP publique du serveur Hetzner |
| `VPS_USER` | Utilisateur SSH de déploiement (`deploy`) |
| `VPS_SSH_KEY` | Contenu de la clé privée SSH (`~/.ssh/id_ed25519`) |
| `VPS_PORT` | Port SSH du serveur (`22`) |
| `VPS_GHCR_USER` | Username GitHub pour l'authentification GHCR côté VPS |
| `GHCR_TOKEN` | Personal Access Token GitHub avec scope `read:packages` |

### Tester le build Docker localement avant de push

```bash
docker build -t streampulse-api ./backend
```

### Déclencher un redéploiement manuel

GitHub → onglet **Actions** → workflow **"CD"** → bouton **"Run workflow"** → branche `main` → **"Run workflow"**.

### Releases

Le projet utilise **release-please** (`googleapis/release-please-action@v4`) pour les releases automatiques.

**Fonctionnement :** après chaque merge sur `main` et déploiement réussi, release-please analyse
les Conventional Commits et ouvre/met à jour une PR `chore: release vX.Y.Z`. Merger cette PR
crée le tag Git et la GitHub Release.

**Versioning semver :**
- `fix:` → patch | `feat:` → minor (patch avant v1.0.0) | `feat!:` / `BREAKING CHANGE` → major

**Règles importantes :**
- Ne **jamais** éditer `CHANGELOG.md` manuellement — il est géré par release-please
- Ne **jamais** supprimer `release-please-config.json` ni `.release-please-manifest.json`
- Pour forcer une version : modifier `.release-please-manifest.json` → `{ ".": "X.Y.Z" }`

## Architecture

- `backend/` — Go REST API
- `mobile/` — Flutter client (iOS, Android) — Clean Architecture + Riverpod
- `docker/` — Compose files and container configuration
- `docs/` — Project documentation

Linear project tracks all tickets: https://linear.app/streampulse  
Branch names (`str-XX`) automatically link to Linear issues.

## Backend Go — Architecture

Stdlib `net/http` + `http.ServeMux`. Pas de framework. Composition manuelle dans `cmd/api/main.go`.

### Structure d'un domaine

```
internal/<domaine>/
├── handler.go      # HTTP handlers + interfaces ISP (Registrar, Authenticator, …)
├── service.go      # Logique métier, types domaine (User, TokenPair, …), interface Repository
├── repository.go   # Accès PostgreSQL via pgx/v5, SQL brut
└── *_test.go       # Tests stdlib uniquement (pas de testify)
```

### Workflow sqlc (queries SQL → Go typé)

```
internal/<domaine>/queries/  ← tu écris le SQL ici (annotations sqlc)
      ↓  sqlc generate
internal/<domaine>/db/       ← NE PAS ÉDITER — code généré automatiquement
      ↑
repository.go l'utilise
```

Commande à relancer après chaque modification d'une query :
```bash
cd backend && sqlc generate
```

Config : `backend/sqlc.yaml` — schéma lu depuis `migrations/*.up.sql`.

**Ne jamais éditer `internal/*/db/*.go`** — ils sont écrasés à chaque `sqlc generate`.

### Patterns à respecter

- **ISP** : le handler déclare des interfaces étroites (`Registrar`, `Authenticator`, `TokenRefresher`) — chacune couvre exactement ce dont le handler a besoin. `*Service` les satisfait toutes.
- **Injection** : `NewService(repo, jwtSecret)` → `NewHandler(svc, svc, svc)` dans `main.go`.
- **Erreurs** : `apperror.Unauthorized(msg)` / `apperror.InvalidArgument(msg)` / … → `httpjson.WriteError` mappe automatiquement vers le bon status HTTP.
- **Tests** : stubs légers (`stubRegistrar`, `stubAuthenticator`) pour les handler tests ; `fakeRepo` en mémoire pour les service tests.

### Routes auth existantes

| Méthode | Route | Handler | Auth requise |
|---|---|---|---|
| POST | `/api/auth/register` | `Handler.Register` | Non |
| POST | `/api/auth/login` | `Handler.Login` | Non |
| POST | `/api/auth/refresh` | `Handler.Refresh` | Non |
| POST | `/api/auth/logout` | `Handler.Logout` | Oui (JWT) |
| POST | `/api/auth/forgot-password` | `Handler.ForgotPassword` | Non |
| POST | `/api/auth/reset-password` | `Handler.ResetPassword` | Non |

### Protéger une route avec JWT

```go
// Dans cmd/api/main.go, après avoir créé authHandler :
mux.Handle("/api/ma-route", auth.RequireAuth(cfg.JWTSecret, monHandler))

// Avec restriction de rôle (admin > broadcaster > user > anonymous) :
mux.Handle("/api/admin", auth.RequireAuth(cfg.JWTSecret,
    auth.RequireRole("admin", monHandler)))

// Récupérer l'identité dans un handler :
userID, _ := auth.UserIDFromContext(r.Context())
role,   _ := auth.RoleFromContext(r.Context())
```

### JWT

- **Access token** : HS256, exp. 15 min, claims `sub` (userID) + `role`.
- **Refresh token** : aléatoire 32 octets, stocké haché (SHA-256) dans `refresh_tokens`. Rotation à chaque utilisation.
- Secret : `JWT_SECRET` (env, min 32 chars).

## Application Mobile Flutter

**Dossier** : `mobile/`

### Commandes du quotidien

```bash
cd mobile
flutter pub get                                                      # Installer les dépendances
flutter pub run build_runner build --delete-conflicting-outputs      # Générer *.g.dart et *.freezed.dart
flutter run                                                          # Lancer sur device/émulateur connecté
flutter analyze                                                      # Lint
flutter test                                                         # Tests unitaires et widgets
```

### Ajouter une nouvelle feature

Créer l'arborescence suivante dans `mobile/lib/features/<nom>/` :

```
<nom>/
├── data/
│   └── repositories/      # Implémente l'interface domain
├── domain/
│   ├── entities/          # Entités pures (pas de dépendances Flutter/infra)
│   ├── repositories/      # Interface abstraite (Principe D)
│   └── usecases/          # Logique métier isolée
└── presentation/
    ├── screens/           # Widgets Flutter
    └── providers/         # ChangeNotifier controllers (package `provider`)
```

### Adresse API en développement

- **Défaut** (`core/constants/api_constants.dart`) : `http://localhost:8080` — couvre **simulateur iOS** et **device Android physique via `adb reverse`**.
- **Device Android physique (USB)** : `adb reverse tcp:8080 tcp:8080` mappe `localhost:8080` du device vers le Mac, puis `flutter run` (le défaut `localhost` suffit). ⚠️ `adb reverse` est éphémère : à refaire après débranchement / reboot du device.
- **Émulateur Android** : `10.0.2.2` pointe vers `localhost` de l'hôte → surcharger avec `--dart-define=API_BASE_URL=http://10.0.2.2:8080`.
- **IP LAN (sans câble)** : `--dart-define=API_BASE_URL=http://192.168.x.x:8080` (IP locale du Mac, `ipconfig getifaddr en0`). Nécessite même Wi-Fi + bind Docker sur `0.0.0.0` + firewall macOS ouvert sur 8080.
- Configurable via `--dart-define=API_BASE_URL=http://...` ou variable d'environnement

### Authentification (mobile)

Voir [ADR 009](docs/adr/009-authentification-flutter.md) pour les décisions détaillées.

**Stockage** : `SecureStorage` (`core/storage/secure_storage.dart`) wrappe `flutter_secure_storage`
avec `EncryptedSharedPreferences` (Android) / Keychain (iOS). 5 méthodes uniquement :
`saveAccessToken`, `saveRefreshToken`, `getAccessToken`, `getRefreshToken`, `clearTokens`.

**Transport** : `DioClient` (`core/network/dio_client.dart`) injecte automatiquement le `Bearer`
sur chaque requête et intercepte les `401` :

- Refresh **sérialisé** via `Completer<bool>` (un seul refresh en vol pour N requêtes 401 parallèles).
- `_refreshDio` séparé sans intercepteur → pas de récursion.
- Anti-boucle : `req.path` parmi `/api/auth/{login,register,refresh,logout}` → pas de refresh ;
  `req.extra['_retried']` empêche de rejouer deux fois.
- Échec du refresh → `clearTokens()` + propagation de l'erreur (le router renvoie vers `/login`).

**Logout** : `AuthRepository.logout()` appelle `POST /api/auth/logout` en best-effort
(`try/catch` silencieux), puis purge **toujours** `SecureStorage`. Le `home_screen` complète
avec `ref.invalidate(loginControllerProvider / registerControllerProvider)` pour libérer les
`AsyncValue` retenus en mémoire.

**Erreurs 401** : message UI **hard-codé** (`'Email ou mot de passe incorrect'`) — ne jamais
relayer le `serverMessage` pour éviter une fuite d'info technique. Les 400/409/5xx peuvent en
revanche utiliser `serverMessage` (codes business contrôlés).

**UI auth** : un seul `AuthScreen` avec onglets en place (`AnimatedSwitcher` entre `LoginView`
et `RegisterView`, pas de changement de route). `LoginScreen` et `RegisterScreen` sont des
wrappers minces vers `AuthScreen(initialTab: ...)`.

**Toasts** : `toastification` via les helpers `showAuthSuccessToast / ErrorToast / InfoToast`
(`presentation/widgets/auth_toasts.dart`). `ToastificationWrapper` est posé dans `app.dart`.

## Architecture Docker

Réseau interne : `streampulse-net` (bridge Docker). Tous les services y sont connectés.

| Service | Image | Rôle | Port interne | Port hôte |
|---|---|---|---|---|
| `postgres` | `postgres:16-alpine` | Base de données | 5432 | — |
| `api` | build local Go 1.22 | API REST | 8080 | 8080 |
| `mailpit` | `axllent/mailpit:latest` | Email de test (dev) | 1025 (SMTP), 8025 (UI) | 1025, 8025 |
| `prometheus` | `prom/prometheus:latest` | Métriques | 9090 | 9090 |
| `loki` | `grafana/loki:latest` | Logs | 3100 | — |
| `tempo` | `grafana/tempo:latest` | Traces (OTLP) | 3200, 4317, 4318 | — |
| `grafana` | `grafana/grafana:latest` | Visualisation | 3000 | 3000 |

**Volumes nommés :** `postgres_data`, `grafana_data`

**Configs des services** (bind-mounts read-only) :
- `docker/prometheus/prometheus.yml` → `/etc/prometheus/prometheus.yml`
- `docker/grafana/provisioning/` → `/etc/grafana/provisioning/`
- `docker/loki/loki-config.yml` → `/etc/loki/local-config.yaml`
- `docker/tempo/tempo-config.yml` → `/etc/tempo/tempo-config.yaml`

```bash
# Commandes essentielles
docker compose up -d                    # Démarrer tous les services
docker compose down                     # Arrêter (volumes conservés)
docker compose down -v                  # Arrêter + supprimer les volumes
docker compose logs -f [service]        # Logs en temps réel
docker compose ps                       # État et santé des services
docker compose build api && docker compose up -d api  # Rebuild l'API

# Ajouter un nouveau service : l'ajouter dans docker-compose.yml
# sous la clé `services:`, le connecter au réseau `streampulse-net`,
# ajouter un healthcheck, puis relancer `docker compose up -d`
```

## Variables d'environnement

Copier `.env.example` en `.env` avant le premier lancement. Ne jamais committer `.env`.

| Variable | Description | Exemple |
|---|---|---|
| `POSTGRES_USER` | Utilisateur PostgreSQL | `streampulse` |
| `POSTGRES_PASSWORD` | Mot de passe PostgreSQL | `mot-de-passe-fort` |
| `POSTGRES_DB` | Nom de la base de données | `streampulse_db` |
| `GRAFANA_ADMIN_PASSWORD` | Mot de passe admin Grafana | `mot-de-passe-fort` |
| `API_PORT` | Port exposé de l'API sur l'hôte | `8080` |
| `GO_ENV` | Environnement Go | `development` |
| `JWT_SECRET` | Clé de signature JWT (min. 32 chars) | `chaine-aleatoire-longue` |
| `SMTP_HOST` | Serveur SMTP (vide = mode log dev) | `smtp.mailgun.org` |
| `SMTP_PORT` | Port SMTP STARTTLS | `587` |
| `SMTP_USERNAME` | Utilisateur SMTP | `postmaster@streampulse.com` |
| `SMTP_PASSWORD` | Mot de passe SMTP | `mot-de-passe-smtp` |
| `SMTP_FROM` | Adresse expéditeur | `noreply@streampulse.com` |
| `APP_BASE_URL` | Schéma URL pour les liens d'email (deep link mobile) | `streampulse://app` |

## Santé des services

```bash
docker compose ps   # Voir l'état de tous les services
```

| Service | URL de healthcheck | Attendu |
|---|---|---|
| API | http://localhost:8080/health | 200 OK |
| Prometheus | http://localhost:9090/-/healthy | 200 OK |
| Grafana | http://localhost:3000/api/health | 200 OK |
| Mailpit | http://localhost:8025 | 200 OK |
| Loki | interne : `localhost:3100/ready` | — |
| Tempo | interne : `localhost:3200/ready` | — |

**URLs d'accès local :**
- Grafana : http://localhost:3000 (admin / `$GRAFANA_ADMIN_PASSWORD`)
- Prometheus : http://localhost:9090
- API : http://localhost:8080
- Mailpit (webmail de test) : http://localhost:8025

**Workflow complet de réinitialisation de mot de passe (dev) :**
```bash
# 1. Lancer la stack
docker compose up -d

# 2. Dans l'app Flutter (émulateur Android ou simulateur iOS)
#    Login screen → "Mot de passe oublié ?" → saisir user1@streampulse.dev → Envoyer

# 3. Ouvrir Mailpit → copier le token depuis le lien de l'email
open http://localhost:8025

# 4a. Déclencher le deep link depuis le terminal (Android)
adb shell am start -a android.intent.action.VIEW \
  -d "streampulse://app/reset-password?token=<TOKEN>"

# 4b. Simulateur iOS
xcrun simctl openurl booted \
  "streampulse://app/reset-password?token=<TOKEN>"

# 5. Saisir le nouveau mot de passe dans l'app → Réinitialiser
# 6. Se connecter avec le nouveau mot de passe → ✓
```
> `APP_BASE_URL=streampulse://app` — le lien email ouvre directement l'app Flutter via deep link.  
> En production, remplacer `SMTP_HOST=mailpit` par le relay réel et renseigner `SMTP_USERNAME` / `SMTP_PASSWORD`.

## Documentation

| Fichier | Contenu |
|---|---|
| `docs/README.md` | Index de toute la documentation, ordre de lecture recommandé |
| `docs/architecture.md` | Schéma ASCII, composants, flux requête et observabilité, choix techniques |
| `docs/infrastructure.md` | Services Docker, variables d'env, procédures, troubleshooting |
| `docs/adr/001-choix-stack-observabilite.md` | Décision : stack LGTM vs ELK, Datadog, New Relic |
| `docs/adr/002-choix-conteneurisation-docker.md` | Décision : Docker Compose vs Podman, Nix, K8s local |
| `docs/adr/003-choix-cicd-github-actions.md` | Décision : GitHub Actions + GHCR vs GitLab CI, Jenkins, CircleCI |
| `docs/adr/006-authentification-jwt.md` | Décision : JWT HS256 + rotation refresh côté backend |
| `docs/adr/009-authentification-flutter.md` | Décision : stockage sécurisé, refresh auto, logout best-effort côté Flutter |

**Règle :** toute nouvelle décision d'architecture significative → nouvel ADR dans `docs/adr/`
avec le numéro suivant (prochain : `010-...`). Référencer le ticket Linear correspondant.

## Principes SOLID

Ces principes s'appliquent à **tout le code du projet** (Go et Flutter).

| Principe | Règle | Exemple concret |
|---|---|---|
| **S** — Single Responsibility | Une classe/fichier = une seule raison de changer | `SecureStorage` gère uniquement les tokens ; `DioClient` gère uniquement le transport HTTP |
| **O** — Open/Closed | Extensible par héritage/composition, fermé à la modification | Ajouter une `Failure` = créer une sous-classe, pas modifier `Failure` |
| **L** — Liskov Substitution | Tout sous-type respecte le contrat du type parent | `ServerFailure` peut remplacer `Failure` partout sans changer le comportement attendu |
| **I** — Interface Segregation | Interfaces minimales — ne pas exposer de méthodes inutilisées | `AuthRepository` expose uniquement les méthodes nécessaires à cette feature |
| **D** — Dependency Inversion | Dépendre des abstractions, injecter les concrets | `DioClient` reçoit `SecureStorage` via constructeur, ne l'instancie pas |

**En pratique :**
- Les entités dans `domain/entities/` ne doivent jamais importer de code infra (Dio, SQLite, Flutter)
- Les interfaces dans `domain/repositories/` définissent les contrats ; `data/repositories/` les implémente
- Toujours injecter les dépendances (constructeur ou Riverpod provider) plutôt que d'instancier en interne
