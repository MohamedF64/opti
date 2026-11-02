import 'package:flutter_test/flutter_test.dart';
import 'package:opti/data/bons_plans.dart';

Map<String, dynamic> bon(String id, String suivie, {String type = 'enseigne'}) => {
  'id': id,
  'titre': 'Bon plan $id',
  'lien': 'https://www.dealabs.com/bons-plans/$id',
  'enseigne': suivie,
  'prix': '10€',
  'publie_le': '2026-11-01T11:53:42+01:00',
  'type': type,
  'suivie': suivie,
};

void main() {
  test('groupés par enseigne, la plus fournie en premier ; une enseigne retirée disparaît tout de suite', () {
    final d = DonneesBonsPlans.depuisJson({
      'bons_plans': [
        bon('1', 'Fnac'),
        bon('2', 'Amazon'),
        bon('3', 'Amazon'),
        bon('4', 'Aliexpress'), // retirée depuis la collecte
        bon('5', 'Claude', type: 'essai'),
      ],
      'enseignes': [
        {'nom': 'Amazon', 'cle': 'amazon', 'origine': 'depenses', 'total': 50.0},
        {'nom': 'Fnac', 'cle': 'fnac', 'origine': 'ajoutee', 'total': null},
      ],
      'retirees': ['Aliexpress'],
    });
    expect(d.parEnseigne.keys, ['Amazon', 'Fnac']);
    expect(d.essais.map((b) => b.suivie), ['Claude']);
    expect(d.enseignes.map((e) => e.depenses), [true, false]);
    expect(d.retirees, ['Aliexpress']);
    // Recherche : titre ou enseigne, sans accents ni majuscules ; jamais une enseigne retirée.
    expect(d.chercher('amazon').map((b) => b.id), ['2', '3']);
    expect(d.chercher('BON PLAN 1').map((b) => b.id), ['1']);
    expect(d.chercher('aliexpress'), isEmpty);
  });

  test('« ecouteurs » trouve « Écouteurs »', () {
    final d = DonneesBonsPlans.depuisJson({
      'bons_plans': [
        {...bon('6', 'Fnac'), 'titre': 'Écouteurs sans fil à 29€'},
      ],
      'enseignes': [
        {'nom': 'Fnac', 'cle': 'fnac', 'origine': 'ajoutee', 'total': null},
      ],
    });
    expect(d.chercher('ecouteurs fnac').map((b) => b.id), ['6']);
  });
}
