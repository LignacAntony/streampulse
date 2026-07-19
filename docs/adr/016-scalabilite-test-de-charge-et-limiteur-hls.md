# ADR 016 — Scalabilité : test de charge Go in-process et limiteur de capacité HLS

**Date** : 2026-07-19
**Statut** : Accepté
**Ticket** : [STR-87](https://linear.app/streampulse/issue/STR-87) (sous-issues [STR-88](https://linear.app/streampulse/issue/STR-88), [STR-89](https://linear.app/streampulse/issue/STR-89), [STR-90](https://linear.app/streampulse/issue/STR-90), [STR-91](https://linear.app/streampulse/issue/STR-91))

---

## Contexte

Le moteur HLS ([ADR 015](015-moteur-hls-segmentation-ffmpeg.md)) transporte l'audio d'un
diffuseur vers les auditeurs. STR-87 exige la preuve de sa tenue en charge :

> Given un flux HLS actif, when **50 clients** simulent la récupération du manifeste et des
> segments, then p95 < **300 ms**, mémoire < **2 Mo/connexion**, **aucune goroutine leak**
> (détection pprof).

Deux questions d'architecture en découlent : **comment mesurer** (outil et cible du test de
charge), et **comment protéger** le serveur quand la demande dépasse la capacité (gestion des
connexions concurrentes).

## Décision

### 1. Test de charge : Go pur, in-process, hors CI bloquante (STR-90)

- **Go pur** (pas k6) : un test `go test` classique dans
  [`backend/internal/streaming/loadtest/`](../../backend/internal/streaming/loadtest/load_test.go).
  Zéro outil nouveau, et surtout mémoire + goroutines mesurables **dans le même process** via
  `runtime`/`pprof` — un outil externe n'aurait vu que la latence.
- **In-process** : le test démarre le vrai serveur (vrai mux, vraies `LiveSessions`, vrai
  middleware JWT, **vrai ffmpeg** — skip si absent). Un stub remplace uniquement le
  `StreamService` (la DB n'est pas l'objet mesuré). 1 diffuseur sine AAC temps réel,
  50 goroutines auditeurs pendant 60 s (playlist → segments nouveaux → pause 2 s),
  latences agrégées par tri (percentiles nearest-rank).
- **Build tag `loadtest`** : exclu de `go test ./...` (pas de +75 s ni de flakiness de seuils
  sur runner partagé à chaque push). Exécution : `make loadtest` (`-race -count=1` — un test de
  charge ne doit jamais être servi depuis le cache) ou workflow **« Load Test »**
  (`workflow_dispatch`, rapport en artifact, `shell: bash` pour que pipefail propage un échec).
- **Détection de fuite (STR-89)** : goroutines comptées avant charge puis après stop + drain
  (`LiveSessions.Wait` borné, retries + GC, tolérance 3) ; en cas de dépassement, le message
  d'échec embarque le dump `pprof.Lookup("goroutine")` — les stacks fuyardes sont directement
  dans le rapport de test.

### 2. Limiteur de capacité : refus immédiat 503, budget partagé (STR-88)

Le modèle `net/http` (une goroutine par connexion) n'a pas besoin d'un « pool de goroutines » :
les mesures ci-dessous le confirment avec ~15× de marge. Le risque réel est l'**absence de
borne** — un pic d'auditeurs au-delà de la capacité dégraderait tout le monde. D'où
[`limiter.go`](../../backend/internal/streaming/limiter.go) :

- `NewMaxInFlight(limit)` : sémaphore (canal bufferisé), acquisition **non bloquante**, slot
  libéré en `defer` (sûr même si le handler panique). Budget **partagé** entre les routes
  enveloppées par la même instance — playlist + segments consomment la même capacité.
- Au-delà de la limite : **503 JSON** (`server_overloaded`) + `Retry-After: 2`, **sans file
  d'attente** — refus net, déterministe et testable ; pas de log sur ce chemin (pas
  d'inondation sous surcharge).
- Monté dans `main.go` **avant** `RequireAuth` (on refuse avant même de parser le JWT sous
  surcharge). L'ingest n'est **pas** limité : un seul push par flux, déjà garanti par
  `errIngestInProgress`.
- Config : `HLS_MAX_CONCURRENT` (défaut **256**, `0` explicite = désactivé, valeur vide ≡
  absente → défaut, conformément à la convention de `config.go`). Réponse 503 documentée dans
  l'OpenAPI des deux routes auditeur.

## Alternatives écartées

- **k6** : standard du load test, mais dépendance binaire nouvelle (CI + local), scripts JS à
  maintenir, et aveugle sur mémoire/goroutines côté serveur — il aurait fallu un second outillage
  pprof à côté. Le critère STR-87 est précisément serveur-side.
- **Test contre la stack Docker** : plus réaliste (réseau, container limits) mais mesures
  mémoire/goroutines seulement via pprof HTTP à exposer + `docker stats`, et CI beaucoup plus
  lourde. L'in-process mesure ce que STR-87 demande ; la limite (pas de RTT réseau) est assumée.
- **Worker pool / pool de goroutines côté serveur** : combattrait le modèle de `net/http` sans
  bénéfice mesuré (0,13 Mo/connexion observé) ; complexité et risque de famine pour rien.
- **File d'attente dans le limiteur** (backpressure douce) : ajoute de la latence cachée et un
  état à dimensionner ; le refus immédiat + `Retry-After` est compréhensible par les players
  HLS (retry naturel au prochain poll) et trivialement testable. Réévaluable si le besoin
  apparaît.

## Validation (run de référence, 2026-07-19)

Sortie locale de `make loadtest` (Apple M3, 8 Go, Go 1.26.1, ffmpeg 8.1.2), limiteur monté
à 256 dans le harnais :

| Critère STR-87 | Seuil | Mesuré | Verdict |
|---|---|---|---|
| p95 playlist | < 300 ms | **23,52 ms** | ✅ |
| p95 segment | < 300 ms | **41,02 ms** | ✅ |
| Mémoire/connexion | < 2 Mo | **0,13 Mo** | ✅ |
| Échecs HTTP | 0 | **0 / 1800 requêtes** | ✅ |
| Goroutine leak | 0 | goroutines 13 → 10 après drain | ✅ |

1500 requêtes playlist + 300 segments (~50 Mo servis), `-race` sans warning, aucun 503 émis
(50 auditeurs < 256). Limites connues : in-process (latences hors RTT réseau/TLS), source sine
à débit constant, matériel local ≠ VPS — refaire le run via le workflow « Load Test » pour des
chiffres CI reproductibles.

## Conséquences

- Les auditeurs peuvent recevoir un **503** sur playlist/segments à saturation : les clients
  (mobile inclus) doivent le traiter comme réessayable (`Retry-After`).
- Le registre et la borne restent **locaux au process** (mono-instance, cf. ADR 013 §7) : le
  multi-instance reste hors scope.
- Aucune métrique de shedding (compteur de 503) : piste ticket observabilité si le limiteur
  déclenche en réel.
- Aucune migration ; `.env.example` et CLAUDE.md documentent la nouvelle variable.
