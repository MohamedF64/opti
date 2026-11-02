/// Données renvoyées par GET /abonnements (voir opti-backend/api/abonnements.py).
library;

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
double? _dn(Object? v) => (v as num?)?.toDouble();
DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);

class Prelevement {
  Prelevement.depuisJson(Map<String, dynamic> j)
    : date = DateTime.parse(j['date']),
      montant = _d(j['montant']),
      libelle = j['libelle'] ?? '';

  final DateTime date;
  final double montant;
  final String libelle;
}

class Abonnement {
  Abonnement.depuisJson(Map<String, dynamic> j)
    : id = j['id'],
      nom = j['nom'],
      categorie = j['categorie'],
      frequence = j['frequence'] ?? 'mensuel',
      montant = _d(j['montant']),
      montantMin = _dn(j['montant_min']),
      montantMax = _dn(j['montant_max']),
      variable = j['variable'] == true,
      parMois = _d(j['par_mois']),
      statut = j['statut'],
      usage = j['usage'],
      verdict = j['verdict'],
      economieParAn = _dn(j['economie_par_an']),
      dernierPrelevement = _date(j['dernier_prelevement']),
      prochainPrelevement = _date(j['prochain_prelevement']),
      moisPause = [for (final m in (j['mois_pause'] as List?) ?? const []) m as int],
      changementPrix = j['changement_prix'] == null
          ? null
          : (
              ancien: _d(j['changement_prix']['ancien']),
              nouveau: _d(j['changement_prix']['nouveau']),
              depuis: DateTime.parse(j['changement_prix']['depuis']),
            ),
      libelles = [for (final l in (j['libelles'] as List?) ?? const []) l as String],
      montantManuel = j['montant_manuel'] == true,
      historique = [for (final p in (j['historique'] as List?) ?? const []) Prelevement.depuisJson(p)],
      essaiJusquAu = _date(j['essai_jusqu_au']),
      prixMaximum = _dn(j['prix_maximum']),
      depassement = j['depassement'] == null
          ? null
          : (date: DateTime.parse(j['depassement']['date']), montant: _d(j['depassement']['montant']));

  final String id, nom, frequence, statut, verdict;
  final String? categorie, usage;
  final double montant, parMois;
  final double? montantMin, montantMax, economieParAn;
  final bool variable, montantManuel;
  final DateTime? dernierPrelevement, prochainPrelevement;
  final List<int> moisPause;
  final ({double ancien, double nouveau, DateTime depuis})? changementPrix;
  final List<String> libelles;
  final List<Prelevement> historique;
  final DateTime? essaiJusquAu; // essai gratuit pas encore prélevé
  final double? prixMaximum; // ce que le contrat peut coûter au plus (saisi à la main)
  final ({DateTime date, double montant})? depassement; // dernier prélèvement au-dessus du maximum, pas encore vu

  bool get resilie => statut == 'resilie';
  bool get essai => statut == 'essai';
  bool get essaiTermine => statut == 'essai_termine';
  bool get aVerifier => statut == 'a_verifier';
}

/// « Nouvel abonnement ? » proposé par la détection.
class AbonnementDetecte {
  AbonnementDetecte.depuisJson(Map<String, dynamic> j)
    : cle = j['cle'],
      libelle = j['libelle'] ?? '',
      montant = _d(j['montant']),
      frequence = j['frequence'] ?? 'mensuel',
      dernier = DateTime.parse(j['dernier']);

  final String cle, libelle, frequence;
  final double montant;
  final DateTime dernier;
}

class EcranAbonnements {
  EcranAbonnements.depuisJson(Map<String, dynamic> j)
    : totalParMois = _d(j['total_par_mois']),
      fourchette = j['fourchette'] == null ? null : (min: _d(j['fourchette']['min']), max: _d(j['fourchette']['max'])),
      nombreSuivis = j['nombre_suivis'] as int? ?? 0,
      rentables = j['rentables'] as int? ?? 0,
      abonnements = [for (final a in j['abonnements'] as List) Abonnement.depuisJson(a)],
      detectes = [for (final d in (j['detectes'] as List?) ?? const []) AbonnementDetecte.depuisJson(d)];

  final double totalParMois;
  final ({double min, double max})? fourchette; // total au plus bas et au plus haut (montants variables)
  final int nombreSuivis, rentables;
  final List<Abonnement> abonnements;
  final List<AbonnementDetecte> detectes;
}
