"""Connexion des banques via Enable Banking.

Parcours : l'app appelle /banque/connexion → le backend crée un « state » à usage unique
et demande à Enable Banking l'adresse de la banque → Mohamed s'authentifie chez sa banque
→ la banque le renvoie sur /banque/retour avec un code → le backend ouvre la session
Enable Banking et rattache les comptes autorisés à ceux déjà connus.
"""
import html
import os
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any

import db
import enable_banking as eb

BANQUES = {"cic": "CIC", "revolut": "Revolut"}
# Adresse de retour déclarée dans l'application Enable Banking ; par défaut, le domaine de production Vercel.
REDIRECT_URL = os.environ.get("EB_REDIRECT_URL") or f"https://{os.environ.get('VERCEL_PROJECT_PRODUCTION_URL', 'localhost')}/banque/retour"
_CONSENT_PAR_DEFAUT = 180 * 86400


class ConnexionError(Exception):
    """Erreur à montrer telle quelle à Mohamed sur la page de retour."""


def nom_banque(saisie: str) -> str:
    nom = BANQUES.get((saisie or "").strip().lower())
    if not nom:
        raise ConnexionError(f"Banque inconnue : {saisie!r} (attendu : CIC ou Revolut)")
    return nom


async def demarrer_connexion(saisie: str) -> str:
    """Renvoie l'adresse de la page d'autorisation de la banque."""
    banque = nom_banque(saisie)
    aspsp = next((a for a in await eb.list_aspsps("FR") if a.get("name") == banque), None)
    if aspsp is None:
        raise ConnexionError(f"{banque} n'est pas proposée par Enable Banking")

    # Une heure de marge sous le maximum accepté par la banque.
    duree = (aspsp.get("maximum_consent_validity") or _CONSENT_PAR_DEFAUT) - 3600
    valid_until = datetime.now(timezone.utc) + timedelta(seconds=duree)

    state = secrets.token_urlsafe(32)
    # Une heure pour s'authentifier : la validation Revolut peut prendre plusieurs minutes.
    await db.insert("bank_auth_requests", {
        "state": state, "aspsp_name": banque,
        "expires_at": (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat(),
    })
    reponse = await eb.request("POST", "/auth", json={
        "access": {"valid_until": valid_until.isoformat()},
        "aspsp": {"name": banque, "country": "FR"},
        "state": state,
        "redirect_url": REDIRECT_URL,
        "psu_type": "personal",
    })
    return reponse["url"]


_MOTS_EPARGNE = ("econom", "économ", "epargne", "épargne", "pocket", "saving", "vault", "coffre", "livret")


def type_de_compte(compte: dict[str, Any]) -> str:
    """Courant ou épargne. Revolut peut déclarer une réserve (« Économies ») comme compte
    courant : le nom l'emporte, pour ne jamais la confondre avec le compte principal."""
    if (compte.get("cash_account_type") or "").upper() == "SVGS":
        return "savings"
    nom = f"{compte.get('name') or ''} {compte.get('product') or ''}".lower()
    return "savings" if any(mot in nom for mot in _MOTS_EPARGNE) else "checking"


def iban_last4(compte: dict[str, Any]) -> str | None:
    iban = ((compte.get("account_id") or {}).get("iban") or "").replace(" ", "")
    return iban[-4:] if len(iban) >= 4 else None


def choisir_compte_existant(compte: dict[str, Any], existants: list[dict[str, Any]]) -> dict[str, Any] | None:
    """Rattache un compte Enable Banking à un compte déjà connu, sinon None (à créer).

    1) même compte Enable Banking déjà relié (renouvellement du consentement) ;
    2) mêmes 4 derniers chiffres d'IBAN ;
    3) même type (courant / épargne), pas encore relié, et sans IBAN connu qui contredirait.
    """
    for e in existants:
        if e.get("eb_account_uid") == compte.get("uid"):
            return e
    last4 = iban_last4(compte)
    if last4:
        for e in existants:
            if e.get("iban_last4") == last4:
                return e
    for e in existants:
        if (not e.get("eb_account_uid") and e.get("account_type") == type_de_compte(compte)
                and not (last4 and e.get("iban_last4") and e["iban_last4"] != last4)):
            return e
    return None


async def terminer_connexion(code: str, state: str) -> tuple[str, list[str]]:
    """Ouvre la session et rattache les comptes ; renvoie (banque, libellés des comptes)."""
    maintenant = datetime.now(timezone.utc).isoformat()
    # Consommation atomique du state : un seul usage, avant expiration.
    demandes = await db.update(
        "bank_auth_requests", {"used_at": maintenant},
        state=f"eq.{state}", used_at="is.null", expires_at=f"gt.{maintenant}",
    )
    if not demandes:
        raise ConnexionError("Lien d'autorisation invalide, déjà utilisé ou expiré. Relance la connexion depuis l'app.")
    banque = demandes[0]["aspsp_name"]

    session = await eb.request("POST", "/sessions", json={"code": code})
    valid_until = (session.get("access") or {}).get("valid_until")

    # Les anciennes connexions de cette banque sont remplacées par la nouvelle.
    await db.update("bank_connections", {"status": "expired"}, aspsp_name=f"eq.{banque}", status="eq.active")
    connexion = (await db.insert("bank_connections", {
        "aspsp_name": banque, "session_id": session["session_id"], "valid_until": valid_until,
    }))[0]

    existants = await db.select("bank_accounts", bank=f"eq.{banque}")
    libelles = []
    for compte in session.get("accounts") or []:
        champs = {
            "connection_id": connexion["id"],
            "eb_account_uid": compte["uid"],
            "identification_hash": compte.get("identification_hash"),
        }
        existant = choisir_compte_existant(compte, existants)
        if existant:
            if not existant.get("iban_last4") and iban_last4(compte):
                champs["iban_last4"] = iban_last4(compte)
            await db.update("bank_accounts", champs, id=f"eq.{existant['id']}")
            existant.update(champs)
            libelles.append(existant.get("account_label") or banque)
        else:
            libelle = compte.get("name") or compte.get("product") or f"{banque} {type_de_compte(compte)}"
            nouveau = (await db.insert("bank_accounts", {
                **champs, "bank": banque, "account_label": libelle, "account_type": type_de_compte(compte),
                "iban_last4": iban_last4(compte), "currency": compte.get("currency") or "EUR", "active": True,
            }))[0]
            existants.append(nouveau)
            libelles.append(f"{libelle} (nouveau)")
    return banque, libelles


def page_retour(titre: str, message: str, ok: bool) -> str:
    couleur = "#1D7A48" if ok else "#C62828"
    return f"""<!doctype html><html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Opti · {html.escape(titre)}</title>
<style>body{{font:17px/1.6 Georgia,serif;max-width:560px;margin:60px auto;padding:0 16px;color:#13221A;background:#F1F6F0}}
h1{{color:{couleur};font-size:26px}}
a.retour{{display:inline-block;margin-top:18px;padding:12px 22px;border-radius:24px;background:#13221A;color:#fff;
text-decoration:none;font-family:system-ui,sans-serif}}</style></head>
<body><h1>{html.escape(titre)}</h1><p>{message}</p>
<a class="retour" href="opti://retour">Revenir à Opti</a></body></html>"""
