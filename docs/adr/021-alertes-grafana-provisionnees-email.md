# ADR 021 — Alertes Grafana provisionnées, notification par email

**Date** : 2026-07-24
**Statut** : Accepté — **amendée le 2026-09-02** (ajout d'un canal Discord, cf. § 3 bis)
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
| Taux 5xx | ratio 5xx/total **`and sum(rate(http_requests_total[5m])) > 0.1`** | > 5 % (ticket) |
| CPU machine | `1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))` | > 90 % (ticket) |
| Goroutines API | `go_goroutines{job="api"}` | > 200 |
| API injoignable | `up{job="api"}` | < 1, `for: 2m` |

**Plancher de trafic** (ajouté en revue) : le ratio seul déclenche à 100 % dès
qu'une unique requête échoue sur une fenêtre creuse. La condition n'est évaluée
qu'au-dessus de 0,1 req/s (~30 requêtes sur 5 min), volume à partir duquel 5 %
est statistiquement parlant.

**Panne totale** (ajoutée en revue) : si l'API tombe, plus aucune requête n'est
comptée — la série devient stale, le ratio 5xx repasse en `NoData` et la règle
reste verte pendant l'indisponibilité. `up{job="api"} == 0` couvre ce cas que le
ratio ne peut structurellement pas détecter ; `for: 2m` (un redémarrage de
déploiement prend ~30 s) et `noDataState: Alerting` (la cible qui disparaît de
Prometheus est elle-même un incident).

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

### 3 bis. Ajout d'un canal Discord (amendement du 2026-09-02)

Cette ADR écartait Discord parce qu'il « suppose un espace de travail partagé que
le projet n'a pas ». **La prémisse a changé** : l'équipe s'est dotée d'un Discord.
La décision n'est donc pas renversée — une alternative écartée est devenue
disponible, et on l'ajoute.

Ce que l'usage a montré entre-temps, et qui rend l'ajout nécessaire plutôt que
confortable : **l'email n'a jamais eu de destinataire réel.** Son défaut est une
adresse en `.invalid`, non délivrable par construction, et le déploiement
Kubernetes ne passait même pas la variable — relevé le 2026-09-02,
`ALERT_EMAIL_TO` y était vide. Une alerte qui se serait déclenchée sur ce cluster
n'aurait prévenu personne.

**Second receiver dans le même contact point**, pas un second contact point : la
politique de notification route vers un contact point, pas vers un type. Les deux
canaux sont donc notifiés sans toucher à `policies.yml`.

**L'email est conservé.** Il reste le canal garanti — celui qui fonctionne sans
secret à provisionner — et Mailpit garde sa valeur de démonstration locale. Un
canal de notification ne doit pas dépendre d'une URL que quelqu'un a pu oublier
de renseigner.

⚠️ **`ALERT_DISCORD_WEBHOOK` est volontairement facultative**, sans `:?` en
production, à la différence de `ALERT_EMAIL_TO`. Le déploiement continu lance
`docker compose pull api` sur le VPS : une variable requise mais absente y ferait
échouer le déploiement de l'**API** — vérifié, l'interpolation d'un `:?` sur le
service `grafana` suffit à faire échouer un `pull api`. Un canal de notification
ne doit pas pouvoir bloquer une mise en production.

⚠️ **« Facultative » ne veut pas dire « vide ».** Pour Grafana, l'`url` d'un
receiver `discord` est un champ secret **obligatoire** : vide, le provisioning
est rejeté à la validation (« could not find webhook url property in settings »),
et comme l'échec porte sur le module `provisioning`, **Grafana refuse de
démarrer** — mesuré : exit 1, 29 modules en échec. L'email serait tombé avec lui,
alors que le contact point partagé était justement censé le garantir.

Le défaut est donc **non vide et non routable** : une URL sur le TLD réservé
`.invalid` (RFC 2606), exactement le procédé déjà retenu pour `ALERT_EMAIL_TO`.
Non configuré, le canal échoue à l'**envoi** et non au démarrage : « dial tcp:
lookup discord.invalid : no such host », classé irrécupérable par le notifier,
donc une seule tentative et aucune rafale de reprises. Mesuré de bout en bout
(Grafana + Mailpit, alerte réelle) : **l'email part quand même, et une seule
fois** — les intégrations d'un contact point sont notifiées indépendamment.
L'absence de configuration reste visible dans Grafana → Alerting → Contact
points, ce qui vaut mieux qu'un canal silencieux qu'on croirait sain.

⚠️ Le CD ne redémarre que le service `api`. Une modification du provisioning
d'alerting **n'est pas appliquée automatiquement** : Grafana doit être redémarré
à la main sur le VPS.

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

## Alternatives écartées

**Alertmanager de Prometheus.** L'outil canonique du couple Prometheus/Alertmanager, avec un
routage plus fin (inhibition, silences, groupement par étiquette). Écarté : il ajoute un service
et une seconde interface à surveiller, alors que Grafana — déjà déployé pour les dashboards — sait
évaluer des règles et router des notifications. L'inhibition n'a pas d'usage ici avec quatre règles.

**Définir les alertes dans l'UI Grafana.** Plus rapide à écrire et à ajuster. Écarté pour la même
raison que les dashboards (ADR 019) : une règle qui ne vit que dans le volume Grafana disparaît au
premier `docker compose down -v`, n'est pas relue, et n'apparaît dans aucun diff. Le provisioning
YAML rend les seuils discutables en revue de PR.

**Notifier sur Slack ou Discord plutôt que par email.** Plus immédiat. Écarté à la
rédaction : cela supposait un espace de travail partagé que le projet n'avait pas, et un webhook
à stocker. L'email fonctionne avec le relay SMTP déjà configuré pour la réinitialisation de mot
de passe, et Mailpit le rend testable en local sans rien envoyer dehors.

> **Révisé le 2026-09-02.** L'équipe s'est dotée d'un Discord : la prémisse ne tient plus. Le
> canal est ajouté **en plus** de l'email, pas à sa place (cf. § 3 bis) — « plutôt que » était le
> mauvais cadrage, les deux ne s'excluent pas.

## Conséquences

- Toute nouvelle alerte = une entrée dans `rules.yml`, revue en PR comme du code.
- Le `repeat_interval` de 4 h borne le volume d'emails d'une alerte persistante.
- STR-166 (panel Live Streaming) pourra alerter sur ses métriques custom dans le
  même groupe.
- En prod, les emails partent dès que les `SMTP_*` du `.env` VPS sont renseignés —
  aucune action Grafana manuelle. **Limite connue** (relevée en revue) :
  `GF_SMTP_ENABLED` vaut `true` sans condition ; avec un `SMTP_HOST` vide, Grafana
  considère le SMTP actif et échoue à l'envoi en ne loggant que côté serveur — les
  alertes se déclenchent sans notifier. Un gating conditionnel est peu commode en
  Compose : la contrainte est donc documentée dans le runbook de déploiement, avec
  un test du contact point en vérification post-déploiement obligatoire.
