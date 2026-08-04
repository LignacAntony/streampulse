# ADR 025 — Statistiques d'audience en temps réel

**Date** : 2026-08-03
**Statut** : Accepté
**Ticket** : [STR-154](https://linear.app/streampulse/issue/STR-154) (sous-issues [STR-158](https://linear.app/streampulse/issue/STR-158), [STR-160](https://linear.app/streampulse/issue/STR-160), [STR-161](https://linear.app/streampulse/issue/STR-161))

---

## Contexte

US-06-02 : le diffuseur veut voir combien de personnes l'écoutent. Le tableau de
bord livré par [ADR 024](024-tableau-de-bord-diffuseur-lancer-et-arreter-un-flux.md)
affiche l'état et la durée d'un direct, mais aucun chiffre d'audience — le
compteur avait été explicitement sorti du périmètre faute de source de données.

Deux obstacles à lever :

1. **HLS n'a pas de connexion persistante.** Un lecteur récupère un manifeste,
   puis des segments, en requêtes HTTP indépendantes. Rien ne signale son
   arrivée, rien ne signale son départ. Il n'existe donc pas de « nombre
   d'auditeurs connectés » à lire quelque part — seulement à estimer.
2. **La seule mesure existante vit dans Prometheus.**
   [ADR 022](022-metriques-metier-streaming-et-panel-live.md) dérive une
   estimation (`rate(playlist 200)[2m] × 10`) pour un panel Grafana, mais
   `/metrics` est bloqué par Caddy en production et coupler le client mobile à
   la stack d'observabilité serait une inversion de dépendance.

## Décision

### 1. Fenêtre glissante en mémoire, dans la session

Chaque session live tient une map `clientKey → dernière requête de manifeste`.
Un client compte comme auditeur tant que sa dernière requête a moins de
`listenerWindow` = **30 s**, soit trois fois la durée d'un segment
(`hlsSegmentSeconds = 10`). Un lecteur sain redemande le manifeste bien plus
souvent ; un lecteur parti sort du compte en une demi-minute.

**Seules les playlists comptent.** Les segments arrivent par rafales et
gonfleraient artificiellement le chiffre. Seules les réponses `200` comptent :
une requête refusée n'est pas un auditeur.

**La purge n'a pas lieu sur le chemin chaud.** Elle balaie toute la map, et la
déclencher à chaque manifeste sérialiserait derrière le mutex de session toutes
les requêtes concurrentes d'un flux très suivi — jusqu'à 10 000 entrées
parcourues par requête. `touchListener` est donc O(1) ; la purge vit dans
`stats()`, appelé toutes les 5 s par un seul lecteur, et en dernier recours
quand le plafond est atteint.

Le pic (`peak_listeners`) est par conséquent le maximum **observé aux instants
de lecture**, à 5 s près, et non un maximum instantané continu : le compte n'est
exact qu'après purge. Il survit aux départs mais pas à l'arrêt du flux ni au
redémarrage du process — l'historique persistant est
[STR-162](https://linear.app/streampulse/issue/STR-162).

La map est plafonnée à `maxTrackedListeners` = 10 000 entrées : une diffusion
très suivie — ou un client qui ferait varier son identité — ne doit pas faire
enfler la mémoire sans limite. Le plafond purge **avant** de rejeter : une map
saturée d'entrées déjà expirées écarterait sinon un auditeur légitime et
sous-compterait l'audience. Un client déjà suivi reste rafraîchi malgré le
plafond, sinon il expirerait à tort.

### 2. Identification par adresse réseau, et le drapeau qui va avec

`clientKey` est l'adresse du client. C'est le seul discriminant disponible : les
lecteurs natifs (AVPlayer, ExoPlayer) ne portent pas le `Bearer` — c'est déjà
pourquoi les routes HLS sont en `OptionalAuth` — et rien d'autre dans la requête
n'est stable.

Conséquences assumées : deux lecteurs derrière la même IP publique comptent pour
un, et un client qui change d'adresse compte double le temps que sa fenêtre
expire. D'où le vocabulaire retenu partout, jusque dans l'interface :
**« auditeurs estimés »**, jamais « connectés ».

Le point délicat est `X-Forwarded-For`. L'en-tête est falsifiable : le lire sans
condition laisserait n'importe qui gonfler le compteur d'un flux en variant sa
valeur. Mais l'ignorer rend la fonctionnalité vide de sens en production, où
tous les auditeurs traversent Caddy et partagent donc son adresse — le compteur
saturerait à 1.

Retenu : un drapeau `TRUST_PROXY_HEADERS`, **faux par défaut**. Activé, le
premier maillon de `X-Forwarded-For` fait foi ; désactivé, on s'en tient à
`RemoteAddr`. C'est une donnée de déploiement, pas de domaine, injectée par
`SetTrustProxyHeaders` au démarrage — même motif que `SetMetrics`.

> **À faire au déploiement** : poser `TRUST_PROXY_HEADERS=true` sur le VPS.
> Sans lui, la statistique affichera 1 auditeur quoi qu'il arrive.

### 3. `GET /api/streams/{id}/stats`, propriétaire uniquement

Réservé au propriétaire du flux, **404 pour un tiers** — jamais 403 : l'audience
d'un flux ne doit pas être devinable, ni même son existence. Cohérent avec le
reste du domaine.

Un flux qui n'est pas en direct répond `200` avec des compteurs à zéro plutôt
qu'une erreur : le client interroge l'endpoint pendant toute la vie de l'écran
et n'a pas à distinguer « pas encore démarré » de « échec ».

`duration_seconds` est calculée côté serveur — depuis `started_at` jusqu'à
maintenant tant que le flux est live, jusqu'à `ended_at` ensuite — et bornée à
zéro : une horloge en avance ne doit pas produire de durée négative.

### 4. Interrogation toutes les 5 secondes, échecs silencieux

Le mobile interroge l'endpoint toutes les **5 s** tant qu'un flux est en direct,
cadence imposée par l'AC. La première mesure part immédiatement à l'armement :
attendre 5 s laisserait la carte sans chiffre juste après le démarrage, au
moment précis où le diffuseur la regarde.

Les mesures s'arrêtent quand le direct s'arrête et quand l'écran passe en
arrière-plan, comme la souscription SSE.

**Un échec de mesure est ignoré volontairement.** L'audience est une information
d'appoint : une coupure réseau ne doit pas faire clignoter une erreur sur un
tableau de bord par ailleurs fonctionnel. La dernière valeur connue reste
affichée, et l'erreur de chargement de la liste garde son propre canal.

La ligne d'audience est rendue **dès que le flux est en direct**, avec des
tirets tant qu'aucune mesure n'est arrivée. La faire apparaître au premier
relevé ferait sauter la mise en page, et elle disparaîtrait au passage en
arrière-plan — là où la durée, elle, se contente de figer. C'est la métrique
cœur de l'US : elle garde sa place.

`duration_seconds` n'est pas repris côté mobile. Le tableau de bord affiche déjà
la durée via un compteur local rafraîchi chaque seconde ; la valeur serveur
n'arriverait que toutes les 5 s et ferait sauter le chronomètre. Le champ reste
dans le contrat HTTP, où l'historique en aura besoin.

## Alternatives écartées

- **Interroger l'API Prometheus depuis le mobile** : `/metrics` est bloqué en
  production, et cela coupleraient le client à la stack d'observabilité.
- **Compter les segments plutôt que les manifestes** : les segments arrivent par
  rafales, le chiffre suivrait le débit, pas l'audience.
- **Identifiant de lecture généré par le client** (query sur la playlist) :
  indépendant du réseau et insensible au NAT, mais ne compterait aucun lecteur
  tiers (VLC, ffplay, navigateur) et se falsifie tout aussi facilement.
- **Persister l'audience en base** : nécessaire pour l'historique
  ([STR-162](https://linear.app/streampulse/issue/STR-162)), inutile pour du
  temps réel, et coûteux en écritures à 5 s d'intervalle.

## Conséquences

- L'audience est **une estimation**, et le mot apparaît dans l'interface. Y
  attacher un engagement chiffré serait une erreur.
- Les compteurs repartent de zéro à chaque redémarrage de l'API et à chaque
  arrêt de flux : ce ne sont pas des données d'analytique.
- Derrière un reverse proxy sans `TRUST_PROXY_HEADERS`, le chiffre est
  inexploitable. C'est la seule configuration à ne pas oublier.
