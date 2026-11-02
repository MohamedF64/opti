import 'package:flutter_test/flutter_test.dart';
import 'package:opti/data/verrou.dart';

class CoffreMemoire implements Coffre {
  final valeurs = <String, String>{};
  @override
  Future<String?> lire(String cle) async => valeurs[cle];
  @override
  Future<void> ecrire(String cle, String valeur) async => valeurs[cle] = valeur;
  @override
  Future<void> effacer(String cle) async => valeurs.remove(cle);
}

void main() {
  final midi = DateTime(2026, 11, 1, 12);

  test('le code est gardé haché, jamais en clair, et verrouille au redémarrage', () async {
    final coffre = CoffreMemoire();
    await Verrou(coffre).definirCode('1234');
    expect(coffre.valeurs.values.any((v) => v.contains('1234')), isFalse);
    final apres = Verrou(coffre);
    await apres.charger();
    expect(apres.verrouille, isTrue);
    expect(await apres.essayer('1234'), Essai.bon);
    expect(apres.verrouille, isFalse);
  });

  test('5 codes faux d\'affilée : bloqué ; un bon code remet le compteur à zéro', () async {
    final verrou = Verrou(CoffreMemoire());
    await verrou.definirCode('1234');
    for (var i = 0; i < 4; i++) {
      expect(await verrou.essayer('0000'), Essai.faux);
    }
    expect(verrou.essaisRestants, 1);
    expect(await verrou.essayer('1234'), Essai.bon);
    expect(verrou.essaisRestants, 5);
    for (var i = 0; i < 4; i++) {
      await verrou.essayer('0000');
    }
    expect(await verrou.essayer('0000'), Essai.bloque);
    await verrou.reinitialiser();
    expect(verrou.actif, isFalse);
    expect(verrou.aRecreer, isTrue);
  });

  test('retour après 30 s : pas de verrou ; après 5 min : verrouillé (délai 1 min)', () async {
    final verrou = Verrou(CoffreMemoire());
    await verrou.definirCode('1234');
    verrou.quitter(midi);
    verrou.revenir(midi.add(const Duration(seconds: 30)));
    expect(verrou.verrouille, isFalse);
    verrou.quitter(midi);
    verrou.revenir(midi.add(const Duration(minutes: 5)));
    expect(verrou.verrouille, isTrue);
  });

  test("pendant la demande d'empreinte, l'arrière-plan ne compte pas", () async {
    late Verrou verrou;
    verrou = Verrou(
      CoffreMemoire(),
      empreinte: () async {
        verrou.quitter(midi);
        verrou.revenir(midi.add(const Duration(minutes: 2)));
        return true;
      },
    );
    await verrou.definirCode('1234');
    await verrou.activerEmpreinte(true);
    await verrou.choisirDelai(0);
    verrou.quitter(midi);
    verrou.revenir(midi);
    expect(verrou.verrouille, isTrue);
    expect(await verrou.essayerEmpreinte(), isTrue);
    expect(verrou.verrouille, isFalse);
  });
}
