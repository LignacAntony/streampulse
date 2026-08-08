# ADR 031 — Lecture audio en arrière-plan (audio_service)

**Date** : 2026-08-06
**Statut** : Accepté
**Ticket** : [STR-109](https://linear.app/streampulse/issue/STR-109) (US-04-03)

## Contexte

Le lecteur HLS de STR-108 ([ADR 023](023-lecteur-audio-hls-mobile.md)) était volontairement
**scopé à l'écran** : un `AudioPlayer` just_audio créé/détruit avec `StreamPlayerScreen`. L'ADR 023
l'annonçait déjà — « le contrôleur devra être **hissé en service** quand STR-109 arrivera ». Deux
limites en découlaient :

1. quitter l'écran (retour, autre onglet) **détruisait** le player → l'audio s'arrêtait ;
2. verrouiller le téléphone ou mettre l'app en arrière-plan **coupait** le son (iOS suspend un
   `AudioPlayer` sans session active ; Android tue la lecture sans service de premier plan).

`audio_service` était déjà une dépendance choisie ([ADR 005](005-architecture-flutter-clean.md)),
mais **jamais initialisée** : `MainActivity` était un `FlutterActivity` nu et le `<service>` du
manifeste était mal nommé.

## Décision

**Hisser le lecteur en service partagé, au niveau application.** Un unique `AudioPlayer` est hébergé
dans un `AudioHandler` `audio_service` (`StreamAudioHandler`), initialisé une fois dans `main()` via
`AudioService.init(...)` et injecté dans l'arbre. Le lecteur survit ainsi à la navigation et à la
mise en arrière-plan / au verrouillage, et publie une notification + des contrôles écran verrouillé.

### 1. Frontière : `AudioPlaybackService` (DIP)

Le `AudioPlayerController` dépend d'une abstraction étroite `AudioPlaybackService`
(`playerStateStream`, `playbackErrors`, `loadUri`, `play`/`pause`/`stop`), **jamais**
directement de just_audio ni d'audio_service. `StreamAudioHandler` l'implémente côté production ; un
fake léger la remplace dans les tests. Le contrôleur reste donc testable sans plateforme ni device.

### 2. Répartition des responsabilités

- Le **handler** est « bête » : il mappe les événements du lecteur en `PlaybackState` (notification)
  et **transmet** les erreurs au contrôleur — il ne décide pas de la reprise.
- Le **contrôleur** garde tout l'arbitrage STR-118 (reconnexion bornée avec backoff, garde
  `_disposed`, garde `ended` dans `_onPlayerState`). À l'état terminal (`ended`/`error`), il appelle
  `stop()` pour retirer la notification.
- **Ambiguïté du 409** (important) : le manifeste renvoie **409 aussi bien pour un flux terminé que
  pour un flux live dont le manifeste n'est pas encore prêt** (fenêtre de démarrage ~10 s, segments
  HLS de 10 s). Le contrôleur lève l'ambiguïté avec un flag `_hasPlayed` : il ne conclut « terminé »
  immédiatement que si la lecture **avait démarré** (manifeste servi au moins une fois) ; sinon il
  **reconnecte d'abord** (backoff 1+2+4+8 = 15 s) et ne conclut qu'après épuisement. La sonde
  (`isManifestUnavailable`) accepte les <500 via `validateStatus` pour ne pas polluer les logs d'un
  faux « erreur » sur un 404/409 attendu.
- Les **contrôles système** (play/pause/stop de la notif) appellent le handler, dont l'état de
  lecture se propage au contrôleur via `playerStateStream` → l'UI reste synchrone.

### 3. Mini-player

« Survivre à la navigation » impose une surface de contrôle in-app : un mini-player persistant est
posé dans le `MainShell` (entre le contenu de l'onglet et la barre de navigation). Il lit le **même**
contrôleur partagé (titre + diffuseur, play/pause, croix = `stop`), et se masque à l'état `idle`.

### 4. Configuration native

- **Android** : `MainActivity` étend `AudioServiceActivity` ; le manifeste déclare
  `com.ryanheise.audioservice.AudioService` (`foregroundServiceType="mediaPlayback"`) + un
  `MediaButtonReceiver` ; permissions `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_MEDIA_PLAYBACK` /
  `POST_NOTIFICATIONS` (cette dernière requise sur Android 13+ pour afficher la notification média).
- **Contrainte SDK (important)** : `audio_service` 0.18.18 compile en `compileSdk 35` et n'appelle pas
  `startForeground()` sous les règles de service de premier plan d'Android 16 (`targetSdk 36`) → ANR +
  kill en arrière-plan. `targetSdk` est donc **épinglé à 35** (`android/app/build.gradle.kts`) le temps
  que le plugin supporte le SDK 36. À relever quand ce sera le cas.
- **iOS** : `UIBackgroundModes: audio` (déjà présent) suffit avec la session `playback` gérée par
  audio_service.

### 5. Volume délégué au système (modèle Spotify)

Le **slider de volume in-app** de STR-108 (exigé par STR-117) est **retiré** : comme sur Spotify, le
volume est piloté par les **boutons matériels / le volume média de l'OS**. Le lecteur reste au volume
par défaut (1.0) et n'expose plus `setVolume` — supprimé de `PlaybackController`,
`AudioPlaybackService`, du handler et de l'UI. Cela évite un double contrôle (slider vs boutons) et
aligne le comportement sur les apps de streaming. *(Supersède la partie « slider volume » de
l'ADR 023 / STR-117.)*

## Alternatives considérées

- **`just_audio_background`** : plus simple, mais moins de contrôle sur la notification et non
  retenu comme dépendance — `audio_service` était déjà le choix acté (ADR 005).
- **Garder le player scopé + seulement une `AudioSession`** : donnerait l'arrière-plan sur iOS mais
  pas le service de premier plan Android ni les contrôles système, et ne réglerait pas la survie à
  la navigation. Rejeté.
- **Déplacer toute la logique STR-118 dans le handler** : rejeté — coupler la reprise/sonde au
  service isolé compliquerait les tests ; le contrôleur reste le cerveau, le handler le transport.

## Conséquences

- Lecture continue en arrière-plan / écran verrouillé, avec notification et contrôles système, et
  qui survit à la navigation interne (mini-player).
- La lecture ne s'arrête plus « toute seule » en quittant l'écran : l'utilisateur l'arrête via la
  croix du mini-player, la notification, ou en lançant un autre flux.
- **Non vérifiable sur le web** : l'arrière-plan est une fonctionnalité device (iOS/Android) ; à
  valider sur téléphone. Les tests unitaires couvrent le contrôleur et le mini-player.
- `audio_service` est désormais réellement initialisé ; toute future lecture on-demand (playlists)
  réutilisera ce même handler partagé.

## Références

- [ADR 023](023-lecteur-audio-hls-mobile.md) — lecteur HLS scopé (STR-108), qui annonçait ce passage.
- [ADR 005](005-architecture-flutter-clean.md) — Clean Architecture Flutter, choix d'`audio_service`.
- STR-108 (lecteur play/pause/volume) · STR-118 (gestion des erreurs, reprise bornée).
