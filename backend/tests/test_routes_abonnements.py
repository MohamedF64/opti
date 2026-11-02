"""Routes Abonnements : réservées au propriétaire, entrées validées."""
import os
import sys
from pathlib import Path

from fastapi.testclient import TestClient

os.environ.setdefault("SUPABASE_URL", "https://exemple.supabase.co")
os.environ.setdefault("OWNER_USER_ID", "11111111-2222-4333-8444-555555555555")
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

import index  # noqa: E402

client = TestClient(index.app)
ID = "b02c7d86-e0b2-42dc-bb97-c8e238ba3448"
ROUTES = [
    ("get", "/abonnements", None),
    ("post", "/abonnements", {"nom": "Netflix", "montant": 9.99}),
    ("patch", f"/abonnements/{ID}", {"usage": "souvent"}),
    ("delete", f"/abonnements/{ID}", None),
    ("post", f"/abonnements/{ID}/prix-ok", None),
    ("post", "/abonnements/detectes/netflix/ajouter", {}),
    ("post", "/abonnements/detectes/netflix/refuser", None),
]


def test_toutes_les_routes_exigent_la_session():
    for methode, chemin, corps in ROUTES:
        r = getattr(client, methode)(chemin, **({"json": corps} if corps is not None else {}))
        assert r.status_code == 401, chemin


def test_entrees_invalides_refusees():
    index.app.dependency_overrides[index.require_owner] = lambda: "proprietaire"
    try:
        assert client.post("/abonnements", json={"nom": "X", "montant": 0}).status_code == 422
        assert client.post("/abonnements", json={"nom": "X", "montant": 5, "frequence": "parfois"}).status_code == 422
        assert client.patch(f"/abonnements/{ID}", json={"usage": "beaucoup"}).status_code == 422
        assert client.patch(f"/abonnements/{ID}", json={"mois_pause": [13]}).status_code == 422
        assert client.patch(f"/abonnements/{ID}", json={}).status_code == 422
        assert client.patch("/abonnements/pas-un-uuid", json={"usage": "souvent"}).status_code == 422
    finally:
        index.app.dependency_overrides.clear()
