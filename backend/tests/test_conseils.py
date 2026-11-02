"""Conseils de l'accueil : exemples de docs/regles-de-calcul.md § 6."""
import sys
from dataclasses import dataclass
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

import conseils as c  # noqa: E402


@dataclass
class Objectif:
    id: str
    nom: str
    type: str
    statut: str
    cible: float
    disponible: float
    reste: float
    echeance: date | None = None


@dataclass
class Abo:
    id: str
    nom: str
    statut: str
    verdict: str
    economie_par_an: float | None


IMPREVUS = Objectif("imp", "Imprévus", "imprevus", "active", 1000.0, 40.0, 960.0)
RENOVATION = Objectif("reno", "Rénovation", "projet", "active", 1000.0, 0.0, 1000.0)
PAIES = [910.00, 880.00, 1040.00, 1850.00]


def lisible(texte):
    """Les espaces insécables des montants, remplacées pour comparer les phrases."""
    return texte.replace(" ", " ").replace(" ", " ")


def conseils(aujourdhui, **autres):
    valeurs = dict(debut_cycle=date(2026, 10, 26), paie_au_plus_tot=date(2026, 11, 21), jours_restants=27,
                   reste_du_cycle=1491.34, paies=PAIES, depense_par_jour=31.86, en_cours={}, moyennes={},
                   objectifs=[IMPREVUS, RENOVATION], abonnements=[])
    return c.calculer(aujourdhui, **(valeurs | autres))


def test_paie_plus_haute_que_d_habitude_la_moitie_du_supplement():
    [conseil] = conseils(date(2026, 11, 1))
    assert lisible(conseil.texte) == "Ta paie est plus haute que d'habitude (+907 €). Mets 450 € de côté dans Imprévus ?"
    assert conseil.action == {"type": "verser", "objectif_id": "imp", "objectif": "Imprévus", "montant": 450}
    assert conseils(date(2026, 10, 26)) and conseils(date(2026, 10, 30))
    assert all(x.type != "paie_haute" for x in conseils(date(2026, 10, 30), paies=[910.00, 880.00, 1040.00, 1100.0]))


def test_paie_haute_plus_affichee_apres_7_jours():
    assert [x.type for x in conseils(date(2026, 11, 1))] == ["paie_haute"]    # 7e jour du cycle (26/10 → 01/11)
    assert conseils(date(2026, 11, 2)) == []


def test_surplus_de_fin_de_cycle():
    [conseil] = conseils(date(2026, 11, 21), debut_cycle=date(2026, 10, 26), reste_du_cycle=450.0, jours_restants=7)
    assert lisible(conseil.texte) == ("Il te reste 450 € pour 7 jours, tu en as besoin d'environ 243 €. "
                             "Mets 100 € de côté dans Imprévus ?")
    assert conseil.action["montant"] == 100
    # Pas de surplus : rien.
    assert conseils(date(2026, 11, 21), reste_du_cycle=250.0, jours_restants=7) == []
    # Trop tôt (plus de 7 jours avant la paie au plus tôt) : rien.
    assert conseils(date(2026, 11, 13), reste_du_cycle=450.0, jours_restants=15) == []


def test_reserve_d_imprevus_faible_sans_paie_haute():
    [conseil] = conseils(date(2026, 11, 1), paies=[910.00, 880.00, 1040.00, 980.0])
    assert lisible(conseil.texte) == ("Ta réserve Imprévus est à 40 € sur 1 000 €. En y versant 90 € à chaque paie, "
                             "elle est pleine en 11 mois.")
    assert conseil.action["montant"] == 90


def test_categorie_qui_s_emballe():
    [conseil] = conseils(date(2026, 11, 10), en_cours={"Loisirs": 148.87, "Alimentation": 105.53},
                         moyennes={"Loisirs": 70.02, "Alimentation": 202.46})
    assert lisible(conseil.texte) == ("Loisirs : 148,87 € depuis ta paie, 2 fois ta moyenne d'un cycle entier (70 €). "
                             "Lève le pied d'ici le 21/11.")
    assert (conseil.montant, conseil.action) == (78.85, None)
    [en_retard] = conseils(date(2026, 11, 22), en_cours={"Loisirs": 148.87}, moyennes={"Loisirs": 70.02},
                           reste_du_cycle=100.0, jours_restants=6)
    assert lisible(en_retard.texte).endswith("Lève le pied d'ici ta paie.")
    # Moins de 30 € au-dessus : rien.
    assert conseils(date(2026, 11, 10), en_cours={"Loisirs": 95.0}, moyennes={"Loisirs": 70.02}) == []


def test_abonnement_jamais_utilise_et_classement_3_au_plus():
    abo = Abo("deezer", "Deezer", "actif", "a_couper", 131.88)
    resultat = conseils(date(2026, 11, 1), abonnements=[abo],
                        en_cours={"Loisirs": 148.87, "Vêtements": 82.30, "Shopping": 150.0},
                        moyennes={"Loisirs": 70.02, "Vêtements": 21.0, "Shopping": 118.4})
    assert [x.type for x in resultat] == ["paie_haute", "abonnement", "categorie"]
    assert lisible(resultat[1].texte) == "Tu n'utilises jamais Deezer : le résilier te ferait gagner 132 € par an."


def test_versement_vers_le_projet_quand_imprevus_est_plein():
    plein = Objectif("imp", "Imprévus", "imprevus", "active", 1000.0, 1000.0, 0.0)
    [conseil] = conseils(date(2026, 11, 1), objectifs=[plein, RENOVATION])
    assert conseil.action["objectif"] == "Rénovation"


def test_offre_moins_chere_classee_par_l_economie_sur_un_an():
    """§ 12, exemples validés le 01/11/2026 : Claude Pro 21,60 € → Pro annuel 216 € (43,20 €/an) ;
    Prime mensuel 6,99 € → Prime étudiants annuel 34,95 € (48,96 €/an) ; ni essai gratuit ni offre groupée."""
    import catalogue as cat
    services = [
        {"id": "prime", "nom": "Amazon Prime", "famille": "amazon", "page_url": "u", "page_etat": "ok"},
        {"id": "claude", "nom": "Claude", "famille": "ia", "page_url": "u", "page_etat": "illisible"},
        {"id": "google", "nom": "Google One", "famille": "ia", "page_url": "u", "page_etat": "ok"},
    ]

    def offre(id, service, nom, prix, frequence="mensuel", **autres):
        return {"id": id, "service_id": service, "nom": nom, "prix": prix, "frequence": frequence, "go": None,
                "verifie_le": "2026-11-01", "source_url": "u"} | autres

    offres = [
        offre("pro_m", "claude", "Pro mensuel", 21.60), offre("pro_a", "claude", "Pro annuel", 216.00, "annuel"),
        offre("prime_m", "prime", "Prime mensuel", 6.99),
        offre("prime_e", "prime", "Prime étudiants", 3.49, conditions=["etudiant", "age_18_24"]),
        offre("prime_ea", "prime", "Prime étudiants annuel", 34.95, "annuel", conditions=["etudiant", "age_18_24"]),
        offre("ai_plus", "google", "Google AI Plus", 9.99), offre("ai_pro", "google", "Google AI Pro", 4.00),
    ]
    etats = [{"id": "claude", "nom": "Anthropic (Claude)", "par_mois": 21.60, "statut": "actif"},
             {"id": "prime", "nom": "AMAZON PRIME FR", "par_mois": 6.99, "statut": "actif"},
             {"id": "google", "nom": "Google AI plus", "par_mois": 9.99, "statut": "essai"}]
    lignes = [{"id": f"l_{a}", "subscription_id": a, "nom": "Ligne 1", "catalog_offer_id": o, "prix": None, "go": None}
              for a, o in (("claude", "pro_m"), ("prime", "prime_m"), ("google", "ai_plus"))]
    profil = {"etudiant": True, "moins_26": True, "age_18_24": True}
    comparaison = cat.comparer(etats, lignes, services, offres, profil, date(2026, 11, 1))

    tous = conseils(date(2026, 11, 1), catalogue=comparaison["abonnements"])
    assert [(r.type, r.montant) for r in tous] == [("paie_haute", 450), ("offre", 48.96), ("offre", 43.20)]
    resultat = tous[1:]                                                                      # pas Google (essai)
    assert lisible(resultat[0].texte) == ("Amazon Prime : l'offre Prime étudiants annuel (34,95 € payés d'avance) "
                                          "te coûterait 4,08 € de moins par mois, soit 48,96 € par an.")
    assert lisible(resultat[1].texte) == ("Claude : l'offre Pro annuel (216 € payés d'avance) te coûterait 3,60 € "
                                          "de moins par mois, soit 43,20 € par an.")
    assert resultat[1].cle == "offre:l_claude:pro_a:2026-10-26" and resultat[1].action == {"type": "catalogue"}
