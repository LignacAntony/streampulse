#!/usr/bin/env python3
"""Vérifie que l'index anglais des décisions couvre toutes les ADR.

Le périmètre bilingue déclaré dans `docs/README.md` promet que *chaque*
décision d'architecture est résumée en anglais. Cette promesse ne tient qu'un
temps sans garde : une ADR ajoutée sans son entrée laisse un index qui prétend
être exhaustif et ne l'est plus — et le prochain lecteur anglophone n'a aucun
moyen de savoir ce qui lui manque.

# Asymétrie volontaire

  Fichier sans entrée   → **erreur**. C'est l'oubli qu'on veut attraper.
  Entrée sans fichier   → toléré, et signalé. Une entrée peut précéder son
                          fichier quand deux branches avancent en parallèle :
                          l'index annonce alors une décision en cours de
                          fusion. L'inverse ne se produit jamais par
                          inadvertance.

Usage :

    make check-adr-index
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ADR_DIR = REPO / "docs" / "adr"
INDEX = REPO / "docs" / "en" / "adr-index.md"

FICHIER = re.compile(r"^(\d{3})-")
ENTREE = re.compile(r"^\*\*ADR (\d{3}) —", re.M)


def main() -> int:
    if not ADR_DIR.is_dir():
        print(f"répertoire ADR introuvable : {ADR_DIR}", file=sys.stderr)
        return 2
    if not INDEX.is_file():
        print(f"index anglais introuvable : {INDEX}", file=sys.stderr)
        return 2

    fichiers = {
        m.group(1)
        for f in ADR_DIR.glob("*.md")
        if (m := FICHIER.match(f.name))
    }
    entrees = set(ENTREE.findall(INDEX.read_text(encoding="utf-8")))

    manquantes = sorted(fichiers - entrees)
    en_avance = sorted(entrees - fichiers)

    if en_avance:
        print(
            "Entrées d'index sans ADR correspondante (décision en cours de "
            f"fusion ?) : {', '.join(en_avance)}"
        )

    if manquantes:
        print(
            f"\n{len(manquantes)} ADR absente(s) de l'index anglais :",
            file=sys.stderr,
        )
        for num in manquantes:
            nom = next(f.name for f in ADR_DIR.glob(f"{num}-*.md"))
            print(f"  - {nom}", file=sys.stderr)
        print(
            "\nAjouter une entrée dans docs/en/adr-index.md, au format :\n"
            "  **ADR NNN — Titre anglais.** *Context:* … *Decision:* … "
            "*Consequence:* …\n"
            "Le périmètre bilingue de docs/README.md promet que l'index est "
            "exhaustif.",
            file=sys.stderr,
        )
        return 1

    print(f"Index anglais complet : {len(fichiers)} ADR, toutes résumées.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
