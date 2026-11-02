"""Notifications : règles de docs/regles-de-calcul.md § 10."""
import os
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from fastapi.testclient import TestClient

os.environ.setdefault("SUPABASE_URL", "https://exemple.supabase.co")
os.environ.setdefault("OWNER_USER_ID", "11111111-2222-4333-8444-555555555555")
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

import index  # noqa: E402
import notifications as n  # noqa: E402

PARIS = ZoneInfo("Europe/Paris")
TOUTES = set(n.TYPES)
CIC = {"aspsp_name": "CIC", "status": "active", "valid_until": "2027-04-29T10:00:00+00:00",
       "last_success_at": "2026-11-01T11:00:00+00:00"}


def a(jour, heure, connexions=(), depense=None, limite=None, salaires=(), deja=frozenset(), actives=TOUTES):
    return n.a_envoyer(datetime(*jour, heure, 0, tzinfo=PARIS), list(connexions), depense, limite,
                       list(salaires), set(deja), set(actives))


def test_limite_depassee_texte_neutre_avec_pourcentage_une_fois_par_jour():
    [notif] = a((2026, 11, 1), 17, depense=72.40, limite=55.27)
    assert notif.texte == "Limite du jour dépassée (131 %). Ouvre Opti pour voir le détail."
    assert "72" not in notif.texte and notif.cle == "limite:2026-11-01" and notif.ecran == "accueil"
    assert a((2026, 11, 1), 21, depense=80.00, limite=55.27, deja={"limite:2026-11-01"}) == []
    assert a((2026, 11, 1), 17, depense=55.27, limite=55.27) == []      # pile la limite : pas dépassée


def test_renouvellement_a_14_7_et_1_jour_a_12_h_seulement():
    for jour, dans in (((2027, 4, 15), "dans 14 jours"), ((2027, 4, 22), "dans 7 jours"), ((2027, 4, 28), "demain")):
        cic = {**CIC, "last_success_at": datetime(*jour, 9, tzinfo=PARIS).isoformat()}
        [notif] = a(jour, 12, [cic])
        assert notif.texte == f"Accès CIC : expire {dans}. Renouvelle-le dans Opti › Réglages."
        assert notif.ecran == "reglages"
        assert a(jour, 17, [cic]) == []                                  # pas à 17 h
    cic = {**CIC, "last_success_at": datetime(2027, 4, 20, 9, tzinfo=PARIS).isoformat()}
    assert a((2027, 4, 20), 12, [cic]) == []                             # J-9 : pas un palier


def test_synchro_en_panne_depuis_plus_de_24_h_et_acces_expire():
    vieux = {**CIC, "last_success_at": datetime(2026, 10, 31, 8, tzinfo=PARIS).isoformat()}
    [notif] = a((2026, 11, 1), 12, [vieux])
    assert notif.texte == "CIC ne se synchronise plus depuis hier. Ouvre Opti pour vérifier."
    recent = {**CIC, "last_success_at": datetime(2026, 10, 31, 17, tzinfo=PARIS).isoformat()}
    assert a((2026, 11, 1), 12, [recent]) == []                          # 19 h : pas encore 24 h
    [expire] = a((2026, 11, 1), 8, [{**CIC, "status": "expired"}])
    assert expire.texte == "Accès CIC expiré. Renouvelle-le dans Opti › Réglages."


def test_paie_recue_une_fois_et_seulement_recente():
    paie = {"id": "p1", "date": "2026-10-26", "amount": 1850.00}
    [notif] = a((2026, 10, 26), 12, salaires=[paie])
    assert notif.texte == "Ta paie est arrivée. Ouvre Opti pour voir ton budget du cycle."
    assert "2005" not in notif.texte
    assert a((2026, 10, 26), 17, salaires=[paie], deja={"paie:p1"}) == []
    assert a((2026, 10, 30), 12, salaires=[paie]) == []                   # 4 jours après : trop vieille


def test_types_coupes_dans_les_reglages():
    assert a((2026, 11, 1), 17, depense=72.40, limite=55.27, actives=TOUTES - {"limite"}) == []


def test_synchro_seulement_a_8_12_17_et_21_h_de_paris():
    assert [h for h in range(24) if n.heure_de_synchro(datetime(2026, 11, 1, h, tzinfo=PARIS))] == [8, 12, 17, 21]
    # En été (UTC+2), le cron de 6 h UTC tombe à 8 h de Paris.
    assert n.heure_de_synchro(datetime(2027, 7, 1, 6, tzinfo=ZoneInfo("UTC")))


def test_routes_notifications_exigent_la_session_et_le_cron_son_secret():
    client = TestClient(index.app)
    assert client.post("/notifications/appareil", json={"jeton": "x" * 20}).status_code == 401
    assert client.get("/notifications/reglages").status_code == 401
    assert client.post("/notifications/test").status_code == 401
    assert client.get("/bilan").status_code == 401
    assert client.get("/banque/synchro/cron", headers={"Authorization": "Bearer faux"}).status_code == 401
