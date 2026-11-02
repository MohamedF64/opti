"""Écran Historique : toutes les opérations, par tranches de jours entiers (les totaux par jour restent justes)."""
import asyncio
import re
from datetime import date, timedelta
from typing import Any

import db

CHAMPS = "id,date,amount,description,merchant,category,status,is_internal,goal_id,bank_name"
JOURS_PAR_PAGE = 14
RESULTATS_RECHERCHE_MAX = 200
BANQUES = ("CIC", "Revolut")


def nettoyer_recherche(texte: str | None) -> str:
    """Garde lettres, chiffres, espaces, apostrophes et tirets : la recherche part dans un filtre PostgREST,
    où virgules, parenthèses, points et étoiles ont un sens."""
    propre = re.sub(r"[^\w\s'-]", " ", texte or "")
    return re.sub(r"\s+", " ", propre).strip()[:40]


async def operations(jusqu_au: date, recherche: str | None = None, banque: str | None = None) -> dict[str, Any]:
    """Sans recherche : les opérations des 14 jours qui finissent à `jusqu_au`, et la date où reprendre
    (None quand il n'y a plus rien de plus ancien). Avec recherche : les 200 plus récentes qui correspondent."""
    filtres: dict[str, str] = {"order": "date.desc,created_at.desc"}
    if banque in BANQUES:
        filtres["bank_name"] = f"eq.{banque}"
    mot = nettoyer_recherche(recherche)
    if mot:
        motif = f"*{mot}*"
        filtres["or"] = f"(merchant.ilike.{motif},description.ilike.{motif})"
        lignes = await db.select("transactions", select=CHAMPS, limit=str(RESULTATS_RECHERCHE_MAX), **filtres)
        return {"operations": lignes, "suite": None}

    debut = jusqu_au - timedelta(days=JOURS_PAR_PAGE - 1)
    lignes, plus_ancienne = await asyncio.gather(
        db.select("transactions", select=CHAMPS, date=f"gte.{debut.isoformat()}", limit="2000",
                  **{**filtres, "and": f"(date.lte.{jusqu_au.isoformat()})"}),
        db.select("transactions", select="date", order="date.asc", limit="1",
                  **({"bank_name": filtres["bank_name"]} if "bank_name" in filtres else {})),
    )
    suite = debut - timedelta(days=1)
    if not plus_ancienne or date.fromisoformat(str(plus_ancienne[0]["date"])[:10]) > suite:
        suite = None
    return {"operations": lignes, "suite": suite}
