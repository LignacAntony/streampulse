# ADR 022 — Lecteur audio HLS mobile (just_audio)

**Date** : 2026-07-27
**Statut** : Accepté
**Ticket** : [STR-108](https://linear.app/streampulse/issue/STR-108) (sous-issues STR-116 moteur, STR-117 UI, STR-118 erreurs, STR-119 tests)

---

## Contexte

STR-108 (« US-04-02 : Lecteur audio HLS play/pause/volume ») : en tant qu'auditeur, écouter un flux
live HLS avec des contrôles, démarrage < 3 s, rebuffering < 2 %. Le backend sert un **manifeste HLS
public** (`GET /api/streams/{id}/playlist.m3u8` + segments), sans authentification pour les flux
publics ([ADR 015](015-moteur-hls-segmentation-ffmpeg.md) révisé par STR-108). L'app Flutter a déjà
`just_audio` + `audio_session` déclarés, la découverte des flux (STR-107) et une route
`/stream/:id` vers un écran player (jusqu'ici un placeholder).

---

## Décision

### 1. Lecture HLS déléguée à **just_audio**

Le package `just_audio` s'appuie sur les players natifs (AVPlayer iOS / ExoPlayer Android) qui gèrent
HLS nativement. Pas de moteur maison, pas de parsing manuel du `.m3u8`.

### 2. URL du manifeste **passée directement** (pas le client généré)

Le player reçoit `AudioSource.uri(Uri.parse('{baseUrl}/api/streams/{id}/playlist.m3u8'))` :

- Le `streamPlaylist` **généré** (openapi-generator) renvoie `Future<Response<String>>` : il
  **bufferise** la réponse → inutilisable pour du streaming. On construit donc l'URL à la main
  (`ApiConstants.hlsPlaylist(id)`).
- **Aucun en-tête `Authorization`** : la lecture est publique (ADR 015 révisé). Conséquence directe :
  marche iOS **et** Android uniformément, et **pas d'expiration de token** en cours d'écoute (le player
  natif ne saurait pas rafraîchir un JWT).

### 3. `AudioPlayerController` (ChangeNotifier), scopé à l'écran

Un `ChangeNotifier` enveloppe l'`AudioPlayer` et expose un état applicatif
(`loading` / `buffering` / `playing` / `paused` / `ended` / `error`) + `play`/`pause`/`setVolume`/`retry`.
Il est **créé et détruit avec l'écran player** (`dispose()` de l'`AudioPlayer` à la sortie) — pas de
singleton global. Le passage en **service partagé** (lecture qui survit à la navigation) relève de la
**lecture en arrière-plan, STR-109** (US-04-03) via `audio_service`, hors périmètre ici.

### 4. Spécificités **live** dans l'UI (STR-117)

Un flux live n'a **pas de durée fixe ni de seek** : on remplace la barre de progression du design par
un **badge « EN DIRECT »** + le **temps écoulé** depuis `started_at`. Le **volume** est un **slider**
(exigé par STR-117). L'esthétique du design (artwork rond + halo violet, fond sombre, accent violet
`#6C5CE7`) est conservée.

### 5. Fin de flux et erreurs (STR-118)

Quand le diffuseur arrête, la session est récoltée côté backend → le manifeste passe en **409/404** →
le player émet une erreur. Le contrôleur bascule en état **`error` / « flux terminé »** avec un
bouton **réessayer** ; inutile d'écouter le SSE (qui exige un JWT) — la fin se détecte via le statut
HTTP du manifeste.

---

## Alternatives considérées

- **Réécrire un moteur HLS en Dart** : rejeté — `just_audio` + players natifs le font déjà, mieux.
- **Utiliser le `streamPlaylist` généré** : rejeté — il bufferise la réponse (non-streaming).
- **Token de lecture dans l'URL / en-tête `Bearer`** : rejeté — la lecture publique (ADR 015 révisé)
  suffit et évite les soucis d'auth du player natif (iOS) et d'expiration.
- **Contrôleur global singleton** : rejeté pour STR-108 — un player scopé à l'écran est plus simple et
  correct pour la lecture au premier plan ; le partage sera introduit par STR-109.

---

## Conséquences

- **Simple et uniforme** iOS/Android : une URL, aucun header, aucun rafraîchissement de token.
- **Latence de démarrage** : dépend de la taille des segments backend (~10 s) — à valider (STR-119) ;
  tuning du buffer just_audio, voire segments plus courts côté backend si le < 3 s n'est pas tenu.
- **Compteur d'auditeurs** : non fourni par le backend aujourd'hui (`listenerCount` nul) → affiché
  seulement s'il est renseigné ; sinon masqué (suivi backend éventuel).
- Le contrôleur devra être **hissé en service** quand STR-109 (arrière-plan) arrivera.

---

## Références

- [ADR 015](015-moteur-hls-segmentation-ffmpeg.md) — moteur HLS backend (révisé STR-108 : lecture publique).
- [ADR 005](005-architecture-flutter-clean.md) — Clean Architecture Flutter. [ADR 009](009-authentification-flutter.md) — client Dio/auth.
- STR-116 (moteur) · STR-117 (UI) · STR-118 (erreurs) · STR-119 (tests) — sous-issues de STR-108.
