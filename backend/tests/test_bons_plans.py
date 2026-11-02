"""Bons plans Dealabs : exemples de docs/regles-de-calcul.md § 12, point 3."""
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

import bons_plans as bp  # noqa: E402

AUJOURDHUI = date(2026, 11, 1)


def op(marchand, montant, jour="2026-10-01", categorie="Shopping"):
    return {"merchant": marchand, "amount": -montant, "date": jour, "category": categorie, "is_internal": False}


OPERATIONS = [
    op("AMAZON PAYMENTS", 30), op("AMAZON EU SARL", 20),           # même enseigne, 2 achats
    op("PRIMARK OPARINOR", 48.15),                                  # 1 achat, plus de 40 €
    op("ALIEXPRESS", 3.0),                                          # 1 petit achat : pas suivie
    op("VINTED", 20), op("VINTED", 15),                             # retirée par le propriétaire
    op("CARREFOUR", 80, categorie="Alimentation"),                  # pas une catégorie d'achats
    op("FNAC", 60, jour="2025-09-01"),                              # plus de 12 mois
]
CHOIX = [{"nom": "Vinted", "suivie": False}, {"nom": "Fnac", "suivie": True}, {"nom": "New Yorker", "suivie": True}]


def test_enseignes_suivies():
    suivies = bp.enseignes(OPERATIONS, CHOIX, AUJOURDHUI)
    assert [(e["nom"], e["origine"]) for e in suivies] == [
        ("Amazon", "depenses"), ("Fnac", "ajoutee"), ("New Yorker", "ajoutee"), ("Primark", "depenses")]


def test_meme_enseigne():
    assert bp.meme_enseigne("amazon payments", "amazon")
    assert bp.meme_enseigne("primark oparinor", "primark")
    assert bp.meme_enseigne("fnac", "fnac")
    assert not bp.meme_enseigne("new yorker", "new balance")
    assert bp.meme_enseigne("fnac", "fnac darty")              # même premier mot (4 lettres)
    assert bp.meme_enseigne("darty", "darty marketplace")


FLUX = """<?xml version="1.0" encoding="UTF-8"?>
<rss xmlns:pepper="http://www.pepper.com/rss" version="2.0"><channel>
<item><pepper:merchant name="Amazon" price="449€"/><title><![CDATA[Écran 27" à 449€]]></title>
<link>https://www.dealabs.com/bons-plans/ecran-1</link><pubDate>Sun, 01 Nov 2026 11:53:42 +0100</pubDate>
<guid>https://www.dealabs.com/bons-plans/ecran-1</guid></item>
<item><pepper:merchant name="Foot Locker" price="76,50€"/><title>Baskets</title>
<link>https://www.dealabs.com/bons-plans/baskets-2</link><pubDate>Sun, 01 Nov 2026 10:00:00 +0100</pubDate>
<guid>https://www.dealabs.com/bons-plans/baskets-2</guid></item>
<item><title>Claude Pro : 1 mois offert pour les nouveaux abonnés</title>
<link>https://www.dealabs.com/bons-plans/claude-3</link><pubDate>Sat, 31 Oct 2026 09:00:00 +0100</pubDate>
<guid>https://www.dealabs.com/bons-plans/claude-3</guid></item>
<item><title>Lien douteux</title><link>https://ailleurs.example/x</link>
<pubDate>Sat, 31 Oct 2026 09:00:00 +0100</pubDate></item>
</channel></rss>"""


def test_lire_flux():
    bons = bp.lire_flux(FLUX)
    assert [(b["enseigne"], b["prix"]) for b in bons] == [("Amazon", "449€"), ("Foot Locker", "76,50€"), (None, None)]
    assert bp.lire_flux("pas du xml") == []


def test_garder():
    """« Amazon — 449 € » : Amazon suivie → gardé. « Foot Locker » : non suivie → ignoré. Essai Claude : gardé."""
    suivies = bp.enseignes(OPERATIONS, CHOIX, AUJOURDHUI)
    gardes = bp.garder(bp.lire_flux(FLUX), suivies, ["Claude", "Prixtel"])
    assert [(g["type"], g["suivie"]) for g in gardes] == [("enseigne", "Amazon"), ("essai", "Claude")]
