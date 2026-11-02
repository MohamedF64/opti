/// Double authentification : mot de passe + code à 6 chiffres d'une app comme Google Authenticator.
/// Le backend refuse toute session sans le code (« aal2 »), la base aussi.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

enum EtapeConnexion { connexion, activerCode, saisirCode, ouverte }

/// Ce que l'app doit montrer. Le code ne se tape qu'à la connexion : la session garde ensuite son niveau aal2.
EtapeConnexion etapeConnexion({
  required bool session,
  AuthenticatorAssuranceLevels? niveau,
  AuthenticatorAssuranceLevels? prochain,
}) {
  if (!session) return EtapeConnexion.connexion;
  if (niveau == AuthenticatorAssuranceLevels.aal2) return EtapeConnexion.ouverte;
  if (prochain == AuthenticatorAssuranceLevels.aal2) return EtapeConnexion.saisirCode;
  return EtapeConnexion.activerCode; // aucun code enregistré : activation obligatoire
}

EtapeConnexion etapeActuelle(GoTrueClient auth) {
  final aal = auth.mfa.getAuthenticatorAssuranceLevel();
  return etapeConnexion(session: auth.currentSession != null, niveau: aal.currentLevel, prochain: aal.nextLevel);
}

/// Clé à recopier à la main, par groupes de 4 : « JBSW Y3DP EHPK 3PXP ».
String cleLisible(String secret) =>
    [for (var i = 0; i < secret.length; i += 4) secret.substring(i, i + 4 > secret.length ? secret.length : i + 4)]
        .join(' ');

/// Nouveau code TOTP. Les essais non confirmés (activation abandonnée) sont retirés d'abord.
Future<TOTPEnrollment> commencerActivation(GoTrueClient auth, void Function(String id) garderId) async {
  final facteurs = await auth.mfa.listFactors();
  for (final f in facteurs.all.where((f) => f.status == FactorStatus.unverified)) {
    await auth.mfa.unenroll(f.id);
  }
  final r = await auth.mfa.enroll(issuer: 'Opti', friendlyName: 'Opti ${DateTime.now().millisecondsSinceEpoch}');
  garderId(r.id);
  return r.totp!;
}

/// Code enregistré à utiliser à la connexion.
String? facteurVerifie(GoTrueClient auth) => auth.currentUser?.factors
    ?.where((f) => f.factorType == FactorType.totp && f.status == FactorStatus.verified)
    .firstOrNull
    ?.id;
