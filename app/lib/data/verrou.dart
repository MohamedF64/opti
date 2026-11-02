/// Verrou de l'app : code à 4 chiffres et empreinte (règles validées par Mohamed le 01/11/2026).
/// Le code ne quitte jamais le téléphone : seule son empreinte salée est gardée, dans le coffre Android.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Stockage clé → valeur ; le vrai est le coffre Android (Keystore), les tests en donnent un en mémoire.
abstract class Coffre {
  Future<String?> lire(String cle);
  Future<void> ecrire(String cle, String valeur);
  Future<void> effacer(String cle);
}

class CoffreAndroid implements Coffre {
  static const _stockage = FlutterSecureStorage();

  @override
  Future<String?> lire(String cle) => _stockage.read(key: cle);
  @override
  Future<void> ecrire(String cle, String valeur) => _stockage.write(key: cle, value: valeur);
  @override
  Future<void> effacer(String cle) => _stockage.delete(key: cle);
}

enum Essai { bon, faux, bloque }

class Verrou extends ChangeNotifier {
  Verrou(this._coffre, {Future<bool> Function()? empreinte}) : _demanderEmpreinte = empreinte ?? _empreinteAndroid;

  static const longueur = 4;
  static const essaisMax = 5;
  static const delais = [0, 60, 300]; // secondes : immédiatement, 1 min (par défaut), 5 min

  final Coffre _coffre;
  final Future<bool> Function() _demanderEmpreinte;
  String? _hache, _sel;
  int _essais = 0;
  bool _empreinte = false, _aRecreer = false, _verrouille = false, _empreinteEnCours = false;
  int _delai = 60;
  DateTime? _parti;

  bool get actif => _hache != null;
  bool get verrouille => _verrouille;
  bool get empreinte => _empreinte;
  bool get aRecreer => _aRecreer; // déconnecté après 5 codes faux ou un oubli : proposer un nouveau code
  int get delai => _delai;
  int get essaisRestants => essaisMax - _essais;

  /// À l'ouverture de l'app : verrouillée si un code existe.
  Future<void> charger() async {
    _hache = await _coffre.lire('code_hache');
    _sel = await _coffre.lire('code_sel');
    _essais = int.tryParse(await _coffre.lire('code_essais') ?? '') ?? 0;
    _empreinte = await _coffre.lire('empreinte') == '1';
    _aRecreer = await _coffre.lire('code_a_recreer') == '1';
    _delai = int.tryParse(await _coffre.lire('delai') ?? '') ?? 60;
    _verrouille = actif;
    notifyListeners();
  }

  static String hacher(String code, String sel) {
    var valeur = utf8.encode('$sel:$code');
    for (var i = 0; i < 10000; i++) {
      valeur = Uint8List.fromList(sha256.convert(valeur).bytes);
    }
    return base64Encode(valeur);
  }

  Future<void> definirCode(String code) async {
    final hasard = Random.secure();
    _sel = base64Encode(List<int>.generate(16, (_) => hasard.nextInt(256)));
    _hache = hacher(code, _sel!);
    _essais = 0;
    _aRecreer = false;
    _verrouille = false;
    await _coffre.ecrire('code_sel', _sel!);
    await _coffre.ecrire('code_hache', _hache!);
    await _coffre.ecrire('code_essais', '0');
    await _coffre.effacer('code_a_recreer');
    notifyListeners();
  }

  /// Bon code : déverrouille. Au 5e faux code d'affilée : `bloque`, l'app doit déconnecter Mohamed.
  Future<Essai> essayer(String code) async {
    if (!actif) return Essai.bon;
    if (hacher(code, _sel!) == _hache) {
      _essais = 0;
      _verrouille = false;
      await _coffre.ecrire('code_essais', '0');
      notifyListeners();
      return Essai.bon;
    }
    _essais++;
    await _coffre.ecrire('code_essais', '$_essais');
    notifyListeners();
    return _essais >= essaisMax ? Essai.bloque : Essai.faux;
  }

  Future<bool> essayerEmpreinte() async {
    if (!actif || !_empreinte || _empreinteEnCours) return false;
    _empreinteEnCours = true;
    try {
      final ok = await _demanderEmpreinte();
      if (ok) {
        _essais = 0;
        _verrouille = false;
        await _coffre.ecrire('code_essais', '0');
        notifyListeners();
      }
      return ok;
    } finally {
      _empreinteEnCours = false;
    }
  }

  Future<void> activerEmpreinte(bool oui) async {
    _empreinte = oui;
    await _coffre.ecrire('empreinte', oui ? '1' : '0');
    notifyListeners();
  }

  Future<void> choisirDelai(int secondes) async {
    _delai = secondes;
    await _coffre.ecrire('delai', '$secondes');
    notifyListeners();
  }

  Future<void> desactiver() async {
    _hache = _sel = null;
    _empreinte = _verrouille = false;
    _essais = 0;
    for (final cle in ['code_hache', 'code_sel', 'code_essais', 'empreinte']) {
      await _coffre.effacer(cle);
    }
    notifyListeners();
  }

  /// 5 codes faux ou « Code oublié ? » : plus de code ; un nouveau sera proposé après la reconnexion.
  Future<void> reinitialiser() async {
    await desactiver();
    _aRecreer = true;
    await _coffre.ecrire('code_a_recreer', '1');
    notifyListeners();
  }

  Future<void> plusTard() async {
    _aRecreer = false;
    await _coffre.effacer('code_a_recreer');
    notifyListeners();
  }

  // ── Arrière-plan ──
  void quitter(DateTime maintenant) {
    if (_empreinteEnCours) return; // la fenêtre d'empreinte fait passer l'app en arrière-plan
    _parti ??= maintenant;
  }

  /// Retour dans l'app : verrouillée si elle est restée ailleurs au moins `delai` secondes.
  void revenir(DateTime maintenant) {
    final parti = _parti;
    _parti = null;
    if (!actif || parti == null || _empreinteEnCours) return;
    if (maintenant.difference(parti).inSeconds >= _delai) {
      _verrouille = true;
      notifyListeners();
    }
  }

  static Future<bool> empreinteDisponible() async {
    try {
      final auth = LocalAuthentication();
      return await auth.isDeviceSupported() && (await auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _empreinteAndroid() async {
    try {
      return await LocalAuthentication().authenticate(localizedReason: 'Déverrouiller Opti', biometricOnly: true);
    } catch (_) {
      return false; // annulée, trop d'essais, capteur indisponible : le pavé du code reste là
    }
  }
}

/// Fourni dans main() (ProviderScope.overrides), une fois le coffre lu.
final verrouProvider = Provider<Verrou>((ref) => throw UnimplementedError('verrouProvider non fourni'));
