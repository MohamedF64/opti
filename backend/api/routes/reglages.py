"""Réglages › Budget : limite manuelle, mode économies max, épargne visée, jours de paie."""
import asyncio
from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

import budget
import reglages
from routes.commun import PROPRIETAIRE

router = APIRouter(dependencies=PROPRIETAIRE)


class Reglages(BaseModel):
    jour_paie_min: int | None = Field(default=None, ge=1, le=31)
    jour_paie_max: int | None = Field(default=None, ge=1, le=31)
    limite_manuelle: float | None = Field(default=None, gt=0, le=1000)   # null : pas de limite manuelle
    mode_economies_max: bool | None = None
    epargne_visee: float | None = Field(default=None, ge=0, le=100_000)  # null : proposée par les objectifs


def _modifs(req: Reglages, actuels: dict[str, Any]) -> dict[str, Any]:
    modifs = req.model_dump(exclude_unset=True)
    if modifs.get("mode_economies_max") is None:
        modifs.pop("mode_economies_max", None)
    for cle in ("jour_paie_min", "jour_paie_max"):
        if cle in modifs and modifs[cle] is None:
            modifs.pop(cle)
    if {**actuels, **modifs}["jour_paie_min"] > {**actuels, **modifs}["jour_paie_max"]:
        raise HTTPException(status_code=422, detail="Le premier jour de paie doit précéder le dernier.")
    return modifs


async def reglages_et_effet(essai: dict[str, Any] | None = None) -> dict[str, Any]:
    try:
        actuels, b = await asyncio.gather(
            reglages.lire(),
            budget.budget_du_jour(essai=reglages.en_base(essai) if essai else None),
        )
    except ValueError as e:
        raise HTTPException(409, str(e))
    return {
        "reglages": {**actuels, **(essai or {})},
        "budget": {"limite_du_jour": b.limite_du_jour, "limite_calculee": b.limite_calculee,
                   "limite_appliquee": b.limite_appliquee, "epargne_visee": b.epargne_visee,
                   "epargne_proposee": b.epargne_proposee, "source_epargne": b.source_epargne,
                   "effet_limite_manuelle": b.effet_limite_manuelle},
    }


@router.get("/reglages")
async def reglages_lire():
    """Réglages du budget et la limite du jour qu'ils donnent."""
    return await reglages_et_effet()


@router.post("/reglages/apercu")
async def reglages_apercu(req: Reglages):
    """« Ta limite passerait de X à Y » : calcule sans rien enregistrer."""
    return await reglages_et_effet(_modifs(req, await reglages.lire()))


@router.patch("/reglages")
async def reglages_modifier(req: Reglages):
    modifs = _modifs(req, await reglages.lire())
    if not modifs:
        raise HTTPException(status_code=422, detail="Rien à modifier.")
    await reglages.ecrire(modifs)
    return await reglages_et_effet()
