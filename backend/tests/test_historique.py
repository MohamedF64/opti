"""Historique : recherche sans danger pour les filtres PostgREST, route réservée au propriétaire."""
import os
import sys
from pathlib import Path

from fastapi.testclient import TestClient

os.environ.setdefault("SUPABASE_URL", "https://exemple.supabase.co")
os.environ.setdefault("OWNER_USER_ID", "11111111-2222-4333-8444-555555555555")
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

import historique as h  # noqa: E402
import index  # noqa: E402

client = TestClient(index.app)


def test_recherche_nettoyee():
    assert h.nettoyer_recherche("Primark") == "Primark"
    assert h.nettoyer_recherche("  Maison   Durand ") == "Maison Durand"
    assert h.nettoyer_recherche("Le Maraîcher l'été") == "Le Maraîcher l'été"
    # Ce qui pourrait sortir du filtre : virgules, parenthèses, points, étoiles.
    assert h.nettoyer_recherche("a),amount.gt.0,(b*") == "a amount gt 0 b"
    assert len(h.nettoyer_recherche("x" * 100)) == 40
    assert h.nettoyer_recherche(None) == ""


def test_historique_reserve_au_proprietaire():
    assert client.get("/operations").status_code == 401


def test_historique_page_et_suite(monkeypatch):
    from datetime import date
    appels = []

    async def select(table, **filtres):
        appels.append(filtres)
        if filtres.get("limit") == "1":
            return [{"date": "2026-05-01"}]
        return [{"id": "t1", "date": "2026-10-31", "amount": -5}]

    monkeypatch.setattr(h.db, "select", select)
    import asyncio
    r = asyncio.run(h.operations(date(2026, 10, 31)))
    assert r["suite"] == date(2026, 10, 17)                       # 14 jours : 18/10 → 31/10
    assert appels[0]["date"] == "gte.2026-10-18" and appels[0]["and"] == "(date.lte.2026-10-31)"
    r = asyncio.run(h.operations(date(2026, 5, 10)))
    assert r["suite"] is None                                     # plus rien avant le 01/05
