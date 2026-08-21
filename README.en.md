# StreamPulse

> StreamPulse platform — Go backend, Flutter application, containerised deployment.

[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://conventionalcommits.org)
[![Release](https://img.shields.io/github/v/release/LignacAntony/streampulse)](https://github.com/LignacAntony/streampulse/releases)

> 🇫🇷 **Version française : [README.md](README.md)** — the French version is the
> reference. When the two disagree, the French one is right, and the divergence
> is a bug worth reporting.

---

## Contents

- [Tech stack](#tech-stack)
- [Repository layout](#repository-layout)
- [Requirements](#requirements)
- [Install and run](#install-and-run)
- [API documentation](#api-documentation)
- [Environment variables](#environment-variables)
- [Git workflow](#git-workflow)
- [Commit conventions](#commit-conventions)
- [Contributing](#contributing)

---

## Tech stack

| Layer | Technology |
| --- | --- |
| Backend / API | **Go** |
| Application | **Flutter** (iOS, Android) |
| Containerisation | **Docker** + Docker Compose |
| CI/CD | GitHub Actions |
| Project tracking | Linear ([StreamPulse project](https://linear.app/streampulse)) |

## Repository layout

```
streampulse/
├── backend/         # Go API
├── mobile/          # Flutter application (iOS + Android)
├── docker/          # Docker configuration (prometheus, grafana, loki, tempo)
├── docs/            # Technical documentation
└── .github/         # CI/CD workflows and templates
```

## Requirements

- [Go](https://go.dev/dl/) ≥ 1.22
- [Flutter](https://docs.flutter.dev/get-started/install) ≥ 3.22
- [Docker](https://docs.docker.com/get-docker/) + Docker Compose
- [Git](https://git-scm.com/) with SSH or GPG signing configured — commits on
  `main` must be signed

## Install and run

```bash
# 1. Clone the repository
git clone git@github.com:LignacAntony/streampulse.git
cd streampulse

# 2. Copy the environment template and fill in the values
cp .env.example .env
$EDITOR .env  # replace JWT_SECRET and the passwords

# 3. Start the stack with Docker
docker compose up -d

# 4. (Backend) Run the Go API locally, outside Docker
cd backend && go run ./cmd/api

# 5. (App) Run the Flutter application
cd mobile && flutter run
```

## API documentation

The API serves its own OpenAPI documentation through Swagger UI:

- Interactive UI: `http://localhost:8080/swagger/`
- Raw YAML specification: `http://localhost:8080/swagger/openapi.yaml`

> ⚠️ These endpoints are **not mounted in production** (`GO_ENV=production`), so
> that the API surface is not published. They remain available in development
> and test.

The Dart/Dio client used by the Flutter application is generated from that
specification:

```bash
make generate-openapi-client
```

The command runs the `openapitools/openapi-generator-cli:v7.23.0` Docker image,
overwrites `mobile/packages/streampulse_api`, then regenerates the Dart
serialisers.

## Environment variables

The project follows the [**12-Factor App**](https://12factor.net/config)
methodology: all configuration is externalised through environment variables,
and **no value is hard-coded** in the source.

### Setup

1. Copy the template: `cp .env.example .env`
2. Fill in the sensitive values (`JWT_SECRET`, passwords, …)
3. **Never commit** `.env` — it is listed in `.gitignore`, and a CI check
   (gitleaks plus a set of greps) fails on any hard-coded secret

### Available variables

| Variable | Description | Default | Required | Example |
| --- | --- | --- | --- | --- |
| `GO_ENV` | Runtime environment (`development`, `production`, `test`) | `development` | no | `production` |
| `API_PORT` | HTTP port the Go API listens on | `8080` | no | `8080` |
| `JWT_SECRET` | JWT signing key — **32 characters minimum** | — | **yes** | `<random string ≥ 32 chars>` |
| `DB_HOST` | PostgreSQL host | `localhost` | no | `postgres` (under compose) |
| `DB_PORT` | PostgreSQL port | `5432` | no | `5432` |
| `DB_USER` | PostgreSQL user | — | **yes** | `streampulse` |
| `DB_PASSWORD` | PostgreSQL password | — | **yes** | `<strong password>` |
| `DB_NAME` | PostgreSQL database name | — | **yes** | `streampulse_db` |
| `INGEST_RECONNECT_GRACE_SECONDS` | Silence tolerated before a live stream is stopped automatically. Must exceed 30 s — the mobile client's maximum backoff — or the API refuses to start | `45` | no | `45` |
| `INGEST_STOP_TIMEOUT_SECONDS` | Timeout for one automatic stop attempt against the database | `10` | no | `10` |
| `POSTGRES_USER` | Compose alias for `DB_USER` (Postgres container init) | — | **yes (compose)** | `streampulse` |
| `POSTGRES_PASSWORD` | Compose alias for `DB_PASSWORD` | — | **yes (compose)** | `<strong password>` |
| `POSTGRES_DB` | Compose alias for `DB_NAME` | — | **yes (compose)** | `streampulse_db` |
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin password | — | **yes (compose)** | `<strong password>` |

### Implementation

Loading is centralised in [`backend/internal/config`](./backend/internal/config).
It uses [Viper](https://github.com/spf13/viper) to:

- load a `.env` file from the repository root when present (local development);
- read environment variables, which take precedence in production;
- apply the defaults documented above;
- **validate fail-fast** at startup — a missing required variable, or a
  `JWT_SECRET` shorter than 32 characters, and the API refuses to start.

```go
cfg, err := config.Load()
if err != nil {
    log.Fatalf("config: %v", err)
}
```

## Git workflow

The repository follows a **simplified Git Flow**:

| Branch | Role |
| --- | --- |
| `main` | Production code. Protected — merges only through an approved PR. |
| `develop` | Integration branch. Every feature is merged here first. |
| `feature/<ticket>-<slug>` | Feature branches, cut from `develop`. |
| `fix/<ticket>-<slug>` | Fix branches. |
| `hotfix/<ticket>-<slug>` | Urgent fixes, cut from `main`. |

**Rules**

- No direct push to `main` or `develop`
- Every PR requires **at least one approving review**
- No force-push — non-fast-forward updates are blocked
- Commits on `main` must be **signed**

## Commit conventions

The project uses [**Conventional Commits**](https://www.conventionalcommits.org/en/v1.0.0/):

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types**: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`,
`ci`, `chore`, `revert`.

> Commit and PR descriptions are written **in French** — this is a project
> convention, not an oversight. The documentation is bilingual; the commit
> history is not.

**PR titles** are validated automatically by GitHub Actions. See
[CONTRIBUTING.md](./CONTRIBUTING.md) for details.

## Contributing

Read [CONTRIBUTING.md](./CONTRIBUTING.md) before opening a PR.
