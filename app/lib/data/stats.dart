/// Écran Stats (GET /stats) : cycles de paie, donut par catégorie, bilan — docs/regles-de-calcul.md § 8.
library;

double _d(Object? v) => v == null ? 0 : (v is num ? v.toDouble() : double.parse(v.toString()));

class CycleStats {
  CycleStats.depuisJson(Map<String, dynamic> j)
    : debut = DateTime.parse(j['debut'] as String),
      fin = DateTime.parse(j['fin'] as String),
      enCours = j['en_cours'] == true,
      jours = j['jours'] as int,
      depense = _d(j['depense']),
      entre = _d(j['entre']),
      reste = _d(j['reste']),
      payeParEpargne = _d(j['paye_par_epargne']),
      joursSousLimite = j['jours_sous_limite'] as int;

  final DateTime debut, fin;
  final bool enCours;
  final int jours, joursSousLimite;
  final double depense, entre, reste, payeParEpargne;
}

class CategorieStats {
  CategorieStats.depuisJson(Map<String, dynamic> j)
    : nom = j['nom'] as String,
      montant = _d(j['montant']),
      part = _d(j['part']),
      nombre = j['nombre'] as int,
      ecart = j['ecart'] == null ? null : _d(j['ecart']),
      pourcent = (j['pourcent'] as num?)?.round(),
      nouveau = j['nouveau'] == true,
      inclut = [for (final c in j['inclut'] as List? ?? const []) c as String];

  final String nom;
  final double montant, part;
  final int nombre;
  final double? ecart; // seulement au-delà de 10 % et 20 €
  final int? pourcent;
  final bool nouveau;
  final List<String> inclut; // « Le reste » : les catégories regroupées

  /// Catégories à demander au serveur quand on touche cette part.
  List<String> get categories => inclut.isNotEmpty ? inclut : [nom];
}

class EcranStats {
  EcranStats.depuisJson(Map<String, dynamic> j)
    : periode = j['periode'] as String,
      cycles = [for (final c in j['cycles'] as List) CycleStats.depuisJson(c)],
      moyenne = j['moyenne'] == null ? null : _d(j['moyenne']),
      depense = _d(j['depense']),
      entre = _d(j['entre']),
      reste = _d(j['reste']),
      payeParEpargne = _d(j['paye_par_epargne']),
      categories = [for (final c in j['categories'] as List) CategorieStats.depuisJson(c)];

  final String periode;
  final List<CycleStats> cycles; // du plus ancien au plus récent
  final double? moyenne; // des cycles terminés
  final double depense, entre, reste, payeParEpargne;
  final List<CategorieStats> categories;

  int get joursSousLimite => cycles.fold(0, (s, c) => s + c.joursSousLimite);
  int get jours => cycles.fold(0, (s, c) => s + c.jours);
}
