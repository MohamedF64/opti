import 'package:flutter_test/flutter_test.dart';
import 'package:opti/data/abonnements.dart';
import 'package:opti/data/catalogue.dart';
import 'package:opti/util/texte.dart';

import 'catalogue_test.dart' show offre;

Map<String, dynamic> service(String id, String nom, String famille, List<Map<String, dynamic>> offres) => {
  'id': id,
  'nom': nom,
  'famille': famille,
  'page_url': null,
  'offres': offres,
};

void main() {
  test('recherche sans accents ni majuscules', () {
    expect(correspond('ecouteurs', 'Écouteurs Bluetooth'), isTrue);
    expect(correspond('PRIME  amazon', 'Amazon Prime étudiant'), isTrue);
    expect(correspond('prime netflix', 'Amazon Prime'), isFalse);
  });

  test("catalogue : un service trouvé garde toutes ses offres, sinon seules les offres trouvées", () {
    final d = DonneesCatalogue.depuisJson({
      'profil': <String, dynamic>{},
      'abonnements': <dynamic>[],
      'catalogue': [
        service('s1', 'Amazon Prime', 'prime', [
          offre('o1', 'Amazon Prime', 'Mensuel', 6.99),
          offre('o2', 'Amazon Prime', 'Étudiant', 3.49),
        ]),
        service('s2', 'Sosh', 'mobile', [
          offre('o3', 'Sosh', 'Forfait 40 Go', 10.99),
          offre('o4', 'Sosh', 'Forfait 5G 130 Go', 15.99),
        ]),
      ],
    });
    final prime = d.chercher('prime');
    expect([for (final (s, o) in prime) '${s.nom}:${o.length}'], ['Amazon Prime:2']);
    final cinqG = d.chercher('5g');
    expect([for (final (s, o) in cinqG) '${s.nom}:${o.map((x) => x.nom).join(',')}'], ['Sosh:Forfait 5G 130 Go']);
    expect(d.chercher('etudiant').single.$2.single.nom, 'Étudiant');
    expect(d.chercher('netflix'), isEmpty);
  });

  test('total estimé : fourchette et prix maximum lus depuis le serveur', () {
    final e = EcranAbonnements.depuisJson({
      'total_par_mois': 148.81,
      'fourchette': {'min': 148.14, 'max': 156.14},
      'abonnements': [
        {
          'id': 'px',
          'nom': 'Prixtel',
          'montant': 15.65,
          'par_mois': 15.65,
          'variable': true,
          'montant_min': 14.98,
          'montant_max': 16.98,
          'statut': 'actif',
          'verdict': 'rentable',
          'prix_maximum': 22.98,
          'depassement': {'id': 'p3', 'date': '2026-11-04', 'montant': 24.98},
        },
      ],
    });
    expect((e.fourchette!.min, e.fourchette!.max), (148.14, 156.14));
    final a = e.abonnements.single;
    expect((a.prixMaximum, a.depassement!.montant), (22.98, 24.98));
    expect(EcranAbonnements.depuisJson({'total_par_mois': 10, 'abonnements': <dynamic>[]}).fourchette, isNull);
  });
}
