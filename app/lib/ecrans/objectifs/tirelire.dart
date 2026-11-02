part of '../objectifs.dart';

// Tirelire : reprises, dépenses payées avec un projet, rattachement.

// ── Reprises de la tirelire ───────────────────────────────────────────────────

class _CarteReprise extends ConsumerWidget {
  const _CarteReprise({required this.reprise, required this.objectifs});
  final Reprise reprise;
  final List<Objectif> objectifs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final r = reprise;
    final depense = -r.depenses.fold<double>(0, (t, d) => t + d.operation.montant);
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.piggyBank, size: 16, color: c.or),
              const SizedBox(width: 8),
              const Expanded(child: Etiquette('Repris de ta tirelire')),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Tu as repris ${euros(r.montant)} le ${jourMois(r.date)}, puis dépensé ${euros(depense)} '
            '${r.arrivee == 'CIC' ? 'au CIC' : 'sur Revolut'}.',
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => _repondreReprise(context, ref, r, objectifs),
              child: const Text('C\'était pour quoi ?'),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _repondreReprise(BuildContext context, WidgetRef ref, Reprise r, List<Objectif> objectifs) async {
  final choix = objectifs.where((o) => r.objectifId == null || o.id == r.objectifId).toList();
  if (choix.isEmpty) return;
  final reponse = await showModalBottomSheet<({Objectif? objectif, List<String> depenses})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.couleurs.fond,
    builder: (_) => _FeuilleReprise(reprise: r, objectifs: choix),
  );
  if (reponse == null || !context.mounted) return;
  await _agir(context, ref, (api) => api.repondreReprise(r.id, reponse.objectif?.id, reponse.depenses));
}

class _FeuilleReprise extends StatefulWidget {
  const _FeuilleReprise({required this.reprise, required this.objectifs});
  final Reprise reprise;
  final List<Objectif> objectifs;

  @override
  State<_FeuilleReprise> createState() => _FeuilleRepriseState();
}

class _FeuilleRepriseState extends State<_FeuilleReprise> {
  late Objectif _objectif = widget.objectifs.where((o) => o.imprevus).firstOrNull ?? widget.objectifs.first;
  late final Set<String> _cochees = {
    for (final d in widget.reprise.depenses)
      if (d.cochee) d.operation.id,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final r = widget.reprise;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tu as repris ${euros(r.montant)} de ta tirelire le ${jourMois(r.date)}. C\'était pour :',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              RadioGroup<Objectif>(
                groupValue: _objectif,
                onChanged: (o) => setState(() => _objectif = o ?? _objectif),
                child: Column(
                  children: [
                    for (final o in widget.objectifs)
                      RadioListTile<Objectif>(
                        value: o,
                        contentPadding: EdgeInsets.zero,
                        title: Text(o.nom),
                        secondary: Icon(iconeDe(o), size: 20),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Etiquette('Dépenses payées avec cet argent'),
              for (final d in r.depenses)
                CheckboxListTile(
                  value: _cochees.contains(d.operation.id),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (v) =>
                      setState(() => v == true ? _cochees.add(d.operation.id) : _cochees.remove(d.operation.id)),
                  title: Text(d.operation.libelle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('le ${jourMois(d.operation.date)}'),
                  secondary: Text(euros(-d.operation.montant), style: chiffres()),
                ),
              Text(
                'Les dépenses cochées sortiront de ta limite du jour.',
                style: TextStyle(color: c.texteSecondaire, fontSize: 13),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _cochees.isEmpty
                    ? null
                    : () => Navigator.pop(context, (objectif: _objectif, depenses: _cochees.toList())),
                child: const Text('Valider'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, (objectif: null, depenses: <String>[])),
                child: const Text('Non, dépense normale'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Dépenses payées avec un projet ────────────────────────────────────────────

/// « Payé avec ton épargne ? » : une grosse dépense qu'un projet a de quoi payer.
class _CarteSuggestion extends ConsumerWidget {
  const _CarteSuggestion({required this.suggestion, required this.objectifs});
  final SuggestionRattachement suggestion;
  final List<Objectif> objectifs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final s = suggestion;
    final projets = objectifs.where((o) => s.objectifIds.contains(o.id)).toList();
    if (projets.isEmpty) return const SizedBox.shrink();
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.sparkles, size: 16, color: c.or),
              const SizedBox(width: 8),
              const Etiquette('Payé avec ton épargne ?'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text('${s.libelle} · le ${jourMois(s.date)}', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 12),
              Text(euros(-s.montant), style: chiffres()),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            projets.length == 1
                ? 'Rattacher à « ${projets.first.nom} » ? Elle sortira de ta limite du jour.'
                : 'Rattacher à un de tes projets ? Elle sortira de ta limite du jour.',
            style: TextStyle(color: c.texteSecondaire, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => _agir(context, ref, (api) => api.ignorerSuggestion(s.id)),
                child: const Text('Non, dépense normale'),
              ),
              FilledButton(
                onPressed: () async {
                  final choisi = projets.length == 1
                      ? projets.first
                      : await choisirObjectif(context, titre: 'Payé avec quel projet ?', objectifs: projets);
                  if (choisi != null && context.mounted) {
                    await _agir(context, ref, (api) => api.rattacher(s.id, choisi.id));
                  }
                },
                child: Text(projets.length == 1 ? 'Oui' : 'Choisir le projet'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CarteDepenses extends ConsumerWidget {
  const _CarteDepenses({required this.objectif});
  final Objectif objectif;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Etiquette('Payé avec cet objectif'),
          for (final t in objectif.depenses)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.libelle, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('le ${jourMois(t.date)}', style: TextStyle(fontSize: 12, color: c.texteSecondaire)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(eurosSignes(t.montant), style: chiffres()),
                  IconButton(
                    tooltip: 'Détacher (redevient une dépense normale)',
                    onPressed: () => _agir(context, ref, (api) => api.rattacher(t.id, null)),
                    icon: Icon(LucideIcons.x, size: 16, color: c.texteSecondaire),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Choix d'un objectif dans une liste (null si la feuille est fermée).
Future<Objectif?> choisirObjectif(
  BuildContext context, {
  required String titre,
  required List<Objectif> objectifs,
  Objectif? initial,
}) async {
  if (objectifs.isEmpty) return null;
  final choix = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    backgroundColor: context.couleurs.fond,
    builder: (_) => _ChoixObjectif(titre: titre, objectifs: objectifs, initial: initial ?? objectifs.first),
  );
  return choix is Objectif ? choix : null;
}

/// Depuis une opération de l'accueil : la payer avec l'épargne d'un objectif, ou la détacher.
Future<void> rattacherOperation(BuildContext context, WidgetRef ref, Operation operation) async {
  if (operation.montant >= 0) return;
  if (operation.enAttente) {
    signaler(
      context,
      "Cette dépense est encore en attente : tu pourras la rattacher dès que la banque l'aura comptabilisée.",
    );
    return;
  }
  final donnees = ref.read(objectifsProvider).value ?? ref.read(cacheProvider).objectifs();
  final actifs = donnees?.actifs ?? <Objectif>[];
  if (actifs.isEmpty) {
    signaler(context, "Crée d'abord un objectif dans l'onglet Objectifs.");
    return;
  }
  final actuel = actifs.where((o) => o.id == operation.objectifId).firstOrNull;
  final choix = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    backgroundColor: context.couleurs.fond,
    builder: (_) => _ChoixObjectif(
      titre: "${operation.libelle} · ${euros(-operation.montant)} : payé avec l'épargne de quel objectif ?",
      objectifs: actifs,
      initial: actuel ?? actifs.first,
      detacher: actuel != null,
    ),
  );
  if (!context.mounted || choix == null) return;
  if (choix is Objectif) {
    await _agir(context, ref, (api) => api.rattacher(operation.id, choix.id));
  } else if (choix == _detacher) {
    await _agir(context, ref, (api) => api.rattacher(operation.id, null));
  }
}
