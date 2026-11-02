"""Tests de la synchro, sur des exemples tirés des vraies opérations renvoyées par CIC et Revolut."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

import synchro as s  # noqa: E402

CIC = {"id": "cic", "bank": "CIC", "account_type": "checking"}
REVOLUT = {"id": "rev", "bank": "Revolut", "account_type": "checking"}
ECONOMIES = {"id": "eco", "bank": "Revolut", "account_type": "savings"}
HISTORIQUE = s.historique_par_marchand([
    {"description": "GRAIN OR BOULAN (Rueil-Malmais)", "merchant": None, "category": "Alimentation"},
    {"description": "GRAIN OR BOULAN (Rueil-Malmais)", "merchant": None, "category": "Alimentation"},
    {"description": "TRANSFERT VERS REVOLUT", "merchant": None, "category": "Épargne", "is_internal": True},
])


def tx(montant, sens, libelles, statut="BOOK", ref="r1", **autres):
    return {"transaction_amount": {"amount": montant, "currency": "EUR"}, "credit_debit_indicator": sens,
            "status": statut, "entry_reference": ref, "remittance_information": libelles,
            "booking_date": "2026-10-29", "transaction_date": autres.pop("transaction_date", None), **autres}


def test_paiement_cic_comptabilise_nettoye_et_classe_par_l_historique():
    l = s.vers_ligne(CIC, tx("5.30", "DBIT", ["PAIEMENT PSC 2810 RUEIL-MALMAIS", "GRAIN OR BOULAN  CARTE 0051"],
                             transaction_date="2026-10-28"), HISTORIQUE)
    assert l["description"] == "GRAIN OR BOULAN (Rueil-Malmais)"
    assert (l["amount"], l["category"], l["is_internal"]) == (-5.30, "Alimentation", False)
    assert l["date"] == "2026-10-28"  # jour de l'achat, pas de la comptabilisation


def test_paiement_cic_en_attente_sans_reference():
    l = s.vers_ligne(CIC, tx("1.99", "DBIT", ["PAIEMENT CB G 20 RUEIL-MALMAISON"], statut="PDNG", ref=None,
                             booking_date=None, transaction_date="2026-10-29"), HISTORIQUE)
    assert (l["status"], l["entry_reference"], l["category"]) == ("pending", None, "Alimentation")


def test_recharge_revolut_depuis_la_carte_cic_est_de_l_epargne():
    cote_revolut = s.vers_ligne(REVOLUT, tx("150.00", "CRDT", ["Top-up by *0051"]), HISTORIQUE)
    cote_cic = s.vers_ligne(CIC, tx("150.00", "DBIT", ["PAIEMENT PSC 2710 PARIS", "REVOLUT**0051*  CARTE 0051"]), HISTORIQUE)
    assert (cote_revolut["category"], cote_revolut["is_internal"], cote_revolut["amount"]) == ("Épargne", True, 150.0)
    assert (cote_cic["category"], cote_cic["is_internal"], cote_cic["amount"]) == ("Épargne", True, -150.0)


def test_autres_formats_de_paiement_cic():
    cas = {
        "PAIEMENT MOB 2609 ATTAINVILLE | LA FERME DES ORM CARTE 0051": "LA FERME DES ORM (Attainville)",
        "3 PAIEMENTS 1908 SAINT NAZAIRE | SPEED QUEEN CARTE 0051": "SPEED QUEEN (Saint Nazaire)",
        "1209 SARCELLES | CTA 95           CARTE 0051": "CTA 95 (Sarcelles)",
        "PAIEMENT PSC 2410 GONES2020922/ | QPF GONESSE AUT CARTE 0051": "QPF GONESSE AUT (Gones)",
    }
    for brut, attendu in cas.items():
        assert s.nettoyer_libelle("CIC", {"remittance_information": brut.split(" | ")})[0] == attendu


def test_versement_du_compte_principal_vers_la_reserve():
    l = s.vers_ligne(REVOLUT, tx("300.00", "DBIT", ["To EUR MB:921c57e1-090d-4619-b98b-7f002cbdb49d"]), HISTORIQUE)
    assert (l["category"], l["is_internal"], l["amount"]) == ("Épargne", True, -300.0)


def test_reserve_economies_toujours_interne():
    versement = s.vers_ligne(ECONOMIES, tx("300.00", "CRDT", ["To EUR MB:921c57e1"]), HISTORIQUE)
    retrait = s.vers_ligne(ECONOMIES, tx("400.00", "DBIT", ["To EUR"]), HISTORIQUE)
    assert (versement["category"], versement["amount"]) == ("Épargne", 300.0)
    assert (retrait["category"], retrait["amount"]) == ("Retrait d'épargne", -400.0)
    assert versement["is_internal"] and retrait["is_internal"]


def test_marchand_revolut_par_mots_cles():
    l = s.vers_ligne(REVOLUT, tx("21.60", "DBIT", ["Anthropic* Claude Sub"], creditor={"name": "Anthropic* Claude Sub"}), HISTORIQUE)
    assert (l["category"], l["merchant"]) == ("Abonnement", "Anthropic* Claude Sub")
    l = s.vers_ligne(REVOLUT, tx("75.05", "DBIT", ["Carrefour Dac Vl"], creditor={"name": "Mp*carrefour Dac Vl"}), HISTORIQUE)
    assert (l["category"], l["merchant"]) == ("Alimentation", "carrefour Dac Vl")


def test_entree_inconnue_est_un_virement_recu_sortie_inconnue_autre():
    assert s.categoriser("Payment from MANGOPAY", None, 311.14, {}) == "Virement reçu"
    assert s.categoriser("XYZ INCONNU", None, -12.0, {}) == "Autre"
    assert s.categoriser("SALAIRE ACME", None, -10.0, {}) == "Autre"  # « salaire » en sortie : pas un revenu


def test_virement_sortant_vers_quelqu_un_qui_t_a_deja_paye():
    # Alex Martin t'a déjà envoyé de l'argent (historique « Virement reçu ») ; le 20/08, c'est toi qui lui envoies.
    assert s.categoriser("Alex Martin", "Alex Martin", -68.08, {"alex martin": "Virement reçu"}) == "Virement émis"
    assert s.categoriser("Alex Martin", "Alex Martin", 50.0, {"alex martin": "Virement reçu"}) == "Virement reçu"


def test_rapprochement_avec_l_historique_importe():
    existantes = [
        {"date": "2026-05-15", "amount": -5.30, "entry_reference": None, "status": "booked"},
        {"date": "2026-10-01", "amount": -9.00, "entry_reference": "deja", "status": "booked"},
    ]
    nouvelles = [
        {"date": "2026-05-16", "amount": -5.30, "entry_reference": "a"},   # même achat que le CSV, un jour d'écart
        {"date": "2026-05-16", "amount": -5.30, "entry_reference": "b"},   # second achat identique : gardé
        {"date": "2026-10-01", "amount": -9.00, "entry_reference": "deja"},  # déjà synchronisé
        {"date": "2026-10-02", "amount": -3.00, "entry_reference": "c"},
    ]
    gardees, ecartees = s.rapprocher(nouvelles, existantes)
    assert [g["entry_reference"] for g in gardees] == ["b", "c"]
    assert ecartees == 2


def test_choix_du_solde():
    assert s.choisir_solde([{"balance_type": "CLBD", "balance_amount": {"amount": "2144.01"}},
                            {"balance_type": "XPCD", "balance_amount": {"amount": "2021.13"}}]) == 2021.13
    assert s.choisir_solde([{"balance_type": "ITAV", "balance_amount": {"amount": "178.83"}}]) == 178.83
    assert s.choisir_solde([]) is None


def test_solde_cic_comptabilise_plus_operations_en_attente():
    # Le cas du 31/10 : le prévisionnel du CIC (1 989,35) oubliait le virement de 150 € vers Revolut.
    soldes = [{"balance_type": "XPCD", "balance_amount": {"amount": "1989.35"}},
              {"balance_type": "CLBD", "balance_amount": {"amount": "2053.82"}}]
    en_attente = [{"amount": a} for a in (-150.0, -23.98, -30.70, -1.99, -7.80)]
    assert s.choisir_solde(soldes, en_attente) == 1839.35
    assert s.choisir_solde(soldes, []) == 2053.82
    # Revolut ne donne qu'un disponible, qui compte déjà ses opérations en attente.
    assert s.choisir_solde([{"balance_type": "ITAV", "balance_amount": {"amount": "169.66"}}],
                           [{"amount": -82.30}]) == 169.66


def test_assurance_voiture():
    l = s.vers_ligne(REVOLUT, tx("55.88", "DBIT", ["Assurance Auto 123456789", "Assureur"],
                                 creditor={"name": "Assurance Auto"}), HISTORIQUE)
    assert l["category"] == "Assurance"


def test_paiement_cb_en_ligne_comptabilise():
    l = s.vers_ligne(CIC, tx("85.19", "DBIT", ["PAIEMENT CB  2910 PARIS", "LEBONCOIN        CARTE 0051"],
                             transaction_date="2026-10-30"), HISTORIQUE)
    assert (l["description"], l["merchant"]) == ("LEBONCOIN (Paris)", "LEBONCOIN")
    assert l["date"] == "2026-10-29"  # le CIC le date du 30, le libellé dit le 29


def test_date_d_achat_lue_dans_le_libelle_cic():
    def jour(libelles, compta):
        return s.date_achat("CIC", {"remittance_information": libelles}, compta)
    assert jour(["PAIEMENT PSC 2910 RUEIL-MALMAIS", "GRAIN OR BOULAN  CARTE 0051"], "2026-10-30") == "2026-10-29"
    assert jour(["3112 PARIS", "FNAC  CARTE 0051"], "2027-01-02") == "2026-12-31"       # changement d'année
    assert jour(["3 PAIEMENTS 1908 SAINT NAZAIRE", "SPEED QUEEN"], "2026-10-19") == "2026-10-19"  # échéance
    assert jour(["PAIEMENT CB GRAIN OR BOULAN"], "2026-10-30") == "2026-10-30"           # pas de date
    assert jour(["PAIEMENT PSC 3102 PARIS", "X"], "2026-03-01") == "2026-03-01"           # date impossible
    assert s.date_achat("Revolut", {"remittance_information": ["2910 PARIS"]}, "2026-10-30") == "2026-10-30"
