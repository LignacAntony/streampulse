# ADR 015 — Moteur HLS : segmentation et manifeste via ffmpeg

**Date** : 2026-07-13
**Statut** : Accepté
**Ticket** : [STR-70](https://linear.app/streampulse/issue/STR-70) (sous-issue [STR-71](https://linear.app/streampulse/issue/STR-71) — endpoint de réception)

---

## Contexte

STR-70 poursuit la milestone **« Moteur de Streaming Live (Backend Go) »**. Après le CRUD des
flux ([ADR 013](013-domaine-streaming.md)) et le cycle de vie du direct start/stop + SSE
([ADR 013](013-domaine-streaming.md) §7), il faut désormais **transporter réellement l'audio** :

> En tant que backend, je veux segmenter le flux audio entrant en fichiers `.ts` de ~10 s et
> générer un manifeste `.m3u8` mis à jour en continu, afin de permettre la lecture HLS par les
> clients.

Le CDC (§4.3) fixe le transport : **pas de RTMP**. Le diffuseur pousse de l'audio **AAC via un
endpoint HTTP** du backend, et le backend **segmente en HLS** (protocole de lecture côté auditeur).

### État du code au démarrage de STR-70

- `LiveSessions` ([`session.go`](../../backend/internal/streaming/session.go)) gère déjà le cycle
  de vie d'une session live : une goroutine par flux, `context.CancelFunc`, mutex, abonnés SSE,
  drain déterministe via `Wait()`. La goroutine `session.run(ctx)` est un **placeholder**
  (`<-ctx.Done()`) explicitement réservé à STR-70/71 (cf. ADR 013 §7).
- L'URL de stream source `{STREAM_INGEST_BASE_URL}/api/streams/ingest/{stream_key}` est **déjà
  annoncée** au diffuseur ([`handler.go`](../../backend/internal/streaming/handler.go), `toResponse`),
  mais **aucun endpoint ne l'écoute encore**.
- Aucun service de manifeste ni de segments côté auditeur.

### Découpage STR-70 / STR-71

STR-71 est une **sous-issue** de STR-70. Répartition retenue :

- **STR-71** = l'**endpoint de réception** (ingest) qui accepte le flux entrant et le pousse dans
  le moteur.
- **STR-70** (parent) = le **moteur HLS** : segmentation, manifeste glissant, service des fichiers
  aux auditeurs, câblage dans la session.

### Incohérence de contrat résolue

Le titre de STR-71 évoque `POST /api/streams/:id/broadcast` (routé par **id**), alors que l'URL
**déjà exposée au diffuseur** (ADR 013) est routée par **stream_key** :
`…/api/streams/ingest/{stream_key}`. On **conserve la forme par `stream_key`** : elle est déjà dans
le contrat, déjà lisible par le diffuseur dans son dashboard, et le `stream_key` est le secret
d'authentification naturel du push (modèle Twitch/OBS). Le titre de STR-71 est donc considéré
comme obsolète sur ce point.

---

## Décision

### 1. Segmentation déléguée à **ffmpeg** en sous-processus (une instance par session live)

La goroutine `session.run(ctx)` lance un process **ffmpeg** avec `exec.CommandContext(ctx, …)` :
l'annulation du context (stop diffuseur ou shutdown serveur) tue proprement ffmpeg via le pipeline
d'arrêt existant (`Stop`/`StopAll` → `cancel()`).

Invocation cible (remux **sans ré-encodage**, AAC/ADTS → MPEG-TS) :

```
ffmpeg -hide_banner -loglevel warning \
  -i pipe:0 \                                  # audio entrant lu sur stdin
  -c:a copy \                                  # passthrough AAC → TS (pas de transcodage, CPU ~0)
  -f hls \
  -hls_time 10 \                               # segments ~10 s
  -hls_list_size 6 \                           # fenêtre glissante (≈1 min de retard max)
  -hls_flags delete_segments+append_list+omit_endlist \
  -hls_segment_type mpegts \
  -hls_base_url segments/ \                     # URI des segments dans le manifeste → segments/…
  -hls_segment_filename '<dir>/seg_%05d.ts' \
  '<dir>/playlist.m3u8'
```

- `<dir>` = répertoire temporaire **par session** (`os.MkdirTemp`, monté sur tmpfs en prod si
  possible). ffmpeg y écrit les `.ts` **et** le `.m3u8`, et gère seul la fenêtre glissante
  (`delete_segments`).
- `-c:a copy` : le flux étant déjà AAC, on **remux** seulement (empaquetage TS). Pas de
  transcodage → coût CPU négligeable, pas de perte de qualité.
- `-hls_base_url segments/` : les players HLS résolvent les URI de segments **relativement au
  manifeste**. Comme le manifeste est servi à `…/{id}/playlist.m3u8` et les segments à
  `…/{id}/segments/{seg}`, on préfixe les entrées du manifeste par `segments/` (le fichier sur
  disque garde son nom nu `seg_%05d.ts`).
- Le manifeste produit est un **live playlist** (pas de `#EXT-X-ENDLIST` tant que le flux tourne,
  grâce à `omit_endlist`).

Le segmenteur (`internal/streaming/hls.go`) encapsule ce process : création du `<dir>`, démarrage
de ffmpeg, exposition de son `stdin` (entrée d'ingest) et des chemins manifeste/segments, puis
`close()` (ferme stdin → ffmpeg finalise, kill au-delà d'un délai de grâce, supprime `<dir>`). Il
est injectable dans `LiveSessions` (factory `newSeg`) pour des tests unitaires **sans ffmpeg**.

### 2. Endpoint d'ingest (STR-71) : `POST /api/streams/ingest/{stream_key}`

- **Authentification par `stream_key`, routage 100 % en mémoire** (pas de JWT, **pas de lookup DB**).
  Le `start` du flux connaît déjà la clé (`stream.StreamKey`) : `Sessions.Start(streamID, streamKey)`
  indexe la session à la fois par `id` (public : SSE, lecture HLS) et par `stream_key` (secret :
  ingest). Le handler appelle `LiveSessions.AttachIngest(stream_key)` qui résout la session **en
  mémoire**. Conséquence : « clé inconnue » et « flux pas en direct » sont indistinguables sans
  session → **404** unique (on ne divulgue pas la validité d'une clé). Ce choix évite une requête SQL
  et une nouvelle query sqlc, et colle au fait que `LiveSessions` est déjà l'autorité in-memory du
  direct (cf. ADR 013 §7).
- **Corps = flux continu** : `AttachIngest` retourne l'`io.Writer` (stdin ffmpeg) + une fonction de
  détachement ; le handler **copie `r.Body` dedans** en streaming (`io.Copy`). La requête reste
  ouverte toute la diffusion. En fin de push, on **ne ferme pas** l'entrée du segmenteur : la session
  reste live (fenêtre de segments disponible) jusqu'au `stop` explicite.
- **Un seul push par flux** : un flag `ingesting` (sous mutex) rejette un 2e push concurrent → `409`.
  Segmenteur indisponible (ffmpeg absent) → `500`.
- **Timeouts serveur** : le push est long ; le handler neutralise les `ReadTimeout`/`WriteTimeout`
  d'`http.Server` via `http.NewResponseController` (`SetReadDeadline`/`SetWriteDeadline` à zéro),
  sinon une diffusion de plusieurs minutes serait coupée.
- **Note « multipart »** : l'énoncé mentionne « multipart ». Pour un flux **continu** unique, un
  corps brut en `Transfer-Encoding: chunked` (`Content-Type: audio/aac`) est plus simple et se pipe
  directement dans `pipe:0`. On accepte le corps en streaming ; la forme brute chunked est la voie
  recommandée pour le MVP.

### 3. Service des fichiers HLS aux auditeurs

Deux routes de lecture, servies depuis `<dir>` de la session (via `http.ServeFile` / `ServeContent`) :

| Méthode | Route | Contenu | Content-Type |
|---|---|---|---|
| `GET` | `/api/streams/{id}/playlist.m3u8` | manifeste courant | `application/vnd.apple.mpegurl` |
| `GET` | `/api/streams/{id}/segments/{name}.ts` | un segment | `video/mp2t` |

- **Visibilité** : réutilise la logique de `GetStream` (flux privé d'un tiers / absent / archivé →
  `404`). `Cache-Control: no-cache` sur le manifeste (il change en continu), cache court sur les
  segments (immuables une fois écrits).
- **Auth auditeur** : `RequireAuth` (JWT), cohérent avec les autres lectures. ⚠️ *caveat* connu :
  certains players HLS natifs passent mal les en-têtes `Authorization` sur les sous-requêtes de
  segments ; si cela bloque la démo, un token de lecture court dans l'URL sera tracé comme suivi
  (hors périmètre STR-70).
- **Anti-traversal** : `{name}` validé strictement (`^seg_\d+\.ts$`), jamais concaténé brut au path.

### 4. Câblage dans la session + arrêt

- `session` porte désormais : le `*exec.Cmd` ffmpeg, son `stdin` (`io.WriteCloser`), et le chemin
  `<dir>`.
- `run(ctx)` : crée `<dir>`, lance ffmpeg, puis **attend** sa fin **ou** `ctx.Done()`. À la sortie :
  ferme stdin, tue le process s'il vit encore, **supprime `<dir>`** (`os.RemoveAll`).
- L'événement SSE `ended` existant (ADR 013 §7) reste le **signal de fin faisant autorité** pour
  l'auditeur ; le manifeste cesse simplement d'être mis à jour. On n'ajoute pas de dépendance à un
  `#EXT-X-ENDLIST` écrit à la volée (un `kill` en cours de flux ne le garantirait pas).

### 5. ffmpeg dans l'image runtime

`apk add --no-cache ffmpeg` dans le **stage runner** du [`backend/Dockerfile`](../../backend/Dockerfile)
(alpine). Le binaire Go reste statique (CGO désactivé) ; ffmpeg est une dépendance **système**
appelée en sous-processus, pas liée au binaire. En dev local sans Docker, ffmpeg doit être présent
dans le `PATH` (`brew install ffmpeg`).

---

## Alternatives considérées

- **Bibliothèque HLS Go pure** (`bluenviron/gohlslib`, `asticode/go-astits`) : muxer MPEG-TS en Go,
  **pas de binaire système**, reste dans l'esprit « binaire statique / zéro dépendance lourde » du
  projet, très testable en process. **Écartée pour le MVP** : nettement plus de code (parsing ADTS,
  gestion PTS/DTS, fenêtre glissante, écriture manifeste) et on **possède les bugs de muxing** —
  exactement la classe de bugs (audio saccadé, timestamps qui dérivent) coûteuse à déboguer sur un
  projet étudiant. Candidate naturelle si on veut plus tard retirer la dépendance système.
- **Muxer MPEG-TS maison (stdlib only)** : contrôle et pureté maximales, mais effort et risque de
  correctness hors budget MVP. Rejetée.
- **RTMP + serveur média externe (nginx-rtmp, MediaMTX)** : rejeté par le CDC (§4.3, pas de RTMP)
  et alourdit l'infra.
- **Transcodage `-c:a aac`** (au lieu de `copy`) : inutile puisque l'entrée est déjà AAC ; ajoute du
  CPU et de la latence. On garde le **remux** `copy`.
- **Segments/manifeste en mémoire** (ring buffer, pas de disque) : impose d'intercepter la sortie
  ffmpeg, ce qui annule la simplicité du `-f hls` vers un répertoire. Rejeté pour le MVP ; le tmp
  dir sur tmpfs offre déjà un stockage volatil et rapide.
- **Ingest routé par `id` + JWT** (titre initial STR-71) : rejeté — le `stream_key` est déjà le
  secret de push exposé au diffuseur (cf. §2 et ADR 013).

---

## Conséquences

### Avantages

- **Correctness quasi gratuite** : ffmpeg est la référence du muxing HLS ; sortie conforme, lue par
  tout player standard (Safari, `hls.js`, `just_audio`).
- **Peu de code Go** : la logique de segmentation tient dans une invocation ; le backend se limite à
  lancer/piloter le process et servir des fichiers. Se greffe sur `LiveSessions` **sans repenser la
  concurrence** (le placeholder `run()` était prévu pour ça).
- **CPU négligeable** (remux `-c:a copy`, pas de transcodage).
- **Chemin le plus court vers une démo qui se lit vraiment.**

### Inconvénients

- **Dépendance système ffmpeg** dans l'image runtime (rompt l'idéal « binaire autonome pur ») et à
  installer en dev local.
- **Un process par session live** : à surveiller (limites de process, zombies) ; l'arrêt s'appuie
  sur `exec.CommandContext` + le pipeline `cancel()` existant.
- **Stockage disque temporaire** par session : nettoyage impératif à l'arrêt (`os.RemoveAll`), sous
  peine de fuite d'espace.
- **Mono-instance** : le tmp dir est local au process — même limite structurelle que le registre
  `LiveSessions` (multi-réplica hors scope, cf. ADR 013 §7).

---

## Références

- [ADR 013](013-domaine-streaming.md) — domaine streaming, cycle de vie du direct (§7), `LiveSessions`.
- [ADR 008](008-architecture-handler-service-repository.md) — handler/service/repository.
- [ADR 012](012-openapi-source-de-verite.md) — OpenAPI source de vérité (mettre à jour `openapi.yaml`
  puis régénérer le client mobile après ajout des routes).
- CDC §4.3 — transport d'ingest HTTP, pas de RTMP, segmentation HLS côté backend.
- STR-70 (moteur HLS) / STR-71 (endpoint de réception, sous-issue).
