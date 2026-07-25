# ADR 020 — Traces OpenTelemetry : OTLP/HTTP vers Tempo, otelhttp et otelpgx

**Date** : 2026-07-23
**Statut** : Accepté
**Ticket** : [STR-164](https://linear.app/streampulse/issue/STR-164) (sous-issues [STR-173](https://linear.app/streampulse/issue/STR-173), [STR-174](https://linear.app/streampulse/issue/STR-174), [STR-175](https://linear.app/streampulse/issue/STR-175), [STR-176](https://linear.app/streampulse/issue/STR-176), [STR-177](https://linear.app/streampulse/issue/STR-177))

---

## Contexte

US-07-02 : troisième pilier de l'observabilité après les logs (ADR 018) et les
métriques (ADR 019). Tempo tourne depuis l'ADR 001 avec ses récepteurs OTLP ouverts
(gRPC 4317, HTTP 4318) et la corrélation Grafana provisionnée (`derivedFields` Loki →
Tempo, `tracesToLogsV2` Tempo → Loki) — dormante faute de traces et de `trace_id`
dans les logs.

## Décision

### 1. Export OTLP/HTTP (pas gRPC)

`otlptracehttp` vers `tempo:4318`. `OTEL_EXPORTER_OTLP_ENDPOINT` est la variable
*générique* de la spec OTLP : sa valeur est une **base** à laquelle `/v1/traces` est
ajouté. L'URL est normalisée via `net/url` (slash final, préfixe de chemin d'un
reverse proxy) puis passée à `WithEndpointURL`, qui en déduit aussi le TLS ; une URL
invalide fait échouer le démarrage plutôt que de désactiver l'export en silence
(revue de PR). Un seul service émetteur sur un réseau Docker
interne : le streaming et la compression de gRPC n'apporteraient rien, et l'arbre de
dépendances reste léger. `OTEL_EXPORTER_OTLP_ENDPOINT` **vide → provider noop** :
aucun bruit réseau en `go run` local ; le compose (dev et prod) pointe Tempo.

### 2. Échantillonnage : ParentBased(AlwaysSample)

Trafic modeste, Tempo en stockage local : tout échantillonner simplifie le debug
(« la requête qui a planté » est toujours là). Un ratio serait introduit par variable
d'environnement si le volume l'exigeait. `/health` et `/metrics` ne sont pas tracés
(filtre `skipObservability`, partagé avec logs et métriques) ; le HLS **reste tracé**
— traces courtes, chemin chaud où une latence anormale mérite une trace consultable.

**Routes de longue durée** (révisé en revue de PR) : le push d'ingest
(`/api/streams/ingest/{stream_key}`) n'est **pas** tracé — la connexion du diffuseur
tient des heures et le handler ne touche jamais la base (`AttachIngest` est 100 %
mémoire, ADR 015) : le span n'aurait aucun enfant à corréler et ne serait exporté
qu'à la fin de la diffusion. Le **SSE** (`/api/streams/{id}/events`) reste tracé
malgré sa durée : il appelle `GetStream` avant de streamer, et sans span serveur
cette requête SQL deviendrait une trace racine orpheline. Son span racine n'arrive
dans Tempo qu'à la déconnexion, mais les enfants sont exportés dès qu'ils se
terminent (`BatchSpanProcessor.OnEnd` est appelé par span, pas par trace) : la trace
reste exploitable pendant la session.

### 3. Spans HTTP : `httpmw.Tracing` (otelhttp) au-dessus d'AccessLog

Chaîne finale : `CORS(Tracing(mux, AccessLog(logger, Metrics(reg, mux))))`. Le span
racine existe quand AccessLog construit le logger de requête → chaque ligne de log
porte `trace_id`/`span_id` en plus du `request_id` (qui reste : corrélation même
sans tracing). Les spans sont nommés par le pattern de route via `mux.Handler(r)`
(« GET /api/streams/{id} ») — même mécanique et cardinalité bornée que le label des
métriques (ADR 019). Propagation W3C `traceparent` activée : un client déjà tracé
verra son contexte poursuivi.

### 4. Spans SQL : `otelpgx` sur le pool

Le ticket évoquait « otelgorm ou sqlx » — le projet est sur pgx/v5 + sqlc.
`otelpgx.NewTracer()` posé sur `poolCfg.ConnConfig.Tracer` (une ligne dans
`pool.go`) : un span par requête SQL, enfant du span HTTP via le `ctx` qui descend
déjà des handlers aux repositories. Le texte SQL est tracé **sans les arguments**
(queries sqlc paramétrées — pas de données personnelles dans les traces). La
connexion legacy du seeder n'est pas instrumentée (elle passe par `pgx.Conn`, pas
par le pool).

**Limite connue** (relevée en revue) : une requête SQL émise hors contexte HTTP
produit un span racine sans parent. Le périmètre réel est réduit —
`ReconcileLiveStreams` au démarrage (une requête, une fois par process) ; les
goroutines de session (`session.go`) ne touchent pas la base, et les actions admin
(`StopLiveForUser`) héritent du contexte HTTP de leur handler. À revoir si des jobs
de fond périodiques apparaissent : un sampler dédié éviterait d'exporter ces racines.

### 5. Resource et corrélation

`service.name = streampulse-api` (aligné sur le label des logs) +
`deployment.environment.name`. La trace complète du critère (mobile → API → DB) se
lit ainsi : requête du mobile → span serveur otelhttp → spans SQL otelpgx, visible
dans Grafana → Explore → Tempo, ou en un clic depuis un log Loki (bouton TraceID).
L'instrumentation du client Flutter (OTEL Dart, header `traceparent` sortant) est
hors du scope de ce ticket backend.

## Conséquences

- La promesse de l'ADR 018 est tenue : `trace_id` dans les logs vient du vrai span
  OTEL, la corrélation logs ↔ traces Grafana fonctionne dans les deux sens.
- STR-188 (corrélation dans les dashboards, épic 166/167) n'a plus qu'à consommer.
- Le `defer` de `main.go` flushe l'exporteur à l'arrêt (batch OTLP, timeout 5 s).
- Toute nouvelle route est automatiquement tracée et nommée par son pattern.
