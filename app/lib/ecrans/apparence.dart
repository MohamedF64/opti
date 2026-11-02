/// Réglages › Apparence : mode (clair, sombre, auto) et thème (Holocron, Forêt).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/apparence.dart';
import '../theme/opti_theme.dart';
import '../widgets/communs.dart';

class CarteApparence extends ConsumerWidget {
  const CarteApparence({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(apparenceProvider);
    final notifier = ref.read(apparenceProvider.notifier);
    final c = context.couleurs;
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Mode', style: TextStyle(fontSize: 13, color: c.texteSecondaire)),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ThemeMode.light, icon: Icon(LucideIcons.sun, size: 16), label: Text('Clair')),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(LucideIcons.moon, size: 16), label: Text('Sombre')),
              ButtonSegment(value: ThemeMode.system, icon: Icon(LucideIcons.smartphone, size: 16), label: Text('Auto')),
            ],
            selected: {a.mode},
            onSelectionChanged: (choix) => notifier.changer(mode: choix.first),
          ),
          if (a.mode == ThemeMode.system)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Suit le réglage clair / sombre du téléphone.',
                style: TextStyle(fontSize: 12, color: c.texteSecondaire),
              ),
            ),
          const SizedBox(height: 16),
          Text('Fond', style: TextStyle(fontSize: 13, color: c.texteSecondaire)),
          const SizedBox(height: 8),
          SegmentedButton<Fond>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: Fond.anime, icon: Icon(LucideIcons.sparkles, size: 16), label: Text('Animé')),
              ButtonSegment(value: Fond.uni, icon: Icon(LucideIcons.square, size: 16), label: Text('Uni')),
              ButtonSegment(value: Fond.image, icon: Icon(LucideIcons.image, size: 16), label: Text('Image')),
            ],
            selected: {a.fond},
            onSelectionChanged: (choix) async {
              // Image : la galerie s'ouvre si aucune image n'a encore été importée.
              if (choix.first == Fond.image && a.image == null) {
                await notifier.choisirImage();
              } else {
                await notifier.changer(fond: choix.first);
              }
            },
          ),
          if (a.fond == Fond.image) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: notifier.choisirImage,
                icon: const Icon(LucideIcons.imagePlus, size: 18),
                label: const Text("Changer d'image"),
              ),
            ),
            _Curseur(
              libelle: 'Flou du fond',
              valeur: a.flou,
              max: 20,
              texte: '${a.flou.round()} px',
              onChanged: (v) => notifier.changer(flou: v.roundToDouble()),
            ),
            _Curseur(
              libelle: 'Voile',
              valeur: a.voile * 100,
              max: 70,
              texte: '${(a.voile * 100).round()} %',
              onChanged: (v) => notifier.changer(voile: (v / 5).round() * 5 / 100),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Accent tiré de l'image"),
              subtitle: Text(
                a.couleurImage == null ? 'Couleur introuvable' : 'Couleur ajustée pour rester lisible',
                style: TextStyle(fontSize: 12, color: c.texteSecondaire),
              ),
              secondary: a.couleurImage == null
                  ? null
                  : Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: accentLisible(Color(a.couleurImage!), c.sombre ? Brightness.dark : Brightness.light),
                        shape: BoxShape.circle,
                      ),
                    ),
              value: a.accentImage,
              onChanged: a.couleurImage == null ? null : (v) => notifier.changer(accentImage: v),
            ),
          ],
          const SizedBox(height: 16),
          Text('Thème', style: TextStyle(fontSize: 13, color: c.texteSecondaire)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (theme, nom, detail) in const [
                (OptiTheme.holocron, 'Holocron', 'Violet et or'),
                (OptiTheme.foret, 'Forêt', 'Vert et brume'),
                (OptiTheme.ocean, 'Océan', 'Aquarium'),
              ]) ...[
                Expanded(
                  child: _ChoixTheme(
                    theme: theme,
                    nom: nom,
                    detail: detail,
                    choisi: a.theme == theme,
                    onTap: () => notifier.changer(theme: theme),
                  ),
                ),
                if (theme != OptiTheme.ocean) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Curseur extends StatelessWidget {
  const _Curseur({
    required this.libelle,
    required this.valeur,
    required this.max,
    required this.texte,
    required this.onChanged,
  });
  final String libelle, texte;
  final double valeur, max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text(libelle)),
        Expanded(
          child: Slider(value: valeur.clamp(0, max), max: max, onChanged: onChanged),
        ),
        SizedBox(
          width: 44,
          child: Text(texte, textAlign: TextAlign.right, style: chiffres(fontSize: 12)),
        ),
      ],
    );
  }
}

/// Aperçu d'un thème dans le mode actif : fond, accent et or.
class _ChoixTheme extends StatelessWidget {
  const _ChoixTheme({
    required this.theme,
    required this.nom,
    required this.detail,
    required this.choisi,
    required this.onTap,
  });
  final OptiTheme theme;
  final String nom, detail;
  final bool choisi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final actuel = context.couleurs;
    final apercu = OptiColors.de(theme, actuel.sombre ? Brightness.dark : Brightness.light);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: apercu.fond,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: choisi ? actuel.accent : actuel.ligne, width: choisi ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (final couleur in [apercu.accent, apercu.or, apercu.ok])
                  Container(
                    width: 14,
                    height: 14,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(color: couleur, shape: BoxShape.circle),
                  ),
                const Spacer(),
                if (choisi) Icon(LucideIcons.check, size: 16, color: apercu.accent),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              nom,
              style: TextStyle(fontWeight: FontWeight.w700, color: apercu.texte),
            ),
            Text(detail, style: TextStyle(fontSize: 12, color: apercu.texteSecondaire)),
          ],
        ),
      ),
    );
  }
}
