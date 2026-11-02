import 'package:flutter_test/flutter_test.dart';
import 'package:opti/data/stats.dart';

void main() {
  test('lit la réponse de GET /stats (cycle précédent, chiffres réels du 31/10/2026)', () {
    final s = EcranStats.depuisJson({
      'periode': 'precedent',
      'cycles': [
        {
          'debut': '2026-09-25',
          'fin': '2026-10-25',
          'en_cours': false,
          'jours': 31,
          'depense': 1023.93,
          'entre': 1103.13,
          'reste': 79.2,
          'paye_par_epargne': 0,
          'jours_sous_limite': 20,
        },
      ],
      'moyenne': 1023.93,
      'depense': 1023.93,
      'entre': 1103.13,
      'reste': 79.2,
      'paye_par_epargne': 0,
      'categories': [
        {
          'nom': 'Alimentation',
          'montant': 434.93,
          'part': 42.5,
          'nombre': 28,
          'precedent': 279.14,
          'ecart': 155.79,
          'pourcent': 56,
          'nouveau': false,
          'inclut': [],
        },
        {
          'nom': 'Le reste',
          'montant': 140.09,
          'part': 13.7,
          'nombre': 10,
          'precedent': null,
          'ecart': null,
          'pourcent': null,
          'nouveau': false,
          'inclut': ['Restauration', 'Abonnement'],
        },
      ],
    });
    expect(s.cycles.single.joursSousLimite, 20);
    expect((s.joursSousLimite, s.jours), (20, 31));
    expect(s.categories.first.pourcent, 56);
    expect(s.categories.first.categories, ['Alimentation']);
    expect(s.categories.last.categories, ['Restauration', 'Abonnement']);
  });
}
