"""Notifications — voir docs/regles-de-calcul.md § 10 (validé le 01/11/2026).

`a_envoyer(...)` est pur (testable) : il décide quoi envoyer à une synchro automatique.
`apres_synchro()` charge les données, envoie via Firebase Cloud Messaging et garde la trace de chaque envoi.
Textes neutres (choix de Mohamed) : jamais de montant ni de marchand, ils s'affichent sur l'écran verrouillé.
"""
import asyncio
import json
import os
import time
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

import httpx
import jwt

import abonnements as abos
import budget
import db
import stats
import synchro

TYPES = ("renouvellement", "panne", "limite", "paie", "essai", "abonnement", "catalogue", "promos")
HEURES_SYNCHRO = (8, 12, 17, 21)     # heure de Paris ; 4 par jour = maximum DSP2 sans Mohamed
HEURE_RENOUVELLEMENT = 12
PALIERS_RENOUVELLEMENT = (14, 7, 1)
PANNE_APRES = timedelta(hours=24)
PAIE_RECENTE_JOURS = 3
PALIERS_ESSAI = (3, 1)


@dataclass
class Notification:
    cle: str        # une seule fois par clé (table notifications_envoyees)
    type: str
    titre: str
    texte: str
    ecran: str      # ce que l'app ouvre : « accueil », « reglages », « abonnements » ou « catalogue »


def _quand(instant: datetime, maintenant: datetime) -> str:
    jours = (maintenant.astimezone(budget.PARIS).date() - instant.astimezone(budget.PARIS).date()).days
    return "hier" if jours <= 1 else f"le {instant.astimezone(budget.PARIS):%d/%m}"


def _instant(valeur: str | None) -> datetime | None:
    return datetime.fromisoformat(str(valeur).replace("Z", "+00:00")) if valeur else None


def a_envoyer(maintenant: datetime, connexions: list[dict[str, Any]], depense: float | None, limite: float | None,
              salaires: list[dict[str, Any]], deja: set[str], actives: set[str], *,
              bilan: tuple[int, int] | None = None, abonnements: list[Any] = (),
              detectes: list[str] = (), pages: list[dict[str, Any]] = (),
              evenements: list[dict[str, Any]] = ()) -> list[Notification]:
    """`connexions` : la plus récente de chaque banque ; `depense`/`limite` : du jour ; `salaires` : opérations
    « Salaire » récentes ; `deja` : clés déjà envoyées ; `actives` : types laissés allumés dans les Réglages ;
    `bilan` : jours sous la limite et jours du cycle qui vient de finir ; `abonnements` : états (abonnements.etat) ;
    `detectes` : clés des nouveaux abonnements détectés (§ 11) ; `pages` : pages de prix modifiées et
    `evenements` : calendrier des grandes promos (§ 12)."""
    paris = maintenant.astimezone(budget.PARIS)
    aujourdhui = paris.date()
    resultat: list[Notification] = []

    for c in connexions:
        banque = c["aspsp_name"]
        jours = synchro.jours_restants(c.get("valid_until"), maintenant)
        fin = str(c.get("valid_until") or "")[:10]
        if c.get("status") != "active" or (jours is not None and jours < 0):
            resultat.append(Notification(f"expire:{banque}:{fin}", "panne", "Accès bancaire expiré",
                                         f"Accès {banque} expiré. Renouvelle-le dans Opti › Réglages.", "reglages"))
            continue
        if paris.hour == HEURE_RENOUVELLEMENT and jours in PALIERS_RENOUVELLEMENT:
            dans = "demain" if jours == 1 else f"dans {jours} jours"
            resultat.append(Notification(f"renouvellement:{banque}:{fin}:{jours}", "renouvellement",
                                         "Accès bancaire à renouveler",
                                         f"Accès {banque} : expire {dans}. Renouvelle-le dans Opti › Réglages.",
                                         "reglages"))
        reussie = _instant(c.get("last_success_at"))
        if reussie is not None and maintenant - reussie > PANNE_APRES:
            resultat.append(Notification(f"panne:{banque}:{c['last_success_at']}", "panne", "Synchro en panne",
                                         f"{banque} ne se synchronise plus depuis {_quand(reussie, maintenant)}. "
                                         "Ouvre Opti pour vérifier.", "reglages"))

    if depense is not None and limite is not None and depense > limite + 0.005:
        pourcent = f" ({round(depense / limite * 100)} %)" if limite > 0 else ""
        resultat.append(Notification(f"limite:{aujourdhui.isoformat()}", "limite", "Limite du jour",
                                     f"Limite du jour dépassée{pourcent}. Ouvre Opti pour voir le détail.", "accueil"))

    for s in salaires:
        if float(s["amount"]) > 0 and (aujourdhui - budget._jour(s)).days < PAIE_RECENTE_JOURS:
            if bilan and bilan[1] > 0:
                sous, jours = bilan
                texte = (f"Ta paie est arrivée. Cycle précédent : {sous} jours sur {jours} sous ta limite "
                         f"({round(sous / jours * 100)} %). Ouvre Opti pour ton bilan.")
            else:
                texte = "Ta paie est arrivée. Ouvre Opti pour voir ton budget du cycle."
            resultat.append(Notification(f"paie:{s['id']}", "paie", "Paie reçue", texte, "accueil"))

    for e in abonnements:
        if e.statut == "essai" and e.essai_jusqu_au and paris.hour == HEURE_RENOUVELLEMENT:
            jours = (e.essai_jusqu_au - aujourdhui).days
            if jours in PALIERS_ESSAI:
                dans = "demain" if jours == 1 else f"dans {jours} jours"
                resultat.append(Notification(f"essai:{e.id}:{e.essai_jusqu_au.isoformat()}:{jours}", "essai",
                                             "Essai gratuit", f"Ton essai {e.nom} se termine {dans}. "
                                             "Ouvre Opti pour le garder ou le résilier.", "abonnements"))
        if e.depassement:
            resultat.append(Notification(f"depassement:{e.depassement['id']}", "abonnement", "Abonnement",
                                         f"{e.nom} a prélevé plus que ton maximum. Ouvre Opti pour vérifier.",
                                         "abonnements"))
        if e.changement_prix:
            ancien, nouveau = e.changement_prix["ancien"], e.changement_prix["nouveau"]
            ecart = round((nouveau - ancien) / ancien * 100)
            resultat.append(Notification(f"prix:{e.id}:{nouveau:.2f}", "abonnement", "Abonnement",
                                         f"Un abonnement a changé de prix ({ecart:+d} %). Ouvre Opti pour vérifier.",
                                         "abonnements"))
    for cle in detectes:
        resultat.append(Notification(f"detecte:{cle}", "abonnement", "Abonnement",
                                     "Un nouvel abonnement a été détecté. Ouvre Opti pour confirmer.", "abonnements"))

    for p in pages:
        resultat.append(Notification(f"page:{p['id']}:{p['page_modifiee_le']}", "catalogue", "Catalogue de prix",
                                     "Une page de prix a changé. Ouvre Opti pour vérifier.", "catalogue"))
    if paris.hour == HEURE_RENOUVELLEMENT:
        for e in evenements:
            debut = budget._jour({"date": e["debut"]})
            if (debut - aujourdhui).days == 1:
                nom = e["nom"]
                annonce = (f"Les {nom.lower()} commencent demain." if nom.lower().startswith("soldes")
                           else f"Le {nom} commence demain.")
                resultat.append(Notification(f"promo:{nom}:{debut.isoformat()}", "promos", "Grandes promos",
                                             f"{annonce} Ouvre Opti pour voir ta marge ce mois-ci.", "accueil"))

    return [n for n in resultat if n.cle not in deja and n.type in actives]


# ── Réglages (table settings : notif_<type> = "false" pour couper) ───────────

async def reglages() -> dict[str, bool]:
    lignes = await db.select("settings", key=f"in.({','.join('notif_' + t for t in TYPES)})")
    coupes = {r["key"][len("notif_"):] for r in lignes if str(r.get("value")).lower() == "false"}
    return {t: t not in coupes for t in TYPES}


async def modifier_reglages(valeurs: dict[str, bool]) -> dict[str, bool]:
    existantes = {r["key"] for r in await db.select("settings", select="key", key="like.notif_*")}
    for type_, oui in valeurs.items():
        cle, valeur = f"notif_{type_}", "true" if oui else "false"
        if cle in existantes:
            await db.update("settings", {"value": valeur}, key=f"eq.{cle}")
        else:
            await db.insert("settings", {"key": cle, "value": valeur})
    return await reglages()


async def enregistrer_appareil(jeton: str, nom: str | None) -> None:
    await db.upsert("push_tokens", {"token": jeton, "platform": "fcm", "device_name": nom, "enabled": True,
                                    "last_used_at": datetime.now(timezone.utc).isoformat()}, on_conflict="token")


# ── Firebase Cloud Messaging (API HTTP v1) ────────────────────────────────────

class FcmError(Exception):
    pass


_acces: tuple[str, float] | None = None   # jeton OAuth Google et son expiration


def _compte_service() -> dict[str, Any]:
    brut = os.environ.get("FCM_SERVICE_ACCOUNT")
    if not brut:
        raise FcmError("FCM_SERVICE_ACCOUNT manquant")
    return json.loads(brut)


async def _jeton_acces(client: httpx.AsyncClient, compte: dict[str, Any]) -> str:
    global _acces
    if _acces and _acces[1] > time.time() + 60:
        return _acces[0]
    maintenant = int(time.time())
    assertion = jwt.encode({"iss": compte["client_email"], "scope": "https://www.googleapis.com/auth/firebase.messaging",
                            "aud": compte["token_uri"], "iat": maintenant, "exp": maintenant + 3600},
                           compte["private_key"], algorithm="RS256")
    r = await client.post(compte["token_uri"], data={"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                                                      "assertion": assertion})
    if r.status_code >= 400:
        raise FcmError(f"Jeton Google refusé ({r.status_code})")
    _acces = (r.json()["access_token"], maintenant + int(r.json().get("expires_in", 3600)))
    return _acces[0]


async def envoyer(jetons: list[str], n: Notification) -> dict[str, int]:
    """Envoie à chaque téléphone ; les jetons que Firebase ne connaît plus sont retirés."""
    compte = _compte_service()
    bilan = {"ok": 0, "erreurs": 0}
    async with httpx.AsyncClient(timeout=15.0) as client:
        acces = await _jeton_acces(client, compte)
        for jeton in jetons:
            r = await client.post(
                f"https://fcm.googleapis.com/v1/projects/{compte['project_id']}/messages:send",
                headers={"Authorization": f"Bearer {acces}"},
                json={"message": {"token": jeton, "notification": {"title": n.titre, "body": n.texte},
                                  "data": {"ecran": n.ecran, "type": n.type},
                                  "android": {"priority": "high"}}})
            if r.status_code < 400:
                bilan["ok"] += 1
            else:
                bilan["erreurs"] += 1
                if r.status_code == 404 or "UNREGISTERED" in r.text:
                    await db.delete("push_tokens", token=f"eq.{jeton}")
    return bilan


async def _jetons() -> list[str]:
    return [r["token"] for r in await db.select("push_tokens", select="token", enabled="eq.true", platform="eq.fcm")]


DELAI_TEST = 10   # secondes : le temps de quitter Opti (Android n'affiche pas la bannière de l'app ouverte)


async def tester(delai: float = 0) -> dict[str, int]:
    await asyncio.sleep(delai)
    return await envoyer(await _jetons(), Notification("test", "test", "Opti",
                                                       "Les notifications marchent. Ouvre Opti quand tu veux.", "accueil"))


# ── Après une synchro automatique ─────────────────────────────────────────────

async def _connexions() -> list[dict[str, Any]]:
    plus_recentes, vues = [], set()
    for c in await db.select("bank_connections", order="created_at.desc"):
        if c["aspsp_name"] not in vues:
            vues.add(c["aspsp_name"])
            plus_recentes.append(c)
    return plus_recentes


async def calculer(maintenant: datetime | None = None) -> list[Notification]:
    maintenant = maintenant or datetime.now(timezone.utc)
    aujourdhui = maintenant.astimezone(budget.PARIS).date()
    connexions = await _connexions()
    salaires = await db.select("transactions", select="id,date,amount", category="eq.Salaire",
                               date=f"gte.{(aujourdhui - timedelta(days=PAIE_RECENTE_JOURS)).isoformat()}")
    # Petite table (quelques envois par mois) ; pas de colonne id, donc pas de select_tout.
    deja = {r["cle"] for r in await db.select("notifications_envoyees", select="cle")}
    actives = {t for t, oui in (await reglages()).items() if oui}
    try:
        b = await budget.budget_du_jour(aujourdhui)
        depense, limite = b.depense_aujourdhui, b.limite_du_jour
    except ValueError:
        depense = limite = None   # pas encore de paie connue : pas de limite à comparer
    # Bilan du cycle qui vient de finir : calculé seulement quand une paie reste à annoncer.
    bilan = None
    if any(f"paie:{s['id']}" not in deja for s in salaires if float(s["amount"]) > 0):
        precedent = await stats.ecran("precedent", aujourdhui)
        if precedent.cycles:
            bilan = (precedent.cycles[0].jours_sous_limite, precedent.cycles[0].jours)
    souscriptions, operations, refusees = await abos._donnees(aujourdhui)
    etats = [abos.etat(s, operations, aujourdhui) for s in souscriptions]
    detectes = [c["cle"] for c in abos.detecter(operations, souscriptions, refusees, aujourdhui)]
    pages, evenements = await asyncio.gather(
        db.select("catalog_services", select="id,page_modifiee_le", page_etat="eq.modifiee"),
        db.select("catalog_events", select="nom,debut", debut=f"gte.{aujourdhui.isoformat()}"),
    )
    return a_envoyer(maintenant, connexions, depense, limite, salaires, deja, actives,
                     bilan=bilan, abonnements=etats, detectes=detectes, pages=pages, evenements=evenements)


async def apres_synchro() -> dict[str, Any]:
    """Réponse réduite aux compteurs : rien de financier dans les logs du cron."""
    a_faire = await calculer()
    jetons = await _jetons()
    envoyees = 0
    if jetons:
        for n in a_faire:
            if (await envoyer(jetons, n))["ok"]:
                await db.insert("notifications_envoyees", {"cle": n.cle, "type": n.type})
                envoyees += 1
    return {"a_envoyer": len(a_faire), "envoyees": envoyees, "telephones": len(jetons)}


def heure_de_synchro(maintenant: datetime | None = None) -> bool:
    return (maintenant or datetime.now(timezone.utc)).astimezone(budget.PARIS).hour in HEURES_SYNCHRO
