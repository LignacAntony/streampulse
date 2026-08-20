# Plan de formation des utilisateurs

Comment amener chaque public à l'autonomie sur StreamPulse, y compris les
personnes en situation de handicap.

Ce plan est dimensionné pour l'usage réel du produit : une application mobile
d'écoute et de diffusion. Il ne prétend pas à un dispositif de formation
professionnelle certifiant — il décrit ce qui est nécessaire et suffisant pour
que chaque rôle sache faire ce qu'il a à faire.

**Documents liés** — [manuel-utilisateur.md](manuel-utilisateur.md) (le support
principal), [accessibilite.md](accessibilite.md).

---

## 1. Publics et objectifs

| Public | Effectif attendu | Ce qu'il doit savoir faire à l'issue | Prérequis |
|---|---|---|---|
| **Auditeur** | Le plus grand nombre | Créer un compte, trouver un direct, écouter, gérer favoris et playlists | Savoir installer une application |
| **Diffuseur** | Quelques dizaines | Tout ce qui précède, plus : créer un flux, obtenir et protéger sa clé, démarrer et arrêter, lire son audience | Être auditeur autonome |
| **Administrateur** | 2 à 3 personnes | Gérer les comptes, modérer les directs, traiter les demandes de rôle, comprendre ce qui est irréversible | Être diffuseur autonome |
| **Personne relais** | 1 par structure utilisatrice | Accompagner les trois publics ci-dessus, savoir vers quoi orienter une demande d'adaptation | Avoir suivi le parcours diffuseur |

## 2. Dispositif

| Public | Modalité | Durée | Support | Évaluation |
|---|---|---|---|---|
| Auditeur | Autoformation guidée | 20 min | [manuel-utilisateur.md](manuel-utilisateur.md) § 1 | Écouter un direct et créer une playlist de 3 pistes |
| Auditeur | Prise en main accompagnée, à la demande | 30 min | Démonstration sur appareil | Idem, réalisé sans aide |
| Diffuseur | Atelier en petit groupe (4 à 6) | 1 h | § 2 du manuel + un flux de test | Diffuser 5 minutes, arrêter, relire son audience |
| Diffuseur | Fiche mémo « ma clé de diffusion » | 5 min | Une page, imprimable | Savoir dire quand renouveler sa clé |
| Administrateur | Session individuelle | 1 h 30 | § 3 du manuel + [securite.md](securite.md) § 1 et 2 | Désactiver puis réactiver un compte de test ; interrompre un direct de test |
| Administrateur | Lecture dirigée RGPD | 30 min | [rgpd.md](rgpd.md) § 3 | Expliquer ce que la suppression d'un compte efface et ce qu'elle conserve |
| Personne relais | Parcours complet + questions | 3 h | L'ensemble de `docs/` | Rejouer un parcours de chaque rôle devant un tiers |

## 3. Progression

Le parcours diffuseur suppose le parcours auditeur, et le parcours
administrateur suppose le parcours diffuseur. Ce n'est pas une convention
pédagogique : un administrateur qui n'a jamais diffusé ne mesure pas ce
qu'interrompre un direct signifie pour la personne à l'autre bout.

```
Auditeur ──▶ Diffuseur ──▶ Administrateur
   │                             ▲
   └──────── Personne relais ────┘
```

**Équivalent textuel du schéma.** Le parcours auditeur est le point d'entrée.
Il mène au parcours diffuseur, qui mène lui-même au parcours administrateur. Le
parcours « personne relais » part également du parcours auditeur et rejoint le
niveau administrateur, sans passer par la responsabilité de modération.

## 4. Adaptations pour les publics en situation de handicap

Cette section n'est pas un ajout : c'est une exigence du référentiel, et elle
conditionne le reste du dispositif.

### 4.1 Déficience visuelle

- **Tous les supports écrits sont utilisables au lecteur d'écran.** Le manuel
  est structuré par titres hiérarchisés, ce qui permet la navigation de titre en
  titre plutôt que la lecture linéaire.
- **Aucune information n'est portée par une image seule.** Chaque capture
  d'écran est doublée d'un équivalent textuel, et chaque schéma est suivi de sa
  description. Un support amputé de ses images reste complet.
- **Aucune information n'est portée par la couleur seule** (cf.
  [accessibilite.md](accessibilite.md)).
- La prise en main accompagnée peut se faire **entièrement à l'oral**, en
  s'appuyant sur les libellés que le lecteur d'écran annonce — ce sont ceux que
  le manuel cite mot pour mot.

### 4.2 Déficience auditive

- **Aucune séquence de formation ne repose sur du son.** C'est contre-intuitif
  pour une application audio, et c'est précisément le point : *utiliser*
  StreamPulse — créer un compte, gérer une playlist, démarrer un flux, modérer —
  ne demande pas d'entendre. Seul le contrôle qualité d'une diffusion le
  demande, et il peut être délégué.
- Les démonstrations en direct sont doublées d'un **support écrit remis avant la
  séance**, pour ne pas dépendre de la lecture labiale.
- Un diffuseur sourd ou malentendant peut vérifier que son flux passe par les
  **indicateurs visuels** : le flux affiché « en direct » et le compteur
  d'auditeurs qui progresse.

### 4.3 Déficience motrice

- L'application se pilote **sans geste complexe** : appuis simples, pas de
  double-appui, pas de geste à plusieurs doigts. Une seule interaction demande
  un glissement — réordonner une playlist — et elle a une alternative :
  reconstruire l'ordre en retirant puis rajoutant les pistes.
- Les séances accompagnées se font **sans limite de temps** ; aucun exercice
  n'est chronométré.
- Les supports sont utilisables avec les technologies d'assistance du système
  (contrôle vocal, commutateur), puisqu'ils reposent sur les libellés standards
  de la plateforme.

### 4.4 Troubles cognitifs et de l'apprentissage

- Le manuel procède **par étapes numérotées**, une action par étape.
- Le vocabulaire technique est réduit, et ce qui reste est défini dans le
  **glossaire** d'[accessibilite.md](accessibilite.md).
- Un tableau **« Que faire si… »** clôt le manuel : il donne la conduite à tenir
  sans exiger d'avoir lu ce qui précède.
- Les séances peuvent être **fractionnées** : un objectif par séance courte
  plutôt qu'un parcours d'une heure.

### 4.5 Demander une adaptation

Toute demande d'adaptation non couverte ici — support en gros caractères,
version audio, interprétation en langue des signes pour une séance — se fait
auprès de la personne relais de la structure, ou en ouvrant une issue sur le
dépôt du projet.

## 5. Maintien à jour

Une évolution qui change un parcours utilisateur **entraîne la mise à jour du
manuel dans la même modification**, pas après. Un support de formation qui
décrit une version antérieure du produit est plus nuisible que pas de support :
il fait douter la personne de ce qu'elle voit à l'écran.

Le tableau du § 2 est révisé à chaque version majeure.
