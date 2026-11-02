"""Tests des objectifs, sur les exemples de docs/regles-de-calcul.md § 5."""
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

import objectifs as o  # noqa: E402

AUJOURDHUI = date(2026, 10, 30)


def objectif(**autres):
    return {"id": "g1", "name": "Permis", "kind": "projet", "icon": "car", "status": "active",
            "target_amount": 1200, "deadline": "2027-04-30", "created_at": "2026-05-01T10:00:00+00:00", **autres}


def mvt(montant, jour, statut="confirme"):
    return {"goal_id": "g1", "amount": montant, "status": statut,
            "created_at": f"{jour}T12:00:00+00:00", "confirmed_at": f"{jour}T12:00:00+00:00" if statut == "confirme" else None}


def test_exemple_du_document_permis():
    # 300 € déjà versés, dont 300 € sur les 90 derniers jours = 100 €/mois environ.
    e = o.calculer(objectif(), [mvt(100, "2026-08-15"), mvt(100, "2026-09-15"), mvt(100, "2026-10-15")], [], AUJOURDHUI)
    assert (e.verse, e.reste, e.jours_restants) == (300, 900, 182)
    assert (e.par_jour, e.par_semaine, e.par_mois) == (4.95, 34.62, 150.33)
    assert e.rythme_mensuel == 101.33
    assert e.faisabilite == 67
    assert e.date_estimee == date(2027, 7, 27)
    assert not e.echeance_depassee


def test_versement_en_attente_ne_compte_pas_encore():
    e = o.calculer(objectif(), [mvt(150, "2026-10-29", statut="en_attente")], [], AUJOURDHUI)
    assert (e.verse, e.en_attente, e.reste) == (0, 150, 1200)


def test_retrait_diminue_le_verse():
    e = o.calculer(objectif(kind="imprevus", deadline=None, target_amount=1000),
                   [mvt(400, "2026-10-01"), mvt(-200, "2026-10-20")], [], AUJOURDHUI)
    assert (e.verse, e.reste) == (200, 800)
    assert e.par_jour is None and e.faisabilite is None      # pas d'échéance


def test_projet_paye_avec_la_tirelire_compte_une_seule_fois():
    # Voyage : 350 € versés, 247,80 € repris de la tirelire pour payer l'Airbnb, Airbnb rattaché.
    e = o.calculer(objectif(target_amount=350), [mvt(350, "2026-07-01"), mvt(-247.80, "2026-07-20")],
                   [{"goal_id": "g1", "amount": -247.80}], AUJOURDHUI)
    assert (e.verse, e.disponible, e.depense, e.epargne_totale) == (102.20, 102.20, 247.80, 350)
    assert (e.atteint, e.progression, e.reste) == (True, 1.0, 0)


def test_imprevus_apres_une_urgence_est_a_reremplir():
    # 1 000 € versés, 200 € repris, garage 185 € rattaché : le coussin est à 800 €, soit 80 %.
    e = o.calculer(objectif(kind="imprevus", deadline=None, target_amount=1000),
                   [mvt(1000, "2026-06-01"), mvt(-200, "2026-10-20")], [{"goal_id": "g1", "amount": -185}], AUJOURDHUI)
    assert (e.disponible, e.depense, e.epargne_totale, e.progression, e.reste) == (800, 185, 800, 0.8, 200)
    assert not e.atteint


def test_echeance_depassee_propose_une_date_sans_division_par_zero():
    e = o.calculer(objectif(target_amount=350, deadline="2026-07-31"), [mvt(100, "2026-09-01")], [], AUJOURDHUI)
    assert e.echeance_depassee
    assert (e.jours_restants, e.par_jour, e.faisabilite) == (None, None, None)
    # 100 € sur 90 jours = 1,11 €/jour ; 250 € restants → 225 jours.
    assert e.echeance_suggeree == date(2027, 6, 12)


def test_echeance_depassee_sans_rythme():
    e = o.calculer(objectif(target_amount=350, deadline="2026-07-31"), [], [], AUJOURDHUI)
    assert e.echeance_depassee and e.echeance_suggeree is None


def test_premier_mois_pas_de_rythme_affiche():
    # Le cas d'Imprévus : 2 × 5 € le 30/10. Le lendemain, pas d'estimation ni de faisabilité.
    e = o.calculer(objectif(created_at="2026-10-01T08:00:00+00:00"), [mvt(5, "2026-10-30"), mvt(5, "2026-10-30")],
                   [], date(2026, 10, 31))
    assert (e.verse, e.rythme_connu, e.premier_versement) == (10, False, date(2026, 10, 30))
    assert (e.date_estimee, e.faisabilite) == (None, None)
    assert e.par_mois is not None                     # ce qu'il faut mettre de côté reste affiché
    plus_tard = o.calculer(objectif(created_at="2026-10-01T08:00:00+00:00"), [mvt(5, "2026-10-30")], [],
                           date(2026, 11, 29))
    assert plus_tard.rythme_connu and plus_tard.date_estimee is not None


def test_objectif_recent_rythme_sur_30_jours_minimum():
    # Créé il y a 5 jours avec un versement de 150 € : rythme = 150 € / 30 jours, pas / 5 jours.
    e = o.calculer(objectif(created_at="2026-10-25T08:00:00+00:00"), [mvt(150, "2026-10-26")], [], AUJOURDHUI)
    assert e.rythme_mensuel == 152.0


def test_objectif_atteint_faisabilite_maximale():
    e = o.calculer(objectif(), [mvt(1200, "2026-10-01")], [], AUJOURDHUI)
    assert (e.atteint, e.reste, e.par_jour, e.faisabilite, e.date_estimee) == (True, 0, 0, 100, None)


# ── Reconnaissance des virements ──────────────────────────────────────────────

DEPUIS = date(2026, 10, 31)


def attente(id_, montant, declare_le, refusees=()):
    return {"id": id_, "goal_id": "g1", "amount": montant, "status": "en_attente",
            "created_at": f"{declare_le}T20:00:00+00:00", "transaction_id": None,
            "rejected_transaction_ids": list(refusees)}


def reserve(id_, montant, jour, statut="booked"):
    return {"id": id_, "amount": montant, "date": jour, "status": statut}


def test_virement_du_meme_montant_confirme_le_versement():
    paires = o.rapprocher_versements([attente("m1", 150, "2026-11-02")],
                                     [reserve("t0", 80, "2026-11-03"), reserve("t1", 150, "2026-11-04")], DEPUIS)
    assert paires == [("m1", "t1")]


def test_fenetre_de_2_jours_avant_a_7_jours_apres():
    m = [attente("m1", 150, "2026-11-10")]
    assert o.rapprocher_versements(m, [reserve("t1", 150, "2026-11-08")], DEPUIS) == [("m1", "t1")]   # virement d'abord
    assert o.rapprocher_versements(m, [reserve("t1", 150, "2026-11-07")], DEPUIS) == []               # 3 jours avant
    assert o.rapprocher_versements(m, [reserve("t1", 150, "2026-11-17")], DEPUIS) == [("m1", "t1")]
    assert o.rapprocher_versements(m, [reserve("t1", 150, "2026-11-18")], DEPUIS) == []               # 8 jours après


def test_retrait_reconnu_par_une_sortie_de_la_reserve():
    paires = o.rapprocher_versements([attente("m1", -200, "2026-11-02")],
                                     [reserve("t1", 200, "2026-11-02"), reserve("t2", -200, "2026-11-02")], DEPUIS)
    assert paires == [("m1", "t2")]


def test_virement_conteste_jamais_repropose():
    paires = o.rapprocher_versements([attente("m1", 150, "2026-11-02", refusees=["t1"])],
                                     [reserve("t1", 150, "2026-11-02")], DEPUIS)
    assert paires == []


def test_deux_versements_identiques_deux_virements_distincts():
    paires = o.rapprocher_versements(
        [attente("m2", 50, "2026-11-05"), attente("m1", 50, "2026-11-01")],
        [reserve("t1", 50, "2026-11-01"), reserve("t2", 50, "2026-11-05")], DEPUIS)
    assert sorted(paires) == [("m1", "t1"), ("m2", "t2")]


def test_virement_deja_utilise_ou_en_attente_ou_trop_ancien_ignore():
    deja = {"id": "m0", "goal_id": "g1", "amount": 150, "status": "confirme", "transaction_id": "t1",
            "created_at": "2026-11-01T10:00:00+00:00"}
    paires = o.rapprocher_versements(
        [deja, attente("m1", 150, "2026-11-02")],
        [reserve("t1", 150, "2026-11-01"), reserve("t2", 150, "2026-11-02", statut="pending"),
         reserve("t3", 150, "2026-10-30")], DEPUIS)
    assert paires == []


def test_operations_de_la_reserve_a_attribuer():
    mouvements = [{"id": "m0", "amount": 150, "status": "confirme", "transaction_id": "t1",
                   "created_at": "2026-11-01T10:00:00+00:00"}]
    a_attribuer = o.operations_a_attribuer(
        mouvements, [reserve("t1", 150, "2026-11-01"), reserve("t2", 80, "2026-11-03"),
                     reserve("t3", 300, "2026-10-20")], DEPUIS)
    assert [t["id"] for t in a_attribuer] == ["t2"]


def test_objectif_archive_ne_propose_rien():
    e = o.calculer(objectif(target_amount=350, deadline="2026-07-31", status="archive"), [], [], AUJOURDHUI)
    assert (e.echeance_depassee, e.par_jour, e.faisabilite, e.echeance_suggeree) == (False, None, None, None)


def test_versement_confirme_a_la_main_relie_ensuite_a_son_virement():
    # Le cas du 30/10 : 5 € déclarés, « confirmer quand même », puis deux virements de 5 € dans la réserve.
    a_la_main = {"id": "m1", "goal_id": "g1", "amount": 5, "status": "confirme", "transaction_id": None,
                 "created_at": "2026-10-30T22:35:47+00:00", "rejected_transaction_ids": []}
    operations = [reserve("t1", 5, "2026-10-30"), reserve("t2", 5, "2026-10-30")]
    depuis = date(2026, 10, 30)
    assert o.rapprocher_versements([a_la_main], operations, depuis) == [("m1", "t1")]
    relie = {**a_la_main, "transaction_id": "t1"}
    assert [t["id"] for t in o.operations_a_attribuer([relie], operations, depuis)] == ["t2"]


# ── « C'était une annulation » ────────────────────────────────────────────────

def confirme(id_, montant, jour, transaction_id=None):
    return {"id": id_, "goal_id": "g1", "amount": montant, "status": "confirme", "transaction_id": transaction_id,
            "created_at": f"{jour}T10:00:00+00:00", "confirmed_at": f"{jour}T10:00:00+00:00"}


def test_annulation_du_test_du_30_10():
    # 2 × 5 € versés le 30/10, puis 10 € repris le même soir.
    mouvements = [confirme("m1", 5, "2026-10-30", "t1"), confirme("m2", 5, "2026-10-30", "t2")]
    choisis = o.versements_a_annuler(reserve("t3", -10, "2026-10-30"), mouvements)
    assert sorted(m["id"] for m in choisis) == ["m1", "m2"]


def test_annulation_prend_les_versements_les_plus_recents():
    mouvements = [confirme("vieux", 50, "2026-10-01"), confirme("recent", 50, "2026-10-20"),
                  confirme("autre", 30, "2026-10-25")]
    assert [m["id"] for m in o.versements_a_annuler(reserve("t", -50, "2026-10-26"), mouvements)] == ["recent"]


def test_annulation_impossible_si_rien_ne_tombe_juste():
    mouvements = [confirme("m1", 5, "2026-10-30"), confirme("m2", 5, "2026-10-30")]
    assert o.versements_a_annuler(reserve("t", -7, "2026-10-30"), mouvements) == []


def test_annulation_ignore_retraits_attente_et_versements_posterieurs():
    mouvements = [confirme("pioche", -10, "2026-10-29"),
                  {**confirme("attente", 10, "2026-10-29"), "status": "en_attente"},
                  confirme("apres", 10, "2026-11-02")]
    assert o.versements_a_annuler(reserve("t", -10, "2026-10-30"), mouvements) == []


# ── « Rattacher à un projet ? » ───────────────────────────────────────────────

def etat(id_, disponible, type_="projet", statut="active"):
    e = o.calculer(objectif(id=id_, kind=type_, status=statut, target_amount=1000), [mvt(disponible, "2026-09-01")], [],
                   AUJOURDHUI)
    return e


def depense(id_, montant, jour="2026-10-31", **autres):
    return {"id": id_, "amount": montant, "date": jour, "status": "booked", "is_internal": False, "goal_id": None,
            "merchant": "AIRBNB", **autres}


def test_suggestion_pour_une_grosse_depense_couverte_par_un_projet():
    etats = [etat("voyage", 350), etat("imprevus", 900, type_="imprevus")]
    s = o.suggestions_rattachement([depense("t1", -247.80)], etats, date(2026, 10, 30))
    assert [(x["id"], x["objectifs"]) for x in s] == [("t1", ["voyage"])]   # Imprévus n'est pas un projet


def test_pas_de_suggestion_si_aucun_projet_n_a_assez():
    assert o.suggestions_rattachement([depense("t1", -247.80)], [etat("voyage", 200)], date(2026, 10, 30)) == []


def test_pas_de_suggestion_sous_100_ou_deja_traitee():
    etats = [etat("voyage", 1000)]
    depenses = [depense("petite", -99.99), depense("attente", -150, status="pending"),
                depense("ignoree", -150, suggestion_ignoree=True), depense("rattachee", -150, goal_id="voyage"),
                depense("interne", -150, is_internal=True), depense("ancienne", -150, jour="2026-10-20")]
    assert o.suggestions_rattachement(depenses, etats, date(2026, 10, 30)) == []


def test_pas_de_suggestion_vers_un_projet_archive():
    assert o.suggestions_rattachement([depense("t1", -150)], [etat("voyage", 1000, statut="archive")],
                                      date(2026, 10, 30)) == []


# ── Reprises de la tirelire suivies jusqu'aux dépenses ────────────────────────

def op(id_, montant, jour, banque, interne=False, **autres):
    return {"id": id_, "amount": montant, "date": jour, "bank_name": banque, "is_internal": interne,
            "goal_id": None, "status": "booked", "merchant": id_.upper(), **autres}


RESERVE = lambda id_, montant, jour, **a: {"id": id_, "amount": montant, "date": jour, "status": "booked", **a}  # noqa: E731
DEBUT = date(2026, 10, 30)


def test_reprise_puis_garage_sur_revolut():
    # Mardi : 200 € repris de la réserve, arrivés sur Revolut, puis garage 185 € le lendemain.
    q = o.chaines_de_retrait([RESERVE("w", -200, "2026-11-03")],
                             [op("arrivee", 200, "2026-11-03", "Revolut", True), op("garage", -185, "2026-11-04", "Revolut"),
                              op("pain", -2, "2026-11-04", "Revolut"), op("loin", -50, "2026-11-08", "Revolut")],
                             [], DEBUT)
    assert len(q) == 1 and q[0]["arrivee"] == "Revolut" and q[0]["objectif_id"] is None
    assert [(d["id"], d["cochee"]) for d in q[0]["depenses"]] == [("garage", True), ("pain", True)]


def test_reprise_envoyee_au_cic_puis_depensee_au_cic():
    q = o.chaines_de_retrait([RESERVE("w", -300, "2026-11-03")],
                             [op("rev", 300, "2026-11-03", "Revolut", True), op("vers_cic", 300, "2026-11-04", "CIC", True),
                              op("courses_rev", -20, "2026-11-04", "Revolut"), op("loyer", -280, "2026-11-05", "CIC")],
                             [], DEBUT)
    assert q[0]["arrivee"] == "CIC" and [d["id"] for d in q[0]["depenses"]] == ["loyer"]


def test_pas_de_question_si_les_depenses_font_moins_de_la_moitie():
    assert o.chaines_de_retrait([RESERVE("w", -200, "2026-11-03")],
                                [op("pain", -60, "2026-11-04", "Revolut")], [], DEBUT) == []


def test_les_plus_grosses_depenses_qui_tiennent_dans_la_reprise_sont_cochees():
    q = o.chaines_de_retrait([RESERVE("w", -200, "2026-11-03")],
                             [op("a", -150, "2026-11-03", "Revolut"), op("b", -80, "2026-11-04", "Revolut"),
                              op("c", -40, "2026-11-05", "Revolut")], [], DEBUT)
    assert {d["id"]: d["cochee"] for d in q[0]["depenses"]} == {"a": True, "b": False, "c": True}


def test_reprise_deja_traitee_annulee_ou_en_attente_ignoree():
    depenses = [op("garage", -185, "2026-11-04", "Revolut")]
    for w in (RESERVE("w", -200, "2026-11-03", suggestion_ignoree=True), RESERVE("w", -200, "2026-11-03", reserve_annulee=True),
              RESERVE("w", -200, "2026-11-03", status="pending"), RESERVE("w", 200, "2026-11-03")):
        assert o.chaines_de_retrait([w], depenses, [], DEBUT) == []


def test_reprise_declaree_garde_son_objectif_et_depenses_deja_rattachees_exclues():
    mouvements = [{"id": "m", "goal_id": "imprevus", "amount": -200, "status": "confirme", "transaction_id": "w",
                   "created_at": "2026-11-03T08:00:00+00:00"}]
    q = o.chaines_de_retrait([RESERVE("w", -200, "2026-11-03")],
                             [op("garage", -185, "2026-11-04", "Revolut"), op("deja", -150, "2026-11-04", "Revolut", goal_id="x")],
                             mouvements, DEBUT)
    assert q[0]["objectif_id"] == "imprevus" and [d["id"] for d in q[0]["depenses"]] == ["garage"]
