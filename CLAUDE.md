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
make loadtest             # Test de charge HLS 50 auditeurs (STR-90) — depuis la racine, requiert ffmpeg
# Décision + run de référence : docs/adr/016-scalabilite-test-de-charge-et-limiteur-hls.md
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

# OpenAPI — depuis la racine du repo
make generate-openapi-client   # Régénère le client Dart/Dio depuis la spec OpenAPI
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
- `mobile/` — Flutter client (iOS, Android) — Clean Architecture + provider
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

### Logs structurés (STR-163, ADR 018)

- Logger racine : `observability.New(cfg, os.Stdout)` (zerolog, JSON), posé en global dans `main.go`.
- Dans un handler/service avec `ctx` : `zerolog.Ctx(ctx).Info().Str("k", "v").Msg("...")` — corrélé `request_id` par le middleware `httpmw.AccessLog`.
- Sans contexte HTTP (migrator, seeder, boot) : global `github.com/rs/zerolog/log`.
- **Jamais** `log.Printf`/`fmt.Println` (STR-170). Path loggable : `httpjson.LoggablePath` (masque le `stream_key`).
- Requête Loki type : `{service="api"} | json | level="error"` (Grafana → Explore).

### Métriques Prometheus (STR-165, ADR 019)

- Middleware `httpmw.Metrics(reg, mux)` (séparé d'`AccessLog`) : `http_requests_total{method,path,status}` + `http_request_duration_seconds{method,path}`.
- Le label `path` = pattern du routeur via `mux.Handler(r)` (aucune table à synchroniser) ; hors table → `{other}` ; méthodes hors allowlist → `other` ; routes longue durée (SSE, ingest) comptées mais exclues de l'histogramme de latence.
- `/metrics` n'est **pas** exposé publiquement : bloqué par Caddy en prod (403), scrape interne uniquement.
- Dashboards provisionnés (non éditables en UI) : `docker/grafana/provisioning/dashboards/` — la vérité vit dans git.

### Métriques métier du streaming (STR-166, ADR 022)

- Le domaine déclare `streaming.MetricsRecorder` (ISP) ; l'implémentation Prometheus vit dans `observability.NewStreamingMetrics` et est injectée dans `main.go` via `SetMetrics` (sessions + handler).
- `streampulse_hls_requests_total{stream_id,kind,status}` : seule famille portant un `stream_id` — les séries sont **supprimées à l'arrêt du flux** (`ForgetStream` sur `Stop`/`reap`/`StopAll`), sans quoi la cardinalité croîtrait à chaque diffusion.
- `streampulse_live_streams_active` : `GaugeFunc` branché sur `LiveSessions.ActiveCount()` — lit l'état réel à chaque scrape, aucune dérive possible.
- Auditeurs = **estimation** `rate(playlist) × durée de segment` (HLS est sans connexion persistante) ; latence et erreurs viennent des métriques HTTP de l'ADR 019.

### Traces OpenTelemetry (STR-164, ADR 020)

- `observability.NewTracer(ctx, cfg)` : OTLP/HTTP vers Tempo, noop si `OTEL_EXPORTER_OTLP_ENDPOINT` vide (`go run` local). Shutdown flush déféré dans `main.go`.
- Chaîne middleware : `CORS(Tracing(mux, AccessLog(logger, Metrics(reg, mux))))` — spans nommés par pattern de route, `/health`+`/metrics` non tracés.
- SQL : `otelpgx` sur le pool (`pool.go`) — un span par query, sans les arguments.
- Logs corrélés : `trace_id`/`span_id` ajoutés par `AccessLog` quand un span est actif → bouton TraceID dans Grafana (Loki `derivedFields`).

### Alertes Grafana (STR-167, ADR 021)

- Provisionnées as-code : `docker/grafana/provisioning/alerting/` (contact point email, policy, règles 5xx>5%/CPU>90%/goroutines>200, `for: 5m`).
- Dev : les emails d'alerte partent dans Mailpit (http://localhost:8025). Prod : relay `SMTP_*` du `.env`.
- Dashboard « Logs & Erreurs » : variables `$level` et `$trace_id`, dernières erreurs cliquables vers Tempo.

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
| DELETE | `/api/auth/me` | `Handler.DeleteAccount` | Oui (JWT) |

### Routes streams existantes

Domaine `internal/streaming/` (handler/service/repository). Détails dans [ADR 013](docs/adr/013-domaine-streaming.md).

| Méthode | Route | Handler | Auth requise |
|---|---|---|---|
| POST | `/api/streams` | `Handler.Create` | Oui — rôle `broadcaster` |
| GET | `/api/streams` | `Handler.List` | Non — découverte publique (invité), liste en direct paginée, sans secret |
| GET | `/api/streams/{id}` | `Handler.Get` | Oui (JWT) — réponse unique : propriétaire = `stream_key`/`stream_source_url` remplis, tiers = ces secrets à `null`, ou 404 (privé) |
| PUT | `/api/streams/{id}` | `Handler.Update` | Oui (JWT) — propriétaire uniquement |
| DELETE | `/api/streams/{id}` | `Handler.Delete` | Oui (JWT) — propriétaire uniquement, soft delete (`archived_at`) |
| PATCH | `/api/streams/{id}/start` | `Handler.Start` | Oui — rôle `broadcaster`, owner ; `idle→live` (409 si pas idle ou déjà un live) |
| PATCH | `/api/streams/{id}/stop` | `Handler.Stop` | Oui — rôle `broadcaster`, owner ; `live→ended` (409 si pas live) |
| GET | `/api/streams/{id}/events` | `Handler.Events` | Oui (JWT) — flux **SSE**, event `ended` à l'arrêt (STR-77) |
| PUT | `/api/streams/{id}/favorite` | `Handler.AddFavorite` | Oui (JWT) — ajoute aux favoris ; idempotent → 204 ; flux non visible → 404 (US-04-05). **PUT** et non POST : évite un conflit ServeMux avec `ingest/{stream_key}` |
| DELETE | `/api/streams/{id}/favorite` | `Handler.RemoveFavorite` | Oui (JWT) — retire des favoris ; idempotent → 204 (US-04-05) |
| GET | `/api/users/me/favorites` | `Handler.ListFavorites` | Oui (JWT) — liste « mes favoris » (tous statuts, visibles, non archivés), sans secret (US-04-05) |
| GET | `/api/users/me/streams` | `Handler.ListMine` | Oui (JWT) — tableau de bord diffuseur : **mes** flux (tous statuts, non archivés), **avec** `stream_key`/`stream_source_url` (le filtre porte sur le porteur du JWT) ; `[]` si aucun flux, jamais 403 (STR-153, ADR 024) |
| GET | `/api/streams/{id}/stats` | `Handler.Stats` | Oui (JWT) — audience du flux : auditeurs **estimés**, pic, durée. Propriétaire uniquement → 404 sinon ; flux non live → 200 avec compteurs à zéro (STR-154, ADR 025) |
| POST | `/api/streams/{id}/key/rotate` | `Handler.RotateKey` | Oui — rôle `broadcaster`, owner ; remet une `stream_key` neuve et invalide l'ancienne, 409 si le flux est **live** (l'index `byKey` de `LiveSessions` pointerait sur l'ancienne clé). Chemin en `key/rotate` et **non** `rotate-key` : ce dernier entre en conflit ServeMux avec `ingest/{stream_key}` (STR-228, ADR 028) |
| POST | `/api/streams/ingest/{stream_key}` | `Handler.Ingest` | **Non (JWT)** — auth par `stream_key` dans le path ; push audio segmenté en HLS (STR-70/71). Tout `audio/*` est accepté : l'AAC (et un `Content-Type` absent) part direct dans le segmenteur, tout autre format (MP3, OGG, WAV, …) passe par un ffmpeg de transcodage intercalé devant (STR-204, ADR 030) ; 415 si le corps est indécodable |
| GET | `/api/streams/{id}/playlist.m3u8` | `Handler.Playlist` | **Public** (`OptionalAuth`) — flux publics servis à un anonyme, privé → 404 ; owner authentifié voit ses flux privés — manifeste HLS, 409 si pas live/pas prêt (STR-108) ; 503 si capacité atteinte (`HLS_MAX_CONCURRENT`, STR-88) |
| GET | `/api/streams/{id}/segments/{segment}` | `Handler.Segment` | **Public** (`OptionalAuth`) — idem playlist — segment `.ts` (nom validé anti-traversal) (STR-108) ; 503 si capacité atteinte (`HLS_MAX_CONCURRENT`, STR-88) |

- Moteur HLS (STR-70) : le diffuseur pousse de l'AAC sur `ingest/{stream_key}` (auth par clé, 100 % mémoire) ; **ffmpeg** (`-c:a copy`) segmente en `.ts` de ~10 s + manifeste `.m3u8` glissant servi aux auditeurs. Un segmenteur par session live, tué + répertoire nettoyé à l'arrêt. Détails [ADR 015](docs/adr/015-moteur-hls-segmentation-ffmpeg.md).
- Transcodage d'ingest (STR-204, [ADR 030](docs/adr/030-transcodage-a-la-volee-des-formats-dingest.md)) : un **second** ffmpeg (`-c:a aac -f adts`) est intercalé devant le segmenteur quand le `Content-Type` n'est pas de l'AAC, et vit le temps du push. Le segmenteur reste en `-c:a copy` — le chemin AAC ne paie ni process ni ré-encodage. Le démultiplexeur `-f` vient d'une table close (`resolveIngestFormat`), jamais d'une chaîne du diffuseur. Des octets entrés sans AAC en sortie → **415** (corps indécodable), pas 500.
- Cycle de vie du direct (STR-77) : `start`/`stop` = endpoints dédiés (le PUT ne touche pas au statut) ; **un seul flux live par diffuseur** ; goroutines gérées par `LiveSessions` (context + mutex). Détails [ADR 013](docs/adr/013-domaine-streaming.md) §7.
- Titre **non unique** (contrainte retirée en `000015`) : pas de 409 sur le titre.
- `stream_key` (32 octets base64url, en clair) jamais exposé à un tiers ; URL source = `{STREAM_INGEST_BASE_URL}/api/streams/ingest/{stream_key}`.

### Routes playlists existantes

Domaine `internal/playlist/` (handler/service/repository). Playlists personnelles de
l'utilisateur : actions de niveau `user` (`auth.RequireAuth` seul, pas de rôle). Détails dans
[ADR 026](docs/adr/026-domaine-playlists.md).

| Méthode | Route | Handler | Auth requise |
|---|---|---|---|
| POST | `/api/playlists` | `Handler.Create` | Oui (JWT) — crée une playlist vide ; 409 si le nom est déjà utilisé (contrainte `uq_playlists_user_name`) |
| GET | `/api/playlists` | `Handler.List` | Oui (JWT) — playlists du demandeur avec `track_count` (LEFT JOIN), triées par date de création desc ; pas de pagination |
| GET | `/api/playlists/{id}` | `Handler.Get` | Oui (JWT) — propriétaire uniquement ; playlist d'un tiers → **404** (ne divulgue pas l'existence) |
| PUT | `/api/playlists/{id}` | `Handler.Update` | Oui (JWT) — renommage/description, propriétaire uniquement ; **remplacement total** (omettre `description` l'efface) ; 409 sur nom en doublon |
| DELETE | `/api/playlists/{id}` | `Handler.Delete` | Oui (JWT) — suppression définitive (cascade `playlist_tracks`), propriétaire uniquement ; 404 sinon |
| GET | `/api/playlists/{id}/tracks` | `Handler.ListTracks` | Oui (JWT) — pistes ordonnées par `position` ; propriété vérifiée via `GetPlaylist` (404 si tiers) |
| POST | `/api/playlists/{id}/tracks` | `Handler.AddTrack` | Oui (JWT) — ajoute une piste **du demandeur** en fin de playlist, renvoie l'ordre résultant (201) ; piste inconnue ou d'un tiers → 404 ; déjà présente → 409 (STR-132, ADR 029) |
| PUT | `/api/playlists/{id}/tracks` | `Handler.ReorderTracks` | Oui (JWT) — **remplacement total** de l'ordre (`{track_ids: [...]}`, index 0 = première piste), renvoie l'ordre persisté ; doublon → 400, liste qui ne couvre pas exactement la playlist → 409 (STR-132, ADR 029) |
| DELETE | `/api/playlists/{id}/tracks/{trackId}` | `Handler.RemoveTrack` | Oui (JWT) — retire la piste et **recompacte** les positions en 0..n-1 (204) ; piste absente → 404 (STR-132, ADR 029) |

- Tables `playlists` / `playlist_tracks` préexistantes (migration `000004`) ; contrainte `UNIQUE (user_id, name)` (`000006`).
- Isolation : `GetPlaylist` compare `user_id` ; `ListTracks` réutilise `GetPlaylist` ; `Update`/`Delete` filtrent sur `(id, user_id)` en SQL (0 ligne → 404).
- Ordre des pistes (US-05-03, [ADR 029](docs/adr/029-pistes-dune-playlist-ajout-retrait-reordonnancement.md)) : migration `000019` pose `UNIQUE (playlist_id, position)` **DEFERRABLE INITIALLY DEFERRED** — un réordonnancement réécrit toutes les positions dans une transaction, ses états intermédiaires contiennent forcément des doublons ; la contrainte n'est vérifiée qu'au COMMIT. Toutes les mutations de pistes passent donc par `inTx` (repository).
- ⚠️ Sur `playlist_tracks`, un `INSERT … ON CONFLICT` doit **nommer ses colonnes** (`ON CONFLICT (playlist_id, track_id)`) : une contrainte différée ne peut pas servir d'arbitre, et un `ON CONFLICT DO NOTHING` nu les considère toutes → SQLSTATE 55000 au démarrage (ADR 029 §2).

### Routes tracks existantes

Bibliothèque de pistes audio de l'utilisateur : domaine `internal/track/` (handler/service/
repository), extrait du domaine playlist (US-05-01, [ADR 032](docs/adr/032-domaine-track-upload-audio.md)).
Actions de niveau `user` (`auth.RequireAuth` seul, pas de rôle : l'US vise « diffuseur **ou** utilisateur »).

| Méthode | Route | Handler | Auth requise |
|---|---|---|---|
| POST | `/api/tracks` | `Handler.Upload` | Oui (JWT) — **upload multipart** (`file` + `title` requis, `artist`/`duration_s` optionnels) d'un audio MP3/AAC/OGG ≤ 50 Mo. MIME **sniffé côté serveur** (PDF renommé `.mp3` → 415) ; fichier stocké hors répertoire servi, piste référencée en base (201). 400 (titre/fichier manquant), 403 (quota de stockage/compte dépassé, `MaxUserStorageBytes` = 500 Mo — **403 et non 507** : condition client, hors bucket 5xx/alerte), 409 (titre en doublon `uq_tracks_user_title`), 413 (> 50 Mo), 415 (non-audio, prioritaire sur le quota) |
| GET | `/api/tracks` | `Handler.ListUserTracks` | Oui (JWT) — bibliothèque de pistes du demandeur, source du sélecteur d'ajout (US-05-03) |
| GET | `/api/tracks/{id}/stream` | `Handler.StreamTrack` | Oui (JWT) — sert le **binaire audio** d'une piste au lecteur mobile (US-05-04, [ADR 034](docs/adr/034-lecture-dune-playlist-avec-file-dattente.md)). Propriété vérifiée en SQL → piste d'un tiers = **404** (jamais 403 : ne pas révéler son existence) ; `http.ServeContent` honore les requêtes `Range` (206) ; `Content-Type` pris en base (jamais deviné) ; `Cache-Control: private, no-store`. Fichier absent du volume alors que la ligne existe → 404 + log `error` |

- Table `tracks` préexistante (migration `000003`) : `file_path`/`mime_type` (CHECK `audio/mpeg|aac|ogg`)/`file_size`/`duration_s` (CHECK `> 0`) ; contrainte `uq_tracks_user_title (user_id, title)` (`000006`). **Aucune migration** ajoutée par l'US-05-01.
- Stockage : `track.FileStorage` écrit sous `STORAGE_PATH` (volume Docker `track_storage`, `/data/tracks`), nom = UUID + extension canonique (jamais le nom client → anti-traversal). Interface `track.Storage` (`Save`/`Open`/`Remove`) pour découpler d'un futur stockage objet ; `Open` renvoie un `StoredFile` (`ReadSeeker` + `Closer` — le `Seek` est ce qui rend les requêtes `Range` possibles).
- Validation MIME par **sniff de contenu** (`github.com/gabriel-vasile/mimetype`), normalisé vers la valeur canonique du CHECK DB. Durée = champ client optionnel (pas d'extraction ffprobe). Détails [ADR 032](docs/adr/032-domaine-track-upload-audio.md).
- **Quota** : `MaxUserStorageBytes` (500 Mo) vérifié après `detectAudio` et avant écriture → **403** (`storage_quota_exceeded`, hors bucket 5xx) ; `ParseMultipartForm` borné à 1 Mio en mémoire (débordement disque temporaire) pour éviter l'OOM sous uploads concurrents. Borne de concurrence globale + alerte disque/cap global : tickets séparés.
- **Nettoyage des fichiers** : la suppression d'un compte (`admin.DeleteUser` **et** `auth.DeleteAccount`) passe par `track.Service.PurgeUserTracks(userID, deleteUser)` (injecté par `SetTrackPurger`, interface `UserTrackPurger`). Il **enrobe** le hard-delete : relève les chemins → exécute `deleteUser` (cascade DB sur `tracks`) → supprime les fichiers du volume **seulement si le delete a réussi** (pas de ligne fantôme). Best-effort. Pas encore de `DELETE /api/tracks/{id}` (hors périmètre US-05-01).
- Contrat OpenAPI : ces routes portent le tag `Track` → côté client généré, `listUserTracks`/`uploadTrack` vivent dans `TrackApi` (le `DioClient` mobile expose `trackApi`).

### Routes admin existantes

Réservées aux administrateurs (`auth.RequireAuth` + `auth.RequireRole("admin")`). Gestion des
utilisateurs : domaine `internal/admin/` ([ADR 017](docs/adr/017-tableau-de-bord-admin-gestion-utilisateurs.md)).
Supervision et interruption des flux actifs : même domaine `internal/admin/`
([ADR 039](docs/adr/039-supervision-admin-des-flux-et-journal-daudit.md)).
Demandes de rôle diffuseur : domaine `internal/broadcaster/` ([ADR 014](docs/adr/014-demande-activation-role-diffuseur.md)).

| Méthode | Route | Handler | Auth requise |
|---|---|---|---|
| GET | `/api/admin/users` | `admin.Handler.List` | Oui — rôle admin — recherche/filtres/pagination, réponse `{users, total}` |
| PATCH | `/api/admin/users/{id}` | `admin.Handler.SetActive` | Oui — rôle admin — active/désactive (`is_active`) ; 409 self-action, 409 dernier admin actif |
| DELETE | `/api/admin/users/{id}` | `admin.Handler.Delete` | Oui — rôle admin — hard delete (cascade), stoppe d'abord les lives du user ; mêmes 409 |
| GET | `/api/admin/streams` | `admin.Handler.ListStreams` | Oui — rôle admin — liste de modération paginée (tous les live, publics et privés, avec l'identité du diffuseur), réponse `{streams, total}` |
| POST | `/api/admin/streams/{id}/stop` | `admin.Handler.StopStream` | Oui — rôle admin — interruption immédiate (`live→ended`, sans contrôle de propriétaire) + entrée `audit_logs` best-effort ; 204/404/409 |
| GET | `/api/admin/broadcaster-requests` | `broadcaster.Handler.List` | Oui — rôle admin — liste les demandes (filtre `?status=`) |
| POST | `/api/admin/broadcaster-requests/{id}/approve` | `broadcaster.Handler.Approve` | Oui — rôle admin — valide + promeut l'utilisateur |
| POST | `/api/admin/broadcaster-requests/{id}/reject` | `broadcaster.Handler.Reject` | Oui — rôle admin — refuse + `review_note` |

### Documentation OpenAPI

La spec OpenAPI est la **source de vérité** du contrat HTTP (cf. [ADR 012](docs/adr/012-openapi-source-de-verite.md)).

- Spec embarquée dans le binaire : `backend/internal/openapi/openapi.yaml` (`//go:embed`).
- Endpoints, montés **uniquement si `!cfg.IsProd()`** dans `cmd/api/main.go` :
  - `GET /swagger/` — Swagger UI
  - `GET /swagger/openapi.yaml` — spec YAML brute
  - `GET /swagger` — redirection 308 vers `/swagger/`
- Après toute modif de route : mettre à jour `openapi.yaml`, puis régénérer le client mobile
  via `make generate-openapi-client`.

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

### Client API généré (OpenAPI)

Le client HTTP de la couche data est **généré** depuis la spec OpenAPI du backend, pas écrit à la main :

- Package local `mobile/packages/streampulse_api` (dépendance `path:` dans `pubspec.yaml` ;
  `*.g.dart` commités → pas besoin de `build_runner` avant compilation).
- Les DTOs de la couche data (`UserResponse`, `TokenPairResponse`, …) en proviennent.
- Conversion DTO généré → entité domaine via les extensions `toEntity()` dans
  `features/auth/data/mappers/auth_dto_mappers.dart` (le type généré ne fuit pas hors de la couche data).
- Régénération (depuis la racine du repo) : `make generate-openapi-client`.

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

### Lecture audio auditeur (STR-108/109/110)

Voir [ADR 023](docs/adr/023-lecteur-audio-hls-mobile.md) (lecteur HLS),
[ADR 031](docs/adr/031-lecture-audio-en-arriere-plan.md) (arrière-plan) et
[ADR 033](docs/adr/033-gestion-des-interruptions-audio.md) (interruptions),
[ADR 034](docs/adr/034-lecture-dune-playlist-avec-file-dattente.md) (file d'attente) et
[ADR 035](docs/adr/035-modes-shuffle-et-repeat.md) (shuffle/repeat).

- **Service partagé, app-level** : un unique `AudioPlayer` vit dans `StreamAudioHandler`
  (`core/audio/`, `audio_service` + just_audio), initialisé dans `main()` via `AudioService.init`
  et fourni par `app_providers.dart`. La lecture **survit à la navigation** et à l'arrière-plan /
  verrouillage (notification + contrôles système).
- **Deux interfaces sur ce lecteur unique** (ISP, ADR 034) : `PlaybackTransport` (play/pause/stop +
  flux d'état/erreurs) est étendu par `AudioPlaybackService` (`loadUri`, direct) et
  `QueuePlaybackService` (`loadQueue`/`skipToIndex`/`currentIndexStream`, file d'attente).
  `StreamAudioHandler` implémente les deux ; `main()` l'injecte sous ses deux rôles.
- **DIP** : le `AudioPlayerController` (app-level, `ChangeNotifierProvider`) dépend de l'abstraction
  `AudioPlaybackService`, jamais de just_audio/audio_service directement → testable avec un fake
  (`test/support/fake_audio_playback_service.dart`).
- **Répartition** : le handler mappe l'état → notification et **transmet** les erreurs ; le
  contrôleur garde l'arbitrage STR-118 (reconnexion bornée 1/2/4/8 s, gardes `_disposed`/`ended`).
  État terminal → `stop()` retire la notification.
- **Ambiguïté du 409** : le manifeste renvoie 409 pour un flux **terminé** *comme* pour un flux live
  **pas encore prêt** (démarrage ~10 s). Le contrôleur ne conclut « terminé » via
  `isManifestUnavailable` que si la lecture avait démarré (`_hasPlayed`) ; sinon il reconnecte
  d'abord. La sonde utilise `validateStatus` (<500) pour ne pas logger de faux « erreur ».
- **Mini-player** : `MiniPlayer` (titre/diffuseur, play/pause, croix = `stop`) est masqué à l'état
  `idle`. Le plein écran (`StreamPlayerScreen`) lit aussi ce contrôleur partagé et **ne le détruit
  pas**. Dans `MainShell`, c'est `PlayerBar` (`app/shell/`) qui choisit entre ce mini-player et
  celui de la file d'attente.
- **Natif** : `MainActivity` étend `AudioServiceActivity` ; le manifeste déclare
  `com.ryanheise.audioservice.AudioService` (`mediaPlayback`) + `MediaButtonReceiver`, et les
  permissions `WAKE_LOCK` (sinon `startForeground()` n'est jamais appelé → kill) + `POST_NOTIFICATIONS`
  (demandée au runtime via `ensureNotificationPermission()`) ; iOS a `UIBackgroundModes: audio`.
  L'arrière-plan ne se teste **que sur device** (pas sur web).
- **Interruptions (STR-110, ADR 033)** : le handler configure l'`AudioSession` (`music`), crée le
  player en `handleInterruptions: false`, et applique une `InterruptionPolicy` **pure/testable**
  (`core/audio/`) : appel → pause puis reprise (si c'est nous qui avions mis en pause) ; notification
  → duck/unduck ; casque débranché → pause sans reprise. L'état se propage au mini-player/notification
  via `playerStateStream` (aucun changement contrôleur/UI).

### Lecture d'une playlist avec file d'attente (US-05-04)

Voir [ADR 034](docs/adr/034-lecture-dune-playlist-avec-file-dattente.md).

- **`PlaylistQueueController`** (app-level, `features/playlists/presentation/providers/`) : lance une
  file de pistes, expose la file et l'index courant. Sa source est une playlist **ou** la
  bibliothèque (STR-231) : `play(tracks:, sourceName:, playlistId:)` prend des `Track` (le type sans
  position), `playlistId` reste nul hors playlist — c'est lui qui permet à l'écran de détail de
  souligner « la piste en cours **de cette** playlist ». Un appui sur une ligne de « Mes pistes »
  lance **toute** la bibliothèque à partir d'elle : une file d'un seul élément rendrait
  précédent/suivant et les modes de lecture sans objet. L'**enchaînement est délégué au lecteur natif**
  (`ConcatenatingAudioSource`, qui précharge la suivante) ; le contrôleur suit
  `currentIndexStream` — un saut fait depuis la notification système remonte donc par le même
  chemin qu'un appui dans l'app, sans seconde source de vérité.
- **Un lecteur pour deux sources** : démarrer une file appelle `stopLive` (→ `AudioPlayerController
  .stop`) ; démarrer un direct appelle `onTakeOver` (→ `PlaylistQueueController.clear`, qui vide la
  file **sans** toucher au lecteur — l'arrêter couperait le direct). Câblage croisé dans
  `app_providers.dart`, arbitrage d'affichage dans `PlayerBar`.
- **Auth du lecteur natif** : le binaire d'une piste est privé, chaque `AudioSource` porte un
  `Authorization`. just_audio ouvrant ses propres connexions HTTP, il ne traverse pas les
  intercepteurs de `DioClient` : `PlaybackAuth` (`core/audio/`) fournit le token, et
  `DioClient.refreshTokens()` (public) alimente la reprise. Jamais de token en paramètre d'URL.
- **Reprise après échec** : bornée à 3 tentatives, backoff 1/2/4 s, position conservée, et **seule
  la première** force une rotation de token (une expiration se règle en une rotation). Le compteur
  ne se réarme qu'à une action utilisateur ou à un changement de piste — pas sur `ready`, sinon un
  réseau instable relancerait la même piste sans fin. La cause de l'échec n'est pas devinée :
  just_audio ne remonte pas le statut HTTP (ADR 034 §5).
- **UI** : bouton « Lire » + appui sur une ligne dans `PlaylistDetailScreen` (démarre à cette
  piste), `QueueMiniPlayer` (précédent/play/suivant/croix), `PlaybackQueueSheet` (file visible,
  appui = saut). La file est une **photo** des pistes au lancement : réordonner la playlist ne
  change pas ce qui joue tant qu'on ne relance pas.
- **Avancement et navigation dans la piste (STR-230)** : `positionStream` / `bufferedPositionStream`
  / `durationStream` / `seek` vivent sur `QueuePlaybackService` **et pas** sur `PlaybackTransport`
  (un direct n'a pas de position). Rendu par `queue_progress.dart` : trait de 2 px sur le bandeau,
  `Slider` manipulable dans la feuille (le bandeau fait 60 px, on n'y vise pas au pouce). Durée lue
  dans le **lecteur**, `duration_s` de la base ne servant que de valeur d'attente (déclaré par le
  client à l'upload, il peut mentir). Le serveur ne coûte rien : `Range` déjà géré (ADR 034 §1).

### Modes shuffle et repeat (US-05-05)

Voir [ADR 035](docs/adr/035-modes-shuffle-et-repeat.md).

- **Mélange tiré par le lecteur natif** (`setShuffleModeEnabled` + `shuffle()`), jamais côté Dart :
  l'application règle le mode et **lit** l'ordre obtenu (`effectiveIndices`). `shuffle()` est appelé
  avant l'activation (il garde la piste courante en tête → la lecture n'est pas coupée) et après
  chaque `loadQueue` (une source neuve arrive avec un ordre naturel).
- ⚠️ **Un ordre n'est tiré que sur demande de l'auditeur** (`play`). Un rechargement **subi**
  (reprise après erreur, relance d'une file terminée) passe l'ordre courant à `loadQueue`, que le
  handler réapplique via `_FixedShuffleOrder` : sans ça, l'expiration d'access token (15 min,
  ADR 034 §5) réécrirait la suite de la file à ce rythme.
- **`PlaybackOrder`** (`core/audio/playback_order.dart`) : objet **pur** (comme `InterruptionPolicy`)
  portant `positionOf` et `relative(current, ±1, wrap:)`. Utilisé par le contrôleur **et** par
  `StreamAudioHandler._skipRelative` (boutons de la notification) → une seule règle.
- ⚠️ **`repeat one` ne gouverne que l'enchaînement automatique** : un saut manuel avance quand même.
  D'où le remplacement de `seekToNext()`/`seekToPrevious()`, qui sous `LoopMode.one` rejouent la
  piste courante.
- Énumération applicative `QueueRepeatMode` (`off`/`one`/`all`), traduite en `LoopMode` par le seul
  handler. **Préfixée `Queue`** : `material.dart` exporte déjà un `RepeatMode` (animations).
- **Les modes appartiennent au contrôleur**, pas au lecteur (que le direct remet à zéro en prenant
  la main) : réappliqués avant chaque chargement, conservés après `stop()`, perdus au redémarrage
  (pas de persistance). Non exposés aux commandes système (l'état ne serait pas relu → dérive).
- **UI** : toggles « Aléatoire » / répétition (3 états) dans `PlaybackQueueSheet` ; action
  « Lire en aléatoire » dans l'AppBar de `PlaylistDetailScreen`, avec **piste de départ tirée au
  sort**. La file affichée et le « n/total » suivent l'**ordre de lecture**, pas celui de la playlist.

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
(`try/catch` silencieux), puis purge **toujours** `SecureStorage`. Le `profile_screen`
(`_logout()`) complète avec `BroadcasterController.reset()` et `FavoritesController.reset()` :
le conteneur `provider` n'offrant pas d'invalidation déclarative
(cf. [ADR 036](docs/adr/036-state-management-flutter-provider.md)), tout contrôleur
**app-level** portant de l'état lié au compte doit être remis à zéro à la main.
Les contrôleurs **locaux à l'écran** n'ont rien à faire : ils repartent vierges à la reconstruction.

**Erreurs 401** : message UI **hard-codé** (`'Email ou mot de passe incorrect'`) — ne jamais
relayer le `serverMessage` pour éviter une fuite d'info technique. Les 400/409/5xx peuvent en
revanche utiliser `serverMessage` (codes business contrôlés).

**UI auth** : un seul `AuthScreen` avec onglets en place (`AnimatedSwitcher` entre `LoginView`
et `RegisterView`, pas de changement de route). `LoginScreen` et `RegisterScreen` sont des
wrappers minces vers `AuthScreen(initialTab: ...)`.

**Toasts** : `toastification` via les helpers `showAuthSuccessToast / ErrorToast / InfoToast`
(`presentation/widgets/auth_toasts.dart`). `ToastificationWrapper` est posé dans `app.dart`.

### Accessibilité et adaptation aux largeurs (STR-244, ADR 043)

- ⚠️ **Un `tooltip` n'est pas un `label`.** Vérifié sur l'arbre sémantique : un
  `IconButton(tooltip: 'X')` rend `label="" tooltip="X"`. Android s'en sert à défaut de
  description ; **iOS en fait un *hint***, donc VoiceOver annonce « bouton » sans nom.
  Utiliser `AccessibleIconButton` (`core/widgets/`), qui pose les deux, et dont le libellé
  décrit l'**action** (« Mettre en pause »), jamais l'icône ni l'état.
- Une **ligne de liste** porte une phrase unique via `Semantics(container: true, label: ...)`
  et masque ses enfants : sinon un lecteur d'écran annonce « 3 », « Sunrise », « Neon Lights »
  en trois arrêts sans jamais dire laquelle joue. Les boutons d'une liste **nomment leur
  cible** (« Interrompre le flux X »).
- Tests : `test/support/accessibility.dart` — `expectMeetsAccessibilityGuidelines` (les 4
  vérificateurs de `flutter_test`) et `expectNoTooltipOnlyTapTargets`, plus stricte car
  `labeledTapTargetGuideline` accepte un tooltip seul. Toujours `tester.ensureSemantics()`
  avant de monter le widget, sinon il n'y a pas d'arbre à inspecter.
- **Responsive** : `Breakpoints` + `ResponsiveContent` (`core/layout/`). Le paysage est
  autorisé par les deux manifestes — décision prise d'**adapter** plutôt que de verrouiller
  le portrait. `ResponsiveContent` borne et centre au-delà de 600 px ; **sans effet en
  portrait téléphone**, la contrainte n'y mord pas.
- ⚠️ **Ne pas lancer `dart format` sur des fichiers existants** : la version courante du
  formateur réécrit des lignes non touchées et peut introduire des lints. Ne formater que
  les fichiers qu'on crée.

### Conventions Flutter — State management

Choisir **le plus simple qui suffit**, dans cet ordre :

| Niveau | Outil | Quand |
|---|---|---|
| 1 | `setState` | État local jetable d'un seul widget (`_isLoading`, `_hidePassword`) |
| 2 | `ValueNotifier` + `ValueListenableBuilder` | Une seule valeur réactive locale sans reconstruire tout le widget |
| 3 | `ChangeNotifier` + `provider` | État partagé entre plusieurs écrans (session, thème) |

- `context.watch<T>()` dans `build()` uniquement — reconstruit à chaque `notifyListeners()`
- `context.read<T>()` dans les callbacks (`onPressed`, `_onSubmit`) uniquement — ne reconstruit pas
- `notifyListeners()` après chaque mutation d'un notifier
- ⚠️ **Un flux haute fréquence ne traverse jamais un `ChangeNotifier` app-level.** Position de
  lecture, niveau audio, chrono : à ~5 Hz, un `notifyListeners()` reconstruit tout l'arbre sous le
  contrôleur. Le contrôleur expose le `Stream` tel quel, le widget qui l'affiche s'y abonne seul
  (exemple : `queue_progress.dart`, STR-230).
- ⚠️ **Un getter de `Stream` rend souvent un objet neuf à chaque accès** (`StreamController.stream`
  le fait) : un `StreamBuilder` branché dessus se réabonne à chaque reconstruction. Sans conséquence
  sur un flux continu, fatal sur un flux qui n'émet qu'une fois (une durée de piste). S'abonner une
  fois dans `initState` quand la valeur compte.

### Conventions Flutter — Async & cycle de vie

- `if (!mounted) return;` après **chaque** `await` avant d'utiliser `context` ou `setState`
- `dispose()` systématique des `TextEditingController` et `ValueNotifier`

### Conventions Flutter — Couche données

- Pas d'appel réseau direct dans un écran — toujours via un repository
- Models avec `fromJson` / `toJson`, classes immuables (`final`, `const`)
- Erreurs gérées avec des exceptions typées + toast — ne jamais relayer un message serveur brut sur une erreur 401

### Conventions Flutter — Style

- Couleurs via `Theme.of(context).colorScheme`, jamais codées en dur
- Guillemets simples `'...'`, `const` partout où possible, imports relatifs
- Handlers privés préfixés `_` (`_onSubmit`, `_loadData`)
- Pas de `print` — utiliser un guard `if (kDebugMode)`

## Architecture Docker

Réseau interne : `streampulse-net` (bridge Docker). Tous les services y sont connectés.

| Service | Image | Rôle | Port interne | Port hôte |
|---|---|---|---|---|
| `postgres` | `postgres:16-alpine` | Base de données | 5432 | — |
| `api` | build local Go 1.22 | API REST | 8080 | 8080 |
| `mailpit` | `axllent/mailpit:latest` | Email de test (dev) | 1025 (SMTP), 8025 (UI) | 1025, 8025 |
| `prometheus` | `prom/prometheus:latest` | Métriques | 9090 | 9090 |
| `loki` | `grafana/loki:latest` | Logs | 3100 | — |
| `alloy` | `grafana/alloy:latest` | Collecte logs Docker → Loki (ADR 018) | 12345 | — |
| `node_exporter` | `prom/node-exporter:latest` | Métriques machine pour Prometheus (ADR 019) | 9100 | — |
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
| `CORS_ALLOWED_ORIGINS` | Origines CORS autorisées, séparées par des virgules (en dev, localhost/127.0.0.1 autorisés d'office) | `https://app.streampulse.com` |
| `STREAM_INGEST_BASE_URL` | Préfixe de l'URL de stream source du diffuseur (cf. ADR 013) : `{base}/api/streams/ingest/{stream_key}` | `http://localhost:8080` |
| `STORAGE_PATH` | Répertoire racine des fichiers audio uploadés (US-05-01, ADR 032), hors répertoire servi. Volume Docker `track_storage` en conteneur ; chemin relatif au repo en `go run` local | `/data/tracks` |
| `HLS_MAX_CONCURRENT` | Nombre max de requêtes HLS simultanées servies aux auditeurs (0 = illimité) | `256` |
| `TRUST_PROXY_HEADERS` | Lire `X-Forwarded-For` pour identifier les auditeurs (comptage d'audience, ADR 025). `false` en local ; `true` **uniquement** derrière un reverse proxy, sinon le compteur sature à 1 | `false` |
| `LOG_LEVEL` | Niveau minimal des logs JSON (`trace`\|`debug`\|`info`\|`warn`\|`error`) — ADR 018 | `info` |
| `LOG_PRETTY` | Sortie console lisible, réservée au `go run` local hors Docker (jamais en conteneur) | `true` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Endpoint OTLP/HTTP Tempo pour les traces (vide = tracing désactivé) — ADR 020 | `http://tempo:4318` |

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
| `docs/README.md` (§ Index complet des ADR) | **Les 40 ADR**, avec leur numéro et leur décision |
| `docs/adr/001-choix-stack-observabilite.md` | Décision : stack LGTM vs ELK, Datadog, New Relic |
| `docs/adr/002-choix-conteneurisation-docker.md` | Décision : Docker Compose vs Podman, Nix, K8s local |
| `docs/adr/003-choix-cicd-github-actions.md` | Décision : GitHub Actions + GHCR vs GitLab CI, Jenkins, CircleCI |
| `docs/adr/006-authentification-jwt.md` | Décision : JWT HS256 + rotation refresh côté backend |
| `docs/adr/009-authentification-flutter.md` | Décision : stockage sécurisé, refresh auto, logout best-effort côté Flutter |
| `docs/adr/012-openapi-source-de-verite.md` | Décision : OpenAPI source de vérité du contrat HTTP + client Dart/Dio généré |
| `docs/adr/036-state-management-flutter-provider.md` | Décision : `provider` + `ChangeNotifier` (supersede l'ADR 005 sur ce point) |
| `docs/adr/037-initialisation-base-de-donnees.md` | Décision : schéma, migrations et seed PostgreSQL |

**Règle :** toute nouvelle décision d'architecture significative → nouvel ADR dans `docs/adr/`
avec le numéro suivant (prochain : `044-...`). Référencer le ticket Linear correspondant.
Un numéro n'est **jamais** réutilisé, et une ADR remplacée passe en `Superseded by NNN` plutôt
que d'être réécrite. Chaque ADR porte un bloc **Date / Statut / Ticket** et une section
**« Alternatives écartées »**.

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
- Toujours injecter les dépendances (constructeur ou `provider`) plutôt que d'instancier en interne
