"""Conseils de l'accueil — voir docs/regles-de-calcul.md § 6 (validé le 01/11/2026).

Épargne simple uniquement (jamais d'investissement ni de fiscalité) ; un conseil n'existe que si les opérations
le justifient et cite son montant ; 3 au maximum, classés par montant en jeu.
`calculer(...)` est pur (testable) ; `ecran()` charge les données de Mohamed puis l'appelle.
"""
import asyncio
import math
from dataclasses import asdict, dataclass, field
from datetime import date, datetime, timedelta
from typing import Any

import abonnements as abos
import budget as b
import catalogue as cat
import db
import objectifs as obj
import stats

NB_CONSEILS = 3
DEBUT_DE_CYCLE_JOURS = 7          # conseils 1 et 3 : les 7 premiers jours du cycle
FIN_DE_CYCLE_JOURS = 7            # conseil 2 : les 7 derniers jours avant la paie au plus tôt
PAIE_HAUTE = 1.3                  # paie > moyenne des 3 précédentes × 1,3
MARGE_FIN_DE_CYCLE = 20.0
PART_RESERVE = 0.10               # conseil 3 : 10 % de la paie habituelle
DEPASSEMENT_MIN = 30.0            # conseil 4 : au moins 30 € au-dessus de la moyenne d'un cycle
CYCLES_MOYENNE = 6
INSECABLE, INSECABLE_FINE = " ", " "


@dataclass
class Conseil:
    cle: str                      # « Pas maintenant » masque cette clé (elle change à chaque cycle)
    type: str                     # paie_haute, fin_de_cycle, reserve, categorie, abonnement, offre
    texte: str
    montant: float                # montant en jeu, pour le classement
    action: dict[str, Any] | None = field(default=None)   # {"type": "verser", ...}, {"type": "abonnement", "id"}
    #                                                         ou {"type": "catalogue"}


def _e(montant: float, centimes: bool = False) -> str:
    """1039.45 → « 1 039 € » (ou « 1 039,45 € ») ; 450.0 → « 450 € »."""
    # Espaces insécables (milliers et avant « € ») : « 1 039 € » ne se coupe jamais en fin de ligne.
    if centimes and abs(montant - round(montant)) >= 0.005:
        entier, dec = f"{montant:,.2f}".split(".")
        return f"{entier.replace(',', INSECABLE_FINE)},{dec}{INSECABLE}€"
    return f"{round(montant):,}".replace(",", INSECABLE_FINE) + f"{INSECABLE}€"


def _jm(d: date) -> str:
    return f"{d:%d/%m}"


def destination(objectifs: list[Any], montant: float) -> tuple[Any, float] | None:
    """Imprévus tant qu'il n'est pas plein, sinon le projet actif à l'échéance la plus proche ;
    le montant est plafonné à ce qu'il lui manque."""
    actifs = [o for o in objectifs if o.statut == "active" and o.reste > 0]
    imprevus = [o for o in actifs if o.type == "imprevus"]
    projets = sorted((o for o in actifs if o.type != "imprevus"), key=lambda o: (o.echeance is None, o.echeance or date.max))
    cible = (imprevus or projets or [None])[0]
    if cible is None:
        return None
    return cible, min(montant, cible.reste)


def _verser(cle: str, type_: str, texte: str, cible: tuple[Any, float]) -> Conseil:
    o, montant = cible
    return Conseil(cle, type_, texte.format(montant=_e(montant), objectif=o.nom), montant,
                   {"type": "verser", "objectif_id": o.id, "objectif": o.nom, "montant": montant})


def calculer(aujourdhui: date, *, debut_cycle: date, paie_au_plus_tot: date, jours_restants: int,
             reste_du_cycle: float, paies: list[float], depense_par_jour: float | None,
             en_cours: dict[str, float], moyennes: dict[str, float], objectifs: list[Any],
             abonnements: list[Any], catalogue: list[dict[str, Any]] = ()) -> list[Conseil]:
    """`paies` : montants des paies, de la plus ancienne à celle du cycle en cours ; `depense_par_jour` : moyenne
    réelle des 3 derniers cycles terminés ; `en_cours` / `moyennes` : dépenses par catégorie du cycle en cours et
    moyenne par cycle terminé ; `objectifs` : objectifs.EtatObjectif ; `abonnements` : abonnements.EtatAbonnement."""
    conseils: list[Conseil] = []
    cycle = debut_cycle.isoformat()
    debut = (aujourdhui - debut_cycle).days < DEBUT_DE_CYCLE_JOURS
    habituelle = sum(paies[-4:-1]) / 3 if len(paies) >= 4 else None

    # 1. Paie plus haute que d'habitude : la moitié du supplément.
    paie_haute = False
    if debut and habituelle and paies[-1] > habituelle * PAIE_HAUTE:
        supplement = paies[-1] - habituelle
        cible = destination(objectifs, round(supplement / 2 / 10) * 10)
        if cible:
            paie_haute = True
            conseils.append(_verser(f"paie_haute:{cycle}", "paie_haute",
                                    f"Ta paie est plus haute que d'habitude (+{_e(supplement)}). "
                                    "Mets {montant} de côté dans {objectif} ?", cible))

    # 2. Surplus de fin de cycle : la moitié de ce qui dépasse les besoins jusqu'à la paie.
    if depense_par_jour and aujourdhui >= paie_au_plus_tot - timedelta(days=FIN_DE_CYCLE_JOURS):
        besoin = jours_restants * depense_par_jour + MARGE_FIN_DE_CYCLE
        surplus = reste_du_cycle - besoin
        montant = math.floor(surplus / 2 / 5) * 5
        cible = destination(objectifs, montant) if montant >= 5 else None
        if cible:
            conseils.append(_verser(f"fin_de_cycle:{cycle}", "fin_de_cycle",
                                    f"Il te reste {_e(reste_du_cycle)} pour {jours_restants} jours, tu en as besoin "
                                    f"d'environ {_e(besoin)}. " + "Mets {montant} de côté dans {objectif} ?", cible))

    # 3. Réserve d'imprévus faible : 10 % de la paie habituelle à chaque paie.
    imprevus = next((o for o in objectifs if o.type == "imprevus" and o.statut == "active"), None)
    if debut and not paie_haute and habituelle and imprevus and imprevus.reste > 0:
        montant = min(round(habituelle * PART_RESERVE / 10) * 10, imprevus.reste)
        if montant > 0:
            mois = math.ceil(imprevus.reste / montant)
            conseils.append(Conseil(
                f"reserve:{cycle}", "reserve",
                f"Ta réserve {imprevus.nom} est à {_e(imprevus.disponible)} sur {_e(imprevus.cible)}. En y versant "
                f"{_e(montant)} à chaque paie, elle est pleine en {mois} mois.", montant,
                {"type": "verser", "objectif_id": imprevus.id, "objectif": imprevus.nom, "montant": montant}))

    # 4. Catégorie qui s'emballe : déjà au-dessus de sa moyenne d'un cycle entier.
    quand = f"d'ici le {_jm(paie_au_plus_tot)}" if aujourdhui < paie_au_plus_tot else "d'ici ta paie"
    for nom, montant in en_cours.items():
        moyenne = moyennes.get(nom, 0.0)
        if moyenne <= 0 or montant - moyenne < DEPASSEMENT_MIN:
            continue
        fois = montant / moyenne
        comparaison = (f"{int(fois)} fois ta moyenne d'un cycle entier" if fois >= 2
                       else "déjà plus que ta moyenne d'un cycle entier")
        conseils.append(Conseil(f"categorie:{nom}:{cycle}", "categorie",
                                f"{nom} : {_e(montant, centimes=True)} depuis ta paie, {comparaison} "
                                f"({_e(moyenne)}). Lève le pied {quand}.",
                                round(montant - moyenne, 2)))

    # 5. Abonnement jamais utilisé : son prix sur un an.
    for a in abonnements:
        if a.verdict == "a_couper" and a.statut in ("actif", "a_verifier") and a.economie_par_an:
            conseils.append(Conseil(f"abonnement:{a.id}:{cycle}", "abonnement",
                                    f"Tu n'utilises jamais {a.nom} : le résilier te ferait gagner "
                                    f"{_e(a.economie_par_an)} par an.", a.economie_par_an,
                                    {"type": "abonnement", "id": a.id}))

    # 6. Offre moins chère (§ 12) : la meilleure de chaque ligne (`catalogue` = abonnements de catalogue.comparer ;
    # ni offre groupée ni offre à revérifier, déjà écartées), hors essai gratuit ; classée par l'économie sur un an.
    for a in catalogue:
        if a["statut"] not in ("actif", "a_verifier"):
            continue
        for ligne in a["lignes"]:
            if not ligne["alternatives"] or not ligne["offre"]:
                continue
            o = ligne["alternatives"][0]
            service = ligne["offre"]["service"]
            nom = service if len(a["lignes"]) == 1 else f"{service} ({ligne['nom']})"
            offre = o["nom"] if o["meme_service"] else f"{o['service']} {o['nom']}"
            prix = (f"{_e(o['paiement_d_avance'], centimes=True)} payés d'avance" if o["paiement_d_avance"]
                    else f"{_e(o['par_mois'], centimes=True)} par mois")
            conseils.append(Conseil(
                f"offre:{ligne['id']}:{o['offre_id']}:{cycle}", "offre",
                f"{nom} : l'offre {offre} ({prix}) te coûterait {_e(o['economie_par_mois'], centimes=True)} de moins "
                f"par mois, soit {_e(o['economie_par_an'], centimes=True)} par an.",
                o["economie_par_an"], {"type": "catalogue"}))

    return sorted(conseils, key=lambda c: -c.montant)[:NB_CONSEILS]


# ── Chargement des données réelles ────────────────────────────────────────────

def _par_cycle(operations: list[dict[str, Any]], aujourdhui: date) -> tuple[dict[str, float], dict[str, float], float | None]:
    """Dépenses par catégorie du cycle en cours, moyenne par cycle terminé, dépense moyenne par jour (3 derniers)."""
    tous = stats.bornes(stats.debuts_de_cycle(operations, aujourdhui), aujourdhui)

    def du_cycle(debut: date, fin: date) -> list[dict[str, Any]]:
        return [o for o in operations if debut <= stats._jour(o) <= fin]

    termines = [(d, f) for d, f, en_cours in tous if not en_cours][-CYCLES_MOYENNE:]
    totaux: dict[str, float] = {}
    for d, f in termines:
        for nom, (montant, _) in stats.par_categorie(du_cycle(d, f)).items():
            totaux[nom] = totaux.get(nom, 0.0) + montant
    moyennes = {nom: round(t / len(termines), 2) for nom, t in totaux.items()} if termines else {}
    en_cours = {}
    if tous and tous[-1][2]:
        en_cours = {nom: m for nom, (m, _) in stats.par_categorie(du_cycle(tous[-1][0], tous[-1][1])).items() if m > 0}
    derniers = termines[-3:]
    jours = sum((f - d).days + 1 for d, f in derniers)
    par_jour = round(sum(b.depense(du_cycle(d, f)) for d, f in derniers) / jours, 2) if jours else None
    return en_cours, moyennes, par_jour


async def ecran(aujourdhui: date | None = None) -> list[Conseil]:
    aujourdhui = aujourdhui or datetime.now(b.PARIS).date()
    try:
        budget = await b.budget_du_jour(aujourdhui)
    except ValueError:
        return []   # pas encore de paie connue
    (operations, _, _), salaires, objectifs, (souscriptions, ops_abos, _), catalogue = await asyncio.gather(
        stats._charger(aujourdhui),
        db.select("transactions", select="date,amount", category="eq.Salaire", amount="gt.0",
                  date=f"lte.{aujourdhui.isoformat()}", order="date.desc", limit="4"),
        obj.objectifs_du_moment(aujourdhui),
        abos._donnees(aujourdhui),
        asyncio.gather(db.select("catalog_services"), db.select("catalog_offers"), db.select("subscription_lines"),
                       cat._profil()),
    )
    en_cours, moyennes, par_jour = _par_cycle(operations, aujourdhui)
    services, offres, lignes, profil = catalogue
    etats =[abos.etat(s, ops_abos, aujourdhui) for s in souscriptions]
    comparaison = cat.comparer([asdict(e) for e in etats], lignes, services, offres, profil, aujourdhui)
    return calculer(
        aujourdhui, debut_cycle=budget.debut_cycle, paie_au_plus_tot=budget.paie_au_plus_tot,
        jours_restants=budget.jours_restants, reste_du_cycle=budget.reste_du_cycle,
        paies=[float(s["amount"]) for s in reversed(salaires)], depense_par_jour=par_jour,
        en_cours=en_cours, moyennes=moyennes, objectifs=objectifs,
        abonnements=etats, catalogue=comparaison["abonnements"],
    )
