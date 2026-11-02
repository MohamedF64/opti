"""Accueil, Historique et Stats (docs/regles-de-calcul.md § 1 à 3, 6, 8)."""
import asyncio
from datetime import date
from typing import Any

from fastapi import APIRouter, HTTPException, Query

import budget
import conseils
import db
import historique
import stats
import synchro
from routes.commun import PROPRIETAIRE, aujourdhui

router = APIRouter(dependencies=PROPRIETAIRE)


async def ecran_accueil() -> dict[str, Any]:
    """Tout ce qu'affiche l'écran d'accueil, calculé côté serveur."""
    try:
        resultat, operations, comptes = await asyncio.gather(
            budget.budget_du_jour(),
            db.select("transactions",
                      select="id,date,amount,description,merchant,category,status,is_internal,goal_id,bank_name",
                      date=f"eq.{aujourdhui().isoformat()}", order="amount.asc"),
            synchro.etat_des_comptes(),
        )
    except ValueError as e:
        raise HTTPException(409, str(e))
    return {
        "budget": resultat,
        "operations_du_jour": [o for o in operations if not o.get("is_internal")],
        "comptes": comptes,
    }


@router.get("/budget/aujourdhui")
async def budget_aujourdhui():
    """Écran d'accueil : « tu peux encore dépenser », « Pourquoi X € ? », opérations du jour, comptes."""
    return await ecran_accueil()


@router.get("/operations")
async def operations_historique(jusqu_au: date | None = None, recherche: str | None = None, banque: str | None = None):
    """Écran Historique : 14 jours d'opérations jusqu'à `jusqu_au` (aujourd'hui par défaut), ou une recherche."""
    return await historique.operations(jusqu_au or aujourdhui(), recherche, banque)


@router.get("/conseils")
async def conseils_accueil():
    """Carte « Conseils » de l'accueil : 3 au maximum (docs/regles-de-calcul.md § 6)."""
    return {"conseils": await conseils.ecran()}


@router.get("/bilan")
async def bilan_du_cycle():
    """Carte « Bilan du cycle » de l'accueil : le cycle qui vient de finir, 3 jours après la paie (sinon null)."""
    return {"bilan": await stats.ecran_bilan()}


async def ecran_stats(periode: str) -> Any:
    if periode not in stats.PERIODES:
        raise HTTPException(422, f"Période inconnue : {periode} (attendu : {', '.join(stats.PERIODES)})")
    return await stats.ecran(periode)


@router.get("/stats")
async def stats_ecran(periode: str = "cycle"):
    """Écran Stats : cycles de la période (cycle, precedent, 6 ou 12), donut par catégorie, bilan."""
    return await ecran_stats(periode)


@router.get("/stats/operations")
async def stats_operations(debut: date, fin: date, categorie: list[str] = Query(...)):
    """Dépenses d'une part du donut (« Le reste » : plusieurs `categorie`)."""
    return {"operations": await stats.operations_de_categories(debut, fin, categorie)}
