part of '../objectifs.dart';

// Détail d'un objectif : épargne, rythme, mouvements.

// ── Détail ────────────────────────────────────────────────────────────────────

class EcranObjectif extends ConsumerWidget {
  const EcranObjectif({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final donnees = ref.watch(objectifsProvider);
    final o = (donnees.value ?? ref.read(cacheProvider).objectifs())?.objectifs.where((o) => o.id == id).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(o?.nom ?? ''),
        actions: [
          if (o != null)
            PopupMenuButton<String>(
              onSelected: (choix) async {
                if (choix == 'modifier') {
                  await ouvrirFormulaireObjectif(context, ref, objectif: o);
                } else {
                  await _agir(
                    context,
                    ref,
                    (api) => api.modifierObjectif(o.id, {'statut': o.archive ? 'active' : 'archive'}),
                  );
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'modifier', child: Text('Modifier')),
                if (!o.imprevus) PopupMenuItem(value: 'archiver', child: Text(o.archive ? 'Réactiver' : 'Archiver')),
              ],
            ),
        ],
      ),
      body: o == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => ref.refresh(objectifsProvider.future),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  _CarteEpargne(objectif: o),
                  if (o.echeanceDepassee) ...[const SizedBox(height: 12), _CarteRepousser(objectif: o)],
                  if (o.parJour != null && !o.atteint) ...[const SizedBox(height: 12), _TuilesBesoin(objectif: o)],
                  const SizedBox(height: 12),
                  _CarteRythme(objectif: o),
                  const SizedBox(height: 12),
                  _CarteMouvements(objectif: o),
                  if (o.depenses.isNotEmpty) ...[const SizedBox(height: 12), _CarteDepenses(objectif: o)],
                ],
              ),
            ),
    );
  }
}

class _CarteEpargne extends ConsumerWidget {
  const _CarteEpargne({required this.objectif});
  final Objectif objectif;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final o = objectif;
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(iconeDe(o), color: c.accent),
              const SizedBox(width: 10),
              Etiquette(o.imprevus ? 'Épargne de précaution' : 'Mis de côté'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                euros(o.epargneTotale),
                style: chiffres(fontSize: 36, fontWeight: FontWeight.w500, letterSpacing: -1, color: c.accent),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(' / ${euros(o.cible)}', style: chiffres(fontSize: 14, color: c.texteSecondaire)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Barre(valeur: o.progression, couleur: o.atteint ? c.ok : c.accent),
          const SizedBox(height: 10),
          if (o.atteint)
            Text('Objectif atteint. Bravo !', style: TextStyle(color: c.ok))
          else
            Text('Il reste ${euros(o.reste)} à mettre de côté.', style: TextStyle(color: c.texteSecondaire)),
          if (o.depense > 0)
            Text(
              'Dans la tirelire : ${euros(o.disponible)} · déjà dépensé avec : ${euros(o.depense)}',
              style: TextStyle(color: c.texteSecondaire, fontSize: 13),
            ),
          if (!o.archive) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _ouvrirMouvement(context, ref, o, piocher: false),
                    icon: const Icon(LucideIcons.arrowDownToLine, size: 16),
                    label: const Text('Mettre de côté'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: o.disponible > 0 ? () => _ouvrirMouvement(context, ref, o, piocher: true) : null,
                    icon: const Icon(LucideIcons.arrowUpFromLine, size: 16),
                    label: const Text('Piocher'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CarteRepousser extends ConsumerWidget {
  const _CarteRepousser({required this.objectif});
  final Objectif objectif;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final o = objectif;
    final suggeree = o.echeanceSuggeree;
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.calendarClock, size: 18, color: c.or),
              const SizedBox(width: 8),
              Expanded(
                child: Text('L\'échéance du ${dateLongue(o.echeance!)} est passée.', style: TextStyle(color: c.or)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            suggeree != null
                ? 'À ton rythme, tu y arriveras le ${dateLongue(suggeree)}. Tu veux la repousser ?'
                : 'Choisis une nouvelle date pour recalculer ce qu\'il faut mettre de côté.',
            style: TextStyle(color: c.texteSecondaire, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (suggeree != null)
                FilledButton(
                  onPressed: () => _agir(context, ref, (api) => api.modifierObjectif(o.id, {'echeance': suggeree})),
                  child: Text('Repousser au ${jourMois(suggeree)}/${suggeree.year}'),
                ),
              OutlinedButton(
                onPressed: () async {
                  final date = await _choisirDate(context, suggeree);
                  if (date != null && context.mounted) {
                    await _agir(context, ref, (api) => api.modifierObjectif(o.id, {'echeance': date}));
                  }
                },
                child: const Text('Choisir une date'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TuilesBesoin extends StatelessWidget {
  const _TuilesBesoin({required this.objectif});
  final Objectif objectif;

  @override
  Widget build(BuildContext context) {
    final o = objectif;
    Widget tuile(String titre, double montant) => Expanded(
      child: Carte(
        child: Column(
          children: [
            Etiquette(titre),
            const SizedBox(height: 6),
            FittedBox(
              child: Text(euros(montant), style: chiffres(fontSize: 16, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Pour tenir le ${dateLongue(o.echeance!)} (${o.joursRestants} jours), mets de côté :',
            style: TextStyle(color: context.couleurs.texteSecondaire, fontSize: 13),
          ),
        ),
        Row(
          children: [
            tuile('Par jour', o.parJour!),
            const SizedBox(width: 8),
            tuile('Par semaine', o.parSemaine!),
            const SizedBox(width: 8),
            tuile('Par mois', o.parMois!),
          ],
        ),
      ],
    );
  }
}

class _CarteRythme extends StatelessWidget {
  const _CarteRythme({required this.objectif});
  final Objectif objectif;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final o = objectif;
    final String phrase;
    if (o.atteint) {
      phrase = 'Tu as atteint ta cible.';
    } else if (o.premierVersement == null) {
      phrase = 'Pas encore de versement confirmé : ton rythme apparaîtra un mois après le premier.';
    } else if (!o.rythmeConnu) {
      phrase =
          '${euros(o.verse)} mis de côté depuis le ${jourMois(o.premierVersement!)}. '
          'Ton rythme apparaîtra après un mois de versements.';
    } else if (o.rythmeMensuel <= 0) {
      phrase = 'Aucun versement ces derniers mois.';
    } else if (o.dateEstimee != null && o.dateEstimee!.isAfter(DateTime.now().add(const Duration(days: 5 * 365)))) {
      phrase =
          'Tu mets de côté environ ${euros(o.rythmeMensuel)} par mois : à ce rythme, '
          'il te faudrait plus de 5 ans. Chaque versement fait bouger cette estimation.';
    } else if (o.dateEstimee != null) {
      phrase =
          'Tu mets de côté environ ${euros(o.rythmeMensuel)} par mois : '
          'tu y arriveras vers le ${dateLongue(o.dateEstimee!)}.';
    } else {
      phrase = 'Tu mets de côté environ ${euros(o.rythmeMensuel)} par mois.';
    }
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.trendingUp, size: 16, color: c.texteSecondaire),
              const SizedBox(width: 8),
              const Etiquette('À ton rythme'),
              const Spacer(),
              if (o.faisabilite != null)
                Text(
                  'Faisabilité ${o.faisabilite}/100',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: o.faisabilite! >= 80 ? c.ok : (o.faisabilite! >= 50 ? c.or : c.alerte),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(phrase),
          if (o.faisabilite != null) ...[
            const SizedBox(height: 10),
            _Barre(
              valeur: o.faisabilite! / 100,
              couleur: o.faisabilite! >= 80 ? c.ok : (o.faisabilite! >= 50 ? c.or : c.alerte),
            ),
          ],
        ],
      ),
    );
  }
}

class _CarteMouvements extends ConsumerWidget {
  const _CarteMouvements({required this.objectif});
  final Objectif objectif;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final mouvements = objectif.mouvements;
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Etiquette('Versements'),
          if (mouvements.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Aucun pour l\'instant.', style: TextStyle(color: c.texteSecondaire)),
            ),
          for (final m in mouvements) _LigneMouvement(mouvement: m),
        ],
      ),
    );
  }
}

class _LigneMouvement extends ConsumerWidget {
  const _LigneMouvement({required this.mouvement});
  final MouvementObjectif mouvement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final m = mouvement;
    final verbe = m.montant > 0 ? 'Mis de côté' : 'Pioché';
    final String etat;
    if (m.enAttente) {
      etat = m.rappel ? 'Virement pas encore vu depuis le ${jourMois(m.declareLe)}' : 'En attente du virement';
    } else {
      etat = m.reconnuAutomatiquement ? 'Virement reconnu le ${jourMois(m.confirmeLe!)}' : 'Confirmé à la main';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                m.enAttente ? LucideIcons.hourglass : LucideIcons.check,
                size: 16,
                color: m.enAttente ? (m.rappel ? c.alerte : c.or) : c.ok,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$verbe le ${jourMois(m.declareLe)}${m.note != null && m.note!.isNotEmpty ? ' · ${m.note}' : ''}',
                    ),
                    Text(etat, style: TextStyle(fontSize: 12, color: m.rappel ? c.alerte : c.texteSecondaire)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(eurosSignes(m.montant), style: chiffres(color: m.montant > 0 ? c.ok : c.texte)),
            ],
          ),
          if (m.enAttente)
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: () => _agir(context, ref, (api) => api.annuler(m.id)),
                    child: const Text('Annuler'),
                  ),
                  TextButton(
                    onPressed: () => _confirmerALaMain(context, ref, m),
                    child: const Text('J\'ai fait le virement'),
                  ),
                ],
              ),
            )
          else if (m.reconnuAutomatiquement)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _agir(context, ref, (api) => api.contester(m.id)),
                child: const Text('Ce n\'est pas ce virement'),
              ),
            ),
        ],
      ),
    );
  }
}
