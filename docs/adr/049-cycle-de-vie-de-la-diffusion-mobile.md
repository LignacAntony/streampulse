# ADR 049 — Cycle de vie de la diffusion mobile : quitter l'application n'est pas la fermer

**Date** : 2026-09-02
**Statut** : Accepté
**Ticket** : STR-XXX
**Révise** : la politique de premier plan de l'[ADR 027](027-capture-microphone-et-push-aac-mobile.md)

## Contexte

Trois symptômes rapportés sur la diffusion, qui n'en font qu'un une fois déroulés.

### Le direct se coupait au changement d'onglet

`DashboardScreen` terminait le direct **côté serveur** dès que l'application
n'était plus au premier plan :

```dart
if (state == AppLifecycleState.paused ||
    state == AppLifecycleState.hidden ||     // ← le coupable
    state == AppLifecycleState.detached) {
  unawaited(notifier.stopForBackground());   // → PATCH /api/streams/{id}/stop
}
```

`AppLifecycleState.hidden` n'est pas un passage en arrière-plan. La documentation
Flutter le définit comme « toutes les vues sont masquées » — ce qui, **sur le
web**, inclut un simple changement d'onglet navigateur. Sur iOS et Android il
précède toujours `paused`, donc il n'apportait rien là où il était censé servir,
et il tuait le direct là où il n'aurait rien dû faire.

### Au retour, l'auditeur repartait du premier segment

Conséquence mécanique : `stop` détruit la session, `start` en refabrique une, et
chaque session crée un segmenteur ffmpeg neuf dans un `os.MkdirTemp` neuf.
Mesuré sur la stack locale, en sondant le manifeste toutes les 5 s pendant un
push AAC temps réel :

```
t= 15s  200  MEDIA-SEQUENCE:0  n=1  first=seg_00000
t= 60s  200  MEDIA-SEQUENCE:0  n=6  first=seg_00000
t= 90s  200  MEDIA-SEQUENCE:3  n=6  first=seg_00003
t=150s  200  MEDIA-SEQUENCE:9  n=6  first=seg_00009
```

La numérotation et `EXT-X-MEDIA-SEQUENCE` repartent de zéro à chaque session.
Pour le lecteur de l'auditeur, c'est un manifeste réinitialisé : il recommence au
premier segment. D'où la boucle observée — un bout de son, une attente, le même
bout de son.

### Une fois le direct préservé, l'auditeur entendait un saut

Le direct sauvé, restait la capture. Appuyer sur Home pendant un direct est un
geste banal : lire une note, vérifier un message. La capture s'arrêtait, et le
résultat côté auditeur était **pire qu'un blanc** :

- pendant l'absence, plus aucun segment n'était produit ;
- au retour, comme les horodatages HLS dérivent du **compte de trames ADTS** et
  non de l'horloge murale, le trou de plusieurs secondes n'existait pas dans le
  média. L'auditeur n'entendait pas un silence, il entendait un **saut** — la
  parole reprenait brutalement là où elle s'était arrêtée.

Le diffuseur, lui, ne voyait rien : sa tuile affichait toujours « EN DIRECT ».

La demande est explicite, et elle distingue deux gestes que l'ancienne politique
confondait :

| Geste | Attendu |
|---|---|
| Home, changer d'application, verrouiller l'écran | **le direct continue** |
| Balayer l'application depuis les récents (la fermer) | **le direct s'arrête** |

Le second n'est pas négociable non plus : laisser un micro tourner après une
fermeture, ou en rallumer un sans action de l'utilisateur, serait une capture
audio à son insu.

## Décision

### 1. Le cycle de vie ne distingue que « ailleurs » et « fermé »

```
inactive / hidden  → rien
paused             → rien (le service de premier plan maintient la capture)
detached           → arrêt du direct côté serveur + libération du micro
```

`hidden` ne déclenche plus rien, pour la raison ci-dessus. `paused` non plus :
quitter l'application pendant un direct est un geste normal.

L'arrêt sur `detached` est **best-effort** — le processus est en train de mourir,
la requête peut ne pas partir. Le bail d'ingest du serveur
(`INGEST_RECONNECT_GRACE_SECONDS`, 45 s) reste le filet.

### 2. Un service de premier plan Android maintient la capture

Depuis Android 10, l'accès au micro hors premier plan exige un service de premier
plan déclarant `foregroundServiceType="microphone"` ; depuis Android 14, la
permission `FOREGROUND_SERVICE_MICROPHONE` s'y ajoute (`targetSdk` du projet :
36). Sans cela, la capture ne renvoie pas d'erreur : elle renvoie du **silence**,
ce qui est le pire des trois comportements possibles.

Le package `record` embarque déjà ce service (`AudioRecordingService`), activé par
`AndroidRecordConfig(service: AndroidService(...))`. Mais **son manifeste ne le
déclare pas** — il ne porte que la permission `RECORD_AUDIO`. C'est donc à
l'application de déclarer le service, sinon `startService` échoue silencieusement.

```xml
<service android:name="com.llfbandit.record.service.AudioRecordingService"
    android:foregroundServiceType="microphone"
    android:stopWithTask="true"
    android:exported="false"/>
```

`stopWithTask="true"` est la moitié « fermeture » du contrat : **par défaut un
service de premier plan survit au balayage de l'application**. Sans cet attribut,
le micro continuerait de tourner après que l'utilisateur croit avoir tout fermé.

La notification permanente n'est pas un effet de bord à subir : c'est l'exigence
système, et c'est aussi ce qui rend la diffusion visible et interrompable pendant
qu'on est ailleurs sur le téléphone.

### 3. Un conflit d'ingest n'est pas une panne

`IngestConflictException` traduit le **409** de l'ingest. Le publisher cesse alors
de réessayer, au lieu d'épuiser ses six tentatives puis de passer à `failed` — ce
qui, via l'invariant « jamais de live silencieux » de l'ADR 027, aurait **terminé
le direct de l'encodeur externe** qui alimentait légitimement ce flux.

## Conséquences

- Le diffuseur peut quitter l'application, verrouiller son écran et continuer à
  parler. C'est la fonctionnalité attendue d'une application de diffusion.
- Une notification permanente s'affiche pendant toute la diffusion. Non
  supprimable : c'est le prix système de l'accès micro en arrière-plan.
- Fermer l'application coupe le direct — immédiatement pour la capture
  (`stopWithTask`), sous 45 s pour le statut serveur si l'appel `detached` n'a pas
  eu le temps de partir.
- **iOS n'est pas vérifié.** `UIBackgroundModes: audio` est déjà déclaré et
  couvre en principe la capture, mais aucun appareil iOS n'était disponible au
  moment de ce changement. À valider avant toute distribution iOS.
- L'ADR 027 reste en vigueur sur l'encodage AAC/ADTS, les permissions et la
  reprise réseau ; seule sa politique de premier plan est remplacée.

### Vérification

Sur appareil réel (Galaxy S20 Ultra, Android 13), diffusion depuis le micro,
sonde serveur toutes les 5 s :

```
14:36:48  app_1er_plan=0  seg_00005   ← l'application passe en arrière-plan
14:36:59  app_1er_plan=0  seg_00006
14:37:10  app_1er_plan=0  seg_00007
14:37:21  app_1er_plan=1  seg_00008   ← retour au premier plan
```

Segments produits sans interruption, et **contenant du vrai son**
(`mean_volume` −23,6 dB ; le silence serait à −91 dB). Cette seconde vérification
est celle qui compte : Android rend du silence, pas une erreur, quand le type de
service est mal déclaré.

## Alternatives écartées

**Suspendre la capture en arrière-plan et la reprendre au retour.** C'était la
première correction écrite, et elle a été rejetée en test sur appareil. Elle
préservait bien la session serveur — donc le segmenteur, donc la numérotation des
segments — mais elle ne réglait pas le problème de fond : l'auditeur entendait
toujours un saut, puisque la capture s'était arrêtée. Elle ajoutait par-dessus
une machinerie d'état (URL d'ingest mémorisée, issue de reprise, resynchronisation
avant reprise) pour un résultat que l'utilisateur ne voulait pas. Le vrai besoin
n'était pas de mieux présenter l'interruption, c'était de ne pas interrompre.

**Adopter au démarrage un direct que le serveur tient encore pour vivant.**
Prototypé pour couvrir la mort du processus — l'état de reprise vivant en
mémoire, fermer l'application laissait une tuile « EN DIRECT » que plus rien
n'alimentait. Fonctionnel, puis retiré : un direct qui se rallume tout seul en
rouvrant l'application est un défaut, pas une fonctionnalité, et rallumer un
micro sans action de l'utilisateur est exactement ce qu'il ne faut pas faire.

**Se contenter de retirer `hidden`.** Corrige le web, laisse le mobile intact :
un appel entrant de trente secondes tuait toujours le direct. Le symptôme le plus
visible disparaissait, la cause restait.

**Faire reprendre la numérotation des segments au serveur après un `start`.**
Techniquement possible (réutiliser le répertoire, passer `-start_number`), mais on
paierait la complexité d'un segmenteur à état pour rattraper une session que le
client n'aurait jamais dû détruire.

**Le package `flutter_foreground_task` plutôt que le service de `record`.** Une
dépendance de plus et un service à piloter à la main, pour le même résultat. Le
champ `AndroidRecordConfig.service` est certes `@Deprecated` (« prefer external
package usage ») : c'est une dette assumée et documentée à l'appel, à reprendre
quand `record` le retirera.

**Réutiliser le service de premier plan d'`audio_service`.** Il existe déjà, mais
son type est `mediaPlayback` et il n'est démarré que par la lecture. Un diffuseur
ne lit rien ; il aurait fallu lui faire jouer un silence pour maintenir le
service, et lui déclarer `microphone` en plus. Détourner le service de lecture
pour tenir la capture aurait mélangé deux responsabilités que le reste du code
sépare soigneusement.
