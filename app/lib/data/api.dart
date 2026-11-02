import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'abonnements.dart';
import 'bons_plans.dart';
import 'cache.dart';
import 'catalogue.dart';
import 'modeles.dart';
import 'objectifs.dart';
import 'stats.dart';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Appels au backend Opti, toujours avec la session Supabase de Mohamed.
class OptiApi {
  Future<Map<String, String>> _entetes() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) throw ApiException('Session expirée : reconnecte-toi.');
    return {'Authorization': 'Bearer ${session.accessToken}', 'Content-Type': 'application/json'};
  }

  Future<Map<String, dynamic>> _requete(
    String methode,
    String chemin, {
    Object? corps,
    Duration delai = const Duration(seconds: 30),
  }) async {
    final requete = http.Request(methode, Uri.parse('$backendUrl$chemin'));
    final http.Response r;
    try {
      requete.headers.addAll(await _entetes());
      if (corps != null) requete.body = jsonEncode(corps);
      r = await http.Response.fromStream(await requete.send().timeout(delai));
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Serveur injoignable. Vérifie ta connexion internet.');
    }
    final texte = utf8.decode(r.bodyBytes);
    if (r.statusCode == 401) throw ApiException('Session expirée : reconnecte-toi.');
    if (r.statusCode >= 400) {
      String detail = texte;
      try {
        detail = (jsonDecode(texte) as Map)['detail']?.toString() ?? texte;
      } catch (_) {}
      // 409 : refus métier, message déjà rédigé pour Mohamed.
      throw ApiException(r.statusCode == 409 ? detail : 'Erreur ${r.statusCode} : $detail');
    }
    return jsonDecode(texte) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> accueil() => _requete('GET', '/budget/aujourdhui');

  /// Synchronise les banques (jusqu'à une minute si une banque est lente).
  Future<void> synchroniser() => _requete('POST', '/banque/synchro', delai: const Duration(seconds: 90));

  // ── Objectifs ──
  Future<Map<String, dynamic>> objectifs() => _requete('GET', '/objectifs');

  Future<void> creerObjectif({required String nom, required double cible, DateTime? echeance, String? icone}) =>
      _requete('POST', '/objectifs', corps: {'nom': nom, 'cible': cible, 'echeance': _jour(echeance), 'icone': icone});

  /// Seules les clés passées sont modifiées (`echeance`, `statut` : 'active' ou 'archive', …).
  Future<void> modifierObjectif(String id, Map<String, Object?> valeurs) =>
      _requete('PATCH', '/objectifs/$id', corps: valeurs.map((k, v) => MapEntry(k, v is DateTime ? _jour(v) : v)));

  /// Montant positif : mettre de côté ; négatif : piocher.
  Future<void> declarerMouvement(String objectifId, double montant, {String? note}) =>
      _requete('POST', '/objectifs/$objectifId/mouvements', corps: {'montant': montant, 'note': note});

  Future<void> confirmer(String mouvementId, {String? operationId}) =>
      _requete('POST', '/mouvements/$mouvementId/confirmer', corps: {'transaction_id': operationId});

  Future<void> contester(String mouvementId) => _requete('POST', '/mouvements/$mouvementId/contester');

  Future<void> annuler(String mouvementId) => _requete('DELETE', '/mouvements/$mouvementId');

  Future<void> attribuer(String operationId, String objectifId) =>
      _requete('POST', '/reserve/$operationId/attribuer', corps: {'objectif_id': objectifId});

  /// Les versements qu'annulerait ce retrait de la réserve (« C'était une annulation »).
  Future<List<VersementAnnulable>> proposerAnnulation(String operationId) async {
    final r = await _requete('GET', '/reserve/$operationId/annulation');
    return [for (final m in r['mouvements'] as List) VersementAnnulable.depuisJson(m)];
  }

  Future<void> annulerParRetrait(String operationId, List<String> mouvementIds) =>
      _requete('POST', '/reserve/$operationId/annuler', corps: {'mouvement_ids': mouvementIds});

  /// Historique : 14 jours jusqu'à `jusquAu` (aujourd'hui si null), ou une recherche. `suite` : date où reprendre.
  Future<({List<Operation> operations, DateTime? suite})> historique({
    DateTime? jusquAu,
    String? recherche,
    String? banque,
  }) async {
    final params = {
      if (jusquAu != null) 'jusqu_au': _jour(jusquAu)!,
      if (recherche != null && recherche.trim().isNotEmpty) 'recherche': recherche.trim(),
      'banque': ?banque,
    };
    final r = await _requete(
      'GET',
      Uri(path: '/operations', queryParameters: params.isEmpty ? null : params).toString(),
    );
    return (
      operations: [for (final o in r['operations'] as List) Operation.depuisJson(o)],
      suite: r['suite'] == null ? null : DateTime.parse(r['suite'] as String),
    );
  }

  /// Réponse à une reprise de la tirelire : `objectifId` null pour « Non, dépense normale ».
  Future<void> repondreReprise(String repriseId, String? objectifId, List<String> depenseIds) =>
      _requete('POST', '/reserve/$repriseId/reprise', corps: {'objectif_id': objectifId, 'depense_ids': depenseIds});

  /// Dépense payée avec l'épargne d'un objectif ; `objectifId` null pour la détacher.
  Future<void> rattacher(String operationId, String? objectifId) =>
      _requete('POST', '/operations/$operationId/rattacher', corps: {'objectif_id': objectifId});

  /// {"categorie", "retenu", "modifiees"} ; `retenir` applique le choix à tout le marchand, passé et futur.
  Future<Map<String, dynamic>> changerCategorie(String operationId, String categorie, {required bool retenir}) =>
      _requete('POST', '/operations/$operationId/categorie', corps: {'categorie': categorie, 'retenir': retenir});

  /// « Non, dépense normale » : la suggestion n'est plus proposée.
  Future<void> ignorerSuggestion(String operationId) => _requete('POST', '/operations/$operationId/ignorer-suggestion');

  /// {"conseils": [{cle, type, texte, montant, action}]} : 3 au maximum.
  Future<Map<String, dynamic>> conseils() => _requete('GET', '/conseils');

  /// {"bilan": {...} | null} : le cycle qui vient de finir, pendant 3 jours après la paie.
  Future<Map<String, dynamic>> bilan() => _requete('GET', '/bilan');

  // ── Notifications ──
  Future<void> enregistrerAppareil(String jeton) =>
      _requete('POST', '/notifications/appareil', corps: {'jeton': jeton, 'nom': 'Android'});

  /// {"renouvellement": true, "panne": true, "limite": true, "paie": true}
  Future<Map<String, dynamic>> reglagesNotifications() => _requete('GET', '/notifications/reglages');

  Future<Map<String, dynamic>> modifierNotifications(Map<String, bool> valeurs) =>
      _requete('PATCH', '/notifications/reglages', corps: valeurs);

  /// {"ok": n, "erreurs": n} : nombre de téléphones atteints.
  Future<Map<String, dynamic>> testerNotification() => _requete('POST', '/notifications/test');

  // ── Réglages et banques ──
  /// {"reglages": {...}, "budget": {"limite_du_jour", "limite_calculee", "limite_appliquee", "epargne_proposee", ...}}
  Future<Map<String, dynamic>> reglages() => _requete('GET', '/reglages');

  /// Même réponse, calculée avec ces réglages sans les enregistrer.
  Future<Map<String, dynamic>> apercuReglages(Map<String, Object?> essai) =>
      _requete('POST', '/reglages/apercu', corps: essai);

  Future<Map<String, dynamic>> modifierReglages(Map<String, Object?> valeurs) =>
      _requete('PATCH', '/reglages', corps: valeurs);

  /// Adresse de la page d'autorisation de la banque (renouveler l'accès ou relier un autre compte).
  Future<String> urlConnexionBanque(String banque) async =>
      (await _requete('POST', '/banque/connexion', corps: {'banque': banque}))['url'] as String;

  // ── Abonnements ──
  /// Stats : `periode` = cycle, precedent, 6 ou 12.
  Future<Map<String, dynamic>> stats(String periode) => _requete('GET', '/stats?periode=$periode');

  /// Dépenses d'une part du donut entre deux dates (« Le reste » : plusieurs catégories).
  Future<List<Operation>> operationsCategorie(DateTime debut, DateTime fin, List<String> categories) async {
    final r = await _requete(
      'GET',
      Uri(
        path: '/stats/operations',
        queryParameters: {'debut': _jour(debut)!, 'fin': _jour(fin)!, 'categorie': categories},
      ).toString(),
    );
    return [for (final o in r['operations'] as List) Operation.depuisJson(o)];
  }

  Future<Map<String, dynamic>> abonnements() => _requete('GET', '/abonnements');

  Future<void> creerAbonnement({
    required String nom,
    required double montant,
    String frequence = 'mensuel',
    String? categorie,
    String? libelle,
    DateTime? essaiJusquAu,
  }) => _requete(
    'POST',
    '/abonnements',
    corps: {
      'nom': nom,
      'montant': montant,
      'frequence': frequence,
      'categorie': categorie,
      'libelle': libelle,
      if (essaiJusquAu != null) 'essai_jusqu_au': essaiJusquAu.toIso8601String().substring(0, 10),
    },
  );

  /// Clés : nom, montant, montant_auto, frequence, categorie, usage, libelles, mois_pause, statut, essai_garde.
  Future<void> modifierAbonnement(String id, Map<String, Object?> valeurs) =>
      _requete('PATCH', '/abonnements/$id', corps: valeurs);

  Future<void> supprimerAbonnement(String id) => _requete('DELETE', '/abonnements/$id');

  Future<void> accepterPrix(String id) => _requete('POST', '/abonnements/$id/prix-ok');

  Future<void> depassementVu(String id) => _requete('POST', '/abonnements/$id/depassement-vu');

  Future<void> ajouterDetecte(String cle, {String? nom}) =>
      _requete('POST', '/abonnements/detectes/$cle/ajouter', corps: {'nom': nom});

  Future<void> refuserDetecte(String cle) => _requete('POST', '/abonnements/detectes/$cle/refuser');

  // ── Catalogue de prix ──
  Future<Map<String, dynamic>> catalogue() => _requete('GET', '/catalogue');

  /// Clés : etudiant, moins_26, age_18_24.
  Future<void> modifierProfil(Map<String, bool> valeurs) => _requete('PATCH', '/catalogue/profil', corps: valeurs);

  /// Lignes d'un abonnement : [{nom, offre_id, prix, go}] ; liste vide = détaché du catalogue.
  Future<void> changerLignes(String abonnementId, List<Map<String, Object?>> lignes) =>
      _requete('PUT', '/abonnements/$abonnementId/lignes', corps: {'lignes': lignes});

  /// « Une page de prix a changé » : offre → nouveau prix ; vide = « Rien ne change ».
  Future<void> validerPage(String serviceId, Map<String, double> prix) =>
      _requete('POST', '/catalogue/services/$serviceId/valider', corps: {'prix': prix});

  /// Vérifiée à la main : `prix` null = toujours le même prix.
  Future<void> verifierOffre(String offreId, double? prix) =>
      _requete('POST', '/catalogue/offres/$offreId/verifier', corps: {'prix': prix});

  // ── Bons plans ──
  Future<Map<String, dynamic>> bonsPlans() => _requete('GET', '/bons-plans');

  /// Ajouter (`suivie` vrai) ou retirer une enseigne.
  Future<void> choisirEnseigne(String nom, bool suivie) =>
      _requete('POST', '/bons-plans/enseignes', corps: {'nom': nom, 'suivie': suivie});

  static String? _jour(DateTime? d) =>
      d == null ? null : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final apiProvider = Provider((ref) => OptiApi());

/// Données de l'accueil ; `ref.invalidate(accueilProvider)` pour recharger. Chaque réponse est gardée
/// en cache pour la prochaine ouverture.
final accueilProvider = FutureProvider<Accueil>((ref) async {
  final json = await ref.watch(apiProvider).accueil();
  await ref.read(cacheProvider).garderAccueil(json);
  return Accueil.depuisJson(json);
});

/// Données de l'écran Objectifs ; à invalider après chaque action.
final objectifsProvider = FutureProvider<EcranObjectifs>((ref) async {
  final json = await ref.watch(apiProvider).objectifs();
  await ref.read(cacheProvider).garderObjectifs(json);
  return EcranObjectifs.depuisJson(json);
});

/// Données de l'écran Abonnements ; à invalider après chaque action.
final abonnementsProvider = FutureProvider<EcranAbonnements>((ref) async {
  final json = await ref.watch(apiProvider).abonnements();
  await ref.read(cacheProvider).garderAbonnements(json);
  return EcranAbonnements.depuisJson(json);
});

/// Stats d'une période (cycle, precedent, 6 ou 12), gardées en cache comme les autres écrans.
final statsProvider = FutureProvider.family<EcranStats, String>((ref, periode) async {
  final json = await ref.watch(apiProvider).stats(periode);
  await ref.read(cacheProvider).garderStats(periode, json);
  return EcranStats.depuisJson(json);
});

/// Écran Catalogue ; à invalider après chaque action.
final catalogueProvider = FutureProvider<DonneesCatalogue>(
  (ref) async => DonneesCatalogue.depuisJson(await ref.watch(apiProvider).catalogue()),
);

/// Page Bons plans ; à invalider après chaque choix d'enseigne.
final bonsPlansProvider = FutureProvider<DonneesBonsPlans>(
  (ref) async => DonneesBonsPlans.depuisJson(await ref.watch(apiProvider).bonsPlans()),
);
