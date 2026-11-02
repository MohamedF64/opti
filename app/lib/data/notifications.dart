/// Notifications push (Firebase Cloud Messaging) — règles : docs/regles-de-calcul.md § 10 du backend.
/// Le serveur décide et envoie ; l'app demande l'autorisation, donne son jeton et ouvre le bon écran.
library;

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'api.dart';

/// Types et libellés, dans l'ordre des Réglages (mêmes clés que `notifications.TYPES` côté serveur).
const typesNotifications = {
  'limite': ('Limite du jour dépassée', 'Une fois par jour au plus'),
  'paie': ('Paie reçue', 'Avec ton budget du cycle'),
  'renouvellement': ('Accès bancaire à renouveler', '14, 7 et 1 jour(s) avant'),
  'panne': ('Synchro en panne', 'Banque muette depuis plus de 24 h, accès expiré'),
  'essai': ('Essais gratuits', 'Fin dans 3 jours et demain, avec le nom du service'),
  'abonnement': ('Abonnements', 'Changement de prix, nouvel abonnement détecté'),
  'catalogue': ('Catalogue de prix', "Une page de prix officielle a changé (vérifiée le 1er du mois)"),
  'promos': ('Soldes et Black Friday', 'La veille à 12 h, pour penser à ta marge'),
};

StreamSubscription<String>? _rafraichissement;

/// À chaque ouverture (session active) : autorisation (Android 13+), puis jeton envoyé au serveur.
/// Silencieux en cas d'échec : l'app marche sans notifications.
Future<void> enregistrerTelephone(OptiApi api) async {
  try {
    final messagerie = FirebaseMessaging.instance;
    final autorisation = await messagerie.requestPermission();
    if (autorisation.authorizationStatus == AuthorizationStatus.denied) return;
    // getToken / onTokenRefresh : dépréciés au profit de register() / onRegistered (identifiant d'installation),
    // mais c'est le jeton que l'envoi du serveur (API HTTP v1, champ `token`) attend. À revoir à leur retrait.
    // ignore: deprecated_member_use
    final jeton = await messagerie.getToken();
    if (jeton != null) await api.enregistrerAppareil(jeton);
    // ignore: deprecated_member_use
    _rafraichissement ??= messagerie.onTokenRefresh.listen((nouveau) => api.enregistrerAppareil(nouveau));
  } catch (_) {}
}

/// Écran à ouvrir quand on touche une notification : « reglages », « abonnements », « catalogue » ou « accueil ».
String ecranDe(RemoteMessage message) => message.data['ecran'] as String? ?? 'accueil';
