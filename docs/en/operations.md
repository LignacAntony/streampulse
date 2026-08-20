# Operations — StreamPulse

> 🇫🇷 **Version française : [docs/infrastructure.md](../infrastructure.md)** —
> the French version is the reference and goes further: it carries the full
> troubleshooting runbook and the VPS procedures, written for the team that
> operates the service. This page covers what a reader needs to run, observe
> and deploy the stack.

---

## Services

| Service | Image | Role | Internal port | Host port | Healthcheck |
|---|---|---|---|---|---|
| `postgres` | `postgres:16-alpine` | Relational database | 5432 | — | `pg_isready` |
| `api` | local build (Go 1.25) | REST API: auth, HLS streaming, playlists, tracks, admin | 8080 | **8080** | `GET /health` |
| `prometheus` | `prom/prometheus:latest` | Metric collection | 9090 | **9090** | `GET /-/healthy` |
| `loki` | `grafana/loki:latest` | Log aggregation | 3100 | — | none (distroless) |
| `tempo` | `grafana/tempo:latest` | Distributed traces (OTLP) | 3200, 4317, 4318 | — | none (distroless) |
| `grafana` | `grafana/grafana:latest` | Observability dashboards | 3000 | **3000** | `GET /api/health` |

> **On Loki and Tempo.** Both images are distroless — no shell, no `wget`, no
> `curl` — so an HTTP healthcheck cannot run from inside the container. They
> start correctly; Grafana waits on them with `service_started` rather than
> `service_healthy`. This is a property of the images, not a gap in the
> configuration.

Internal network: `streampulse-net` (Docker bridge).
Named volumes: `postgres_data`, `grafana_data`.

## First run

```bash
cp .env.example .env
$EDITOR .env          # set JWT_SECRET and the passwords
docker compose up -d
docker compose ps     # every service should be healthy or started
```

The API applies its migrations at startup and seeds development data when
`GO_ENV=development`. A missing required variable, or a `JWT_SECRET` shorter
than 32 characters, makes it **refuse to start** — deliberately, so that a
misconfiguration fails immediately instead of surfacing later as a confusing
runtime error.

## Everyday commands

```bash
docker compose up -d                     # start everything
docker compose down                      # stop, keeping volumes
docker compose down -v                   # stop and delete volumes
docker compose logs -f api               # follow one service
docker compose build api && docker compose up -d api   # rebuild the API
```

## Local URLs

| Service | URL | Credentials |
|---|---|---|
| Grafana | http://localhost:3000 | `admin` / `$GRAFANA_ADMIN_PASSWORD` |
| Prometheus | http://localhost:9090 | — |
| API | http://localhost:8080 | JWT, depending on the route |
| API health | http://localhost:8080/health | — |
| Swagger UI | http://localhost:8080/swagger/ | — (not mounted in production) |

## Checking service health

```bash
docker compose ps

curl -s -o /dev/null -w "%{http_code}" http://localhost:9090/-/healthy   # Prometheus
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/health  # Grafana
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health      # API

# Is Prometheus actually scraping the API?
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[].health'
```

## Observability

**Metrics.** Prometheus scrapes the API every 15 seconds. Path labels carry the
**router pattern**, never the raw URL — an unbounded label would grow the series
count without limit (ADR 019).

**Logs.** One JSON line per request, correlated by `request_id`, and by
`trace_id` when a span is active. In Grafana: *Explore* →
`{service="api"} | json | level="error"`.

**Traces.** Exported over OTLP to Tempo, one span per SQL query — without the
arguments. Tracing is disabled when `OTEL_EXPORTER_OTLP_ENDPOINT` is empty, so a
local `go run` needs no collector.

**Alerting.** Contact points, policies and rules are provisioned as code under
`docker/grafana/provisioning/alerting/`. They are therefore not editable from
the Grafana UI — the truth lives in git, and an alert configured by hand would
be lost with its container.

**Retention** is set explicitly on every store rather than inherited from image
defaults: 30 days for logs, 7 for traces, 90 for metrics. The reasoning is in
`docs/rgpd.md`, and the short version is that logs carry a client network prefix
and a user id, so an undefined retention period is not acceptable.

## CI/CD

| Workflow | Trigger | What it does |
|---|---|---|
| **CI** | push and pull requests on `develop` and `main` | Go lint, tests (unit and integration, against a PostgreSQL service), coverage gate at 80 %, build, Flutter analyze and tests, plus repository guards |
| **CD** | successful CI on `main`, or manual dispatch | Build and push the Docker image to GHCR, deploy over SSH, then release-please, then the Android build |
| **Security** | push on `develop` and `main`, plus weekly | Trivy on Go dependencies and on the image, gosec, gitleaks |

The coverage gate fails below **80 %** on a declared scope; what is excluded and
why is documented in `docs/couverture-de-tests.md`.

Releases are produced by **release-please** from Conventional Commits. Merging
its release PR creates the tag and the GitHub release, and the Android artefacts
are attached to it — see `docs/distribution-mobile.md`.

> `CHANGELOG.md` is generated. Editing it by hand is the one thing not to do.

## Production

The API is reachable at `https://api.streampulse.win`, behind Caddy, which
terminates TLS with automatic Let's Encrypt certificates.

`/metrics`, Prometheus and Grafana are **not meant to be reachable from the
internet**: `docker-compose.prod.yml` binds those ports to `127.0.0.1`, and the
Caddy configuration answers 403 on `/metrics`. Remote access goes through an SSH
tunnel.

> The French version documents the manual VPS update procedure, the deployment
> checks and the full troubleshooting runbook. Those are operational procedures
> for the team that runs the service, and they are the part of this document
> that stays French-only.
