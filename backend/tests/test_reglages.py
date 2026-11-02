"""Réglages : conversion vers la table settings, routes réservées au propriétaire et validées."""
import os
import sys
from pathlib import Path

from fastapi.testclient import TestClient

os.environ.setdefault("SUPABASE_URL", "https://exemple.supabase.co")
os.environ.setdefault("OWNER_USER_ID", "11111111-2222-4333-8444-555555555555")
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

import index  # noqa: E402
import reglages as r  # noqa: E402

client = TestClient(index.app)


def test_conversion_vers_la_base_et_retour():
    assert r.en_base({"limite_manuelle": 40.0, "mode_economies_max": True, "epargne_visee": None}) == {
        "limite_manuelle": "40.0", "mode_economies_max": "true", "epargne_visee": None}
    lignes = [{"key": "salary_day", "value": "21"}, {"key": "salary_day_max", "value": "28"},
              {"key": "limite_manuelle", "value": "40.0"}, {"key": "mode_economies_max", "value": "true"}]
    assert r.depuis_base(lignes) == {"jour_paie_min": 21, "jour_paie_max": 28, "limite_manuelle": 40.0,
                                     "mode_economies_max": True, "epargne_visee": None}
    assert r.depuis_base([])["jour_paie_max"] == 28


def test_routes_reservees():
    assert client.get("/reglages").status_code == 401
    assert client.post("/reglages/apercu", json={}).status_code == 401
    assert client.patch("/reglages", json={"limite_manuelle": 40}).status_code == 401


def test_entrees_invalides(monkeypatch):
    async def lire():
        return {"jour_paie_min": 21, "jour_paie_max": 28, "limite_manuelle": None, "mode_economies_max": False,
                "epargne_visee": None}
    monkeypatch.setattr(r, "lire", lire)
    index.app.dependency_overrides[index.require_owner] = lambda: "proprietaire"
    try:
        assert client.patch("/reglages", json={"limite_manuelle": -5}).status_code == 422
        assert client.patch("/reglages", json={"jour_paie_min": 32}).status_code == 422
        assert client.patch("/reglages", json={"jour_paie_min": 29}).status_code == 422   # après le 28
        assert client.patch("/reglages", json={}).status_code == 422
    finally:
        index.app.dependency_overrides.clear()
