"""Objectifs d'épargne — voir docs/regles-de-calcul.md § 5 (validé le 30/10/2026).

Trois notions (correction validée par Mohamed le 31/10/2026) :
- **versé = disponible** : ce qui est dans la tirelire pour l'objectif (versements − reprises confirmés).
- **dépensé** : les dépenses rattachées à l'objectif. Elles ne retirent rien de la tirelire : l'argent
  en est déjà sorti quand il a été repris (sinon l'Airbnb d'un voyage serait compté deux fois).
- **épargne totale** : ce qui fait avancer l'objectif. Projet : tirelire + dépensé (payer le projet ne le
  fait pas reculer). Imprévus : la tirelire seule (un coussin à garder plein, à reremplir après une urgence).
"""
import asyncio
import math
from dataclasses import asdict, dataclass
from datetime import date, datetime, timedelta, timezone
from typing import Any

import db
import erreurs

JOURS_PAR_MOIS = 30.4
RYTHME_JOURS_MIN, RYTHME_JOURS_MAX = 30, 90


@dataclass
class EtatObjectif:
    id: str
    nom: str
    type: str                          # « projet » ou « imprevus »
    icone: str | None
    statut: str                        # « active » ou « archive »
    cible: float
    echeance: date | None
    verse: float
    depense: float                     # dépenses rattachées (positif)
    epargne_totale: float              # projet : tirelire + dépensé ; Imprévus : tirelire
    disponible: float
    en_attente: float                  # versements déclarés, virement pas encore vu
    reste: float
    progression: float                 # 0 à 1
    atteint: bool
    jours_restants: int | None         # None : pas d'échéance, ou échéance passée
    par_jour: float | None
    par_semaine: float | None
    par_mois: float | None
    rythme_mensuel: float              # moyenne des versements confirmés récents, ramenée au mois
    rythme_connu: bool                 # au moins 30 jours depuis le premier versement confirmé
    premier_versement: date | None
    date_estimee: date | None          # à ce rythme
    faisabilite: int | None            # 0 à 100 ; None sans échéance ou échéance passée
    echeance_depassee: bool
    echeance_suggeree: date | None     # quand l'échéance est passée : la date « à ton rythme »


def _jour(valeur: Any) -> date:
    return date.fromisoformat(str(valeur)[:10])


def _date_du_mouvement(m: dict[str, Any]) -> date:
    return _jour(m.get("confirmed_at") or m["created_at"])


def calculer(objectif: dict[str, Any], mouvements: list[dict[str, Any]],
             depenses_rattachees: list[dict[str, Any]], aujourdhui: date) -> EtatObjectif:
    """État d'un objectif à partir de ses mouvements et des opérations rattachées (montants signés)."""
    confirmes = [m for m in mouvements if m.get("status") == "confirme"]
    verse = round(sum(float(m["amount"]) for m in confirmes), 2)
    en_attente = round(sum(float(m["amount"]) for m in mouvements if m.get("status") == "en_attente"), 2)
    depense = round(-sum(float(t["amount"]) for t in depenses_rattachees), 2)
    cible = float(objectif["target_amount"] or 0)
    imprevus = objectif.get("kind") == "imprevus"
    epargne_totale = verse if imprevus else round(verse + depense, 2)
    reste = round(max(cible - epargne_totale, 0), 2)
    atteint = cible > 0 and reste == 0

    # Rythme : versements confirmés sur les 90 derniers jours, ou depuis la création de l'objectif
    # (30 jours au moins, pour qu'un premier versement ne compte pas comme un rythme énorme).
    cree_le = _jour(objectif["created_at"]) if objectif.get("created_at") else aujourdhui
    fenetre = min(max((aujourdhui - cree_le).days, RYTHME_JOURS_MIN), RYTHME_JOURS_MAX)
    recents = sum(float(m["amount"]) for m in confirmes if (aujourdhui - _date_du_mouvement(m)).days < fenetre)
    rythme_jour = max(recents, 0) / fenetre
    # Avant un mois d'historique, le rythme ne veut rien dire (10 € versés hier ≠ 10 €/mois) :
    # ni date estimée, ni faisabilité, ni échéance suggérée.
    premier = min((_date_du_mouvement(m) for m in confirmes), default=None)
    rythme_connu = premier is not None and (aujourdhui - premier).days >= RYTHME_JOURS_MIN
    date_estimee = None
    if rythme_connu and reste > 0 and rythme_jour > 0:
        date_estimee = aujourdhui + timedelta(days=math.ceil(reste / rythme_jour))

    echeance = _jour(objectif["deadline"]) if objectif.get("deadline") else None
    actif = (objectif.get("status") or "active") == "active"
    echeance_depassee = actif and echeance is not None and echeance < aujourdhui and not atteint
    jours = par_jour = par_semaine = par_mois = faisabilite = None
    if actif and echeance is not None and not echeance_depassee:
        jours = max((echeance - aujourdhui).days, 1)
        besoin_jour = reste / jours
        par_jour, par_semaine, par_mois = (round(besoin_jour * n, 2) for n in (1, 7, JOURS_PAR_MOIS))
        if besoin_jour == 0:
            faisabilite = 100
        elif rythme_connu:
            faisabilite = min(100, round(rythme_jour / besoin_jour * 100))

    return EtatObjectif(
        id=objectif["id"], nom=objectif["name"], type=objectif.get("kind") or "projet",
        icone=objectif.get("icon"), statut=objectif.get("status") or "active",
        cible=cible, echeance=echeance, verse=verse, depense=depense, epargne_totale=epargne_totale,
        disponible=verse, en_attente=en_attente, reste=reste,
        progression=1.0 if atteint else (round(max(epargne_totale, 0) / cible, 4) if cible > 0 else 0.0),
        atteint=atteint,
        jours_restants=jours, par_jour=par_jour, par_semaine=par_semaine, par_mois=par_mois,
        rythme_mensuel=round(rythme_jour * JOURS_PAR_MOIS, 2), rythme_connu=rythme_connu,
        premier_versement=premier, date_estimee=date_estimee,
        faisabilite=faisabilite, echeance_depassee=echeance_depassee,
        echeance_suggeree=date_estimee if echeance_depassee else None,
    )


async def objectifs_du_moment(aujourdhui: date) -> list[EtatObjectif]:
    """Tous les objectifs (actifs d'abord), calculés sur les données de Mohamed."""
    objectifs, mouvements, rattachees = await asyncio.gather(
        db.select("goals", order="created_at.asc"),
        db.select("goal_movements", limit="10000"),
        db.select("transactions", select="goal_id,amount", goal_id="not.is.null", limit="10000"),
    )
    etats = [
        calculer(o, [m for m in mouvements if m["goal_id"] == o["id"]],
                 [t for t in rattachees if t["goal_id"] == o["id"]], aujourdhui)
        for o in objectifs
    ]
    return sorted(etats, key=lambda e: (e.statut != "active", e.type != "imprevus"))


# ── Reconnaissance des virements vers / depuis la réserve « Économies » ─────────

AVANT_DECLARATION_JOURS, APRES_DECLARATION_JOURS = 2, 7


def rapprocher_versements(mouvements: list[dict[str, Any]], operations_reserve: list[dict[str, Any]],
                          depuis: date) -> list[tuple[str, str]]:
    """(versement, opération) à relier. Un versement en attente est reconnu par une opération de la
    réserve de même montant signé (+ versement, − retrait), datée de 2 jours avant à 7 jours après la
    déclaration, jamais contestée pour ce versement, ni déjà utilisée par un autre. Les plus anciennes
    déclarations choisissent d'abord, chacune l'opération la plus proche en date.
    Un versement confirmé à la main sans opération est relié de la même façon, sinon son virement
    resterait « à attribuer » et serait compté deux fois."""
    utilisees = {m["transaction_id"] for m in mouvements if m.get("transaction_id")}
    candidates = [t for t in operations_reserve if t.get("status") != "pending" and _jour(t["date"]) >= depuis]
    paires = []
    a_relier = [m for m in mouvements if m.get("status") == "en_attente" or not m.get("transaction_id")]
    for m in sorted(a_relier, key=lambda m: str(m["created_at"])):
        declare = _jour(m["created_at"])
        refusees = set(m.get("rejected_transaction_ids") or [])
        possibles = [t for t in candidates
                     if t["id"] not in utilisees and t["id"] not in refusees
                     and abs(float(t["amount"]) - float(m["amount"])) < 0.005
                     and -AVANT_DECLARATION_JOURS <= (_jour(t["date"]) - declare).days <= APRES_DECLARATION_JOURS]
        if possibles:
            t = min(possibles, key=lambda t: abs((_jour(t["date"]) - declare).days))
            utilisees.add(t["id"])
            paires.append((m["id"], t["id"]))
    return paires


def operations_a_attribuer(mouvements: list[dict[str, Any]], operations_reserve: list[dict[str, Any]],
                           depuis: date) -> list[dict[str, Any]]:
    """Opérations de la réserve qu'aucun versement n'explique : « 150 € arrivés : pour quel objectif ? »."""
    utilisees = {m["transaction_id"] for m in mouvements if m.get("transaction_id")}
    return [t for t in operations_reserve
            if t.get("status") != "pending" and _jour(t["date"]) >= depuis and t["id"] not in utilisees]


SEUIL_SUGGESTION = 100.0


def suggestions_rattachement(operations: list[dict[str, Any]], etats: list[EtatObjectif],
                             depuis: date) -> list[dict[str, Any]]:
    """« Rattacher à un projet ? » : dépenses comptabilisées de plus de 100 € depuis le départ des objectifs,
    pas encore rattachées ni écartées par Mohamed, quand au moins un projet actif a assez de disponible."""
    projets = [e for e in etats if e.statut == "active" and e.type == "projet"]
    resultat = []
    for t in operations:
        montant = -float(t["amount"])
        if (montant < SEUIL_SUGGESTION or t.get("is_internal") or t.get("goal_id") or t.get("suggestion_ignoree")
                or t.get("status") == "pending" or _jour(t["date"]) < depuis):
            continue
        possibles = [e.id for e in projets if e.disponible + 0.005 >= montant]
        if possibles:
            resultat.append({"id": t["id"], "date": _jour(t["date"]), "montant": float(t["amount"]),
                             "libelle": t.get("merchant") or t.get("description") or "", "objectifs": possibles})
    return sorted(resultat, key=lambda s: s["date"], reverse=True)


# ── Reprises de la tirelire suivies jusqu'aux dépenses (étape 6) ─────────────

CHAINE_ECART_JOURS = 2      # reprise → arrivée sur le compte principal → virement vers le CIC
DEPENSES_JOURS = 3          # dépenses regardées après l'arrivée de l'argent


def _proche(operations: list[dict[str, Any]], montant: float, autour: date, avant: int, apres: int):
    possibles = [t for t in operations if abs(float(t["amount"]) - montant) < 0.005
                 and -avant <= (_jour(t["date"]) - autour).days <= apres]
    return min(possibles, key=lambda t: abs((_jour(t["date"]) - autour).days), default=None)


def chaines_de_retrait(retraits: list[dict[str, Any]], operations: list[dict[str, Any]],
                       mouvements: list[dict[str, Any]], depuis: date) -> list[dict[str, Any]]:
    """Pour chaque reprise de la réserve pas encore traitée, suit l'argent (réserve → Revolut, puis
    éventuellement Revolut → CIC, même montant à ± 2 jours) et regarde les dépenses comptabilisées des
    3 jours suivants sur le compte d'arrivée. Question posée si elles font au moins la moitié de la reprise ;
    les plus grosses qui tiennent dans le montant repris sont cochées d'avance."""
    liens = {m["transaction_id"]: m for m in mouvements if m.get("transaction_id")}
    deja_proposees: set[str] = set()
    questions = []
    for w in sorted(retraits, key=lambda t: str(t["date"])):
        montant = -float(w["amount"])
        if (montant <= 0 or w.get("status") == "pending" or w.get("suggestion_ignoree")
                or w.get("reserve_annulee") or _jour(w["date"]) < depuis):
            continue
        jour = _jour(w["date"])
        arrivee, debut = "Revolut", jour
        vers_cic = _proche([t for t in operations if t.get("bank_name") == "CIC"], montant, jour,
                           0, CHAINE_ECART_JOURS)
        if vers_cic is not None:
            arrivee, debut = "CIC", _jour(vers_cic["date"])
        depenses = [t for t in operations
                    if t.get("bank_name") == arrivee and not t.get("is_internal") and not t.get("goal_id")
                    and float(t["amount"]) < 0 and t.get("status") != "pending" and t["id"] not in deja_proposees
                    and 0 <= (_jour(t["date"]) - debut).days <= DEPENSES_JOURS]
        total = -sum(float(t["amount"]) for t in depenses)
        if not depenses or total < montant / 2:
            continue
        cochees, cumul = set(), 0.0
        for t in sorted(depenses, key=lambda t: float(t["amount"])):      # les plus grosses d'abord
            if cumul - float(t["amount"]) <= montant + 0.005:
                cochees.add(t["id"])
                cumul -= float(t["amount"])
        if not cochees:
            cochees.add(min(depenses, key=lambda t: float(t["amount"]))["id"])
        deja_proposees.update(t["id"] for t in depenses)
        lien = liens.get(w["id"])
        questions.append({
            "id": w["id"], "date": jour, "montant": montant, "arrivee": arrivee,
            "objectif_id": lien["goal_id"] if lien else None,
            "depenses": [{"id": t["id"], "date": _jour(t["date"]), "montant": float(t["amount"]),
                          "libelle": t.get("merchant") or t.get("description") or "", "cochee": t["id"] in cochees}
                         for t in sorted(depenses, key=lambda t: str(t["date"]))],
        })
    return questions


ANNULATION_CANDIDATS_MAX = 12


def versements_a_annuler(retrait: dict[str, Any], mouvements: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """« C'était une annulation » : les versements confirmés, antérieurs au retrait, dont la somme fait
    exactement le montant repris. Parmi les combinaisons possibles, les versements les plus récents
    d'abord. Liste vide si aucune combinaison ne tombe juste."""
    cible = round(-float(retrait["amount"]), 2)
    jour = _jour(retrait["date"])
    candidats = sorted((m for m in mouvements if m.get("status") == "confirme" and float(m["amount"]) > 0
                        and _date_du_mouvement(m) <= jour),
                       key=lambda m: str(m.get("confirmed_at") or m["created_at"]), reverse=True)
    candidats = candidats[:ANNULATION_CANDIDATS_MAX]

    def chercher(debut: int, reste: float, choisis: list[dict[str, Any]]) -> list[dict[str, Any]] | None:
        if abs(reste) < 0.005:
            return choisis
        for i in range(debut, len(candidats)):
            montant = float(candidats[i]["amount"])
            if montant <= reste + 0.005:
                trouve = chercher(i + 1, round(reste - montant, 2), choisis + [candidats[i]])
                if trouve is not None:
                    return trouve
        return None

    return (chercher(0, cible, []) or []) if cible > 0 else []


async def _reserve_et_depart() -> tuple[list[dict[str, Any]], date]:
    reglage, comptes = await asyncio.gather(
        db.select("settings", key="eq.objectifs_depuis"),
        db.select("bank_accounts", select="id", account_type="eq.savings"),
    )
    depuis = _jour(reglage[0]["value"]) if reglage else date.today()
    if not comptes:
        return [], depuis
    ids = ",".join(c["id"] for c in comptes)
    operations = await db.select("transactions", select="id,date,amount,status,description,suggestion_ignoree",
                                 bank_account_id=f"in.({ids})", date=f"gte.{depuis.isoformat()}",
                                 reserve_annulee="eq.false", limit="5000")
    return operations, depuis


async def _operations_hors_reserve(depuis: date) -> list[dict[str, Any]]:
    """Opérations des comptes courants (CIC, Revolut principal) depuis le départ des objectifs."""
    comptes, operations = await asyncio.gather(
        db.select("bank_accounts", select="id", account_type="eq.savings"),
        db.select("transactions", select="id,date,amount,bank_name,bank_account_id,is_internal,goal_id,status,"
                                         "merchant,description", date=f"gte.{depuis.isoformat()}", limit="5000"),
    )
    reserve = {c["id"] for c in comptes}
    return [t for t in operations if t.get("bank_account_id") not in reserve]


async def confirmer_versements() -> int:
    """Appelée après chaque synchro : confirme les versements dont le virement est arrivé, et relie
    à leur virement ceux déjà confirmés à la main."""
    operations, depuis = await _reserve_et_depart()
    mouvements = await db.select("goal_movements", limit="10000")
    statuts = {m["id"]: m["status"] for m in mouvements}
    paires = rapprocher_versements(mouvements, operations, depuis)
    for mouvement_id, transaction_id in paires:
        valeurs: dict[str, Any] = {"transaction_id": transaction_id}
        if statuts[mouvement_id] == "en_attente":
            valeurs |= {"status": "confirme", "confirmed_at": datetime.now(timezone.utc).isoformat()}
        await db.update("goal_movements", valeurs, id=f"eq.{mouvement_id}")
    return len(paires)


# ── Actions de l'app ──────────────────────────────────────────────────────────

RAPPEL_JOURS = 7


class ActionRefusee(erreurs.ActionRefusee):
    """Action impossible dans l'état actuel (message affichable tel quel)."""


def _mouvement_pour_app(m: dict[str, Any], aujourdhui: date) -> dict[str, Any]:
    declare = _jour(m["created_at"])
    return {
        "id": m["id"], "montant": float(m["amount"]), "statut": m["status"], "note": m.get("note"),
        "declare_le": declare, "confirme_le": _jour(m["confirmed_at"]) if m.get("confirmed_at") else None,
        "reconnu_automatiquement": bool(m.get("transaction_id")),
        "rappel": m["status"] == "en_attente" and (aujourdhui - declare).days >= RAPPEL_JOURS,
    }


async def ecran_objectifs(aujourdhui: date) -> dict[str, Any]:
    """Tout ce qu'affiche l'écran Objectifs (après avoir relié les virements déjà synchronisés)."""
    await confirmer_versements()
    etats, mouvements, (operations, depuis), grosses_depenses, rattachees = await asyncio.gather(
        objectifs_du_moment(aujourdhui),
        db.select("goal_movements", order="created_at.desc", limit="10000"),
        _reserve_et_depart(),
        db.select("transactions", select="id,date,amount,merchant,description,status,is_internal,goal_id,suggestion_ignoree",
                  amount=f"lte.{-SEUIL_SUGGESTION}", goal_id="is.null", limit="1000"),
        db.select("transactions", select="id,date,amount,merchant,description,goal_id",
                  goal_id="not.is.null", order="date.desc", limit="1000"),
    )
    questions = chaines_de_retrait([t for t in operations if float(t["amount"]) < 0],
                                   await _operations_hors_reserve(depuis), mouvements, depuis)
    deja_posees = {q["id"] for q in questions}
    return {
        "reprises": questions,
        "objectifs": [{
            **asdict(e),
            "mouvements": [_mouvement_pour_app(m, aujourdhui) for m in mouvements if m["goal_id"] == e.id][:30],
            "depenses": [{"id": t["id"], "date": _jour(t["date"]), "montant": float(t["amount"]),
                          "libelle": t.get("merchant") or t.get("description") or ""}
                         for t in rattachees if t["goal_id"] == e.id][:30],
        } for e in etats],
        "suggestions": suggestions_rattachement(grosses_depenses, etats, depuis),
        # Une reprise suivie jusqu'à des dépenses est posée comme « reprise » plutôt que « à attribuer ».
        "a_attribuer": [{"id": t["id"], "date": _jour(t["date"]), "montant": float(t["amount"]),
                         "libelle": t.get("description")} for t in operations_a_attribuer(mouvements, operations, depuis)
                        if t["id"] not in deja_posees],
    }


async def _objectif(goal_id: str) -> dict[str, Any]:
    trouves = await db.select("goals", id=f"eq.{goal_id}")
    if not trouves:
        raise ActionRefusee("Objectif introuvable.")
    return trouves[0]


async def _mouvement(mouvement_id: str) -> dict[str, Any]:
    trouves = await db.select("goal_movements", id=f"eq.{mouvement_id}")
    if not trouves:
        raise ActionRefusee("Versement introuvable.")
    return trouves[0]


async def creer_objectif(nom: str, cible: float, echeance: date | None, icone: str | None) -> dict[str, Any]:
    lignes = await db.insert("goals", {"name": nom, "target_amount": cible, "kind": "projet", "status": "active",
                                       "deadline": echeance.isoformat() if echeance else None, "icon": icone})
    return lignes[0]


async def modifier_objectif(goal_id: str, valeurs: dict[str, Any]) -> dict[str, Any]:
    """Nom, cible, échéance (repousser), icône, statut (archiver / réactiver)."""
    objectif = await _objectif(goal_id)
    if objectif.get("kind") == "imprevus" and ("deadline" in valeurs or valeurs.get("status") == "archive"):
        raise ActionRefusee("Imprévus est permanent : pas d'échéance ni d'archivage.")
    if "deadline" in valeurs and valeurs["deadline"] is not None:
        valeurs["deadline"] = valeurs["deadline"].isoformat()
    return (await db.update("goals", valeurs, id=f"eq.{goal_id}"))[0]


async def declarer_mouvement(goal_id: str, montant: float, note: str | None) -> dict[str, Any]:
    """« Je mets 150 € de côté » (montant positif) ou « je pioche 200 € » (négatif), en attente du virement."""
    objectif = await _objectif(goal_id)
    if objectif.get("status") != "active":
        raise ActionRefusee("Cet objectif est archivé.")
    ligne = (await db.insert("goal_movements", {"goal_id": goal_id, "amount": round(montant, 2),
                                                "status": "en_attente", "note": note}))[0]
    await confirmer_versements()        # le virement a peut-être déjà été fait (jusqu'à 2 jours avant)
    return await _mouvement(ligne["id"])


async def confirmer_a_la_main(mouvement_id: str, transaction_id: str | None) -> dict[str, Any]:
    """« J'ai fait le virement » : sans opération (pas encore visible) ou en choisissant celle de la réserve."""
    m = await _mouvement(mouvement_id)
    if m["status"] != "en_attente":
        raise ActionRefusee("Ce versement est déjà confirmé.")
    if transaction_id:
        operations, _ = await _reserve_et_depart()
        if transaction_id not in {t["id"] for t in operations}:
            raise ActionRefusee("Cette opération n'est pas un mouvement de ta réserve.")
        if await db.select("goal_movements", transaction_id=f"eq.{transaction_id}"):
            raise ActionRefusee("Cette opération confirme déjà un autre versement.")
    return (await db.update("goal_movements", {"status": "confirme", "transaction_id": transaction_id,
                                               "confirmed_at": datetime.now(timezone.utc).isoformat()},
                            id=f"eq.{mouvement_id}"))[0]


async def contester(mouvement_id: str) -> dict[str, Any]:
    """« Ce n'est pas ce virement » : retour en attente, et ce virement ne lui sera plus proposé."""
    m = await _mouvement(mouvement_id)
    if m["status"] != "confirme":
        raise ActionRefusee("Ce versement n'est pas confirmé.")
    refusees = list(m.get("rejected_transaction_ids") or [])
    if m.get("transaction_id"):
        refusees.append(m["transaction_id"])
    return (await db.update("goal_movements", {"status": "en_attente", "transaction_id": None, "confirmed_at": None,
                                               "rejected_transaction_ids": refusees}, id=f"eq.{mouvement_id}"))[0]


async def annuler(mouvement_id: str) -> None:
    m = await _mouvement(mouvement_id)
    if m["status"] != "en_attente":
        raise ActionRefusee("Un versement confirmé ne s'annule pas : conteste-le d'abord.")
    await db.delete("goal_movements", id=f"eq.{mouvement_id}")


async def attribuer(transaction_id: str, goal_id: str) -> dict[str, Any]:
    """« 150 € arrivés dans ta tirelire : pour quel objectif ? » → versement confirmé d'office."""
    objectif = await _objectif(goal_id)
    if objectif.get("status") != "active":
        raise ActionRefusee("Cet objectif est archivé.")
    operations, depuis = await _reserve_et_depart()
    mouvements = await db.select("goal_movements", limit="10000")
    operation = next((t for t in operations_a_attribuer(mouvements, operations, depuis) if t["id"] == transaction_id), None)
    if operation is None:
        raise ActionRefusee("Cette opération n'est plus à attribuer.")
    return (await db.insert("goal_movements", {
        "goal_id": goal_id, "amount": float(operation["amount"]), "status": "confirme",
        "transaction_id": transaction_id, "confirmed_at": datetime.now(timezone.utc).isoformat(),
        "created_at": f"{operation['date']}T12:00:00+00:00",
    }))[0]


async def rattacher_depense(transaction_id: str, goal_id: str | None) -> dict[str, Any]:
    """Une dépense payée avec l'épargne d'un projet (None : la détacher)."""
    operations = await db.select("transactions", select="id,amount,is_internal,status", id=f"eq.{transaction_id}")
    if not operations:
        raise ActionRefusee("Opération introuvable.")
    if goal_id:
        objectif = await _objectif(goal_id)
        if objectif.get("status") != "active":
            raise ActionRefusee("Cet objectif est archivé.")
        if operations[0]["is_internal"] or float(operations[0]["amount"]) >= 0:
            raise ActionRefusee("Seule une dépense peut être rattachée à un objectif.")
        if operations[0]["status"] == "pending":
            # Une opération en attente est remplacée à chaque synchro : le rattachement serait perdu.
            raise ActionRefusee("Cette dépense est encore en attente : tu pourras la rattacher dès que la banque l'aura comptabilisée.")
    ligne = (await db.update("transactions", {"goal_id": goal_id}, id=f"eq.{transaction_id}",
                             select="id,goal_id"))[0]
    return ligne


async def ignorer_suggestion(transaction_id: str) -> None:
    """« Non, dépense normale » : la question n'est plus posée pour cette dépense."""
    if not await db.update("transactions", {"suggestion_ignoree": True}, id=f"eq.{transaction_id}", select="id"):
        raise ActionRefusee("Opération introuvable.")


async def _retrait_a_attribuer(transaction_id: str) -> dict[str, Any]:
    operations, depuis = await _reserve_et_depart()
    mouvements = await db.select("goal_movements", limit="10000")
    operation = next((t for t in operations_a_attribuer(mouvements, operations, depuis) if t["id"] == transaction_id), None)
    if operation is None or float(operation["amount"]) >= 0:
        raise ActionRefusee("Ce retrait n'est plus à attribuer.")
    return operation


async def proposer_annulation(transaction_id: str) -> list[dict[str, Any]]:
    """Les versements que ce retrait annulerait, pour que Mohamed les vérifie avant de valider."""
    retrait = await _retrait_a_attribuer(transaction_id)
    choisis = versements_a_annuler(retrait, await db.select("goal_movements", limit="10000"))
    if not choisis:
        montant = f"{-float(retrait['amount']):.2f}".replace(".", ",")
        raise ActionRefusee(f"Aucun ensemble de versements récents ne fait exactement {montant} €.")
    noms = {o["id"]: o["name"] for o in await db.select("goals", select="id,name")}
    return [{"id": m["id"], "objectif": noms.get(m["goal_id"], "?"), "montant": float(m["amount"]),
             "date": _date_du_mouvement(m), "note": m.get("note")} for m in choisis]


async def annuler_par_retrait(transaction_id: str, mouvement_ids: list[str]) -> int:
    """Supprime les versements annulés et retire de la réserve l'aller et le retour."""
    retrait = await _retrait_a_attribuer(transaction_id)
    attendus = versements_a_annuler(retrait, await db.select("goal_movements", limit="10000"))
    if sorted(m["id"] for m in attendus) != sorted(mouvement_ids):
        raise ActionRefusee("La situation a changé : rouvre l'écran et réessaie.")
    operations = [transaction_id] + [m["transaction_id"] for m in attendus if m.get("transaction_id")]
    await db.delete("goal_movements", id=f"in.({','.join(mouvement_ids)})")
    await db.update("transactions", {"reserve_annulee": True}, id=f"in.({','.join(operations)})")
    return len(mouvement_ids)


async def repondre_reprise(transaction_id: str, goal_id: str | None, depense_ids: list[str]) -> None:
    """« Tu as repris 200 € de ta tirelire… C'était pour : » — objectif choisi : la reprise lui est attribuée
    (si elle ne l'était pas) et les dépenses cochées lui sont rattachées. None : « Non, dépense normale »
    (la reprise reste à attribuer si elle ne l'était pas). Dans les deux cas, la question n'est plus posée."""
    (operations, depuis), mouvements = await asyncio.gather(_reserve_et_depart(),
                                                            db.select("goal_movements", limit="10000"))
    questions = chaines_de_retrait([t for t in operations if float(t["amount"]) < 0],
                                   await _operations_hors_reserve(depuis), mouvements, depuis)
    question = next((q for q in questions if q["id"] == transaction_id), None)
    if question is None:
        raise ActionRefusee("Cette reprise n'est plus en question : rouvre l'écran.")
    if goal_id:
        objectif = await _objectif(goal_id)
        if objectif.get("status") != "active":
            raise ActionRefusee("Cet objectif est archivé.")
        if question["objectif_id"] and question["objectif_id"] != goal_id:
            raise ActionRefusee("Cette reprise est déjà attribuée à un autre objectif.")
        proposees = {d["id"] for d in question["depenses"]}
        if not depense_ids or not set(depense_ids) <= proposees:
            raise ActionRefusee("Coche au moins une des dépenses proposées.")
        if not question["objectif_id"]:
            await db.insert("goal_movements", {
                "goal_id": goal_id, "amount": -question["montant"], "status": "confirme",
                "transaction_id": transaction_id, "confirmed_at": datetime.now(timezone.utc).isoformat(),
                "created_at": f"{question['date'].isoformat()}T12:00:00+00:00",
            })
        await db.update("transactions", {"goal_id": goal_id}, id=f"in.({','.join(depense_ids)})", select="id")
    await db.update("transactions", {"suggestion_ignoree": True}, id=f"eq.{transaction_id}", select="id")

