"""Catalogue de prix — voir docs/regles-de-calcul.md § 12 (validé le 01/11/2026).

Le catalogue (services, offres datées et sourcées) est le même que Mohamed soit abonné ou non ; la comparaison
avec ses abonnements se fait ici, rien ne sort. Épargne simple uniquement : payer moins, jamais acheter plus.
Les fonctions de calcul sont pures (testables) ; `ecran()` charge les données puis les appelle.
"""
import asyncio
import re
import unicodedata
from datetime import date
from typing import Any

import abonnements as abos
import db
import erreurs

PAR_MOIS = {"mensuel": 1.0, "annuel": 1 / 12, "hebdomadaire": 52 / 12, "quatre_semaines": 13 / 12}
ECONOMIE_MIN_EUROS = 1.0          # signalée à partir de 1 €/mois…
ECONOMIE_MIN_PART = 0.10          # … ou de 10 % du prix actuel
MOTS_GENERIQUES = {"one", "pro", "plus", "the", "and", "par", "forfait", "mobile", "abonnement"}
PROFIL = {"etudiant": "profil_etudiant", "moins_26": "profil_moins_26", "age_18_24": "profil_age_18_24"}


class ActionRefusee(erreurs.ActionRefusee):
    """Action impossible (message affichable tel quel)."""


def _jour(valeur: Any) -> date:
    return valeur if isinstance(valeur, date) else date.fromisoformat(str(valeur)[:10])


def par_mois(offre: dict[str, Any]) -> float:
    """Prix ramené au mois : Basic-Fit 24,99 € toutes les 4 semaines → 27,07 €."""
    return round(float(offre["prix"]) * PAR_MOIS[offre.get("frequence") or "mensuel"], 2)


def a_reverifier(offre: dict[str, Any], aujourdhui: date) -> bool:
    """Vérifiée il y a plus de 12 mois : le 01/11/2025 → à revérifier à partir du 02/11/2026."""
    verifie = _jour(offre["verifie_le"])
    try:
        limite = verifie.replace(year=verifie.year + 1)
    except ValueError:                       # 29 février
        limite = verifie.replace(year=verifie.year + 1, day=28)
    return aujourdhui > limite


def accessible(offre: dict[str, Any], profil: dict[str, bool]) -> bool:
    """Une offre sous conditions seulement si l'une d'elles est cochée dans le profil : Prime « étudiants et
    18-24 ans » = étudiant OU 18-24 ans."""
    conditions = offre.get("conditions") or []
    return not conditions or any(profil.get(c, False) for c in conditions)


def _mots(texte: str) -> set[str]:
    sans_accents = unicodedata.normalize("NFKD", texte).encode("ascii", "ignore").decode().lower()
    return {m for m in re.findall(r"[a-z0-9]+", sans_accents) if len(m) >= 3 and m not in MOTS_GENERIQUES}


def service_propose(nom_abonnement: str, services: list[dict[str, Any]]) -> dict[str, Any] | None:
    """« Forfait mobile Prixtel » → Prixtel ; « Anthropic (Claude) » → Claude. Mohamed confirme ensuite."""
    mots = _mots(nom_abonnement)
    return next((s for s in services if _mots(s["nom"]) & mots), None)


def _signalee(economie: float, prix_actuel: float) -> bool:
    return economie > 0 and (economie >= ECONOMIE_MIN_EUROS - 1e-9 or economie >= prix_actuel * ECONOMIE_MIN_PART)


def _resume(offre: dict[str, Any], service: dict[str, Any]) -> dict[str, Any]:
    return {
        "offre_id": offre["id"], "service": service["nom"], "nom": offre["nom"], "prix": float(offre["prix"]),
        "frequence": offre.get("frequence") or "mensuel", "par_mois": par_mois(offre), "go": offre.get("go"),
        "conditions": offre.get("conditions"), "engagement": offre.get("engagement"), "essai": offre.get("essai"),
        "prix_promo": offre.get("prix_promo"), "promo_duree": offre.get("promo_duree"),
        "source_url": offre.get("source_url"), "verifie_le": _jour(offre["verifie_le"]),
    }


def alternatives(prix_actuel: float, go: int | None, actuelle: dict[str, Any], offres: list[dict[str, Any]],
                 services: dict[str, dict[str, Any]], profil: dict[str, bool], aujourdhui: date) -> list[dict[str, Any]]:
    """Offres moins chères pour une ligne, de la plus grosse économie à la plus petite.

    Même service, ou (forfaits mobiles seulement) un autre opérateur avec au moins autant de Go ; ni offre
    groupée, ni offre à revérifier, ni condition non remplie. Comparées à leur prix d'après la promo (`prix`).
    """
    famille = services[actuelle["service_id"]]["famille"]
    resultat = []
    for o in offres:
        if o["id"] == actuelle["id"] or o.get("inclut") or a_reverifier(o, aujourdhui) or not accessible(o, profil):
            continue
        meme_service = o["service_id"] == actuelle["service_id"]
        if not meme_service and (famille != "mobile" or services[o["service_id"]]["famille"] != "mobile"):
            continue
        if famille == "mobile" and (go is None or o.get("go") is None or o["go"] < go):
            continue
        economie = round(prix_actuel - par_mois(o), 2)
        if _signalee(economie, prix_actuel):
            resultat.append(_resume(o, services[o["service_id"]]) | {
                "meme_service": meme_service, "economie_par_mois": economie,
                "economie_par_an": round(economie * 12, 2),
                "paiement_d_avance": float(o["prix"]) if (o.get("frequence") or "mensuel") == "annuel" else None,
            })
    return sorted(resultat, key=lambda a: -a["economie_par_mois"])


def meilleur_prix(service_nom: str, offres: list[dict[str, Any]], services: dict[str, dict[str, Any]],
                  profil: dict[str, bool], aujourdhui: date) -> float | None:
    """Prix mensuel le plus bas accessible pour un service (Prime étudiant compris si le profil le permet)."""
    prix = [par_mois(o) for o in offres if services[o["service_id"]]["nom"] == service_nom and not o.get("inclut")
            and accessible(o, profil) and not a_reverifier(o, aujourdhui)]
    return min(prix) if prix else None


def groupees(lignes_mobiles: list[dict[str, Any]], services_suivis: set[str], offres: list[dict[str, Any]],
             services: dict[str, dict[str, Any]], profil: dict[str, bool], aujourdhui: date) -> list[dict[str, Any]]:
    """Offres groupées « à étudier » : comparées à une ligne mobile + les services inclus que Mohamed paie déjà,
    chacun à son meilleur prix accessible. `ecart` > 0 : plus chère. Un service inclus qu'il n'a pas ne remplace
    rien (bonus, sans valeur dans le calcul). Jamais un conseil : Mohamed décide."""
    resultat = []
    for o in offres:
        if not o.get("inclut") or a_reverifier(o, aujourdhui) or not accessible(o, profil):
            continue
        remplaces, cout_services = [], 0.0
        for nom in o["inclut"]:
            meilleur = meilleur_prix(nom, offres, services, profil, aujourdhui) if nom in services_suivis else None
            if meilleur is not None:
                remplaces.append({"service": nom, "par_mois": meilleur})
                cout_services += meilleur
        candidates = [l for l in lignes_mobiles if l.get("go") is not None and o.get("go") is not None
                      and o["go"] >= l["go"]]
        if not candidates:
            continue
        ligne = min(candidates, key=lambda l: par_mois(o) - l["prix"] - cout_services)
        cout = round(ligne["prix"] + cout_services, 2)
        resultat.append(_resume(o, services[o["service_id"]]) | {
            "inclut": list(o["inclut"]),
            "remplace": [{"ligne": ligne["nom"], "par_mois": ligne["prix"]}] + remplaces,
            "cout_actuel": cout, "ecart_par_mois": round(par_mois(o) - cout, 2),
            "go_en_plus": o["go"] - ligne["go"],
        })
    return sorted(resultat, key=lambda g: g["ecart_par_mois"])


def comparer(etats: list[dict[str, Any]], lignes: list[dict[str, Any]], services_liste: list[dict[str, Any]],
             offres: list[dict[str, Any]], profil: dict[str, bool], aujourdhui: date) -> dict[str, Any]:
    """Écran Catalogue : chaque abonnement suivi avec ses lignes et leurs offres moins chères, les offres groupées,
    et le catalogue lui-même (offres à revérifier marquées)."""
    services = {s["id"]: s for s in services_liste}
    par_id = {o["id"]: o for o in offres}
    lignes_par_abo: dict[str, list[dict[str, Any]]] = {}
    for l in lignes:
        lignes_par_abo.setdefault(l["subscription_id"], []).append(l)

    sortie_abos, lignes_mobiles, services_suivis = [], [], set()
    for e in etats:
        if e["statut"] == "resilie":
            continue
        siennes = sorted(lignes_par_abo.get(e["id"], []), key=lambda l: l["nom"])
        propose = service_propose(e["nom"], services_liste) if not siennes else None
        sortie_lignes = []
        for l in siennes:
            actuelle = par_id.get(l.get("catalog_offer_id"))
            # Prix de la ligne : saisi ; sinon, ligne unique : ce que Mohamed paie vraiment ; sinon le prix catalogue.
            prix = (float(l["prix"]) if l.get("prix") is not None
                    else e["par_mois"] if len(siennes) == 1 else par_mois(actuelle) if actuelle else None)
            go = l.get("go") if l.get("go") is not None else (actuelle or {}).get("go")
            service = services[actuelle["service_id"]] if actuelle else None
            if service:
                services_suivis.add(service["nom"])
                if service["famille"] == "mobile" and prix is not None:
                    lignes_mobiles.append({"nom": f"{e['nom']} · {l['nom']}", "prix": prix, "go": go})
            sortie_lignes.append({
                # prix_saisi / go_saisi : tels qu'enregistrés (formulaire de l'app), sans les valeurs par défaut.
                "id": l["id"], "nom": l["nom"], "prix": prix, "go": go,
                "prix_saisi": l.get("prix"), "go_saisi": l.get("go"),
                "offre": _resume(actuelle, service) if actuelle else None,
                "alternatives": alternatives(prix, go, actuelle, offres, services, profil, aujourdhui)
                if actuelle and prix is not None else [],
                "go_manquants": bool(service and service["famille"] == "mobile" and go is None),
            })
        sortie_abos.append({
            "id": e["id"], "nom": e["nom"], "par_mois": e["par_mois"], "statut": e["statut"],
            "rattache": bool(siennes),
            "service_propose": {"id": propose["id"], "nom": propose["nom"]} if propose else None,
            "lignes": sortie_lignes,
        })

    catalogue = [{
        "id": s["id"], "nom": s["nom"], "famille": s["famille"], "page_url": s["page_url"], "page_etat": s["page_etat"],
        "page_lue_le": s.get("page_lue_le"), "page_modifiee_le": s.get("page_modifiee_le"),
        # Page modifiée : montants apparus et disparus depuis la dernière validation, pour choisir le nouveau prix.
        "montants_apparus": sorted(set(s.get("page_montants") or []) - set(s.get("page_montants_avant") or []))
        if s["page_etat"] == "modifiee" else [],
        "montants_disparus": sorted(set(s.get("page_montants_avant") or []) - set(s.get("page_montants") or []))
        if s["page_etat"] == "modifiee" else [],
        "offres": [_resume(o, s) | {"inclut": o.get("inclut"), "a_reverifier": a_reverifier(o, aujourdhui)}
                   for o in sorted(offres, key=lambda o: par_mois(o)) if o["service_id"] == s["id"]],
    } for s in sorted(services_liste, key=lambda s: (s["famille"], s["nom"]))]

    return {
        "profil": profil,
        "abonnements": sortie_abos,
        "groupees": groupees(lignes_mobiles, services_suivis, offres, services, profil, aujourdhui),
        "catalogue": catalogue,
    }


# ── Données ───────────────────────────────────────────────────────────────────

def profil_depuis(lignes: list[dict[str, Any]]) -> dict[str, bool]:
    brut = {r["key"]: r["value"] for r in lignes}
    return {nom: (brut.get(cle) or "").lower() == "true" for nom, cle in PROFIL.items()}


async def _profil() -> dict[str, bool]:
    return profil_depuis(await db.select("settings", key=f"in.({','.join(PROFIL.values())})"))


async def ecran(aujourdhui: date) -> dict[str, Any]:
    ecran_abos, services, offres, lignes, profil = await asyncio.gather(
        abos.ecran(aujourdhui), db.select("catalog_services"), db.select("catalog_offers"),
        db.select("subscription_lines"), _profil(),
    )
    return comparer(ecran_abos["abonnements"], lignes, services, offres, profil, aujourdhui)


async def modifier_profil(valeurs: dict[str, bool]) -> dict[str, bool]:
    existantes = {r["key"] for r in await db.select("settings", select="key", key=f"in.({','.join(PROFIL.values())})")}
    ecritures = []
    for nom, valeur in valeurs.items():
        cle, texte = PROFIL[nom], "true" if valeur else "false"
        ecritures.append(db.update("settings", {"value": texte}, key=f"eq.{cle}") if cle in existantes
                         else db.insert("settings", {"key": cle, "value": texte}))
    await asyncio.gather(*ecritures)
    return await _profil()


async def changer_lignes(abonnement_id: str, lignes: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Remplace les lignes d'un abonnement (rattachement confirmé par Mohamed ; liste vide = détaché)."""
    if not await db.select("subscriptions", select="id", id=f"eq.{abonnement_id}"):
        raise ActionRefusee("Abonnement introuvable.")
    ids = {l["offre_id"] for l in lignes if l.get("offre_id")}
    if ids and len(await db.select("catalog_offers", select="id", id=f"in.({','.join(ids)})")) != len(ids):
        raise ActionRefusee("Offre introuvable dans le catalogue.")
    await db.delete("subscription_lines", subscription_id=f"eq.{abonnement_id}")
    if not lignes:
        return []
    return await db.insert("subscription_lines", [{
        "subscription_id": abonnement_id, "nom": l["nom"], "catalog_offer_id": l.get("offre_id"),
        "prix": l.get("prix"), "go": l.get("go"),
    } for l in lignes])


async def valider_page(service_id: str, prix: dict[str, float], aujourdhui: date) -> None:
    """« Une page de prix a changé » : nouveaux prix choisis par Mohamed (aucun = « Rien ne change ») ; toutes
    les offres du service sont alors vérifiées du jour et la page redevient normale."""
    offres = await db.select("catalog_offers", select="id", service_id=f"eq.{service_id}")
    if not await db.select("catalog_services", select="id", id=f"eq.{service_id}"):
        raise ActionRefusee("Service introuvable dans le catalogue.")
    if not set(prix) <= {o["id"] for o in offres}:
        raise ActionRefusee("Cette offre n'appartient pas à ce service.")
    await asyncio.gather(*(db.update("catalog_offers", {"prix": p}, id=f"eq.{i}") for i, p in prix.items()))
    await db.update("catalog_offers", {"verifie_le": aujourdhui.isoformat()}, service_id=f"eq.{service_id}")
    await db.update("catalog_services", {"page_etat": "ok", "page_montants_avant": None}, id=f"eq.{service_id}")


async def verifier_offre(offre_id: str, prix: float | None, aujourdhui: date) -> dict[str, Any]:
    """Vérifiée à la main (pages illisibles, ou prix revu) : nouveau prix éventuel, date du jour."""
    valeurs: dict[str, Any] = {"verifie_le": aujourdhui.isoformat()}
    if prix is not None:
        valeurs["prix"] = prix
    trouves = await db.update("catalog_offers", valeurs, id=f"eq.{offre_id}")
    if not trouves:
        raise ActionRefusee("Offre introuvable dans le catalogue.")
    return trouves[0]
