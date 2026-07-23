# ADR 019 — Métriques Prometheus : middleware dédié, cardinalité bornée, dashboards provisionnés

**Date** : 2026-07-23
**Statut** : Accepté
**Ticket** : [STR-165](https://linear.app/streampulse/issue/STR-165) (sous-issues [STR-178](https://linear.app/streampulse/issue/STR-178), [STR-179](https://linear.app/streampulse/issue/STR-179), [STR-180](https://linear.app/streampulse/issue/STR-180), [STR-181](https://linear.app/streampulse/issue/STR-181), [STR-182](https://linear.app/streampulse/issue/STR-182), [STR-183](https://linear.app/streampulse/issue/STR-183))

---

## Contexte

US-07-03 : Prometheus scrape `/metrics` depuis l'ADR 001 mais l'endpoint était un stub
vide. STR-165 expose les vraies métriques HTTP et infrastructure, et les visualise dans
deux dashboards Grafana. S'appuie sur la chaîne middleware posée par STR-163 (ADR 018).

## Décision

### 1. Middleware `httpmw.Metrics` séparé d'`AccessLog`

Logs et métriques sont deux préoccupations (SRP) : middlewares distincts, composés dans
`main.go` — `CORS(AccessLog(logger, Metrics(reg, mux)))`. `Metrics` est au plus près du
mux : les préflights CORS ne sont pas comptés. Le `statusRecorder` de STR-163 est
réutilisé (même package). Le registre est injecté (`prometheus.Registerer`) — registre
réel dans `main.go`, registre neuf dans chaque test.

### 2. Cardinalité des labels : pattern du mux + allowlists (révisé en revue de PR)

Le path brut contient des UUID → une série Prometheus par ressource. Le `r.Pattern`
de Go 1.22 est invisible du middleware (copie de requête), mais **`mux.Handler(r)`**
retourne le pattern matché *sans exécuter le handler* : `Metrics` prend le
`*http.ServeMux` et dérive le label depuis la vraie table de routage — aucune copie
à synchroniser (la première version dupliquait les routes dans une table de regex,
supprimée en revue). Pattern vide (404, 405, redirections) → **`{other}`** : un scan
de bot ne crée qu'une série.

Même logique pour `method` : net/http accepte n'importe quel token HTTP comme
méthode ; hors allowlist (`GET/HEAD/POST/PUT/PATCH/DELETE/OPTIONS`) → `other`.

Les routes longue durée (`/api/streams/{id}/events` en SSE, ingest diffuseur) sont
comptées dans `http_requests_total` mais **exclues de l'histogramme** : une unique
observation de plusieurs minutes tomberait dans le bucket `+Inf` et fausserait les
quantiles globaux.

### 3. Métriques exposées

- `http_requests_total{method, path, status}` (counter)
- `http_request_duration_seconds{method, path}` (histogram, buckets par défaut —
  p50/p95/p99 calculés à la requête via `histogram_quantile`)
- Collectors Go du registre par défaut : `go_goroutines`, `go_memstats_*` (gratuits)
- `/health` et `/metrics` exclus (healthcheck 15 s + scrape 15 s pollueraient) —
  prédicat `skipObservability` partagé avec `AccessLog`
- `/metrics` **non exposé publiquement** : `respond /metrics 403` dans le Caddyfile
  et port API bindé sur `127.0.0.1` en prod — Prometheus scrape en interne via
  `streampulse-net` (le registre révèle routes, volumes, version Go)

### 4. node_exporter dans les deux composes

Panel Infra = CPU/RAM machine → `prom/node-exporter` (rootfs `/host` en lecture seule),
ajouté au compose **dev et prod** (leçon de STR-163 : la parité évite les oublis).
Limite connue : sous Docker Desktop il mesure la VM Linux, pas le Mac — suffisant pour
développer le dashboard ; vraies valeurs sur le VPS. Scrape ajouté à `prometheus.yml`
(job `node`).

### 5. Dashboards provisionnés dans le repo

Deux JSON sous `docker/grafana/provisioning/dashboards/` + provider `file` (dossier
Grafana « StreamPulse », non éditables en UI — la vérité vit dans git) :

- **API Backend** (`streampulse-api`) : RPS, taux 5xx, latences p50/p95/p99, RPS par
  route, erreurs 4xx/5xx.
- **Infrastructure** (`streampulse-infra`) : CPU et RAM machine (node_exporter),
  goroutines et heap de l'API.

## Conséquences

- Aucune synchronisation à maintenir : une nouvelle route dans `main.go` est
  labellisée automatiquement par son pattern de routage.
- STR-166 (panel Live Streaming) ajoutera ses métriques custom (`streams_active_total`,
  `listeners_connected`) au même registre ; STR-167 branchera les alertes sur
  `http_requests_total`.
- STR-164 (OTEL) s'insérera dans la même chaîne middleware sans toucher à `Metrics`.
