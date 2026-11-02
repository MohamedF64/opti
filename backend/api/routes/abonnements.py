"""Abonnements (docs/regles-de-calcul.md § 7 et § 11)."""
from datetime import date
from uuid import UUID

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

import abonnements as abos
from routes.commun import PROPRIETAIRE, aujourdhui

router = APIRouter(dependencies=PROPRIETAIRE)


class NouvelAbonnement(BaseModel):
    nom: str = Field(min_length=1, max_length=60)
    montant: float = Field(gt=0, le=100_000)
    frequence: str = Field(default="mensuel", pattern="^(hebdomadaire|mensuel|trimestriel|annuel)$")
    categorie: str | None = Field(default=None, max_length=40)
    libelle: str | None = Field(default=None, min_length=2, max_length=60)   # tel qu'il apparaît sur le relevé
    essai_jusqu_au: date | None = None   # essai gratuit : date de fin (§ 11)


class ModifAbonnement(BaseModel):
    nom: str | None = Field(default=None, min_length=1, max_length=60)
    montant: float | None = Field(default=None, gt=0, le=100_000)
    montant_auto: bool | None = None                 # True : revenir au montant calculé
    frequence: str | None = Field(default=None, pattern="^(hebdomadaire|mensuel|trimestriel|annuel)$")
    categorie: str | None = Field(default=None, max_length=40)
    usage: str | None = Field(default=None, pattern="^(jamais|parfois|souvent|toujours)$")
    libelles: list[str] | None = Field(default=None, max_length=10)
    mois_pause: list[int] | None = Field(default=None, max_length=11)
    statut: str | None = Field(default=None, pattern="^(active|cancelled)$")
    essai_garde: bool | None = None                  # « Tu l'as gardé ? Oui » à la fin d'un essai
    prix_maximum: float | None = Field(default=None, gt=0, le=100_000)   # null : retirer le maximum


class AjoutDetecte(BaseModel):
    nom: str | None = Field(default=None, min_length=1, max_length=60)


# Noms de l'API (français) → colonnes de la table subscriptions.
_COLONNES = {"nom": "name", "montant": "amount", "frequence": "frequency", "categorie": "category",
             "statut": "status", "montant_auto": "montant_auto", "usage": "usage", "libelles": "libelles",
             "mois_pause": "mois_pause", "essai_garde": "essai_garde", "prix_maximum": "montant_max"}


@router.get("/abonnements")
async def abonnements_ecran():
    """Écran Abonnements : abonnements calculés, total par mois, propositions « Nouvel abonnement ? »."""
    return await abos.ecran(aujourdhui())


@router.post("/abonnements")
async def abonnements_creer(req: NouvelAbonnement):
    return await abos.creer(req.nom.strip(), req.montant, req.frequence, req.categorie, req.libelle,
                            req.essai_jusqu_au)


@router.patch("/abonnements/{abonnement_id}")
async def abonnements_modifier(abonnement_id: UUID, req: ModifAbonnement):
    valeurs = {_COLONNES[k]: v for k, v in req.model_dump(exclude_unset=True).items()}
    if any(not 1 <= m <= 12 for m in valeurs.get("mois_pause") or []):
        raise HTTPException(status_code=422, detail="Mois de pause invalide.")
    if not valeurs:
        raise HTTPException(status_code=422, detail="Rien à modifier.")
    return await abos.modifier(str(abonnement_id), valeurs)


@router.delete("/abonnements/{abonnement_id}")
async def abonnements_supprimer(abonnement_id: UUID):
    await abos.supprimer(str(abonnement_id))
    return {"ok": True}


@router.post("/abonnements/{abonnement_id}/prix-ok")
async def abonnements_accepter_prix(abonnement_id: UUID):
    await abos.accepter_prix(str(abonnement_id), aujourdhui())
    return {"ok": True}


@router.post("/abonnements/{abonnement_id}/depassement-vu")
async def abonnements_depassement_vu(abonnement_id: UUID):
    await abos.depassement_vu(str(abonnement_id), aujourdhui())
    return {"ok": True}


@router.post("/abonnements/detectes/{cle}/ajouter")
async def abonnements_ajouter_detecte(cle: str, req: AjoutDetecte):
    return await abos.ajouter_detecte(cle, req.nom, aujourdhui())


@router.post("/abonnements/detectes/{cle}/refuser")
async def abonnements_refuser_detecte(cle: str):
    await abos.refuser_detecte(cle, aujourdhui())
    return {"ok": True}
