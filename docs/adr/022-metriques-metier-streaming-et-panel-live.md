# ADR 022 — Métriques métier du streaming et panel Live

**Date** : 2026-07-26
**Statut** : Accepté
**Ticket** : [STR-166](https://linear.app/streampulse/issue/STR-166) (sous-issues [STR-184](https://linear.app/streampulse/issue/STR-184), [STR-185](https://linear.app/streampulse/issue/STR-185), [STR-186](https://linear.app/streampulse/issue/STR-186))

---

## Contexte

US-07-04, dernière US de l'épic Observabilité. Les métriques HTTP génériques
(ADR 019) mesurent l'API sans rien savoir du métier : elles ignorent combien de
flux sont en direct et ne distinguent pas un flux d'un autre (le label `path` est
volontairement agrégé au pattern de route). Le panel Live demande des données par
flux, « réelles, pas des fixtures ».

## Décision

### 1. N'ajouter que ce qui n'est pas dérivable

Deux des quatre demandes du ticket sont **déjà couvertes** par l'ADR 019 : la
latence HLS p95 et le taux d'erreurs se lisent dans
`http_request_duration_seconds` et `http_requests_total` filtrés sur les paths
HLS. Le dashboard les réutilise plutôt que de créer un second histogramme —
une seule source, pas de divergence possible.

Deux métriques sont ajoutées :

| Métrique | Type | Labels |
|---|---|---|
| `streampulse_live_streams_active` | gauge | — |
| `streampulse_hls_requests_total` | counter | `stream_id`, `kind` (playlist\|segment), `status` |

### 2. Auditeurs : estimation par le débit de requêtes

HLS n'a pas de connexion persistante — un auditeur est une suite de `GET` de la
playlist, un par segment (~10 s). Aucune gauge ne peut donc « compter les
connectés » :

- un **tracker avec TTL** côté Go supposerait d'identifier le client (IP+UA :
  le NAT fusionne plusieurs auditeurs, un changement de réseau en invente) et
  ajouterait un état à purger ;
- les **abonnés SSE** seraient exacts mais ne mesurent rien d'utile : le client
  mobile n'ouvre pas `/events`.

Retenu : `rate(streampulse_hls_requests_total{kind="playlist",status="200"}[2m]) × 10`,
soit le débit de requêtes multiplié par la durée cible d'un segment. Le panel
est explicitement titré « estimé » et sa description porte la méthode. Un
comptage exact ne se justifierait que pour de la facturation ou des quotas.

### 3. Cardinalité de `stream_id` : bornée par l'oubli, pas par l'absence

Le « par flux » du ticket impose un label à valeurs non bornées dans l'absolu.
La croissance est contenue en supprimant les séries d'un flux à son arrêt
(`ForgetStream` → `DeletePartialMatch`), sur **tous** les chemins de sortie :
`Stop` (arrêt explicite), `reap` (ffmpeg meurt seul) et `StopAll` (arrêt du
serveur). La cardinalité *active* suit donc le nombre de directs simultanés —
une poignée de séries — et le label reste cantonné à cette seule famille.

### 4. Architecture : interface étroite pour les événements, GaugeFunc pour l'état

- Le domaine `internal/streaming` déclare `MetricsRecorder`
  (`RecordHLSRequest`, `ForgetStream`) et ignore Prometheus ; l'implémentation
  `StreamingMetrics` vit dans `internal/observability` et est injectée par
  `main.go` — même schéma ISP que `admin.LiveStopper`. Un `noopRecorder` est
  posé par défaut : le domaine tourne sans observabilité (tests, binaires nus).
- Les flux actifs sont un **état**, pas un événement : `RegisterLiveStreamsGauge`
  branche un `GaugeFunc` sur `LiveSessions.ActiveCount()`, lu à chaque scrape.
  La gauge ne peut pas diverger de la réalité, y compris si une session meurt
  par un chemin imprévu — contrairement à un compteur incrémenté/décrémenté.
- L'injection passe par `SetMetrics` plutôt que par le constructeur :
  `NewHandler` a 47 sites d'appel, et l'observabilité est optionnelle par
  construction.

### 5. Status réel des lectures HLS

`http.ServeFile` écrit l'en-tête lui-même : le handler ne connaîtrait pas le
code rendu. Un `hlsStatusRecorder` (même principe que le `statusRecorder` des
middlewares) le capture pour le label `status`, ce qui rend le taux d'erreurs
`.ts` fidèle — 404 de fenêtre glissante et 503 de capacité (STR-88) inclus.

## Conséquences

- Le dashboard « Live Streaming » complète les trois autres ; l'épic
  Observabilité est clos (logs ADR 018, métriques ADR 019, traces ADR 020,
  alertes ADR 021, métier ADR 022).
- Une alerte sur le taux d'erreurs `.ts` ou sur l'absence de flux pourrait être
  ajoutée au groupe `streampulse-critiques` (ADR 021) sans nouveau socle.
- Si un comptage exact des auditeurs devient nécessaire, il remplacera
  l'estimation sans toucher au reste : seul le panel change de requête.
