"""Tests de la connexion des banques (Enable Banking et base simulés, aucun appel réseau)."""
import asyncio
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

import banque as bq  # noqa: E402

CIC_COURANT = {"id": "a1", "bank": "CIC", "account_label": "C/C Personnel Parcours", "account_type": "checking",
               "iban_last4": None, "eb_account_uid": None}
CIC_LIVRET = {"id": "a2", "bank": "CIC", "account_label": "Livret A SUP", "account_type": "savings",
              "iban_last4": "7504", "eb_account_uid": None}


# ── Rattachement des comptes ──────────────────────────────────────────────────

def test_compte_courant_rattache_par_type():
    compte = {"uid": "eb-1", "cash_account_type": "CACC", "account_id": {"iban": "FR76 1234 5678 9012"}}
    assert bq.choisir_compte_existant(compte, [CIC_COURANT, CIC_LIVRET])["id"] == "a1"


def test_livret_rattache_par_iban():
    compte = {"uid": "eb-2", "cash_account_type": "SVGS", "account_id": {"iban": "FR7600000000007504"}}
    assert bq.choisir_compte_existant(compte, [CIC_COURANT, CIC_LIVRET])["id"] == "a2"


def test_iban_contradictoire_cree_un_nouveau_compte():
    compte = {"uid": "eb-3", "cash_account_type": "SVGS", "account_id": {"iban": "FR7600000000009999"}}
    assert bq.choisir_compte_existant(compte, [CIC_COURANT, CIC_LIVRET]) is None


def test_renouvellement_retrouve_le_meme_compte():
    deja_relie = {**CIC_COURANT, "eb_account_uid": "eb-1"}
    assert bq.choisir_compte_existant({"uid": "eb-1"}, [CIC_LIVRET, deja_relie])["id"] == "a1"


def test_second_compte_courant_non_rattache_au_premier():
    deja_relie = {**CIC_COURANT, "eb_account_uid": "eb-1"}
    compte = {"uid": "eb-autre", "cash_account_type": "CACC", "account_id": {}}
    assert bq.choisir_compte_existant(compte, [deja_relie]) is None


def test_reserve_revolut_ne_prend_pas_l_historique_du_compte_principal():
    revolut = {"id": "r1", "bank": "Revolut", "account_label": "Revolut", "account_type": "checking",
               "iban_last4": None, "eb_account_uid": None}
    reserve = {"uid": "eb-poche", "cash_account_type": "CACC", "name": "Économies", "account_id": {}}
    principal = {"uid": "eb-princ", "cash_account_type": "CACC", "name": "Main", "account_id": {}}
    # Même si la réserve arrive en premier, elle n'est pas rattachée au compte principal.
    assert bq.choisir_compte_existant(reserve, [revolut]) is None
    assert bq.choisir_compte_existant(principal, [revolut])["id"] == "r1"
    assert bq.type_de_compte(reserve) == "savings"


def test_banque_inconnue_refusee():
    with pytest.raises(bq.ConnexionError):
        bq.nom_banque("LCL")
    assert bq.nom_banque(" revolut ") == "Revolut"


# ── Parcours de retour ────────────────────────────────────────────────────────

class FausseBase:
    def __init__(self, demandes):
        self.demandes = demandes
        self.tables = {"bank_accounts": [dict(CIC_COURANT), dict(CIC_LIVRET)], "bank_connections": []}

    async def update(self, table, values, **filters):
        if table == "bank_auth_requests":
            return self.demandes  # la vraie requête filtre state, used_at et expires_at
        if table == "bank_accounts":
            ligne = next(r for r in self.tables[table] if f"eq.{r['id']}" == filters["id"])
            ligne.update(values)
            return [ligne]
        return []

    async def insert(self, table, row):
        row = {"id": f"nouveau-{len(self.tables[table])}", **row}
        self.tables[table].append(row)
        return [row]

    async def select(self, table, **filters):
        return [dict(r) for r in self.tables[table]]


def _brancher(monkeypatch, base, session):
    monkeypatch.setattr(bq, "db", base)

    async def fausse_requete(method, path, **kwargs):
        assert (method, path, kwargs["json"]) == ("POST", "/sessions", {"code": "le-code"})
        return session
    monkeypatch.setattr(bq.eb, "request", fausse_requete)


def test_retour_rattache_et_cree(monkeypatch):
    base = FausseBase([{"state": "s", "aspsp_name": "CIC"}])
    _brancher(monkeypatch, base, {
        "session_id": "sess-1", "access": {"valid_until": "2027-04-27T00:00:00+00:00"},
        "accounts": [
            {"uid": "eb-1", "cash_account_type": "CACC", "account_id": {"iban": "FR7611112222333344445555"}},
            {"uid": "eb-9", "cash_account_type": "SVGS", "name": "Livret Jeune", "account_id": {"iban": "FR760000000000001234"}},
        ],
    })
    banque, comptes = asyncio.run(bq.terminer_connexion("le-code", "s"))
    assert banque == "CIC"
    assert comptes == ["C/C Personnel Parcours", "Livret Jeune (nouveau)"]
    courant = base.tables["bank_accounts"][0]
    assert courant["eb_account_uid"] == "eb-1" and courant["iban_last4"] == "5555"
    assert base.tables["bank_connections"][0]["session_id"] == "sess-1"


def test_retour_avec_state_invalide_refuse(monkeypatch):
    _brancher(monkeypatch, FausseBase([]), {})
    with pytest.raises(bq.ConnexionError):
        asyncio.run(bq.terminer_connexion("le-code", "state-rejoue"))
