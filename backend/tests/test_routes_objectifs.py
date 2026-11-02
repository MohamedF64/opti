"""Routes Objectifs : réservées au propriétaire, entrées validées, refus métier lisibles."""
import os
import sys
from pathlib import Path

from fastapi.testclient import TestClient

os.environ.setdefault("SUPABASE_URL", "https://exemple.supabase.co")
os.environ.setdefault("OWNER_USER_ID", "11111111-2222-4333-8444-555555555555")
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

import index  # noqa: E402
import objectifs  # noqa: E402

client = TestClient(index.app)
ID = "b02c7d86-e0b2-42dc-bb97-c8e238ba3448"
ROUTES = [
    ("get", "/objectifs", None),
    ("post", "/objectifs", {"nom": "Permis", "cible": 1200}),
    ("patch", f"/objectifs/{ID}", {"statut": "archive"}),
    ("post", f"/objectifs/{ID}/mouvements", {"montant": 150}),
    ("post", f"/mouvements/{ID}/confirmer", {}),
    ("post", f"/mouvements/{ID}/contester", None),
    ("delete", f"/mouvements/{ID}", None),
    ("post", f"/reserve/{ID}/attribuer", {"objectif_id": ID}),
    ("post", f"/operations/{ID}/rattacher", {"objectif_id": None}),
    ("get", f"/reserve/{ID}/annulation", None),
    ("post", f"/operations/{ID}/ignorer-suggestion", None),
    ("post", f"/reserve/{ID}/reprise", {"objectif_id": None}),
    ("post", f"/reserve/{ID}/annuler", {"mouvement_ids": [ID]}),
]


def appeler(methode, chemin, corps):
    return getattr(client, methode)(chemin, **({"json": corps} if corps is not None else {}))


def test_toutes_les_routes_exigent_la_session():
    for methode, chemin, corps in ROUTES:
        assert appeler(methode, chemin, corps).status_code == 401, chemin


def connecte():
    index.app.dependency_overrides[index.require_owner] = lambda: "proprietaire"


def test_entrees_invalides_refusees():
    connecte()
    try:
        assert client.post(f"/objectifs/{ID}/mouvements", json={"montant": 0}).status_code == 422
        assert client.post("/objectifs", json={"nom": "", "cible": 100}).status_code == 422
        assert client.post("/objectifs", json={"nom": "X", "cible": -5}).status_code == 422
        assert client.patch(f"/objectifs/{ID}", json={"statut": "supprime"}).status_code == 422
        assert client.patch(f"/objectifs/{ID}", json={}).status_code == 422
        assert client.post("/mouvements/pas-un-uuid/contester").status_code == 422
    finally:
        index.app.dependency_overrides.clear()


def test_refus_metier_renvoie_409_avec_le_message(monkeypatch):
    async def refuse(*_):
        raise objectifs.ActionRefusee("Ce versement n'est pas confirmé.")
    monkeypatch.setattr(objectifs, "contester", refuse)
    connecte()
    try:
        r = client.post(f"/mouvements/{ID}/contester")
        assert (r.status_code, r.json()["detail"]) == (409, "Ce versement n'est pas confirmé.")
    finally:
        index.app.dependency_overrides.clear()
