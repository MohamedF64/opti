"""Bons plans Dealabs — voir docs/regles-de-calcul.md § 12, point 3.

Flux RSS publics lus par le serveur à chaque synchro automatique ; seuls les bons plans des enseignes où
Mohamed achète (ou qu'il a ajoutées) et les essais gratuits des services du catalogue sont gardés, 7 jours.
Ses enseignes ne sortent jamais d'Opti : on télécharge les flux complets et le tri se fait ici.
Pas de notification (aucune incitation à acheter). Les fonctions de tri sont pures (testables).
"""
import asyncio
import re
import xml.etree.ElementTree as ET
from datetime import date, datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from typing import Any

import httpx

import db
import synchro
import veille

FLUX = [f"https://www.dealabs.com/rss/{f}" for f in (
    "tous", "tendance", "groupe/gratuit", "groupe/forfaits-mobiles", "groupe/high-tech", "groupe/mode",
    "groupe/culture-divertissement", "groupe/services-divers")]
PEPPER = "{http://www.pepper.com/rss}"
GARDE_JOURS = 7
CATEGORIES = {"Shopping", "Loisirs", "Maison", "Sport", "High-tech"}
MIN_ACHATS, MIN_TOTAL = 2, 40.0             # sur les 12 derniers mois
MOT_MIN = 4                                 # « primark oparinor » = « Primark » : premier mot d'au moins 4 lettres
ESSAI = re.compile(r"\bessai\b|\bmois offerts?\b|\bjours offerts\b|\bgratuit", re.I)


def cle(nom: str) -> str:
    return synchro.cle_marchand(nom)


def meme_enseigne(a: str, b: str) -> bool:
    """« amazon payments » = « amazon » ; « primark oparinor » = « primark » ; « fnac » = « fnac » ;
    mais « new yorker » ≠ « new balance » (premier mot trop court)."""
    if not a or not b:
        return False
    if synchro.meme_marchand(a, b):
        return True
    premier_a, premier_b = a.split()[0], b.split()[0]
    return premier_a == premier_b and len(premier_a) >= MOT_MIN


def enseignes(operations: list[dict[str, Any]], choix: list[dict[str, Any]], aujourdhui: date) -> list[dict[str, Any]]:
    """Enseignes suivies : déduites des dépenses des 12 derniers mois (2 achats ou 40 € au moins dans les
    catégories d'achats), plus celles ajoutées par Mohamed, moins celles qu'il a retirées."""
    depuis = aujourdhui - timedelta(days=365)
    groupes: dict[str, dict[str, Any]] = {}
    for o in operations:
        if (o.get("category") not in CATEGORIES or float(o["amount"]) >= 0 or o.get("is_internal")
                or date.fromisoformat(str(o["date"])[:10]) < depuis):
            continue
        k = cle(o.get("merchant") or o.get("description") or "")
        if not k:
            continue
        groupe = next((g for g in groupes if meme_enseigne(g, k)), None) or k
        g = groupes.setdefault(groupe, {"achats": 0, "total": 0.0, "noms": set()})
        g["achats"] += 1
        g["total"] += -float(o["amount"])
        g["noms"].add(k)
    retirees = [cle(c["nom"]) for c in choix if not c["suivie"]]
    resultat = []
    for k, g in groupes.items():
        if (g["achats"] >= MIN_ACHATS or g["total"] >= MIN_TOTAL) and not any(meme_enseigne(k, r) for r in retirees):
            court = min(g["noms"], key=len)
            nom = court.split()[0] if len(court.split()[0]) >= MOT_MIN else court
            resultat.append({"nom": nom.title(), "cle": nom, "origine": "depenses", "total": round(g["total"], 2)})
    for c in choix:
        if c["suivie"] and not any(meme_enseigne(cle(c["nom"]), e["cle"]) for e in resultat):
            resultat.append({"nom": c["nom"], "cle": cle(c["nom"]), "origine": "ajoutee", "total": None})
    return sorted(resultat, key=lambda e: e["nom"].lower())


def lire_flux(xml: str) -> list[dict[str, Any]]:
    """Bons plans d'un flux RSS Dealabs : titre, lien, enseigne, prix, date. Flux illisible : liste vide."""
    try:
        racine = ET.fromstring(xml)
    except ET.ParseError:
        return []
    resultat = []
    for item in racine.iter("item"):
        marchand = item.find(f"{PEPPER}merchant")
        lien = (item.findtext("link") or "").strip()
        try:
            publie = parsedate_to_datetime(item.findtext("pubDate") or "")
        except (TypeError, ValueError):
            continue
        if not lien.startswith("https://www.dealabs.com/"):
            continue
        prix = (marchand.get("price") if marchand is not None else None) or None
        resultat.append({
            "id": (item.findtext("guid") or lien).strip(), "titre": (item.findtext("title") or "").strip()[:200],
            "lien": lien, "enseigne": marchand.get("name") if marchand is not None else None,
            "prix": prix, "publie_le": publie.isoformat(),
        })
    return resultat


def garder(bons: list[dict[str, Any]], suivies: list[dict[str, Any]], services: list[str]) -> list[dict[str, Any]]:
    """Bons plans d'une enseigne suivie, ou essais gratuits d'un service du catalogue (« 3 mois offerts »)."""
    resultat, vus = [], set()
    for b in bons:
        if b["id"] in vus:
            continue
        enseigne = next((e["nom"] for e in suivies if b["enseigne"] and meme_enseigne(e["cle"], cle(b["enseigne"]))),
                        None)
        titre = b["titre"].lower()
        service = next((s for s in services if ESSAI.search(b["titre"]) and s.lower() in titre), None)
        if enseigne or service:
            vus.add(b["id"])
            resultat.append(b | {"type": "essai" if service else "enseigne", "suivie": enseigne or service})
    return resultat


# ── Données ───────────────────────────────────────────────────────────────────

async def _suivies(aujourdhui: date) -> list[dict[str, Any]]:
    debut = (aujourdhui - timedelta(days=365)).isoformat()
    operations, choix = await asyncio.gather(
        db.select_tout("transactions", select="id,date,amount,merchant,description,category,is_internal",
                       date=f"gte.{debut}", amount="lt.0", is_internal="eq.false"),
        db.select("followed_merchants"),
    )
    return enseignes(operations, choix, aujourdhui)


async def collecter(maintenant: datetime | None = None) -> dict[str, int]:
    """Après une synchro automatique : lit les flux, garde ce qui concerne Mohamed, oublie ce qui a plus de 7 jours.
    Réponse réduite aux compteurs (logs du cron)."""
    maintenant = maintenant or datetime.now(timezone.utc)
    async with httpx.AsyncClient(timeout=15.0) as client:
        reponses = await asyncio.gather(*(client.get(u, headers=veille.NAVIGATEUR) for u in FLUX),
                                        return_exceptions=True)
    bons = [b for r in reponses if isinstance(r, httpx.Response) and r.status_code == 200 for b in lire_flux(r.text)]
    suivies, services = await asyncio.gather(_suivies(maintenant.date()), db.select("catalog_services", select="nom"))
    limite = maintenant - timedelta(days=GARDE_JOURS)
    gardes = [b for b in garder(bons, suivies, [s["nom"] for s in services])
              if datetime.fromisoformat(b["publie_le"]) >= limite]
    if gardes:
        await db.upsert("bons_plans", gardes, on_conflict="id")
    await db.delete("bons_plans", publie_le=f"lt.{limite.isoformat()}")
    return {"flux_lus": sum(isinstance(r, httpx.Response) and r.status_code == 200 for r in reponses),
            "gardes": len(gardes)}


async def ecran(aujourdhui: date) -> dict[str, Any]:
    depuis = (aujourdhui - timedelta(days=GARDE_JOURS)).isoformat()
    bons, suivies, choix = await asyncio.gather(
        db.select("bons_plans", publie_le=f"gte.{depuis}", order="publie_le.desc"),
        _suivies(aujourdhui), db.select("followed_merchants", select="nom,suivie", suivie="eq.false"),
    )
    return {"bons_plans": bons, "enseignes": suivies, "retirees": sorted(c["nom"] for c in choix)}


async def choisir_enseigne(nom: str, suivie: bool) -> None:
    """Ajouter (suivie) ou retirer une enseigne ; une enseigne retirée ne revient pas avec les dépenses."""
    await db.upsert("followed_merchants", {"nom": nom.strip(), "suivie": suivie}, on_conflict="nom")
