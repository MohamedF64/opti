"""Changer de catégorie, retenu par marchand : docs/regles-de-calcul.md § 9."""
import asyncio
import os
import sys
from pathlib import Path

from fastapi.testclient import TestClient

os.environ.setdefault("SUPABASE_URL", "https://exemple.supabase.co")
os.environ.setdefault("OWNER_USER_ID", "11111111-2222-4333-8444-555555555555")
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

import categories  # noqa: E402
import index  # noqa: E402
import synchro as s  # noqa: E402

CA_ATTENTE = {"id": "a", "amount": -23.98, "merchant": "C ET A FRANCE paris 15e", "category": "Autre",
              "status": "pending", "is_internal": False}
CA_AOUT = {"id": "b", "amount": -5.99, "merchant": "C ET A FRANCE", "description": "C ET A FRANCE (Paris)",
           "category": "Autre", "status": "booked", "is_internal": False}
KISS = {"id": "c", "amount": -43.89, "merchant": "Maison Durand", "category": "Autre", "status": "pending",
        "is_internal": False}


def test_meme_marchand_quand_un_nom_commence_par_l_autre():
    assert s.meme_marchand("c et a france paris e", "c et a france")
    assert s.meme_marchand("maison durand", "maison durand")
    assert not s.meme_marchand("maison durand", "c et a france")
    assert not s.meme_marchand("g", "g sport")          # moins de 5 caractères : pas assez pour conclure


def test_dépenses_du_marchand_reclassées_sauf_entrées_et_internes():
    remboursement = {**CA_AOUT, "id": "d", "amount": 5.99}
    interne = {**CA_AOUT, "id": "e", "is_internal": True}
    deja = {**CA_AOUT, "id": "f", "category": "Shopping"}
    ops = [CA_ATTENTE, CA_AOUT, KISS, remboursement, interne, deja]
    assert categories.a_reclasser("c et a france paris e", "Shopping", ops) == ["a", "b"]


def test_la_synchro_applique_le_choix_avant_l_historique_et_les_mots_cles():
    historique = {"c et a france": "Autre", "maison durand": "Restauration"}
    regles = {"c et a france paris e": "Shopping", "maison durand": "Alimentation"}
    assert s.categoriser("C ET A FRANCE (Paris)", "C ET A FRANCE", -12.99, historique, regles) == "Shopping"
    assert s.categoriser("Maison Durand", "Maison Durand", -20.00, historique, regles) == "Alimentation"
    # Un remboursement du marchand n'est pas concerné.
    assert s.categoriser("Maison Durand", "Maison Durand", 20.00, {}, regles) == "Virement reçu"
    # La règle la plus précise gagne.
    assert s.regle_pour("c et a france paris e", {"c et a": "Loisirs", "c et a france": "Shopping"}) == "Shopping"


class FausseBase:
    def __init__(self, transactions, regles=None):
        self.transactions = {t["id"]: dict(t) for t in transactions}
        self.regles = dict(regles or {})

    async def select(self, table, **f):
        if table == "merchant_categories":
            return [{"cle": k, "categorie": v} for k, v in self.regles.items()]
        return [t for i, t in self.transactions.items() if f.get("id") == f"eq.{i}"]

    async def select_tout(self, table, **f):
        return list(self.transactions.values())

    async def update(self, table, valeurs, id):
        ids = id[4:-1].split(",") if id.startswith("in.") else [id[3:]]
        for i in ids:
            self.transactions[i].update(valeurs)

    async def upsert(self, table, ligne):
        self.regles[ligne["cle"]] = ligne["categorie"]

    async def delete(self, table, cle):
        self.regles.pop(cle[3:])


def test_retenir_reclasse_tout_le_marchand_et_remplace_l_ancienne_regle(monkeypatch):
    base = FausseBase([CA_ATTENTE, CA_AOUT, KISS], regles={"c et a france": "Vêtements"})
    monkeypatch.setattr(categories, "db", base)
    r = asyncio.run(categories.changer("a", "Shopping", retenir=False))   # en attente : forcément retenu
    assert r == {"categorie": "Shopping", "retenu": True, "modifiees": 2}
    assert base.regles == {"c et a france paris e": "Shopping"}
    assert [t["category"] for t in base.transactions.values()] == ["Shopping", "Shopping", "Autre"]


def test_sans_retenir_seule_cette_depense_change(monkeypatch):
    base = FausseBase([CA_ATTENTE, CA_AOUT])
    monkeypatch.setattr(categories, "db", base)
    assert asyncio.run(categories.changer("b", "Shopping", retenir=False))["modifiees"] == 1
    assert base.regles == {} and base.transactions["a"]["category"] == "Autre"


def test_refus_metier(monkeypatch):
    monkeypatch.setattr(categories, "db", FausseBase([{**CA_AOUT, "amount": 5.99}]))
    for args, message in ((("b", "Salaire", True), "Catégorie inconnue."),
                          (("b", "Shopping", True), "Seules les dépenses changent de catégorie."),
                          (("z", "Shopping", True), "Opération introuvable.")):
        try:
            asyncio.run(categories.changer(*args))
            raise AssertionError("refus attendu")
        except categories.ActionRefusee as e:
            assert str(e) == message


def test_route_exige_la_session():
    client = TestClient(index.app)
    r = client.post("/operations/00000000-0000-0000-0000-000000000000/categorie", json={"categorie": "Shopping"})
    assert r.status_code == 401
