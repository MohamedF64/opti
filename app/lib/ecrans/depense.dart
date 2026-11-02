/// Toucher une dépense (accueil, Historique, Stats) : changer sa catégorie ou la payer avec l'épargne d'un projet.
/// Règles : docs/regles-de-calcul.md § 9 du backend.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/api.dart';
import '../data/modeles.dart';
import '../theme/opti_theme.dart';
import '../util/format.dart';
import '../widgets/communs.dart';
import 'objectifs.dart';

/// Mêmes catégories que `categories.CATEGORIES` côté serveur.
const categoriesProposees = [
  'Alimentation',
  'Restauration',
  'Shopping',
  'Transport',
  'Loisirs',
  'Sport',
  'Santé',
  'Maison',
  'Abonnement',
  'Assurance',
  'Distributeur',
  'Cadeau',
  'Dons',
  'Virement émis',
  'Autre',
];

enum _Action { categorie, projet }

Future<void> toucherDepense(BuildContext context, WidgetRef ref, Operation operation) async {
  if (operation.montant >= 0) return;
  if (operation.interne) return rattacherOperation(context, ref, operation);
  final action = await showModalBottomSheet<_Action>(
    context: context,
    showDragHandle: true,
    backgroundColor: context.couleurs.fond,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${operation.libelle} · ${euros(-operation.montant)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Text(operation.categorie, style: TextStyle(color: context.couleurs.texteSecondaire)),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(LucideIcons.tag),
              title: const Text('Changer la catégorie'),
              onTap: () => Navigator.pop(context, _Action.categorie),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(LucideIcons.piggyBank),
              title: const Text("Payer avec l'épargne d'un projet"),
              onTap: () => Navigator.pop(context, _Action.projet),
            ),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  if (action == _Action.categorie) {
    await changerCategorie(context, ref, operation);
  } else {
    await rattacherOperation(context, ref, operation);
  }
}

Future<void> changerCategorie(BuildContext context, WidgetRef ref, Operation operation) async {
  final choix = await showModalBottomSheet<({String categorie, bool retenir})>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: context.couleurs.fond,
    builder: (_) => _ChoixCategorie(operation: operation),
  );
  if (!context.mounted || choix == null) return;
  if (choix.categorie == operation.categorie && !choix.retenir) return;
  try {
    final r = await ref.read(apiProvider).changerCategorie(operation.id, choix.categorie, retenir: choix.retenir);
    ref.invalidate(accueilProvider);
    ref.invalidate(statsProvider);
    if (!context.mounted) return;
    final n = r['modifiees'] as int? ?? 1;
    signaler(
      context,
      r['retenu'] == true
          ? '${operation.libelle} : $n dépense${n > 1 ? 's' : ''} en ${choix.categorie}, et les prochaines aussi.'
          : 'Dépense passée en ${choix.categorie}.',
    );
  } catch (e) {
    if (context.mounted) signaler(context, e);
  }
}

class _ChoixCategorie extends StatefulWidget {
  const _ChoixCategorie({required this.operation});
  final Operation operation;

  @override
  State<_ChoixCategorie> createState() => _ChoixCategorieState();
}

class _ChoixCategorieState extends State<_ChoixCategorie> {
  late String _choisie = widget.operation.categorie;
  bool _retenir = true;

  @override
  Widget build(BuildContext context) {
    final o = widget.operation;
    // Une dépense en attente est remplacée à chaque synchro : le choix est forcément retenu.
    final retenir = _retenir || o.enAttente;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${o.libelle} · ${euros(-o.montant)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final nom in categoriesProposees)
                        ChoiceChip(
                          label: Text(nom),
                          selected: nom == _choisie,
                          onSelected: (_) => setState(() => _choisie = nom),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: retenir,
                onChanged: o.enAttente ? null : (v) => setState(() => _retenir = v ?? true),
                title: Text('Retenir pour ${o.libelle}'),
                subtitle: Text(
                  o.enAttente
                      ? 'Dépense en attente : le choix est toujours retenu.'
                      : 'Ses dépenses passées et futures passent aussi en $_choisie.',
                  style: TextStyle(fontSize: 12, color: context.couleurs.texteSecondaire),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.pop(context, (categorie: _choisie, retenir: retenir)),
                child: const Text('Valider'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
