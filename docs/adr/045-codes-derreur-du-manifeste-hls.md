# ADR 045 — Codes d'erreur du manifeste HLS : distinguer « terminé » de « pas encore prêt »

**Date** : 2026-08-25
**Statut** : Accepté
**Ticket** : [STR-229](https://linear.app/streampulse/issue/STR-229)

## Contexte

`GET /api/streams/{id}/playlist.m3u8` rendait exactement la même erreur dans deux
situations qui n'ont rien à voir :

- **flux terminé** — plus aucune session live, `lookup` rend `ok == false` ;
- **flux live en démarrage** — la session existe, mais `os.Stat` échoue : ffmpeg n'a pas
  encore écrit le premier segment (~10 s, la taille d'un segment HLS).

Les deux branches de `serveHLSFile` écrivaient `apperror.Conflict("stream is not live")`.
Le client recevait donc un `409` indistinct — alors que **le serveur, lui, connaissait la
différence** : `ok` valait `false` dans un cas, `true` dans l'autre.

Ce n'était pas une imprécision cosmétique. Les deux cas appellent des conduites **opposées** :
abandonner, ou patienter. Faute de pouvoir trancher, le lecteur mobile s'appuyait sur une
heuristique — le drapeau `_hasPlayed` (ADR 031, PR #282) : ne conclure « direct terminé » que
si la lecture avait déjà démarré, sinon reconnecter d'abord.

Le coût était mesurable. Ouvrir un flux **déjà terminé** depuis une liste Découvrir périmée
déclenchait les quatre reconnexions avec backoff (1+2+4+8) avant d'afficher « Le direct est
terminé » : **~15 s de « Reconnexion… »** pour annoncer une fin que le serveur connaissait dès
la première requête. La revue de la PR #282 l'avait relevée comme une régression d'UX assumée,
faute de pouvoir faire mieux côté client.

## Décision

### 1. Deux codes publics sur le même statut

Le `409` reste — c'est bien un conflit d'état dans les deux cas, et changer le statut casserait
les clients pour un gain nul. C'est le champ `error.code` qui porte la distinction :

| Situation | Code | Nature |
|---|---|---|
| Aucune session live | `stream_not_live` | Définitive — réessayer ne sert à rien |
| Session vivante, manifeste pas encore écrit | `manifest_not_ready` | Transitoire — réessayer a du sens |

Le mécanisme existait déjà et n'a pas eu à être inventé : `apperror.Error.PublicCode`, posé par
`.Coded(...)`, laisse un domaine publier un code métier stable sans connaître le transport —
`Code` continue seul de décider du statut HTTP. Le précédent est `storage_quota_exceeded`
(ADR 032).

### 2. Le segment ne suit pas

`serveHLSFile` prend désormais **deux** erreurs (`notLive`, `notReady`) au lieu d'une, mais
`Segment` leur passe la même valeur. Ses deux causes d'indisponibilité — flux éteint, ou segment
sorti de la fenêtre glissante — appellent la même conduite chez le lecteur : redemander le
manifeste. C'est le manifeste qui portera le verdict.

Uniformiser par symétrie aurait ajouté un code que personne ne lit, sur un endpoint appelé
plusieurs fois par minute et par auditeur. Un test (`TestHandler_Segment_NotLiveAndNotReady
StayIdentical`) fige l'asymétrie pour qu'elle ne soit pas « corrigée » plus tard comme un oubli.

### 3. Côté client : un verdict, plus une heuristique

`ManifestStatus` (`available` / `ended` / `notReady` / `unknown`) remplace le booléen
`isManifestUnavailable`. Le contrôleur applique la décision du serveur au lieu de la reconstituer,
et `_hasPlayed` disparaît.

La sonde devient **systématique** — elle n'était déclenchée que lorsqu'elle était jugée décisive.
C'est une requête HTTP de plus par échec, bornée par le même plafond de reprises, et c'est ce qui
permet le verdict immédiat.

### 4. Le défaut penche vers l'attente

Un `409` dont le code n'est pas reconnu — un backend antérieur à cette décision, un code ajouté
plus tard — est traité comme `notReady`, pas comme `ended`. Seule la fin de direct est reconnue
**explicitement**.

Le choix n'est pas symétrique : se tromper vers l'attente coûte au pire les reconnexions bornées
déjà en place ; se tromper vers la fin couperait un direct en train de démarrer, soit exactement
le bug que cette ADR corrige. On ne le réintroduit pas par le défaut.

### 5. Ce qui ne change pas

- **Tentatives épuisées avec un manifeste toujours pas servi** → toujours `ended`. Un diffuseur
  qui démarre sans jamais pousser d'audio produit cet état ; « terminé » reste le message le plus
  juste pour l'auditeur, et c'est ce que faisait la version précédente.
- **Manifeste servi mais lecture en échec** → toujours `error` : le problème est réseau ou lecteur,
  pas côté direct.
- Le plafond de reprises et le backoff 1/2/4/8 s (STR-118) sont inchangés.

## Conséquences

- Ouvrir un direct terminé depuis une liste périmée affiche « Le direct est terminé »
  **immédiatement**, au lieu de ~15 s de « Reconnexion… ». C'est le gain visé.
- Le contrôleur perd un état (`_hasPlayed`) et un raisonnement conditionnel : il lit un verdict.
- La sonde ne passe **pas** par le client généré, contrairement au reste de la couche data.
  `StreamingApi.streamPlaylist` est typé `Response<String>` pour le chemin nominal (le `.m3u8`),
  et sa désérialisation traverse un `case 'String': return '$value'` : un corps d'erreur JSON en
  ressort stringifié à la Dart (`{error: {code: stream_not_live}}`, sans guillemets), donc illisible
  par `jsonDecode`. Or c'est ce corps qu'on vient chercher. La sonde utilise le `Dio` sous-jacent —
  **la même instance**, donc les mêmes intercepteurs et le même `Bearer` : la lecture propriétaire
  d'un flux privé continue de fonctionner.
- `ApiConstants.playlistPath` est extrait et `hlsPlaylist` en dérive : le lecteur natif et la sonde
  doivent viser le même endpoint, les laisser diverger rendrait la sonde muette sur ce qui joue.
- Un test relie les constantes Go aux exemples publiés dans `openapi.yaml`
  (`TestOpenAPI_DocumenteLesDeuxCodesDu409`). C'est le seul code d'erreur du projet sur lequel un
  client **branche** au lieu de l'afficher : un renommage silencieux livrerait une application qui
  ne reconnaît plus rien et reprendrait les reconnexions inutiles.

## Alternatives écartées

**Deux statuts HTTP distincts (409 / 425 « Too Early », ou 503 + `Retry-After`).** Le statut aurait
porté la nuance sans champ supplémentaire. Écarté : `425` est défini pour le rejeu TLS early-data,
le détourner tromperait tout intermédiaire qui le lit ; `503` rangerait un démarrage normal parmi
les indisponibilités serveur, donc dans les compteurs d'erreur et les alertes (ADR 019) alors que
rien ne va mal. Le conflit d'état est bien un `409` dans les deux cas — c'est la *cause* qui diffère,
et le corps est fait pour ça.

**Garder l'ambiguïté et raccourcir le backoff côté client.** Passer de 15 s à ~3 s aurait réduit la
gêne sans toucher au serveur. Écarté : ça n'aurait pas corrigé le fond — le client continuerait de
deviner — et raccourcir la fenêtre de reconnexion dégraderait la tolérance aux coupures réseau, qui
est la raison d'être de ce backoff (STR-118). On aurait échangé un défaut visible contre un défaut
invisible.

**Un en-tête dédié (`X-Stream-State`).** Écarté : le corps d'erreur JSON est déjà le canal
conventionnel du projet, il est documenté dans `openapi.yaml` et lisible dans Swagger. Un en-tête
hors contrat aurait été un second mécanisme pour le même besoin.

**Distinguer aussi les deux cas du segment.** Écarté : cf. §2 — un code que personne ne lit, sur
l'endpoint le plus appelé du service.
