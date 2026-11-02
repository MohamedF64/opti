"""Tests de l'authentification du backend.

On génère une paire de clés ES256 locale qui joue le rôle de Supabase :
aucun appel réseau, aucun vrai jeton.
"""
import os
import sys
import time
from pathlib import Path

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi.testclient import TestClient

SUPABASE_URL = "https://exemple.supabase.co"
OWNER = "11111111-2222-4333-8444-555555555555"

os.environ["SUPABASE_URL"] = SUPABASE_URL
os.environ["OWNER_USER_ID"] = OWNER
os.environ.pop("SUPABASE_SERVICE_ROLE_KEY", None)
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

import index  # noqa: E402

FAKE_SUPABASE_KEY = ec.generate_private_key(ec.SECP256R1())
INTRUS_KEY = ec.generate_private_key(ec.SECP256R1())


class _FakeSigningKey:
    key = FAKE_SUPABASE_KEY.public_key()


@pytest.fixture(autouse=True)
def fake_jwks(monkeypatch):
    monkeypatch.setattr(index._jwks_client, "get_signing_key_from_jwt", lambda token: _FakeSigningKey())


client = TestClient(index.app)


def make_token(sub=OWNER, key=FAKE_SUPABASE_KEY, exp_in=3600, aud="authenticated", iss=f"{SUPABASE_URL}/auth/v1", aal="aal2"):
    now = int(time.time())
    claims = {"sub": sub, "aud": aud, "iss": iss, "iat": now, "exp": now + exp_in, "aal": aal}
    return jwt.encode({k: v for k, v in claims.items() if v is not None}, key, algorithm="ES256")


def appel(token=None):
    """Une route protégée quelconque : l'état des banques."""
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    return client.get("/banque/etat", headers=headers)


def test_sans_jeton_refuse():
    assert appel().status_code == 401


def test_jeton_du_proprietaire_accepte():
    # Passe l'authentification ; échoue ensuite faute de base configurée, ce qui est attendu ici.
    r = appel(make_token())
    assert r.status_code == 502
    assert "SUPABASE_SERVICE_ROLE_KEY" in r.json()["detail"]


def test_mot_de_passe_seul_refuse():
    # Session ouverte avec le mot de passe, sans le code à 6 chiffres.
    r = appel(make_token(aal="aal1"))
    assert r.status_code == 403
    assert r.json()["detail"] == "Code de vérification requis"


def test_jeton_sans_niveau_refuse():
    assert appel(make_token(aal=None)).status_code == 403


def test_jeton_expire_refuse():
    assert appel(make_token(exp_in=-60)).status_code == 401


def test_jeton_signe_par_un_intrus_refuse():
    assert appel(make_token(key=INTRUS_KEY)).status_code == 401


def test_jeton_d_un_autre_compte_refuse():
    assert appel(make_token(sub="00000000-0000-0000-0000-000000000001")).status_code == 403


def test_mauvaise_audience_refusee():
    assert appel(make_token(aud="anon")).status_code == 401


def test_mauvais_emetteur_refuse():
    assert appel(make_token(iss="https://autre-projet.supabase.co/auth/v1")).status_code == 401


def test_jeton_illisible_refuse():
    assert appel("pas-un-jeton").status_code == 401


def test_routes_publiques_restent_ouvertes():
    assert client.get("/health").status_code == 200
    for page in ("/confidentialite", "/conditions"):
        r = client.get(page)
        assert r.status_code == 200
        assert "text/html" in r.headers["content-type"]


def test_route_ia_retiree():
    assert client.post("/ia", json={"action": "x"}).status_code == 404


def test_retour_banque_ne_montre_pas_le_detail_technique(monkeypatch):
    async def panne(code, state):
        raise index.db.DatabaseError("Base 500 sur bank_auth_requests : détail interne")
    monkeypatch.setattr(index.bq, "terminer_connexion", panne)
    r = client.get("/banque/retour", params={"code": "c", "state": "s"})
    assert r.status_code == 502
    assert "bank_auth_requests" not in r.text and "Erreur technique" in r.text


# Routes ouvertes sans session (chacune protégée autrement : state à usage unique, secret du cron, Preview).
PUBLIQUES = {"/", "/health", "/confidentialite", "/conditions", "/banque/retour", "/banque/synchro/cron"}


def test_toutes_les_autres_routes_exigent_la_session():
    """Filet de sécurité : une nouvelle route oubliée sans protection fait échouer ce test."""
    from routes import apercus
    apercu = {r.path for r in apercus.router.routes}
    exemples = {"abonnement_id": OWNER, "mouvement_id": OWNER, "goal_id": OWNER, "transaction_id": OWNER,
                "service_id": OWNER, "offre_id": OWNER, "cle": "netflix"}
    verifiees = 0
    for chemin, methodes in index.app.openapi()["paths"].items():
        if chemin in PUBLIQUES or chemin in apercu:
            continue
        url = chemin.format(**exemples)
        for methode in methodes:
            assert client.request(methode.upper(), url).status_code == 401, f"{methode.upper()} {chemin}"
            verifiees += 1
    assert verifiees >= 45
