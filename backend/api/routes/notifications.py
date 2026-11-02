"""Notifications (docs/regles-de-calcul.md § 10)."""
import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

import notifications
from routes.commun import PROPRIETAIRE

router = APIRouter(dependencies=PROPRIETAIRE)


class Appareil(BaseModel):
    jeton: str = Field(min_length=10, max_length=4096)
    nom: str | None = Field(default=None, max_length=100)


class ReglagesNotifications(BaseModel):
    renouvellement: bool | None = None
    panne: bool | None = None
    limite: bool | None = None
    paie: bool | None = None
    essai: bool | None = None
    abonnement: bool | None = None
    catalogue: bool | None = None
    promos: bool | None = None


async def avec_firebase(appel):
    """Firebase en panne : 502 avec un message clair (la base, elle, est gérée dans index.py)."""
    try:
        return await appel
    except (notifications.FcmError, httpx.HTTPError) as e:
        raise HTTPException(502, f"Firebase indisponible : {e}")


@router.post("/notifications/appareil")
async def notifications_appareil(req: Appareil):
    """Le téléphone donne son jeton Firebase (à chaque ouverture : il peut changer)."""
    await notifications.enregistrer_appareil(req.jeton, req.nom)
    return {"ok": True}


@router.get("/notifications/reglages")
async def notifications_reglages():
    return await notifications.reglages()


@router.patch("/notifications/reglages")
async def notifications_modifier(req: ReglagesNotifications):
    modifs = {k: v for k, v in req.model_dump().items() if v is not None}
    if not modifs:
        raise HTTPException(422, "Rien à modifier.")
    return await notifications.modifier_reglages(modifs)


@router.post("/notifications/test")
async def notifications_test():
    """« Envoyer une notification de test » depuis les Réglages : envoyée 10 s plus tard, le temps de quitter Opti."""
    return await avec_firebase(notifications.tester(notifications.DELAI_TEST))
