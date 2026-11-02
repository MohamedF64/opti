import 'package:flutter_test/flutter_test.dart';
import 'package:opti/util/format.dart';
import 'package:opti/data/modeles.dart';

void main() {
  test('montants au format français', () {
    expect(euros(44.93), '44,93 €');
    expect(euros(1850.00), '1 850,00 €');
    expect(eurosSignes(-5.3), '−5,30 €');
    expect(eurosSignes(30), '+30,00 €');
  });

  test('jour et mois', () {
    expect(jourMois(DateTime(2026, 11, 3)), '03/11');
  });

  test('il y a…', () {
    final maintenant = DateTime(2026, 10, 30, 12);
    expect(ilYa(DateTime(2026, 10, 30, 9), maintenant: maintenant), 'il y a 3 h');
    expect(ilYa(DateTime(2026, 10, 30, 11, 48), maintenant: maintenant), 'il y a 12 min');
    expect(ilYa(DateTime(2026, 10, 29, 9), maintenant: maintenant), 'hier');
  });

  test('titre du jour', () {
    final m = DateTime(2026, 10, 31, 15);
    expect(titreJour(DateTime(2026, 10, 31), maintenant: m), "Aujourd'hui");
    expect(titreJour(DateTime(2026, 10, 30), maintenant: m), 'Hier');
    expect(titreJour(DateTime(2026, 10, 26), maintenant: m), 'Lundi 26 octobre');
    expect(titreJour(DateTime(2025, 11, 1), maintenant: m), 'Samedi 1er novembre 2025');
  });

  test('date longue', () {
    expect(dateLongue(DateTime(2027, 7, 27)), '27 juillet 2027');
    expect(dateLongue(DateTime(2026, 11, 1)), '1er novembre 2026');
  });

  test("lecture d'un montant tapé", () {
    expect(lireMontant('150'), 150);
    expect(lireMontant('150,5'), 150.5);
    expect(lireMontant('1 200,00 €'), 1200);
    expect(lireMontant('abc'), isNull);
  });

  test("reste après aujourd'hui et limite de demain (cas du 31/10)", () {
    final b = Budget.depuisJson({
      'debut_cycle': '2026-10-26',
      'paie': 1850.00,
      'paie_au_plus_tot': '2026-11-21',
      'paie_au_plus_tard': '2026-11-28',
      'paie_en_retard': false,
      'jours_restants': 28,
      'epargne_visee': 0,
      'source_epargne': 'aucune',
      'abonnements_a_venir': [],
      'depense_aujourdhui': 204.55,
      'reste_du_cycle': 1705.88,
      'limite_calculee': 60.92,
      'limite_du_jour': 60.92,
      'tu_peux_encore': -143.63,
      'limite_appliquee': 'calculee',
      'effet_limite_manuelle': 0,
      'pourquoi': [],
    });
    expect(b.resteApresAujourdhui, closeTo(1501.33, 0.001));
    expect(b.limiteDemain, closeTo(55.60, 0.01));
  });
}
