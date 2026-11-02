"""Routes sans session : santé, pages légales, retour de la banque (protégé par un state) et cron (secret)."""
import os
import secrets
import sys
from html import escape as html_escape

import httpx
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import HTMLResponse

import banque as bq
import bons_plans
import db
import enable_banking as eb
import notifications
import synchro
import veille

router = APIRouter()


@router.get("/")
def root():
    return {"status": "ok", "message": "Budget App API is running"}


@router.get("/health")
def health():
    return {"status": "healthy"}


@router.get("/banque/synchro/cron")
async def banque_synchro_cron(request: Request):
    """Appelé chaque heure par le cron Supabase ; ne synchronise qu'à 8, 12, 17 et 21 h (Paris), puis envoie
    les notifications (docs/regles-de-calcul.md § 10). Consultation en l'absence du propriétaire."""
    secret = os.environ.get("CRON_SECRET")
    recu = request.headers.get("authorization", "")
    if not secret or not secrets.compare_digest(recu, f"Bearer {secret}"):
        raise HTTPException(401, "Accès réservé au cron")
    if not notifications.heure_de_synchro():
        return {"synchro": False}
    comptes = await synchro.synchroniser()
    pages = None
    if veille.jour_de_veille():   # le 1er du mois à 8 h : pages de prix relues avant les notifications
        try:
            pages = await veille.lire_pages()
        except (db.DatabaseError, httpx.HTTPError) as e:
            pages = {"erreur": type(e).__name__}
    try:
        bons = await bons_plans.collecter()
    except (db.DatabaseError, httpx.HTTPError) as e:
        bons = {"erreur": type(e).__name__}
    try:
        envoi = await notifications.apres_synchro()
    except (db.DatabaseError, notifications.FcmError, httpx.HTTPError, ValueError) as e:
        envoi = {"erreur": type(e).__name__}
    # Réponse réduite aux compteurs : aucune donnée financière dans les logs du cron.
    return {"synchro": True, "notifications": envoi, "pages": pages, "bons_plans": bons,
            "comptes": [{"compte": c["compte"], "ok": "erreur" not in c, "nouvelles": c.get("nouvelles", 0)}
                        for c in comptes]}


@router.get("/banque/retour", response_class=HTMLResponse)
async def banque_retour(code: str | None = None, state: str | None = None,
                        error: str | None = None, error_description: str | None = None):
    """Page où la banque renvoie le propriétaire après l'autorisation (publique : protégée par le state)."""
    if error:
        detail = html_escape(error_description or error)
        return HTMLResponse(bq.page_retour("Autorisation annulée", f"La banque a répondu : {detail}.", False), 400)
    if not code or not state:
        return HTMLResponse(bq.page_retour("Lien incomplet", "Relance la connexion depuis l'app.", False), 400)
    try:
        banque, comptes = await bq.terminer_connexion(code, state)
    except bq.ConnexionError as e:
        return HTMLResponse(bq.page_retour("Connexion impossible", html_escape(str(e)), False), 400)
    except (eb.EnableBankingError, db.DatabaseError) as e:
        # Page publique : le détail technique va seulement dans les journaux Vercel (privés).
        print(f"/banque/retour : {type(e).__name__} : {e}", file=sys.stderr)
        return HTMLResponse(bq.page_retour(
            "Erreur pendant la connexion", "Erreur technique. Réessaie depuis l'app dans quelques minutes.", False), 502)
    liste = "".join(f"<li>{html_escape(c)}</li>" for c in comptes) or "<li>aucun compte renvoyé</li>"
    return HTMLResponse(bq.page_retour(
        f"{banque} est connecté",
        f"Comptes reliés :</p><ul>{liste}</ul><p>Tu peux fermer cette page et revenir dans Opti.",
        True,
    ))


# ── Pages légales, exigées par Enable Banking pour une application en production ──

def _page(titre: str, corps: str) -> HTMLResponse:
    return HTMLResponse(f"""<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Opti · {titre}</title>
<style>body{{font:16px/1.6 Georgia,serif;max-width:680px;margin:40px auto;padding:0 16px;color:#13221A;background:#F1F6F0}}
h1{{font-size:28px}}h2{{font-size:19px;margin-top:28px}}</style></head>
<body><h1>Opti · {titre}</h1>{corps}<p><small>Dernière mise à jour : 28 octobre 2026.</small></p></body></html>""")


@router.get("/confidentialite", response_class=HTMLResponse)
def confidentialite():
    return _page("Politique de confidentialité", """
<p>Opti est une application <strong>strictement personnelle</strong> de suivi de budget. Elle n'est ni commercialisée ni proposée au public : son seul utilisateur est la personne qui l'a développée.</p>
<h2>Données traitées</h2>
<p>Soldes et transactions des comptes bancaires que l'utilisateur a lui-même autorisés via Enable Banking, ainsi que les réglages de l'application (limites de dépenses, objectifs d'épargne, abonnements).</p>
<h2>Finalité</h2>
<p>Afficher à l'utilisateur ses dépenses, ses abonnements et des conseils d'épargne. Aucune autre utilisation.</p>
<h2>Stockage et sécurité</h2>
<p>Les données sont stockées dans une base hébergée dans l'Union européenne (Irlande), accessible uniquement au compte de l'utilisateur. Les clés d'accès restent côté serveur et ne sont jamais intégrées à l'application mobile.</p>
<h2>Partage</h2>
<p>Aucune donnée n'est vendue, partagée ni transmise à des tiers, en dehors des prestataires techniques nécessaires au fonctionnement (Enable Banking pour l'accès bancaire, l'hébergeur de la base et du serveur).</p>
<h2>Durée et retrait</h2>
<p>L'accès bancaire expire au plus tard après 180 jours et peut être révoqué à tout moment auprès de la banque ou d'Enable Banking. L'utilisateur peut supprimer ses données à tout moment.</p>
""")


@router.get("/conditions", response_class=HTMLResponse)
def conditions():
    return _page("Conditions d'utilisation", """
<p>Opti est un outil personnel, utilisé par son seul développeur pour gérer son propre budget. Il n'est pas ouvert à d'autres utilisateurs et ne constitue pas un service financier.</p>
<h2>Nature des informations</h2>
<p>Les chiffres et conseils affichés sont calculés automatiquement à partir des données bancaires de l'utilisateur, à titre indicatif. Ils ne constituent ni un conseil en investissement, ni un conseil fiscal.</p>
<h2>Accès bancaire</h2>
<p>L'accès aux comptes passe par Enable Banking, avec l'autorisation explicite de l'utilisateur auprès de sa banque, en lecture seule. Opti n'initie aucun paiement.</p>
""")
