import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'abonnements.dart';
import 'modeles.dart';
import 'objectifs.dart';
import 'stats.dart';

/// Coffre chiffré (clé dans le Keystore Android), comme le code du verrou.
const _coffre = FlutterSecureStorage();

/// Écriture et lecture chiffrées ; remplaçable dans les tests.
abstract class Coffre {
  Future<Map<String, String>> toutLire();
  Future<void> ecrire(String cle, String valeur);
  Future<void> effacer(String cle);
}

class CoffreChiffre implements Coffre {
  @override
  Future<Map<String, String>> toutLire() => _coffre.readAll();
  @override
  Future<void> ecrire(String cle, String valeur) => _coffre.write(key: cle, value: valeur);
  @override
  Future<void> effacer(String cle) => _coffre.delete(key: cle);
}

/// Dernières réponses du serveur (soldes, opérations, objectifs…) : à l'ouverture, les écrans s'affichent
/// tout de suite avec ces chiffres, puis se mettent à jour. Chiffrées dans le coffre et gardées en mémoire
/// (lecture immédiate pendant l'affichage) ; seules les préférences sans donnée personnelle restent en clair.
class CacheLocal {
  CacheLocal(this._prefs, this._chiffre, this._memoire);
  final SharedPreferences _prefs;
  final Coffre _chiffre;
  final Map<String, String> _memoire;

  static const _cleAccueil = 'cache_accueil', _cleObjectifs = 'cache_objectifs', _cleAbonnements = 'cache_abonnements';
  static const _prefixe = 'cache_', _prefixeStats = 'cache_stats_';

  /// Au démarrage : lit le coffre une fois. Les caches en clair des versions ≤ 0.23 y sont déplacés puis effacés.
  static Future<CacheLocal> charger(SharedPreferences prefs, Coffre chiffre) async {
    final memoire = {
      for (final e in (await chiffre.toutLire()).entries)
        if (e.key.startsWith(_prefixe)) e.key: e.value,
    };
    for (final cle in prefs.getKeys().where((c) => c.startsWith(_prefixe)).toList()) {
      final texte = prefs.getString(cle);
      if (texte != null && !memoire.containsKey(cle)) {
        await chiffre.ecrire(cle, texte);
        memoire[cle] = texte;
      }
      await prefs.remove(cle);
    }
    return CacheLocal(prefs, chiffre, memoire);
  }

  Future<void> _garder(String cle, Map<String, dynamic> json) {
    final texte = jsonEncode(json);
    _memoire[cle] = texte;
    return _chiffre.ecrire(cle, texte);
  }

  Future<void> garderAccueil(Map<String, dynamic> json) => _garder(_cleAccueil, json);
  Future<void> garderObjectifs(Map<String, dynamic> json) => _garder(_cleObjectifs, json);
  Future<void> garderAbonnements(Map<String, dynamic> json) => _garder(_cleAbonnements, json);
  Future<void> garderStats(String periode, Map<String, dynamic> json) => _garder('$_prefixeStats$periode', json);

  Accueil? accueil() => _lire(_cleAccueil, Accueil.depuisJson);
  EcranObjectifs? objectifs() => _lire(_cleObjectifs, EcranObjectifs.depuisJson);
  EcranAbonnements? abonnements() => _lire(_cleAbonnements, EcranAbonnements.depuisJson);
  EcranStats? stats(String periode) => _lire('$_prefixeStats$periode', EcranStats.depuisJson);

  /// Carte « Bilan du cycle » refermée pour ce cycle (début du cycle).
  bool bilanFerme(DateTime debut) => _prefs.getString('bilan_ferme') == debut.toIso8601String().substring(0, 10);
  Future<void> fermerBilan(DateTime debut) => _prefs.setString('bilan_ferme', debut.toIso8601String().substring(0, 10));

  /// Réglages › Apparence (gardés à la déconnexion : ce ne sont pas des données personnelles).
  Map<String, dynamic>? apparence() {
    final brut = _prefs.getString('apparence');
    return brut == null ? null : jsonDecode(brut) as Map<String, dynamic>;
  }

  Future<void> garderApparence(Map<String, Object?> json) => _prefs.setString('apparence', jsonEncode(json));

  /// « Pas maintenant » sur un conseil (sa clé change à chaque cycle).
  bool conseilMasque(String cle) => _prefs.getStringList('conseils_masques')?.contains(cle) ?? false;
  Future<void> masquerConseil(String cle) {
    final liste = [...?_prefs.getStringList('conseils_masques'), cle];
    return _prefs.setStringList('conseils_masques', liste.length > 50 ? liste.sublist(liste.length - 50) : liste);
  }

  /// À la déconnexion : rien ne doit rester sur le téléphone.
  Future<void> vider() async {
    for (final cle in _memoire.keys.toList()) {
      _memoire.remove(cle);
      await _chiffre.effacer(cle);
    }
  }

  T? _lire<T>(String cle, T Function(Map<String, dynamic>) convertir) {
    final texte = _memoire[cle];
    if (texte == null) return null;
    try {
      return convertir(jsonDecode(texte) as Map<String, dynamic>);
    } catch (_) {
      return null; // format d'une ancienne version de l'app : on attend simplement le serveur
    }
  }
}

/// Fourni dans main() (ProviderScope.overrides), une fois le coffre lu.
final cacheProvider = Provider<CacheLocal>((ref) => throw UnimplementedError('cacheProvider non fourni'));

/// Session Supabase (jeton de rafraîchissement) dans le coffre chiffré au lieu de SharedPreferences.
/// Une session enregistrée en clair par une version ≤ 0.23 y est déplacée : pas de reconnexion à faire.
class SessionChiffree extends LocalStorage {
  SessionChiffree(this.cle);
  final String cle; // « sb-<projet>-auth-token », la clé par défaut de supabase_flutter

  @override
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final enClair = prefs.getString(cle);
    if (enClair != null) {
      if (await _coffre.read(key: cle) == null) await _coffre.write(key: cle, value: enClair);
      await prefs.remove(cle);
    }
  }

  @override
  Future<bool> hasAccessToken() => _coffre.containsKey(key: cle);

  @override
  Future<String?> accessToken() => _coffre.read(key: cle);

  @override
  Future<void> removePersistedSession() => _coffre.delete(key: cle);

  @override
  Future<void> persistSession(String persistSessionString) => _coffre.write(key: cle, value: persistSessionString);
}
