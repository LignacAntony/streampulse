#!/usr/bin/env python3
"""Porte de qualité : échoue si la couverture Go passe sous le seuil.

Le sujet exige « un code testable unitairement à 80 % minimum ». Sans cette
porte, `ci.yml` produisait bien un `coverage.txt` mais l'archivait sans jamais
le lire : une PR faisant tomber la couverture à 10 % passait au vert.

# Le périmètre est déclaré, et c'est ce qui rend le seuil défendable

Un seuil calculé sur un périmètre flou ne veut rien dire — on peut le tenir en
ajoutant du code trivial, ou le rater à cause de code que personne ne peut
tester. Quatre familles sont donc exclues du calcul, chacune pour une raison
qui tient :

  internal/*/db/            Code généré par sqlc. Le tester reviendrait à
                            tester sqlc. Il est réécrit à chaque `sqlc
                            generate` et n'a pas d'auteur.

  cmd/api/                  Racine de composition : construit la config, ouvre
                            le pool, monte les routes, écoute. L'exercer
                            demanderait de démarrer le serveur, ce qui relève
                            d'un test de bout en bout — un chantier distinct,
                            pas un test unitaire.

  internal/infrastructure/  Enveloppes minces sur des pilotes tiers (migrate,
                            pgx). Les tester serait tester les pilotes ; leur
                            comportement réel est vérifié par les tests
                            d'intégration, qui passent par eux.

  internal/testsupport/     Le socle de test lui-même. Sa couverture est un
                            artefact : il n'est exécuté que par d'autres tests.

Tout le reste — handlers, services, repositories, middlewares, configuration —
est dans le périmètre.

# Usage

    make coverage            # unitaires seuls, informatif
    make coverage-gate       # unitaires + intégration, échoue sous le seuil

Ou directement :

    go test ./... -coverprofile=cov.out -covermode=count
    python3 scripts/check-coverage.py cov.out [seuil]
"""

from __future__ import annotations

import collections
import re
import sys
from pathlib import Path

MODULE = "github.com/LignacAntony/streampulse/"
SEUIL_DEFAUT = 80.0

# Chaque motif est un préfixe ou un fragment de chemin, avec sa justification
# — celle-ci est affichée dans le rapport pour qu'un lecteur n'ait pas à venir
# lire ce fichier pour savoir ce qui est compté.
EXCLUSIONS = (
    ("/db/", "code généré par sqlc"),
    ("cmd/api/", "racine de composition, relève d'un test de bout en bout"),
    ("internal/infrastructure/", "enveloppes minces sur des pilotes tiers"),
    ("internal/testsupport/", "socle de test"),
)

LIGNE = re.compile(r"^(.*?):\d+\.\d+,\d+\.\d+ (\d+) (\d+)$")


def exclu(chemin: str) -> str | None:
    """Rend le premier motif d'exclusion couvrant `chemin`, ou None.

    Rend le motif et non la raison : c'est lui qui sert de clé d'attribution
    dans le récapitulatif, et un motif est unique là où deux exclusions
    pourraient partager une formulation.
    """
    for motif, _ in EXCLUSIONS:
        if motif in chemin:
            return motif
    return None


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(f"usage: {argv[0]} <profil.out> [seuil]", file=sys.stderr)
        return 2

    profil = Path(argv[1])
    seuil = float(argv[2]) if len(argv) > 2 else SEUIL_DEFAUT

    if not profil.is_file():
        print(f"profil de couverture introuvable : {profil}", file=sys.stderr)
        return 2

    lignes = profil.read_text().splitlines()
    if len(lignes) < 2:
        print(f"profil vide : {profil} — les tests ont-ils tourné ?", file=sys.stderr)
        return 2

    dans = collections.defaultdict(lambda: [0, 0])
    hors = collections.defaultdict(lambda: [0, 0])

    for ligne in lignes[1:]:  # la première ligne porte le mode
        m = LIGNE.match(ligne)
        if not m:
            continue
        chemin = m.group(1).replace(MODULE, "")
        n, atteint = int(m.group(2)), int(m.group(3))
        cible = hors if exclu(chemin) else dans
        paquet = chemin.rsplit("/", 1)[0]
        cible[paquet][1] += n
        if atteint > 0:
            cible[paquet][0] += n

    couverts = sum(v[0] for v in dans.values())
    total = sum(v[1] for v in dans.values())
    if total == 0:
        print("aucun statement dans le périmètre — exclusions trop larges ?", file=sys.stderr)
        return 2

    pct = 100.0 * couverts / total

    print("Couverture par paquet (périmètre déclaré)")
    print(f"{'couv':>8}  {'stmts':>11}  paquet")
    for paquet, (c, n) in sorted(dans.items(), key=lambda kv: kv[1][0] / kv[1][1]):
        print(f"{100.0 * c / n:7.1f}%  {c:5}/{n:<5} {paquet}")

    # Chaque paquet est attribué au **premier** motif qui le couvre, comme le
    # fait `exclu()`. Le compter sous chaque motif correspondant ferait dépasser
    # le total à la moindre exclusion qui en recoupe une autre — un futur
    # `internal/infrastructure/.../db/` relèverait des deux — et le lecteur ne
    # pourrait plus recouper le détail avec le total.
    exclus_total = sum(v[1] for v in hors.values())
    par_motif: dict[str, int] = {motif: 0 for motif, _ in EXCLUSIONS}
    for chemin, (_, n) in hors.items():
        motif = exclu(chemin + "/")
        if motif is not None:
            par_motif[motif] += n

    print(f"\nExclus du calcul : {exclus_total} statements")
    for motif, raison in EXCLUSIONS:
        if par_motif[motif]:
            print(f"  {par_motif[motif]:5} — {motif:26} {raison}")

    print(f"\nPérimètre déclaré : {couverts}/{total} = {pct:.2f}%")
    print(f"Seuil exigé       : {seuil:.2f}%")

    if pct + 1e-9 < seuil:
        manque = int((seuil / 100.0) * total) - couverts + 1
        print(
            f"\n❌ Sous le seuil de {seuil - pct:.2f} point(s) — "
            f"environ {manque} statements à couvrir.",
            file=sys.stderr,
        )
        return 1

    print(f"\n✅ Seuil tenu (marge : {pct - seuil:.2f} point).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
