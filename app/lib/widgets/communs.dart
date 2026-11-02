import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/apparence.dart';
import '../theme/opti_theme.dart';
import 'fond_anime.dart';

/// Carte translucide commune à tous les écrans.
class Carte extends StatelessWidget {
  const Carte({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: c.ligne),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }
}

/// Petit titre en capitales espacées (« MES COMPTES »).
class Etiquette extends StatelessWidget {
  const Etiquette(this.texte, {super.key});
  final String texte;

  @override
  Widget build(BuildContext context) => Text(
    texte.toUpperCase(),
    style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: context.couleurs.texteSecondaire),
  );
}

/// Fond commun : lueur dorée et violette en haut de l'écran.
class FondOpti extends ConsumerWidget {
  const FondOpti({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final apparence = ref.watch(apparenceProvider);
    // Icônes de la barre d'état (heure, batterie) lisibles sur le fond, même sans AppBar.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (c.sombre ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: switch (apparence.fond) {
        Fond.uni => ColoredBox(color: c.fond, child: child),
        Fond.image when apparence.cheminImage != null && File(apparence.cheminImage!).existsSync() => Stack(
          children: [
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: apparence.flou, sigmaY: apparence.flou),
                child: Image.file(File(apparence.cheminImage!), fit: BoxFit.cover),
              ),
            ),
            // Voile : noir en sombre, crème en clair, pour que le texte reste lisible.
            Positioned.fill(
              child: ColoredBox(color: c.voile.withValues(alpha: apparence.voile)),
            ),
            child,
          ],
        ),
        _ => Stack(
          children: [
            Positioned.fill(child: FondAnime(theme: apparence.theme)),
            child,
          ],
        ),
      },
    );
  }
}

/// Message d'erreur avec bouton « Réessayer », dans une liste pour garder le « tirer pour rafraîchir ».
class Erreur extends StatelessWidget {
  const Erreur({super.key, required this.message, required this.reessayer});
  final String message;
  final VoidCallback reessayer;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Icon(LucideIcons.triangleAlert, color: c.or, size: 36),
        const SizedBox(height: 12),
        const Text(
          'Impossible de charger tes données',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.texteSecondaire),
        ),
        const SizedBox(height: 20),
        Center(
          child: FilledButton.icon(
            onPressed: reessayer,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Réessayer'),
          ),
        ),
      ],
    );
  }
}

/// Affiche le message d'une action refusée ou échouée.
void signaler(BuildContext context, Object erreur) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erreur.toString())));
}

/// « Opti 0.10.0 », discret, pour savoir quelle version tourne sur le téléphone.
/// Sans le numéro de build : Android l'affiche gonflé (14 → 2014, APK par architecture).
/// Marge du bas = barre de navigation du téléphone, pour ne pas être coupé.
class VersionOpti extends StatelessWidget {
  const VersionOpti({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom + 12),
      child: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, info) => Text(
          info.hasData ? 'Opti ${info.data!.version}' : '',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: context.couleurs.texteSecondaire.withValues(alpha: 0.7)),
        ),
      ),
    );
  }
}
