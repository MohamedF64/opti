import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'depense.dart';
import 'bilan.dart';
import 'conseils.dart';
import '../config.dart';
import '../data/api.dart';
import '../data/cache.dart';
import '../data/modeles.dart';
import 'historique.dart';
import 'reglages.dart';
import '../theme/opti_theme.dart';
import '../util/format.dart';
import '../widgets/communs.dart';

/// Accueil : une seule grosse info, « tu peux encore dépenser X € aujourd'hui ».
class EcranAccueil extends ConsumerStatefulWidget {
  const EcranAccueil({super.key});

  @override
  ConsumerState<EcranAccueil> createState() => _EcranAccueilState();
}

class _EcranAccueilState extends ConsumerState<EcranAccueil> {
  bool _synchroEnCours = false;
  String? _erreurSynchro;

  @override
  void initState() {
    super.initState();
    // Synchro à l'ouverture : l'accueil s'affiche tout de suite (derniers chiffres connus), puis se met à jour.
    WidgetsBinding.instance.addPostFrameCallback((_) => _synchroniser(forcer: false));
  }

  /// Pas de nouvelle synchro à l'ouverture si la dernière a moins de 2 minutes ;
  /// « tirer vers le bas » (forcer) synchronise toujours.
  static const _synchroRecente = Duration(minutes: 2);

  Future<void> _synchroniser({bool forcer = true}) async {
    if (_synchroEnCours) return;
    if (!forcer) {
      final derniere = (ref.read(accueilProvider).value ?? ref.read(cacheProvider).accueil())?.derniereSynchro;
      if (derniere != null && DateTime.now().difference(derniere) < _synchroRecente) return;
    }
    setState(() {
      _synchroEnCours = true;
      _erreurSynchro = null;
    });
    try {
      await ref.read(apiProvider).synchroniser();
    } catch (e) {
      _erreurSynchro = e.toString();
    } finally {
      if (mounted) {
        setState(() => _synchroEnCours = false);
        ref.invalidate(accueilProvider);
        ref.invalidate(bilanProvider);
        ref.invalidate(conseilsProvider);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accueil = ref.watch(accueilProvider);
    // Réponse du serveur, sinon les chiffres de la dernière ouverture le temps qu'elle arrive.
    final a = accueil.value ?? ref.read(cacheProvider).accueil();
    final erreur = _erreurSynchro ?? (accueil.hasError ? accueil.error.toString() : null);
    return Scaffold(
      body: FondOpti(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _synchroniser,
            child: a == null
                ? (accueil.hasError
                      ? Erreur(message: erreur!, reessayer: () => ref.invalidate(accueilProvider))
                      : const Center(child: CircularProgressIndicator()))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      _EnTete(accueil: a, synchroEnCours: _synchroEnCours || accueil.isLoading, erreurSynchro: erreur),
                      const SizedBox(height: 16),
                      for (final b in a.banques.where(
                        (b) => b.statut == 'expiree' || (b.joursRestants ?? 99) <= 14,
                      )) ...[_CarteRenouvellement(banque: b), const SizedBox(height: 12)],
                      const CarteBilan(),
                      _CarteDuJour(budget: a.budget),
                      const CarteConseils(),
                      const SizedBox(height: 12),
                      _CarteCycle(budget: a.budget),
                      const SizedBox(height: 12),
                      _CarteOperations(operations: a.operations),
                      const SizedBox(height: 12),
                      _CarteComptes(accueil: a),
                      const SizedBox(height: 20),
                      const VersionOpti(),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Rappel du renouvellement de l'accès bancaire (DSP2 : 180 jours), dès 14 jours avant ; rouge à 7 jours.
class _CarteRenouvellement extends StatelessWidget {
  const _CarteRenouvellement({required this.banque});
  final Banque banque;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final b = banque;
    final expire = b.statut == 'expiree' || (b.joursRestants ?? 0) <= 0;
    final urgent = expire || (b.joursRestants ?? 0) <= 7;
    final couleur = urgent ? c.alerte : c.or;
    return Carte(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EcranReglages())),
      child: Row(
        children: [
          Icon(LucideIcons.landmark, color: couleur),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expire
                      ? 'Ton accès ${b.nom} a expiré'
                      : 'Ton accès ${b.nom} expire${b.accesJusquAu != null ? ' le ${jourMois(b.accesJusquAu!)}' : ''}'
                            ' (dans ${b.joursRestants} jours)',
                  style: TextStyle(color: couleur, fontWeight: FontWeight.w600),
                ),
                Text(
                  "Renouvelle-le dans les Réglages : 1 minute, avec l'app de ta banque.",
                  style: TextStyle(fontSize: 12.5, color: c.texteSecondaire),
                ),
              ],
            ),
          ),
          Icon(LucideIcons.chevronRight, size: 18, color: c.texteSecondaire),
        ],
      ),
    );
  }
}

class _EnTete extends StatelessWidget {
  const _EnTete({required this.accueil, required this.synchroEnCours, this.erreurSynchro});
  final Accueil accueil;
  final bool synchroEnCours;
  final String? erreurSynchro;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final heure = DateTime.now().hour;
    final derniere = accueil.derniereSynchro;
    final probleme = erreurSynchro != null || accueil.synchroEnErreur || accueil.consentementARenouveler;
    final couleur = synchroEnCours ? c.texteSecondaire : (probleme ? c.or : c.ok);
    final texte = synchroEnCours
        ? 'Synchro…'
        : accueil.consentementARenouveler
        ? 'Accès banque à renouveler'
        : (erreurSynchro != null || accueil.synchroEnErreur)
        ? 'Synchro en échec'
        : derniere == null
        ? 'Jamais synchronisé'
        : 'À jour · ${ilYa(derniere)}';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(heure < 18 ? 'Bonjour,' : 'Bonsoir,', style: TextStyle(color: c.texteSecondaire)),
              if (prenom.isNotEmpty) Text(prenom, style: context.titre(26)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: c.surface.withValues(alpha: 1), // fond plein : lisible sur les fonds animés et les images
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: couleur.withValues(alpha: 0.6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              synchroEnCours
                  ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: couleur))
                  : Icon(probleme ? LucideIcons.cloudAlert : LucideIcons.cloudCheck, size: 14, color: couleur),
              const SizedBox(width: 6),
              Text(texte, style: TextStyle(fontSize: 12, color: couleur)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Réglages',
          icon: Icon(LucideIcons.settings, size: 20, color: c.texteSecondaire),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EcranReglages())),
        ),
      ],
    );
  }
}

class _CarteDuJour extends StatelessWidget {
  const _CarteDuJour({required this.budget});
  final Budget budget;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final depasse = budget.tuPeuxEncore < 0;
    final couleurBarre = budget.progression >= 1 ? c.alerte : (budget.progression >= 0.75 ? c.or : c.ok);
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Etiquette(depasse ? "Limite du jour dépassée de" : "Tu peux encore dépenser aujourd'hui")),
          const SizedBox(height: 6),
          Text(
            euros(budget.tuPeuxEncore.abs()),
            textAlign: TextAlign.center,
            style: chiffres(
              fontSize: 48,
              fontWeight: FontWeight.w500,
              letterSpacing: -1.5,
              color: depasse ? c.alerte : c.accent,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: budget.progression.clamp(0, 1).toDouble(),
              minHeight: 6,
              backgroundColor: c.ligne,
              color: couleurBarre,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Dépensé : ${euros(budget.depenseAujourdhui)}',
                style: TextStyle(fontSize: 12.5, color: c.texteSecondaire),
              ),
              const Spacer(),
              Text(
                'Limite du jour : ${euros(budget.limiteDuJour)}',
                style: TextStyle(fontSize: 12.5, color: c.texteSecondaire),
              ),
            ],
          ),
          // Cycle dépassé (§ 1) : de combien, et la limite « courses habituelles » qui remplace 0 €.
          if (budget.depassement > 0) ...[
            const SizedBox(height: 10),
            Text(
              'Budget du cycle dépassé de ${euros(budget.depassement)}.'
              '${budget.limiteAppliquee == 'essentiel' ? ' Pour finir le cycle, vise ${euros(budget.limiteDuJour)} par jour '
                        "pour l'essentiel : ce sera pris sur ton épargne." : ''}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.or),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            child: TextButton.icon(
              onPressed: () => _montrerPourquoi(context, budget),
              icon: const Icon(LucideIcons.circleQuestionMark, size: 16),
              label: Text('Pourquoi ${euros(budget.limiteDuJour)} ?'),
            ),
          ),
        ],
      ),
    );
  }
}

void _montrerPourquoi(BuildContext context, Budget budget) {
  final c = context.couleurs;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.fond,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pourquoi ${euros(budget.limiteDuJour)} ?',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            for (final l in budget.pourquoi)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.libelle,
                        style: TextStyle(
                          color: l.libelle.startsWith('Reste') ? c.texte : c.texteSecondaire,
                          fontWeight: l.libelle.startsWith('Reste') ? FontWeight.w700 : FontWeight.normal,
                        ),
                      ),
                    ),
                    Text(
                      l.libelle.startsWith('÷') ? '${euros(l.montant)} / jour' : eurosSignes(l.montant),
                      style: chiffres(),
                    ),
                  ],
                ),
              ),
            if (budget.limiteAppliquee == 'plancher' && budget.effetLimiteManuelle != 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Ta marge de sécurité s\'applique : tes prochains jours baissent de ${euros(budget.effetLimiteManuelle)} chacun.',
                  style: TextStyle(color: c.or, fontSize: 13),
                ),
              ),
            if (budget.abonnementsAVenir.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Etiquette('Abonnements à venir'),
              const SizedBox(height: 6),
              for (final a in budget.abonnementsAVenir)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Text(jourMois(a.date), style: TextStyle(color: c.texteSecondaire, fontSize: 13)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(a.nom, style: const TextStyle(fontSize: 13))),
                      const SizedBox(width: 12),
                      Text(euros(a.montant), style: chiffres(fontSize: 13)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _CarteCycle extends StatelessWidget {
  const _CarteCycle({required this.budget});
  final Budget budget;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Carte(
      child: Row(
        children: [
          Icon(LucideIcons.calendarClock, color: c.or, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  budget.paieEnRetard
                      ? 'Paie en retard (attendue au plus tard le ${jourMois(budget.paieAuPlusTard)})'
                      : 'Paie entre le ${jourMois(budget.paieAuPlusTot)} et le ${jourMois(budget.paieAuPlusTard)}',
                  style: const TextStyle(fontSize: 14),
                ),
                Text(
                  '${budget.joursRestants} jours · reste du cycle ${euros(budget.resteDuCycle)}',
                  style: TextStyle(fontSize: 12.5, color: c.texteSecondaire),
                ),
                // Le reste du cycle est figé au début de la journée (la limite du jour ne bouge pas) :
                // on montre aussi ce qu'il deviendra demain avec les dépenses d'aujourd'hui.
                if (budget.depenseAujourdhui > 0)
                  Text(
                    "après aujourd'hui : ${euros(budget.resteApresAujourdhui)}"
                    '${budget.joursRestants > 1 && budget.resteApresAujourdhui > 0 ? ' · ≈ ${euros(budget.limiteDemain)}/jour dès demain' : ''}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: budget.limiteDemain < budget.limiteDuJour ? c.or : c.texteSecondaire,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CarteOperations extends ConsumerWidget {
  const _CarteOperations({required this.operations});
  final List<Operation> operations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final objectifs = (ref.watch(objectifsProvider).value ?? ref.read(cacheProvider).objectifs())?.objectifs ?? [];
    String? payePar(Operation o) => objectifs.where((x) => x.id == o.objectifId).firstOrNull?.nom;
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Etiquette("Aujourd'hui")),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EcranHistorique())),
                child: const Text('Tout voir'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (operations.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text("Aucune opération aujourd'hui.", style: TextStyle(color: c.texteSecondaire)),
            ),
          for (final o in operations)
            InkWell(
              // Toucher une dépense : changer sa catégorie, ou la payer avec l'épargne d'un objectif.
              onTap: o.montant < 0 ? () => toucherDepense(context, ref, o) : null,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(o.libelle, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(
                            payePar(o) != null
                                ? 'Payé avec « ${payePar(o)} » · ${o.banque}'
                                : '${o.categorie} · ${o.banque}${o.enAttente ? ' · en attente' : ''}',
                            style: TextStyle(fontSize: 12, color: payePar(o) != null ? c.accent : c.texteSecondaire),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(eurosSignes(o.montant), style: chiffres(color: o.montant > 0 ? c.ok : c.texte)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CarteComptes extends StatelessWidget {
  const _CarteComptes({required this.accueil});
  final Accueil accueil;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Etiquette('Mes comptes'),
              const Spacer(),
              Text(euros(accueil.soldeTotal), style: chiffres(fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 8),
          for (final b in accueil.banques)
            for (final compte in b.comptes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(LucideIcons.landmark, size: 16, color: c.texteSecondaire),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${b.nom} · ${compte.libelle}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text(compte.solde == null ? '—' : euros(compte.solde!), style: chiffres()),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
