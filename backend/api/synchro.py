"""Synchronisation des comptes Enable Banking vers la table `transactions`.

Pour chaque compte relié :
- soldes : on garde le solde « disponible » le plus parlant (opérations en attente incluses) ;
- opérations comptabilisées : ajoutées une seule fois (référence bancaire unique par compte,
  et rapprochement date + montant avec l'historique importé qui n'a pas de référence) ;
- opérations en attente : remplacées à chaque passage, car elles n'ont pas de référence
  stable et changent de libellé une fois comptabilisées ;
- catégorie : virement interne d'abord, puis choix retenus par Mohamed (regles-de-calcul.md § 9),
  puis historique de Mohamed, puis mots-clés.
Une erreur sur un compte (banque en panne, session expirée) n'empêche pas les autres.
"""
import asyncio
import re
from collections import Counter
from datetime import date, datetime, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo

import db
import objectifs
import enable_banking as eb

DEBUT_PAR_DEFAUT = date(2026, 5, 1)
RECOUVREMENT_JOURS = 7
INTERNE = "Épargne", "Retrait d'épargne"

# Mots-clés repris des anciens parsers e-mail (CIC et Revolut).
REGLES: list[tuple[tuple[str, ...], str]] = [
    (("aldi", "carrefour", "franprix", "lidl", "monop", "leclerc", "auchan", "intermarche", "casino",
      "la baguette", "g 20", "g20", "marie blachere", "boucherie", "boulangerie", "alimentation gen",
      "crf mkt", "supermarche", "sc-sup"), "Alimentation"),
    (("burger king", "haagen", "five guys", "quick", "mcdonald", "kfc", "subway", "snack food", "uber *eats",
      "uber eats", "deliveroo", "zettle", "kebab", "snack", "pizza", "burger"), "Restauration"),
    (("imagine r", "comutitre", "navigo", "ratp", "sncf", "trainline", "heetch", "uber", "autodoc",
      "norauto", "carglass", "feu vert", "station service", "carburant", "total", "esso", "shell",
      "carte grise", "cta ", "carter-cash"), "Transport"),
    (("assurance",), "Assurance"),
    (("pathe", "pathé", "ugc", "kinepolis", "fnac", "playstation",
      "sony interactive", "steam", "microsoft*xbox", "tabac", "g2a", "instant gaming", "airbnb"), "Loisirs"),
    (("vinted", "amazon paym", "amazon eu", "amazon media", "amazon mp", "amazon retail", "cdiscount",
      "aliexpress", "groupon", "yves rocher", "miniso", "micromania", "leboncoin",
      "stock prive", "easy cash"), "Shopping"),
    (("primark", "chaussea", "snipes", "histoire d'or"), "Shopping"),   # Vêtements fusionné le 01/11/2026
    (("amazon prime", "prixtel", "orange", "sosh", "free mobile", "netflix", "spotify", "google one",
      "microsoft store", "microsoft payme", "playstation network", "msbill", "anthropic", "icloud",
      "basic fit"), "Abonnement"),
    (("pharmacie", "dr ", "krys", "optical", "doctor", "medical", "cpam", "ameli"), "Santé"),
    (("myprotein", "decathlon"), "Sport"),
    (("bricomarche", "brico depot", "leroy merlin", "castorama", "action", "gifi", "ikea"), "Maison"),
    (("selecta", "ivs france"), "Distributeur"),
    (("retrait dab", "cash withdrawal"), "Retrait"),
    (("ecole de conduite", "permis"), "Permis"),
    (("salaire",), "Salaire"),
]

# Réglages propres à chaque installation (api/perso.py, jamais publié ; modèle : perso_exemple.py) :
# noms du titulaire sur les virements, commerces de quartier, employeurs.
try:
    import perso
except ImportError:
    import perso_exemple as perso
NOMS_TITULAIRE = tuple(n.lower() for n in perso.NOMS_TITULAIRE)
_deja_completee: set[str] = set()
for _i, (_mots, _categorie) in enumerate(REGLES):
    if _categorie in perso.MOTS_CLES and _categorie not in _deja_completee:   # même ordre : même résultat
        REGLES[_i] = (_mots + tuple(perso.MOTS_CLES[_categorie]), _categorie)
        _deja_completee.add(_categorie)


# ── Libellés ──────────────────────────────────────────────────────────────────

def _titre(ville: str) -> str:
    return re.sub(r"\s+", " ", ville).strip().title()


def nettoyer_libelle(banque: str, tx: dict[str, Any]) -> tuple[str, str | None]:
    """(libellé lisible, marchand) à partir d'une opération Enable Banking."""
    morceaux = [m.strip() for m in tx.get("remittance_information") or [] if m and m.strip()]
    brut = " | ".join(morceaux)
    creancier = (tx.get("creditor") or {}).get("name")

    if banque == "CIC":
        # Paiements carte comptabilisés : « PAIEMENT PSC 2810 RUEIL-MALMAIS | GRAIN OR BOULAN  CARTE 0051 »,
        # « PAIEMENT MOB 2609 … », « 3 PAIEMENTS 1908 … », ou sans préfixe : « 1209 SARCELLES | CTA 95 CARTE 0051 ».
        # Aussi « PAIEMENT CB  2910 PARIS | LEBONCOIN  CARTE 0051 » (paiement en ligne comptabilisé).
        m = re.match(r"(?:PAIEMENT (?:PSC|MOB|CB)\s+|\d+ PAIEMENTS )?\d{4} (.+?) \| (.+?)(?:\s+CARTE \d{4})?\s*$", brut)
        if m:
            marchand = re.sub(r"\s{2,}", " ", m.group(2)).strip()
            ville = _titre(re.sub(r"[\d/]+", " ", m.group(1)))
            return (f"{marchand} ({ville})" if ville else marchand), marchand
        # « PAIEMENT CB FNAC PARIS CEDE » (en attente)
        m = re.match(r"PAIEMENT CB (.+)$", brut)
        if m:
            return m.group(1).strip(), m.group(1).strip()
        return re.sub(r"\s{2,}", " ", brut) or "Opération CIC", None

    # Revolut : le libellé est le nom du marchand ou du correspondant.
    if creancier and (tx.get("credit_debit_indicator") == "DBIT"):
        marchand = re.sub(r"^(mp\*|sumup \*|zettle_\*)", "", creancier, flags=re.I).strip()
        return brut or marchand, marchand
    return brut or "Opération Revolut", None


def date_achat(banque: str, tx: dict[str, Any], comptabilisee: str | None) -> str | None:
    """Jour de l'achat. Le CIC date ses paiements carte du jour de comptabilisation (souvent le
    lendemain) mais écrit le vrai jour dans le libellé : « PAIEMENT PSC 2910 … » = le 29/10.
    Les paiements en plusieurs fois gardent la date de comptabilisation (sinon chaque échéance
    retomberait sur le mois de l'achat)."""
    if banque != "CIC" or not comptabilisee:
        return comptabilisee
    brut = " ".join(m.strip() for m in tx.get("remittance_information") or [] if m)
    m = re.match(r"(?:PAIEMENT (?:PSC|MOB|CB)\s+)?(\d{2})(\d{2}) \S", brut)
    if not m:
        return comptabilisee
    compta = date.fromisoformat(comptabilisee[:10])
    try:
        achat = date(compta.year, int(m.group(2)), int(m.group(1)))
        if achat > compta:                       # achat de décembre comptabilisé en janvier
            achat = achat.replace(year=compta.year - 1)
    except ValueError:
        return comptabilisee
    return achat.isoformat() if (compta - achat).days <= 10 else comptabilisee


def cle_marchand(texte: str) -> str:
    t = (texte or "").lower()
    t = re.sub(r"\(.*?\)", " ", t)             # ville entre parenthèses
    t = re.sub(r"[0-9*#/|_.,:;-]+", " ", t)
    return re.sub(r"\s+", " ", t).strip()


# ── Catégories ────────────────────────────────────────────────────────────────

def virement_interne(banque: str, type_compte: str, libelle: str, montant: float) -> str | None:
    """« Épargne », « Retrait d'épargne » ou None si ce n'est pas un mouvement entre les comptes du titulaire."""
    l = libelle.lower()
    entree = montant > 0
    if banque == "Revolut" and type_compte == "savings":
        return "Épargne" if entree else "Retrait d'épargne"      # la réserve ne parle qu'au compte principal
    if banque == "Revolut":
        if l.startswith("top-up by") or l.startswith("to pocket"):
            return "Épargne"
        if l.startswith("to eur") or l.startswith("from eur"):
            # Mouvement entre le compte principal et la réserve « Économies ».
            return "Retrait d'épargne" if entree else "Épargne"
        if l.startswith("pocket withdrawal") or any(n in l for n in NOMS_TITULAIRE):
            return "Retrait d'épargne"
    if banque == "CIC":
        if "revolut" in l:
            return "Retrait d'épargne" if entree else "Épargne"
        if entree and any(n in l for n in NOMS_TITULAIRE):
            return "Retrait d'épargne"
    return None


def historique_par_marchand(lignes: list[dict[str, Any]]) -> dict[str, str]:
    """Catégorie la plus fréquente par marchand, d'après les opérations déjà classées."""
    compteur: dict[str, Counter] = {}
    for l in lignes:
        if l.get("is_internal") or l.get("category") in (None, "", "Autre", "À vérifier", *INTERNE):
            continue
        cle = cle_marchand(l.get("merchant") or l.get("description") or "")
        if len(cle) >= 3:
            compteur.setdefault(cle, Counter())[l["category"]] += 1
    return {cle: c.most_common(1)[0][0] for cle, c in compteur.items()}


MARCHAND_MIN = 5   # en dessous, un début de nom commun ne suffit pas à dire « même marchand »


def meme_marchand(a: str, b: str) -> bool:
    """Noms nettoyés égaux, ou l'un commence par l'autre (le CIC nomme différemment l'opération en attente
    « c et a france paris e » et comptabilisée « c et a france »)."""
    court, long = sorted((a, b), key=len)
    return bool(court) and (court == long or (len(court) >= MARCHAND_MIN and long.startswith(court)))


def regle_pour(cle: str, regles: dict[str, str]) -> str | None:
    """Catégorie retenue par Mohamed pour ce marchand (la règle la plus précise d'abord)."""
    for connue in sorted(regles, key=len, reverse=True):
        if meme_marchand(cle, connue):
            return regles[connue]
    return None


def categoriser(libelle: str, marchand: str | None, montant: float, historique: dict[str, str],
                regles: dict[str, str] | None = None) -> str:
    if montant < 0 and regles and (choisie := regle_pour(cle_marchand(marchand or libelle), regles)):
        return choisie
    categorie = _categorie(libelle, marchand, montant, historique)
    # Une personne qui t'a déjà envoyé de l'argent (historique « Virement reçu ») peut aussi en recevoir :
    # un virement sortant n'est jamais « reçu ».
    if montant < 0 and categorie == "Virement reçu":
        return "Virement émis"
    return categorie


def _categorie(libelle: str, marchand: str | None, montant: float, historique: dict[str, str]) -> str:
    cle = cle_marchand(marchand or libelle)
    # Historique : correspondance exacte, puis plus long préfixe (« grain or boulan rueil » → « grain or boulan »).
    if cle in historique:
        return historique[cle]
    for connu in sorted(historique, key=len, reverse=True):
        if len(connu) >= 5 and cle.startswith(connu):
            return historique[connu]
    texte = f"{libelle} {marchand or ''}".lower()
    for mots, categorie in REGLES:
        if any(mot in texte for mot in mots):
            if categorie == "Salaire" and montant < 0:
                continue
            return categorie
    return "Virement reçu" if montant > 0 else "Autre"


# ── Conversion d'une opération ────────────────────────────────────────────────

def vers_ligne(compte: dict[str, Any], tx: dict[str, Any], historique: dict[str, str],
               regles: dict[str, str] | None = None) -> dict[str, Any]:
    banque = compte["bank"]
    valeur = float((tx.get("transaction_amount") or {}).get("amount") or 0)
    montant = -abs(valeur) if tx.get("credit_debit_indicator") == "DBIT" else abs(valeur)
    libelle, marchand = nettoyer_libelle(banque, tx)
    interne = virement_interne(banque, compte.get("account_type") or "checking", libelle, montant)
    en_attente = tx.get("status") == "PDNG"
    return {
        "bank_account_id": compte["id"],
        "bank_name": banque,
        # Le jour de l'achat compte pour les dépenses du jour, pas celui de la comptabilisation.
        "date": date_achat(banque, tx, tx.get("transaction_date") or tx.get("booking_date") or tx.get("value_date")),
        "description": libelle,
        "merchant": marchand,
        "amount": round(montant, 2),
        "currency": (tx.get("transaction_amount") or {}).get("currency") or "EUR",
        "category": interne or categoriser(libelle, marchand, montant, historique, regles),
        "is_internal": interne is not None,
        "status": "pending" if en_attente else "booked",
        "entry_reference": None if en_attente else tx.get("entry_reference"),
        "source": "enable_banking",
        "raw_payload": tx,
    }


def choisir_solde(soldes: list[dict[str, Any]], en_attente: list[dict[str, Any]] | None = None) -> float | None:
    """Solde à afficher, opérations en attente incluses.

    Quand la banque fournit son solde comptabilisé (CLBD/ITBD) et la liste des opérations en attente,
    Opti fait le calcul lui-même : le « prévisionnel » du CIC (XPCD) oublie certaines opérations qu'il
    liste pourtant en attente (le 31/10 : un virement de 150 € vers Revolut). Sinon : le prévisionnel
    de la banque, puis le disponible (Revolut ne donne que ITAV, opérations en attente comprises)."""
    par_type = {s.get("balance_type"): s for s in soldes}
    if en_attente is not None:
        for t in ("CLBD", "ITBD"):
            if t in par_type:
                return round(float(par_type[t]["balance_amount"]["amount"])
                             + sum(float(l["amount"]) for l in en_attente), 2)
    for t in ("XPCD", "ITAV", "CLAV", "ITBD", "CLBD"):
        if t in par_type:
            return float(par_type[t]["balance_amount"]["amount"])
    return float(soldes[0]["balance_amount"]["amount"]) if soldes else None


def rapprocher(nouvelles: list[dict[str, Any]], existantes: list[dict[str, Any]]) -> tuple[list[dict], int]:
    """Écarte les opérations déjà en base : même référence, ou même montant à un jour près
    qu'une opération importée sans référence (CSV, e-mail, relevé). Chaque opération existante
    ne peut servir qu'une fois, pour ne pas écarter deux achats identiques le même jour."""
    refs = {e["entry_reference"] for e in existantes if e.get("entry_reference")}
    sans_ref = [e for e in existantes if not e.get("entry_reference") and e.get("status") != "pending"]
    utilisees: set[int] = set()
    gardees, ecartees = [], 0
    for n in nouvelles:
        if n["entry_reference"] and n["entry_reference"] in refs:
            ecartees += 1
            continue
        jour = date.fromisoformat(n["date"])
        trouve = next((i for i, e in enumerate(sans_ref) if i not in utilisees
                       and abs(float(e["amount"]) - n["amount"]) < 0.005
                       and abs((date.fromisoformat(str(e["date"])[:10]) - jour).days) <= 1), None)
        if trouve is not None:
            utilisees.add(trouve)
            ecartees += 1
            continue
        gardees.append(n)
    return gardees, ecartees


# ── Synchro ───────────────────────────────────────────────────────────────────

async def _toutes_les_operations(uid: str, date_from: date, psu: dict | None) -> list[dict[str, Any]]:
    operations, cle = [], None
    for _ in range(50):  # garde-fou contre une pagination infinie
        params = {"date_from": date_from.isoformat(), **({"continuation_key": cle} if cle else {})}
        page = await eb.request("GET", f"/accounts/{uid}/transactions", params=params, psu=psu)
        operations += page.get("transactions") or []
        cle = page.get("continuation_key")
        if not cle:
            break
    return operations


async def synchroniser_compte(compte: dict[str, Any], historique: dict[str, str], simulation: bool,
                             psu: dict | None = None, regles: dict[str, str] | None = None) -> dict[str, Any]:
    uid = compte["eb_account_uid"]
    existantes, reponse_soldes = await asyncio.gather(
        db.select_tout("transactions", bank_account_id=f"eq.{compte['id']}",
                       select="id,date,amount,entry_reference,status"),
        eb.request("GET", f"/accounts/{uid}/balances", psu=psu),
    )
    soldes = reponse_soldes.get("balances") or []
    dates = [str(e["date"])[:10] for e in existantes if e.get("status") != "pending"]
    depart = (date.fromisoformat(max(dates)) - timedelta(days=RECOUVREMENT_JOURS)) if dates else DEBUT_PAR_DEFAUT

    operations = await _toutes_les_operations(uid, depart, psu)
    lignes = [vers_ligne(compte, tx, historique, regles) for tx in operations]
    comptabilisees = [l for l in lignes if l["status"] == "booked"]
    en_attente = [l for l in lignes if l["status"] == "pending"]
    nouvelles, ecartees = rapprocher(comptabilisees, existantes)
    solde = choisir_solde(soldes, en_attente)

    if not simulation:
        await db.delete("transactions", bank_account_id=f"eq.{compte['id']}", status="eq.pending")
        if nouvelles or en_attente:
            await db.insert("transactions", nouvelles + en_attente)
        maintenant = datetime.now(timezone.utc).isoformat()
        await db.update("bank_accounts", {"balance": solde, "balance_at": maintenant, "last_sync_at": maintenant},
                        id=f"eq.{compte['id']}")

    return {
        "compte": f"{compte['bank']} · {compte['account_label']}",
        "depuis": depart.isoformat(),
        "solde": solde,
        "soldes_banque": {b.get("balance_type"): (b.get("balance_amount") or {}).get("amount") for b in soldes},
        "recues": len(operations),
        "nouvelles": len(nouvelles),
        "deja_connues": ecartees,
        "en_attente": len(en_attente),
        "categories": dict(Counter(l["category"] for l in nouvelles + en_attente).most_common()),
        "a_verifier": [f"{l['date']} {l['amount']:+.2f} {l['description']}"
                       for l in nouvelles + en_attente if l["category"] == "Autre"][:25],
        "entrees": [f"{l['date']} {l['amount']:+.2f} {l['category']} · {l['description']}"
                    for l in nouvelles if l["amount"] > 0 and not l["is_internal"]][:25],
    }


async def synchroniser(simulation: bool = False, psu: dict | None = None) -> list[dict[str, Any]]:
    """`psu` : en-têtes de Mohamed quand il lance la synchro lui-même (voir enable_banking.request)."""
    lignes_historique, connexions_actives, comptes, choix = await asyncio.gather(
        db.select_tout("transactions", select="id,description,merchant,category,is_internal"),
        db.select("bank_connections", status="eq.active"),
        db.select("bank_accounts", eb_account_uid="not.is.null", connection_id="not.is.null"),
        db.select("merchant_categories", select="cle,categorie"),
    )
    historique = historique_par_marchand(lignes_historique)
    regles = {r["cle"]: r["categorie"] for r in choix}
    connexions = {c["id"]: c for c in connexions_actives}

    async def un_compte(compte: dict[str, Any], connexion: dict[str, Any]) -> dict[str, Any]:
        try:
            resultat = await synchroniser_compte(compte, historique, simulation, psu, regles)
            statut, erreur = "ok", None
        except (eb.EnableBankingError, db.DatabaseError) as e:
            resultat = {"compte": f"{compte['bank']} · {compte['account_label']}", "erreur": str(e)}
            statut, erreur = "error", str(e)
            if isinstance(e, eb.EnableBankingError) and e.code in ("EXPIRED_SESSION", "REVOKED_SESSION", "CLOSED_SESSION"):
                statut = "expired"
        if not simulation:
            valeurs = {"last_sync_at": datetime.now(timezone.utc).isoformat(), "last_sync_status": statut,
                       "last_error": erreur}
            if statut == "ok":
                valeurs["last_success_at"] = valeurs["last_sync_at"]   # « en panne depuis plus de 24 h »
            if statut == "expired":
                valeurs["status"] = "expired"
            await db.update("bank_connections", valeurs, id=f"eq.{connexion['id']}")
        return resultat

    # Les comptes se synchronisent en même temps : on n'attend plus le CIC pour interroger Revolut.
    resultats = list(await asyncio.gather(*(
        un_compte(compte, connexions[compte["connection_id"]])
        for compte in comptes if compte["connection_id"] in connexions
    )))
    if not simulation:
        try:
            await objectifs.confirmer_versements()
        except db.DatabaseError:
            pass  # la synchro bancaire reste valable ; la reconnaissance réessaiera à la prochaine
    return resultats


# ── État des comptes (écran Comptes) ──────────────────────────────────────────

SEUIL_RENOUVELLEMENT_JOURS = 14     # rappel dès 14 jours avant l'expiration (orange à 7 dans l'app)


def jours_restants(valid_until: str | None, maintenant: datetime | None = None) -> int | None:
    if not valid_until:
        return None
    """En jours du calendrier (heure de Paris) : un accès jusqu'au 29/04 vu le 31/10 → 180, pas 179."""
    paris = ZoneInfo("Europe/Paris")
    fin = datetime.fromisoformat(str(valid_until).replace("Z", "+00:00")).astimezone(paris).date()
    return (fin - (maintenant or datetime.now(timezone.utc)).astimezone(paris).date()).days


def resumer_etat(connexions: list[dict[str, Any]], comptes: list[dict[str, Any]],
                 maintenant: datetime | None = None) -> dict[str, Any]:
    """Une entrée par banque : statut, consentement, dernière synchro et comptes avec leur solde."""
    banques = []
    for c in connexions:
        jours = jours_restants(c.get("valid_until"), maintenant)
        expiree = c.get("status") != "active" or (jours is not None and jours < 0)
        banques.append({
            "banque": c["aspsp_name"],
            "statut": "expiree" if expiree else ("erreur" if c.get("last_sync_status") == "error" else "ok"),
            "consentement_jusqu_au": c.get("valid_until"),
            "jours_restants": max(jours, 0) if jours is not None else None,
            "a_renouveler": expiree or (jours is not None and jours < SEUIL_RENOUVELLEMENT_JOURS),
            "derniere_synchro": c.get("last_sync_at"),
            "derniere_erreur": c.get("last_error"),
            "comptes": [{
                "id": a["id"], "libelle": a.get("account_label"), "type": a.get("account_type"),
                "solde": float(a["balance"]) if a.get("balance") is not None else None,
                "solde_au": a.get("balance_at"),
            } for a in comptes if a.get("connection_id") == c["id"]],
        })
    return {"banques": sorted(banques, key=lambda b: b["banque"]),
            "solde_total": round(sum(a["solde"] or 0 for b in banques for a in b["comptes"]), 2)}


async def etat_des_comptes() -> dict[str, Any]:
    # La connexion la plus récente de chaque banque suffit : les anciennes sont remplacées.
    connexions, vues = [], set()
    for c in await db.select("bank_connections", order="created_at.desc"):
        if c["aspsp_name"] not in vues:
            vues.add(c["aspsp_name"])
            connexions.append(c)
    comptes = await db.select("bank_accounts", eb_account_uid="not.is.null")
    return resumer_etat(connexions, comptes)
