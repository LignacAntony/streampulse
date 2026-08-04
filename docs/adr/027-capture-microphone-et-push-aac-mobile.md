# ADR 027 — Capture microphone et push AAC depuis l'application mobile

**Date** : 2026-08-04
**Statut** : Accepté
**Ticket** : [STR-156](https://linear.app/streampulse/issue/STR-156)

---

## Contexte

Le tableau de bord livré par STR-153 pilote le cycle de vie d'un flux mais
laisse un encodeur externe pousser l'audio vers `stream_source_url`. STR-156
doit rendre la diffusion autonome depuis iOS et Android : permission micro,
encodage compatible avec l'ingest et reprise après une coupure réseau.

Le backend attend un flux **AAC avec en-têtes ADTS** et le transmet à ffmpeg
avec `-c:a copy` ([ADR 015](015-moteur-hls-segmentation-ffmpeg.md)). Il ne faut
donc ni lui envoyer du PCM, ni lui faire supporter le coût CPU d'un transcodage
par diffuseur.

L'analyse initiale de STR-153 reposait sur `record` v5, qui ne savait streamer
que du PCM16. Depuis `record` 6.2.0, Android et iOS savent produire un stream
AAC/ADTS ; la version 6.2.1 corrige en plus un crash possible du stream AAC sur
Android. `record` 7 demande Flutter 3.44 / Dart 3.12, au-delà de la toolchain du
projet (Flutter 3.41 / Dart 3.11).

## Décision

### 1. `record` 6.2.1, AAC-LC mono 44,1 kHz à 64 kbit/s

L'application utilise `AudioRecorder.startStream` avec `AudioEncoder.aacLc`.
La permission et `isEncoderSupported` sont vérifiés **avant** l'appel
`PATCH /start` : un refus de permission ou un appareil incompatible ne doit
jamais créer un direct silencieux.

Si le serveur a accepté le démarrage mais que la capture échoue avant le
premier push, le client appelle immédiatement `PATCH /stop` et rend l'erreur à
l'écran.

### 2. Corps HTTP brut chunked, malgré le mot « multipart » du ticket

Le contrat réel de l'ingest est un corps brut `Content-Type: audio/aac`, pas un
formulaire multipart. Un client Dio dédié envoie directement le
`Stream<List<int>>` sans `Content-Length` : l'adaptateur IO utilise ainsi le
transfert HTTP chunked, sans fichier temporaire ni accumulation en mémoire.

Ce client n'hérite ni du timeout de réception des appels REST courts, ni de
l'intercepteur JWT : la requête dure tout le direct et l'authentification est
portée par la clé secrète dans l'URL.

### 3. Reconnexion avec un nouvel encodeur et un backoff borné

Une fin de requête ou une erreur réseau pendant que la diffusion est désirée
déclenche une nouvelle tentative après 1, 2, 4, 8, 16 puis 30 secondes. Chaque
tentative redémarre `record`, afin que le nouveau corps commence par des trames
AAC/ADTS autonomes. L'interface affiche « Reconnexion audio… » pendant cette
fenêtre et le bouton Arrêter reste disponible.

### 4. Diffusion au premier plan uniquement

`record` ne garantit pas à lui seul une capture continue en arrière-plan sur
iOS et Android. Ajouter un service foreground Android et une stratégie iOS
spécifique augmenterait fortement le périmètre et donnerait des comportements
différents selon l'OS.

La règle mobile est explicite : quand l'application reçoit
`paused`, `hidden` ou `detached`, elle termine d'abord le flux côté serveur puis
libère le micro. Ainsi, une suspension normale de l'OS ne laisse pas un statut
`live` sans audio. `inactive` est ignoré, car cet état transitoire apparaît
notamment pendant la boîte de permission micro.

Le serveur couvre le cas où aucun callback ne peut partir : chaque session live
porte un bail d'ingest configurable (`INGEST_RECONNECT_GRACE_SECONDS`, 45
secondes par défaut), armé dès le démarrage puis réarmé à
chaque déconnexion. La deadline réseau est elle aussi glissante : une socket
half-open sans nouveaux octets finit par libérer le slot. Une reconnexion
annule le timer ; sinon le backend passe le flux à `ended`, ferme ffmpeg et
notifie les abonnés. Un échec persistant est borné par
`INGEST_STOP_TIMEOUT_SECONDS` (10 secondes par défaut), puis le bail est réarmé
pour réessayer. Le délai par défaut dépasse le plus grand backoff mobile (30
secondes), ce qui laisse une tentative de reprise sans conserver indéfiniment
un live silencieux.

### 5. Pas de capture sur Flutter web

L'adaptateur HTTP navigateur ne sait pas pousser ce corps streamé de la même
manière. La vérification échoue avant le démarrage avec un message
d'indisponibilité ; aucun live muet n'est créé.

## Alternatives écartées

- Enregistrer un fichier `.aac` et le lire pendant son écriture : dépendance au
  flush de la plateforme, latence et reprise fragile.
- Écrire un encodeur via platform channel : doublon désormais inutile avec
  `record` 6.2.1.
- Envoyer du PCM et transcoder côté backend : coût CPU permanent, et préempte
  la décision de STR-224.
- Maintenir le direct en arrière-plan dès ce lot : nécessite un service
  foreground et une UX de notification, avec des contraintes iOS distinctes.

## Conséquences

- Le bouton « Démarrer » active désormais le micro du téléphone ; l'URL reste
  affichée pour les encodeurs externes et le diagnostic.
- Une coupure réseau ne termine pas immédiatement le direct : le client tente
  de reprendre et expose son état dans la carte.
- La mise en arrière-plan termine volontairement la diffusion.
- Le protocole est verrouillé par un test HTTP réel : octets bruts, type
  `audio/aac`, absence de `Content-Length`.
