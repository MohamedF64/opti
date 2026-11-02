import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/abonnements.dart';
import '../data/api.dart';
import '../data/cache.dart';
import '../data/catalogue.dart';
import '../theme/opti_theme.dart';
import '../util/format.dart';
import '../widgets/communs.dart';
import 'bons_plans.dart';
import 'catalogue.dart';

part 'abonnements/cartes.dart';
part 'abonnements/detail.dart';
part 'abonnements/formulaire.dart';

const _usages = [('jamais', 'Jamais'), ('parfois', 'Parfois'), ('souvent', 'Souvent'), ('toujours', 'Toujours')];
const _frequences = [
  ('mensuel', 'Mensuel'),
  ('annuel', 'Annuel'),
  ('trimestriel', 'Trimestriel'),
  ('hebdomadaire', 'Hebdo'),
];
const _moisCourts = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

IconData iconeAbonnement(Abonnement a) {
  final texte = '${a.categorie} ${a.nom}'.toLowerCase();
  if (texte.contains('assurance')) return LucideIcons.shieldCheck;
  if (texte.contains('transport') || texte.contains('navigo') || texte.contains('imagine')) {
    return LucideIcons.trainFront;
  }
  if (texte.contains('sport') || texte.contains('fit')) return LucideIcons.dumbbell;
  if (texte.contains('mobile') || texte.contains('forfait') || texte.contains('orange')) return LucideIcons.smartphone;
  if (texte.contains('anthropic') || texte.contains('claude')) return LucideIcons.bot;
  if (texte.contains('prime') || texte.contains('netflix') || texte.contains('disney')) return LucideIcons.tv;
  if (texte.contains('spotify') || texte.contains('deezer')) return LucideIcons.music;
  return LucideIcons.repeat;
}

/// Usages choisis à l'écran mais pas encore confirmés par le serveur : affichés tout de suite.
class UsagesLocaux extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => {};

  void fixer(String id, String usage) => state = {...state, id: usage};
  void oublier(String id) => state = {...state}..remove(id);
}

final usagesLocauxProvider = NotifierProvider<UsagesLocaux, Map<String, String>>(UsagesLocaux.new);

/// Verdict selon l'usage (même règle que le serveur, docs/regles-de-calcul.md § 7).
String verdictDe(String? usage) => switch (usage) {
  'toujours' || 'souvent' => 'rentable',
  'parfois' => 'a_revoir',
  'jamais' => 'a_couper',
  _ => 'a_renseigner',
};

/// Statut unique, le même partout : couleur et libellé. `usage` : choix pas encore confirmé.
(String, Color) statutAffiche(BuildContext context, Abonnement a, {String? usage}) {
  final c = context.couleurs;
  if (a.resilie) return ('Résilié', c.texteSecondaire);
  if (a.essai) return ('Essai gratuit', c.accent);
  if (a.essaiTermine) return ('Essai terminé', c.or);
  if (a.aVerifier) return ('À vérifier', c.or);
  return switch (usage != null ? verdictDe(usage) : a.verdict) {
    'rentable' => ('Rentable', c.ok),
    'a_revoir' => ('À revoir', c.or),
    'a_couper' => ('À couper', c.alerte),
    _ => ('Usage à renseigner', c.texteSecondaire),
  };
}

Future<bool> _agir(BuildContext context, WidgetRef ref, Future<void> Function(OptiApi api) action) async {
  try {
    await action(ref.read(apiProvider));
    ref.invalidate(abonnementsProvider);
    ref.invalidate(accueilProvider); // les abonnements à venir entrent dans la limite du jour
    return true;
  } catch (e) {
    if (context.mounted) signaler(context, e);
    return false;
  }
}

// ── Liste ─────────────────────────────────────────────────────────────────────

class EcranAbonnementsListe extends ConsumerStatefulWidget {
  const EcranAbonnementsListe({super.key});

  @override
  ConsumerState<EcranAbonnementsListe> createState() => _EcranAbonnementsListeState();
}

class _EcranAbonnementsListeState extends ConsumerState<EcranAbonnementsListe> {
  String _filtre = 'tous'; // tous, a_revoir, a_couper, resilies

  bool _garde(Abonnement a) => switch (_filtre) {
    'a_revoir' =>
      !a.resilie && (a.verdict == 'a_revoir' || a.aVerifier || a.essaiTermine || a.verdict == 'a_renseigner'),
    'a_couper' => !a.resilie && a.verdict == 'a_couper',
    'resilies' => a.resilie,
    _ => !a.resilie,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final donnees = ref.watch(abonnementsProvider);
    final d = donnees.value ?? ref.read(cacheProvider).abonnements();
    // Fond plein (comme les cartes) : lisible par-dessus le fond animé.
    final boutonPlein = OutlinedButton.styleFrom(
      backgroundColor: c.surface.withValues(alpha: 1),
      side: BorderSide(color: c.ligne),
    );
    return Scaffold(
      body: FondOpti(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(abonnementsProvider.future),
            child: d == null
                ? (donnees.hasError
                      ? Erreur(message: donnees.error.toString(), reessayer: () => ref.invalidate(abonnementsProvider))
                      : const Center(child: CircularProgressIndicator()))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('Abonnements', style: context.titre(26))),
                          IconButton.filledTonal(
                            tooltip: 'Ajouter un essai gratuit',
                            onPressed: () => ouvrirFormulaireAbonnement(context, ref, essai: true),
                            icon: const Icon(LucideIcons.gift),
                          ),
                          const SizedBox(width: 4),
                          IconButton.filledTonal(
                            tooltip: 'Ajouter un abonnement',
                            onPressed: () => ouvrirFormulaireAbonnement(context, ref),
                            icon: const Icon(LucideIcons.plus),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Carte(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Etiquette('Total par mois'),
                                      const SizedBox(width: 4),
                                      InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () => showDialog<void>(
                                          context: context,
                                          builder: (contexte) => AlertDialog(
                                            title: const Text('Une estimation'),
                                            content: const Text(
                                              'Estimation à partir de tes derniers prélèvements. Les montants '
                                              'variables, les hausses de prix et les mois de pause (Imagine R '
                                              "l'été) le font bouger.",
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(contexte),
                                                child: const Text('OK'),
                                              ),
                                            ],
                                          ),
                                        ),
                                        child: Icon(LucideIcons.info, size: 15, color: c.texteSecondaire),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: 'Environ ',
                                          style: TextStyle(fontSize: 15, color: c.texteSecondaire),
                                        ),
                                        TextSpan(
                                          text: euros(d.totalParMois),
                                          style: chiffres(fontSize: 28, fontWeight: FontWeight.w500, color: c.accent),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (d.fourchette case final f?)
                                    Text(
                                      'entre ${euros(f.min)} et ${euros(f.max)}',
                                      style: TextStyle(fontSize: 12, color: c.texteSecondaire),
                                    ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Etiquette('Rentables'),
                                const SizedBox(height: 4),
                                Text('${d.rentables}/${d.nombreSuivis}', style: chiffres(fontSize: 20)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: boutonPlein,
                              onPressed: () =>
                                  Navigator.of(context)
                                      .push(MaterialPageRoute<void>(builder: (_) => const EcranCatalogue())),
                              icon: const Icon(LucideIcons.tags, size: 18),
                              label: const Text('Catalogue de prix'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: boutonPlein,
                              onPressed: () =>
                                  Navigator.of(context)
                                      .push(MaterialPageRoute<void>(builder: (_) => const EcranBonsPlans())),
                              icon: const Icon(LucideIcons.percent, size: 18),
                              label: const Text('Bons plans'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      for (final a in d.abonnements.where((a) => a.essaiTermine)) ...[
                        _CarteEssaiTermine(abonnement: a),
                        const SizedBox(height: 12),
                      ],
                      for (final det in d.detectes) ...[_CarteDetecte(detecte: det), const SizedBox(height: 12)],
                      for (final a in d.abonnements.where((a) => a.depassement != null)) ...[
                        _CarteDepassement(abonnement: a),
                        const SizedBox(height: 12),
                      ],
                      for (final a in d.abonnements.where((a) => a.changementPrix != null)) ...[
                        _CartePrix(abonnement: a),
                        const SizedBox(height: 12),
                      ],
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final (cle, libelle) in const [
                              ('tous', 'Tous'),
                              ('a_revoir', 'À revoir'),
                              ('a_couper', 'À couper'),
                              ('resilies', 'Résiliés'),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(libelle),
                                  selected: _filtre == cle,
                                  showCheckmark: false,
                                  onSelected: (_) => setState(() => _filtre = cle),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final a in d.abonnements.where(_garde)) ...[
                        _CarteAbonnement(abonnement: a),
                        const SizedBox(height: 10),
                      ],
                      if (!d.abonnements.any(_garde))
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Aucun abonnement ici.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.texteSecondaire),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
