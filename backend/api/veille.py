"""Surveillance des pages de prix officielles — voir docs/regles-de-calcul.md § 12, point 2.

Le 1er du mois, à la synchro de 8 h : chaque page est relue et l'ensemble des montants en euros qu'elle affiche
est comparé à la lecture précédente. Méthode semi-automatique, sans IA : Opti signale qu'une page a changé,
Mohamed valide le nouveau prix en un clic. `montants_de_page` et `nouvel_etat` sont purs (testables).
"""
import asyncio
import html
import re
from datetime import datetime, timezone
from typing import Any

import httpx

import budget
import db

JOUR, HEURE = 1, 8                   # le 1er du mois, synchro de 8 h (Paris)
NAVIGATEUR = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130 Safari/537.36",
              "Accept-Language": "fr-FR,fr;q=0.9"}
# « 9,99 € », « 9.99€ », « 69 € », et la façon d'écrire de Free : « 19 €99 ».
MONTANT = re.compile(r"(?<![\d,.])(\d{1,4})(?:[,.](\d{2}))?\s?(?:€|&euro;|EUR\b)(\d{2}\b)?")


def montants_de_page(page: str) -> list[float]:
    """Montants en euros affichés dans le texte de la page (scripts et styles ignorés), triés, sans doublon."""
    texte = re.sub(r"<script.*?</script>|<style.*?</style>", " ", page, flags=re.S | re.I)
    texte = html.unescape(re.sub(r"<[^>]+>", " ", texte)).replace("\xa0", " ").replace(" ", " ")
    montants = set()
    for entiers, centimes, centimes_apres in MONTANT.findall(re.sub(r"[ \t]+", " ", texte)):
        montants.add(round(int(entiers) + int(centimes or centimes_apres or 0) / 100, 2))
    return sorted(montants)


def nouvel_etat(avant: list[float] | None, apres: list[float], etat: str) -> tuple[str, bool]:
    """(nouvel état, page modifiée à l'instant ?). Aucun montant lu : illisible. Première lecture : référence.
    Une page modifiée le reste jusqu'à la validation de Mohamed, sans nouvelle notification si rien ne bouge."""
    if not apres:
        return "illisible", False
    if avant is None:
        return ("modifiee" if etat == "modifiee" else "ok"), False
    if {round(float(m), 2) for m in avant} != set(apres):
        return "modifiee", True
    return ("modifiee" if etat == "modifiee" else "ok"), False


def jour_de_veille(maintenant: datetime | None = None) -> bool:
    paris = (maintenant or datetime.now(timezone.utc)).astimezone(budget.PARIS)
    return paris.day == JOUR and paris.hour == HEURE


async def _lire(client: httpx.AsyncClient, url: str) -> str | None:
    try:
        r = await client.get(url, headers=NAVIGATEUR, follow_redirects=True)
        return r.text if r.status_code == 200 else None
    except httpx.HTTPError:
        return None


async def lire_pages(maintenant: datetime | None = None) -> dict[str, int]:
    """Relit toutes les pages du catalogue. Réponse réduite aux compteurs (logs du cron)."""
    maintenant = maintenant or datetime.now(timezone.utc)
    services = await db.select("catalog_services")
    async with httpx.AsyncClient(timeout=15.0) as client:
        pages = await asyncio.gather(*(_lire(client, s["page_url"]) for s in services))
    compteurs = {"lues": 0, "modifiees": 0, "illisibles": 0}
    ecritures = []
    for s, page in zip(services, pages):
        montants = montants_de_page(page) if page else []
        # Référence = dernière lecture validée : celle d'avant le changement si la page attend déjà Mohamed.
        reference = s.get("page_montants_avant") if s["page_etat"] == "modifiee" else s.get("page_montants")
        etat, modifiee = nouvel_etat(s.get("page_montants"), montants, s["page_etat"])
        valeurs: dict[str, Any] = {"page_lue_le": maintenant.isoformat(), "page_etat": etat}
        if montants:
            valeurs["page_montants"] = montants
            compteurs["lues"] += 1
        else:
            compteurs["illisibles"] += 1
        if modifiee:
            valeurs |= {"page_montants_avant": reference, "page_modifiee_le": maintenant.isoformat()}
            compteurs["modifiees"] += 1
        ecritures.append(db.update("catalog_services", valeurs, id=f"eq.{s['id']}"))
    await asyncio.gather(*ecritures)
    return compteurs
