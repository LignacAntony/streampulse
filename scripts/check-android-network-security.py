#!/usr/bin/env python3
"""Verrouille la politique de trafic en clair de l'app Android (STR-240).

Le correctif d'origine ne tenait qu'à la vigilance du relecteur : rien
n'empêchait un commit ultérieur de rebasculer `cleartextTrafficPermitted` à
`true`, de ré-ajouter `android:usesCleartextTraffic` au manifeste, ou de
supprimer la configuration — c'est-à-dire de rouvrir le trou sans bruit.

Exécutable en local (`make check-android-security`) comme en CI : un contrôle
qu'on ne peut pas rejouer sur son poste n'en est pas un.
"""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID = "{http://schemas.android.com/apk/res/android}"
APP = Path("mobile/android/app/src")

MAIN_CONFIG = APP / "main/res/xml/network_security_config.xml"
MANIFEST = APP / "main/AndroidManifest.xml"
DEV_CONFIGS = [
    APP / "debug/res/xml/network_security_config.xml",
    APP / "profile/res/xml/network_security_config.xml",
]

# Le clair reste toléré vers la boucle locale : ce trafic ne quitte pas
# l'appareil. Toute autre adresse ici serait une régression.
ALLOWED_CLEARTEXT_DOMAINS = {"localhost", "127.0.0.1"}

errors: list[str] = []


def fail(msg: str) -> None:
    errors.append(msg)


def canonical(node: ET.Element) -> tuple:
    """Structure comparable d'un élément, commentaires et espaces exclus."""
    return (
        node.tag,
        tuple(sorted(node.attrib.items())),
        tuple(canonical(child) for child in node if isinstance(child.tag, str)),
        (node.text or "").strip(),
    )


def check_release_config() -> None:
    if not MAIN_CONFIG.exists():
        fail(f"{MAIN_CONFIG} est absent — les builds release n'auraient plus de politique réseau")
        return

    root = ET.parse(MAIN_CONFIG).getroot()

    base = root.find("base-config")
    if base is None:
        fail(f"{MAIN_CONFIG} : pas de <base-config>, le défaut Android (clair autorisé) s'appliquerait")
    elif base.get("cleartextTrafficPermitted") != "false":
        fail(
            f"{MAIN_CONFIG} : base-config cleartextTrafficPermitted="
            f'"{base.get("cleartextTrafficPermitted")}", attendu "false" — '
            "les builds release pourraient émettre du HTTP en clair"
        )

    for cfg in root.findall("domain-config"):
        if cfg.get("cleartextTrafficPermitted") != "true":
            continue
        for dom in cfg.findall("domain"):
            name = (dom.text or "").strip()
            if name not in ALLOWED_CLEARTEXT_DOMAINS:
                fail(
                    f"{MAIN_CONFIG} : le clair est autorisé vers {name!r}, hors de la boucle "
                    f"locale {sorted(ALLOWED_CLEARTEXT_DOMAINS)} — à justifier explicitement"
                )


def check_manifest() -> None:
    if not MANIFEST.exists():
        fail(f"{MANIFEST} est absent")
        return

    app = ET.parse(MANIFEST).getroot().find("application")
    if app is None:
        fail(f"{MANIFEST} : pas d'élément <application>")
        return

    if app.get(f"{ANDROID}usesCleartextTraffic") is not None:
        fail(
            f"{MANIFEST} : android:usesCleartextTraffic est de retour. Cet attribut "
            "s'applique à toutes les variantes, release comprise, et prend le pas sur "
            "l'intention par variante — utiliser networkSecurityConfig."
        )

    if app.get(f"{ANDROID}networkSecurityConfig") is None:
        fail(f"{MANIFEST} : android:networkSecurityConfig absent, aucune politique n'est appliquée")


def check_dev_configs_agree() -> None:
    """Les variantes de développement doivent porter la même politique.

    Elles sont volontairement dupliquées — le modèle de source sets Android
    n'offre pas d'inclusion — mais une divergence serait silencieuse. Seule la
    structure est comparée : les commentaires peuvent différer (chacun nomme sa
    variante).
    """
    present = [p for p in DEV_CONFIGS if p.exists()]
    if len(present) != len(DEV_CONFIGS):
        missing = [str(p) for p in DEV_CONFIGS if not p.exists()]
        fail(
            f"configuration de développement manquante : {missing} — cette variante "
            "retomberait sur la politique release et ne joindrait plus l'API locale"
        )
        return

    shapes = {p: canonical(ET.parse(p).getroot()) for p in present}
    first, *rest = present
    for other in rest:
        if shapes[other] != shapes[first]:
            fail(
                f"{first} et {other} ont divergé. Les variantes de développement "
                "doivent porter la même politique ; répercuter la modification, ou "
                "documenter pourquoi elles diffèrent désormais."
            )


def main() -> int:
    if not APP.exists():
        print(f"::error::{APP} introuvable — lancer depuis la racine du dépôt", file=sys.stderr)
        return 1

    check_release_config()
    check_manifest()
    check_dev_configs_agree()

    if errors:
        for err in errors:
            print(f"::error::{err}", file=sys.stderr)
        print(f"\n{len(errors)} régression(s) de politique réseau Android.", file=sys.stderr)
        return 1

    print("politique réseau Android : clair refusé en release, boucle locale seule exception,")
    print("variantes de développement alignées.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
