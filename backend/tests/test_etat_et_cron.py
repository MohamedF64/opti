"""Tests du cron quotidien et de l'état des comptes."""
import asyncio
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

from fastapi.testclient import TestClient

os.environ.setdefault("SUPABASE_URL", "https://exemple.supabase.co")
os.environ.setdefault("OWNER_USER_ID", "11111111-2222-4333-8444-555555555555")
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

import index  # noqa: E402
import synchro  # noqa: E402

client = TestClient(index.app)
MAINTENANT = datetime(2027, 4, 22, 12, 0, tzinfo=timezone.utc)


def test_cron_refuse_sans_le_bon_secret(monkeypatch):
    monkeypatch.setenv("CRON_SECRET", "s3cr3t-assez-long-pour-le-test")
    assert client.get("/banque/synchro/cron").status_code == 401
    assert client.get("/banque/synchro/cron", headers={"Authorization": "Bearer faux"}).status_code == 401


def test_cron_refuse_si_secret_absent_cote_serveur(monkeypatch):
    monkeypatch.delenv("CRON_SECRET", raising=False)
    assert client.get("/banque/synchro/cron", headers={"Authorization": "Bearer "}).status_code == 401


def test_cron_accepte_et_ne_renvoie_que_des_compteurs(monkeypatch):
    monkeypatch.setenv("CRON_SECRET", "s3cr3t-assez-long-pour-le-test")

    async def fausse_synchro(**kwargs):
        return [{"compte": "CIC · Courant", "solde": 2021.13, "nouvelles": 3, "categories": {"Alimentation": 3}},
                {"compte": "Revolut · Revolut", "erreur": "ASPSP_TIMEOUT"}]
    async def fausses_notifications():
        return {"a_envoyer": 1, "envoyees": 1, "telephones": 1}
    monkeypatch.setattr(synchro, "synchroniser", fausse_synchro)
    monkeypatch.setattr(index.notifications, "apres_synchro", fausses_notifications)
    monkeypatch.setattr(index.notifications, "heure_de_synchro", lambda: True)
    monkeypatch.setattr(index.veille, "jour_de_veille", lambda: False)   # pages de prix : seulement le 1er à 8 h

    async def faux_bons_plans():
        return {"flux_lus": 8, "gardes": 2}
    monkeypatch.setattr(index.bons_plans, "collecter", faux_bons_plans)
    r = client.get("/banque/synchro/cron", headers={"Authorization": "Bearer s3cr3t-assez-long-pour-le-test"})
    assert r.status_code == 200
    assert r.json() == {"synchro": True, "notifications": {"a_envoyer": 1, "envoyees": 1, "telephones": 1},
                        "pages": None, "bons_plans": {"flux_lus": 8, "gardes": 2},
                        "comptes": [{"compte": "CIC · Courant", "ok": True, "nouvelles": 3},
                                    {"compte": "Revolut · Revolut", "ok": False, "nouvelles": 0}]}


def test_cron_hors_des_heures_de_synchro_ne_fait_rien(monkeypatch):
    monkeypatch.setenv("CRON_SECRET", "s3cr3t-assez-long-pour-le-test")
    monkeypatch.setattr(index.notifications, "heure_de_synchro", lambda: False)
    r = client.get("/banque/synchro/cron", headers={"Authorization": "Bearer s3cr3t-assez-long-pour-le-test"})
    assert r.json() == {"synchro": False}


def test_etat_reserve_au_proprietaire():
    assert client.get("/banque/etat").status_code == 401


def test_etat_signale_le_renouvellement_a_moins_de_7_jours():
    connexions = [
        {"id": "c1", "aspsp_name": "CIC", "status": "active", "valid_until": "2027-04-27T19:49:39+00:00",
         "last_sync_status": "ok", "last_sync_at": "2027-04-22T05:10:00+00:00", "last_error": None},
        {"id": "c2", "aspsp_name": "Revolut", "status": "expired", "valid_until": "2027-04-27T19:51:22+00:00",
         "last_sync_status": "expired", "last_sync_at": None, "last_error": "EXPIRED_SESSION"},
    ]
    comptes = [{"id": "a1", "connection_id": "c1", "account_label": "C/C", "account_type": "checking", "balance": 2021.13},
               {"id": "a2", "connection_id": "c2", "account_label": "Revolut", "account_type": "checking", "balance": 178.83}]
    etat = synchro.resumer_etat(connexions, comptes, MAINTENANT)
    cic, revolut = etat["banques"]
    assert (cic["statut"], cic["jours_restants"], cic["a_renouveler"]) == ("ok", 5, True)
    assert (revolut["statut"], revolut["a_renouveler"]) == ("expiree", True)
    assert etat["solde_total"] == 2199.96


def test_consentement_lointain_pas_a_renouveler():
    c = [{"id": "c1", "aspsp_name": "CIC", "status": "active", "valid_until": "2027-04-27T19:49:39+00:00"}]
    etat = synchro.resumer_etat(c, [], datetime(2026, 10, 29, tzinfo=timezone.utc))
    assert (etat["banques"][0]["jours_restants"], etat["banques"][0]["a_renouveler"]) == (180, False)


def test_budget_reserve_au_proprietaire():
    assert client.get("/budget/aujourdhui").status_code == 401


def test_jours_restants_en_jours_du_calendrier():
    # Accès renouvelé le 31/10 à 20 h 14 (Paris) jusqu'au 29/04 à 20 h 13 : 180 jours, pas 179.
    assert synchro.jours_restants("2027-04-29T18:13:14+00:00", datetime(2026, 10, 31, 19, 25, tzinfo=timezone.utc)) == 180
    # Tard le soir (23 h 30 à Paris), on compte toujours depuis le 31/10.
    assert synchro.jours_restants("2027-04-27T18:50:20+00:00", datetime(2026, 10, 31, 22, 30, tzinfo=timezone.utc)) == 178


def test_select_tout_lit_toutes_les_pages(monkeypatch):
    import db
    lignes = [{"id": i} for i in range(2345)]
    appels = []

    async def faux_call(methode, table, params=None, **_):
        appels.append(params)
        debut = int(params["offset"])
        return lignes[debut:debut + int(params["limit"])]

    monkeypatch.setattr(db, "_call", faux_call)
    resultat = asyncio.run(db.select_tout("transactions", select="id", order="date.desc", limit="10"))
    assert len(resultat) == 2345 and len(appels) == 3
    assert appels[0]["order"] == "date.desc,id.asc" and appels[0]["limit"] == "1000"
