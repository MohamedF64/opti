"""Preview uniquement (jamais en production) : les écrans sans session, pour vérifier sur les vraies données.

Ces routes ne sont protégées que par la protection Vercel des Preview : ne jamais la désactiver."""
from datetime import date, datetime

from fastapi import APIRouter, HTTPException

import abonnements as abos
import banque as bq
import bons_plans
import budget
import catalogue
import conseils
import db
import enable_banking as eb
import historique
import notifications
import objectifs as obj
import stats
import synchro
import veille
from routes.accueil import ecran_accueil, ecran_stats
from routes.commun import aujourdhui
from routes.notifications import avec_firebase
from routes.reglages import reglages_et_effet

router = APIRouter()


@router.get("/banque/diagnostic")
async def banque_diagnostic():
    """Vérifie les clés Enable Banking et Supabase stockées dans Vercel."""
    try:
        aspsps = await eb.list_aspsps("FR")
        comptes = await db.select("bank_accounts")
    except eb.EnableBankingError as e:
        raise HTTPException(502, str(e))
    return {
        "banques_fr": len(aspsps),
        "consentement_jours": {
            a["name"]: (a.get("maximum_consent_validity") or 0) // 86400
            for a in aspsps if a.get("name", "").lower() in {"cic", "revolut"}
        },
        "comptes_en_base": len(comptes),
        "url_retour": bq.REDIRECT_URL,   # doit être celle déclarée dans l'application Enable Banking
    }


@router.get("/banque/synchro/simulation")
async def banque_synchro_simulation():
    """Calcule la synchro sans rien écrire en base."""
    return await synchro.synchroniser(simulation=True)


@router.get("/budget/apercu")
async def budget_apercu():
    """Le même résultat que /budget/aujourdhui."""
    return await ecran_accueil()


@router.get("/operations/apercu")
async def operations_apercu(jusqu_au: date | None = None, recherche: str | None = None, banque: str | None = None):
    """Le même résultat que GET /operations."""
    return await historique.operations(jusqu_au or aujourdhui(), recherche, banque)


@router.get("/reglages/apercu-preview")
async def reglages_apercu_preview(limite_manuelle: float | None = None, mode_economies_max: bool | None = None):
    """Réglages actuels et effet d'une limite manuelle."""
    essai = {k: v for k, v in {"limite_manuelle": limite_manuelle, "mode_economies_max": mode_economies_max}.items()
             if v is not None}
    return await reglages_et_effet(essai or None)


@router.get("/abonnements/apercu")
async def abonnements_apercu():
    """Le même résultat que GET /abonnements (lecture seule)."""
    return await abos.ecran(aujourdhui())


@router.get("/stats/apercu")
async def stats_apercu(periode: str = "cycle"):
    """Le même résultat que GET /stats."""
    return await ecran_stats(periode)


@router.post("/catalogue/veille-apercu")
async def catalogue_veille_apercu():
    """Relit les pages de prix tout de suite (comme le 1er du mois à 8 h)."""
    return await veille.lire_pages()


@router.post("/bons-plans/collecte-apercu")
async def bons_plans_collecte_apercu():
    """Lit les flux Dealabs tout de suite (comme après une synchro automatique)."""
    return await bons_plans.collecter()


@router.get("/bons-plans/apercu")
async def bons_plans_apercu():
    """Le même résultat que GET /bons-plans."""
    return await bons_plans.ecran(aujourdhui())


@router.get("/catalogue/apercu")
async def catalogue_apercu():
    """Le même résultat que GET /catalogue (lecture seule)."""
    return await catalogue.ecran(aujourdhui())


@router.get("/conseils/apercu")
async def conseils_apercu(jour: date | None = None):
    """Les conseils tels qu'ils seraient ce jour-là."""
    return {"conseils": await conseils.ecran(jour)}


@router.get("/bilan/apercu")
async def bilan_apercu(jour: date | None = None):
    """La carte Bilan telle qu'elle serait ce jour-là."""
    return {"bilan": await stats.ecran_bilan(jour)}


@router.get("/notifications/apercu")
async def notifications_apercu(heure: int | None = None):
    """Ce qui serait envoyé maintenant (ou à `heure`, Paris), sans rien envoyer."""
    maintenant = datetime.now(budget.PARIS)
    if heure is not None:
        maintenant = maintenant.replace(hour=heure)
    return await notifications.calculer(maintenant)


@router.post("/notifications/test-apercu")
async def notifications_test_apercu():
    """Notification de test envoyée de l'ordinateur, Opti fermée sur le téléphone."""
    return await avec_firebase(notifications.tester())


@router.get("/objectifs/apercu")
async def objectifs_apercu():
    """Le même résultat que GET /objectifs (lecture seule)."""
    return await obj.ecran_objectifs(aujourdhui())
