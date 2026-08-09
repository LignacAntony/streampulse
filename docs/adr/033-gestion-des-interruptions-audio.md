# ADR 033 — Gestion des interruptions audio (appels, notifications, casque)

**Date** : 2026-08-09
**Statut** : Accepté
**Ticket** : [STR-110](https://linear.app/streampulse/issue/STR-110) (US-04-04)

## Contexte

US-04-04 : un flux en lecture doit **se mettre en pause à un appel entrant** et **reprendre
automatiquement** à la fin de l'appel. STR-109 ([ADR 031](031-lecture-audio-en-arriere-plan.md)) a posé
le service partagé `StreamAudioHandler` (audio_service + just_audio), mais **aucune `AudioSession`
n'était configurée** et le handler n'écoutait ni les appels ni le débranchement du casque. Sans
session configurée, le focus audio ne se déclenche pas correctement.

`audio_session` (déjà transitif) expose `interruptionEventStream`
(`AudioInterruptionEvent(begin, type)`, `type ∈ {pause, duck, unknown}`) et
`becomingNoisyEventStream` (sortie audio débranchée).

## Décision

Configurer explicitement la session et **gérer les interruptions nous-mêmes**, dans le
`StreamAudioHandler` (il possède le player + la session), via une **politique pure et testable**.

### 1. Session + `handleInterruptions: false`

Le handler configure `AudioSessionConfiguration.music()` au démarrage et crée l'`AudioPlayer` en
**`handleInterruptions: false`** : on ne laisse pas just_audio décider tout seul, la politique est à
nous (explicite et testable, pas de double gestion).

### 2. `InterruptionPolicy` (pure, unit-testable)

Une machine à états **sans dépendance plateforme** décide de l'action
(`pause` / `resume` / `duck` / `unduck` / `none`) :

- **appel / interruption `pause`** pendant la lecture → `pause`, mémorisée ; à la fin → `resume`
  **seulement si c'est nous qui avions mis en pause** (jamais si l'utilisateur avait déjà mis en pause
  avant l'appel) ;
- **notification (`duck`)** → `duck` (baisse le volume à 0.4) puis `unduck` (restaure 1.0) — pas de
  coupure franche pour une interruption transitoire ;
- **casque débranché (`becomingNoisy`)** → `pause`, **sans** reprise automatique (le son ne doit pas
  repartir tout seul sur le haut-parleur).

Le handler ne fait que **traduire** l'action en appel lecteur. La propagation d'état est gratuite :
`pause`/`play` émettent sur `playerStateStream` → le `AudioPlayerController` passe en `paused`/`playing`
→ **mini-player et notification reflètent l'interruption sans code supplémentaire**.

## Alternatives considérées

- **Laisser `handleInterruptions: true` de just_audio tout gérer** : ~3 lignes, correct et idiomatique,
  mais **non unit-testable** (logique dans le plugin) — rejeté au profit d'une politique explicite.
- **Gérer dans le `AudioPlayerController`** : rejeté — la session est une préoccupation de transport
  (handler), pas d'arbitrage applicatif. Le contrôleur reste inchangé.

## Conséquences

- Comportement conforme à l'US, avec en bonus le ducking des notifications et la pause au débranchement
  du casque.
- La **politique** est couverte par des tests unitaires ; le **branchement** session→politique→player
  reste vérifié sur device (un vrai appel entrant ne se simule pas en test).
- Pas de conflit avec le micro diffuseur : écoute et diffusion ne sont jamais simultanées, et `record`
  repose sa propre catégorie de session.

## Références

- [ADR 031](031-lecture-audio-en-arriere-plan.md) — service audio partagé (STR-109), sur lequel ceci
  s'appuie.
- STR-118 — reprise sur erreur réseau (distincte des interruptions de focus, gérée par le contrôleur).
