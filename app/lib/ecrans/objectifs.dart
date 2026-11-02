import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/api.dart';
import '../data/cache.dart';
import '../data/modeles.dart';
import '../data/objectifs.dart';
import '../theme/opti_theme.dart';
import '../util/format.dart';
import '../widgets/communs.dart';

part 'objectifs/tirelire.dart';
part 'objectifs/detail.dart';
part 'objectifs/feuilles.dart';

/// Icônes au trait proposées pour un objectif (nom enregistré en base → icône).
const iconesObjectif = <String, IconData>{
  'shield': LucideIcons.shield,
  'plane': LucideIcons.plane,
  'car': LucideIcons.car,
  'house': LucideIcons.house,
  'graduation-cap': LucideIcons.graduationCap,
  'gift': LucideIcons.gift,
  'smartphone': LucideIcons.smartphone,
  'laptop': LucideIcons.laptop,
  'heart': LucideIcons.heart,
  'bike': LucideIcons.bike,
  'briefcase': LucideIcons.briefcase,
  'piggy-bank': LucideIcons.piggyBank,
};

IconData iconeDe(Objectif o) => iconesObjectif[o.icone] ?? (o.imprevus ? LucideIcons.shield : LucideIcons.target);

/// Exécute une action, recharge l'écran, et affiche l'erreur éventuelle.
Future<bool> _agir(BuildContext context, WidgetRef ref, Future<void> Function(OptiApi api) action) async {
  try {
    await action(ref.read(apiProvider));
    ref.invalidate(objectifsProvider);
    ref.invalidate(accueilProvider); // l'épargne visée de l'accueil dépend des objectifs
    return true;
  } catch (e) {
    if (context.mounted) signaler(context, e);
    return false;
  }
}

// ── Liste ─────────────────────────────────────────────────────────────────────

class EcranObjectifsListe extends ConsumerWidget {
  const EcranObjectifsListe({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final donnees = ref.watch(objectifsProvider);
    // Réponse du serveur, sinon les objectifs de la dernière ouverture le temps qu'elle arrive.
    final d = donnees.value ?? ref.read(cacheProvider).objectifs();
    return Scaffold(
      body: FondOpti(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(objectifsProvider.future),
            child: d == null
                ? (donnees.hasError
                      ? Erreur(message: donnees.error.toString(), reessayer: () => ref.invalidate(objectifsProvider))
                      : const Center(child: CircularProgressIndicator()))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('Objectifs', style: context.titre(26))),
                          IconButton.filledTonal(
                            tooltip: 'Nouvel objectif',
                            onPressed: () => ouvrirFormulaireObjectif(context, ref),
                            icon: const Icon(LucideIcons.plus),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (d.aAttribuer.isNotEmpty) ...[
                        _CarteAAttribuer(operations: d.aAttribuer, objectifs: d.actifs),
                        const SizedBox(height: 12),
                      ],
                      for (final r in d.reprises) ...[
                        _CarteReprise(reprise: r, objectifs: d.actifs),
                        const SizedBox(height: 12),
                      ],
                      for (final sug in d.suggestions) ...[
                        _CarteSuggestion(suggestion: sug, objectifs: d.actifs),
                        const SizedBox(height: 12),
                      ],
                      for (final o in d.actifs) ...[_CarteObjectif(objectif: o), const SizedBox(height: 12)],
                      if (d.archives.isNotEmpty)
                        Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Etiquette('Archivés (${d.archives.length})'),
                            children: [
                              for (final o in d.archives) ...[_CarteObjectif(objectif: o), const SizedBox(height: 12)],
                            ],
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

class _CarteObjectif extends StatelessWidget {
  const _CarteObjectif({required this.objectif});
  final Objectif objectif;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final o = objectif;
    final String sousTitre;
    if (o.archive) {
      sousTitre = 'Archivé';
    } else if (o.atteint) {
      sousTitre = 'Objectif atteint';
    } else if (o.echeanceDepassee) {
      sousTitre = 'Échéance du ${jourMois(o.echeance!)} passée';
    } else if (o.parMois != null) {
      sousTitre = '${euros(o.parMois!)} / mois jusqu\'au ${dateLongue(o.echeance!)}';
    } else {
      sousTitre = 'Sans échéance';
    }
    return Carte(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EcranObjectif(id: o.id))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(iconeDe(o), size: 20, color: c.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(o.nom, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    Text(
                      sousTitre,
                      style: TextStyle(fontSize: 12.5, color: o.echeanceDepassee ? c.or : c.texteSecondaire),
                    ),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronRight, size: 18, color: c.texteSecondaire),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(euros(o.epargneTotale), style: chiffres(fontSize: 18, fontWeight: FontWeight.w500)),
              Text(' / ${euros(o.cible)}', style: chiffres(fontSize: 13, color: c.texteSecondaire)),
              const Spacer(),
              if (o.enAttente != 0)
                Text('${eurosSignes(o.enAttente)} en attente', style: TextStyle(fontSize: 12, color: c.or)),
            ],
          ),
          const SizedBox(height: 8),
          _Barre(valeur: o.progression, couleur: o.atteint ? c.ok : c.accent),
        ],
      ),
    );
  }
}

class _Barre extends StatelessWidget {
  const _Barre({required this.valeur, required this.couleur});
  final double valeur;
  final Color couleur;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(99),
    child: LinearProgressIndicator(
      value: valeur.clamp(0, 1).toDouble(),
      minHeight: 6,
      backgroundColor: context.couleurs.ligne,
      color: couleur,
    ),
  );
}

class _CarteAAttribuer extends ConsumerWidget {
  const _CarteAAttribuer({required this.operations, required this.objectifs});
  final List<OperationAAttribuer> operations;
  final List<Objectif> objectifs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.piggyBank, size: 16, color: c.or),
              const SizedBox(width: 8),
              const Etiquette('Dans ta tirelire, à attribuer'),
            ],
          ),
          for (final t in operations)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.montant > 0
                          ? '${euros(t.montant)} arrivés le ${jourMois(t.date)}'
                          : '${euros(-t.montant)} repris le ${jourMois(t.date)}',
                    ),
                  ),
                  TextButton(
                    onPressed: () => _choisirObjectif(context, ref, t),
                    child: const Text('Pour quel objectif ?'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _choisirObjectif(BuildContext context, WidgetRef ref, OperationAAttribuer t) async {
    final imprevus = objectifs.where((o) => o.imprevus).firstOrNull ?? objectifs.firstOrNull;
    if (imprevus == null) return;
    final choisi = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.couleurs.fond,
      builder: (_) => _ChoixObjectif(
        titre: t.montant > 0
            ? '${euros(t.montant)} arrivés dans ta tirelire : pour quel objectif ?'
            : '${euros(-t.montant)} repris de ta tirelire : pour quel objectif ?',
        objectifs: objectifs,
        initial: imprevus,
        annulationPossible: t.montant < 0,
      ),
    );
    if (!context.mounted) return;
    if (choisi is Objectif) {
      await _agir(context, ref, (api) => api.attribuer(t.id, choisi.id));
    } else if (choisi == _annulation) {
      await _annulerParRetrait(context, ref, t);
    }
  }

  /// « C'était une annulation » : montrer les versements concernés, puis les supprimer avec le retrait.
  Future<void> _annulerParRetrait(BuildContext context, WidgetRef ref, OperationAAttribuer t) async {
    final List<VersementAnnulable> versements;
    try {
      versements = await ref.read(apiProvider).proposerAnnulation(t.id);
    } catch (e) {
      if (context.mounted) signaler(context, e);
      return;
    }
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (contexte) => AlertDialog(
        title: Text('Annuler ${versements.length == 1 ? 'ce versement' : 'ces versements'} ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Les ${euros(-t.montant)} repris le ${jourMois(t.date)} annulent :'),
            const SizedBox(height: 8),
            for (final v in versements)
              Text(
                '• ${v.objectif} : ${eurosSignes(v.montant)} le ${jourMois(v.date)}'
                '${v.note != null && v.note!.isNotEmpty ? ' (${v.note})' : ''}',
              ),
            const SizedBox(height: 8),
            const Text("Ils disparaîtront de l'historique, comme s'ils n'avaient jamais eu lieu."),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(contexte, false), child: const Text('Non')),
          FilledButton(onPressed: () => Navigator.pop(contexte, true), child: const Text('Oui, annuler')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _agir(context, ref, (api) => api.annulerParRetrait(t.id, [for (final v in versements) v.id]));
    }
  }
}

/// Réponse « C'était une annulation » de la feuille de choix.
const _annulation = 'annulation';

/// Réponse « Ce n'est plus payé par un objectif » de la feuille de choix.
const _detacher = 'detacher';

class _ChoixObjectif extends StatefulWidget {
  const _ChoixObjectif({
    required this.titre,
    required this.objectifs,
    required this.initial,
    this.annulationPossible = false,
    this.detacher = false,
  });
  final String titre;
  final List<Objectif> objectifs;
  final Objectif initial;
  final bool annulationPossible;
  final bool detacher;

  @override
  State<_ChoixObjectif> createState() => _ChoixObjectifState();
}

class _ChoixObjectifState extends State<_ChoixObjectif> {
  late Objectif _choisi = widget.initial;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.titre, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            RadioGroup<Objectif>(
              groupValue: _choisi,
              onChanged: (o) => setState(() => _choisi = o ?? _choisi),
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
            FilledButton(onPressed: () => Navigator.pop(context, _choisi), child: const Text('Valider')),
            if (widget.annulationPossible)
              TextButton(
                onPressed: () => Navigator.pop(context, _annulation),
                child: const Text("C'était une annulation (rendre l'argent)"),
              ),
            if (widget.detacher)
              TextButton(
                onPressed: () => Navigator.pop(context, _detacher),
                child: const Text('Ne plus la payer avec un objectif'),
              ),
          ],
        ),
      ),
    );
  }
}
