# Performance de l'application mobile — preuves de fluidité

**Ticket** : [STR-243](https://linear.app/streampulse/issue/STR-243) · **Dernier relevé** :
2026-08-21 · **Décision associée** : [ADR 043](adr/043-accessibilite-de-l-application-et-adaptation-aux-largeurs.md)
pour l'adaptation aux largeurs, [ADR 034](adr/034-lecture-dune-playlist-avec-file-dattente.md)
et [ADR 023](adr/023-lecteur-audio-hls-mobile.md) pour le lecteur.

Le sujet demande une **preuve** de la fluidité de l'interface à 60 images par seconde. Ce
document la produit, et dit ce qu'elle vaut.

---

## 1. Ce qu'on mesure, et pourquoi à deux endroits

Une trame à 60 FPS dispose de **16,67 ms**. Ce budget se dépense en deux phases, sur deux fils
d'exécution différents :

| Phase | Fil | Ce qui s'y passe | Ce qui la fait déborder |
|---|---|---|---|
| **build** | UI (Dart) | reconstruction de l'arbre de widgets | trop de widgets reconstruits pour rien |
| **raster** | raster (Impeller/Skia) | rastérisation de la scène | trop de couches, effets coûteux, images non redimensionnées |

D'où **deux mesures complémentaires**, aucune ne remplaçant l'autre :

- `mobile/test/performance/rebuild_budget_test.dart` — **sans appareil, dans la CI**, à chaque
  PR. Vérifie la *cause* : qu'un flux haute fréquence ne reconstruit que le widget qui
  l'affiche. Ne voit rien de la rastérisation.
- `mobile/integration_test/frame_budget_test.dart` — **sur appareil, à la main**. Mesure les
  temps réels de build et de raster. Ne peut pas tourner dans la CI (pas d'appareil).

⚠️ Sous `flutter test`, **le temps est simulé et rien n'est rastérisé** : `tester.pump(Duration)`
n'avance qu'une horloge fictive. Un « budget de trame » vérifié là serait une fiction. C'est
toute la raison du second fichier — et de son détour par `flutter drive`, `flutter test` ne
connaissant pas `--profile`.

⚠️ Et une mesure en **mode debug** ne prouve rien non plus : le code Dart y est interprété par
le JIT sans optimisation, et les temps de construction y sont couramment plusieurs fois ceux du
binaire livré. `make frame-budget` impose `--profile`.

---

## 2. La discipline qui produit la fluidité

Elle est écrite dans CLAUDE.md et appliquée dans le code : **un flux haute fréquence ne traverse
jamais un `ChangeNotifier` app-level.**

Position de lecture, niveau audio, chronomètre d'écoute émettent plusieurs fois par seconde. Les
faire passer par `notifyListeners()` sur un contrôleur app-level reconstruirait **tout l'arbre
sous ce contrôleur** à cette cadence — y compris une liste en cours de défilement, puisque le
bandeau du lecteur et l'écran courant vivent sous les mêmes providers (`app_providers.dart`).

Trois règles en découlent, chacune matérialisée dans le code :

1. **Le contrôleur expose le `Stream` tel quel**, le widget qui l'affiche s'y abonne seul.
   `queue_progress.dart` (STR-230) pour l'avancement, `VolumeSlider` (STR-244) pour le volume.
2. **Un seul abonnement, posé à la construction** — jamais un `StreamBuilder` reconstruit. Un
   getter de `Stream` rend souvent un objet neuf à chaque accès (`StreamController.stream` le
   fait) : un `StreamBuilder` s'y réabonnerait à chaque reconstruction. Sans conséquence sur un
   flux continu, **fatal** sur un flux qui n'émet qu'une fois — la durée d'une piste serait
   perdue et la barre resterait muette.
3. **Le tic local reste local.** `ListeningTime` bat une fois par seconde dans son propre
   `State` ; le cumul, lui, vit dans le contrôleur app-level parce que la lecture survit à la
   navigation (ADR 042).

Le point 1 est ce que la garde CI vérifie.

---

## 3. Garde sans appareil — budget de reconstruction (CI)

```bash
cd mobile && flutter test test/performance/rebuild_budget_test.dart
```

Quatre cas, dont deux existent uniquement pour empêcher un vert vide :

| Test | Ce qu'il établit |
|---|---|
| 60 positions ne reconstruisent aucun observateur du contrôleur | La règle elle-même : une seconde de lecture à la cadence réelle (~16 ms) laisse à **0** le compteur de reconstructions d'un widget qui `watch` le contrôleur app-level |
| …mais la barre d'avancement, elle, a bien avancé | **Anti-vacuité** : sans lui, le test précédent passerait aussi si les positions n'étaient jamais délivrées |
| la sonde détecte bien une reconstruction quand il y en a une | **Test de contrôle** : un changement de piste (`emitIndex`) *doit* notifier, et la sonde le voit. Sans lui, on ne saurait pas si la sonde compte quelque chose |
| le curseur manipulable de la file suit la même règle | Le point le plus exposé : le `Slider` affiche la position **et** accepte un glissement |

La sonde est un widget qui appelle `context.watch<PlaylistQueueController>()`. Elle tient la
place de tout ce qui observe réellement ce contrôleur dans l'application — `PlayerBar`,
`QueueMiniPlayer`, l'écran de détail d'une playlist — et donc, par ricochet, de tout ce qui se
reconstruirait avec eux.

**Résultat : 4/4, compteur à 0 reconstruction sur 60 émissions.**

Ce que cette garde *n'établit pas* : rien sur la rastérisation, rien sur le coût réel d'une
trame. C'est l'objet de la section suivante.

---

## 4. Mesure sur appareil — temps de trame réels

```bash
flutter devices                          # relever l'identifiant
make frame-budget DEVICE=<id>
```

**Appareil** : Samsung Galaxy S20 Ultra 5G (SM-G988B), Android 13, arm64-v8a, dalle adaptative
48–120 Hz. **Mode** : `--profile` (binaire optimisé, AOT). **Run** : 2026-08-21.

Deux scénarios, choisis parce que ce sont ceux où le jank apparaîtrait :

### 4.1 Défilement de « Découvrir » **pendant une lecture**

Une liste de 60 `StreamTile` reçoit six `fling` successifs pendant qu'un `positionStream`
alimente `QueueProgressLine` toutes les 16 ms — la cadence réelle du lecteur.

| | p50 | p95 | max | Budget 60 FPS |
|---|---:|---:|---:|---|
| **build** (fil UI) | 1,17 ms | **3,00 ms** | 5,29 ms | 16,67 ms ✅ |
| **raster** | 3,40 ms | **6,89 ms** | 22,44 ms | 16,67 ms ✅ |

354 trames relevées, **1 hors budget (0,3 %)**.

### 4.2 Glissement du curseur de la file d'attente

Quatre glissements de 20 pas sur le `Slider` de `PlaybackQueueSheet`, positions du lecteur
continuant d'arriver pendant que le doigt est posé.

| | p50 | p95 | max | Budget 60 FPS |
|---|---:|---:|---:|---|
| **build** (fil UI) | 2,25 ms | **4,13 ms** | 6,16 ms | 16,67 ms ✅ |
| **raster** | 2,69 ms | **4,41 ms** | 5,00 ms | 16,67 ms ✅ |

123 trames relevées, **0 hors budget**.

### Lecture

Le p95 de build tient dans **moins d'un quart** du budget, celui de raster dans moins de la
moitié. La marge est telle que la conclusion **ne dépend pas de la fréquence de la dalle** : la
dalle de cet appareil est adaptative (48 à 120 Hz), et les deux p95 passent aussi le budget de
120 Hz (8,33 ms). Le résultat n'est donc pas un artefact d'un rafraîchissement à 60 Hz qui aurait
laissé du mou.

Le seul dépassement — une trame de raster à 22,44 ms sur 354 — tombe pendant le défilement. Sa
cause n'est **pas** établie : les dix trames de préchauffage écartées ne couvrent ni un passage
du ramasse-miettes, ni la première rastérisation d'une tuile qui entre à l'écran en cours de
`fling`. Une trame isolée à 0,3 % n'est pas perceptible ; c'est noté ici parce qu'un tableau qui
n'affiche que des ✅ n'apprend rien à personne.

Point notable : la phase **build** est plus coûteuse au curseur (2,25 ms) qu'au défilement de la
liste (1,17 ms), alors que le second construit bien plus de widgets. C'est cohérent avec la
section 2 — le défilement ne reconstruit que les tuiles qui entrent à l'écran, et surtout **pas**
l'arbre du lecteur, tandis que le curseur reconstruit son sous-arbre à chaque trame par
construction. La discipline se lit dans les chiffres.

---

## 5. Limites assumées

- **Un seul appareil, un seul run.** Les chiffres ci-dessus décrivent ce matériel-là. Un
  téléphone d'entrée de gamme rastériserait plus lentement ; la garde CI de la section 3, elle,
  est indépendante du matériel.
- **Des scénarios reconstitués, pas l'application entière.** Les deux scénarios montent les
  vrais widgets (`StreamTile`, `QueueProgressLine`, `QueueProgressSlider`, le vrai
  `PlaylistQueueController`) avec un lecteur simulé, plutôt que de lancer l'application complète
  contre une API. C'est ce qui les rend rejouables sans backend — et ce qui les empêche de voir
  un jank qui viendrait d'ailleurs (chargement d'images distantes, par exemple : l'application
  n'affiche aujourd'hui aucune vignette de flux).
- **Les dix premières trames sont écartées** de chaque relevé : la première rastérisation d'un
  widget compile ses shaders, coût qui ne se reproduit pas en régime permanent.
- **Pas dans la CI.** GitHub Actions n'a pas d'appareil. La mesure reste manuelle et datée ;
  c'est la garde de reconstruction qui tient la ligne entre deux relevés.
