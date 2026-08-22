# ADR 041 — Métriques métier : débit, départs d'auditeurs, interruptions et résumé admin

**Date** : 2026-08-20
**Statut** : Accepté
**Ticket** : [STR-244](https://linear.app/streampulse/issue/STR-244)

---

## Contexte

Le sujet énumère quatre visualisations attendues du dashboard Grafana : « utilisateurs
en ligne, **débit de streaming**, taux d'erreurs, temps de réponse API ». Il demande
aussi, dans son volet observabilité, de savoir « différencier les erreurs 500
(techniques) du nombre de **déconnexions brutales d'utilisateurs** (métier/expérience) »
— et, sur le volet fonctionnel, que l'administrateur ait « accès aux métriques
globales ».

L'audit de conformité a relevé six écarts, tous vérifiés dans le code :

| # | Écart | État avant |
| -- | -- | -- |
| 1 | Aucune métrique d'octets | `httpmw/metrics.go` ne déclarait que `http_requests_total` et `http_request_duration_seconds` |
| 2 | Aucune métrique de déconnexion | rien côté auditeur, rien côté diffuseur |
| 3 | Aucune séparation métier/technique **sur un** dashboard | `grep '"type": "row"'` sur les 4 dashboards → 0 |
| 4 | Aucune alerte métier | les 4 règles portaient sur 5xx, CPU, goroutines, `up` |
| 5 | Aucune trace émise depuis le mobile | `grep -r traceparent mobile/` → 0 |
| 6 | Le rôle admin ne donnait accès à aucune métrique | `/metrics` monté sans `RequireAuth`, aucune route `/api/admin/metrics` |

S'y ajoutait un défaut d'exploitation non listé par le sujet mais découvert au même
endroit : le stderr du ffmpeg de segmentation partait en texte brut
(`hls.go` : `cmd.Stderr = os.Stderr`), donc **invisible** dans les panneaux Grafana
qui filtrent tous avec `| json`. Une erreur ffmpeg pendant une diffusion ne pouvait
pas être vue.

---

## 1. Débit : publier un compteur qui existait déjà

`statusRecorder` (`httpmw/logging.go`) comptait déjà les octets écrits — pour l'access
log seulement. Le `Metrics` middleware construit son propre `statusRecorder` sur le
même chemin. Il ne manquait donc que la publication :

```go
responseBytes := promauto.With(reg).NewCounterVec(prometheus.CounterOpts{
    Name: "http_response_bytes_total",
    Help: "Octets de corps de réponse HTTP écrits vers les clients.",
}, []string{"path"})
```

**Un seul label `path`.** La question posée est « quelle route transporte les octets »
— en pratique, les segments `.ts`. Grouper aussi par méthode multiplierait les séries
pour une dimension que personne n'interroge : le débit d'un GET et celui d'un POST sur
la même route ne se comparent pas, ils s'additionnent.

**`Add` et non `Inc`** : c'est un volume, pas un événement. Une réponse vide (204, 304)
ajoute zéro mais crée quand même la série, ce qui vaut mieux qu'un trou dans le graphe.

**Les routes de longue durée sont comptées.** Elles sont exclues de l'histogramme de
latence (une observation de plusieurs minutes fausserait les centiles, ADR 019) mais
ce sont justement elles qui portent le volume : les exclure aussi du compteur d'octets
viderait la métrique de son objet.

### Ce que ce compteur ne mesure pas

Le sens **entrant** — le push audio du diffuseur — traverse `r.Body`, que ce middleware
n'enveloppe pas. Il n'est donc pas compté. C'est un choix : envelopper le corps de
requête impose un lecteur intermédiaire sur le chemin d'ingest, pour mesurer un débit
d'environ 128 kbit/s par diffuseur qu'on connaît déjà par construction. Le débit qui
varie, qui sature et qu'un jury veut voir, c'est celui qui part vers les auditeurs.
La description du panneau le dit.

---

## 2. Départs d'auditeurs : nommer ce que la mesure permet

Le sujet parle de « déconnexions brutales ». HLS ne permet pas de les observer.

Il n'y a pas de connexion persistante : un lecteur demande le manifeste, puis les
segments, et **rien ne signale son départ**. L'audience est déjà une estimation
(ADR 025) : un client compte comme présent tant qu'il a demandé le manifeste dans les
30 dernières secondes. Un auditeur qui ferme proprement son lecteur et un auditeur dont
le réseau tombe expirent donc **exactement de la même façon**.

La métrique s'appelle en conséquence `streampulse_listener_departures_total`, et pas
`disconnections`. Prétendre distinguer le brutal du volontaire serait affirmer une
information que le protocole ne porte pas — et un jury qui pose la question obtiendrait
une réponse fausse.

**Ce qui n'est pas compté.** L'arrêt d'un flux détruit sa `map` d'auditeurs sans passer
par `pruneListeners`. Les auditeurs d'une diffusion qui se termine normalement ne sont
donc jamais comptés comme des départs — sinon le compteur monterait à chaque fin de
diffusion réussie, exactement le signal qu'il est censé ne pas donner.

### Le balayage périodique

`pruneListeners` n'était appelé que par `stats()`, lui-même appelé par
`GET /api/streams/{id}/stats` — donc uniquement pendant qu'un diffuseur regarde son
tableau de bord. Un compteur alimenté par cette voie n'aurait avancé que lorsqu'on
l'observait : **une métrique dont la valeur dépend de qui la regarde**.

D'où `LiveSessions.StartListenerSweep(done, 30s)`, sur le modèle de
`httpmw.RateLimit.StartEviction` déjà en place. Effet de bord bienvenu : une diffusion
abandonnée cesse d'afficher ses derniers auditeurs, même si personne ne consulte ses
statistiques.

La purge reste **hors** du chemin chaud : `touchListener` demeure O(1) et ne balaie que
lorsque le plafond de 10 000 auditeurs suivis est atteint. `TouchListener` ne prend le
verrou du registre pour publier une métrique que si `departed > 0` — le cas courant ne
paie rien de plus qu'avant.

---

## 3. Interruptions de diffusion : une seule famille, deux causes

`streampulse_stream_interruptions_total{reason}` compte les diffusions terminées
**autrement que par un arrêt volontaire du diffuseur** :

| `reason` | Cause | Qui doit agir |
| -- | -- | -- |
| `ingest_timeout` | Plus aucun push audio pendant le délai de grâce | Le diffuseur (réseau, application fermée) |
| `segmenter_failed` | ffmpeg s'est arrêté seul | Nous (panne serveur) |

Les deux comptent comme une écoute perdue ; une seule appelle une intervention sur
l'infrastructure. C'est ce qui justifie le label plutôt que deux compteurs distincts —
et la table de valeurs est **close**, aucune chaîne extérieure ne peut créer de série.

La métrique est posée **avant** l'appel au handler qui termine l'état persistant : à
ce point la diffusion est perdue quoi qu'il advienne de l'écriture en base, et c'est
cette perte — pas son enregistrement — que la métrique décrit.

### Pourquoi ni l'une ni l'autre ne porte de `stream_id`

`streampulse_hls_requests_total` est aujourd'hui la **seule** famille labellisée par
flux, et l'ADR 022 a dû lui adjoindre tout un mécanisme de purge (`ForgetStream`, plus
un second effacement différé pour les requêtes encore en vol) sans lequel la cardinalité
croîtrait à chaque diffusion.

Ajouter un second porteur de ce label doublerait cette surface fragile pour une vue
qu'on a déjà : le détail par diffusion se lit sur la famille existante. Les deux
nouveaux compteurs restent donc globaux.

---

## 4. Séparer métier et technique sur un dashboard

La séparation existait, mais **entre** dashboards — alors que le sujet demande de
différencier « sur un dashboard ». Les deux dashboards principaux gagnent donc deux
rows chacun :

- **Live Streaming** : « Métier — audience et continuité des diffusions » (flux,
  auditeurs, débit, départs, interruptions) puis « Technique — santé du service HLS »
  (latence, codes d'erreur, rejets de capacité).
- **API Backend** : « Métier — usage de l'API » (requêtes, débit, activité
  authentifiée) puis « Technique — santé du service » (5xx, centiles, erreurs).

Les quatre dashboards gagnent des `links` croisés avec `keepTime: true` : passer de
l'un à l'autre conserve la fenêtre temporelle, sans quoi on compare deux périodes
différentes en croyant comparer deux services.

### Un panneau renommé plutôt que sur-promis

Le sujet demande « utilisateurs en ligne ». L'API est **sans état** — JWT, aucune table
de sessions — et un label `user_id` serait de cardinalité non bornée : le registre ne
peut pas compter des individus. Le panneau correspondant s'appelle donc « Activité
authentifiée » et mesure ce qu'il mesure, un débit de requêtes sur les routes
authentifiées. Le volet « qui est là » est porté par l'audience estimée du dashboard
Live Streaming et par la population de comptes de `GET /api/admin/metrics`.

---

## 5. Alertes métier

Les quatre règles existantes ne se déclenchent pas si la plateforme sert parfaitement
des 200 à personne. Deux règles rejoignent un groupe `streampulse-metier` séparé —
séparé parce que l'intervalle d'évaluation est porté par le groupe, et qu'une
interruption de diffusion se constate à la minute quand un pic de CPU se juge sur une
fenêtre :

- **Segmenteur HLS arrêté seul** — `reason="segmenter_failed"` **uniquement**, et
  `for: 0m` contrairement aux règles techniques. L'événement est ponctuel et déjà
  consommé quand on le lit : exiger qu'il « dure » cinq minutes reviendrait à exiger
  qu'une seconde diffusion tombe pour être prévenu de la première. `noDataState: OK` —
  tant qu'aucun segmenteur n'est mort, la série n'existe pas, et c'est le cas nominal.

  > **Corrigé en revue (PR #328).** La règle portait d'abord sur les deux causes. Or
  > cette ADR distingue `ingest_timeout` et `segmenter_failed` précisément parce
  > qu'elles n'appellent pas la même intervention — puis alertait sur les deux, ce qui
  > était incohérent avec son propre raisonnement. Côté diffuseur, fermer l'application
  > ou sortir de couverture produit un `ingest_timeout` identique à une perte réseau :
  > sur une plateforme au churn normal, l'alerte serait presque toujours active et
  > noierait le seul cas actionnable. `ingest_timeout` reste compté et visible sur le
  > dashboard — mesurer n'oblige pas à réveiller quelqu'un.
- **Segments HLS en échec > 5 %** — ce que cela vaut côté auditeur : de l'audio qui se
  coupe. Garde de trafic minimal (0,2 segment/s), sinon un unique 404 sur une diffusion
  sans public suffirait à alerter.

### L'adresse de destination

`contactpoints.yml` portait `admin@streampulse.dev` **codé en dur** : un domaine
placeholder que le projet ne possède pas. Une alerte envoyée à un domaine qu'on ne
contrôle pas ne prévient personne — et s'il venait à exister, elle préviendrait
quelqu'un d'autre.

L'adresse vient désormais de l'environnement (`$ALERT_EMAIL_TO`). Grafana documente
explicitement l'interpolation dans le provisioning d'alerting — « Provisioning
interpolates environment variables using the `$variable` syntax », avec un exemple de
contact point email. Forme sans accolades : `${VAR}` déclenche une double expansion si
la valeur contient elle-même un `$`. ⚠️ L'interpolation ne s'applique **pas** aux
annotations de règles d'alerte ; les nôtres n'en contiennent aucune (vérifié : aucun
`$` dans `rules.yml`).

Le défaut vise `.invalid`, TLD réservé par la RFC 2606 : non délivrable par
construction, donc jamais adressé à un tiers par accident. En développement, tout part
dans Mailpit quelle que soit l'adresse.

⚠️ **La variable doit être câblée dans l'environnement du process Grafana**, pas
seulement dans le `.env` : c'est le provisioning de Grafana qui interpole, depuis son
propre environnement. Elle est donc passée explicitement dans les deux fichiers compose —
avec un défaut en développement, et **sans défaut** en production, où son absence fait
échouer le démarrage plutôt que de router les alertes vers le vide.

---

## 6. `GET /api/admin/metrics` : lire le registre local, pas Prometheus

Le sujet veut que le rôle admin ait accès aux métriques globales. Aujourd'hui elles ne
sont lisibles que dans Grafana, derrière une authentification séparée et sans rapport
avec le rôle applicatif.

La route rend un JSON : durée de fonctionnement, flux en direct et audience estimée,
compteurs HTTP, population de comptes.

**Source : le registre Prometheus du process lui-même**, via `prometheus.Gatherer` —
pas une requête au serveur Prometheus. Interroger Prometheus ferait de lui non plus un
observateur mais une **dépendance** : sa panne ferait tomber une route applicative, et
le déploiement gagnerait une URL de plus à configurer.

Le prix est réel et doit être dit : le registre ne conserve pas d'historique, seulement
la valeur courante de chaque compteur. Ce que rend cette route sont des **cumuls depuis
le démarrage du process**, pas des taux glissants. Les champs le disent dans leur nom
(`requests_total`, `server_error_rate` « depuis le boot ») et la spec OpenAPI le
répète. Grafana reste l'endroit où lire une évolution dans le temps.

### Deux détails qui ne sont pas cosmétiques

**Le taux vaut 0 et non NaN quand aucune requête n'a été servie.** `encoding/json` rend
une erreur sur un NaN : le résumé entier échouerait au démarrage du process, précisément
quand un admin le consulte pour vérifier que tout est reparti.

**Un volet indisponible ne fait pas échouer le résumé.** Une erreur de collecte est
journalisée en `warn` et laisse le volet HTTP à zéro ; les flux, l'audience et les
comptes sont servis. Le résumé est une vue de supervision, pas une transaction. Seule
une base injoignable fait échouer la route — dans ce cas plus aucun volet n'est fiable.

**Le domaine ne connaît pas Prometheus.** `admin.HTTPCounters` et `admin.HTTPTotals`
sont déclarés dans le domaine ; `observability.HTTPStats` connaît Prometheus ; un
adaptateur de huit lignes dans `main.go` les relie. Sans lui, l'un des deux devrait
importer l'autre : soit du Prometheus dans un domaine métier, soit un domaine métier
dans l'infrastructure. Même règle que `streaming.MetricsRecorder` (ADR 022).

---

## 7. Trace depuis le mobile

Le backend acceptait déjà l'en-tête entrant : propagateur `TraceContext`,
échantillonneur `ParentBased(AlwaysSample)` (`observability/tracer.go`). Il ne manquait
que l'émetteur.

`TraceContext` (`mobile/lib/core/network/trace_context.dart`) est un objet **pur**,
sans dépendance à Dio ni à Flutter — comme `InterruptionPolicy` (ADR 033) et
`PlaybackOrder` (ADR 035) : la génération d'identifiants se teste sans réseau. Un
intercepteur Dio pose l'en-tête sur chaque requête sortante.

**Placé avant l'intercepteur d'authentification** : une requête rejouée après un 401
doit repartir avec un identifiant neuf plutôt que celui de la tentative qui a échoué.
Le Dio dédié au refresh en reçoit un aussi — c'est un appel réseau qui peut être lent,
et c'est justement celui qu'on cherche quand une requête paraît avoir mis deux fois
trop de temps.

**Échantillonnage à 100 % par défaut.** Le backend suit le drapeau du parent : c'est ce
réglage qui rend une trace mobile visible dans Tempo. Assumé pour ce projet — le volume
est celui d'une démonstration, et une trace échantillonnée au hasard est inexploitable
quand on cherche précisément la requête qu'on vient de faire. Réductible sans toucher
au code : `--dart-define=TRACE_SAMPLED=false`.

### Ce que la trace mobile ne couvre pas

**La lecture audio.** just_audio ouvre ses propres connexions HTTP, hors de Dio — la
même raison qui oblige à lui passer l'en-tête `Authorization` séparément (ADR 034 §4).
Les segments HLS et les binaires de pistes ne portent donc pas de trace. C'est le trajet
le plus intéressant en volume, et il reste hors couverture.

---

## 8. stderr ffmpeg vers zerolog

`hls.go` écrivait le stderr de ffmpeg directement sur celui du conteneur. Alloy
transmettait ces lignes telles quelles à Loki, où **tous** les panneaux du dashboard
« Logs & Erreurs » filtrent avec `| json` — elles étaient donc écartées en
`JSONParserErr`. Une erreur ffmpeg pendant une diffusion était invisible dans Grafana.

Le transcodeur d'ingest résolvait déjà le même problème avec un `tailBuffer`
(`transcode.go`), qui convient à un process court dont on lit la fin après coup. Le
segmenteur, lui, vit toute la diffusion : ses erreurs doivent apparaître quand elles
surviennent. D'où `ffmpegLogWriter`, qui émet une ligne de log JSON par ligne de
stderr, étiquetée `stream_id` et `component="ffmpeg-hls"`.

**Niveau `warn` et non `error`.** ffmpeg écrit sur ce flux des avertissements bénins
(paquets non monotones, ré-horodatage) aussi bien que des erreurs fatales, sans les
distinguer dans un format exploitable. Les faire toutes passer en `error` déclencherait
l'alerte 5xx sur du bruit ; `warn` les rend cherchables sans mentir sur leur gravité.

**Le reliquat est vidé à la fermeture.** os/exec n'appelle `Write` que depuis la
goroutine de recopie qu'il crée pour un `Stderr` non-`*os.File`, et `cmd.Wait()`
l'attend : aucun accès concurrent, donc pas de verrou. Une dernière ligne sans saut de
ligne final serait perdue sans le `flush()` appelé après `<-s.done`. Le tampon est borné
à 4 Ko : un ffmpeg qui n'émettrait jamais de saut de ligne ne peut pas faire grandir la
mémoire sans fin.

---

## Conséquences

**Positives**

- Le débit de streaming est mesuré là où il compte, pour le coût d'une ligne : le
  compteur d'octets existait déjà.
- Les incidents vécus par les auditeurs (départs, interruptions) sont comptés et
  alertés, séparément des 5xx techniques — sur le même dashboard.
- Une erreur ffmpeg en cours de diffusion est désormais visible dans Grafana.
- Une trace démarre depuis le mobile pour tout ce qui passe par Dio.
- L'admin obtient des métriques par son rôle applicatif, sans compte Grafana.
- Aucune dépendance réseau ajoutée à une route applicative.

**Négatives, assumées**

- Les « départs d'auditeurs » ne distinguent pas la fermeture volontaire de la coupure
  réseau. HLS ne le permet pas ; la métrique est nommée en conséquence.
- Le débit d'ingest (diffuseur → serveur) n'est pas mesuré.
- Le résumé admin rend des cumuls depuis le boot, pas des taux glissants.
- La lecture audio (just_audio) reste hors du périmètre de tracing.
- Un balayage périodique de plus tourne dans le process, toutes les 30 s.
- En production, un déploiement sans `ALERT_EMAIL_TO` **refuse de démarrer**
  (`${ALERT_EMAIL_TO:?…}` dans `docker-compose.prod.yml`). C'est délibéré : la première
  version omettait la variable côté prod, si bien que `$ALERT_EMAIL_TO` s'y expansait en
  chaîne vide et que **toutes** les alertes partaient nulle part — pire que l'adresse en
  dur qu'elle remplaçait, qui produisait au moins une enveloppe délivrable (revue
  PR #328). Un déploiement qui ne sait pas à qui adresser ses alertes doit s'arrêter,
  pas démarrer en silence.

---

## Alternatives écartées

**Compter les octets entrants en enveloppant `r.Body`.** Donnerait le débit d'ingest.
Écarté : impose un lecteur intermédiaire sur le chemin chaud du push audio pour mesurer
un débit qu'on connaît par construction (~128 kbit/s par diffuseur). Le débit qui varie
et qui sature est celui qui sort.

**Labelliser les départs et les interruptions par `stream_id`.** Donnerait le détail par
diffusion. Écarté : doublerait la surface de purge que l'ADR 022 a mise en place pour
borner la cardinalité, alors que ce détail est déjà lisible sur
`streampulse_hls_requests_total`.

**Faire interroger Prometheus par `GET /api/admin/metrics`.** Donnerait de vrais taux
glissants, identiques à ceux de Grafana. Écarté : transforme un observateur en
dépendance — la panne du serveur de métriques ferait tomber une route applicative.

**Purger les auditeurs expirés dans `touchListener`.** Supprimerait le balayage
périodique. Écarté pour la raison déjà donnée en ADR 025 : la purge coûte un balayage
de toute la map et sérialiserait derrière le mutex de session toutes les requêtes
concurrentes d'un flux très suivi.

**Un compteur par raison d'interruption plutôt qu'un label.** Écarté : la table de
valeurs est close et courte ; un label garde les deux causes comparables sur un même
graphe et une même alerte.

**Un SDK OpenTelemetry complet côté Flutter.** Donnerait de vrais spans clients, avec
durées mesurées sur l'appareil. Écarté : le paquet Dart n'est pas stable, il faudrait
un second exportateur OTLP à configurer et à sécuriser depuis l'extérieur du réseau,
pour un gain qui reste hors du critère demandé — celui-ci porte sur la **continuité**
de la trace, que l'en-tête suffit à établir.

---

## Références

- [ADR 019 — Métriques Prometheus](019-metriques-prometheus-cardinalite-et-dashboards.md) — familles HTTP existantes, règle du label `path`
- [ADR 020 — Traces OpenTelemetry](020-traces-opentelemetry-otlp-tempo.md) — propagateur et échantillonneur côté serveur
- [ADR 021 — Alertes Grafana](021-alertes-grafana-provisionnees-email.md) — contact point, policy, format des règles
- [ADR 022 — Métriques métier du streaming](022-metriques-metier-streaming-et-panel-live.md) — `MetricsRecorder`, purge de cardinalité
- [ADR 025 — Statistiques d'audience](025-statistiques-daudience-en-temps-reel.md) — pourquoi l'audience est une estimation
- [ADR 015 — Moteur HLS](015-moteur-hls-segmentation-ffmpeg.md) — cycle de vie du segmenteur
