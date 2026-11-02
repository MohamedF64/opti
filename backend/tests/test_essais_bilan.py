"""Essais gratuits, alertes d'abonnements et bilan de cycle : règles de docs/regles-de-calcul.md § 11."""
import sys
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

import abonnements as a  # noqa: E402
import budget as b  # noqa: E402
import notifications as n  # noqa: E402
import stats  # noqa: E402

PARIS = ZoneInfo("Europe/Paris")
TOUTES = set(n.TYPES)
NETFLIX = {"id": "nf", "name": "Netflix", "merchant_key": "netflix", "amount": 13.49, "frequency": "mensuel",
           "status": "active", "montant_reference": 13.49, "is_trial": True, "trial_end_date": "2026-11-15"}


def prelevement(jour, montant=13.49):
    return {"id": f"nf-{jour}", "date": jour, "amount": -montant, "merchant": "NETFLIX.COM", "description": "NETFLIX.COM",
            "category": "Abonnement", "is_internal": False, "status": "booked"}


def test_essai_en_cours_puis_termine_sans_prelevement():
    e = a.etat(NETFLIX, [], date(2026, 11, 1))
    assert (e.statut, e.essai_jusqu_au, e.prochain_prelevement) == ("essai", date(2026, 11, 15), date(2026, 11, 15))
    assert a.etat(NETFLIX, [], date(2026, 11, 16)).statut == "essai_termine"


def test_un_prelevement_transforme_l_essai_en_abonnement():
    e = a.etat(NETFLIX, [prelevement("2026-11-14")], date(2026, 11, 16))     # 1 jour avant la fin : compte
    assert (e.statut, e.essai_jusqu_au, e.dernier_prelevement) == ("actif", None, date(2026, 11, 14))
    vieux = a.etat(NETFLIX, [prelevement("2026-05-03")], date(2026, 11, 1))   # ancien abonnement Netflix : ignoré
    assert vieux.statut == "essai"


def test_essai_finissant_dans_le_cycle_compte_dans_les_abonnements_a_venir():
    essai = b.Abonnement("Netflix", 13.49, "mensuel", None, premier_prelevement=date(2026, 11, 15))
    assert b.abonnements_a_venir([essai], date(2026, 10, 26), date(2026, 11, 24)) == [
        {"nom": "Netflix", "montant": 13.49, "date": "2026-11-15"}]
    assert b.abonnements_a_venir([essai], date(2026, 11, 25), date(2026, 12, 24)) == []   # cycle suivant : non


def test_rappels_d_essai_a_j3_et_j1_avec_le_nom_sans_montant():
    def rappels(jour, heure=12):
        e = a.etat(NETFLIX, [], jour)
        return n.a_envoyer(datetime(jour.year, jour.month, jour.day, heure, tzinfo=PARIS), [], None, None, [],
                           set(), TOUTES, abonnements=[e])
    [j3] = rappels(date(2026, 11, 12))
    assert j3.texte == "Ton essai Netflix se termine dans 3 jours. Ouvre Opti pour le garder ou le résilier."
    assert "13" not in j3.texte and j3.ecran == "abonnements"
    [j1] = rappels(date(2026, 11, 14))
    assert "se termine demain" in j1.texte
    assert rappels(date(2026, 11, 13)) == [] and rappels(date(2026, 11, 12), heure=17) == []


def test_alertes_changement_de_prix_et_nouvel_abonnement():
    prixtel = {"id": "px", "name": "Prixtel", "merchant_key": "prixtel", "amount": 12.61, "frequency": "mensuel",
               "status": "active", "montant_reference": 12.61}
    ops = [{"id": f"p{i}", "date": d, "amount": -m, "merchant": "PRIXTEL", "description": "PRIXTEL",
            "category": "Abonnement", "is_internal": False, "status": "booked"}
           for i, (d, m) in enumerate([("2026-08-05", 14.98), ("2026-09-04", 16.98), ("2026-10-05", 14.98)])]
    e = a.etat(prixtel, ops, date(2026, 11, 1))
    notifs = n.a_envoyer(datetime(2026, 11, 1, 17, tzinfo=PARIS), [], None, None, [], set(), TOUTES,
                         abonnements=[e], detectes=["deezer"])
    assert [x.texte for x in notifs] == [
        "Un abonnement a changé de prix (+24 %). Ouvre Opti pour vérifier.",
        "Un nouvel abonnement a été détecté. Ouvre Opti pour confirmer."]
    assert n.a_envoyer(datetime(2026, 11, 1, 17, tzinfo=PARIS), [], None, None, [], set(), TOUTES - {"abonnement"},
                       abonnements=[e], detectes=["deezer"]) == []


def test_notification_de_paie_avec_le_bilan_du_cycle():
    paie = {"id": "p1", "date": "2026-10-26", "amount": 1850.00}
    [notif] = n.a_envoyer(datetime(2026, 10, 26, 12, tzinfo=PARIS), [], None, None, [paie], set(), TOUTES,
                          bilan=(20, 31))
    assert notif.texte == ("Ta paie est arrivée. Cycle précédent : 20 jours sur 31 sous ta limite (65 %). "
                           "Ouvre Opti pour ton bilan.")


def test_carte_bilan_pendant_3_jours_apres_la_paie():
    def op(jour, montant, categorie="Alimentation"):
        return {"date": jour, "amount": montant, "category": categorie}
    ops = [op("2026-08-25", 880.00, "Salaire"), op("2026-09-25", 1040.00, "Salaire"), op("2026-10-26", 1850.00, "Salaire"),
           op("2026-09-01", -279.14), op("2026-09-02", -687.83, "Shopping"),          # cycle d'août : 966,97 €
           op("2026-10-01", -434.93), op("2026-10-02", -589.00, "Shopping")]          # cycle de septembre : 1 023,93 €

    def carte(jour):
        return stats.bilan(stats.calculer("precedent", jour, ops, []), stats.calculer("6", jour, ops, []), jour)
    c = carte(date(2026, 10, 28))
    assert (c["debut"], c["fin"], c["depense"], c["reste"]) == (date(2026, 9, 25), date(2026, 10, 25), 1023.93, 16.07)
    assert (c["moyenne"], c["ecart_moyenne_pourcent"]) == (995.45, 3)
    assert c["categorie"] == {"nom": "Alimentation", "pourcent": 56, "ecart": 155.79}
    assert carte(date(2026, 10, 29)) is None                                           # 3 jours après : plus de carte


def test_alerte_prelevement_au_dessus_du_maximum_une_seule_fois():
    prixtel = {"id": "px", "name": "Prixtel", "merchant_key": "prixtel", "amount": 15.65, "frequency": "mensuel",
               "status": "active", "montant_reference": 15.65, "montant_max": 22.98}
    ops = [{"id": f"p{i}", "date": d, "amount": -m, "merchant": "PRIXTEL", "description": "PRIXTEL",
            "category": "Abonnement", "is_internal": False, "status": "booked"}
           for i, (d, m) in enumerate([("2026-08-05", 14.98), ("2026-09-04", 16.98), ("2026-10-05", 14.98),
                                       ("2026-11-04", 24.98)])]
    e = a.etat(prixtel, ops, date(2026, 11, 4))
    quand = datetime(2026, 11, 4, 17, tzinfo=PARIS)
    notifs = [x for x in n.a_envoyer(quand, [], None, None, [], set(), TOUTES, abonnements=[e]) if x.cle.startswith("dep")]
    assert [(x.cle, x.texte) for x in notifs] == [
        ("depassement:p3", "Prixtel a prélevé plus que ton maximum. Ouvre Opti pour vérifier.")]
    assert not [x for x in n.a_envoyer(quand, [], None, None, [], {"depassement:p3"}, TOUTES, abonnements=[e])
                if x.cle.startswith("dep")]
