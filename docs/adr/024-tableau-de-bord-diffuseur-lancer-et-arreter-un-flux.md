# ADR 024 — Tableau de bord diffuseur : lancer et arrêter un flux

**Date** : 2026-07-30
**Statut** : Accepté
**Ticket** : [STR-153](https://linear.app/streampulse/issue/STR-153) (sous-issues [STR-155](https://linear.app/streampulse/issue/STR-155), [STR-157](https://linear.app/streampulse/issue/STR-157), [STR-159](https://linear.app/streampulse/issue/STR-159))

---

## Contexte

US-06-01 : le backend sait déjà tout faire — créer un flux, le démarrer, l'arrêter, recevoir
l'audio et le segmenter en HLS ([ADR 013](013-domaine-streaming.md),
[ADR 015](015-moteur-hls-segmentation-ffmpeg.md)) — mais aucun de ces gestes n'est atteignable
depuis l'application. L'onglet « Tableau » était un `PlaceholderScreen`, et un diffuseur
fraîchement promu par un administrateur n'avait aucun moyen de créer, ni de lancer, un direct.

Deux lectures de l'énoncé s'affrontaient : le tableau de bord doit-il **capturer le micro du
téléphone** et pousser l'audio lui-même, ou seulement **piloter** le cycle de vie du flux en
laissant l'encodeur du diffuseur pousser vers l'URL d'ingest ?

## Décision

### 1. Plan de contrôle uniquement — la capture micro sort du périmètre

> **Mise à jour 2026-08-04** — Cette limite est levée par
> [l'ADR 027](027-capture-microphone-et-push-aac-mobile.md) : `record` 6.2.1
> sait désormais streamer de l'AAC/ADTS sur Android et iOS. La décision
> ci-dessous reste l'historique du périmètre de STR-153.

Le tableau de bord crée, démarre et arrête les flux, et remet au diffuseur l'URL d'ingest à
donner à son encodeur (ffmpeg, BUTT, Mixxx). Il ne capture pas le micro.

Raison technique : `POST /api/streams/ingest/{stream_key}` attend de l'**AAC en ADTS**, que
ffmpeg segmente en `-c:a copy` sans réencoder. Or côté Flutter, `record` ne sait streamer que du
PCM16 — pousser de l'AAC depuis le téléphone impose soit de lire un fichier en cours d'écriture,
soit un encodeur natif via platform channel, soit d'assouplir le contrat backend et d'y ajouter
un réencodage (donc du CPU serveur par diffuseur, cf. STR-224). Chacune de ces branches dépasse
à elle seule l'estimation de l'US.

STR-156 (capture micro + push) devient un ticket autonome.

### 2. Le compteur d'auditeurs sort aussi

L'AC demande un compteur d'auditeurs temps réel. Aucune API ne l'expose : les métriques
livrées par [ADR 022](022-metriques-metier-streaming-et-panel-live.md) vivent côté Prometheus, et
`MetricsRecorder` n'offre que `RecordHLSRequest` / `ForgetStream` — aucun décompte en mémoire.
Le seul chiffre disponible est une **estimation** Grafana
(`rate(playlist 200)[2m] × 10`), et `/metrics` est bloqué par Caddy en production.

Fabriquer un compteur dans l'urgence reviendrait à préempter STR-160
(`GET /api/streams/:id/stats`), qui appartient à STR-154. STR-158 est donc déplacée sous STR-154,
avec son endpoint. Le tableau de bord n'affiche pas de compteur à ce stade — écart à l'AC assumé
et tracé ici.

### 3. Feature `broadcast/` distincte, entité dédiée

La couche diffuseur vit dans `mobile/lib/features/broadcast/`, avec son entité
`BroadcastStream` — et non en étendant `LiveStream` de la feature `streams`.

Motif : `BroadcastStream` porte `streamKey` et `streamSourceUrl`. Ajouter ces champs à
`LiveStream` ferait voyager un secret de type bearer dans la découverte publique, les favoris et
le lecteur auditeur. La séparation rend la fuite structurellement impossible plutôt que
seulement improbable. Coût accepté : un mapper et un datasource supplémentaires.

### 4. Fraîcheur du statut par SSE, avec resynchronisation à chaque reconnexion

Un flux peut s'arrêter sans que le diffuseur y soit pour quelque chose : interruption par un
administrateur ([ADR 018](018-supervision-admin-des-flux-et-journal-daudit.md)) ou nettoyage des
flux orphelins. Le tableau de bord souscrit donc à `GET /api/streams/{id}/events` tant qu'un flux
est en direct.

Trois conséquences ont dicté l'implémentation :

- **Un client SSE séparé.** `DioClient` borne ses réponses à `receiveTimeout` = 10 s, alors que
  le keep-alive serveur tombe toutes les 15 s (`sseKeepAliveInterval`) : une souscription passée
  par lui mourrait toutes les 10 s. `core/network/sse_client.dart` utilise donc sa propre
  instance Dio, sans `receiveTimeout`, et laisse `DioClient` dédié aux requêtes courtes.
- **La politique de reprise appartient à l'appelant.** `SseClient.connect()` n'expose qu'**une**
  connexion ; `BroadcastNotifier` porte le backoff exponentiel plafonné à 30 s et la coupure en
  arrière-plan. Le client reste ainsi testable sans horloge.
- **Chaque reconnexion est suivie d'un `refresh()`.** Le flux SSE ne rejoue pas les évènements
  manqués et n'émet qu'`ended` : sans cette resynchronisation, un arrêt survenu pendant une
  coupure resterait invisible.

Le `Bearer` est lu à l'ouverture, pas injecté par intercepteur : le serveur n'authentifie qu'à
la connexion, une souscription établie survit donc à l'expiration du token à 15 minutes.

### 5. Un seul direct : prévenir plutôt que subir le 409

Le backend n'autorise qu'un flux live par diffuseur (migration `000016_streams_one_live`). Plutôt
que de laisser l'utilisateur découvrir la règle par une erreur, le bouton « Démarrer » des autres
flux est désactivé avec la mention « Un autre flux est en direct ». Le 409 reste traité en filet
de sécurité — une course entre deux appareils reste possible — et déclenche alors un rechargement
plutôt qu'un échec sec.

### 6. La clé de diffusion n'est jamais rendue par défaut

`stream_key` est un secret de type bearer : qui la détient diffuse à la place du propriétaire.
L'URL d'ingest s'affiche donc masquée (points + 4 derniers caractères), la révélation se referme
seule au bout de 15 s, et le bouton de copie place l'URL entière dans le presse-papier sans jamais
l'afficher ni l'écho dans le toast.

Limite assumée : sur Android le presse-papier est lisible par d'autres applications, et
`Clipboard.setData` de Flutter n'expose pas le drapeau « contenu sensible » d'Android 13+.

**Mise à jour (STR-228, [ADR 028](028-rotation-de-la-cle-de-diffusion.md))** : la clé se régénère
désormais depuis le tableau de bord (`POST /api/streams/{id}/key/rotate`). En cas de fuite, le
recours n'est plus de supprimer le flux et d'en recréer un — ce qui lui faisait perdre son
identifiant, ses favoris et son historique.

### 7. Onglet visible pour tous, état vide orienté

L'onglet « Tableau » reste dans le shell quel que soit le rôle. Un non-diffuseur y trouve un état
vide qui pousse vers `/broadcaster-request`, un visiteur non connecté vers `/login`. Rendre les
branches du `StatefulShellRoute.indexedStack` conditionnelles au rôle ferait glisser les index
d'onglets et obligerait à reconstruire le routeur lors d'une promotion en cours de session.

Corollaire côté API : `GET /api/users/me/streams` est monté derrière `RequireAuth` **sans**
`RequireRole("broadcaster")` et renvoie `[]` à un non-diffuseur, plutôt qu'un 403 que le client
devrait distinguer du cas « aucun flux ».

## Limites de latence

L'AC de STR-159 demande un démarrage en moins de 5 secondes. Le critère ne peut porter que sur le
plan de contrôle, et c'est ce qui est testé (`dashboard_screen_test.dart` : le passage à
« EN DIRECT » est rendu depuis la réponse de `start`, sans rechargement bloquant de la liste).

| Mesure | Ordre de grandeur |
|---|---|
| `PATCH /api/streams/{id}/start` | < 200 ms |
| Premier son entendu par un auditeur | ~10-25 s |

La seconde ligne n'est pas améliorable ici : elle découle de `hls_time = 10` et d'une fenêtre de
6 segments (`internal/streaming/hls.go`). La réduire est une décision de moteur HLS, pas de
tableau de bord.

## Livraison en deux phases

La [PR #273](https://github.com/LignacAntony/streampulse/pull/273) (STR-108, lecteur audio HLS)
était en revue au démarrage de ce travail et modifiait `internal/streaming/`, `openapi.yaml` et le
client Dart généré — exactement les fichiers dont l'endpoint `/api/users/me/streams` a besoin. Le
travail a donc été découpé pour n'entrer en conflit avec aucun d'eux :

- **Phase 1** : domaine, `BroadcastNotifier`, `SseClient`, écrans et tests, sans un seul fichier
  partagé avec #273. Le repository était un palier temporaire (`PendingBroadcastRepository`) :
  liste vide, mutations en échec explicite plutôt qu'un faux succès.
- **Phase 2** (après le merge de #273) : query `ListStreamsByOwner`, handler `ListMine`, route,
  `openapi.yaml`, régénération du client Dart, couche `data/` réelle, suppression du palier.

Les deux phases sont livrées.

### 8. Suppression d'un flux depuis le dashboard (ajout après revue)

L'US ne parle que de lancer et arrêter. La revue a relevé que les flux terminés
s'accumulent sans aucun moyen de nettoyer la liste, ce qui rend le tableau de bord
inutilisable au bout de quelques diffusions. La suppression a donc été rapatriée
dans ce lot plutôt que reportée.

Elle s'appuie sur `DELETE /api/streams/{id}`, déjà livré par STR-67 : suppression
douce (`archived_at`), propriétaire uniquement. Point notable : `ArchiveStream`
**termine le flux au passage** s'il est en direct. La confirmation le dit
explicitement — sans quoi un diffuseur pourrait couper sa propre diffusion en
croyant ranger sa liste.

L'édition d'un flux (`PUT /api/streams/{id}`, également disponible) reste hors
périmètre : aucun besoin exprimé, et elle mérite son propre ticket.

## Alternatives écartées

- **Polling de `/api/users/me/streams`** plutôt que SSE : plus simple et sans client dédié, mais
  la réactivité à un arrêt administrateur dépendrait de l'intervalle.
- **Stocker l'identifiant du flux localement** au lieu d'ajouter un endpoint : perdu à la
  réinstallation, invisible depuis un second appareil.
- **`GET /api/streams?mine=true`** : un même handler servirait tantôt un contrat public sans
  secrets, tantôt un contrat propriétaire avec la `stream_key` — le genre de branchement où une
  régression fait fuiter la clé.
- **Création implicite du flux** au premier « Démarrer » : moins de friction, mais titre par
  défaut exposé dans la découverte publique et aucun contrôle public/privé.

## Conséquences

- L'onglet « Tableau » quitte `PlaceholderScreen`.
- Un client SSE réutilisable existe désormais dans `core/network/` — le lecteur auditeur pourra
  s'en servir pour réagir à `ended` sans réinventer le parsing ni le backoff.
- Trois tickets restent à ouvrir ou déplacer : STR-156 (capture micro) devient autonome, STR-158
  (compteur) passe sous STR-154, et la rotation de `stream_key` reste à créer.
