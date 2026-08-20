# ADR 036 — `provider` plutôt que Riverpod pour le state management Flutter

**Date** : 2026-08-19
**Statut** : Accepté — **remplace ([supersedes](005-architecture-flutter-clean.md)) l'ADR 005 sur le seul volet state management**
**Ticket** : [STR-237](https://linear.app/streampulse/issue/STR-237)

---

## Contexte

L'[ADR 005](005-architecture-flutter-clean.md) (2026-05-04, STR-92) retenait **Riverpod**
(`flutter_riverpod` + `riverpod_annotation`) comme solution de state management, et écartait
explicitement le package `provider`. L'application a réellement été écrite ainsi pendant un mois :
inscription, connexion et réinitialisation de mot de passe ont été livrées avec des
`AsyncNotifier`, un `ProviderScope` racine et des `ConsumerWidget`.

**L'équipe pédagogique a ensuite interdit Riverpod** : le référentiel demande de démontrer la
maîtrise des mécanismes de state management, pas celle d'un framework qui les encapsule.

La migration a eu lieu le **2026-06-04** (`8e912ec`, *refactor(mobile): remplacer Riverpod par
provider*) et a touché toute la couche présentation :

| Avant (Riverpod) | Après (`provider`) |
|---|---|
| `ProviderScope` | `MultiProvider` (`StreamPulseApp`, `app/app_providers.dart`) |
| `AsyncNotifier<T>` | `ChangeNotifier` + résultat renvoyé par le `Future` |
| `ConsumerWidget`, `ref.watch` / `ref.read` | `context.watch<T>()` / `context.read<T>()` |
| `ref.listen` | `await` dans le callback de l'écran (cf. [ADR 011](011-reinitialisation-mot-de-passe-flutter.md) §3) |
| `routerProvider` | fonction `createAppRouter(storage)` |
| `auth_providers.dart` (DI par feature) | `app/app_providers.dart` (DI centralisée) |

Le code a suivi, la documentation non. Un premier passage
(`a871c93`, 2026-06-13) a corrigé `architecture.md`, `docs/README.md`, `CLAUDE.md` et
`mobile/README.md` — mais **aucune ADR**. Deux mois plus tard, l'ADR 005 affirme toujours que le
projet utilise Riverpod, les ADR 009 et 011 raisonnent sur des détails d'implémentation de
Riverpod 2.x, et il n'existe nulle part de trace du *pourquoi*.

État réel du code aujourd'hui : `mobile/pubspec.yaml` déclare `provider: ^6.1.2` et **aucune**
dépendance Riverpod ; aucun `AsyncNotifier`, `ProviderScope`, `ref.watch` ni `ref.invalidate`
n'existe dans `mobile/lib/`.

Cette ADR acte la décision, en explique le motif, et **assume son coût** plutôt que de réécrire
l'ADR 005 : l'historique décisionnel — y compris les décisions révisées — fait partie de ce que
le dossier doit montrer.

---

## Décision

**Le state management de l'application Flutter repose sur le package `provider`
(`ChangeNotifier` + `context.watch` / `context.read`). Riverpod n'est pas utilisé.**

### 1. Motif : une contrainte pédagogique, pas un revirement technique

Riverpod n'a pas été écarté parce qu'il serait moins bon que `provider` — l'analyse de l'ADR 005
reste valable sur le fond. Il a été écarté parce que **le cadre d'évaluation l'interdit**.

La contrainte est cohérente avec l'esprit du référentiel : `provider` expose directement
l'`InheritedWidget` et la mécanique d'abonnement de Flutter, là où Riverpod construit son propre
graphe de dépendances au-dessus. Sur un projet évalué sur la compréhension de l'architecture,
travailler une couche plus bas est défendable — et c'est cohérent avec le reste du projet, qui
refuse déjà les frameworks côté backend (stdlib `net/http` sans Gin/Echo, tests sans testify).

### 2. Une échelle de choix, du plus simple au plus lourd

`provider` n'est pas appliqué uniformément : la règle est de prendre **le plus simple qui suffit**.

| Niveau | Outil | Quand |
|---|---|---|
| 1 | `setState` | État local jetable d'un seul widget (`_isLoading`, `_hidePassword`) |
| 2 | `ValueNotifier` + `ValueListenableBuilder` | Une valeur réactive locale, sans reconstruire tout le widget |
| 3 | `ChangeNotifier` + `provider` | État partagé entre plusieurs écrans (session, thème, lecteur audio) |

### 3. Portée d'un contrôleur : app-level seulement quand c'est nécessaire

Deux portées coexistent, et le choix est explicite :

- **App-level** (`MultiProvider` de `app_providers.dart`) pour ce qui doit survivre à la
  navigation : `AudioPlayerController`, `PlaylistQueueController`, `ProfileController`,
  `FavoritesController`, `BroadcasterController`.
- **Local à l'écran** (`ChangeNotifierProvider` posé dans le `build`) pour tout le reste :
  `PlaylistsController`, `PlaylistDetailController`, `AdminUsersProvider`,
  `AdminStreamsProvider`, `UploadTrackController`, `BroadcastNotifier`. C'est
  précisément ce qui évite la fuite d'état entre comptes rencontrée sur les favoris
  ([#266](https://github.com/LignacAntony/streampulse/pull/266)) — à la reconnexion, l'écran est
  reconstruit et le contrôleur repart vierge (cf. [ADR 026](026-domaine-playlists.md) §8).

### 4. Les contrôleurs restent des objets Dart ordinaires

Un contrôleur reçoit ses dépendances par **constructeur** (`LoginController(this._repository)`) et
ne connaît que des **abstractions** du domaine (`AuthRepository`, `AudioPlaybackService`). Il
n'importe ni `provider`, ni Flutter au-delà de `foundation.dart`. Conséquence directe : les tests
l'instancient à la main avec un faux dépôt, sans conteneur ni `ProviderContainer`.

C'est le point où `provider` et Riverpod se valent : l'inversion de dépendances (principe D) vient
de la conception des contrôleurs, pas du conteneur qui les héberge.

### 5. Les flux haute fréquence ne passent pas par un `ChangeNotifier`

Position de lecture, niveau audio, chrono : un `notifyListeners()` à ~5 Hz sur un contrôleur
app-level reconstruit tout l'arbre sous le provider. Ces valeurs sont exposées **telles quelles**
en `Stream` par le contrôleur, et le seul widget qui les affiche s'y abonne
(`queue_progress.dart`, cf. [ADR 034](034-lecture-dune-playlist-avec-file-dattente.md)).

C'est une discipline à tenir à la main : Riverpod l'aurait offerte par construction via
`select`/`family`.

---

## Coût assumé, et comment le projet le compense

| Ce que Riverpod aurait apporté | Coût réel dans le projet | Compensation |
|---|---|---|
| **Invalidations sélectives** (`ref.watch(p.select(...))`) : un widget ne se reconstruit que sur le champ qu'il lit | `notifyListeners()` réveille **tous** les `context.watch` d'un contrôleur | Contrôleurs **petits et nombreux** plutôt qu'un store global ; `Consumer`/`Selector` posés au plus près du widget concerné ; flux haute fréquence sortis du notifier (décision 5) |
| **`ref.invalidate(provider)`** : remise à zéro déclarative d'un état à la déconnexion | Aucun équivalent — l'état d'un contrôleur app-level survit au logout | Méthode **`reset()` explicite** sur les contrôleurs app-level portant de l'état par compte (`BroadcasterController`, `FavoritesController`), appelée dans `_logout()` (`profile_screen.dart`) ; contrôleurs **locaux à l'écran** partout où c'est possible (décision 3), ce qui supprime le problème à la racine |
| **Code generation** (`riverpod_annotation`) : providers typés, moins de boilerplate | Chaque provider est écrit à la main dans `app_providers.dart` | Un **seul** fichier de câblage, lisible d'un coup d'œil — et un fichier généré de moins à régénérer avant de compiler |
| **Détection à la compilation** d'un provider non fourni | `context.read<T>()` d'un type absent échoue **à l'exécution** | Câblage centralisé dans `app_providers.dart` (une omission casse tout de suite, au premier écran) ; tests de widgets qui montent l'arbre réel |
| **Pas de dépendance au `BuildContext`** | `context.read` dans les callbacks impose la règle `if (!mounted) return;` après chaque `await` | Convention documentée dans `CLAUDE.md`, vérifiable en revue et par `flutter analyze` (`use_build_context_synchronously`) |

Le coût est réel mais **borné** : il porte sur le confort et sur des garde-fous que le projet
remplace par de la discipline explicite — pas sur une capacité fonctionnelle manquante.

---

## Alternatives écartées

### Rester sur Riverpod et documenter l'écart

Techniquement le meilleur outil pour ce projet (l'analyse de l'ADR 005 tient toujours), mais
**interdit par le cadre d'évaluation**. Un écart assumé sur un point explicitement cadré ne se
négocie pas contre du confort de développement.

### BLoC / Cubit (`flutter_bloc`)

Autorisé, éprouvé, et il aurait apporté la séparation stricte Événements/États. Écarté pour deux
raisons : la verbosité (un fichier par événement et par état, sur une app qui compte déjà une
vingtaine de contrôleurs), et le fait que la moitié de l'état de l'app est un **flux continu**
(position de lecture, état du lecteur natif) mal servi par un modèle événementiel discret. Le
gain d'architecture n'aurait pas payé le coût d'écriture.

### `InheritedWidget` / `InheritedNotifier` à la main, sans package

C'était l'option la plus « brute », donc la plus démonstrative sur le papier. Écartée parce que
`provider` **est** cette mécanique, empaquetée avec les deux choses qu'on écrirait de toute façon
mal : la gestion du cycle de vie (`dispose` automatique des notifiers) et un `MultiProvider` qui
évite une pyramide d'`InheritedWidget` imbriqués. Réécrire ça à la main aurait produit du code
moins sûr sans rien démontrer de plus.

### Réécrire l'ADR 005 au lieu d'en publier une nouvelle

Le plus rapide : corriger « Riverpod » en « provider » dans l'ADR 005 et clore le sujet. Écarté —
cela effacerait la trace d'une décision réellement prise puis révisée. Une ADR est un journal, pas
une description de l'état courant : **un numéro n'est jamais réutilisé, une décision remplacée
passe en `Superseded`**. C'est aussi la seule façon de faire apparaître *pourquoi* le projet a
dévié, qui est précisément ce que l'exercice évalue.

---

## Conséquences

- **[ADR 005](005-architecture-flutter-clean.md)** passe en `Superseded by 036` **sur le seul volet
  state management**. Le reste de l'ADR 005 (Clean Architecture par feature, `go_router`,
  `just_audio`/`audio_service`, `dio`, `flutter_secure_storage`) **reste en vigueur**.
- Les ADR **009** et **011**, écrites au vocabulaire Riverpod (`AsyncNotifier`, `ref.listen`,
  `ref.invalidate`), sont corrigées pour décrire les contrôleurs réellement livrés ; l'ADR 011 §3
  conserve le raisonnement d'origine en encadré historique — le bug d'état initial qu'elle décrit
  ne se produit pas avec `ChangeNotifier`, et la raison vaut d'être conservée.
- **Aucune** dépendance Riverpod ne doit réapparaître dans `mobile/pubspec.yaml`. La vérification
  tient en une commande :
  ```bash
  grep -rn "riverpod\|ProviderScope\|ref\.watch\|ref\.invalidate" mobile/lib mobile/pubspec.yaml
  ```
- Toute nouvelle feature suit l'échelle de la décision 2 et la règle de portée de la décision 3.

---

## Références

- [ADR 005](005-architecture-flutter-clean.md) — Architecture Flutter (décision d'origine, superseded sur ce point)
- [ADR 009](009-authentification-flutter.md) — Authentification côté Flutter
- [ADR 026](026-domaine-playlists.md) §8 — contrôleur local à l'écran, isolation entre comptes
- [ADR 034](034-lecture-dune-playlist-avec-file-dattente.md) — flux haute fréquence hors `ChangeNotifier`
- `mobile/lib/app/app_providers.dart` — conteneur d'injection racine
- `mobile/lib/features/auth/presentation/providers/login_controller.dart` — contrôleur type
- Linear : [STR-237](https://linear.app/streampulse/issue/STR-237)
