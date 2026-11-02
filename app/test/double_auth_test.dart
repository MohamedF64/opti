import 'package:flutter_test/flutter_test.dart';
import 'package:opti/data/double_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const aal1 = AuthenticatorAssuranceLevels.aal1, aal2 = AuthenticatorAssuranceLevels.aal2;

  test('sans session : écran de connexion', () {
    expect(etapeConnexion(session: false), EtapeConnexion.connexion);
  });

  test('mot de passe tapé, code déjà activé : on demande le code', () {
    expect(etapeConnexion(session: true, niveau: aal1, prochain: aal2), EtapeConnexion.saisirCode);
  });

  test('mot de passe tapé, aucun code enregistré : activation obligatoire', () {
    expect(etapeConnexion(session: true, niveau: aal1, prochain: aal1), EtapeConnexion.activerCode);
  });

  test('code validé à la connexion : Opti s’ouvre, sans le redemander aux ouvertures suivantes', () {
    expect(etapeConnexion(session: true, niveau: aal2, prochain: aal2), EtapeConnexion.ouverte);
  });

  test('la clé à recopier est découpée par 4', () {
    expect(cleLisible('JBSWY3DPEHPK3PXPAB'), 'JBSW Y3DP EHPK 3PXP AB');
  });
}
