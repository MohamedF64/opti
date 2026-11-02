"""Objectifs, réserve d'épargne et actions sur une opération (docs/regles-de-calcul.md § 5 et § 9)."""
from datetime import date
from uuid import UUID

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

import categories
import objectifs as obj
from routes.commun import PROPRIETAIRE, aujourdhui

router = APIRouter(dependencies=PROPRIETAIRE)


class NouvelObjectif(BaseModel):
    nom: str = Field(min_length=1, max_length=60)
    cible: float = Field(gt=0, le=1_000_000)
    echeance: date | None = None
    icone: str | None = Field(default=None, max_length=40)


class ModifObjectif(BaseModel):
    nom: str | None = Field(default=None, min_length=1, max_length=60)
    cible: float | None = Field(default=None, gt=0, le=1_000_000)
    echeance: date | None = None
    icone: str | None = Field(default=None, max_length=40)
    statut: str | None = Field(default=None, pattern="^(active|archive)$")


class Mouvement(BaseModel):
    montant: float = Field(ge=-1_000_000, le=1_000_000)   # + mettre de côté, − piocher
    note: str | None = Field(default=None, max_length=200)


class Confirmation(BaseModel):
    transaction_id: UUID | None = None


class Attribution(BaseModel):
    objectif_id: UUID


class Annulation(BaseModel):
    mouvement_ids: list[UUID] = Field(min_length=1, max_length=12)


class ReponseReprise(BaseModel):
    objectif_id: UUID | None = None            # None : « Non, dépense normale »
    depense_ids: list[UUID] = Field(default_factory=list, max_length=50)


class Rattachement(BaseModel):
    objectif_id: UUID | None = None


class ChangementCategorie(BaseModel):
    categorie: str = Field(min_length=1, max_length=40)
    retenir: bool = True


@router.get("/objectifs")
async def objectifs_ecran():
    """Écran Objectifs : objectifs calculés, leurs versements, et les mouvements de la réserve à attribuer."""
    return await obj.ecran_objectifs(aujourdhui())


@router.post("/objectifs")
async def objectifs_creer(req: NouvelObjectif):
    return await obj.creer_objectif(req.nom.strip(), req.cible, req.echeance, req.icone)


@router.patch("/objectifs/{goal_id}")
async def objectifs_modifier(goal_id: UUID, req: ModifObjectif):
    noms = {"nom": "name", "cible": "target_amount", "echeance": "deadline", "icone": "icon", "statut": "status"}
    valeurs = {noms[k]: v for k, v in req.model_dump(exclude_unset=True).items()}
    if not valeurs:
        raise HTTPException(status_code=422, detail="Rien à modifier.")
    return await obj.modifier_objectif(str(goal_id), valeurs)


@router.post("/objectifs/{goal_id}/mouvements")
async def objectifs_mouvement(goal_id: UUID, req: Mouvement):
    if abs(req.montant) < 0.01:
        raise HTTPException(status_code=422, detail="Montant nul.")
    return await obj.declarer_mouvement(str(goal_id), req.montant, req.note)


@router.post("/mouvements/{mouvement_id}/confirmer")
async def mouvements_confirmer(mouvement_id: UUID, req: Confirmation):
    transaction = str(req.transaction_id) if req.transaction_id else None
    return await obj.confirmer_a_la_main(str(mouvement_id), transaction)


@router.post("/mouvements/{mouvement_id}/contester")
async def mouvements_contester(mouvement_id: UUID):
    return await obj.contester(str(mouvement_id))


@router.delete("/mouvements/{mouvement_id}")
async def mouvements_annuler(mouvement_id: UUID):
    await obj.annuler(str(mouvement_id))
    return {"ok": True}


@router.post("/reserve/{transaction_id}/attribuer")
async def reserve_attribuer(transaction_id: UUID, req: Attribution):
    return await obj.attribuer(str(transaction_id), str(req.objectif_id))


@router.get("/reserve/{transaction_id}/annulation")
async def reserve_proposer_annulation(transaction_id: UUID):
    """Les versements qu'un retrait de la réserve annulerait (« C'était une annulation »)."""
    return {"mouvements": await obj.proposer_annulation(str(transaction_id))}


@router.post("/reserve/{transaction_id}/annuler")
async def reserve_annuler(transaction_id: UUID, req: Annulation):
    nombre = await obj.annuler_par_retrait(str(transaction_id), [str(i) for i in req.mouvement_ids])
    return {"versements_supprimes": nombre}


@router.post("/reserve/{transaction_id}/reprise")
async def reserve_repondre_reprise(transaction_id: UUID, req: ReponseReprise):
    """Réponse à « Tu as repris X € de ta tirelire, puis dépensé… C'était pour : »."""
    await obj.repondre_reprise(str(transaction_id), str(req.objectif_id) if req.objectif_id else None,
                               [str(i) for i in req.depense_ids])
    return {"ok": True}


@router.post("/operations/{transaction_id}/ignorer-suggestion")
async def operations_ignorer_suggestion(transaction_id: UUID):
    await obj.ignorer_suggestion(str(transaction_id))
    return {"ok": True}


@router.post("/operations/{transaction_id}/rattacher")
async def operations_rattacher(transaction_id: UUID, req: Rattachement):
    objectif = str(req.objectif_id) if req.objectif_id else None
    ligne = await obj.rattacher_depense(str(transaction_id), objectif)
    return {"id": ligne["id"], "objectif_id": ligne.get("goal_id")}


@router.post("/operations/{transaction_id}/categorie")
async def operations_categorie(transaction_id: UUID, req: ChangementCategorie):
    """Change la catégorie d'une dépense ; « retenir » l'applique à tout le marchand, passé et futur (§ 9)."""
    return await categories.changer(str(transaction_id), req.categorie, req.retenir)
