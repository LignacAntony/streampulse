# ADR 035 — Modes shuffle et repeat de la file d'attente

**Date** : 2026-08-12
**Statut** : Accepté
**Ticket** : [STR-134](https://linear.app/streampulse/issue/STR-134) (US-05-05)

## Contexte

L'US-05-04 ([ADR 034](034-lecture-dune-playlist-avec-file-dattente.md)) a posé une file d'attente
qui se joue **une fois, dans l'ordre** : `PlaylistQueueController` suit `currentIndexStream`, et
l'enchaînement appartient au lecteur natif (`ConcatenatingAudioSource`, qui précharge la piste
suivante).

L'US-05-05 demande deux variations sur cet enchaînement : lecture aléatoire, et répétition — d'une
piste ou de toute la file. Toutes deux touchent la même question : **quelle piste vient après
celle-ci**, à laquelle deux acteurs répondent déjà (le lecteur natif pour l'enchaînement
automatique, le contrôleur pour les boutons précédent/suivant et la file affichée).

## Décision

### 1. Le mélange est tiré par le lecteur natif, pas par l'application

just_audio sait mélanger (`setShuffleModeEnabled` + `shuffle()`) et répéter (`LoopMode`). Le
choix de l'ADR 034 — l'ordonnancement appartient au lecteur — est reconduit : l'application règle
les modes et **lit** l'ordre obtenu (`effectiveIndices`), elle ne tire aucune permutation.

Conséquence directe : un enchaînement automatique, un appui dans l'application et un appui sur la
notification système donnent forcément la même piste. Une permutation calculée côté Dart aurait
introduit un second ordre à garder en phase avec celui que le lecteur applique réellement.

`shuffle()` est appelé **avant** l'activation du mode et **après** chaque `loadQueue` :

- avant l'activation, parce qu'il place la piste courante en tête de l'ordre tiré — basculer en
  aléatoire ne coupe donc jamais ce qu'on écoute ;
- après chaque chargement, parce qu'une source neuve arrive avec un ordre de mélange neuf, c'est-à-
  dire naturel : sans ce tirage, relancer une playlist en mode aléatoire la rejouerait dans l'ordre.

**Sauf sur un rechargement subi.** Le lecteur ne tire un ordre que lorsque l'auditeur a demandé
quelque chose : `play()`. Une reprise après erreur ou la relance d'une file terminée rechargent la
source sans que personne ne l'ait demandé, et `loadQueue` reçoit alors l'ordre courant à réappliquer
(`_FixedShuffleOrder`, une `ShuffleOrder` qui rend la permutation qu'on lui donne et ignore les
demandes de mélange). Ce n'est pas un détail de confort : l'access token embarqué dans les
`AudioSource` expire au bout de 15 minutes (ADR 034 §5), donc sans cette conservation la suite
annoncée serait réécrite à ce rythme sur toute écoute un peu longue. Le handler vérifie que l'ordre
reçu est une permutation exacte de la file avant de l'appliquer — à un élément près, il laisserait
des pistes injouables.

### 2. `PlaybackOrder` — un objet pur pour la règle du saut

Un désaccord existe entre just_audio et l'attente d'un auditeur : sous `LoopMode.one`,
`seekToNext()` renvoie la **piste courante**. Le bouton « suivant » ne changerait donc pas de piste
tant que la répétition d'une piste est active — comportement qui se lit comme une panne.

La règle retenue est celle des lecteurs grand public : **`repeat one` ne gouverne que
l'enchaînement automatique**, jamais les sauts manuels. Elle vit dans `PlaybackOrder`
(`core/audio/playback_order.dart`), objet pur et testable comme `InterruptionPolicy`
([ADR 033](033-gestion-des-interruptions-audio.md)) :

```
PlaybackOrder(indices)                     // ordre effectif, index de la file d'origine
  .positionOf(index)                       // rang affiché (« 2/12 »)
  .relative(current, ±1, wrap: repeat all) // piste du saut manuel, ou null
```

Les deux surfaces qui sautent l'utilisent : les boutons de l'application via le contrôleur, ceux de
la notification via `StreamAudioHandler._skipRelative`. Une seule implémentation, donc aucune
divergence possible entre les deux — et une règle testable sans lecteur natif ni plugin.

L'énumération applicative est `QueueRepeatMode` (`off`/`one`/`all`), traduite en `LoopMode` par le
seul handler. Le préfixe `Queue` évite la collision avec le `RepeatMode` que `material.dart`
exporte déjà (animations), qui obligerait sinon chaque widget affichant le mode à renommer un
import.

### 3. Les modes appartiennent au contrôleur, pas au lecteur

Le lecteur natif est partagé avec le direct, qui remet shuffle et loop à zéro en prenant la main
(un live n'a ni file ni fin, et `LoopMode.one` y rejouerait un segment). Si les modes n'étaient
tenus que par le lecteur, écouter un direct puis revenir à une playlist les perdrait sans que rien
ne l'annonce.

`PlaylistQueueController` les porte donc comme état propre et les **réapplique avant chaque
chargement**. Ils survivent aussi à `stop()` : ce sont des préférences d'écoute, pas l'état d'une
file. Ils ne survivent en revanche pas au redémarrage de l'application (aucune persistance —
l'US ne la demande pas, et la préférence est à un tap).

### 4. La file affichée montre l'ordre de lecture

`PlaybackQueueSheet` liste les pistes dans l'ordre où elles seront jouées, et le « n/total » du
mini-player compte le rang dans cet ordre. Afficher l'ordre de la playlist pendant une lecture
aléatoire annoncerait une suite qui n'arrivera pas.

Le contrôleur photographie cet ordre (`_refreshOrder`) après chaque chargement et chaque bascule,
plutôt que de le relire à la volée : l'UI le parcourt à chaque frame, et un ordre qui changerait
sans `notifyListeners` afficherait une file désynchronisée du son.

### 5. Points d'entrée

- **Dans la file** (`PlaybackQueueSheet`) : deux boutons libellés — « Aléatoire » et un bouton de
  répétition qui fait défiler *aucune → toute la file → la piste*. Un seul bouton pour trois états
  exclusifs, convention des lecteurs audio. Ils sont libellés et pas seulement colorés : « répéter
  la piste » et « répéter la file » ne se distinguent pas d'une icône.
- **Avant la lecture** (`PlaylistDetailScreen`) : une action « Lire en aléatoire » dans l'AppBar,
  qui démarre sur une piste **tirée au sort** — le lecteur gardant la piste de départ en tête,
  partir systématiquement de la première rendrait un aléatoire qui commence toujours pareil.

Le mini-player ne porte pas ces réglages : 60 px de haut et quatre boutons déjà, et c'est la file
affichée sous les toggles qui rend leur effet lisible.

## Alternatives écartées

| Alternative | Pourquoi non |
|---|---|
| Mélanger la liste côté Dart et charger la file dans cet ordre | Deux ordres à garder en phase (celui affiché, celui du lecteur), et désactiver l'aléatoire imposerait de recharger la source pour revenir à l'ordre naturel — donc une coupure audible. |
| Suivre just_audio jusqu'au bout (`seekToNext`) sous `repeat one` | Le bouton « suivant » rejouerait la piste courante. La notification et l'application partageraient le défaut, ce qui ne le rend pas moins déroutant. |
| Deux boutons de répétition (piste / file) | Trois états exclusifs sur deux interrupteurs : il faut interdire la combinaison des deux, pour un gain de clarté nul. |
| Tenir les modes dans le lecteur uniquement | Le direct les remet à zéro en prenant le lecteur partagé ; la préférence disparaîtrait sans raison visible. |
| Exposer shuffle/repeat aux commandes système (Android Auto, casque) | `audio_service` sait les publier, mais un basculement venu du système ne remonterait pas au contrôleur, qui tient l'état : l'application afficherait un mode et le lecteur en appliquerait un autre. Écarté tant que l'état n'est pas relu depuis le lecteur. |
| Persister les modes entre deux lancements | Hors US ; une préférence à un tap ne justifie pas encore un stockage. |

## Conséquences

**Positives**

- L'enchaînement reste piloté par un seul acteur : ce qu'on entend, ce que la file affiche et ce que
  la notification propose ne peuvent pas diverger.
- La règle du saut manuel est une fonction pure, couverte par des tests sans plugin ni device.
- Activer l'aléatoire ne coupe pas la lecture en cours (piste courante gardée en tête).

**Négatives / limites assumées**

- Les modes sont perdus au redémarrage de l'application (§3).
- L'ordre conservé lors d'un rechargement subi (§1) suppose que la file rechargée est bien la même :
  le handler le vérifie (permutation exacte) et retombe sur un tirage neuf sinon, plutôt que de
  jouer un ordre qui ne correspond plus.
- L'ordre de lecture n'est pas exposé aux commandes système : le tableau de bord d'une voiture
  affichera « lecture normale » même en aléatoire.
- Comme en US-05-04, la file reste une **photo** des pistes au lancement : réordonner la playlist ne
  change pas ce qui joue tant qu'on ne relance pas.

## Références

- [ADR 031](031-lecture-audio-en-arriere-plan.md) — lecteur partagé, arrière-plan
- [ADR 033](033-gestion-des-interruptions-audio.md) — politique pure et testable
- [ADR 034](034-lecture-dune-playlist-avec-file-dattente.md) — file d'attente, ordonnancement délégué
