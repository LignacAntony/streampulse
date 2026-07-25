# ADR 018 — Logs structurés JSON (zerolog) et collecte Loki via Alloy

**Date** : 2026-07-21
**Statut** : Accepté
**Ticket** : [STR-163](https://linear.app/streampulse/issue/STR-163) (sous-issues [STR-168](https://linear.app/streampulse/issue/STR-168), [STR-169](https://linear.app/streampulse/issue/STR-169), [STR-170](https://linear.app/streampulse/issue/STR-170), [STR-171](https://linear.app/streampulse/issue/STR-171), [STR-172](https://linear.app/streampulse/issue/STR-172))

---

## Contexte

US-07-01 : jusqu'ici le backend loggue via la stdlib `log` (`log.Printf`, texte libre non
structuré). Loki tourne dans la stack Docker depuis l'ADR 001 et Grafana a sa datasource
provisionnée — mais rien ne collecte les logs des conteneurs, et du texte libre serait de
toute façon inexploitable en requête. STR-163 pose la fondation de l'épic Observabilité :
tous les logs deviennent du JSON structuré, requêtable dans Loki, corrélé par requête.

Les US suivantes de l'épic s'appuient dessus : STR-164 (traces OTEL) réutilisera le
middleware pour injecter `trace_id`, STR-165 (métriques Prometheus) le même point de
branchement middleware, STR-167 (dashboard Logs & Erreurs + alertes) les labels Loki posés
ici.

## Décision

### 1. zerolog plutôt que zap ou slog

- **zerolog** : API chaînée (`log.Info().Str("k", "v").Msg(...)`), zéro allocation,
  `ConsoleWriter` lisible pour le dev local. Retenu.
- **zap** : équivalent en performance, config plus lourde, deux APIs (Logger/SugaredLogger).
- **slog** (stdlib) : zéro dépendance mais ergonomie inférieure pour les champs contextuels,
  pas de sortie console dev native. La philosophie stdlib du projet (net/http, tests sans
  testify) vise à éviter les *frameworks* — une dépendance ciblée qui paie (pgx, sqlc,
  viper) reste conforme.

### 2. `request_id` maintenant, `trace_id` avec OTEL (STR-164)

Le critère d'acceptation demande un champ `trace_id`, mais le tracing OTEL est l'objet de
STR-164 (bloquée par la présente US). Un `trace_id` maison polluerait la corrélation
logs ↔ traces déjà provisionnée dans Grafana (liens vers des traces Tempo inexistantes).

- Le middleware génère un **`request_id`** (8 octets `crypto/rand` → 16 hex) par requête,
  respecte un `X-Request-ID` entrant bien formé (`^[A-Za-z0-9-]{8,64}$`, anti-injection),
  et le renvoie dans la réponse.
- STR-164 ajoutera le vrai `trace_id` W3C au même endroit.

### 3. Architecture : logger global + logger de contexte (pattern zerolog)

L'injection stricte (un `zerolog.Logger` dans chaque constructeur) toucherait toutes les
signatures pour un gain de testabilité quasi nul — le logging est un *cross-cutting
concern*. À l'inverse :

- `internal/observability.New(cfg, w)` construit le logger racine (champs `service`,
  `environment`, timestamp RFC3339 ms), posé une fois en global (`log.Logger`) dans
  `main.go`. Il devient aussi `zerolog.DefaultContextLogger` — un contexte sans logger
  attaché retombe dessus au lieu du logger désactivé de zerolog (aucun log perdu).
- Le middleware `httpmw.AccessLog` attache au contexte de chaque requête un logger enrichi
  du `request_id`. Tout code disposant d'un `ctx` loggue corrélé via
  `zerolog.Ctx(ctx)` — handlers, services, `httpjson.WriteError`.
- Les sites sans contexte HTTP (migrator, seeder, arrêt du serveur) utilisent le global
  `github.com/rs/zerolog/log`.

### 4. Access log : champs, niveaux, bruit

Une ligne JSON par requête terminée : `request_id`, `method`, `path`, `status`,
`duration_ms`, `bytes`, `remote_addr`, et `user_id` quand la requête est authentifiée
(hook `httpmw.RecordUserID` appelé par `auth.RequireAuth`/`OptionalAuth` — le mux Go 1.22
passant une copie de la requête aux handlers, l'identité remonte au middleware via un
réceptacle mutable posé dans le contexte).

- **Masquage** : le path passe par `httpjson.LoggablePath` (exportée à cette occasion) —
  la règle de rédaction du `stream_key` (PR #262) vit à un seul endroit.
- **Niveaux** : `5xx` (et panics, re-propagées après log) → `error`, `4xx` → `warn`,
  reste → `info`.
- **Anti-bruit** : `/health` et `/metrics` ne sont jamais loggés ; les succès HLS
  (`playlist.m3u8`, `segments/`) sortent en `debug` — 50 auditeurs génèrent ~1 requête/s
  en continu (STR-88), un niveau `info` serait inexploitable. Les erreurs HLS restent
  loggées normalement.

### 5. JSON partout, sortie console en opt-in explicite

`GO_ENV=development` ne suffit pas à basculer en sortie console : la stack compose tourne
aussi en dev, et STR-172 exige des logs JSON valides dans Loki quel que soit
l'environnement collecté.

- **`LOG_LEVEL`** (défaut `info`) : niveau minimal, validé par `config.Load`.
- **`LOG_PRETTY`** (défaut `false`) : sortie `ConsoleWriter` lisible, réservée au
  `go run` local hors Docker. Volontairement absent du `docker-compose.yml`.

### 6. Collecte : Grafana Alloy (Promtail est EOL)

- **Promtail** : EOL depuis mars 2026 — l'adopter aujourd'hui serait une dette immédiate.
- **Driver Docker loki** : plugin à installer sur chaque hôte, couple la disponibilité des
  logs de tous les conteneurs à celle de Loki.
- **Push applicatif direct** : couplerait l'app à l'infra de logs, contraire au 12-Factor
  (ADR 004) — les logs restent un flux stdout.
- **Alloy** (successeur officiel) : retenu. Service `grafana/alloy` dans la stack,
  socket Docker monté en lecture seule, chaîne `discovery.docker` → `discovery.relabel`
  (labels `service` et `project` depuis les labels compose, conteneurs hors compose
  ignorés) → `loki.source.docker` → `loki.write`. L'app reste stdout-only.

Requête type dans Grafana → Explore → Loki :

```logql
{service="api"} | json | level="error"
{service="api"} | json | request_id="a1b2c3d4e5f60718"
```

## Conséquences

- Plus aucun `log.Printf`/`fmt.Println` en production (STR-170) ; le linter n'a rien à
  imposer, la dépendance stdlib `log` a disparu du module (hors `internal/streaming` et
  `internal/admin`, purgés à la clôture de STR-192 pour éviter un conflit de branche).
- Le `LogMailer` dev loggue toujours le token de reset (comportement voulu, SMTP absent
  en dev) — désormais en JSON structuré.
- STR-164 (OTEL) enrichira le même middleware ; STR-165 (Prometheus) se branchera au même
  point de composition dans `main.go`.
- `sanitize` (suppression des retours à la ligne avant log) a disparu : l'encodage JSON
  de zerolog neutralise l'injection de logs par construction.
