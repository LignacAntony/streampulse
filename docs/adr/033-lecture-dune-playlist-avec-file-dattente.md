# ADR 033 — Lecture d'une playlist avec file d'attente (queue)

**Date** : 2026-08-09
**Statut** : Accepté
**Ticket** : [STR-133](https://linear.app/streampulse/issue/STR-133) (US-05-04)

## Contexte

À l'issue de l'US-05-03 ([ADR 029](029-pistes-dune-playlist-ajout-retrait-reordonnancement.md)) une
playlist est **ordonnable mais muette** : l'ordre des pistes est persisté, aucune ne peut être
écoutée. L'US-05-01 ([ADR 032](032-domaine-track-upload-audio.md)) a posé l'upload et le stockage
des fichiers, délibérément **hors répertoire servi** — il n'existe donc aucune route capable de
rendre les octets d'une piste.

Côté mobile, l'US-04-03 ([ADR 031](031-lecture-audio-en-arriere-plan.md)) a hissé le lecteur au
niveau application dans un service de premier plan, mais uniquement pour **un flux live** : une
source unique, sans durée, sans notion de « suivante ».

L'US-05-04 demande : enchaînement automatique, file d'attente visible, saut à n'importe quelle
piste, lecture qui continue en arrière-plan.

## Décision

### 1. Backend — `GET /api/tracks/{id}/stream`, propriétaire uniquement

Une route dédiée sert le binaire, plutôt que d'exposer `STORAGE_PATH` en statique :

- **Propriété vérifiée en SQL** (`WHERE id = $1 AND user_id = $2`). Zéro ligne → **404**, jamais
  403 : la piste d'un tiers doit être indiscernable d'une piste inexistante, sinon le code de statut
  révèle l'existence de la bibliothèque d'autrui.
- **`http.ServeContent`** plutôt qu'un `io.Copy` : il gère les requêtes `Range`, dont le lecteur
  audio a besoin pour reprendre ou avancer dans une piste sans la retélécharger.
- **Type MIME issu de la base** (figé à l'upload, déjà validé par sniff) : ServeContent ne le devine
  jamais depuis un nom de fichier, et `X-Content-Type-Options: nosniff` interdit au client d'en
  faire autant.
- **`Cache-Control: private, no-store`** : contenu privé, aucun cache partagé.
- **Fichier absent du volume alors que la ligne existe → 404**, pas 500 : il n'y a rien à servir et
  aucun réessai ne le changera. L'incohérence est journalisée en `error` pour être vue.

Le domaine gagne `Storage.Open` (interface `StoredFile` = `ReadSeeker` + `Closer`) : le stockage
reste une abstraction, un futur stockage objet n'aura qu'à l'implémenter.

### 2. Mobile — un seul lecteur, deux interfaces (ISP)

L'application n'héberge **qu'un** `AudioPlayer` (ADR 031). Direct et file d'attente s'excluent donc
par construction. Plutôt que de gonfler `AudioPlaybackService` de méthodes de file, l'interface est
scindée :

```
PlaybackTransport          play/pause/stop, playerStateStream, playbackErrors
├── AudioPlaybackService   + loadUri            (direct HLS)
└── QueuePlaybackService   + loadQueue, skipToIndex, currentIndexStream
```

`StreamAudioHandler` implémente les deux ; `main()` l'injecte sous ses deux rôles. Chaque contrôleur
ne dépend que de ce qu'il utilise, et un test peut ne simuler qu'un des deux.

### 3. L'enchaînement est délégué au lecteur natif

`ConcatenatingAudioSource` enchaîne et précharge la piste suivante. Le contrôleur applicatif
**n'ordonnance rien** : il s'abonne à `currentIndexStream` et suit. Conséquence importante : un saut
déclenché depuis la notification système ou un casque Bluetooth met à jour la file affichée par le
même chemin qu'un appui dans l'app — une seule source de vérité, donc aucune dérive possible entre
ce qu'on entend et ce qu'on voit.

`ProcessingState.completed` ne survient qu'à la fin de la **dernière** piste : c'est l'état
« file terminée ».

### 4. Arbitrage direct ↔ file

Deux contrôleurs app-level se disputent un lecteur unique. Le câblage est croisé dans
`app_providers` :

- `PlaylistQueueController.play()` appelle `stopLive` (→ `AudioPlayerController.stop`) **avant** de
  charger sa file ;
- `AudioPlayerController.load()` appelle `onTakeOver` (→ `PlaylistQueueController.clear`), qui
  abandonne la file **sans toucher au lecteur** — l'arrêter couperait le direct qui vient de le
  charger.

L'UI suit cet arbitrage : `PlayerBar` (couche `app`, seule légitime à connaître les deux features)
affiche le mini-player de la file quand elle est active, celui du direct sinon. Ni l'un ni l'autre
n'a besoin de savoir que le second existe.

### 5. Authentification du lecteur natif

Contrairement au manifeste HLS (public), le binaire d'une piste est privé : chaque `AudioSource`
porte un en-tête `Authorization`. Or **just_audio ouvre ses propres connexions HTTP** et ne traverse
pas les intercepteurs de `DioClient` — personne ne rafraîchit son token.

D'où :

- `DioClient.refreshTokens()` devient public (même verrou sérialisé que l'intercepteur) ;
- `PlaybackAuth.token({forceRefresh})` fournit l'access token au contrôleur de file ;
- sur un échec de lecture, le contrôleur retente **une** fois après rotation, à la piste courante.
  Une file peut durer plus que les 15 min d'un access token : sans cette reprise, elle casserait au
  milieu. Un second échec devient un état d'erreur explicite — réessayer en boucle ne ferait que le
  masquer.

Le token voyage en en-tête, jamais en paramètre d'URL (il finirait dans les logs d'accès).

### 6. La file est une photo, pas un lien vivant

`PlaylistQueueController` reçoit une **copie** des pistes au lancement. Réordonner ou retirer une
piste dans l'écran de détail ne modifie pas ce qui joue tant que la lecture n'est pas relancée. Le
contrôleur vit au niveau application, l'écran non : le faire suivre imposerait de réconcilier une
mutation d'ordre avec une position de lecture en cours (que devient « piste 3 » si elle passe en
tête ?). L'utilisateur relance quand il veut la nouvelle version.

## Alternatives écartées

| Alternative | Pourquoi non |
|---|---|
| Servir `STORAGE_PATH` en statique (Caddy/`http.FileServer`) | Aucun contrôle de propriété : le chemin est un UUID, mais quiconque l'obtient lit le fichier. L'ADR 032 a mis ces fichiers hors répertoire servi précisément pour ça. |
| URL signée à durée de vie courte (token en query) | Le token atterrit dans les logs d'accès et les caches ; il faudrait signer, vérifier et faire tourner un secret de plus. L'en-tête `Authorization` fait le travail sans nouvelle surface. |
| Une seule interface `AudioPlaybackService` étendue | `loadUri` et `loadQueue` ne concernent jamais le même appelant : le contrôleur de direct hériterait de méthodes de file qu'il n'implémente pas (violation I, et un fake de test devrait les stuber pour rien). |
| Ordonnancer l'enchaînement côté Dart (charger la piste n+1 à la fin de la n) | Blanc audible entre les pistes (pas de préchargement), et un second ordonnanceur à garder en phase avec les boutons de la notification. |
| Deux lecteurs natifs (un live, un file) | Deux sources audibles en même temps, deux notifications, deux sessions audio à arbitrer côté OS. |
| Faire suivre à la file les mutations de l'écran de détail | Impose de définir le comportement de la lecture en cours quand la piste jouée change de place ou disparaît — complexité sans demande dans l'US. |

## Conséquences

**Positives**

- Les pistes uploadées deviennent écoutables ; l'US-05-05 (Shuffle/Repeat, STR-134) n'a plus qu'à
  s'insérer dans `PlaylistQueueController`.
- Les requêtes `Range` rendent la reprise et l'avance dans une piste gratuites côté client.
- Le mode hors ligne (STR-201) pourra remplacer l'URL d'un `QueueItem` par un chemin local sans
  toucher au contrôleur.

**Négatives / limites assumées**

- La file ne suit pas les mutations de la playlist (cf. §6).
- Un échec autre qu'un token périmé n'est pas retenté automatiquement (une seule reprise, volontaire).
- Le serveur lit le fichier depuis le volume local : le passage à un stockage objet demandera une
  redirection ou un proxy, prévu par l'interface `Storage`.
- L'arrière-plan ne se teste que sur device (comme l'ADR 031).

## Références

- [ADR 029](029-pistes-dune-playlist-ajout-retrait-reordonnancement.md) — ordre des pistes
- [ADR 031](031-lecture-audio-en-arriere-plan.md) — lecteur partagé, arrière-plan
- [ADR 032](032-domaine-track-upload-audio.md) — domaine track, stockage des fichiers
