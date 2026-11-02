"""« Tu peux encore dépenser X € aujourd'hui » — voir docs/regles-de-calcul.md (validé le 30/10/2026).

Deux parties :
- `calculer(...)` : calcul pur à partir de données déjà chargées, entièrement testable ;
- `budget_du_jour()` : charge les données de Mohamed dans la base puis appelle `calculer`.
"""
import asyncio
import calendar
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo

import abonnements as abos
import db

PARIS = ZoneInfo("Europe/Paris")
REVENUS = ("Salaire", "Virement reçu")
ESSENTIEL = ("Alimentation",)      # cycle dépassé : la limite devient les courses habituelles par jour
CYCLES_ESSENTIEL = 3
INTERVALLES_JOURS = {"hebdomadaire": 7, "bimensuel": 14, "mensuel": 30, "mois": 30, "trimestriel": 91, "annuel": 365}


@dataclass
class Abonnement:
    nom: str
    montant: float
    frequence: str
    dernier_prelevement: date | None
    mois_pause: list[int] = field(default_factory=list)   # Imagine R : juillet, août, septembre
    premier_prelevement: date | None = None   # essai gratuit : prélèvement attendu à la fin de l'essai


@dataclass
class Reglages:
    jour_paie_min: int = 21
    jour_paie_max: int = 28
    limite_manuelle: float | None = None
    mode_economies_max: bool = False
    epargne_visee: float | None = None


@dataclass
class Ligne:
    libelle: str
    montant: float


@dataclass
class Budget:
    debut_cycle: date
    paie: float
    paie_au_plus_tot: date
    paie_au_plus_tard: date
    paie_en_retard: bool
    jours_restants: int
    epargne_visee: float
    source_epargne: str
    abonnements_a_venir: list[dict[str, Any]]
    depense_avant_aujourdhui: float
    depense_aujourdhui: float
    reste_du_cycle: float
    limite_calculee: float
    limite_du_jour: float
    tu_peux_encore: float
    limite_appliquee: str              # « calculee », « plancher », « plafond » ou « essentiel »
    effet_limite_manuelle: float       # € retirés (+) ou ajoutés (−) à chacun des jours suivants
    pourquoi: list[Ligne] = field(default_factory=list)
    epargne_proposee: float = 0.0      # ce que proposent les objectifs (affiché dans les Réglages)
    depassement: float = 0.0           # cycle dépassé : de combien (reste du cycle négatif), sinon 0


# ── Cycle de paie ──────────────────────────────────────────────────────────────

def _mois_suivant(d: date, jour: int) -> date:
    annee, mois = (d.year + 1, 1) if d.month == 12 else (d.year, d.month + 1)
    return date(annee, mois, min(jour, calendar.monthrange(annee, mois)[1]))


def derniere_paie(operations: list[dict[str, Any]], aujourdhui: date) -> tuple[date, float] | None:
    """Date et montant de la dernière paie reçue (plusieurs virements le même jour sont additionnés)."""
    paies: dict[date, float] = {}
    for o in operations:
        jour = _jour(o)
        if o.get("category") == "Salaire" and float(o["amount"]) > 0 and jour <= aujourdhui:
            paies[jour] = paies.get(jour, 0.0) + float(o["amount"])
    if not paies:
        return None
    jour = max(paies)
    return jour, round(paies[jour], 2)


def _jour(o: dict[str, Any]) -> date:
    return o["date"] if isinstance(o["date"], date) else date.fromisoformat(str(o["date"])[:10])


# ── Dépenses ──────────────────────────────────────────────────────────────────

def compte_comme_depense(o: dict[str, Any]) -> bool:
    """Sorties vers l'extérieur et remboursements ; ni épargne interne, ni revenus, ni dépenses de projet."""
    if o.get("is_internal") or o.get("goal_id"):
        return False
    if float(o["amount"]) > 0 and o.get("category") in REVENUS:
        return False
    return True


def depense(operations: list[dict[str, Any]]) -> float:
    """Montant dépensé, en positif (les remboursements le réduisent)."""
    return round(-sum(float(o["amount"]) for o in operations if compte_comme_depense(o)), 2)


def essentiel_par_jour(operations: list[dict[str, Any]], debut: date) -> float | None:
    """Courses habituelles par jour (Alimentation) sur les 3 cycles terminés avant `debut` ;
    None sans cycle terminé ou sans courses."""
    paies = sorted({_jour(o) for o in operations
                    if o.get("category") == "Salaire" and float(o["amount"]) > 0 and _jour(o) < debut})
    if not paies:
        return None
    depuis = paies[-CYCLES_ESSENTIEL:][0]
    total = depense([o for o in operations if depuis <= _jour(o) < debut and o.get("category") in ESSENTIEL])
    jours = (debut - depuis).days
    return round(total / jours, 2) if total > 0 else None


# ── Abonnements à venir ───────────────────────────────────────────────────────

def abonnements_a_venir(abonnements: list[Abonnement], debut: date, fin: date) -> list[dict[str, Any]]:
    """Prélèvements attendus d'ici la fin du cycle et pas encore passés pendant ce cycle."""
    a_venir = []
    for a in abonnements:
        intervalle = INTERVALLES_JOURS.get((a.frequence or "mensuel").lower(), 30)
        if a.dernier_prelevement is None:
            # Essai gratuit qui finit dans ce cycle : son prix compte déjà, par prudence (§ 11).
            if a.premier_prelevement and debut <= a.premier_prelevement <= fin:
                a_venir.append({"nom": a.nom, "montant": round(a.montant, 2),
                                "date": a.premier_prelevement.isoformat()})
            continue
        if a.dernier_prelevement >= debut:
            continue  # déjà prélevé pendant ce cycle (compté dans les dépenses)
        prochain = abos.prochain_prelevement(a.dernier_prelevement, intervalle, a.mois_pause)
        while prochain < debut:  # prélèvement manqué : on vise le suivant
            prochain = abos.prochain_prelevement(prochain, intervalle, a.mois_pause)
        if prochain <= fin:
            a_venir.append({"nom": a.nom, "montant": round(a.montant, 2), "date": prochain.isoformat()})
    return sorted(a_venir, key=lambda x: x["date"])


# ── Calcul principal ──────────────────────────────────────────────────────────

def calculer(aujourdhui: date, operations: list[dict[str, Any]], abonnements: list[Abonnement],
             reglages: Reglages, epargne_proposee: tuple[float, str] = (0.0, "aucune")) -> Budget:
    paie = derniere_paie(operations, aujourdhui)
    if paie is None:
        raise ValueError("Aucune paie trouvée : impossible de calculer le cycle")
    debut, montant_paie = paie

    au_plus_tot = _mois_suivant(debut, reglages.jour_paie_min)
    au_plus_tard = _mois_suivant(debut, reglages.jour_paie_max)
    fin = au_plus_tard - timedelta(days=1)
    en_retard = aujourdhui > fin
    jours_restants = max((fin - aujourdhui).days + 1, 1)  # jamais de division par zéro

    if reglages.epargne_visee is not None:
        epargne, source = reglages.epargne_visee, "réglée par toi"
    else:
        epargne, source = epargne_proposee

    a_venir = abonnements_a_venir(abonnements, debut, fin)
    total_a_venir = round(sum(a["montant"] for a in a_venir), 2)

    du_cycle = [o for o in operations if debut <= _jour(o) <= aujourdhui]
    avant = depense([o for o in du_cycle if _jour(o) < aujourdhui])
    aujourd = depense([o for o in du_cycle if _jour(o) == aujourdhui])

    reste = round(montant_paie - epargne - total_a_venir - avant, 2)
    calculee = round(max(reste, 0) / jours_restants, 2)

    limite, appliquee, effet = calculee, "calculee", 0.0
    if reglages.limite_manuelle is not None:
        manuelle = round(reglages.limite_manuelle, 2)
        if reglages.mode_economies_max and manuelle < calculee:
            limite, appliquee = manuelle, "plafond"
        elif not reglages.mode_economies_max and manuelle > calculee:
            limite, appliquee = manuelle, "plancher"
        if appliquee != "calculee" and jours_restants > 1:
            effet = round((limite - calculee) / (jours_restants - 1), 2)

    # Cycle dépassé : jamais « 0 € par jour » ; l'essentiel (courses habituelles), pris sur l'épargne (§ 1).
    depassement = round(-reste, 2) if reste < 0 else 0.0
    essentiel = essentiel_par_jour(operations, debut) if reste <= 0 else None
    if essentiel is not None and essentiel > limite:
        limite, appliquee, effet = essentiel, "essentiel", 0.0

    pourquoi = [
        Ligne(f"Paie du {debut.strftime('%d/%m')}", montant_paie),
        Ligne(f"Épargne visée ({source})", -epargne),
        Ligne("Abonnements à venir avant la paie", -total_a_venir),
        Ligne(f"Déjà dépensé depuis le {debut.strftime('%d/%m')}", -avant),
        Ligne("Reste du cycle", reste),
        Ligne(f"÷ {jours_restants} jour{'s' if jours_restants > 1 else ''} restant{'s' if jours_restants > 1 else ''}", calculee),
    ]
    if appliquee == "plancher":
        pourquoi.append(Ligne("Ta marge de sécurité s'applique", limite))
    elif appliquee == "plafond":
        pourquoi.append(Ligne("Limitée par ton plafond (mode économies max)", limite))
    elif appliquee == "essentiel":
        pourquoi.append(Ligne("Cycle dépassé : tes courses habituelles par jour", limite))
    pourquoi.append(Ligne("Dépensé aujourd'hui", -aujourd))

    return Budget(
        debut_cycle=debut, paie=montant_paie, paie_au_plus_tot=au_plus_tot, paie_au_plus_tard=au_plus_tard,
        paie_en_retard=en_retard, jours_restants=jours_restants, epargne_visee=round(epargne, 2),
        source_epargne=source, abonnements_a_venir=a_venir, depense_avant_aujourdhui=avant,
        depense_aujourdhui=aujourd, reste_du_cycle=reste, limite_calculee=calculee, limite_du_jour=limite,
        tu_peux_encore=round(limite - aujourd, 2), limite_appliquee=appliquee, effet_limite_manuelle=effet,
        pourquoi=pourquoi, epargne_proposee=round(epargne_proposee[0], 2), depassement=depassement,
    )


# ── Épargne proposée quand Mohamed ne l'a pas réglée ─────────────────────────

def epargne_proposee(objectifs: list[dict[str, Any]], mouvements: list[dict[str, Any]],
                     aujourdhui: date, jours_cycle: int, mis_de_cote_recent: float,
                     depenses_rattachees: list[dict[str, Any]] | None = None) -> tuple[float, str]:
    """Ce que demandent les objectifs datés pour ce cycle ; sinon ce qu'il a réellement mis de côté.
    Un projet avance avec ce qui est dans sa tirelire et ce qu'il a déjà payé (voir objectifs.py)."""
    epargne_par_objectif: dict[str, float] = {}
    for m in mouvements:
        if m.get("status") == "confirme":
            epargne_par_objectif[m["goal_id"]] = epargne_par_objectif.get(m["goal_id"], 0.0) + float(m["amount"])
    for t in depenses_rattachees or []:
        epargne_par_objectif[t["goal_id"]] = epargne_par_objectif.get(t["goal_id"], 0.0) - float(t["amount"])
    besoin = 0.0
    for o in objectifs:
        if o.get("status") != "active" or o.get("kind") == "imprevus" or not o.get("deadline"):
            continue
        echeance = date.fromisoformat(str(o["deadline"])[:10])
        if echeance < aujourdhui:
            continue  # échéance dépassée : l'app propose de la repousser
        reste = float(o["target_amount"]) - epargne_par_objectif.get(o["id"], 0.0)
        jours = max((echeance - aujourdhui).days, 1)
        besoin += max(reste, 0) * min(jours_cycle, jours) / jours
    if besoin > 0:
        return round(besoin, 2), "demandée par tes objectifs"
    if mis_de_cote_recent > 0:
        return round(mis_de_cote_recent, 2), "ton rythme récent"
    return 0.0, "aucune pour l'instant"


# ── Chargement des données réelles ────────────────────────────────────────────

def _nombre(valeur: str | None) -> float | None:
    try:
        return float(valeur.replace(",", ".")) if valeur and valeur.strip() else None
    except ValueError:
        return None


async def budget_du_jour(aujourdhui: date | None = None, essai: dict[str, str | None] | None = None) -> Budget:
    """`essai` : réglages à essayer sans les enregistrer (clés de la table settings, None = retiré),
    pour l'aperçu « ta limite passerait de X à Y » des Réglages."""
    aujourdhui = aujourdhui or datetime.now(PARIS).date()
    debut_lecture = (aujourdhui - timedelta(days=120)).isoformat()

    trois_mois = aujourdhui - timedelta(days=90)
    # Toutes les lectures partent en même temps : aucune ne dépend d'une autre.
    operations, settings, souscriptions, comptes_reserve, recents, objectifs, mouvements, rattachees = await asyncio.gather(
        db.select("transactions", select="date,amount,category,is_internal,goal_id,merchant,description,bank_name",
                  date=f"gte.{debut_lecture}", limit="5000"),
        db.select("settings"),
        db.select("subscriptions", status="eq.active"),
        db.select("bank_accounts", bank="eq.Revolut", account_type="eq.savings"),
        db.select("transactions", select="amount,bank_account_id,date", date=f"gte.{trois_mois.isoformat()}", limit="5000"),
        db.select("goals"),
        db.select("goal_movements"),
        db.select("transactions", select="goal_id,amount", goal_id="not.is.null", limit="10000"),
    )
    reglages_bruts = {r["key"]: r["value"] for r in settings} | (essai or {})
    reglages = Reglages(
        jour_paie_min=int(reglages_bruts.get("salary_day") or 21),
        jour_paie_max=int(reglages_bruts.get("salary_day_max") or 28),
        limite_manuelle=_nombre(reglages_bruts.get("limite_manuelle")),
        mode_economies_max=(reglages_bruts.get("mode_economies_max") or "").lower() == "true",
        epargne_visee=_nombre(reglages_bruts.get("epargne_visee")),
    )

    # Montant (fixe, variable ou corrigé à la main), dernier prélèvement et mois de pause : voir abonnements.py.
    abonnements = []
    for a in souscriptions:
        e = abos.etat(a, operations, aujourdhui)
        if e.statut == "resilie":
            continue
        abonnements.append(Abonnement(e.nom, e.montant_budget, e.frequence, e.dernier_prelevement, e.mois_pause,
                                      premier_prelevement=e.essai_jusqu_au))

    # Épargne réellement mise de côté : variation de la réserve « Économies » sur ~3 cycles, ramenée à un cycle.
    reserve = {a["id"] for a in comptes_reserve}
    mis_de_cote = sum(float(o["amount"]) for o in recents if o.get("bank_account_id") in reserve) / 3

    paie = derniere_paie(operations, aujourdhui)
    jours_cycle = 30
    if paie:
        jours_cycle = (_mois_suivant(paie[0], reglages.jour_paie_max) - paie[0]).days
    proposition = epargne_proposee(objectifs, mouvements, aujourdhui, jours_cycle, mis_de_cote, rattachees)
    return calculer(aujourdhui, operations, abonnements, reglages, proposition)
