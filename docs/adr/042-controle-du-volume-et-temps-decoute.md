# ADR 042 — Contrôle du volume dans l'application et temps d'écoute d'un direct

**Date** : 2026-08-21
**Statut** : Accepté
**Ticket** : [STR-244](https://linear.app/streampulse/issue/STR-244/completer-le-lecteur-linterface-et-les-metriques-manquantes-du-bareme)

---

## Contexte

Le sujet énumère quatre éléments du « Lecteur Audio Avancé » : gestion du
streaming, **barre de progression**, **contrôle du volume**, lecture en arrière-plan.
Deux étaient acquis, deux manquaient.

Le code documentait d'ailleurs l'absence du volume comme un choix
(`audio_player_controller.dart` : « le volume est délégué au système, boutons
matériels — pas de contrôle in-app »). L'arbitrage se défend en général : les
boutons matériels existent, et un second réglage peut dérouter. Mais le sujet le
liste nommément, et l'argument « le système le fait » ne tient qu'à moitié —
baisser le volume système baisse aussi les notifications et les appels, alors
qu'un auditeur veut souvent baisser *la radio*, pas son téléphone.

---

## 1. Le volume appartient au transport, pas au contrôleur

`PlaybackTransport` gagne `volume`, `volumeStream` et `setVolume`. Le curseur
s'y abonne **directement** ; il ne passe pas par `AudioPlayerController` ni par
`PlaylistQueueController`.

C'est la règle déjà posée pour la position de lecture (STR-230,
`queue_progress.dart`) : un glissement émet des dizaines de valeurs par seconde,
et les faire transiter par le `notifyListeners` d'un contrôleur app-level
reconstruirait tout l'arbre sous lui à cette cadence.

Le placer sur le **transport** et non sur l'une des deux interfaces dérivées a
une seconde conséquence, utile : le même curseur sert le direct et la file
d'attente. Le volume ne dépend pas de ce qu'on écoute.

`app_providers.dart` expose donc un `Provider<PlaybackTransport>` pointant sur
le même objet que les deux autres — le curseur dépend de l'interface la plus
étroite qui porte ce dont il a besoin (principe I).

---

## 2. Le réglage de l'auditeur est la source de vérité, l'atténuation en dérive

L'atténuation d'une interruption transitoire (ducking, [ADR 033](033-gestion-des-interruptions-audio.md))
et le réglage de l'auditeur sont deux choses différentes. Le lecteur n'en connaît
qu'une : son volume courant.

La version précédente **capturait** `player.volume` juste avant d'atténuer, pour
le restaurer ensuite. C'était correct tant que personne ne pouvait régler le
volume. Depuis qu'un curseur existe, ce schéma a un défaut net : un réglage fait
**pendant** l'interruption est écrasé à la restauration — l'auditeur baisse le
son pendant sa notification, et le son remonte tout seul quand elle se termine.

[`VolumeLevel`](../../mobile/lib/core/audio/volume_level.dart) inverse la
dépendance : le réglage est conservé, l'atténuation est un **facteur** appliqué
par-dessus, et le niveau envoyé au lecteur en dérive.

| | Réglage auditeur | Envoyé au lecteur |
| -- | -- | -- |
| Normal | 0,8 | 0,8 |
| Atténué | 0,8 | 0,32 |
| Réglé pendant l'atténuation | 0,3 | 0,12 |
| Atténuation levée | 0,3 | **0,3** |

Un **facteur** et non un niveau absolu : atténuer à 0,4 en dur *remonterait* le
son de quelqu'un qui écoute à 0,2.

`volumeStream` publie le **réglage**, jamais le niveau effectif : sinon le
curseur sauterait à chaque notification reçue, ce qui se lit comme un bug.

Objet **pur**, comme `InterruptionPolicy` et `PlaybackOrder` : c'est la seule
règle non triviale de tout ce ticket, et elle se vérifie sans lecteur.

---

## 3. Persistance dans `shared_preferences`, pas dans `SecureStorage`

`SecureStorage` n'a qu'une responsabilité — les jetons JWT — et un niveau sonore
n'est ni un secret ni quelque chose qu'on veut chiffrer. Le mélanger y aurait
élargi la seule classe du projet dont la surface doit rester close.

Une abstraction `VolumeStore` sépare le contrat de l'implémentation (principe D),
ce qui permet aux tests de tourner sans plugin de plateforme.

**Le réglage s'applique en continu, ne s'enregistre qu'une fois** : `onChanged`
applique (l'auditeur doit entendre pendant qu'il glisse), `onChangeEnd`
enregistre. Écrire à chaque tick userait le magasin pour un résultat identique.

Le niveau est restauré **avant le premier rendu**, dans `main()`. Le retrouver
après coup ferait démarrer la lecture au volume par défaut puis sauter — et cela
s'entend. La restauration est best-effort, comme la configuration de la session
audio : un magasin indisponible ne doit pas empêcher l'application de démarrer.

---

## 4. Un direct n'a pas de barre de progression, il a un temps d'écoute

Le sujet demande une barre de progression. Un direct n'a pas de fin connue :
il n'y a pas de fraction à remplir, et une barre qui n'avance jamais serait un
mensonge visuel. Ce que l'auditeur peut vouloir savoir, c'est depuis combien de
temps il écoute.

### Pourquoi pas `positionStream`

`just_audio` expose une position sur un flux HLS, et l'afficher aurait coûté une
ligne. Mais cette position est relative à la **source chargée**, et le contrôleur
recharge l'URL à chaque reprise après erreur (reconnexion bornée, STR-118). Une
coupure réseau de deux secondes remettrait donc le compteur à zéro, sous un
libellé qui promet « depuis le début de l'écoute ».

[`ListeningClock`](../../mobile/lib/core/audio/listening_clock.dart) est pilotée
par l'**état de lecture** et non par la source : elle traverse les rechargements.
C'est la seule façon de tenir la promesse du libellé.

Elle se met en pause **pendant une reconnexion** : c'est précisément le moment
où l'auditeur n'entend rien, et laisser courir un compteur sur du silence
surestimerait ce qu'il a réellement écouté.

Objet pur là encore : l'appelant fournit l'instant, ce qui rend le comportement
vérifiable sans attendre. Le widget qui l'affiche reçoit sa source de temps en
paramètre injectable — `tester.pump(Duration)` n'avance que l'horloge simulée de
Flutter, un `DateTime.now()` en dur aurait rendu tout le fichier invérifiable.

Le tic bat **une fois par seconde et localement au widget** : rien au-dessus ne
se reconstruit, et il s'arrête dès que l'horloge est suspendue.

---

## Conséquences

**Positives**

- Le volume se règle dans l'application, indépendamment du volume système.
- Un réglage fait pendant une interruption survit à celle-ci.
- Le niveau est retrouvé d'une session à l'autre.
- Un direct affiche un temps d'écoute qui résiste aux reconnexions.
- Aucun flux haute fréquence n'a été ajouté à un `ChangeNotifier` app-level.

**Négatives, assumées**

- Une dépendance de plus (`shared_preferences`), pour un seul réglage
  aujourd'hui.
- Le curseur n'est pas exposé aux commandes système (notification, écran
  verrouillé) : `audio_service` ne relit pas cet état, il dériverait.
- Le temps d'écoute compte le temps de **lecture**, pas le temps passé sur
  l'écran : mettre en pause le fige. C'est voulu, mais quelqu'un peut s'attendre
  à l'inverse.
- Deux widgets tests de plus dépendent des providers `PlaybackTransport` et
  `VolumeStore` — trois harnais existants ont dû les fournir.

---

## Alternatives écartées

**Garder « le volume est délégué au système ».** L'arbitrage d'origine, et il se
défend. Écarté parce que le sujet nomme le contrôle du volume comme un critère,
et parce que baisser le volume système baisse aussi les notifications.

**Faire passer le volume par un `ChangeNotifier` app-level.** Le plus court à
écrire. Écarté pour la raison déjà donnée en STR-230 : un flux qui émet des
dizaines de fois par seconde reconstruirait tout l'arbre sous le contrôleur.

**Capturer le volume avant d'atténuer** (schéma d'origine). Écarté : un réglage
fait pendant l'interruption serait écrasé à sa levée.

**Afficher `positionStream` sur le direct.** Une ligne. Écarté : la position se
remet à zéro à chaque rechargement de source, donc à chaque reconnexion.

**Un chronomètre du temps passé sur l'écran plutôt que du temps de lecture.**
Écarté : l'écran plein n'est pas l'écoute — la lecture survit à la navigation
(ADR 031), et le mini-player continue ailleurs.

**Stocker le volume dans `SecureStorage`.** Aucune dépendance à ajouter.
Écarté : cette classe n'a qu'une responsabilité, et un volume n'est pas un
secret.

---

## Références

- [ADR 023 — Lecteur audio HLS mobile](023-lecteur-audio-hls-mobile.md)
- [ADR 031 — Lecture audio en arrière-plan](031-lecture-audio-en-arriere-plan.md)
- [ADR 033 — Gestion des interruptions audio](033-gestion-des-interruptions-audio.md) — le ducking dont dérive `VolumeLevel`
- [ADR 034 — Lecture d'une playlist avec file d'attente](034-lecture-dune-playlist-avec-file-dattente.md) — `PlaybackTransport` et ses interfaces dérivées
- [ADR 036 — State management Flutter](036-state-management-flutter-provider.md) — la règle sur les flux haute fréquence
