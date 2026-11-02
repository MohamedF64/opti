"""Tests du client Enable Banking (sans appel réseau)."""
import sys
from pathlib import Path

import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

import enable_banking as eb  # noqa: E402

KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
PEM = KEY.private_bytes(
    serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
).decode()
APP_ID = "f0000000-0000-4000-8000-000000000000"


def test_jeton_conforme_a_la_doc():
    token = eb.make_jwt(APP_ID, PEM, now=1_800_000_000)
    assert jwt.get_unverified_header(token) == {"alg": "RS256", "kid": APP_ID, "typ": "JWT"}
    claims = jwt.decode(token, KEY.public_key(), algorithms=["RS256"], audience="api.enablebanking.com",
                        options={"verify_exp": False, "verify_iat": False})
    assert claims["iss"] == "enablebanking.com"
    assert claims["exp"] - claims["iat"] == 3600


def test_cle_avec_retours_a_la_ligne_litteraux():
    # Variante où le PEM a été collé avec des « \n » littéraux au lieu de vrais retours à la ligne.
    token = eb.make_jwt(APP_ID, PEM.replace("\n", "\\n"), now=1_800_000_000)
    assert jwt.get_unverified_header(token)["kid"] == APP_ID


def test_configuration_manquante(monkeypatch):
    monkeypatch.delenv("EB_APP_ID", raising=False)
    monkeypatch.delenv("EB_PRIVATE_KEY", raising=False)
    with pytest.raises(eb.EnableBankingError) as err:
        eb.make_jwt()
    assert err.value.code == "CONFIG"
