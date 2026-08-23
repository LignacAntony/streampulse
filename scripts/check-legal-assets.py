#!/usr/bin/env python3
"""Vérifie que les documents légaux embarqués dans l'application sont la copie
exacte de ceux publiés dans docs/.

Deux copies existent parce qu'aucune ne peut être supprimée : docs/ est le
livrable documentaire, et Flutter refuse un asset hors du répertoire du paquet.
Le risque est donc la dérive silencieuse — une correction apportée d'un côté et
pas de l'autre. Un document légal qui ne dit plus la même chose selon qu'on le
lise dans l'application ou dans le dépôt est pire que pas de document du tout.

Comparaison octet à octet, volontairement : normaliser les espaces laisserait
passer une reformulation invisible à l'œil.

Sortie : 0 si les copies concordent, 1 sinon, avec la commande de correction.
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ASSETS = REPO / "mobile" / "assets" / "legal"
DOCS = REPO / "docs"

DOCUMENTS = ("politique-confidentialite.md", "cgu.md")


def main() -> int:
    problemes: list[str] = []

    for nom in DOCUMENTS:
        source = DOCS / nom
        copie = ASSETS / nom

        if not source.is_file():
            problemes.append(f"source absente : {source.relative_to(REPO)}")
            continue
        if not copie.is_file():
            problemes.append(
                f"copie absente : {copie.relative_to(REPO)} — "
                f"l'application afficherait un écran vide"
            )
            continue

        attendu = source.read_bytes()
        obtenu = copie.read_bytes()
        if attendu != obtenu:
            problemes.append(
                f"{copie.relative_to(REPO)} diverge de "
                f"{source.relative_to(REPO)} "
                f"({len(attendu)} octets attendus, {len(obtenu)} trouvés)"
            )

    # L'asset déclaré mais orphelin est l'autre sens de la dérive : un document
    # retiré de docs/ continuerait d'être servi dans l'application.
    if ASSETS.is_dir():
        for fichier in sorted(ASSETS.glob("*.md")):
            if fichier.name not in DOCUMENTS:
                problemes.append(
                    f"{fichier.relative_to(REPO)} n'a pas de source dans docs/ "
                    f"— asset orphelin"
                )

    if problemes:
        print("Documents légaux désynchronisés :", file=sys.stderr)
        for p in problemes:
            print(f"  - {p}", file=sys.stderr)
        print(
            "\nCorriger avec :\n"
            "  cp docs/politique-confidentialite.md docs/cgu.md mobile/assets/legal/",
            file=sys.stderr,
        )
        return 1

    print(f"Documents légaux synchronisés ({len(DOCUMENTS)} fichiers).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
