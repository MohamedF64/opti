"""Catalogue de prix : exemples de docs/regles-de-calcul.md § 12."""
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

import catalogue as c  # noqa: E402

AUJOURDHUI = date(2026, 11, 1)
VERIFIE = "2026-11-01"
SERVICES = [
    {"id": "prixtel", "nom": "Prixtel", "famille": "mobile", "page_url": "u", "page_etat": "ok"},
    {"id": "xmobile", "nom": "X Mobile", "famille": "mobile", "page_url": "u", "page_etat": "ok"},
    {"id": "bandyou", "nom": "B&You", "famille": "mobile", "page_url": "u", "page_etat": "ok"},
    {"id": "prime", "nom": "Amazon Prime", "famille": "amazon", "page_url": "u", "page_etat": "ok"},
    {"id": "claude", "nom": "Claude", "famille": "ia", "page_url": "u", "page_etat": "illisible"},
    {"id": "google", "nom": "Google One", "famille": "ia", "page_url": "u", "page_etat": "ok"},
]
PAR_ID = {s["id"]: s for s in SERVICES}
PROFIL = {"etudiant": True, "moins_26": True, "age_18_24": True}


def offre(id, service, prix, go=None, frequence="mensuel", **autres):
    return {"id": id, "service_id": service, "nom": id, "prix": prix, "frequence": frequence, "go": go,
            "verifie_le": VERIFIE, "source_url": "u"} | autres


ACTUELLE = offre("prixtel100", "prixtel", 15.65, go=100)
X = offre("x130", "xmobile", 9.99, go=130)
Y = offre("y100", "xmobile", 15.00, go=100)
Z = offre("z80", "xmobile", 9.99, go=80)
PRIME = [offre("prime_m", "prime", 6.99), offre("prime_a", "prime", 69.90, frequence="annuel"),
         offre("prime_e", "prime", 3.49, conditions=["etudiant", "age_18_24"])]
PACK = offre("pack", "bandyou", 17.99, go=170, inclut=["Amazon Prime"])
CLAUDE = [offre("pro_m", "claude", 21.60), offre("pro_a", "claude", 216.00, frequence="annuel"),
          offre("max", "claude", 108.00)]
GOOGLE = offre("ai_plus", "google", 9.99)
TOUTES = [ACTUELLE, X, Y, Z, PACK, GOOGLE] + PRIME + CLAUDE


def test_prix_ramene_au_mois():
    assert c.par_mois({"prix": 24.99, "frequence": "quatre_semaines"}) == 27.07   # Basic-Fit
    assert c.par_mois({"prix": 69.90, "frequence": "annuel"}) == 5.83
    assert c.par_mois({"prix": 216.00, "frequence": "annuel"}) == 18.00


def test_a_reverifier_apres_12_mois():
    o = {"verifie_le": "2025-11-01"}
    assert not c.a_reverifier(o, date(2026, 11, 1))
    assert c.a_reverifier(o, date(2026, 11, 2))


def test_exemple_x_y_z():
    """X 9,99 € (130 Go) : 5,66 €/mois, 67,92 €/an. Y : 0,65 € (4 %), non signalée. Z : 80 Go, écartée."""
    alt = c.alternatives(15.65, 100, ACTUELLE, [ACTUELLE, X, Y, Z], PAR_ID, PROFIL, AUJOURDHUI)
    assert [a["offre_id"] for a in alt] == ["x130"]
    assert alt[0]["economie_par_mois"] == 5.66 and alt[0]["economie_par_an"] == 67.92


def test_seuil_un_euro_ou_dix_pour_cent():
    assert c._signalee(1.00, 50.0)          # 1 € (2 %)
    assert c._signalee(0.60, 5.0)           # 12 %
    assert not c._signalee(0.65, 15.65)     # 0,65 € (4 %)
    assert not c._signalee(-2.0, 15.0)


def test_go_inconnus_pas_de_comparaison_mobile():
    assert c.alternatives(15.65, None, ACTUELLE, [ACTUELLE, X], PAR_ID, PROFIL, AUJOURDHUI) == []


def test_offre_a_reverifier_ou_sous_condition_ecartee():
    vieille = X | {"verifie_le": "2025-10-01"}
    assert c.alternatives(15.65, 100, ACTUELLE, [ACTUELLE, vieille], PAR_ID, PROFIL, AUJOURDHUI) == []
    prime = PRIME[0]
    avec = c.alternatives(6.99, None, prime, PRIME, PAR_ID, PROFIL, AUJOURDHUI)
    assert [a["offre_id"] for a in avec] == ["prime_e", "prime_a"]          # 3,50 € puis 1,16 €
    sans = c.alternatives(6.99, None, prime, PRIME, PAR_ID, {"etudiant": False, "age_18_24": False}, AUJOURDHUI)
    assert [a["offre_id"] for a in sans] == ["prime_a"]
    # Étudiant OU 18-24 ans : l'un des deux suffit.
    age = c.alternatives(6.99, None, prime, PRIME, PAR_ID, {"etudiant": False, "age_18_24": True}, AUJOURDHUI)
    assert [a["offre_id"] for a in age] == ["prime_e", "prime_a"]


def test_claude_pro_annuel():
    """Pro mensuel 21,60 € → annuel 216 € (18 €/mois) : 3,60 €/mois, 43,20 €/an, 216 € payés d'avance."""
    alt = c.alternatives(21.60, None, CLAUDE[0], TOUTES, PAR_ID, PROFIL, AUJOURDHUI)
    assert [a["offre_id"] for a in alt] == ["pro_a"]                        # ni Max, ni Google (autre service)
    assert alt[0]["economie_par_mois"] == 3.60 and alt[0]["economie_par_an"] == 43.20
    assert alt[0]["paiement_d_avance"] == 216.00


def test_offre_groupee_b_and_you():
    """Pack 17,99 € contre ligne téléphone 6,99 € + Prime étudiant 3,49 € = 10,48 € → surcoût 7,51 €/mois."""
    lignes = [{"nom": "Prixtel · Téléphone", "prix": 6.99, "go": 40},
              {"nom": "Prixtel · Routeur 4G", "prix": 11.99, "go": 200}]
    g = c.groupees(lignes, {"Prixtel", "Amazon Prime"}, TOUTES, PAR_ID, PROFIL, AUJOURDHUI)
    assert len(g) == 1
    assert g[0]["cout_actuel"] == 10.48 and g[0]["ecart_par_mois"] == 7.51
    assert g[0]["remplace"][0]["ligne"] == "Prixtel · Téléphone" and g[0]["go_en_plus"] == 130
    # Sans Prime chez le propriétaire, le Prime inclus ne remplace rien : 17,99 − 6,99 = 11,00 €.
    sans_prime = c.groupees(lignes, {"Prixtel"}, TOUTES, PAR_ID, PROFIL, AUJOURDHUI)
    assert sans_prime[0]["ecart_par_mois"] == 11.00


def test_service_propose():
    assert c.service_propose("Forfait mobile Prixtel", SERVICES)["id"] == "prixtel"
    assert c.service_propose("AMAZON PRIME FR", SERVICES)["id"] == "prime"
    assert c.service_propose("Anthropic (Claude)", SERVICES)["id"] == "claude"
    assert c.service_propose("Google AI plus", SERVICES)["id"] == "google"
    assert c.service_propose("Assurance auto", SERVICES) is None


def test_comparer_lignes_et_rattachement():
    etats = [
        {"id": "a1", "nom": "Forfait mobile Prixtel", "par_mois": 15.65, "statut": "actif"},
        {"id": "a2", "nom": "AMAZON PRIME FR", "par_mois": 6.99, "statut": "actif"},
        {"id": "a3", "nom": "Orange", "par_mois": 15.99, "statut": "resilie"},
    ]
    lignes = [{"id": "l1", "subscription_id": "a2", "nom": "Prime", "catalog_offer_id": "prime_m", "prix": None,
               "go": None}]
    ecran = c.comparer(etats, lignes, SERVICES, TOUTES, PROFIL, AUJOURDHUI)
    noms = [a["nom"] for a in ecran["abonnements"]]
    assert noms == ["Forfait mobile Prixtel", "AMAZON PRIME FR"]            # résilié absent
    prixtel, prime = ecran["abonnements"]
    assert not prixtel["rattache"] and prixtel["service_propose"]["nom"] == "Prixtel"
    assert prime["rattache"] and prime["lignes"][0]["prix"] == 6.99         # ligne unique : ce qui est payé
    assert prime["lignes"][0]["alternatives"][0]["offre_id"] == "prime_e"


def test_profil_depuis_settings():
    assert c.profil_depuis([{"key": "profil_etudiant", "value": "true"}]) == {"etudiant": True, "moins_26": False, "age_18_24": False}
