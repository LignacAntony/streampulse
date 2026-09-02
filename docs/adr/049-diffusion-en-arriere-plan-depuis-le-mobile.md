# ADR 049 — Diffuser depuis l'arrière-plan : quitter l'application n'est pas la fermer

**Date** : 2026-09-02
**Statut** : Accepté
**Ticket** : STR-XXX

## Contexte

L'[ADR 027](027-capture-microphone-et-push-aac-mobile.md) posait « diffusion au
premier plan uniquement » : dès que l'application n'était plus visible, le micro
était relâché. L'[ADR 048](048-cycle-de-vie-de-la-diffusion-et-relance-d-un-flux.md)
a corrigé le pire de ses effets — le direct n'était plus *terminé* — mais a gardé
la règle : arrière-plan = capture suspendue.

Le test sur appareil a montré que cette règle est simplement fausse du point de
vue du diffuseur. Appuyer sur Home pendant un direct est un geste banal : lire une
note, vérifier un message, changer de morceau. La capture s'arrêtait alors, et
côté auditeur le résultat était pire qu'un blanc :

- pendant l'absence, plus aucun segment n'était produit ;
- au retour, la capture reprenait, et comme les horodatages HLS dérivent du
  **compte de trames ADTS** et non de l'horloge murale, le trou de plusieurs
  secondes n'existait pas dans le média. L'auditeur n'entendait pas un silence,
  il entendait un **saut** — la parole reprenait brutalement là où elle s'était
  arrêtée.

Le diffuseur, lui, ne voyait rien : la tuile affichait toujours « EN DIRECT ».

La demande est explicite, et elle distingue deux gestes que l'ancienne politique
confondait :

| Geste | Attendu |
|---|---|
| Home, changer d'application, verrouiller l'écran | **le direct continue** |
| Balayer l'application depuis les récents (la fermer) | **le direct s'arrête** |

Le second n'est pas négociable non plus : reprendre une diffusion micro sans
action de l'utilisateur, ou la laisser tourner après une fermeture, serait une
capture audio à son insu.

## Décision

### 1. Un service de premier plan Android maintient la capture

Depuis Android 10, l'accès au micro hors premier plan exige un service de premier
plan déclarant `foregroundServiceType="microphone"` ; depuis Android 14, la
permission `FOREGROUND_SERVICE_MICROPHONE` s'y ajoute (`targetSdk` du projet :
36). Sans cela, la capture ne renvoie pas d'erreur : elle renvoie du **silence**,
ce qui est le pire des trois comportements possibles.

Le package `record` embarque déjà ce service (`AudioRecordingService`), activé
par `AndroidRecordConfig(service: AndroidService(...))`. Mais **son manifeste ne
le déclare pas** — il ne porte que la permission `RECORD_AUDIO`. C'est donc à
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

### 2. Le cycle de vie ne distingue plus que « ailleurs » et « fermé »

```
inactive / hidden  → rien
paused             → rien (le service maintient la capture)
detached           → arrêt du direct côté serveur + libération du micro
```

`hidden` reste sans effet, pour la raison de l'ADR 048 : sur le web, un simple
changement d'onglet navigateur le produit, et sur mobile il précède toujours
`paused`.

L'arrêt sur `detached` est **best-effort** — le processus est en train de mourir,
la requête peut ne pas partir. Le bail d'ingest du serveur
(`INGEST_RECONNECT_GRACE_SECONDS`, 45 s) reste le filet, et `stopWithTask`
garantit que la capture, elle, cesse immédiatement.

### 3. La machinerie de suspension/reprise disparaît

`suspendForBackground` / `resumeFromBackground`, ainsi que l'URL d'ingest
mémorisée et l'énumération `BroadcastResumeOutcome` introduites par l'ADR 048,
n'ont plus d'objet : il n'y a plus rien à suspendre, donc plus rien à reprendre.
Le code net **rétrécit**.

Une reprise automatique au **redémarrage de l'application** a été prototypée puis
retirée : adopter un direct encore vivant côté serveur rallumait le micro sans
action de l'utilisateur. Un direct qu'on relance à son insu en rouvrant
l'application est un défaut, pas une fonctionnalité.

### 4. Un conflit d'ingest n'est pas une panne

Ajouté au passage, parce que la reprise le rendait atteignable :
`IngestConflictException` traduit le **409** de l'ingest. Le publisher cesse alors
de réessayer, au lieu d'épuiser ses six tentatives puis de passer à `failed` —
ce qui, via l'invariant « jamais de live silencieux » de l'ADR 027, aurait
**terminé le direct de l'encodeur externe** qui alimentait légitimement ce flux.

## Conséquences

- Le diffuseur peut quitter l'application, verrouiller son écran et continuer à
  parler. C'est la fonctionnalité attendue d'une application de diffusion.
- Une notification permanente s'affiche pendant toute la diffusion. Non
  supprimable : c'est le prix système de l'accès micro en arrière-plan, et c'est
  souhaitable.
- Fermer l'application coupe le direct — immédiatement pour la capture, sous 45 s
  pour le statut serveur si l'appel `detached` n'a pas eu le temps de partir.
- **iOS n'est pas vérifié.** `UIBackgroundModes: audio` est déjà déclaré et
  couvre en principe la capture, mais aucun appareil iOS n'était disponible au
  moment de ce changement. À valider avant toute distribution iOS.
- L'ADR 027 reste en vigueur sur l'encodage AAC/ADTS, les permissions et la
  reprise réseau ; seule sa politique de premier plan est remplacée. L'ADR 048
  garde ses parties 2 et 3 (relance d'un flux terminé, `hidden` inerte) ; sa
  partie 1 est remplacée ici.

## Alternatives écartées

**Garder la suspension et masquer le saut côté auditeur.** Il aurait fallu
injecter du silence dans le flux pendant l'absence pour que les horodatages
suivent l'horloge murale. On aurait payé un traitement serveur permanent pour
livrer à l'auditeur… un blanc — que l'utilisateur ne voulait pas davantage que le
saut. Le vrai besoin n'était pas de mieux présenter l'interruption, c'était de ne
pas interrompre.

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
