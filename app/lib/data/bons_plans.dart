/// Données renvoyées par GET /bons-plans (voir opti-backend/api/bons_plans.py, règles § 12 point 3).
library;

import '../util/texte.dart';

class BonPlan {
  BonPlan.depuisJson(Map<String, dynamic> j)
    : id = j['id'],
      titre = j['titre'] ?? '',
      lien = j['lien'],
      enseigne = j['enseigne'],
      prix = j['prix'],
      publieLe = DateTime.parse(j['publie_le']).toLocal(),
      type = j['type'],
      suivie = j['suivie'];

  final String id, titre, lien, type, suivie;
  final String? enseigne, prix;
  final DateTime publieLe;

  bool get essai => type == 'essai';
}

class EnseigneSuivie {
  EnseigneSuivie.depuisJson(Map<String, dynamic> j)
    : nom = j['nom'],
      depenses = j['origine'] == 'depenses',
      total = (j['total'] as num?)?.toDouble();

  final String nom;
  final bool depenses; // déduite des dépenses, sinon ajoutée par Mohamed
  final double? total;
}

class DonneesBonsPlans {
  DonneesBonsPlans.depuisJson(Map<String, dynamic> j)
    : enseignes = [for (final e in j['enseignes'] as List) EnseigneSuivie.depuisJson(e)],
      retirees = [for (final r in (j['retirees'] as List?) ?? const []) r as String],
      _bons = [for (final b in j['bons_plans'] as List) BonPlan.depuisJson(b)];

  final List<EnseigneSuivie> enseignes;
  final List<String> retirees;
  final List<BonPlan> _bons;

  /// Essais gratuits, puis les bons plans des enseignes encore suivies (une enseigne retirée disparaît tout de
  /// suite, sans attendre que ses bons plans aient 7 jours).
  List<BonPlan> get essais => [
    for (final b in _bons)
      if (b.essai) b,
  ];

  /// Recherche dans le titre et l'enseigne, sans tenir compte des majuscules ni des accents (« ecouteurs » trouve
  /// « Écouteurs ») ; les plus récents d'abord.
  List<BonPlan> chercher(String texte) {
    final suivies = {for (final e in enseignes) e.nom};
    return [
      for (final b in _bons)
        if ((b.essai || suivies.contains(b.suivie)) && correspond(texte, '${b.titre} ${b.suivie} ${b.enseigne ?? ''}'))
          b,
    ]..sort((a, b) => b.publieLe.compareTo(a.publieLe));
  }

  Map<String, List<BonPlan>> get parEnseigne {
    final suivies = {for (final e in enseignes) e.nom};
    final groupes = <String, List<BonPlan>>{};
    for (final b in _bons) {
      if (!b.essai && suivies.contains(b.suivie)) groupes.putIfAbsent(b.suivie, () => []).add(b);
    }
    return Map.fromEntries(groupes.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length)));
  }
}
