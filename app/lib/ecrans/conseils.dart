/// Carte « Conseils » de l'accueil : 3 au maximum (docs/regles-de-calcul.md § 6 du backend).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/api.dart';
import '../data/cache.dart';
import '../theme/opti_theme.dart';
import '../util/format.dart';
import '../widgets/communs.dart';
import 'abonnements.dart';
import 'catalogue.dart';

class Conseil {
  Conseil.depuisJson(Map<String, dynamic> j)
    : cle = j['cle'],
      type = j['type'],
      texte = j['texte'],
      action = j['action'] as Map<String, dynamic>?;

  final String cle, type, texte;
  final Map<String, dynamic>?
  action; // {"type": "verser", objectif_id, objectif, montant}, {"type": "abonnement", id} ou {"type": "catalogue"}

  IconData get icone => switch (type) {
    'categorie' => LucideIcons.trendingUp,
    'abonnement' => LucideIcons.scissors,
    'offre' => LucideIcons.tags,
    _ => LucideIcons.piggyBank,
  };
}

final conseilsProvider = FutureProvider<List<Conseil>>((ref) async {
  final r = await ref.watch(apiProvider).conseils();
  return [for (final c in r['conseils'] as List) Conseil.depuisJson(c as Map<String, dynamic>)];
});

class CarteConseils extends ConsumerStatefulWidget {
  const CarteConseils({super.key});

  @override
  ConsumerState<CarteConseils> createState() => _CarteConseilsState();
}

class _CarteConseilsState extends ConsumerState<CarteConseils> {
  final _masques = <String>{};
  String? _enCours;

  Future<void> _masquer(Conseil c) async {
    await ref.read(cacheProvider).masquerConseil(c.cle);
    setState(() => _masques.add(c.cle));
  }

  Future<void> _verser(Conseil c) async {
    final a = c.action!;
    setState(() => _enCours = c.cle);
    try {
      await ref.read(apiProvider).declarerMouvement(a['objectif_id'] as String, (a['montant'] as num).toDouble());
      ref.invalidate(objectifsProvider);
      ref.invalidate(accueilProvider);
      await _masquer(c);
      if (mounted) {
        signaler(
          context,
          'Versement de ${euros(a['montant'] as num)} noté dans ${a['objectif']}. '
          'Fais le virement vers ta réserve Revolut : Opti le reconnaîtra tout seul.',
        );
      }
    } catch (e) {
      if (mounted) signaler(context, e);
    } finally {
      if (mounted) setState(() => _enCours = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cache = ref.read(cacheProvider);
    final conseils = [
      for (final c in ref.watch(conseilsProvider).value ?? const <Conseil>[])
        if (!_masques.contains(c.cle) && !cache.conseilMasque(c.cle)) c,
    ];
    if (conseils.isEmpty) return const SizedBox.shrink();
    final couleurs = context.couleurs;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Carte(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(LucideIcons.lightbulb, size: 16, color: couleurs.or),
                const SizedBox(width: 8),
                const Etiquette('Conseils'),
              ],
            ),
            for (final c in conseils) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(c.icone, size: 18, color: couleurs.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(c.texte)),
                ],
              ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  TextButton(onPressed: () => _masquer(c), child: const Text('Pas maintenant')),
                  if (c.action?['type'] == 'verser')
                    FilledButton(
                      onPressed: _enCours == null ? () => _verser(c) : null,
                      child: Text('Mettre ${eurosCourts(c.action!['montant'] as num)} de côté'),
                    )
                  else if (c.action?['type'] == 'abonnement')
                    FilledButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).push(MaterialPageRoute<void>(builder: (_) => EcranAbonnement(id: c.action!['id'] as String))),
                      child: const Text("Voir l'abonnement"),
                    )
                  else if (c.action?['type'] == 'catalogue')
                    FilledButton(
                      onPressed: () =>
                          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EcranCatalogue())),
                      child: const Text('Voir les offres'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
