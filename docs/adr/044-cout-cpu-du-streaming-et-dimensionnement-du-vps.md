# ADR 044 — Coût CPU du streaming, modèle de capacité et dimensionnement du VPS

**Date** : 2026-08-21
**Statut** : Accepté
**Ticket** : [STR-243](https://linear.app/streampulse/issue/STR-243)

---

## Contexte

Le sujet demande, au titre de la posture de Tech Lead, une **justification des coûts** :

> « capacité à estimer la scalabilité du système (ex. *Combien nous coûte en CPU le streaming
> de 100 flux simultanés ?*) »

L'[ADR 016](016-scalabilite-test-de-charge-et-limiteur-hls.md) mesurait sérieusement la latence,
la mémoire et les goroutines — mais **jamais le processeur**, et sur la mauvaise dimension : 50
auditeurs sur **un** flux. Or ce n'est pas un auditeur qui coûte cher, c'est un flux : un
auditeur est une requête HTTP qui sert un fichier déjà écrit, un flux est un process ffmpeg qui
tourne en permanence.

Le seul chiffrage existant était qualitatif — « CPU ~0 », « CPU négligeable »
([ADR 015](015-moteur-hls-segmentation-ffmpeg.md)) — et l'[ADR 030](030-transcodage-a-la-volee-des-formats-dingest.md)
reconnaissait explicitement le trou : « la charge CPU d'un parc de diffuseurs non-AAC est **à
surveiller** ». Rien dans `docs/` ne mentionnait par ailleurs la taille du VPS, son prix, ni le
coût marginal d'un flux.

## Décision

### 1. Mesurer le CPU par `getrusage`, fils compris

Le harnais de charge gagne une comptabilité CPU
([`cpu_test.go`](../../backend/internal/streaming/loadtest/cpu_test.go)) fondée sur
`syscall.Getrusage`, avec `RUSAGE_SELF` **et** `RUSAGE_CHILDREN` relevés séparément. La
séparation est le cœur de la mesure : dans ce harnais in-process, le process Go *est* le
serveur, mais la segmentation vit dans des process ffmpeg **fils**. Un `RUSAGE_SELF` seul aurait
raté l'essentiel et reproduit le « CPU ~0 » qu'on cherche justement à remplacer.

Trois propriétés de `getrusage` ont dicté le protocole, plutôt que l'inverse :

- **Un fils ne compte qu'une fois récolté** (`wait(2)`). Impossible donc d'échantillonner « le
  CPU pendant la fenêtre de charge » comme on échantillonne le tas : la lecture ne peut être que
  globale, prise **après** l'arrêt des sessions. D'où la lecture du coût marginal dans la
  **pente**, à durée de diffusion constante, et non dans une valeur absolue.
- **Le générateur de charge est un fils comme les autres.** Les ffmpeg qui fabriquent l'audio de
  test seraient comptés avec ceux du serveur. Ils sont donc **défalqués** un par un via
  `cmd.ProcessState.UserTime()`/`SystemTime()` — en production, le diffuseur encode sur *sa*
  machine, pas sur la nôtre. Sans cette soustraction, le coût « par flux » aurait été surestimé
  d'un facteur ~2,9 sur le chemin AAC (1,56 s de générateur pour 0,81 s de serveur à N=1).
- **`ru_maxrss` est le maximum d'un seul fils, pas leur somme, et il est cumulé sur toute la vie
  du process.** Le premier point en fait la grandeur utile — le coût RAM d'**un** ffmpeg, que le
  modèle multiplie ensuite. Le second interdit d'en tirer une valeur par point de balayage :
  le compteur n'étant jamais remis à zéro, chaque point hériterait du pic de tous les précédents.
  D'où un unique relevé en fin de balayage. Et son unité change avec l'OS (octets sur darwin,
  kibioctets sur linux) : une conversion implicite aurait glissé un facteur 1024 dans un
  dimensionnement de serveur.

### 2. Mesurer **sans** `-race`, et refuser de mesurer avec

`make loadtest` compile avec `-race`, ce qui est juste pour un test de latence et de fuite. Pour
un modèle de coût, c'est disqualifiant : le détecteur multiplie le temps CPU du **code Go** par
un ordre de grandeur sans toucher à celui des **process ffmpeg**. L'erreur ne serait donc pas un
facteur d'échelle qu'on pourrait corriger après coup, mais une **déformation asymétrique** de la
répartition entre les deux termes — le genre d'erreur qui ne se voit pas dans le résultat.

D'où une cible séparée, `make loadtest-cpu`, et un garde-fou : le test **échoue** s'il a été
compilé avec le détecteur. Publier un chiffre faux coûte plus cher que ne pas en publier.

La détection lit les **réglages de build** (`debug.ReadBuildInfo`), et non un couple de fichiers
sous `//go:build race` / `//go:build !race`. La première version faisait exactement ça et la CI
l'a refusée, à raison : `race` n'est pas un tag qu'on passe à `-tags`, c'est le toolchain qui le
pose sous `-race`. Le déclarer dans le `DECLARED_TAGS` du job Test aurait fait tourner
`go vet -tags …,race` **sans détecteur actif** — mentir au système de build pour faire taire un
garde-fou — et la variante `race` des deux fichiers n'aurait de toute façon jamais été compilée
par la CI, ce qui est très exactement la pourriture silencieuse que cette garde existe pour
attraper (ADR 016, § Validation). Une fonction se teste dans les deux sens ; une constante sous
build tag, non.

Même logique un cran plus bas : le coût d'un auditeur n'est mesurable que sur une fenêtre assez
longue pour produire plusieurs segments. Sur 12 s, il tombe à 0,05 mcœur contre 0,37 sur 45 s —
les auditeurs re-demandent le même manifeste sans rien télécharger. Le test **saute** plutôt que
de publier ce chiffre-là.

### 3. Faire varier le nombre de flux, pas le nombre d'auditeurs

[`streams_test.go`](../../backend/internal/streaming/loadtest/streams_test.go) balaie N ∈
{1, 5, 10, 20} flux simultanés, à **durée de diffusion identique** (45 s) pour tous les points :
les frais fixes sont ainsi les mêmes partout et le coût marginal se lit dans la pente. Les deux
chemins d'ingest sont mesurés séparément, parce qu'ils ne coûtent pas la même chose (ADR 030) :

- **AAC** — 1 ffmpeg par flux, en `-c:a copy` (remux, pas de ré-encodage) ;
- **MP3** — 2 ffmpeg par flux, le transcodeur ré-encodant réellement en AAC.

Un manifeste qui n'apparaît pas dans le temps imparti n'interrompt pas le balayage : c'est un
**résultat**, et c'est très exactement la forme que prendrait le point de rupture cherché.

Un second test (`TestStreamCPU_Listeners`) chiffre l'autre terme du modèle — ce que coûte un
auditeur à nombre de flux constant — sans quoi « 100 flux » ne dirait rien du parc qui les écoute.
Il procède en **deux phases d'une même diffusion** plutôt qu'en deux diffusions : le socle ffmpeg
s'y annule au lieu d'être soustrait entre deux estimations dont le bruit dépasse le signal
cherché. Détail et raison dans la section Mesures.

## Mesures

`make loadtest-cpu` — Apple M3 (Mac15,3), 8 cœurs, 8 Go, ffmpeg 8.1.2, darwin/arm64, fenêtre de
45 s, générateurs défalqués, sans `-race`. **Run de référence : 2026-08-22.**

### Ce que la mesure ne retire pas

Le CPU du **client HTTP** reste dedans. Le harnais est in-process (ADR 016) : le générateur
pousse son POST et les auditeurs simulés font leurs GET depuis le process même qui héberge le
serveur. `RUSAGE_SELF` étant global au process, l'envoi du corps, les `io.Copy` et le framing des
requêtes atterrissent dans la même colonne que le travail du serveur — un seul compteur pour les
deux rôles, aucun moyen de les séparer.

En production, le diffuseur pousse depuis sa machine et l'auditeur écoute depuis son téléphone :
ce terme n'existe pas. **Tous les chiffres ci-dessous sont donc des majorants**, biais d'autant
plus marqué sur les auditeurs que servir un segment déjà écrit coûte peu. Direction sûre pour un
dimensionnement — on surestime la facture, jamais l'inverse — mais la première version de cette
ADR documentait la soustraction du ffmpeg générateur sans dire un mot de celui-ci, ce qui
laissait croire la mesure purgée de tout ce qui est côté client (revue PR #333). Le fermer
demanderait de sortir les clients du process, c'est-à-dire de renoncer au in-process — et donc
aux mesures mémoire/goroutines qui l'ont fait choisir.

### Ingest AAC — 1 ffmpeg par flux

| Flux | ffmpeg serveur | CPU serveur | dont Go | dont ffmpeg | Cœurs moyens |
|---:|---:|---:|---:|---:|---:|
| 1 | 1 | 0,58 s | 0,41 s | 0,17 s | 0,01 |
| 5 | 5 | 1,96 s | 1,21 s | 0,74 s | 0,04 |
| 10 | 10 | 3,96 s | 2,36 s | 1,60 s | 0,09 |
| 20 | 20 | 7,33 s | 4,46 s | 2,87 s | 0,16 |

**Modèle** : `cœurs ≈ 0,0080 × N + 0,006` → **100 flux ≈ 0,80 cœur**.

Le chemin AAC est dominé par le **serveur Go**, pas par ffmpeg (4,46 s contre 2,87 s à N=20) :
`-c:a copy` ne fait que remuxer, l'essentiel du travail est la recopie de l'ingest et le service
HTTP.

### Ingest MP3 — 2 ffmpeg par flux (transcodage, ADR 030)

| Flux | ffmpeg serveur | CPU serveur | dont Go | dont ffmpeg | Cœurs moyens |
|---:|---:|---:|---:|---:|---:|
| 1 | 2 | 2,10 s | 0,54 s | 1,56 s | 0,05 |
| 5 | 10 | 9,01 s | 1,72 s | 7,29 s | 0,20 |
| 10 | 20 | 16,65 s | 3,05 s | 13,60 s | 0,37 |
| 20 | 40 | 22,01 s | 3,27 s | 18,74 s | 0,49 |

**Modèle** : `cœurs ≈ 0,0227 × N + 0,074` → **100 flux ≈ 2,35 cœurs**.

Ici ce sont les ffmpeg qui portent la charge — 85 % à N=20 (18,74 s sur 22,01 s) : le second
process ne *double* pas le coût, il **ré-encode**, là où le segmenteur ne faisait que recopier
des paquets.

### Reproductibilité — deux runs, et ce qu'ils permettent d'affirmer

| | 2026-08-21 | 2026-08-22 | Écart |
|---|---:|---:|---:|
| 100 flux AAC | 0,60 cœur | 0,80 cœur | **+33 %** |
| 100 flux MP3 | 2,39 cœurs | 2,35 cœurs | −2 % |

Le chemin MP3 est stable à 2 % près, l'AAC varie de 33 % — et c'est cohérent : le signal AAC est
petit (0,16 cœur à N=20 contre 0,49), donc le bruit de la machine y pèse proportionnellement plus.
Un poste de développement n'est pas un banc.

Ce que ces deux runs autorisent à écrire, et rien de plus :

- **100 flux AAC : de l'ordre de 0,6 à 0,8 cœur.** « Moins d'un vCPU » est solide ; trois
  décimales ne le seraient pas.
- **100 flux transcodés : 2,4 cœurs**, à quelques pour cent près.
- **Le transcodage coûte 3 à 4 fois un flux AAC** (2,8× sur le run du 22, 4,1× sur celui du 21).
  C'est ce rapport, pas sa décimale, qui chiffre le « à surveiller » de l'ADR 030.

### Auditeurs — deux phases d'une même diffusion

Mesurer un auditeur en comparant **deux diffusions** ne marchait pas : le signal cherché
(~0,02 cœur pour 50 auditeurs) est du même ordre que la variabilité run-à-run du socle ffmpeg, si
bien qu'un run un peu plus chargé que l'autre rendait l'écart nul — voire négatif, et
« auditeurs par cœur » sortait en négatif ou en `+Inf` sans qu'aucune garde ne le signale (revue
PR #333).

Les deux termes sont donc mesurés dans **une seule diffusion**, en deux phases consécutives : le
socle s'annule au lieu d'être soustrait entre deux estimations bruitées.

| Phase | Ce qui tourne | CPU Go sur 45 s | Cœurs |
|---|---|---:|---:|
| A | 1 flux, 0 auditeur | 0,40 s | 0,0088 |
| B | 1 flux, 50 auditeurs (1600 requêtes, 0 échec) | 1,57 s | 0,0349 |

**Coût marginal d'un auditeur : 0,52 mcœur**, soit **au moins ~1 900 auditeurs par cœur**.

Deux remarques de méthode. D'abord, seul `RUSAGE_SELF` est lu : un auditeur ne coûte aucun ffmpeg
— les segments qu'il télécharge sont déjà écrits, le segmenteur travaille pareil qu'il y ait zéro
ou cinquante auditeurs. C'est aussi ce qui rend le découpage en phases possible, `RUSAGE_SELF` se
lisant à tout instant là où `RUSAGE_CHILDREN` attend la récolte des fils. Ensuite, le test
**échoue** si l'écart entre les deux phases est nul ou négatif : une mesure non concluante doit se
voir, pas se publier.

Ce chiffre est plus élevé que les 0,37 mcœur du premier run — la méthode d'alors soustrayait des
totaux de run entiers, socle ffmpeg compris, et sous-estimait. Un auditeur reste **15 fois moins
cher qu'un flux AAC et 44 fois moins qu'un flux transcodé** : le dimensionnement se joue sur les
diffuseurs, pas sur l'audience.

### Mémoire et disque

Pic de RSS du plus gros process fils : **16 Mo**.

⚠️ C'est un **high-water cumulé sur toute la vie du binaire de test**, que le noyau ne remet jamais
à zéro. Il ne peut donc que croître, et aucune valeur « par point de balayage » ne peut en être
tirée — chaque point hériterait du pic de tous les précédents. La première version de cette ADR
en concluait « 16 Mo, stable sur toute la plage » : une stabilité qu'un compteur monotone est
incapable d'établir (revue PR #333). Ce qu'on peut affirmer est plus modeste et suffit : **aucun
ffmpeg n'a dépassé 16 Mo**, ni en AAC ni en transcodage, ni à N=1 ni à N=20.

Le modèle RAM est donc `≤ 16 Mo × ffmpeg`, soit au plus 1,6 Go pour 100 flux AAC et **3,2 Go pour
100 flux MP3**. Le disque est négligeable : 6 segments de 10 s à 128 kbit/s (`hlsListSize`,
`hlsSegmentSeconds`) ≈ **1 Mo par flux**, dans un répertoire temporaire supprimé à l'arrêt.

## Dimensionnement et coût du VPS

⚠️ **Le plan du VPS n'est pas documenté dans le dépôt** — seul `VPS_HOST` (une IP `65.21.x.x`,
donc Hetzner Allemagne/Finlande) existe. Le chiffrage ci-dessous est instancié sur l'hypothèse
d'un **CX22**, à confirmer par le propriétaire du compte ; le modèle, lui, est valable pour
n'importe quel plan puisqu'il s'exprime en cœurs.

Tarifs Hetzner Cloud relevés le 2026-08-21, hors TVA, 20 To de trafic inclus sur tous les plans :

| Plan | vCPU | RAM | Disque | Prix/mois |
|---|---:|---:|---:|---:|
| **CX22** *(hypothèse)* | 2 | 4 Go | 40 Go | **3,79 €** |
| CX32 | 4 | 8 Go | 80 Go | 6,80 € |

### Ce que tient la machine actuelle

⚠️ Les mesures sont prises sur un **Apple M3**, pas sur un vCPU partagé Hetzner. Un cœur M3 est
sensiblement plus rapide, surtout sur le transcodage. Le facteur de correction n'a **pas** été
mesuré et n'est pas inventé ici : la manière honnête de le fermer est de rejouer la même cible
sur le VPS (`make loadtest-cpu`, ffmpeg est déjà dans l'image). Les capacités ci-dessous
retiennent une marge de **2×** en attendant, et doivent être lues comme un ordre de grandeur.

| Contrainte (2 vCPU, 4 Go, marge 2×) | Ingest AAC | Ingest MP3 |
|---|---|---|
| CPU | ~125 flux | ~44 flux |
| RAM ffmpeg seule | ~100 flux (1,6 Go) | ~50 flux (3,2 Go) |
| **Mur effectif** | **~100 flux — la RAM** | **~44 flux — le CPU** |

La RAM est la contrainte du chemin AAC, pas le processeur : sur un CX22, il resterait à peine
2 Go pour l'API, PostgreSQL et toute la pile d'observabilité (Prometheus, Loki, Tempo, Grafana,
Alloy) une fois 100 segmenteurs lancés. Le palier suivant, **CX32 à 6,80 €/mois** (+3,01 €),
double les deux ressources d'un coup et sort de cette zone.

### Coût marginal

Sur un CX22, un vCPU-mois vaut 1,90 € (3,79 € ÷ 2). Avec la marge de 2× :

| Unité | Coût CPU/mois | Remarque |
|---|---:|---|
| Un flux **AAC** | **≈ 0,030 €** | 3 centimes |
| Un flux **MP3** | **≈ 0,086 €** | ~3× le précédent |
| Un auditeur | ≈ 0,002 € | négligeable devant sa bande passante |

**Le vrai coût d'un auditeur n'est pas son CPU, c'est son trafic.** À 128 kbit/s, une écoute
continue consomme **42 Go par mois**. Les 20 To inclus couvrent donc **~475 auditeurs
permanents** ; au-delà, le trafic sortant est facturé au téraoctet — à 1 €/To, un auditeur
continu revient alors à ~0,04 €/mois, soit **vingt fois son coût CPU**. (Le tarif au téraoctet
est à confirmer en même temps que le plan du serveur ; l'ordre de grandeur, lui, ne dépend pas
de sa valeur exacte : c'est le rapport entre trafic et processeur qui compte.)

## Alternatives écartées

- **`pprof.StartCPUProfile`** — donne la répartition du CPU *à l'intérieur* du process Go, pas
  son total, et ne voit pas du tout les process fils. Or ce sont eux qui portent 85 % de la
  charge sur le chemin MP3 (18,74 s sur 22,01 s à N=20). Excellent pour optimiser, inapte à chiffrer.
- **`docker stats` / cgroups** — mesurerait tout le conteneur d'un coup, générateur de charge
  compris, sans moyen de le défalquer, et imposerait de lancer la pile Docker pour chaque point
  du balayage. `getrusage` donne la même grandeur sans dépendance et avec la séparation
  serveur/fils que le modèle exige.
- **Un test réellement à 100 flux** — 100 flux MP3 signifient 200 ffmpeg serveur **plus** 100
  ffmpeg générateurs sur la machine de mesure. On y mesurerait la saturation du poste de
  développement, pas le coût du service. Le balayage 1→20 reste dans le régime linéaire (vérifié)
  et l'extrapolation y est motivée ; c'est sur le **VPS** qu'un point à 100 aurait du sens.
- **k6 / vegeta** — déjà écartés par l'ADR 016, et aveugles ici pour la même raison : le coût
  mesuré est côté serveur, dans des process que le client ne voit pas.

## Conséquences

- Deux cibles distinctes et non interchangeables : `make loadtest` (latence, mémoire, fuites,
  avec `-race`) et `make loadtest-cpu` (coût, sans `-race`). Le second refuse de tourner dans la
  configuration du premier.
- `listen()` du harnais prend désormais l'identifiant du flux en paramètre : la mesure fait
  écouter des flux dont les identifiants sont générés, un par diffusion simultanée.
- **Le transcodage est le poste de coût du service** (3 à 4× un flux AAC). Si un parc de diffuseurs
  non-AAC se constitue, deux leviers existent avant d'acheter du vCPU : documenter l'AAC comme
  format recommandé côté diffuseur, ou borner le nombre de transcodages simultanés comme
  `HLS_MAX_CONCURRENT` borne déjà les auditeurs (ADR 016 §2).
- **`make loadtest-cpu` reste hors CI, délibérément.** Le workflow « Load Test » vérifie chaque
  semaine que le harnais de latence passe encore ; y ajouter le balayage CPU produirait un chiffre
  mesuré sur un runner GitHub partagé, dont la puissance varie d'un run à l'autre. Un modèle de
  coût dont la valeur bouge sans que le code change n'est pas un modèle. La compilation du
  balayage, elle, **est** gardée : le tag `loadtest` figure dans `DECLARED_TAGS` du job Test, qui
  échoue si ces fichiers cessent de compiler — la panne silencieuse de trois semaines et demie
  documentée par l'ADR 016 ne peut pas se reproduire ici.
- **Gap assumé** : le facteur entre un cœur M3 et un vCPU Hetzner n'est pas mesuré, et le plan du
  VPS n'est pas confirmé. Les deux se ferment par le même geste — rejouer `make loadtest-cpu` sur
  le serveur de production — et cette ADR sera mise à jour avec le run réel.
- Aucune migration, aucune nouvelle variable d'environnement, aucun changement de code applicatif :
  tout tient dans le harnais de test et la documentation.
