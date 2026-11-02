"""Abonnements : tests sur les cas réels de docs/regles-de-calcul.md § 7."""
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

import abonnements as a  # noqa: E402

AUJOURDHUI = date(2026, 10, 31)


def op(jour, montant, marchand, categorie="Abonnement", **autres):
    return {"id": f"{marchand}-{jour}", "date": jour, "amount": -montant, "merchant": marchand,
            "description": marchand, "category": categorie, "is_internal": False, "status": "booked", **autres}


def ab(nom, cle, montant, **autres):
    return {"id": cle, "name": nom, "merchant_key": cle, "amount": montant, "frequency": "mensuel",
            "status": "active", "montant_reference": montant, **autres}


PRIXTEL = [op("2026-05-06", 4.99, "PRIXTEL"), op("2026-05-22", 10.00, "Prixtel"), op("2026-06-04", 14.98, "Prixtel"),
           op("2026-07-06", 16.98, "Prixtel"), op("2026-08-05", 14.98, "PRIXTEL"), op("2026-09-04", 16.98, "PRIXTEL"),
           op("2026-10-05", 14.98, "PRIXTEL")]
IMAGINE_R = [op("2026-04-07", 42.70, "IMAGINE R"), op("2026-05-06", 42.70, "IMAGINE R"),
             op("2026-06-05", 42.70, "Imagine R"), op("2026-10-07", 51.70, "Imagine R - COMUTITRES SAS")]
ANTHROPIC = [op("2026-07-08", 21.60, "Anthropic"), op("2026-08-07", 21.60, "Anthropic* Claude Sub"),
             op("2026-09-07", 21.60, "Anthropic* Claude Sub"), op("2026-10-07", 21.60, "Anthropic* Claude Sub")]


def test_prix_variable_prixtel_moyenne_des_3_derniers_et_alerte_de_prix():
    e = a.etat(ab("Forfait mobile Prixtel", "prixtel", 12.61), PRIXTEL, AUJOURDHUI)
    assert (e.montant, e.variable, e.montant_min, e.montant_max) == (15.65, True, 14.98, 16.98)
    assert e.changement_prix == {"ancien": 12.61, "nouveau": 15.65, "depuis": date(2026, 10, 5)}
    assert (e.statut, e.prochain_prelevement) == ("actif", date(2026, 11, 5))


def test_prix_fixe_anthropic_deux_libelles():
    e = a.etat(ab("Anthropic (Claude)", "anthropic", 21.60), ANTHROPIC, AUJOURDHUI)
    assert (e.montant, e.variable, e.changement_prix, len(e.historique)) == (21.60, False, None, 4)


def test_imagine_r_montant_manuel_et_pause_d_ete():
    imagine = ab("Imagine R", "imagine r", 43.70, montant_manuel=True, mois_pause=[7, 8, 9], libelles=["comutitres"])
    e = a.etat(imagine, IMAGINE_R, AUJOURDHUI)
    assert (e.montant, e.changement_prix, e.prochain_prelevement) == (43.70, None, date(2026, 11, 7))
    # En août, le prélèvement de juin ne rend pas l'abonnement « à vérifier » : le suivant est en octobre.
    ete = a.etat(imagine, IMAGINE_R[:3], date(2026, 8, 20))
    assert (ete.statut, ete.prochain_prelevement) == ("actif", date(2026, 10, 5))


def test_a_verifier_apres_un_intervalle_et_demi():
    orange = ab("Orange", "orange", 15.99)
    vus = [op("2026-05-04", 15.99, "ORANGE SA"), op("2026-06-04", 15.99, "Orange")]
    assert a.etat(orange, vus, date(2026, 7, 15)).statut == "actif"         # attendu le 04/07, 11 jours de retard
    assert a.etat(orange, vus, date(2026, 7, 25)).statut == "a_verifier"    # plus de 15 jours de retard
    assert a.etat({**orange, "status": "cancelled"}, vus, AUJOURDHUI).statut == "resilie"


def test_verdict_selon_l_usage_et_economie():
    prime = [op("2026-09-03", 6.99, "Amazon Prime Fr"), op("2026-10-03", 6.99, "Amazon Prime Fr")]
    assert a.etat(ab("Prime", "amazon prime", 6.99, usage="souvent"), prime, AUJOURDHUI).verdict == "rentable"
    assert a.etat(ab("Prime", "amazon prime", 6.99, usage="parfois"), prime, AUJOURDHUI).verdict == "a_revoir"
    coupe = a.etat(ab("Prime", "amazon prime", 6.99, usage="jamais"), prime, AUJOURDHUI)
    assert (coupe.verdict, coupe.economie_par_an) == ("a_couper", 83.88)
    assert a.etat(ab("Prime", "amazon prime", 6.99), prime, AUJOURDHUI).verdict == "a_renseigner"
    promo = [op("2026-08-26", 0.99, "Amazon Prime Fr"), *prime]
    assert (a.etat(ab("Prime", "amazon prime", 6.99), promo, AUJOURDHUI).variable) is False


def test_prochain_prelevement_saute_les_mois_de_pause():
    assert a.prochain_prelevement(date(2026, 6, 5), 30, [7, 8, 9]) == date(2026, 10, 5)
    assert a.prochain_prelevement(date(2026, 1, 31), 30) == date(2026, 2, 28)
    assert a.prochain_prelevement(date(2026, 3, 1), 365) == date(2027, 3, 1)


# ── Détection ────────────────────────────────────────────────────────────────

def test_detection_trouve_un_vrai_abonnement_et_ignore_le_quotidien():
    operations = [
        *[op(j, 9.99, "NETFLIX.COM") for j in ("2026-08-12", "2026-09-12", "2026-10-12")],
        *[op(j, m, "GRAIN OR BOULAN", "Alimentation") for j, m in (("2026-08-10", 5.3), ("2026-09-10", 5.3), ("2026-10-10", 5.3))],
        *[op(j, 12.99, "MICROSOFT*XBOX G") for j in ("2026-08-11", "2026-09-11", "2026-10-11")],
        *ANTHROPIC,
    ]
    candidats = a.detecter(operations, [ab("Anthropic", "anthropic", 21.60)], {"microsoft"}, AUJOURDHUI)
    assert [(c["cle"], c["montant"], c["frequence"]) for c in candidats] == [("netflix", 9.99, "mensuel")]


def test_detection_ecarte_irregulier_ancien_ou_montants_trop_differents():
    irregulier = [op(j, 10, "GYM") for j in ("2026-08-01", "2026-08-20", "2026-10-01")]
    ancien = [op(j, 15.99, "ORANGE SA") for j in ("2026-04-04", "2026-05-04", "2026-06-04")]
    variable = [op(j, m, "SPOTIFY") for j, m in (("2026-08-01", 5), ("2026-09-01", 10.99), ("2026-10-01", 10.99))]
    for ops in (irregulier, ancien, variable):
        assert a.detecter(ops, [], set(), AUJOURDHUI) == []


def test_cle_de_detection():
    assert a.cle_detection({"merchant": "Anthropic* Claude Sub"}) == "anthropic"
    assert a.cle_detection({"merchant": "SC-EASY CASH (Sarcelles)"}) == "easy"
    assert a.cle_detection({"merchant": "PAIEMENT CB 123"}) is None


# ── Prix maximum et total estimé (§ 7, points 8 et 9, validés le 02/11/2026) ──

def test_prix_maximum_prixtel_reserve_dans_le_budget():
    e = a.etat(ab("Forfait mobile Prixtel", "prixtel", 15.65, montant_max=22.98), PRIXTEL, AUJOURDHUI)
    assert (e.montant, e.prix_maximum, e.montant_budget) == (15.65, 22.98, 22.98)
    assert e.depassement is None
    sans = a.etat(ab("Anthropic", "anthropic", 21.60), ANTHROPIC, AUJOURDHUI)
    assert (sans.prix_maximum, sans.montant_budget) == (None, 21.60)


def test_depassement_du_maximum_puis_vu():
    ops = PRIXTEL + [op("2026-10-30", 24.98, "PRIXTEL")]
    e = a.etat(ab("Forfait mobile Prixtel", "prixtel", 15.65, montant_max=22.98), ops, AUJOURDHUI)
    assert e.depassement == {"id": "PRIXTEL-2026-10-30", "date": date(2026, 10, 30), "montant": 24.98}
    vu = a.etat(ab("Forfait mobile Prixtel", "prixtel", 15.65, montant_max=22.98,
                   depassement_vu="PRIXTEL-2026-10-30"), ops, AUJOURDHUI)
    assert vu.depassement is None


def test_total_estime_et_fourchette_cas_reel():
    # 55,88 + 43,70 + 21,60 + 15,65 + 6,99 + 4,99 = 148,81 ; Prixtel de 14,98 à 22,98 → 148,14 à 156,14.
    fixes = [a.etat(ab(n, n.lower(), m, montant_manuel=True), [], AUJOURDHUI)
             for n, m in (("Direct", 55.88), ("Imagine", 43.70), ("Anthropic", 21.60), ("Prime", 6.99), ("Google", 4.99))]
    prixtel = a.etat(ab("Prixtel", "prixtel", 15.65, montant_max=22.98), PRIXTEL, AUJOURDHUI)
    suivis = fixes + [prixtel]
    assert round(sum(e.par_mois for e in suivis), 2) == 148.81
    assert a.fourchette(suivis) == {"min": 148.14, "max": 156.14}
    sans_max = a.etat(ab("Prixtel", "prixtel", 15.65), PRIXTEL, AUJOURDHUI)
    assert a.fourchette(fixes + [sans_max]) == {"min": 148.14, "max": 150.14}   # plus grand des 3 derniers : 16,98
    assert a.fourchette(fixes) is None
