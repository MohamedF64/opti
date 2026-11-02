part of '../abonnements.dart';

// Détail d'un abonnement.

// ── Détail ────────────────────────────────────────────────────────────────────

/// « Moins cher dans le catalogue » : une option (§ 12), qui ne contredit pas le verdict.
class _MoinsCher extends ConsumerWidget {
  const _MoinsCher({required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final abonnement = ref.watch(catalogueProvider).value?.abonnements.where((a) => a.id == id).firstOrNull;
    Offre? meilleure;
    for (final l in abonnement?.lignes ?? const <LigneAbonnement>[]) {
      final o = l.alternatives.firstOrNull;
      if (o != null && (meilleure == null || o.economieParAn! > meilleure.economieParAn!)) meilleure = o;
    }
    if (meilleure == null) return const SizedBox.shrink();
    final o = meilleure;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Carte(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EcranCatalogue())),
        child: Row(
          children: [
            Icon(LucideIcons.tags, color: c.ok, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Moins cher dans le catalogue : ${o.memeService ? o.nom : '${o.service} ${o.nom}'}, '
                '${euros(o.economieParAn!)} par an d\'économie.',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 18, color: c.texteSecondaire),
          ],
        ),
      ),
    );
  }
}

class EcranAbonnement extends ConsumerWidget {
  const EcranAbonnement({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final donnees = ref.watch(abonnementsProvider).value ?? ref.read(cacheProvider).abonnements();
    final a = donnees?.abonnements.where((a) => a.id == id).firstOrNull;
    if (a == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final usage = ref.watch(usagesLocauxProvider)[a.id] ?? a.usage;
    final verdict = verdictDe(usage);
    final (statut, couleur) = statutAffiche(context, a, usage: usage);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(a.nom),
        actions: [
          PopupMenuButton<String>(
            onSelected: (choix) async {
              switch (choix) {
                case 'modifier':
                  await ouvrirFormulaireAbonnement(context, ref, abonnement: a);
                case 'resilier':
                  await _agir(
                    context,
                    ref,
                    (api) => api.modifierAbonnement(a.id, {'statut': a.resilie ? 'active' : 'cancelled'}),
                  );
                case 'supprimer':
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (contexte) => AlertDialog(
                      title: Text('Supprimer « ${a.nom} » ?'),
                      content: const Text(
                        "Il disparaît de la liste et n'est plus compté dans ta limite du jour. "
                        'Pour garder une trace, préfère « Résilier ».',
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(contexte, false), child: const Text('Annuler')),
                        FilledButton(onPressed: () => Navigator.pop(contexte, true), child: const Text('Supprimer')),
                      ],
                    ),
                  );
                  if (ok == true &&
                      context.mounted &&
                      await _agir(context, ref, (api) => api.supprimerAbonnement(a.id))) {
                    if (context.mounted) Navigator.of(context).pop();
                  }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'modifier', child: Text('Modifier')),
              PopupMenuItem(value: 'resilier', child: Text(a.resilie ? 'Réactiver' : "J'ai résilié")),
              const PopupMenuItem(value: 'supprimer', child: Text('Supprimer')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(abonnementsProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Carte(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(iconeAbonnement(a), color: c.accent),
                      const SizedBox(width: 10),
                      Expanded(child: Etiquette(a.categorie ?? 'Abonnement')),
                      Text(
                        statut,
                        style: TextStyle(color: couleur, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${a.variable ? '≈ ' : ''}${euros(a.montant)}',
                    style: chiffres(fontSize: 34, fontWeight: FontWeight.w500, letterSpacing: -1, color: c.accent),
                  ),
                  Text(
                    [
                      switch (a.frequence) {
                        'annuel' => 'par an (${euros(a.parMois)} / mois)',
                        'trimestriel' => 'par trimestre (${euros(a.parMois)} / mois)',
                        'hebdomadaire' => 'par semaine (${euros(a.parMois)} / mois)',
                        _ => a.variable ? 'par mois en moyenne' : 'par mois',
                      },
                      if (a.prixMaximum != null) "jusqu'à ${euros(a.prixMaximum!)}",
                      if (a.variable) 'de ${euros(a.montantMin!)} à ${euros(a.montantMax!)} sur les 3 derniers',
                      if (a.montantManuel) 'montant corrigé à la main',
                    ].join(' · '),
                    style: TextStyle(color: c.texteSecondaire, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  if (!a.resilie && a.prochainPrelevement != null)
                    Text('Prochain prélèvement : ${dateLongue(a.prochainPrelevement!)}'),
                  if (a.aVerifier)
                    Text(
                      'Pas vu depuis le ${jourMois(a.dernierPrelevement!)} : résilié ? Dis-le-moi avec « J\'ai résilié ».',
                      style: TextStyle(color: c.or, fontSize: 13),
                    ),
                  if (a.moisPause.isNotEmpty)
                    Text(
                      'Pas de prélèvement en ${a.moisPause.map((m) => _moisCourts[m - 1]).join(', ')}.',
                      style: TextStyle(color: c.texteSecondaire, fontSize: 13),
                    ),
                ],
              ),
            ),
            if (!a.resilie && !a.essai) _MoinsCher(id: a.id),
            if (!a.resilie) ...[
              const SizedBox(height: 12),
              Carte(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Etiquette('Tu t\'en sers…'),
                    const SizedBox(height: 10),
                    SegmentedButton<String>(
                      segments: [for (final (cle, libelle) in _usages) ButtonSegment(value: cle, label: Text(libelle))],
                      selected: {?usage},
                      emptySelectionAllowed: true,
                      showSelectedIcon: false,
                      onSelectionChanged: (choix) {
                        if (choix.isNotEmpty) _changerUsage(context, ref, a.id, choix.first);
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(switch (verdict) {
                      'rentable' => 'Il te sert bien : garde-le.',
                      'a_revoir' => 'Tu t\'en sers parfois : vérifie qu\'il vaut toujours son prix.',
                      'a_couper' =>
                        'Tu ne t\'en sers pas : en le résiliant, tu économiserais ${euros(a.parMois * 12)} par an.',
                      _ => 'Indique à quel point tu t\'en sers pour savoir s\'il est rentable.',
                    }, style: TextStyle(color: couleur)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Carte(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Etiquette('Prélèvements'),
                  if (a.historique.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Aucun prélèvement trouvé sur 13 mois.', style: TextStyle(color: c.texteSecondaire)),
                    ),
                  for (final p in a.historique)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Text(
                            '${jourMois(p.date)}/${p.date.year}',
                            style: TextStyle(color: c.texteSecondaire, fontSize: 13),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(p.libelle, maxLines: 1, overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 12),
                          Text(euros(p.montant), style: chiffres()),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// L'usage s'affiche tout de suite ; l'enregistrement part en arrière-plan. L'usage ne change pas
/// la limite du jour : l'accueil n'est pas recalculé.
Future<void> _changerUsage(BuildContext context, WidgetRef ref, String id, String usage) async {
  final locaux = ref.read(usagesLocauxProvider.notifier)..fixer(id, usage);
  try {
    await ref.read(apiProvider).modifierAbonnement(id, {'usage': usage});
    ref.invalidate(abonnementsProvider);
    await ref.read(abonnementsProvider.future);
  } catch (e) {
    if (context.mounted) signaler(context, 'Usage non enregistré : $e');
  } finally {
    locaux.oublier(id);
  }
}
