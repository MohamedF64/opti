/// Réglages › Apparence : thème, mode et fond, gardés sur le téléphone (docs/refonte-apparence.md du backend).
library;

import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/opti_theme.dart';
import 'cache.dart';

/// Fond des écrans principaux : animé, couleur unie du thème, ou image importée.
enum Fond { anime, uni, image }

/// Dossier privé de l'app (fixé dans main) : l'image importée y est copiée, référencée par son seul nom.
String? dossierApp;

@immutable
class Apparence {
  const Apparence({
    this.theme = OptiTheme.holocron,
    this.mode = ThemeMode.system, // Auto par défaut (choix de Mohamed le 01/11/2026)
    this.fond = Fond.anime,
    this.image,
    this.flou = 8,
    this.voile = .35,
    this.accentImage = false,
    this.couleurImage,
  });

  final OptiTheme theme;
  final ThemeMode mode;
  final Fond fond;
  final String? image; // nom du fichier dans dossierApp
  final double flou; // 0 à 20 px
  final double voile; // 0 à 0,7
  final bool accentImage;
  final int? couleurImage; // couleur dominante de l'image (ARGB)

  String? get cheminImage => image == null || dossierApp == null ? null : '$dossierApp/$image';

  Apparence copyWith({
    OptiTheme? theme,
    ThemeMode? mode,
    Fond? fond,
    String? image,
    double? flou,
    double? voile,
    bool? accentImage,
    int? couleurImage,
  }) => Apparence(
    theme: theme ?? this.theme,
    mode: mode ?? this.mode,
    fond: fond ?? this.fond,
    image: image ?? this.image,
    flou: flou ?? this.flou,
    voile: voile ?? this.voile,
    accentImage: accentImage ?? this.accentImage,
    couleurImage: couleurImage ?? this.couleurImage,
  );

  Map<String, Object?> enJson() => {
    'theme': theme.name,
    'mode': mode.name,
    'fond': fond.name,
    'image': image,
    'flou': flou,
    'voile': voile,
    'accent_image': accentImage,
    'couleur_image': couleurImage,
  };

  static Apparence depuisJson(Map<String, dynamic>? j) => Apparence(
    theme: OptiTheme.values.asNameMap()[j?['theme']] ?? OptiTheme.holocron,
    mode: ThemeMode.values.asNameMap()[j?['mode']] ?? ThemeMode.system,
    fond: Fond.values.asNameMap()[j?['fond']] ?? Fond.anime,
    image: j?['image'] as String?,
    flou: (j?['flou'] as num?)?.toDouble() ?? 8,
    voile: (j?['voile'] as num?)?.toDouble() ?? .35,
    accentImage: j?['accent_image'] == true,
    couleurImage: j?['couleur_image'] as int?,
  );

  /// Accent de l'image, ajusté pour rester lisible dans le mode actif ; null s'il n'est pas utilisé.
  Color? accentPour(Brightness luminosite) {
    if (!accentImage || fond != Fond.image || couleurImage == null) return null;
    return accentLisible(Color(couleurImage!), luminosite);
  }
}

/// Comme la maquette : en sombre, éclaircir jusqu'à 55 % de luminance ; en clair, assombrir jusqu'à 40 %.
Color accentLisible(Color c, Brightness luminosite) {
  var r = c.r * 255, g = c.g * 255, b = c.b * 255;
  double l() => (.2126 * r + .7152 * g + .0722 * b) / 255;
  if (luminosite == Brightness.dark && l() < .55) {
    final k = (.55 - l()) / (1 - l());
    (r, g, b) = (r + (255 - r) * k, g + (255 - g) * k, b + (255 - b) * k);
  } else if (luminosite == Brightness.light && l() > .4) {
    final k = .4 / l();
    (r, g, b) = (r * k, g * k, b * k);
  }
  return Color.fromARGB(255, r.round().clamp(0, 255), g.round().clamp(0, 255), b.round().clamp(0, 255));
}

/// Couleur dominante : moyenne des pixels pondérée par leur saturation (les gris comptent peu).
Future<int?> couleurDominante(String chemin) async {
  try {
    final codec = await ui.instantiateImageCodec(await File(chemin).readAsBytes(), targetWidth: 40, targetHeight: 40);
    final image = (await codec.getNextFrame()).image;
    final pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
    var r = 0.0, g = 0.0, b = 0.0, poids = 0.0;
    for (var i = 0; i < pixels.length; i += 4) {
      final (pr, pg, pb) = (pixels[i], pixels[i + 1], pixels[i + 2]);
      final mx = max(pr, max(pg, pb)), mn = min(pr, min(pg, pb));
      final saturation = mx == 0 ? 0.0 : (mx - mn) / mx;
      final k = saturation * saturation * (mx / 255) + .001;
      r += pr * k;
      g += pg * k;
      b += pb * k;
      poids += k;
    }
    return Color.fromARGB(255, (r / poids).round(), (g / poids).round(), (b / poids).round()).toARGB32();
  } catch (_) {
    return null;
  }
}

class ApparenceNotifier extends Notifier<Apparence> {
  @override
  Apparence build() => Apparence.depuisJson(ref.read(cacheProvider).apparence());

  Future<void> changer({
    OptiTheme? theme,
    ThemeMode? mode,
    Fond? fond,
    double? flou,
    double? voile,
    bool? accentImage,
  }) async {
    state = state.copyWith(theme: theme, mode: mode, fond: fond, flou: flou, voile: voile, accentImage: accentImage);
    await ref.read(cacheProvider).garderApparence(state.enJson());
  }

  /// Choisit une image dans la galerie et en fait le fond (un seul fichier gardé). false si annulé.
  Future<bool> choisirImage() async {
    final choix = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2000, imageQuality: 88);
    if (choix == null || dossierApp == null) return false;
    // Nom nouveau à chaque import : Flutter ne ressert pas l'ancienne image depuis son cache.
    final nom = 'fond_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(choix.path).copy('$dossierApp/$nom');
    final ancien = state.cheminImage;
    if (ancien != null && File(ancien).existsSync()) await File(ancien).delete();
    final premierImport = state.image == null;
    state = state.copyWith(
      fond: Fond.image,
      image: nom,
      couleurImage: await couleurDominante('$dossierApp/$nom'),
      // Par défaut après un import : flou 8 px, voile 35 % (docs/refonte-apparence.md).
      flou: premierImport ? 8 : null,
      voile: premierImport ? .35 : null,
    );
    await ref.read(cacheProvider).garderApparence(state.enJson());
    return true;
  }
}

final apparenceProvider = NotifierProvider<ApparenceNotifier, Apparence>(ApparenceNotifier.new);
