/// Bons plans Dealabs des 7 derniers jours pour les enseignes de Mohamed, et essais gratuits des services du
/// catalogue (règles : docs/regles-de-calcul.md § 12 point 3 du backend). Jamais de notification.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/api.dart';
import '../data/bons_plans.dart';
import '../theme/opti_theme.dart';
import '../util/format.dart';
import '../widgets/communs.dart';

Future<void> _choisir(BuildContext context, WidgetRef ref, String nom, bool suivie) async {
  try {
    await ref.read(apiProvider).choisirEnseigne(nom, suivie);
    ref.invalidate(bonsPlansProvider);
  } catch (e) {
    if (context.mounted) signaler(context, e);
  }
}

class EcranBonsPlans extends ConsumerStatefulWidget {
  const EcranBonsPlans({super.key});

  @override
  ConsumerState<EcranBonsPlans> createState() => _EcranBonsPlansState();
}

class _EcranBonsPlansState extends ConsumerState<EcranBonsPlans> {
  final _champ = TextEditingController();
  String _recherche = '';

  @override
  void dispose() {
    _champ.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final donnees = ref.watch(bonsPlansProvider);
    final d = donnees.value;
    final trouves = d == null || _recherche.isEmpty ? null : d.chercher(_recherche);
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Bons plans')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(bonsPlansProvider.future),
        child: d == null
            ? (donnees.hasError
                  ? Erreur(message: donnees.error.toString(), reessayer: () => ref.invalidate(bonsPlansProvider))
                  : const Center(child: CircularProgressIndicator()))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                children: [
                  Text(
                    'Les bons plans Dealabs des 7 derniers jours pour tes enseignes. Pas de notification : '
                    "à regarder quand tu as déjà un achat prévu. C'est un aperçu, pas une liste complète.",
                    style: TextStyle(fontSize: 12, color: c.texteSecondaire),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _champ,
                    textInputAction: TextInputAction.search,
                    onChanged: (v) => setState(() => _recherche = v.trim()),
                    decoration: InputDecoration(
                      hintText: 'Chercher (écouteurs, Nike, Fnac…)',
                      prefixIcon: const Icon(LucideIcons.search, size: 18),
                      suffixIcon: _recherche.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Effacer',
                              onPressed: () => setState(() {
                                _champ.clear();
                                _recherche = '';
                              }),
                              icon: const Icon(LucideIcons.x, size: 18),
                            ),
                      filled: true,
                      fillColor: c.surface.withValues(alpha: 1),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                  if (trouves != null) ...[
                    const SizedBox(height: 16),
                    Etiquette('${trouves.length} résultat${trouves.length > 1 ? 's' : ''}'),
                    const SizedBox(height: 8),
                    if (trouves.isEmpty)
                      Text('Aucun bon plan ne correspond.', style: TextStyle(color: c.texteSecondaire))
                    else
                      Carte(
                        child: Column(children: [for (final b in trouves) _LigneBonPlan(bon: b, avecEnseigne: true)]),
                      ),
                  ] else ...[
                    if (d.essais.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Etiquette('Essais gratuits'),
                      const SizedBox(height: 8),
                      Carte(
                        child: Column(children: [for (final b in d.essais) _LigneBonPlan(bon: b)]),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Etiquette('Par enseigne'),
                    const SizedBox(height: 8),
                    if (d.parEnseigne.isEmpty)
                      Text('Rien cette semaine pour tes enseignes.', style: TextStyle(color: c.texteSecondaire)),
                    for (final MapEntry(key: enseigne, value: bons) in d.parEnseigne.entries) ...[
                      Carte(
                        child: Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: EdgeInsets.zero,
                            title: Text(enseigne, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              '${bons.length} bon${bons.length > 1 ? 's' : ''} plan${bons.length > 1 ? 's' : ''}',
                              style: TextStyle(fontSize: 12, color: c.texteSecondaire),
                            ),
                            children: [for (final b in bons) _LigneBonPlan(bon: b)],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                  const SizedBox(height: 10),
                  const Etiquette('Tes enseignes'),
                  const SizedBox(height: 8),
                  _CarteEnseignes(donnees: d),
                ],
              ),
      ),
    );
  }
}

class _LigneBonPlan extends StatelessWidget {
  const _LigneBonPlan({required this.bon, this.avecEnseigne = false});
  final BonPlan bon;
  final bool avecEnseigne;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final b = bon;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(b.titre, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [if (b.essai || avecEnseigne) b.suivie, ilYa(b.publieLe)].join(' · '),
        style: TextStyle(fontSize: 12, color: c.texteSecondaire),
      ),
      trailing: b.prix == null ? null : Text(b.prix!, style: chiffres(fontSize: 14, color: c.accent)),
      onTap: () async {
        if (!await launchUrl(Uri.parse(b.lien), mode: LaunchMode.externalApplication) && context.mounted) {
          signaler(context, "Impossible d'ouvrir le bon plan.");
        }
      },
    );
  }
}

class _CarteEnseignes extends ConsumerWidget {
  const _CarteEnseignes({required this.donnees});
  final DonneesBonsPlans donnees;

  Future<void> _ajouter(BuildContext context, WidgetRef ref) async {
    final champ = TextEditingController();
    final nom = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ajouter une enseigne'),
        content: TextField(
          controller: champ,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nom (ex. Fnac)', border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, champ.text.trim()), child: const Text('Ajouter')),
        ],
      ),
    );
    champ.dispose();
    if (nom != null && nom.length >= 2 && context.mounted) await _choisir(context, ref, nom, true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final d = donnees;
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in d.enseignes)
                InputChip(
                  label: Text(e.nom),
                  avatar: Icon(e.depenses ? LucideIcons.receipt : LucideIcons.userRound, size: 14),
                  deleteButtonTooltipMessage: 'Retirer',
                  onDeleted: () => _choisir(context, ref, e.nom, false),
                ),
              ActionChip(
                avatar: const Icon(LucideIcons.plus, size: 14),
                label: const Text('Ajouter'),
                onPressed: () => _ajouter(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Ticket : déduite de tes dépenses des 12 derniers mois (2 achats ou 40 € au moins). '
            "Personnage : ajoutée par toi. Une enseigne retirée ne revient pas avec tes dépenses.",
            style: TextStyle(fontSize: 12, color: c.texteSecondaire),
          ),
          if (d.retirees.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Retirées', style: TextStyle(fontSize: 12, color: c.texteSecondaire)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final nom in d.retirees)
                  ActionChip(
                    avatar: const Icon(LucideIcons.undo2, size: 14),
                    label: Text(nom),
                    tooltip: 'Suivre à nouveau',
                    onPressed: () => _choisir(context, ref, nom, true),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
