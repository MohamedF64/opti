"""Accès à la base Supabase depuis le backend, via l'API REST (PostgREST).

Utilise la clé secrète `SUPABASE_SERVICE_ROLE_KEY`, qui ignore la RLS : elle ne quitte
jamais le serveur. Chaque fonction lève DatabaseError en cas d'échec.
"""
import asyncio
import os
from typing import Any

import httpx


class DatabaseError(Exception):
    pass


def _config() -> tuple[str, dict[str, str]]:
    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        raise DatabaseError("SUPABASE_URL ou SUPABASE_SERVICE_ROLE_KEY manquante côté serveur")
    # Les clés secrètes « sb_secret_… » se passent dans l'en-tête apikey ; l'ancienne clé
    # service_role (un JWT) est aussi acceptée en Bearer.
    headers = {"apikey": key, "Content-Type": "application/json"}
    if key.startswith("eyJ"):
        headers["Authorization"] = f"Bearer {key}"
    return f"{url}/rest/v1", headers


_partage: tuple[asyncio.AbstractEventLoop, httpx.AsyncClient] | None = None


def _client() -> httpx.AsyncClient:
    """Une connexion gardée ouverte entre les requêtes (sinon chaque lecture refait la poignée de
    main TLS). Liée à la boucle asyncio en cours : Vercel peut en changer d'une invocation à l'autre."""
    global _partage
    boucle = asyncio.get_running_loop()
    if _partage is None or _partage[0] is not boucle or _partage[1].is_closed:
        _partage = (boucle, httpx.AsyncClient(timeout=20.0))
    return _partage[1]


async def _call(method: str, table: str, *, params: dict | None = None, json: Any = None,
                prefer: str | None = None) -> list[dict[str, Any]]:
    base, headers = _config()
    if prefer:
        headers["Prefer"] = prefer
    try:
        response = await _client().request(method, f"{base}/{table}", params=params, json=json, headers=headers)
    except httpx.HTTPError as e:
        raise DatabaseError(f"Base injoignable : {type(e).__name__}")
    if response.status_code >= 400:
        raise DatabaseError(f"Base {response.status_code} sur {table} : {response.text[:300]}")
    return response.json() if response.content else []


async def select(table: str, **filters: str) -> list[dict[str, Any]]:
    """select("bank_accounts", bank="eq.CIC") ; les valeurs suivent la syntaxe PostgREST."""
    return await _call("GET", table, params={"select": "*", **filters})


PAGE = 1000   # Supabase ne renvoie jamais plus de 1 000 lignes par lecture, quelle que soit la « limit »


async def select_tout(table: str, **filters: str) -> list[dict[str, Any]]:
    """Comme select, mais lit toutes les lignes, par pages de 1 000 (ordre stable : `order`, puis id)."""
    filtres = {"select": "*", **filters}
    filtres["order"] = f"{filtres['order']},id.asc" if "order" in filtres else "id.asc"
    filtres.pop("limit", None)
    lignes: list[dict[str, Any]] = []
    while True:
        page = await _call("GET", table, params={**filtres, "limit": str(PAGE), "offset": str(len(lignes))})
        lignes += page
        if len(page) < PAGE:
            return lignes


async def insert(table: str, rows: dict | list[dict]) -> list[dict[str, Any]]:
    return await _call("POST", table, json=rows, prefer="return=representation")


async def upsert(table: str, rows: dict | list[dict], on_conflict: str | None = None) -> list[dict[str, Any]]:
    """Insère, ou remplace la ligne qui a la même clé primaire (ou la même valeur de `on_conflict`)."""
    return await _call("POST", table, params={"on_conflict": on_conflict} if on_conflict else None, json=rows,
                       prefer="resolution=merge-duplicates,return=representation")


async def update(table: str, values: dict, **filters: str) -> list[dict[str, Any]]:
    return await _call("PATCH", table, params=filters, json=values, prefer="return=representation")


async def delete(table: str, **filters: str) -> list[dict[str, Any]]:
    if not filters:
        raise DatabaseError(f"Suppression sans filtre refusée sur {table}")
    return await _call("DELETE", table, params=filters, prefer="return=representation")
