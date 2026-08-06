# ADR 030 — Transcodage à la volée des formats d'ingest

**Date** : 2026-08-06
**Statut** : Accepté
**Ticket** : [STR-204](https://linear.app/streampulse/issue/STR-204)

---

## Contexte

Le moteur HLS ([ADR 015](015-moteur-hls-segmentation-ffmpeg.md)) fait tourner **un** process ffmpeg
par direct : le diffuseur pousse son audio sur `POST /api/streams/ingest/{stream_key}`, le
segmenteur le remuxe en `.ts` avec `-c:a copy` et publie un manifeste glissant.

`-c:a copy` ne recode rien — c'est précisément ce qui rend le chemin gratuit en CPU et en latence.
Mais cela impose au diffuseur d'arriver déjà en **AAC/ADTS**. C'est le cas de l'application mobile
([ADR 027](027-capture-microphone-et-push-aac-mobile.md)), et de personne d'autre : un encodeur
externe (Icecast, un `ffmpeg` en ligne de commande, un vieux script) pousse volontiers du MP3, de
l'OGG ou du WAV. Ces flux passaient la validation `audio/*` du handler, atteignaient le segmenteur,
et produisaient soit du silence, soit un manifeste vide — sans message exploitable.

L'US demande d'accepter n'importe quel format entrant, avec moins de 2 secondes de latence ajoutée.

## Décision

### 1. Un second ffmpeg **devant** le segmenteur, plutôt qu'un segmenteur reconfigurable

La solution qui vient d'abord est de choisir le codec du segmenteur (`copy` ou `aac`) selon le
format entrant. Elle ne tient pas : le segmenteur est démarré par `LiveSessions.Start`, au moment
du `PATCH /start`, alors que le format n'est connu qu'au premier push — et une session vit
plusieurs pushes successifs (reconnexions du mobile, cf. le bail d'ingest de l'ADR 024). Le
remplacer à chaud reviendrait à faire boucler `session.run` sur des générations de segmenteurs,
alors que la fermeture d'un segmenteur est aujourd'hui le signal « ffmpeg est mort seul, récolte la
session ».

Le transcodeur est donc un **process séparé, intercalé dans le tuyau d'ingest** :

```
corps HTTP → [ffmpeg -i pipe:0 -c:a aac -f adts pipe:1] → stdin du segmenteur (-c:a copy) → .ts
             └──────────── durée de vie = celle du push ────────────┘
```

Trois propriétés en découlent :

- **Le segmenteur ne change pas.** Il reçoit toujours de l'ADTS, ses gardes, son reaping et ses
  tests restent intacts. Aucune ligne de `session.go` ni de `hls.go` n'a été touchée.
- **Le chemin AAC ne paie rien.** Pas de process en plus, pas de ré-encodage, pas d'octet copié en
  plus : `sink` reste l'entrée du segmenteur. C'est le cas nominal (le mobile), il ne devait pas
  régresser pour couvrir un cas de bord.
- **Le cycle de vie est le bon.** Le transcodeur meurt avec le push ; le segmenteur, lui, survit à
  la déconnexion du diffuseur — la fenêtre de segments reste servie jusqu'au `stop` explicite.
  C'est exactement la sémantique existante, et c'est pourquoi le transcodeur ne ferme **jamais**
  l'entrée du segmenteur.

### 2. Le Content-Type choisit le démultiplexeur, il ne le construit pas

`resolveIngestFormat` mappe le type MIME déclaré vers un nom de démultiplexeur ffmpeg tiré d'une
table close (`mp3`, `ogg`, `wav`, `flac`, `mp4`…). La valeur qui atteint la ligne de commande vient
donc du serveur, jamais du diffuseur — la propriété qui justifiait déjà le `#nosec G204` du
segmenteur reste vraie du transcodeur.

Forcer `-f` plutôt que laisser ffmpeg sonder n'est pas qu'une question de sûreté : le sondage
consomme des octets et du temps avant de produire quoi que ce soit, et c'est directement du budget
de latence.

Trois cas, dans cet ordre :

| Content-Type | Traitement |
|---|---|
| absent, `audio/aac` et variantes | passthrough — contrat historique, latence ajoutée nulle |
| `audio/*` répertorié | transcodage avec `-f <demuxer>` |
| `audio/*` inconnu | transcodage avec sondage borné (l'US dit « n'importe quel format ») |
| tout le reste | 415 avant qu'un octet n'atteigne un process |

`audio/mp4` et `audio/webm` sont volontairement **hors** de la liste passthrough : ce sont des
conteneurs, pas de l'ADTS. Les laisser passer tels quels enverrait au segmenteur un flux qu'il ne
sait pas muxer — un test les garde du bon côté de la frontière.

### 3. Le budget de latence est tenu par des bornes explicites

Les valeurs par défaut de ffmpeg (`probesize` 5 Mo, `analyzeduration` 5 s) suffisent à elles seules
à faire sauter le critère des 2 secondes sur une entrée à faible débit. Le transcodeur les ramène à
128 Kio et 1 s — largement de quoi couvrir un en-tête MP3, OGG, WAV ou FLAC — et ajoute
`-fflags +nobuffer` en entrée et `-flush_packets 1` en sortie pour qu'aucun paquet ne soit retenu.

Un test mesure ce qui est réellement promis : le délai entre le premier octet poussé par le
diffuseur et le premier octet AAC transmis au segmenteur, sur un push découpé en blocs de 4 Kio
comme un vrai direct. Mesuré à ~21 ms en local (ffmpeg 8.1, MP3 128 kb/s), deux ordres de
grandeur sous le budget.

La sortie est normalisée en 128 kb/s, 44,1 kHz, stéréo. Un flux d'entrée mono à 8 kHz produirait un
ADTS valide sans normalisation, mais la constance du profil sur toute la durée du direct est ce qui
garantit que les segments restent concaténables par le lecteur.

### 4. « Zéro octet produit » vaut 415, pas 500

Quand le corps ne correspond pas au type annoncé, ffmpeg meurt, l'écriture suivante prend un EPIPE
et `io.Copy` remonte une erreur — indiscernable, telle quelle, d'une coupure réseau. Le handler
ferme donc le transcodeur **avant** de statuer et regarde un signal sans ambiguïté : des octets sont
entrés, aucun AAC n'est sorti.

Ce cas devient un **415** avec `audio payload could not be decoded`, pas un 500 : c'est le push qui
est en cause, pas le serveur, et le diffuseur peut agir. Le stderr de ffmpeg est conservé dans un
tampon borné (8 Kio, les derniers octets) et journalisé — un direct de plusieurs heures ne doit pas
accumuler ses warnings en mémoire.

### 5. `cmd.Wait` après la recopie, pas en parallèle

Détail d'implémentation qui mérite d'être écrit parce qu'il se casse silencieusement : `cmd.Wait`
ferme le pipe de sortie. L'appeler pendant que la goroutine de recopie lit encore tronquerait les
derniers octets AAC. `close` attend donc l'EOF de stdout, puis `Wait` — et le délai de grâce n'est
plus un `select` sur `Wait` mais un `time.AfterFunc` qui tue le process, ce qui ferme son stdout et
débloque la recopie par le même chemin.

## Alternatives écartées

- **Transcoder systématiquement** (`-c:a aac` dans le segmenteur, plus de `copy`). Une ligne à
  changer, mais tout le trafic nominal — du mobile qui envoie déjà de l'AAC — paierait un
  ré-encodage AAC→AAC : perte de génération sur la qualité et CPU brûlé sur le seul chemin qui
  compte vraiment.
- **Remplacer le segmenteur au premier push**, une fois le format connu. Oblige `session.run` à
  gérer plusieurs générations de segmenteurs, alors que la mort d'un segmenteur est le signal de
  récolte de la session. Beaucoup de complexité dans le code le plus concurrent du domaine, pour
  gagner un process sur un cas de bord.
- **Créer le segmenteur paresseusement au premier ingest**, avec le bon codec. Plus propre en
  théorie, mais `Playlist`, `Segment` et `AttachIngest` s'appuient tous sur la présence du
  segmenteur dès `Start` : c'est un changement de sémantique diffus pour toute la lecture HLS.
- **Refuser en 415 tout `audio/*` non répertorié.** Contrat plus net, mais l'US demande d'accepter
  n'importe quel format entrant ; le sondage borné coûte une analyse au démarrage du flux, pas par
  segment.
- **Une métrique Prometheus par format transcodé.** La famille aurait un label de cardinalité
  bornée et serait légitime, mais l'US ne la demande pas ; un log structuré (`media_type`,
  `demuxer`) suffit à répondre à « qui pousse du MP3 ? ».

## Conséquences

- N'importe quel format audio lisible par ffmpeg est diffusable ; les auditeurs reçoivent
  toujours de l'AAC, quel que soit ce que le diffuseur a poussé.
- Un direct non-AAC coûte **deux** process ffmpeg au lieu d'un. `HLS_MAX_CONCURRENT`
  ([ADR 016](016-scalabilite-test-de-charge-et-limiteur-hls.md)) borne les lecteurs, pas les
  diffuseurs : la charge CPU d'un parc de diffuseurs non-AAC est à surveiller sur le dashboard
  machine avant d'être un problème.
- Un push mal étiqueté reçoit désormais un 415 explicite au lieu d'un direct silencieux — c'est un
  changement de comportement visible pour un client qui poussait du MP3 en croyant que ça marchait.
- L'application mobile n'est pas touchée : elle pousse de l'AAC, elle reste sur le chemin direct.
