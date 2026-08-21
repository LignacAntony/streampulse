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
- **`ru_maxrss` est le maximum d'un seul fils, pas leur somme** — et son unité change avec l'OS
  (octets sur darwin, kibioctets sur linux). C'est exactement la grandeur utile ici : le coût
  RAM d'**un** ffmpeg, que le modèle multiplie ensuite. Une conversion implicite aurait glissé un
  facteur 1024 dans un dimensionnement de serveur.

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

## Mesures (run du 2026-08-21)

`make loadtest-cpu` — Apple M3 (Mac15,3), 8 cœurs, 8 Go, ffmpeg 8.1.2, darwin/arm64, fenêtre de
45 s, générateurs défalqués, sans `-race`.

### Ingest AAC — 1 ffmpeg par flux

| Flux | ffmpeg serveur | CPU serveur | dont Go | dont ffmpeg | Cœurs moyens |
|---:|---:|---:|---:|---:|---:|
| 1 | 1 | 0,81 s | 0,61 s | 0,19 s | 0,02 |
| 5 | 5 | 2,86 s | 1,95 s | 0,91 s | 0,06 |
| 10 | 10 | 4,02 s | 2,57 s | 1,45 s | 0,09 |
| 20 | 20 | 6,01 s | 3,41 s | 2,59 s | 0,13 |

**Modèle** : `cœurs ≈ 0,0057 × N + 0,025` → **100 flux ≈ 0,60 cœur**.

Le chemin AAC est dominé par le **serveur Go**, pas par ffmpeg (3,41 s contre 2,59 s à N=20) :
`-c:a copy` ne fait que remuxer, l'essentiel du travail est la recopie de l'ingest et le service
HTTP. L'ajustement sur les seuls points 5–20 donne une pente de 0,0047 cœur/flux, soit 0,51 cœur
à N=100 : le modèle publié est donc le **majorant** des deux, ce qui est le bon sens pour un
dimensionnement.

### Ingest MP3 — 2 ffmpeg par flux (transcodage, ADR 030)

| Flux | ffmpeg serveur | CPU serveur | dont Go | dont ffmpeg | Cœurs moyens |
|---:|---:|---:|---:|---:|---:|
| 1 | 2 | 1,85 s | 0,50 s | 1,36 s | 0,04 |
| 5 | 10 | 8,54 s | 1,56 s | 6,98 s | 0,19 |
| 10 | 20 | 12,50 s | 1,90 s | 10,60 s | 0,28 |
| 20 | 40 | 22,72 s | 3,61 s | 19,11 s | 0,51 |

**Modèle** : `cœurs ≈ 0,0235 × N + 0,042` → **100 flux ≈ 2,39 cœurs**.

Le rapport entre les deux chemins est de **4,1×**, et non de 2× comme le laissait supposer le
simple décompte de process : le second ffmpeg ne *double* pas la charge, il **ré-encode**, alors
que le premier ne faisait que recopier des paquets. C'est le chiffre qui manquait au « à
surveiller » de l'ADR 030. La linéarité y est franche (pente mesurée sur l'intervalle 10→20 :
0,023 cœur/flux, contre 0,0235 pour l'ajustement global), donc l'extrapolation à 100 est solide.

### Auditeurs

| Scénario | CPU serveur | Cœurs moyens |
|---|---:|---:|
| 1 flux, 0 auditeur | 0,57 s | 0,013 |
| 1 flux, 50 auditeurs (1100 requêtes, 0 échec) | 1,39 s | 0,031 |

**Coût marginal d'un auditeur : 0,37 mcœur**, soit **~2 700 auditeurs par cœur**. Un auditeur
coûte 15 fois moins qu'un flux AAC et 64 fois moins qu'un flux MP3 — le dimensionnement se joue
sur les diffuseurs, pas sur l'audience.

### Mémoire et disque

`ru_maxrss` du plus gros process fils : **16 Mo**, stable sur toute la plage (le segmenteur ne
bufferise pas). Le modèle RAM est donc `16 Mo × ffmpeg`, soit 1,6 Go pour 100 flux AAC et
**3,2 Go pour 100 flux MP3**. Le disque est négligeable : 6 segments de 10 s à 128 kbit/s
(`hlsListSize`, `hlsSegmentSeconds`) ≈ **1 Mo par flux**, dans un répertoire temporaire supprimé
à l'arrêt.

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

| Contrainte | Ingest AAC | Ingest MP3 |
|---|---|---|
| CPU (2 vCPU, marge 2×) | ~170 flux | ~40 flux |
| RAM ffmpeg seule (4 Go) | ~100 flux (1,6 Go) | ~50 flux (3,2 Go) |
| **Mur effectif** | **~100 flux — la RAM** | **~40 flux — le CPU** |

La RAM est donc la contrainte du chemin AAC, pas le processeur : sur un CX22, il reste à peine
2 Go pour l'API, PostgreSQL et toute la pile d'observabilité (Prometheus, Loki, Tempo, Grafana,
Alloy) une fois 100 segmenteurs lancés. Le palier suivant, **CX32 à 6,80 €/mois** (+3,01 €),
double les deux ressources d'un coup et sort de cette zone.

### Coût marginal

Sur un CX22, un vCPU-mois vaut 1,90 € (3,79 € ÷ 2). Avec la marge de 2× :

| Unité | Coût CPU/mois | Remarque |
|---|---:|---|
| Un flux **AAC** | **≈ 0,022 €** | 2,2 centimes |
| Un flux **MP3** | **≈ 0,089 €** | 4× le précédent |
| Un auditeur | ≈ 0,0014 € | négligeable devant sa bande passante |

**Le vrai coût d'un auditeur n'est pas son CPU, c'est son trafic.** À 128 kbit/s, une écoute
continue consomme **42 Go par mois**. Les 20 To inclus couvrent donc **~475 auditeurs
permanents** ; au-delà, le trafic sortant est facturé au téraoctet — à 1 €/To, un auditeur
continu revient alors à ~0,04 €/mois, soit **trente fois son coût CPU**. (Le tarif au téraoctet
est à confirmer en même temps que le plan du serveur ; l'ordre de grandeur, lui, ne dépend pas
de sa valeur exacte : c'est le rapport entre trafic et processeur qui compte.) Le premier plafond que rencontrera
StreamPulse en croissance est celui du réseau, pas celui du processeur.

## Alternatives écartées

- **`pprof.StartCPUProfile`** — donne la répartition du CPU *à l'intérieur* du process Go, pas
  son total, et ne voit pas du tout les process fils. Or ce sont eux qui portent 84 % de la
  charge sur le chemin MP3 (19,11 s sur 22,72 s à N=20). Excellent pour optimiser, inapte à chiffrer.
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
- **Le transcodage est le poste de coût du service** (4,1× un flux AAC). Si un parc de diffuseurs
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
