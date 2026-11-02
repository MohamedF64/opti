"""Client Enable Banking (accès aux comptes CIC et Revolut).

Chaque appel est authentifié par un jeton JWT RS256 signé avec la clé privée de
l'application Opti (`EB_PRIVATE_KEY`), dont l'identifiant (`EB_APP_ID`) sert de `kid`.
Doc : https://enablebanking.com/docs/api/reference/
"""
import asyncio
import os
import time
from typing import Any

import httpx
import jwt

EB_API_URL = "https://api.enablebanking.com"
_JWT_LIFETIME = 3600  # 1 h ; l'API refuse au-delà de 24 h


class EnableBankingError(Exception):
    """Erreur renvoyée par Enable Banking ou par la banque derrière (ex. EXPIRED_SESSION)."""

    def __init__(self, status: int, code: str | None, message: str):
        super().__init__(f"Enable Banking {status} {code or ''} : {message}".strip())
        self.status = status
        self.code = code
        self.message = message


def _credentials(app_id: str | None = None, private_key: str | None = None) -> tuple[str, str]:
    app_id = app_id or os.environ.get("EB_APP_ID")
    private_key = private_key or os.environ.get("EB_PRIVATE_KEY")
    if not app_id or not private_key:
        raise EnableBankingError(500, "CONFIG", "EB_APP_ID ou EB_PRIVATE_KEY manquante côté serveur")
    # Certaines interfaces stockent les retours à la ligne du PEM sous forme littérale « \n ».
    return app_id.strip(), private_key.replace("\\n", "\n").strip()


def make_jwt(app_id: str | None = None, private_key: str | None = None, now: int | None = None) -> str:
    app_id, private_key = _credentials(app_id, private_key)
    iat = int(now if now is not None else time.time())
    return jwt.encode(
        {"iss": "enablebanking.com", "aud": "api.enablebanking.com", "iat": iat, "exp": iat + _JWT_LIFETIME},
        private_key,
        algorithm="RS256",
        headers={"kid": app_id},
    )


_partage: tuple[asyncio.AbstractEventLoop, httpx.AsyncClient] | None = None


def _client() -> httpx.AsyncClient:
    """Connexion gardée ouverte vers Enable Banking (même principe que db._client)."""
    global _partage
    boucle = asyncio.get_running_loop()
    if _partage is None or _partage[0] is not boucle or _partage[1].is_closed:
        _partage = (boucle, httpx.AsyncClient(base_url=EB_API_URL, timeout=30.0))
    return _partage[1]


async def request(
    method: str,
    path: str,
    *,
    params: dict[str, Any] | None = None,
    json: dict[str, Any] | None = None,
    psu: dict[str, str] | None = None,
    app_id: str | None = None,
    private_key: str | None = None,
) -> dict[str, Any]:
    """Appelle l'API et renvoie le JSON ; lève EnableBankingError en cas d'échec.

    `psu` : en-têtes décrivant Mohamed quand il est présent (Psu-Ip-Address, Psu-User-Agent).
    La banque compte alors la consultation comme faite par lui, sans le plafond quotidien
    des consultations en son absence.
    """
    headers = {"Authorization": f"Bearer {make_jwt(app_id, private_key)}", **(psu or {})}
    try:
        response = await _client().request(method, path, params=params, json=json, headers=headers)
    except httpx.HTTPError as e:
        raise EnableBankingError(502, "NETWORK", type(e).__name__)

    if response.status_code >= 400:
        try:
            body = response.json()
        except ValueError:
            body = {}
        raise EnableBankingError(
            response.status_code,
            body.get("error") or body.get("code"),
            body.get("message") or response.text[:300],
        )
    return response.json()


async def list_aspsps(country: str = "FR", **creds) -> list[dict[str, Any]]:
    data = await request("GET", "/aspsps", params={"country": country, "psu_type": "personal"}, **creds)
    return data.get("aspsps", [])
