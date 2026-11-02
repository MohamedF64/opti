/// Carte « Bilan du cycle » de l'accueil, 3 jours après la paie (docs/regles-de-calcul.md § 11 du backend).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/api.dart';
import '../data/cache.dart';
import '../theme/opti_theme.dart';
import '../util/format.dart';
import '../widgets/communs.dart';
import 'navigation.dart';

double _d(Object? v) => v == null ? 0 : (v as num).toDouble();

class Bilan {
  Bilan.depuisJson(Map<String, dynamic> j)
    : debut = DateTime.parse(j['debut']),
      fin = DateTime.parse(j['fin']),
      depense = _d(j['depense']),
      reste = _d(j['reste']),
      jours = j['jours'] as int,
      joursSousLimite = j['jours_sous_limite'] as int,
      ecartMoyenne = j['ecart_moyenne_pourcent'] as int?,
      categorie = j['categorie'] == null
          ? null
          : (nom: j['categorie']['nom'] as String, pourcent: j['categorie']['pourcent'] as int);

  final DateTime debut, fin;
  final double depense, reste;
  final int jours, joursSousLimite;
  final int? ecartMoyenne;
  final ({String nom, int pourcent})? categorie;
}

/// null hors des 3 jours qui suivent la paie.
final bilanProvider = FutureProvider<Bilan?>((ref) async {
  final j = (await ref.watch(apiProvider).bilan())['bilan'];
  return j == null ? null : Bilan.depuisJson(j as Map<String, dynamic>);
});

class CarteBilan extends ConsumerStatefulWidget {
  const CarteBilan({super.key});

  @override
  ConsumerState<CarteBilan> createState() => _CarteBilanState();
}

class _CarteBilanState extends ConsumerState<CarteBilan> {
  bool _fermee = false;

  @override
  Widget build(BuildContext context) {
    final b = ref.watch(bilanProvider).value;
    final cache = ref.read(cacheProvider);
    if (b == null || _fermee || cache.bilanFerme(b.debut)) return const SizedBox.shrink();
    final c = context.couleurs;
    final pourcent = b.jours == 0 ? 0 : (b.joursSousLimite / b.jours * 100).round();

    Widget ligne(String libelle, String valeur, {Color? couleur}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(libelle, style: TextStyle(color: c.texteSecondaire)),
          ),
          Text(valeur, style: chiffres(color: couleur)),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Carte(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(LucideIcons.flag, size: 16, color: c.accent),
                const SizedBox(width: 8),
                Expanded(child: Etiquette('Bilan du cycle ${jourMois(b.debut)} → ${jourMois(b.fin)}')),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Fermer',
                  icon: Icon(LucideIcons.x, size: 18, color: c.texteSecondaire),
                  onPressed: () {
                    cache.fermerBilan(b.debut);
                    setState(() => _fermee = true);
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            ligne(
              'Dépensé',
              b.ecartMoyenne == null
                  ? euros(b.depense)
                  : '${euros(b.depense)} (${b.ecartMoyenne! > 0 ? '+' : ''}${b.ecartMoyenne} % / moyenne)',
              couleur: (b.ecartMoyenne ?? 0) > 0 ? c.alerte : null,
            ),
            ligne(
              b.reste >= 0 ? 'Reste du cycle' : "Pris sur l'épargne",
              eurosSignes(b.reste),
              couleur: b.reste >= 0 ? c.ok : c.alerte,
            ),
            ligne('Jours sous ta limite', '${b.joursSousLimite} / ${b.jours} ($pourcent %)'),
            if (b.categorie != null)
              ligne(
                'A le plus bougé',
                '${b.categorie!.nom} ${b.categorie!.pourcent > 0 ? '+' : ''}${b.categorie!.pourcent} %',
                couleur: b.categorie!.pourcent > 0 ? c.alerte : c.ok,
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => ref.read(ongletProvider.notifier).aller(2),
                child: const Text('Voir les stats'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
