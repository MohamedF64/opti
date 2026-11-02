import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Univers de l'app (docs/refonte-apparence.md du backend) ; le mode (clair, sombre, auto) est choisi à part.
enum OptiTheme { holocron, foret, ocean }

/// Couleurs d'une combinaison thème × mode : chacune a les siennes, jamais de texte sombre sur fond sombre.
@immutable
class OptiColors extends ThemeExtension<OptiColors> {
  const OptiColors({
    required this.fond,
    required this.surface,
    required this.ligne,
    required this.texte,
    required this.texteSecondaire,
    required this.accent,
    required this.or,
    required this.ok,
    required this.alerte,
    required this.voile,
    required this.boutonDebut,
    required this.boutonFin,
    required this.sombre,
  });

  final Color fond, surface, ligne, texte, texteSecondaire, accent, or, ok, alerte, voile, boutonDebut, boutonFin;
  final bool sombre;

  static const holocronSombre = OptiColors(
    fond: Color(0xFF0F0A22),
    surface: Color(0xC71B1436), // 78 % d'opacité
    ligne: Color(0x33AA8CFF),
    texte: Color(0xFFF1ECFF),
    texteSecondaire: Color(0xFFABA0CB),
    accent: Color(0xFFA67CF8),
    or: Color(0xFFF5B342),
    ok: Color(0xFF34D399),
    alerte: Color(0xFFF87171),
    voile: Color(0xFF07040F),
    boutonDebut: Color(0xFF7C4DFF),
    boutonFin: Color(0xFFB794F6),
    sombre: true,
  );

  static const holocronClair = OptiColors(
    fond: Color(0xFFFFF7EE),
    surface: Color(0xE6FFFFFF), // 90 %
    ligne: Color(0x26D42A7C),
    texte: Color(0xFF2A1A24),
    texteSecondaire: Color(0xFF7E6E76),
    accent: Color(0xFFD42A7C),
    or: Color(0xFFD98A17),
    ok: Color(0xFF0A8F63),
    alerte: Color(0xFFD42B2B),
    voile: Color(0xFFFFF9F2),
    boutonDebut: Color(0xFFC2185B),
    boutonFin: Color(0xFFEC4899),
    sombre: false,
  );

  static const foretSombre = OptiColors(
    fond: Color(0xFF0D1D15),
    surface: Color(0xCC13261C), // 80 %
    ligne: Color(0x3374D39C),
    texte: Color(0xFFE9F4EC),
    texteSecondaire: Color(0xFFA3BEAD),
    accent: Color(0xFF74D39C),
    or: Color(0xFFE3C77A),
    ok: Color(0xFF74D39C),
    alerte: Color(0xFFF28B82),
    voile: Color(0xFF06110B),
    boutonDebut: Color(0xFF2E8A5A),
    boutonFin: Color(0xFF74D39C),
    sombre: true,
  );

  static const foretClair = OptiColors(
    fond: Color(0xFFF1F6F0),
    surface: Color(0xE6FFFFFF), // 90 %
    ligne: Color(0x261D7A48),
    texte: Color(0xFF13221A),
    texteSecondaire: Color(0xFF56665C),
    accent: Color(0xFF1D7A48),
    or: Color(0xFFA66B00),
    ok: Color(0xFF1D7A48),
    alerte: Color(0xFFC62828),
    voile: Color(0xFFF6FAF5),
    boutonDebut: Color(0xFF1D7A48),
    boutonFin: Color(0xFF3FA36D),
    sombre: false,
  );

  /// Océan clair : aquarium en plein jour (maquette « Thème océan – Accueil aquarium »).
  static const oceanClair = OptiColors(
    fond: Color(0xFFEAF6FB),
    surface: Color(0xEDFFFFFF), // 93 %
    ligne: Color(0x260B6FA4),
    texte: Color(0xFF0B2545),
    texteSecondaire: Color(0xFF4A6380),
    accent: Color(0xFF0B6FA4),
    or: Color(0xFFC2410C), // corail
    ok: Color(0xFF138A72),
    alerte: Color(0xFFC2364F),
    voile: Color(0xFFEAF6FB),
    boutonDebut: Color(0xFF0B6FA4),
    boutonFin: Color(0xFF1FA6C9),
    sombre: false,
  );

  /// Océan sombre : le même aquarium, la nuit.
  static const oceanSombre = OptiColors(
    fond: Color(0xFF061826),
    surface: Color(0xD10A2740), // 82 %
    ligne: Color(0x332DD4BF),
    texte: Color(0xFFE6F6FB),
    texteSecondaire: Color(0xFF9CC3D5),
    accent: Color(0xFF2DD4BF),
    or: Color(0xFFFB923C), // corail
    ok: Color(0xFF34D399),
    alerte: Color(0xFFF87171),
    voile: Color(0xFF04121F),
    boutonDebut: Color(0xFF0E7490),
    boutonFin: Color(0xFF14B8A6),
    sombre: true,
  );

  static OptiColors de(OptiTheme theme, Brightness luminosite) => switch ((theme, luminosite)) {
    (OptiTheme.holocron, Brightness.dark) => holocronSombre,
    (OptiTheme.holocron, Brightness.light) => holocronClair,
    (OptiTheme.foret, Brightness.dark) => foretSombre,
    (OptiTheme.foret, Brightness.light) => foretClair,
    (OptiTheme.ocean, Brightness.dark) => oceanSombre,
    (OptiTheme.ocean, Brightness.light) => oceanClair,
  };

  /// Accent tiré de l'image de fond (bouton en dégradé du même ton).
  OptiColors avecAccent(Color a) => OptiColors(
    fond: fond,
    surface: surface,
    ligne: ligne,
    texte: texte,
    texteSecondaire: texteSecondaire,
    accent: a,
    or: or,
    ok: ok,
    alerte: alerte,
    voile: voile,
    boutonDebut: Color.lerp(a, Colors.black, .2)!,
    boutonFin: a,
    sombre: sombre,
  );

  @override
  OptiColors copyWith() => this;

  @override
  OptiColors lerp(OptiColors? other, double t) => other ?? this;
}

extension OptiColorsContext on BuildContext {
  OptiColors get couleurs => Theme.of(this).extension<OptiColors>()!;

  /// Style des grands titres d'écran : DM Sans (Holocron), Fraunces (Forêt) ou Fredoka (Océan).
  TextStyle titre(double taille) => (Theme.of(this).textTheme.headlineMedium ?? const TextStyle()).copyWith(
    fontSize: taille,
    fontWeight: FontWeight.w700,
    color: couleurs.texte,
  );
}

/// ThemeData d'une combinaison thème × mode.
ThemeData construireTheme(OptiTheme theme, Brightness luminosite, {Color? accent}) {
  final base0 = OptiColors.de(theme, luminosite);
  final c = accent == null ? base0 : base0.avecAccent(accent);
  // Toutes les couleurs dérivées (pastilles, sélecteurs, onglet actif) partent de l'accent du thème.
  final schema = ColorScheme.fromSeed(seedColor: c.accent, brightness: luminosite);
  final base = ThemeData(colorScheme: schema, useMaterial3: true);
  // google_fonts 9 s'appuie sur le paquet séparé material_ui : son TextTheme n'est pas celui
  // de Flutter. On applique donc la police par son nom de famille (TextStyle est commun aux deux).
  final (texte, titres) = switch (theme) {
    OptiTheme.holocron => (GoogleFonts.dmSans().fontFamily, GoogleFonts.dmSans().fontFamily),
    OptiTheme.foret => (GoogleFonts.figtree().fontFamily, GoogleFonts.fraunces().fontFamily),
    OptiTheme.ocean => (GoogleFonts.nunito().fontFamily, GoogleFonts.fredoka().fontFamily),
  };
  final textTheme = base.textTheme.apply(fontFamily: texte, bodyColor: c.texte, displayColor: c.texte);
  final barres = c.sombre ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;
  return base.copyWith(
    scaffoldBackgroundColor: c.fond,
    colorScheme: schema.copyWith(
      primary: c.accent,
      onPrimary: c.sombre ? c.fond : Colors.white,
      secondary: c.or,
      surface: c.fond,
      onSurface: c.texte,
      error: c.alerte,
    ),
    textTheme: textTheme.copyWith(
      headlineMedium: textTheme.headlineMedium?.copyWith(fontFamily: titres),
      titleLarge: textTheme.titleLarge?.copyWith(fontFamily: titres),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: c.texte,
      systemOverlayStyle: barres.copyWith(statusBarColor: Colors.transparent),
      titleTextStyle: textTheme.titleLarge?.copyWith(fontFamily: titres, color: c.texte),
    ),
    // Bouton principal en dégradé, comme la maquette.
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (etats) => etats.contains(WidgetState.disabled) ? c.texteSecondaire : Colors.white,
        ),
        backgroundBuilder: (context, etats, enfant) => DecoratedBox(
          decoration: BoxDecoration(
            gradient: etats.contains(WidgetState.disabled)
                ? null
                : LinearGradient(colors: [c.boutonDebut, c.boutonFin]),
            color: etats.contains(WidgetState.disabled) ? c.ligne : null,
          ),
          child: enfant,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surface,
      selectedColor: c.accent.withValues(alpha: 0.22),
      side: BorderSide(color: c.ligne),
      labelStyle: TextStyle(fontFamily: texte, color: c.texte),
      checkmarkColor: c.accent,
    ),
    navigationBarTheme: NavigationBarThemeData(indicatorColor: c.accent.withValues(alpha: 0.18)),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.fond, modalBackgroundColor: c.fond),
    dialogTheme: DialogThemeData(backgroundColor: c.fond),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.sombre ? const Color(0xFFEDE9F7) : const Color(0xFF2A2A2A),
      contentTextStyle: TextStyle(fontFamily: texte, color: c.sombre ? const Color(0xFF1A1530) : Colors.white),
    ),
    extensions: [c],
  );
}

/// Police des montants : DM Mono, comme la maquette « Refonte 2026 » (texte en DM Sans).
TextStyle chiffres({double? fontSize, FontWeight? fontWeight, Color? color, double? letterSpacing}) =>
    GoogleFonts.dmMono(fontSize: fontSize, fontWeight: fontWeight, color: color, letterSpacing: letterSpacing);
