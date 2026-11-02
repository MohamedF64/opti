"""Écran Stats — voir docs/regles-de-calcul.md § 8 (validé le 31/10/2026).

Un cycle va du jour d'une paie à la veille de la suivante ; le cycle en cours s'arrête à aujourd'hui.
`calculer(...)` est pur (testable) ; `ecran()` charge les données de Mohamed puis l'appelle.
"""
import asyncio
from bisect import bisect_right
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from typing import Any

import abonnements as abos
import budget as b
import db
import historique

PREMIER_CYCLE = date(2026, 5, 27)   # données complètes à partir de cette paie (CIC relié, trou Revolut comblé)
NB_CATEGORIES = 5                   # au-delà : « Le reste »
SEUIL_POURCENT = 0.10               # une évolution s'affiche au-delà de 10 % …
SEUIL_EUROS = 20.0                  # … et de 20 €
PERIODES = {"cycle": 1, "precedent": 1, "6": 6, "12": 12}


@dataclass
class Cycle:
    debut: date
    fin: date                        # veille de la paie suivante, ou aujourd'hui pour le cycle en cours
    en_cours: bool
    jours: int
    depense: float
    entre: float
    reste: float                     # entré − dépensé
    paye_par_epargne: float          # dépenses rattachées à un projet, hors du total
    jours_sous_limite: int          # jours écoulés (cycle en cours) compris


@dataclass
class Categorie:
    nom: str
    montant: float
    part: float                      # en %, sur le total du donut
    nombre: int
    precedent: float | None = None   # montant au cycle d'avant (vues d'un seul cycle)
    ecart: float | None = None       # affiché seulement au-delà des deux seuils
    pourcent: float | None = None
    nouveau: bool = False            # absente du cycle d'avant
    inclut: list[str] = field(default_factory=list)   # « Le reste » : les catégories regroupées


@dataclass
class Stats:
    periode: str
    cycles: list[Cycle]              # du plus ancien au plus récent
    moyenne: float | None            # des cycles terminés de la période
    depense: float
    entre: float
    reste: float
    paye_par_epargne: float
    categories: list[Categorie] = field(default_factory=list)


def _jour(o: dict[str, Any]) -> date:
    return b._jour(o)


def debuts_de_cycle(operations: list[dict[str, Any]], aujourdhui: date) -> list[date]:
    """Jours de paie (catégorie Salaire) depuis le premier cycle complet."""
    return sorted({_jour(o) for o in operations
                   if o.get("category") == "Salaire" and float(o["amount"]) > 0 and PREMIER_CYCLE <= _jour(o) <= aujourdhui})


def bornes(debuts: list[date], aujourdhui: date) -> list[tuple[date, date, bool]]:
    return [(d, debuts[i + 1] - timedelta(days=1) if i + 1 < len(debuts) else aujourdhui, i + 1 == len(debuts))
            for i, d in enumerate(debuts)]


def par_categorie(operations: list[dict[str, Any]]) -> dict[str, tuple[float, int]]:
    """{catégorie: (montant dépensé, nombre d'opérations)} ; les remboursements réduisent leur catégorie."""
    resultat: dict[str, tuple[float, int]] = {}
    for o in operations:
        if b.compte_comme_depense(o):
            nom = o.get("category") or "Autre"
            montant, nombre = resultat.get(nom, (0.0, 0))
            resultat[nom] = (montant - float(o["amount"]), nombre + 1)
    return {k: (round(m, 2), n) for k, (m, n) in resultat.items()}


def donut(categories: dict[str, tuple[float, int]],
          precedentes: dict[str, tuple[float, int]] | None = None) -> list[Categorie]:
    """Les 5 plus grosses catégories puis « Le reste » ; évolution par rapport au cycle d'avant si fournie."""
    positives = sorted(((k, m, n) for k, (m, n) in categories.items() if m > 0), key=lambda x: -x[1])
    total = sum(m for _, m, _ in positives)
    if total <= 0:
        return []
    lignes = [Categorie(k, m, round(m / total * 100, 1), n) for k, m, n in positives[:NB_CATEGORIES]]
    reste = positives[NB_CATEGORIES:]
    if reste:
        m = round(sum(x[1] for x in reste), 2)
        lignes.append(Categorie("Le reste", m, round(m / total * 100, 1), sum(x[2] for x in reste),
                                inclut=[x[0] for x in reste]))
    if precedentes is not None:
        for c in lignes:
            if c.nom == "Le reste":
                continue
            avant = precedentes.get(c.nom, (0.0, 0))[0]
            c.precedent = round(avant, 2)
            if avant <= 0:
                c.nouveau = True
                continue
            ecart = round(c.montant - avant, 2)
            if abs(ecart) > SEUIL_EUROS and abs(ecart) / avant > SEUIL_POURCENT:
                c.ecart, c.pourcent = ecart, round(ecart / avant * 100)
    return lignes


def _entre(operations: list[dict[str, Any]]) -> float:
    return round(sum(float(o["amount"]) for o in operations
                     if float(o["amount"]) > 0 and o.get("category") in b.REVENUS and not o.get("is_internal")), 2)


def _paye_par_epargne(operations: list[dict[str, Any]]) -> float:
    return round(-sum(float(o["amount"]) for o in operations if o.get("goal_id")), 2)


@dataclass
class AbonnementSuivi:
    """Un abonnement actif avec tous ses prélèvements connus, pour retrouver le dernier avant un jour donné."""
    nom: str
    montant: float
    frequence: str
    dates: list[date]
    mois_pause: list[int]

    def au(self, jour: date) -> b.Abonnement:
        i = bisect_right(self.dates, jour)
        return b.Abonnement(self.nom, self.montant, self.frequence, self.dates[i - 1] if i else None, self.mois_pause)


def suivre_abonnements(abonnements: list[dict[str, Any]], operations: list[dict[str, Any]],
                       aujourdhui: date) -> list[AbonnementSuivi]:
    suivis = []
    for a in abonnements:
        e = abos.etat(a, operations, aujourdhui)
        dates = sorted(_jour(t) for t in abos.prelevements(a, operations))
        suivis.append(AbonnementSuivi(e.nom, e.montant, e.frequence, dates, e.mois_pause))
    return suivis


def jours_sous_limite(debut: date, fin: date, operations: list[dict[str, Any]],
                      abonnements: list[AbonnementSuivi], reglages: b.Reglages) -> int:
    """Jours où la dépense du jour est restée sous la limite du jour, recalculée avec les règles actuelles,
    sans épargne visée ni limite manuelle (non historisées). `operations` : celles du cycle, paie comprise."""
    sous, jour = 0, debut
    while jour <= fin:
        r = b.calculer(jour, operations, [a.au(jour) for a in abonnements], reglages)
        sous += r.depense_aujourdhui <= r.limite_du_jour + 0.005
        jour += timedelta(days=1)
    return sous


def calculer(periode: str, aujourdhui: date, operations: list[dict[str, Any]],
             abonnements: list[AbonnementSuivi], reglages: b.Reglages | None = None) -> Stats:
    if periode not in PERIODES:
        raise ValueError(f"Période inconnue : {periode!r}")
    reglages = b.Reglages(jour_paie_min=reglages.jour_paie_min, jour_paie_max=reglages.jour_paie_max) if reglages else b.Reglages()
    tous = bornes(debuts_de_cycle(operations, aujourdhui), aujourdhui)
    if periode == "precedent":
        choisis = tous[-2:-1]
    else:
        choisis = tous[-PERIODES[periode]:]

    def du_cycle(debut: date, fin: date) -> list[dict[str, Any]]:
        return [o for o in operations if debut <= _jour(o) <= fin]

    cycles = []
    for debut, fin, en_cours in choisis:
        ops = du_cycle(debut, fin)
        depense, entre = b.depense(ops), _entre(ops)
        cycles.append(Cycle(
            debut=debut, fin=fin, en_cours=en_cours, jours=(fin - debut).days + 1,
            depense=depense, entre=entre, reste=round(entre - depense, 2), paye_par_epargne=_paye_par_epargne(ops),
            jours_sous_limite=jours_sous_limite(debut, fin, ops, abonnements, reglages),
        ))

    termines = [c.depense for c in cycles if not c.en_cours]
    stats = Stats(
        periode=periode, cycles=cycles, moyenne=round(sum(termines) / len(termines), 2) if termines else None,
        depense=round(sum(c.depense for c in cycles), 2), entre=round(sum(c.entre for c in cycles), 2),
        reste=round(sum(c.reste for c in cycles), 2), paye_par_epargne=round(sum(c.paye_par_epargne for c in cycles), 2),
    )
    if cycles:
        ops = du_cycle(cycles[0].debut, cycles[-1].fin)
        precedentes = None
        if len(cycles) == 1:   # comparaison au cycle d'avant : seulement dans les vues d'un seul cycle
            i = tous.index((cycles[0].debut, cycles[0].fin, cycles[0].en_cours))
            if i > 0:
                # Cycle en cours : comparé aux mêmes premiers jours du cycle d'avant (6 jours contre 6 jours).
                debut_avant, fin_avant, _ = tous[i - 1]
                if cycles[0].en_cours:
                    fin_avant = min(fin_avant, debut_avant + timedelta(days=cycles[0].jours - 1))
                precedentes = par_categorie(du_cycle(debut_avant, fin_avant))
        stats.categories = donut(par_categorie(ops), precedentes)
    return stats


# ── Chargement des données réelles ────────────────────────────────────────────

async def ecran(periode: str, aujourdhui: date | None = None) -> Stats:
    aujourdhui = aujourdhui or datetime.now(b.PARIS).date()
    return calculer(periode, aujourdhui, *await _charger(aujourdhui))


async def _charger(aujourdhui: date) -> tuple[list[dict[str, Any]], list[AbonnementSuivi], b.Reglages]:
    # Un an avant le premier cycle : les abonnements retrouvent leurs prélèvements plus anciens.
    operations, souscriptions, settings = await asyncio.gather(
        db.select_tout("transactions", select="id,date,amount,category,is_internal,goal_id,merchant,description",
                       date=f"gte.{(PREMIER_CYCLE - timedelta(days=365)).isoformat()}"),
        db.select("subscriptions", status="eq.active"),
        db.select("settings", key="in.(salary_day,salary_day_max)"),
    )
    brut = {r["key"]: r["value"] for r in settings}
    reglages = b.Reglages(jour_paie_min=int(brut.get("salary_day") or 21), jour_paie_max=int(brut.get("salary_day_max") or 28))
    return operations, suivre_abonnements(souscriptions, operations, aujourdhui), reglages


# ── Bilan du cycle (carte de l'accueil, § 11) ─────────────────────────────────

BILAN_JOURS = 3   # la carte reste 3 jours après la paie


def bilan(precedent: Stats, six: Stats, aujourdhui: date) -> dict[str, Any] | None:
    """Le cycle qui vient de finir, tant que le nouveau a moins de 3 jours ; None sinon."""
    if not precedent.cycles or not six.cycles or not six.cycles[-1].en_cours:
        return None
    if (aujourdhui - six.cycles[-1].debut).days >= BILAN_JOURS:
        return None
    c = precedent.cycles[0]
    moyenne = six.moyenne
    bougees = [x for x in precedent.categories if x.pourcent is not None]
    plus = max(bougees, key=lambda x: abs(x.ecart or 0), default=None)
    return {
        "debut": c.debut, "fin": c.fin, "depense": c.depense, "reste": c.reste, "entre": c.entre,
        "jours": c.jours, "jours_sous_limite": c.jours_sous_limite, "moyenne": moyenne,
        "ecart_moyenne_pourcent": round((c.depense - moyenne) / moyenne * 100) if moyenne else None,
        "categorie": {"nom": plus.nom, "pourcent": plus.pourcent, "ecart": plus.ecart} if plus else None,
    }


async def ecran_bilan(aujourdhui: date | None = None) -> dict[str, Any] | None:
    aujourdhui = aujourdhui or datetime.now(b.PARIS).date()
    donnees = await _charger(aujourdhui)
    return bilan(calculer("precedent", aujourdhui, *donnees), calculer("6", aujourdhui, *donnees), aujourdhui)


async def operations_de_categories(debut: date, fin: date, categories: list[str]) -> list[dict[str, Any]]:
    """Dépenses d'une ou plusieurs catégories (« Le reste ») sur une période : toucher une part du donut."""
    ops = await db.select_tout("transactions", select=historique.CHAMPS, date=f"gte.{debut.isoformat()}",
                               order="date.desc,created_at.desc")
    return [o for o in ops if _jour(o) <= fin and b.compte_comme_depense(o) and (o.get("category") or "Autre") in categories]
