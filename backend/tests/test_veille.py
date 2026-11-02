"""Surveillance des pages de prix et notifications du catalogue : exemples de docs/regles-de-calcul.md § 12."""
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

import notifications as n  # noqa: E402
import veille as v  # noqa: E402

TOUS = set(n.TYPES)


def test_montants_de_page():
    page = """<html><style>.p{content:"99 €"}</style><script>var x = "12,00 €";</script>
    <p>Le petit à partir de 6,99€ /mois</p><p>Oxygène&nbsp;9,99&nbsp;€</p>
    <div>Forfait Free 5G+ 350 Go 19 €99 /mois</div><span>69,90 € par an</span><b>Prix 9.99 €</b>
    <i>10 € de remise</i></html>"""
    assert v.montants_de_page(page) == [6.99, 9.99, 10.0, 19.99, 69.9]


def test_page_inchangee_modifiee_puis_stable():
    """01/10 : {9,99 ; 19,99} ; 01/11 : {10,99 ; 19,99} → modifiée ; 01/12 : pareil → rien de plus."""
    assert v.nouvel_etat([9.99, 19.99], [9.99, 19.99], "ok") == ("ok", False)
    assert v.nouvel_etat([9.99, 19.99], [10.99, 19.99], "ok") == ("modifiee", True)
    assert v.nouvel_etat([10.99, 19.99], [10.99, 19.99], "modifiee") == ("modifiee", False)


def test_premiere_lecture_et_page_illisible():
    assert v.nouvel_etat(None, [9.99], "ok") == ("ok", False)          # référence, pas de notification
    assert v.nouvel_etat([9.99], [], "ok") == ("illisible", False)


def test_jour_de_veille():
    assert v.jour_de_veille(datetime(2026, 12, 1, 7, 0, tzinfo=timezone.utc))        # 8 h à Paris
    assert not v.jour_de_veille(datetime(2026, 12, 1, 11, 0, tzinfo=timezone.utc))   # 12 h
    assert not v.jour_de_veille(datetime(2026, 12, 2, 7, 0, tzinfo=timezone.utc))


def _notifs(maintenant, **kw):
    return n.a_envoyer(maintenant, [], None, None, [], set(), TOUS, **kw)


def test_notification_page_modifiee():
    page = {"id": "prixtel", "page_modifiee_le": "2026-12-01T07:00:00+00:00"}
    envois = _notifs(datetime(2026, 12, 1, 7, 0, tzinfo=timezone.utc), pages=[page])
    assert [(e.type, e.texte, e.ecran) for e in envois] == [
        ("catalogue", "Une page de prix a changé. Ouvre Opti pour vérifier.", "catalogue")]
    deja = {envois[0].cle}
    assert n.a_envoyer(datetime(2026, 12, 1, 11, 0, tzinfo=timezone.utc), [], None, None, [], deja, TOUS,
                       pages=[page]) == []


def test_veille_des_soldes_et_du_black_friday():
    """Black Friday 2026 : notification le 26/11 à 12 h. Soldes d'hiver le 06/01/2027 : le 05/01 à 12 h."""
    evenements = [{"nom": "Black Friday", "debut": "2026-11-27"}, {"nom": "Soldes d'hiver", "debut": "2027-01-06"}]
    midi = datetime(2026, 11, 26, 11, 0, tzinfo=timezone.utc)
    assert [e.texte for e in _notifs(midi, evenements=evenements)] == [
        "Le Black Friday commence demain. Ouvre Opti pour voir ta marge ce mois-ci."]
    assert _notifs(datetime(2026, 11, 26, 7, 0, tzinfo=timezone.utc), evenements=evenements) == []   # 8 h
    soldes = _notifs(datetime(2027, 1, 5, 11, 0, tzinfo=timezone.utc), evenements=evenements)
    assert soldes[0].texte.startswith("Les soldes d'hiver commencent demain.") and soldes[0].ecran == "accueil"


def test_interrupteurs_catalogue_et_promos():
    page = {"id": "p", "page_modifiee_le": "x"}
    assert n.a_envoyer(datetime(2026, 12, 1, 7, 0, tzinfo=timezone.utc), [], None, None, [], set(),
                       TOUS - {"catalogue"}, pages=[page]) == []
