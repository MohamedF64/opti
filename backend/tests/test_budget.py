"""Tests du calcul « tu peux encore dépenser », sur les exemples de docs/regles-de-calcul.md."""
import sys
from datetime import date
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

import budget as b  # noqa: E402

AUJOURDHUI = date(2026, 10, 30)
ABONNEMENTS = [
    b.Abonnement("AMAZON PRIME FR", 6.99, "mensuel", date(2026, 10, 3)),
    b.Abonnement("Forfait mobile Prixtel", 12.61, "mensuel", date(2026, 10, 5)),
    b.Abonnement("Assurance auto", 55.88, "mensuel", date(2026, 10, 6)),
    b.Abonnement("Abonnement Imagine R", 51.70, "mensuel", date(2026, 10, 7)),
    b.Abonnement("Anthropic (Claude)", 21.60, "mensuel", date(2026, 10, 7)),
]


def op(jour, montant, categorie="Alimentation", **autres):
    return {"date": jour, "amount": montant, "category": categorie, **autres}


def operations_du_document(**en_plus):
    return [
        op("2026-09-25", 1040.00, "Salaire"),
        op("2026-10-26", 1850.00, "Salaire"),
        op("2026-10-26", -250.00, "Épargne", is_internal=True),   # mis de côté : pas une dépense
        op("2026-10-27", -60.00),
        op("2026-10-28", -64.05, "Restauration"),
        op("2026-10-29", -130.17, "Shopping"),
        *en_plus.get("autres", []),
    ]


def test_exemple_du_document_donne_39_55():
    r = b.calculer(AUJOURDHUI, operations_du_document(), ABONNEMENTS, b.Reglages(epargne_visee=300))
    assert (r.debut_cycle, r.paie, r.jours_restants) == (date(2026, 10, 26), 1850.00, 29)
    assert (r.paie_au_plus_tot, r.paie_au_plus_tard) == (date(2026, 11, 21), date(2026, 11, 28))
    assert round(sum(a["montant"] for a in r.abonnements_a_venir), 2) == 148.78
    assert [a["date"] for a in r.abonnements_a_venir] == ["2026-11-03", "2026-11-05", "2026-11-06", "2026-11-07", "2026-11-07"]
    assert r.depense_avant_aujourdhui == 254.22
    assert r.reste_du_cycle == 1147.00
    assert (r.limite_calculee, r.tu_peux_encore, r.limite_appliquee) == (39.55, 39.55, "calculee")


def test_depense_d_aujourd_hui_et_remboursement():
    ops = operations_du_document(autres=[op("2026-10-30", -12.50), op("2026-10-30", 2.50, "Shopping")])
    r = b.calculer(AUJOURDHUI, ops, ABONNEMENTS, b.Reglages(epargne_visee=300))
    assert r.depense_aujourdhui == 10.00
    assert r.tu_peux_encore == 29.55


def test_depense_de_projet_hors_enveloppe():
    ops = operations_du_document(autres=[op("2026-10-29", -247.80, "Loisirs", goal_id="voyage")])
    r = b.calculer(AUJOURDHUI, ops, ABONNEMENTS, b.Reglages(epargne_visee=300))
    assert r.depense_avant_aujourdhui == 254.22


def test_revenus_et_virements_internes_ne_comptent_pas():
    ops = operations_du_document(autres=[op("2026-10-28", 30.00, "Virement reçu"),
                                         op("2026-10-28", 150.00, "Retrait d'épargne", is_internal=True)])
    assert b.calculer(AUJOURDHUI, ops, ABONNEMENTS, b.Reglages(epargne_visee=300)).depense_avant_aujourdhui == 254.22


def test_abonnement_deja_preleve_pendant_le_cycle_n_est_pas_compte_deux_fois():
    abos = ABONNEMENTS + [b.Abonnement("Deezer", 10.99, "mensuel", date(2026, 10, 28))]
    r = b.calculer(AUJOURDHUI, operations_du_document(), abos, b.Reglages(epargne_visee=300))
    assert "Deezer" not in [a["nom"] for a in r.abonnements_a_venir]


def test_marge_de_securite_plancher():
    r = b.calculer(AUJOURDHUI, operations_du_document(), ABONNEMENTS, b.Reglages(epargne_visee=300, limite_manuelle=50))
    assert (r.limite_du_jour, r.limite_appliquee) == (50.0, "plancher")
    assert r.effet_limite_manuelle == round((50 - 39.55) / 28, 2)
    # Une marge plus basse que le calcul ne change rien.
    r = b.calculer(AUJOURDHUI, operations_du_document(), ABONNEMENTS, b.Reglages(epargne_visee=300, limite_manuelle=20))
    assert (r.limite_du_jour, r.limite_appliquee) == (39.55, "calculee")


def test_mode_economies_max_plafond():
    r = b.calculer(AUJOURDHUI, operations_du_document(), ABONNEMENTS,
                   b.Reglages(epargne_visee=300, limite_manuelle=20, mode_economies_max=True))
    assert (r.limite_du_jour, r.limite_appliquee) == (20.0, "plafond")


def test_budget_epuise_jamais_negatif_mais_depassement_visible():
    ops = operations_du_document(autres=[op("2026-10-29", -1500.00, "Shopping"), op("2026-10-30", -20.00)])
    r = b.calculer(AUJOURDHUI, ops, ABONNEMENTS, b.Reglages(epargne_visee=300))
    assert r.reste_du_cycle < 0
    assert r.limite_calculee == 0.0
    assert r.tu_peux_encore == -20.0


def test_paie_en_retard_sans_division_par_zero():
    r = b.calculer(date(2026, 11, 29), operations_du_document(), ABONNEMENTS, b.Reglages(epargne_visee=300))
    assert r.paie_en_retard and r.jours_restants == 1


def test_fin_d_annee_et_mois_courts():
    ops = [op("2026-12-24", 900.0, "Salaire")]
    r = b.calculer(date(2026, 12, 30), ops, [], b.Reglages(jour_paie_max=31))
    assert r.paie_au_plus_tard == date(2027, 1, 31)
    ops = [op("2027-01-26", 900.0, "Salaire")]
    assert b.calculer(date(2027, 2, 1), ops, [], b.Reglages(jour_paie_max=31)).paie_au_plus_tard == date(2027, 2, 28)


def test_sans_paie_erreur_explicite():
    with pytest.raises(ValueError):
        b.calculer(AUJOURDHUI, [op("2026-10-29", -5.0)], [], b.Reglages())


def test_epargne_proposee_par_les_objectifs():
    objectifs = [
        {"id": "voyage", "status": "active", "kind": "projet", "deadline": "2027-01-28", "target_amount": 350},
        {"id": "imprevus", "status": "active", "kind": "imprevus", "deadline": None, "target_amount": 1000},
        {"id": "vieux", "status": "active", "kind": "projet", "deadline": "2026-07-31", "target_amount": 350},
    ]
    mouvements = [{"goal_id": "voyage", "amount": 50, "status": "confirme"},
                  {"goal_id": "voyage", "amount": 100, "status": "en_attente"}]  # pas encore confirmé : ignoré
    montant, source = b.epargne_proposee(objectifs, mouvements, AUJOURDHUI, 29, mis_de_cote_recent=80)
    # Voyage : 300 € restants sur 90 jours, dont 29 dans ce cycle.
    assert (montant, source) == (round(300 * 29 / 90, 2), "demandée par tes objectifs")


def test_epargne_proposee_sinon_rythme_recent():
    assert b.epargne_proposee([], [], AUJOURDHUI, 29, 83.33) == (83.33, "ton rythme récent")
    assert b.epargne_proposee([], [], AUJOURDHUI, 29, -10) == (0.0, "aucune pour l'instant")


def test_cycle_depasse_limite_courses_habituelles():
    """Cycle dépassé de 42,10 € : limite = courses des 3 cycles terminés par jour (ici 876,76 € / 92 jours = 9,53 €),
    jamais 0 € ; une limite manuelle plus haute s'applique à la place."""
    paies = [op("2026-07-26", 1000.00, "Salaire"), op("2026-08-26", 1000.00, "Salaire"),
             op("2026-09-25", 1040.00, "Salaire"), op("2026-10-26", 600.00, "Salaire")]
    courses = [op("2026-07-20", -999.00, "Alimentation"),                            # avant les 3 cycles
               op("2026-08-28", -300.00), op("2026-09-10", -290.90), op("2026-10-01", -285.86),
               op("2026-10-02", -40.00, "Shopping")]                                # pas de l'essentiel
    trop = [op("2026-10-27", -493.32, "Shopping")]                                  # 600 − 148,78 − 493,32 = −42,10
    ops = paies + courses + trop
    r = b.calculer(AUJOURDHUI, ops, ABONNEMENTS, b.Reglages())
    assert (r.reste_du_cycle, r.depassement) == (-42.10, 42.10)
    assert (r.limite_du_jour, r.limite_appliquee) == (9.53, "essentiel")
    assert r.pourquoi[-2].libelle == "Cycle dépassé : tes courses habituelles par jour"
    assert b.calculer(AUJOURDHUI, ops, ABONNEMENTS, b.Reglages(limite_manuelle=15)).limite_appliquee == "plancher"
    # Cycle pas dépassé : rien ne change.
    assert b.calculer(AUJOURDHUI, paies + courses, ABONNEMENTS, b.Reglages()).limite_appliquee == "calculee"
