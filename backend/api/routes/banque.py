"""Banques : synchro à l'ouverture de l'app, état des accès, renouvellement (Enable Banking)."""
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

import banque as bq
import synchro
from routes.commun import PROPRIETAIRE

router = APIRouter(dependencies=PROPRIETAIRE)


class ConnexionRequest(BaseModel):
    banque: str  # « CIC » ou « Revolut »


@router.post("/banque/synchro")
async def banque_synchro(request: Request):
    """Récupère soldes et opérations de tous les comptes reliés (à l'ouverture de l'app).

    Le propriétaire est présent : on transmet son adresse IP et son navigateur à la banque."""
    ip = (request.headers.get("x-forwarded-for") or (request.client.host if request.client else "")).split(",")[0].strip()
    psu = {k: v for k, v in {"Psu-Ip-Address": ip, "Psu-User-Agent": request.headers.get("user-agent", "")}.items() if v}
    return {"comptes": await synchro.synchroniser(psu=psu)}


@router.get("/banque/etat")
async def banque_etat():
    """Pour l'écran Comptes : soldes, dernière synchro, jours de consentement restants."""
    return await synchro.etat_des_comptes()


@router.post("/banque/connexion")
async def banque_connexion(req: ConnexionRequest):
    """Démarre l'autorisation : renvoie l'adresse de la banque à ouvrir dans le navigateur."""
    try:
        return {"url": await bq.demarrer_connexion(req.banque)}
    except bq.ConnexionError as e:
        raise HTTPException(400, str(e))
