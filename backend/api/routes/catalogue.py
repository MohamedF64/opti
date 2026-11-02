"""Catalogue de prix et bons plans (docs/regles-de-calcul.md § 12)."""
from uuid import UUID

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

import bons_plans
import catalogue
from routes.commun import PROPRIETAIRE, aujourdhui

router = APIRouter(dependencies=PROPRIETAIRE)


class Profil(BaseModel):
    etudiant: bool | None = None
    moins_26: bool | None = None
    age_18_24: bool | None = None


class Ligne(BaseModel):
    nom: str = Field(min_length=1, max_length=40)
    offre_id: UUID | None = None
    prix: float | None = Field(default=None, ge=0, le=10_000)   # prix moyen de la ligne, par mois
    go: int | None = Field(default=None, ge=0, le=10_000)


class Lignes(BaseModel):
    lignes: list[Ligne] = Field(max_length=10)


class ValidationPage(BaseModel):
    prix: dict[UUID, float] = Field(default_factory=dict, max_length=20)   # offre → nouveau prix ; vide : rien ne change


class VerifOffre(BaseModel):
    prix: float | None = Field(default=None, ge=0, le=10_000)    # absent : « rien ne change »


class Enseigne(BaseModel):
    nom: str = Field(min_length=2, max_length=40)
    suivie: bool


@router.get("/catalogue")
async def catalogue_ecran():
    """Écran Catalogue : abonnements et leurs offres moins chères, offres groupées, catalogue daté."""
    return await catalogue.ecran(aujourdhui())


@router.patch("/catalogue/profil")
async def catalogue_profil(req: Profil):
    valeurs = req.model_dump(exclude_none=True)
    if not valeurs:
        raise HTTPException(status_code=422, detail="Rien à modifier.")
    return await catalogue.modifier_profil(valeurs)


@router.put("/abonnements/{abonnement_id}/lignes")
async def abonnements_lignes(abonnement_id: UUID, req: Lignes):
    """Rattachement au catalogue : les lignes de l'abonnement (une seule le plus souvent), liste vide = détacher."""
    lignes = [l.model_dump() | {"offre_id": str(l.offre_id) if l.offre_id else None} for l in req.lignes]
    return {"lignes": await catalogue.changer_lignes(str(abonnement_id), lignes)}


@router.post("/catalogue/services/{service_id}/valider")
async def catalogue_valider_page(service_id: UUID, req: ValidationPage):
    """« Une page de prix a changé » : nouveaux prix en un clic, ou « Rien ne change »."""
    if any(not 0 <= p <= 10_000 for p in req.prix.values()):
        raise HTTPException(422, "Prix invalide.")
    await catalogue.valider_page(str(service_id), {str(k): v for k, v in req.prix.items()}, aujourdhui())
    return {"ok": True}


@router.post("/catalogue/offres/{offre_id}/verifier")
async def catalogue_verifier_offre(offre_id: UUID, req: VerifOffre):
    """Offre vérifiée à la main : nouveau prix éventuel, date de vérification = aujourd'hui."""
    return await catalogue.verifier_offre(str(offre_id), req.prix, aujourdhui())


@router.get("/bons-plans")
async def bons_plans_ecran():
    """Page « Bons plans » : bons plans Dealabs de moins de 7 jours pour les enseignes suivies, essais gratuits."""
    return await bons_plans.ecran(aujourdhui())


@router.post("/bons-plans/enseignes")
async def bons_plans_enseigne(req: Enseigne):
    """Ajouter (suivie) ou retirer une enseigne."""
    await bons_plans.choisir_enseigne(req.nom, req.suivie)
    return {"ok": True}
