# ADR 050 — Mesurer et annoncer les coupures de diffusion rétablies

**Date** : 2026-09-02
**Statut** : Accepté
**Ticket** : STR-XXX

## Contexte

Test sur appareil : diffusion depuis le micro, coupure réseau de 20 secondes
provoquée au niveau transport, puis rétablissement. Le diffuseur comptait à voix
haute. L'auditeur a entendu « …cinq, six, **vingt-cinq**, vingt-six… » — sans le
moindre blanc.

Trois constats, dont un seul est un défaut.

### Le raccord sans silence est voulu

Deux mécanismes se combinent. À la perte de connexion, `MicrophoneAudioPublisher`
ferme la tentative en cours, ce qui **arrête aussi la capture** — chaque
tentative redémarre l'encodeur pour que le serveur reçoive un flux AAC/ADTS
autonome. Les nombres sept à vingt-quatre n'ont donc jamais été encodés.

Et les horodatages HLS dérivent du **compte de trames ADTS**, pas de l'horloge
murale : le segmenteur reçoit « six » puis « vingt-cinq » et les colle, sans
savoir que vingt secondes se sont écoulées. Le trou n'existe pas dans le média.

C'est le bon compromis pour de la radio : vingt secondes de silence à l'antenne
sont pires qu'une phrase coupée, et recoller rapproche l'auditeur du direct au
lieu de le laisser dériver. Ce point n'est pas remis en cause.

### Personne n'était prévenu

- **Les métriques n'ont rien vu.** `streampulse_stream_interruptions_total` ne
  compte que les diffusions *terminées* (`ingest_timeout`, `segmenter_failed`).
  Une coupure rétablie avant l'expiration du bail ne termine rien, donc
  n'incrémente rien. Vérifié pendant le test : le compteur est resté à sa
  valeur. **Un incident est survenu, le système s'en est remis, et aucun
  instrument ne l'a enregistré** — dans un projet dont l'observabilité est le
  cœur, c'est l'angle mort le plus gênant.
- **Le diffuseur ne savait pas ce qu'il avait perdu.** La tuile affiche bien
  « Reconnexion audio… » *pendant* la coupure (état `reconnecting`), mais rien
  ne lui disait, une fois revenu, combien de temps n'était pas parti. Or c'est
  la seule information qui change son comportement : sachant qu'il a perdu vingt
  secondes, il peut les redire.
- **L'auditeur n'a rien ressenti.** Sa fenêtre HLS (6 segments, ~60 s) a absorbé
  la coupure : mesuré, un seul trou de récupération de segments, ≤ 15 s, et
  aucune interruption audible. Lui afficher un indicateur reviendrait à lui
  inventer un problème qu'il n'a pas.

## Décision

### 1. Deux séries pour les coupures rétablies

```
streampulse_ingest_recoveries_total      (compteur)
streampulse_ingest_outage_seconds        (histogramme, bornes 1→45 s)
```

Deux séries plutôt qu'une : le compteur répond à « combien de fois ? » et
alimente une alerte sur la fréquence ; l'histogramme répond à « combien de temps
perdu ? », qui est ce que le diffuseur constate. Une moyenne les confondrait —
un hoquet d'une seconde et une coupure de trente n'appellent pas la même
conduite.

Les bornes de l'histogramme s'arrêtent au bail d'ingest (45 s) : au-delà, la
diffusion se termine et relève des interruptions, pas des reprises.

Ni l'une ni l'autre ne porte de `stream_id` : ce serait un second porteur du
label à purger, alors que l'[ADR 022](022-metriques-metier-du-streaming.md) n'en
a délibérément gardé qu'un.

**Les points d'accroche existaient déjà.** `release()` sait quand le push se
détache, `AttachIngest` sait quand il revient ; il suffisait de dater le premier
et de mesurer l'écart au second. La mesure est faite **au rattachement** et non
au détachement : au moment où le push se détache, on ignore encore si la coupure
sera rétablie ou terminera la diffusion.

`ingestLostAt` est nul tant qu'aucun push n'a été détaché — la première prise
d'ingest d'une diffusion n'est donc jamais comptée comme une reprise.

### 2. Le diffuseur apprend la durée au retour

Au rétablissement : « Connexion rétablie — 20 s n'ont pas été diffusées. »

Mesuré **sur les transitions d'état** du contrôleur de session plutôt que dans
le publisher : la sortie de `live` et le retour à `live` sont exactement les
bornes de ce que l'application sait ne pas avoir diffusé, et ça évite d'élargir
l'interface de capture pour une donnée de présentation.

⚠️ Seul `reconnecting` ouvre une coupure, jamais `connecting`. Ce dernier est la
toute première tentative d'une diffusion : le compter ferait annoncer « X s
n'ont pas été diffusées » à chaque démarrage, alors qu'il n'y avait rien à
diffuser avant. Le publisher distingue déjà les deux (`started ? reconnecting :
connecting`).

Sous la seconde, rien n'est annoncé : le diffuseur n'a rien perdu
d'intelligible, et le dire serait du bruit.

La source de temps est injectable, sans quoi la durée serait invérifiable en
test (même raison qu'à l'[ADR 042](042-controle-du-volume-et-temps-decoute.md)).

### 3. Rien n'est ajouté côté auditeur

Il n'a pas de canal : le flux d'événements SSE exige un JWT et n'est utilisé que
par le tableau de bord diffuseur, alors qu'un auditeur peut être anonyme. Et
surtout il n'a rien ressenti — son tampon a absorbé la coupure.

Quand c'est **sa propre** connexion qui flanche, il voit déjà « Reconnexion… »
via `PlaybackStatus.reconnecting`. Cette séparation est juste : coupure diffuseur
et coupure auditeur ne sont pas le même événement, et les confondre afficherait
un incident à quelqu'un qui n'en subit aucun.

## Conséquences

- Une coupure rétablie apparaît dans Grafana (deux panneaux ajoutés au tableau
  « Live Streaming », section Métier) et devient un candidat d'alerte sur la
  fréquence.
- Le diffuseur peut redire ce qui n'est pas parti. C'est le seul des trois
  changements qui modifie l'usage.
- Le raccord reste sans silence : l'auditeur perd toujours le contenu de la
  coupure sans le savoir. Assumé, et documenté ci-dessous comme limite.

## Limites connues

**L'auditeur n'est toujours pas informé de la perte de contenu.** Le faire
proprement demanderait soit un flux d'événements public, soit un
`EXT-X-DISCONTINUITY` dans le manifeste — le marqueur que HLS prévoit exactement
pour ça, qui n'insère pas de silence mais signale au lecteur que la ligne de
temps est rompue. C'est la bonne réponse au niveau du format ; elle demande de
piloter le segmenteur et sort du périmètre.

**La résilience perçue vient du tampon, pas du serveur.** La coupure de 20 s est
passée inaperçue parce que la fenêtre HLS fait ~60 s et que l'auditeur n'était
pas au bord du direct. Une coupure plus longue, ou un auditeur qui vient de
rejoindre avec un ou deux segments d'avance, l'entendrait. Ne jamais présenter
ce résultat comme « les coupures sont invisibles ».

**Le cas du monitoring audio industriel reste mal servi.** Un raccord invisible
produit un enregistrement qui ment sur la continuité de ce qu'il a capté. Là, du
silence signalé serait strictement meilleur qu'un raccord muet — c'est un
arbitrage différent, pour un usage différent de la radio.

## Alternatives écartées

**Injecter du silence pour recaler la ligne de temps sur l'horloge murale.**
Ferait correspondre la durée du média à la durée réelle, au prix d'un segmenteur
à état — et livrerait à l'auditeur… du vide. On préfère qu'il entende un raccord
plutôt qu'un blanc.

**Afficher « Reconnexion… » à l'auditeur pendant une coupure diffuseur.**
Lui montrerait un incident qu'il ne subit pas, tant que son tampon tient. Et
quand le tampon ne tient plus, son propre lecteur affiche déjà l'état.

**Réutiliser `stream_interruptions_total` avec une raison `recovered`.**
Mélangerait dans une même famille des diffusions terminées et des diffusions qui
continuent. Les alertes existantes sur les interruptions se déclencheraient sur
des reprises réussies.
