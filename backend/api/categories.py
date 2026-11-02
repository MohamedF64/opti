"""Changer la catégorie d'une dépense — voir docs/regles-de-calcul.md § 9 (validé le 01/11/2026).

« Retenir pour ce marchand » : le choix est gardé dans `merchant_categories`, appliqué à toutes les dépenses
passées de ce marchand, et la synchro le reprend pour les suivantes (synchro.categoriser).
"""
from datetime import datetime, timezone
from typing import Any

import db
import erreurs
import synchro

CATEGORIES = ("Alimentation", "Restauration", "Shopping", "Transport", "Loisirs", "Sport", "Santé",
              "Maison", "Abonnement", "Assurance", "Distributeur", "Cadeau", "Dons", "Virement émis", "Autre")


class ActionRefusee(erreurs.ActionRefusee):
    """Refus métier, avec un message affichable tel quel."""


def cle(operation: dict[str, Any]) -> str:
    return synchro.cle_marchand(operation.get("merchant") or operation.get("description") or "")


def est_depense(operation: dict[str, Any]) -> bool:
    """Seules les dépenses se reclassent : ni virements entre comptes, ni entrées d'argent."""
    return float(operation["amount"]) < 0 and not operation.get("is_internal")


def a_reclasser(marchand: str, categorie: str, operations: list[dict[str, Any]]) -> list[str]:
    """Identifiants des dépenses de ce marchand qui ne sont pas encore dans la catégorie choisie."""
    return [o["id"] for o in operations
            if est_depense(o) and o.get("category") != categorie and synchro.meme_marchand(cle(o), marchand)]


async def changer(transaction_id: str, categorie: str, retenir: bool) -> dict[str, Any]:
    if categorie not in CATEGORIES:
        raise ActionRefusee("Catégorie inconnue.")
    lignes = await db.select("transactions", id=f"eq.{transaction_id}",
                             select="id,amount,is_internal,merchant,description,category,status")
    if not lignes:
        raise ActionRefusee("Opération introuvable.")
    operation = lignes[0]
    if not est_depense(operation):
        raise ActionRefusee("Seules les dépenses changent de catégorie.")
    marchand = cle(operation)
    # Une dépense en attente est remplacée à chaque synchro : sans règle, le choix serait perdu.
    retenir = (retenir or operation.get("status") == "pending") and len(marchand) >= synchro.MARCHAND_MIN

    if not retenir:
        await db.update("transactions", {"category": categorie}, id=f"eq.{transaction_id}")
        return {"categorie": categorie, "retenu": False, "modifiees": 1}

    # Changer d'avis remplace la règle : les anciennes règles du même marchand disparaissent.
    anciennes = [r["cle"] for r in await db.select("merchant_categories", select="cle")
                 if r["cle"] != marchand and synchro.meme_marchand(r["cle"], marchand)]
    for ancienne in anciennes:
        await db.delete("merchant_categories", cle=f"eq.{ancienne}")
    await db.upsert("merchant_categories", {"cle": marchand, "categorie": categorie,
                                            "updated_at": datetime.now(timezone.utc).isoformat()})
    depenses = await db.select_tout("transactions", select="id,amount,is_internal,merchant,description,category",
                                    amount="lt.0", is_internal="eq.false")
    ids = a_reclasser(marchand, categorie, depenses)
    if ids:
        await db.update("transactions", {"category": categorie}, id=f"in.({','.join(ids)})")
    return {"categorie": categorie, "retenu": True, "modifiees": len(ids)}
