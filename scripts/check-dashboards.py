#!/usr/bin/env python3
"""Valide les dashboards Grafana provisionnés (STR-244, ADR 041).

Ces dashboards sont déclarés `editable: false` : la vérité vit dans git, pas
dans l'UI. Personne ne les ouvre donc avant une mise en production, et une
erreur y est **silencieuse** — Grafana affiche un panneau vide ou une erreur
locale, sans rien faire échouer.

Ce script transforme cette classe de pannes en échec de build. Il vérifie ce
qui casse sans bruit, et rien d'autre :

1. **JSON syntaxiquement valide** — un fichier cassé n'est pas provisionné du tout.
2. **Échappement PromQL des accolades.** Le label `path` contient les patterns du
   routeur (`/api/streams/{id}`). Les matcher exige un `\\\\{` dans le JSON, qui
   donne `\\{` dans la valeur PromQL, que le moteur de regex reçoit comme une
   accolade littérale. Une seule barre oblique inverse et le lexer PromQL rejette
   la requête (« unknown escape sequence ») : le panneau reste vide.
3. **`uid` et `title` présents, `uid` unique** — deux dashboards de même uid, et
   l'un écrase l'autre au provisioning.
4. **`id` de panneau unique dans un dashboard** — un doublon fait disparaître un
   panneau.
5. **Datasources référencées déclarées** dans `datasources.yml`.
6. **Liens croisés pointant sur un dashboard existant** — un lien mort ne se voit
   qu'en cliquant dessus.

Usage : python3 scripts/check-dashboards.py
Sortie : 0 si tout est conforme, 1 sinon (avec le détail sur stderr).
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DASHBOARDS = REPO / "docker/grafana/provisioning/dashboards"
DATASOURCES = REPO / "docker/grafana/provisioning/datasources/datasources.yml"

# Une accolade précédée d'un nombre IMPAIR de barres obliques inverses : le
# lexer PromQL la refusera. Deux (ou tout nombre pair) sont corrects.
LONE_ESCAPE = re.compile(r"(?<!\\)(?:\\\\)*\\[{}]")

# `uid: <valeur>` dans datasources.yml — suffisant et sans dépendance PyYAML,
# le fichier étant plat et versionné avec le script.
DATASOURCE_UID = re.compile(r"^\s*uid:\s*([A-Za-z0-9_-]+)\s*$", re.MULTILINE)


def declared_datasource_uids() -> set[str]:
    if not DATASOURCES.exists():
        return set()
    return set(DATASOURCE_UID.findall(DATASOURCES.read_text(encoding="utf-8")))


def walk_panels(panel: dict):
    """Rend un panneau et tous ses descendants.

    Une row `collapsed: true` porte ses panneaux dans sa propre clé `panels` :
    les oublier laisserait une moitié du dashboard non vérifiée, et c'est
    justement celle qu'on ne regarde pas. Comme les contrôles parcourent la
    liste déjà aplatie par cette fonction, ils couvrent les panneaux imbriqués
    sans avoir à descendre eux-mêmes.
    """
    yield panel
    for nested in panel.get("panels", []):
        yield from walk_panels(nested)


def check_dashboard(path: Path, known_uids: set[str], errors: list[str]) -> dict | None:
    try:
        dashboard = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        errors.append(f"{path.name}: JSON invalide — {exc}")
        return None

    for field in ("uid", "title"):
        if not dashboard.get(field):
            errors.append(f"{path.name}: champ `{field}` manquant ou vide")

    seen_ids: dict[int, str] = {}
    for panel in (p for top in dashboard.get("panels", []) for p in walk_panels(top)):
        pid = panel.get("id")
        title = panel.get("title", "<sans titre>")
        if pid is None:
            errors.append(f"{path.name}: panneau « {title} » sans `id`")
        elif pid in seen_ids:
            errors.append(
                f"{path.name}: `id` {pid} en double — « {title} » et « {seen_ids[pid]} »"
            )
        else:
            seen_ids[pid] = title

        uid = (panel.get("datasource") or {}).get("uid")
        if uid and known_uids and uid not in known_uids:
            errors.append(
                f"{path.name}: panneau « {title} » référence la datasource "
                f"inconnue `{uid}` (déclarées : {', '.join(sorted(known_uids))})"
            )

        for target in panel.get("targets", []):
            expr = target.get("expr", "")
            if LONE_ESCAPE.search(expr):
                errors.append(
                    f"{path.name}: panneau « {title} » — accolade échappée par une "
                    f"seule barre oblique inverse, PromQL la rejettera. "
                    f"Doubler (`\\\\{{`) :\n    {expr}"
                )
    return dashboard


def check_links(dashboards: dict[str, dict], errors: list[str]) -> None:
    known = {d["uid"] for d in dashboards.values() if d.get("uid")}
    for name, dashboard in dashboards.items():
        for link in dashboard.get("links", []):
            url = link.get("url", "")
            if not url.startswith("/d/"):
                continue
            target = url[len("/d/"):].split("/")[0]
            if target not in known:
                errors.append(
                    f"{name}: lien « {link.get('title', url)} » pointe sur le "
                    f"dashboard inconnu `{target}`"
                )


def main() -> int:
    if not DASHBOARDS.is_dir():
        print(f"répertoire introuvable : {DASHBOARDS}", file=sys.stderr)
        return 1

    files = sorted(DASHBOARDS.glob("*.json"))
    if not files:
        print(f"aucun dashboard dans {DASHBOARDS}", file=sys.stderr)
        return 1

    known_uids = declared_datasource_uids()
    errors: list[str] = []
    parsed: dict[str, dict] = {}
    seen_uids: dict[str, str] = {}

    for path in files:
        dashboard = check_dashboard(path, known_uids, errors)
        if dashboard is None:
            continue
        parsed[path.name] = dashboard
        uid = dashboard.get("uid")
        if uid:
            if uid in seen_uids:
                errors.append(
                    f"uid `{uid}` partagé par {seen_uids[uid]} et {path.name} — "
                    "le second écrasera le premier au provisioning"
                )
            else:
                seen_uids[uid] = path.name

    check_links(parsed, errors)

    if errors:
        print("Dashboards Grafana non conformes :\n", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        print(
            f"\n{len(errors)} problème(s) sur {len(files)} dashboard(s).",
            file=sys.stderr,
        )
        return 1

    total_panels = sum(
        len(list(p for top in d.get("panels", []) for p in walk_panels(top)))
        for d in parsed.values()
    )
    print(f"{len(files)} dashboards, {total_panels} panneaux — conformes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
