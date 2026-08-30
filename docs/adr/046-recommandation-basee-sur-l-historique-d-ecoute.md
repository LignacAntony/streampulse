# ADR 046 — Recommandation de pistes basée sur l'historique d'écoute

**Date** : 2026-08-29
**Statut** : Accepté
**Ticket** : [STR-203](https://linear.app/streampulse/issue/STR-203) (US-09-04, fonctionnalité bonus)

## Contexte

L'US-09-04 demande un « algorithme de recommandation simple basé sur l'historique
d'écoute ». Deux constats de départ, vérifiés dans le schéma existant :

1. **Aucun historique d'écoute n'est persisté.** Rien ne journalise « l'utilisateur
   X a écouté Y à l'instant Z ». Le temps d'écoute côté mobile (ADR 042) est un
   cumul local, l'audience d'un flux est une *estimation* Prometheus (ADR 025) :
   ni l'un ni l'autre n'est un événement par utilisateur exploitable. La donnée
   d'entrée de la recommandation **n'existe pas encore** : la première tâche est
   donc de la capter, pas d'écrire l'algorithme.

2. **Le direct HLS ne fournit aucun signal fiable par utilisateur.** Le manifeste
   et les segments sont publics (`OptionalAuth`) et servis sans connexion
   persistante : le serveur ne sait pas *qui* écoute un flux. Le seul contenu dont
   la lecture passe par un endpoint **authentifié** est la **piste** de la
   bibliothèque (`GET /api/tracks/{id}/stream`, US-05-04) — l'identité du lecteur y
   est connue, et la piste porte un **artiste**, métadonnée idéale pour une
   recommandation par affinité.

## Décision

### 1. Capter l'écoute d'une piste, best-effort, sur l'endpoint de lecture

Migration `000023` : table `listening_history(user_id, track_id, played_at)`, une
ligne par écoute (pas un compteur agrégé — on veut pouvoir pondérer par la récence
et faire évoluer l'algorithme sans remigrer). `ON DELETE CASCADE` sur les deux FK.

> Le numéro **023** (et non 020) saute par-dessus `000020_create_chat`,
> `000021_create_chat_global_bans` (feature chat) et `000022_tracks_is_public`
> (visibilité publique/privée des pistes, STR-248), déjà pris sur `develop` : un
> numéro de migration est global et jamais réutilisé, sous peine de collision au
> merge et d'une base incohérente.

Le domaine `track` enregistre l'écoute dans `StreamTrack`, **après** une ouverture
de fichier réussie (donc la piste existe et appartient au demandeur). L'appel est
**best-effort** : une erreur d'historique est journalisée, jamais propagée — elle
ne doit pas casser la lecture. L'injection suit le patron déjà en place pour la
purge des fichiers (`SetTrackPurger`, ADR 032) : une interface **côté
consommateur** `track.PlayRecorder`, satisfaite par `recommendation.Service`,
posée dans `main.go` via `SetPlayRecorder`. Le domaine `track` n'importe donc pas
`recommendation`.

**Ne compter qu'une lecture depuis le début.** `http.ServeContent` honore les
requêtes `Range` : le lecteur émet **plusieurs** requêtes par piste (avance dans
la piste, reprise après coupure réseau — STR-118). Les compter toutes gonflerait
l'historique. On n'enregistre donc que les requêtes sans en-tête `Range`, ou dont
le `Range` commence à `bytes=0-` : une écoute par démarrage, pas par octet
demandé. Règle simple et défendable ; le sur-comptage résiduel (une reprise qui
recharge à zéro) n'est qu'un signal de classement, pas une facturation.

> **Limite connue (relevée au test e2e sur simulateur).** Le lecteur natif
> (`ConcatenatingAudioSource`, ADR 034) **précharge la file** : démarrer une file
> de N pistes ouvre les N sources, chacune par un `GET /stream` en `bytes=0-`.
> Côté serveur, un préchargement est indistinguable d'une vraie écoute → **toutes
> les pistes de la file sont enregistrées**, pas seulement celle réellement
> écoutée. Conséquence : l'affinité reflète aussi ce que l'on **met en file**, pas
> uniquement ce que l'on écoute jusqu'au bout. Acceptable pour une reco « simple »
> (mettre en file traduit un intérêt), mais à corriger si le signal doit être
> fidèle : enregistrer depuis le **client** quand une piste devient *courante*
> (`currentIndexStream`), via une balise dédiée — ce qui déplace la capture hors du
> chemin `/stream`. Ticket séparé.

### 2. Un algorithme « simple » qui vit dans une seule requête SQL

`GET /api/recommendations/tracks` (JWT, niveau user) puise dans les pistes que le
demandeur peut **lire** : les siennes (toute visibilité) **et** les pistes
**publiques** des autres utilisateurs. STR-248 a rendu la lecture cross-user
possible pour une piste publique (`GetTrackFileForStream` : propriétaire **ou**
`is_public`) ; une piste **privée** d'un tiers reste en 404, donc hors vivier. Le
classement, en une requête (deux CTE) :

1. **les pistes jamais écoutées d'abord** (à découvrir) ;
2. puis par **affinité d'artiste** : plus l'artiste a été écouté, plus il remonte ;
3. puis les **moins récemment écoutées** (redécouverte) ;
4. puis les **plus récemment ajoutées**.

**Cold-start géré par construction** : sans historique, toutes les affinités valent
0 et toutes les pistes sont « jamais écoutées » → l'ordre retombe sur les ajouts
récents. L'endpoint rend donc toujours un résultat utile (jamais une liste vide
tant que l'utilisateur a des pistes), sans branche spéciale.

Le service ne fait que traduire les signaux bruts (`artist_plays`, `never_played`,
`from_others`) en une **raison lisible** (« Parce que vous écoutez souvent X »,
« Découverte publique » pour une piste publique d'un tiers, « Nouveauté de votre
bibliothèque », « À réécouter ») : la logique de tri reste en SQL, testée en
intégration contre un vrai PostgreSQL — y compris qu'une piste publique d'un tiers
est proposée et une piste privée d'un tiers jamais (le `NULLS FIRST` et les casts
booléens ne se valident pas avec un fake).

### 3. Portée assumée : les pistes, pas le direct

L'historique et la recommandation portent sur la **bibliothèque de pistes**. Le
direct reste dehors, faute de signal par utilisateur (voir Contexte). C'est une
limite explicite, pas un oubli : l'étendre au direct supposerait soit un endpoint
« balise » appelé par le mobile au démarrage d'un live, soit un suivi de session
côté serveur — un ticket à part.

### 4. Client mobile écrit à la main, pas régénéré

La route est ajoutée à `openapi.yaml` (contrat = source de vérité, ADR 012), mais
la couche data mobile appelle l'endpoint via le `Dio` sous-jacent plutôt que le
client généré, **sans** relancer `make generate-openapi-client`. Même choix, et
même justification, que la sonde de manifeste (ADR 045) : régénérer tout le paquet
pour un unique endpoint bonus apporterait un large diff de code généré pour un
gain nul. Le contrat reste documenté ; la lecture reste typée côté app.

## Alternatives écartées

- **Filtrage collaboratif complet (« ceux qui ont écouté X ont écouté Y »)** —
  écarté pour cette US : on se limite à une reco **par contenu** (affinité
  d'artiste) sur les pistes lisibles par le demandeur (les siennes + les
  publiques). Le collaboratif croiserait les historiques entre utilisateurs, plus
  lourd et hors du « simple » demandé.
- **Ne recommander que sa propre bibliothèque** — c'était la portée initiale
  (avant STR-248) faute de pistes publiques. Depuis que la visibilité publique
  existe et que la lecture cross-user est permise, s'y limiter priverait la reco
  de toute découverte : le vivier inclut donc les pistes publiques des autres.
- **Agréger l'historique en compteur (`play_count` par piste)** — écarté : perdre
  l'horodatage interdirait toute pondération par la récence et tout changement
  d'algorithme sans remigration. Le coût d'une ligne par écoute est négligeable.
- **Compter chaque requête `Range` comme une écoute** — écarté : sur-comptage
  massif (un seul morceau écouté = des dizaines de requêtes de seek/reprise).
- **Extraire le genre par analyse audio (ffprobe/tags)** pour affiner l'affinité —
  écarté de cette US : `tracks` n'a pas de colonne genre, l'artiste suffit à un
  algorithme « simple ». À rouvrir si la reco doit gagner en finesse.
- **Étendre l'historique au direct dès maintenant** — écarté : pas de signal par
  utilisateur sans nouveau mécanisme (balise mobile ou suivi de session). Hors
  périmètre, documenté comme extension.
