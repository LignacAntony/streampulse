# ADR 021 — Alertes Grafana provisionnées, notification par email

**Date** : 2026-07-24
**Statut** : Accepté
**Ticket** : [STR-167](https://linear.app/streampulse/issue/STR-167) (sous-issues [STR-187](https://linear.app/streampulse/issue/STR-187), [STR-188](https://linear.app/streampulse/issue/STR-188), [STR-189](https://linear.app/streampulse/issue/STR-189), [STR-190](https://linear.app/streampulse/issue/STR-190))

---

## Contexte

US-07-05, dernier volet de l'épic Observabilité : logs consultables dans un dashboard
dédié et alertes proactives sur les seuils critiques. Tout le socle existe — logs JSON
labellisés dans Loki (ADR 018), `http_requests_total` et node_exporter (ADR 019),
`trace_id` dans les logs et corrélation Tempo (ADR 020).

## Décision

### 1. Alerting as-code : provisioning YAML, pas de configuration UI

`docker/grafana/provisioning/alerting/` — `contactpoints.yml`, `policies.yml`,
`rules.yml` (groupe `streampulse-critiques`, folder StreamPulse, évaluation 1 min,
`for: 5m`). Même principe que les dashboards (ADR 019) : la vérité vit dans git, l'UI
est en lecture seule sur ces objets.

### 2. Trois règles

| Règle | Expression | Seuil |
|---|---|---|
| Taux 5xx | `(sum(rate(http_requests_total{status=~"5.."}[5m])) or vector(0)) / sum(rate(...))` | > 5 % (ticket) |
| CPU machine | `1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))` | > 90 % (ticket) |
| Goroutines API | `go_goroutines{job="api"}` | > 200 |

Le seuil goroutines n'était pas fixé par le ticket : baseline ~15 au repos, pic
légitime < 100 avec 50 auditeurs (STR-90) — 200 = marge ×4 sous la fuite franche.
`noDataState: OK` sur la règle 5xx (`vector(0)` garantit une valeur) ; `NoData` sur
les deux autres (une cible qui disparaît mérite un signal).

### 3. Notification : email via le SMTP déjà présent dans le projet

Canal retenu : email — seul canal branchable sur l'infra existante ET testable en
local. En dev, `GF_SMTP_HOST=mailpit:1025` : les alertes arrivent dans Mailpit
(http://localhost:8025), aucune sortie réseau. En prod, les mêmes variables `SMTP_*`
que l'API alimentent `GF_SMTP_*` (relay réel). Contact point `equipe-streampulse`
(email), politique racine groupée par `alertname` avec `repeat_interval: 4h`
(anti-bruit). Slack/webhook : rien d'existant côté projet, écarté.

### 4. Dashboard « Logs & Erreurs » (Panel 4)

`logs-erreurs.json` : panel logs Loki piloté par deux variables — `$level`
(all/info/warn/error) et `$trace_id` (textbox, filtre par sous-chaîne) — plus stat
5xx/s, compteur d'erreurs 5 min, volume par niveau, et un panel « dernières erreurs »
dont chaque ligne ouvre la trace Tempo via le bouton TraceID (`derivedFields`,
ADR 020). Critère « filtrable par niveau et par trace_id » couvert.

### 5. Preuve de déclenchement (STR-190)

Scénario E2E documenté et rejoué sur stack isolée : arrêt de postgres, trafic sur
`/api/streams` → 100 % de 5xx → la règle passe `pending` puis `firing` après les
5 min de `for`, et l'email d'alerte est vérifié dans Mailpit via son API. Aucune
route de test ni seuil trafiqué.

## Conséquences

- Toute nouvelle alerte = une entrée dans `rules.yml`, revue en PR comme du code.
- Le `repeat_interval` de 4 h borne le volume d'emails d'une alerte persistante.
- STR-166 (panel Live Streaming) pourra alerter sur ses métriques custom dans le
  même groupe.
- En prod, les emails partent dès que les `SMTP_*` du `.env` VPS sont renseignés —
  aucune action Grafana manuelle.
