"""Réglages du budget (table settings, une ligne clé / valeur par réglage).

Noms côté app → clés en base. Une valeur None retire la ligne (= réglage automatique).
"""
import asyncio
from typing import Any

import db

CLES = {
    "jour_paie_min": "salary_day",
    "jour_paie_max": "salary_day_max",
    "limite_manuelle": "limite_manuelle",
    "mode_economies_max": "mode_economies_max",
    "epargne_visee": "epargne_visee",
}


def en_base(valeurs: dict[str, Any]) -> dict[str, str | None]:
    """{"limite_manuelle": 40.0, "mode_economies_max": True} → {"limite_manuelle": "40.0", "mode_economies_max": "true"}."""
    resultat: dict[str, str | None] = {}
    for nom, valeur in valeurs.items():
        if valeur is None:
            resultat[CLES[nom]] = None
        elif isinstance(valeur, bool):
            resultat[CLES[nom]] = "true" if valeur else "false"
        else:
            resultat[CLES[nom]] = str(valeur)
    return resultat


def depuis_base(lignes: list[dict[str, Any]]) -> dict[str, Any]:
    brut = {r["key"]: r["value"] for r in lignes}

    def nombre(cle: str) -> float | None:
        try:
            return float(brut[cle]) if brut.get(cle) not in (None, "") else None
        except ValueError:
            return None

    return {
        "jour_paie_min": int(brut.get("salary_day") or 21),
        "jour_paie_max": int(brut.get("salary_day_max") or 28),
        "limite_manuelle": nombre("limite_manuelle"),
        "mode_economies_max": (brut.get("mode_economies_max") or "").lower() == "true",
        "epargne_visee": nombre("epargne_visee"),
    }


async def lire() -> dict[str, Any]:
    return depuis_base(await db.select("settings", key=f"in.({','.join(CLES.values())})"))


async def ecrire(valeurs: dict[str, Any]) -> None:
    existantes = {r["key"] for r in await db.select("settings", select="key", key=f"in.({','.join(CLES.values())})")}
    ecritures = []
    for cle, valeur in en_base(valeurs).items():
        if valeur is None:
            if cle in existantes:
                ecritures.append(db.delete("settings", key=f"eq.{cle}"))
        elif cle in existantes:
            ecritures.append(db.update("settings", {"value": valeur}, key=f"eq.{cle}"))
        else:
            ecritures.append(db.insert("settings", {"key": cle, "value": valeur}))
    await asyncio.gather(*ecritures)
