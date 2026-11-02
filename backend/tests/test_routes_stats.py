"""Routes Stats : réservées au propriétaire, période validée."""
import os
import sys
from pathlib import Path

from fastapi.testclient import TestClient

os.environ.setdefault("SUPABASE_URL", "https://exemple.supabase.co")
os.environ.setdefault("OWNER_USER_ID", "11111111-2222-4333-8444-555555555555")
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

import index  # noqa: E402

client = TestClient(index.app)


def test_routes_stats_exigent_la_session():
    assert client.get("/stats").status_code == 401
    assert client.get("/stats/operations?debut=2026-09-25&fin=2026-10-25&categorie=Alimentation").status_code == 401


def test_periode_inconnue_refusee():
    index.app.dependency_overrides[index.require_owner] = lambda: "proprietaire"
    try:
        assert client.get("/stats?periode=3").status_code == 422
        assert client.get("/stats/operations?debut=2026-09-25&fin=2026-10-25").status_code == 422   # catégorie manquante
    finally:
        index.app.dependency_overrides.clear()
