"""Abonnements — voir docs/regles-de-calcul.md § 7 (règles validées par Mohamed le 31/10/2026).

Fonctions pures (testées sur les cas réels : Imagine R, Prixtel, Prime, Anthropic, Orange, Microsoft),
puis le chargement depuis la base.
"""
import asyncio
import calendar
import re
import statistics
from dataclasses import asdict, dataclass
from datetime import date, timedelta
from typing import Any

import db
import erreurs

INTERVALLES = {"hebdomadaire": 7, "mensuel": 30, "mois": 30, "trimestriel": 91, "annuel": 365}
PAR_MOIS = {7: 52 / 12, 30: 1.0, 91: 1 / 3, 365: 1 / 12}       # pour ramener un prix au mois
SEUIL_CHANGEMENT_PRIX = 0.10
VERDICTS = {"toujours": "rentable", "souvent": "rentable", "parfois": "a_revoir", "jamais": "a_couper"}

# Détection
CATEGORIES_EXCLUES = {"Alimentation", "Restauration", "Shopping", "Distributeur"}
MOTS_VIDES = {"la", "le", "les", "de", "du", "des", "sc", "sa", "sas", "sarl", "paiement", "prlv", "sepa",
              "abonnement", "carte", "cb", "vir", "virement"}
ECART_MENSUEL, ECART_ANNUEL = (25, 35), (355, 375)
TOLERANCE_MONTANT = 0.40
DETECTION_RECENTE_JOURS = 45


def _jour(valeur: Any) -> date:
    return date.fromisoformat(str(valeur)[:10])


def _texte(t: dict[str, Any]) -> str:
    return f"{t.get('merchant') or ''} {t.get('description') or ''}".lower()


def intervalle(abonnement: dict[str, Any]) -> int:
    return INTERVALLES.get((abonnement.get("frequency") or "mensuel").lower(), 30)


def cles(abonnement: dict[str, Any]) -> list[str]:
    """Libellé principal et autres libellés du même abonnement, en minuscules."""
    return [c.lower() for c in [abonnement.get("merchant_key"), *(abonnement.get("libelles") or [])] if c]


def prelevements(abonnement: dict[str, Any], operations: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Les prélèvements de cet abonnement, du plus ancien au plus récent."""
    mots = cles(abonnement)
    trouves = [t for t in operations if float(t["amount"]) < 0 and not t.get("is_internal")
               and mots and any(m in _texte(t) for m in mots)]
    return sorted(trouves, key=lambda t: str(t["date"]))


def montant_automatique(prels: list[dict[str, Any]]) -> float | None:
    """Prix fixe : le dernier si les 2 derniers sont identiques ; prix variable : moyenne des 3 derniers."""
    montants = [-float(t["amount"]) for t in prels]
    if not montants:
        return None
    if len(montants) >= 2 and abs(montants[-1] - montants[-2]) < 0.005:
        return round(montants[-1], 2)
    return round(statistics.mean(montants[-3:]), 2)


def _ajouter_mois(d: date, jour: int) -> date:
    annee, mois = (d.year + 1, 1) if d.month == 12 else (d.year, d.month + 1)
    return date(annee, mois, min(jour, calendar.monthrange(annee, mois)[1]))


def prochain_prelevement(dernier: date, jours: int, mois_pause: list[int] | None = None) -> date:
    """Date attendue du prélèvement suivant ; les mois de pause sont sautés (Imagine R : juillet → septembre)."""
    pause = set(mois_pause or [])
    prochain = _ajouter_mois(dernier, dernier.day) if jours == 30 else dernier + timedelta(days=jours)
    for _ in range(12):
        if prochain.month not in pause:
            break
        prochain = _ajouter_mois(prochain, dernier.day) if jours == 30 else prochain + timedelta(days=jours)
    return prochain


@dataclass
class EtatAbonnement:
    id: str
    nom: str
    categorie: str | None
    frequence: str
    montant: float                    # montant retenu (manuel, sinon automatique, sinon enregistré)
    montant_min: float | None         # fourchette des 3 derniers prélèvements (prix variable)
    montant_max: float | None
    variable: bool
    par_mois: float
    statut: str                       # « actif », « a_verifier », « resilie », « essai » ou « essai_termine »
    usage: str | None
    verdict: str                      # « rentable », « a_revoir », « a_couper » ou « a_renseigner »
    economie_par_an: float | None     # quand le verdict est « à couper »
    dernier_prelevement: date | None
    prochain_prelevement: date | None
    mois_pause: list[int]
    changement_prix: dict[str, Any] | None   # {"ancien", "nouveau", "depuis"}
    libelles: list[str]
    montant_manuel: bool
    historique: list[dict[str, Any]]  # derniers prélèvements (date, montant, libellé)
    essai_jusqu_au: date | None = None  # essai gratuit pas encore prélevé (§ 11)
    prix_maximum: float | None = None   # ce que le contrat peut coûter au plus (§ 7, point 8), saisi à la main
    depassement: dict[str, Any] | None = None  # dernier prélèvement au-dessus du maximum, pas encore vu

    @property
    def montant_budget(self) -> float:
        """Ce que la limite du jour réserve : le maximum quand il existe (option A, choix de Mohamed)."""
        return self.prix_maximum or self.montant


def etat(abonnement: dict[str, Any], operations: list[dict[str, Any]], aujourdhui: date) -> EtatAbonnement:
    prels = prelevements(abonnement, operations)
    jours = intervalle(abonnement)
    essai = _fin_essai(abonnement, prels)
    if essai:
        prels = []   # d'éventuels anciens prélèvements du marchand ne disent rien de cet essai
    auto = montant_automatique(prels)
    manuel = bool(abonnement.get("montant_manuel"))
    montant = float(abonnement["amount"]) if manuel or auto is None else auto
    recents = [-float(t["amount"]) for t in prels[-3:]]
    # Variable seulement si le montant retenu est une moyenne (les 2 derniers prélèvements diffèrent) :
    # Prime à 0,99 € une fois en août puis 6,99 € reste un prix fixe.
    variable = not manuel and len(recents) >= 2 and abs(recents[-1] - recents[-2]) >= 0.005

    dernier = None if essai else _jour(prels[-1]["date"]) if prels else (
        _jour(abonnement["last_seen_at"]) if abonnement.get("last_seen_at") else None)
    pause = list(abonnement.get("mois_pause") or [])
    resilie = abonnement.get("status") == "cancelled"
    prochain = prochain_prelevement(dernier, jours, pause) if dernier and not resilie else None
    if resilie:
        statut = "resilie"
    elif essai:
        statut, prochain = ("essai" if aujourdhui <= essai else "essai_termine"), essai
    elif prochain and (aujourdhui - prochain).days > jours / 2:      # 1,5 intervalle sans prélèvement
        statut = "a_verifier"
    else:
        statut = "actif"
    while prochain and prochain < aujourdhui and statut == "actif":  # en retard de quelques jours : on vise la prochaine date
        prochain = prochain_prelevement(prochain, jours, pause)

    usage = abonnement.get("usage")
    verdict = VERDICTS.get(usage or "", "a_renseigner")
    par_mois = round(montant * PAR_MOIS.get(jours, 30.4 / jours), 2)

    reference = abonnement.get("montant_reference")
    changement = None
    if (not resilie and reference not in (None, 0) and prels
            and abs(montant - float(reference)) / float(reference) > SEUIL_CHANGEMENT_PRIX):
        changement = {"ancien": float(reference), "nouveau": montant, "depuis": _jour(prels[-1]["date"])}

    maximum = float(abonnement["montant_max"]) if abonnement.get("montant_max") else None
    depassement = None
    if maximum and prels and not resilie and -float(prels[-1]["amount"]) > maximum + 0.005             and prels[-1].get("id") != abonnement.get("depassement_vu"):
        depassement = {"id": prels[-1].get("id"), "date": _jour(prels[-1]["date"]), "montant": -float(prels[-1]["amount"])}

    return EtatAbonnement(
        id=abonnement["id"], nom=abonnement["name"], categorie=abonnement.get("category"),
        frequence=abonnement.get("frequency") or "mensuel", montant=round(montant, 2),
        montant_min=min(recents) if variable else None, montant_max=max(recents) if variable else None,
        variable=variable, par_mois=par_mois, statut=statut, usage=usage, verdict=verdict,
        economie_par_an=round(par_mois * 12, 2) if verdict == "a_couper" and not resilie else None,
        dernier_prelevement=dernier, prochain_prelevement=prochain, mois_pause=pause,
        changement_prix=changement, libelles=list(abonnement.get("libelles") or []), montant_manuel=manuel,
        historique=[{"id": t.get("id"), "date": _jour(t["date"]), "montant": -float(t["amount"]),
                     "libelle": t.get("merchant") or t.get("description") or ""} for t in reversed(prels[-24:])],
        essai_jusqu_au=essai if not resilie else None,
        prix_maximum=maximum, depassement=depassement,
    )


def fourchette(suivis: list[EtatAbonnement]) -> dict[str, float] | None:
    """Total par mois au plus bas et au plus haut (§ 7, point 9) ; None si aucun montant ne varie."""
    if not any(e.variable or e.prix_maximum for e in suivis):
        return None
    bas = haut = 0.0
    for e in suivis:
        facteur = e.par_mois / e.montant if e.montant else 0.0
        bas += (e.montant_min if e.variable else e.montant) * facteur
        haut += (e.prix_maximum or (e.montant_max if e.variable else e.montant)) * facteur
    return {"min": round(bas, 2), "max": round(haut, 2)}


ESSAI_TOLERANCE_JOURS = 3   # un prélèvement 3 jours avant la fin de l'essai le transforme déjà en abonnement


def _fin_essai(abonnement: dict[str, Any], prels: list[dict[str, Any]]) -> date | None:
    """Date de fin d'un essai gratuit encore en cours (ou terminé sans prélèvement) ; None sinon."""
    if not abonnement.get("is_trial") or not abonnement.get("trial_end_date"):
        return None
    fin = _jour(abonnement["trial_end_date"])
    if any(_jour(t["date"]) >= fin - timedelta(days=ESSAI_TOLERANCE_JOURS) for t in prels):
        return None   # prélevé : c'est devenu un abonnement
    return fin


# ── Détection des nouveaux abonnements ───────────────────────────────────────

def cle_detection(t: dict[str, Any]) -> str | None:
    """Premier mot significatif du marchand : « Anthropic* Claude Sub » et « Anthropic » → « anthropic »."""
    texte = re.sub(r"\(.*?\)", " ", (t.get("merchant") or t.get("description") or "").lower())
    for mot in re.split(r"[^a-zà-ÿ0-9]+", texte):
        if len(mot) >= 3 and mot not in MOTS_VIDES and not mot.isdigit():
            return mot
    return None


def detecter(operations: list[dict[str, Any]], abonnements: list[dict[str, Any]], refusees: set[str],
             aujourdhui: date) -> list[dict[str, Any]]:
    """« Nouvel abonnement ? » : 3 derniers prélèvements d'un marchand espacés d'un mois (ou d'un an),
    montants à ± 40 %, le dernier depuis moins de 45 jours ; hors catégories du quotidien,
    marchands déjà suivis et marchands refusés."""
    deja_suivies = {t.get("id") for a in abonnements for t in prelevements(a, operations)}
    groupes: dict[str, list[dict[str, Any]]] = {}
    for t in operations:
        if (float(t["amount"]) >= 0 or t.get("is_internal") or t.get("status") == "pending"
                or t.get("category") in CATEGORIES_EXCLUES or t.get("id") in deja_suivies):
            continue
        cle = cle_detection(t)
        if cle and cle not in refusees:
            groupes.setdefault(cle, []).append(t)

    candidats = []
    for cle, ops in groupes.items():
        derniers = sorted(ops, key=lambda t: str(t["date"]))[-3:]
        if len(derniers) < 3:
            continue
        dates = [_jour(t["date"]) for t in derniers]
        ecarts = [(b - a).days for a, b in zip(dates, dates[1:])]
        frequence = next((nom for nom, (lo, hi) in (("mensuel", ECART_MENSUEL), ("annuel", ECART_ANNUEL))
                          if all(lo <= e <= hi for e in ecarts)), None)
        montants = [-float(t["amount"]) for t in derniers]
        moyenne = statistics.mean(montants)
        if (frequence is None or (aujourdhui - dates[-1]).days > DETECTION_RECENTE_JOURS
                or any(abs(m - moyenne) > TOLERANCE_MONTANT * moyenne for m in montants)):
            continue
        candidats.append({"cle": cle, "libelle": derniers[-1].get("merchant") or derniers[-1].get("description") or cle,
                          "montant": montant_automatique(derniers), "frequence": frequence,
                          "categorie": derniers[-1].get("category"), "dernier": dates[-1]})
    return sorted(candidats, key=lambda c: c["dernier"], reverse=True)


# ── Écran Abonnements et actions de l'app ────────────────────────────────────

HISTORIQUE_JOURS = 400          # assez pour voir un abonnement annuel
CLE_VALIDE = re.compile(r"^[a-zà-ÿ0-9]{3,40}$")
FREQUENCES = ("hebdomadaire", "mensuel", "trimestriel", "annuel")


class ActionRefusee(erreurs.ActionRefusee):
    """Action impossible (message affichable tel quel)."""


async def _donnees(aujourdhui: date) -> tuple[list[dict], list[dict], set[str]]:
    debut = (aujourdhui - timedelta(days=HISTORIQUE_JOURS)).isoformat()
    souscriptions, operations, reponses = await asyncio.gather(
        db.select("subscriptions", order="name.asc"),
        db.select_tout("transactions", select="id,date,amount,merchant,description,category,is_internal,status",
                       date=f"gte.{debut}", amount="lt.0", is_internal="eq.false"),
        db.select("subscription_candidates", select="merchant_norm,status"),
    )
    refusees = {r["merchant_norm"] for r in reponses if r.get("status") == "rejected" and r.get("merchant_norm")}
    return souscriptions, operations, refusees


async def ecran(aujourdhui: date) -> dict[str, Any]:
    souscriptions, operations, refusees = await _donnees(aujourdhui)
    etats = [etat(s, operations, aujourdhui) for s in souscriptions]
    ordre = {"essai_termine": 0, "a_verifier": 0, "essai": 1, "actif": 2, "resilie": 3}
    etats.sort(key=lambda e: (ordre[e.statut], -e.par_mois))
    suivis = [e for e in etats if e.statut in ("actif", "a_verifier")]   # un essai est gratuit : hors total
    return {
        "total_par_mois": round(sum(e.par_mois for e in suivis), 2),
        "fourchette": fourchette(suivis),
        "nombre_suivis": len(suivis),
        "rentables": sum(1 for e in suivis if e.verdict == "rentable"),
        "abonnements": [asdict(e) for e in etats],
        "detectes": detecter(operations, souscriptions, refusees, aujourdhui),
    }


async def _abonnement(abonnement_id: str) -> dict[str, Any]:
    trouves = await db.select("subscriptions", id=f"eq.{abonnement_id}")
    if not trouves:
        raise ActionRefusee("Abonnement introuvable.")
    return trouves[0]


async def creer(nom: str, montant: float, frequence: str, categorie: str | None, cle: str | None,
                essai_jusqu_au: date | None = None) -> dict[str, Any]:
    cle = (cle or nom).strip().lower()
    return (await db.insert("subscriptions", {
        "name": nom, "amount": montant, "montant_reference": montant, "frequency": frequence,
        "category": categorie or "Abonnement", "status": "active", "merchant_key": cle,
        "is_trial": essai_jusqu_au is not None,
        "trial_end_date": essai_jusqu_au.isoformat() if essai_jusqu_au else None,
    }))[0]


async def modifier(abonnement_id: str, valeurs: dict[str, Any]) -> dict[str, Any]:
    """Un montant saisi devient « corrigé à la main » ; montant_auto=True rend la main au calcul."""
    souscription = await _abonnement(abonnement_id)
    if valeurs.pop("montant_auto", None):
        valeurs["montant_manuel"] = False
    if "amount" in valeurs:
        valeurs |= {"montant_manuel": True, "montant_reference": valeurs["amount"]}
    if valeurs.pop("essai_garde", None):
        valeurs["is_trial"] = False   # « Tu l'as gardé ? Oui » : abonnement normal
    if valeurs.get("montant_max") is not None:
        _, operations, _ = await _donnees(date.today())
        actuel = valeurs.get("amount") or etat(souscription, operations, date.today()).montant
        if valeurs["montant_max"] < actuel - 0.005:
            raise ActionRefusee(f"Le maximum doit être au moins égal au prix actuel ({actuel:.2f} €).".replace(".", ","))
    if "libelles" in valeurs:
        valeurs["libelles"] = sorted({l.strip().lower() for l in valeurs["libelles"] if l.strip()})
    return (await db.update("subscriptions", valeurs, id=f"eq.{abonnement_id}"))[0]


async def supprimer(abonnement_id: str) -> None:
    await _abonnement(abonnement_id)
    await db.delete("subscriptions", id=f"eq.{abonnement_id}")


async def accepter_prix(abonnement_id: str, aujourdhui: date) -> None:
    """« OK » sur « le prix a changé » : le nouveau montant devient la référence."""
    souscription = await _abonnement(abonnement_id)
    _, operations, _ = await _donnees(aujourdhui)
    e = etat(souscription, operations, aujourdhui)
    await db.update("subscriptions", {"amount": e.montant, "montant_reference": e.montant}, id=f"eq.{abonnement_id}")


async def depassement_vu(abonnement_id: str, aujourdhui: date) -> None:
    """« Compris » sur la carte de dépassement : elle disparaît jusqu'au prochain dépassement."""
    souscription = await _abonnement(abonnement_id)
    _, operations, _ = await _donnees(aujourdhui)
    e = etat(souscription, operations, aujourdhui)
    if e.depassement:
        await db.update("subscriptions", {"depassement_vu": e.depassement["id"]}, id=f"eq.{abonnement_id}")


async def _candidat(cle: str, aujourdhui: date) -> dict[str, Any]:
    if not CLE_VALIDE.match(cle):
        raise ActionRefusee("Marchand inconnu.")
    souscriptions, operations, refusees = await _donnees(aujourdhui)
    candidat = next((c for c in detecter(operations, souscriptions, refusees, aujourdhui) if c["cle"] == cle), None)
    if candidat is None:
        raise ActionRefusee("Cette proposition n'est plus d'actualité : rouvre l'écran.")
    return candidat


async def ajouter_detecte(cle: str, nom: str | None, aujourdhui: date) -> dict[str, Any]:
    c = await _candidat(cle, aujourdhui)
    return await creer(nom or c["libelle"], c["montant"], c["frequence"],
                       c["categorie"] if c["categorie"] not in (None, "Autre") else "Abonnement", cle)


async def refuser_detecte(cle: str, aujourdhui: date) -> None:
    c = await _candidat(cle, aujourdhui)
    await db.insert("subscription_candidates", {"merchant": c["libelle"], "merchant_norm": cle, "amount": c["montant"],
                                                "status": "rejected", "rejected_reason": "pas_un_abonnement"})
