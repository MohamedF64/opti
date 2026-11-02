"""Tests de l'écran Stats, sur les règles de docs/regles-de-calcul.md § 8."""
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

import stats  # noqa: E402

AUJOURDHUI = date(2026, 10, 31)


def op(jour, montant, categorie="Alimentation", **autres):
    return {"date": jour, "amount": montant, "category": categorie, **autres}


PAIES = [
    op("2026-04-24", 896.51, "Salaire"),     # avant le premier cycle complet : ignorée
    op("2026-08-25", 880.00, "Salaire"),
    op("2026-09-25", 1040.00, "Salaire"),
    op("2026-10-26", 1850.00, "Salaire"),
]


def test_un_cycle_va_d_une_paie_a_la_veille_de_la_suivante():
    debuts = stats.debuts_de_cycle(PAIES, AUJOURDHUI)
    assert stats.bornes(debuts, AUJOURDHUI) == [
        (date(2026, 8, 25), date(2026, 9, 24), False),
        (date(2026, 9, 25), date(2026, 10, 25), False),
        (date(2026, 10, 26), date(2026, 10, 31), True),     # en cours : s'arrête à aujourd'hui
    ]


def test_ce_qui_compte_et_bilan_du_cycle():
    ops = PAIES + [
        op("2026-09-26", -100.00),
        op("2026-09-27", -10.41, "Shopping"),
        op("2026-09-28", 10.41, "Shopping"),                  # remboursement Vinted : Shopping à 0, absente
        op("2026-09-29", -150.00, "Épargne", is_internal=True),   # virement entre comptes : ignoré
        op("2026-09-30", 30.00, "Virement reçu"),             # revenu : entre dans « entré »
        op("2026-10-01", -850.00, "Permis", goal_id="g1"),   # payé par l'épargne : à part
    ]
    r = stats.calculer("precedent", AUJOURDHUI, ops, [])
    c = r.cycles[0]
    assert (c.debut, c.jours, c.depense, c.entre, c.reste, c.paye_par_epargne) == (
        date(2026, 9, 25), 31, 100.00, 1070.00, 970.00, 850.00)
    assert [(x.nom, x.montant) for x in r.categories] == [("Alimentation", 100.00)]


def test_donut_cinq_categories_puis_le_reste():
    montants = {"Alimentation": 434.93, "Shopping": 214.96, "Autre": 107.37, "Transport": 70.70, "Assurance": 55.88,
                "Restauration": 55.10, "Abonnement": 43.57, "Santé": 15.32, "Maison": 14.14, "Loisirs": 11.96}
    ops = PAIES + [op("2026-10-01", -m, k) for k, m in montants.items()]
    r = stats.calculer("precedent", AUJOURDHUI, ops, [])
    assert r.cycles[0].depense == 1023.93
    assert [(c.nom, c.montant, c.part) for c in r.categories] == [
        ("Alimentation", 434.93, 42.5), ("Shopping", 214.96, 21.0), ("Autre", 107.37, 10.5),
        ("Transport", 70.70, 6.9), ("Assurance", 55.88, 5.5), ("Le reste", 140.09, 13.7)]


def test_evolution_affichee_au_dela_de_10_pourcent_et_20_euros():
    ops = PAIES + [
        op("2026-09-01", -279.14), op("2026-09-01", -396.32, "Shopping"), op("2026-09-01", -75.80, "Transport"),
        op("2026-09-01", -10.00, "Santé"),
        op("2026-10-01", -434.93), op("2026-10-01", -214.96, "Shopping"), op("2026-10-01", -70.70, "Transport"),
        op("2026-10-01", -15.00, "Santé"), op("2026-10-01", -55.88, "Assurance"),
    ]
    r = {c.nom: c for c in stats.calculer("precedent", AUJOURDHUI, ops, []).categories}
    assert (r["Alimentation"].ecart, r["Alimentation"].pourcent) == (155.79, 56)
    assert (r["Shopping"].ecart, r["Shopping"].pourcent) == (-181.36, -46)
    assert r["Transport"].ecart is None          # −5,10 € (−7 %) : sous les deux seuils
    assert r["Santé"].ecart is None              # +50 % mais seulement +5 €
    assert r["Assurance"].nouveau


def test_cycle_en_cours_compare_aux_memes_premiers_jours():
    ops = PAIES + [
        op("2026-09-26", -33.06),            # dans les 6 premiers jours du cycle d'avant
        op("2026-10-20", -401.87),           # plus tard : pas comparé
        op("2026-10-28", -61.64),
    ]
    r = stats.calculer("cycle", AUJOURDHUI, ops, [])
    assert r.cycles[0].jours == 6 and r.cycles[0].en_cours
    alim = r.categories[0]
    assert (alim.precedent, alim.ecart, alim.pourcent) == (33.06, 28.58, 86)


def test_moyenne_des_cycles_termines_seulement():
    ops = PAIES + [op("2026-09-01", -966.97), op("2026-10-01", -1023.93), op("2026-10-28", -360.68)]
    r = stats.calculer("6", AUJOURDHUI, ops, [])
    assert [c.depense for c in r.cycles] == [966.97, 1023.93, 360.68]
    assert r.moyenne == 995.45
    assert all(c.precedent is None for c in r.categories)   # pas de comparaison sur plusieurs cycles


def test_jours_sous_la_limite():
    # Paie 600 € le 26/10, cycle jusqu'au 27/11 (33 jours) → 18,18 €/jour au départ.
    ops = [op("2026-10-26", 600.00, "Salaire"), op("2026-10-27", -100.00), op("2026-10-29", -5.00)]
    r = stats.calculer("cycle", AUJOURDHUI, ops, [])
    assert r.cycles[0].jours_sous_limite == 5    # seul le 27/10 dépasse


def test_abonnement_deja_preleve_n_est_pas_compte_deux_fois():
    abonnement = {"id": "a1", "name": "Prime", "amount": 6.99, "frequency": "mensuel", "merchant_key": "amazon prime"}
    ops = [op("2026-09-03", -6.99, "Abonnement", merchant="AMAZON PRIME"),
           op("2026-10-26", 600.00, "Salaire"),
           op("2026-10-28", -6.99, "Abonnement", merchant="AMAZON PRIME")]
    suivi = stats.suivre_abonnements([abonnement], ops, AUJOURDHUI)[0]
    assert suivi.au(date(2026, 10, 27)).dernier_prelevement == date(2026, 9, 3)    # attendu le 03/11 : à venir
    assert suivi.au(date(2026, 10, 28)).dernier_prelevement == date(2026, 10, 28)  # prélevé : dans les dépenses
