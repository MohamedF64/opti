part of '../abonnements.dart';

// Cartes de la liste : abonnement, détecté, prix, dépassement, essai.

class _CarteAbonnement extends ConsumerWidget {
  const _CarteAbonnement({required this.abonnement});
  final Abonnement abonnement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final a = abonnement;
    final (statut, couleur) = statutAffiche(context, a, usage: ref.watch(usagesLocauxProvider)[a.id]);
    final quand = a.essaiJusquAu != null
        ? '${a.essai ? 'se termine' : 'terminé'} le ${jourMois(a.essaiJusquAu!)}'
              '${a.essaiJusquAu!.year != DateTime.now().year ? '/${a.essaiJusquAu!.year}' : ''}'
        : a.resilie
        ? (a.dernierPrelevement != null
              ? 'dernier le ${jourMois(a.dernierPrelevement!)}/${a.dernierPrelevement!.year}'
              : '')
        : (a.prochainPrelevement != null ? 'prochain le ${jourMois(a.prochainPrelevement!)}' : '');
    return Carte(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EcranAbonnement(id: a.id))),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
            child: Icon(iconeAbonnement(a), size: 20, color: a.resilie ? c.texteSecondaire : c.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.nom,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  [statut, if (quand.isNotEmpty) quand].join(' · '),
                  style: TextStyle(fontSize: 12.5, color: couleur),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${a.variable ? '≈ ' : ''}${euros(a.parMois)}', style: chiffres(fontWeight: FontWeight.w500)),
              Text('/ mois', style: TextStyle(fontSize: 11, color: c.texteSecondaire)),
            ],
          ),
        ],
      ),
    );
  }
}

class _CarteDetecte extends ConsumerWidget {
  const _CarteDetecte({required this.detecte});
  final AbonnementDetecte detecte;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final d = detecte;
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.sparkles, size: 16, color: c.or),
              const SizedBox(width: 8),
              const Etiquette('Nouvel abonnement ?'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${d.libelle} : ${euros(d.montant)} ${d.frequence == 'annuel' ? 'par an' : 'par mois'}, '
            'dernier prélèvement le ${jourMois(d.dernier)}.',
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => _agir(context, ref, (api) => api.refuserDetecte(d.cle)),
                child: const Text("Ce n'en est pas un"),
              ),
              FilledButton(
                onPressed: () => _agir(context, ref, (api) => api.ajouterDetecte(d.cle)),
                child: const Text('Ajouter'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CartePrix extends ConsumerWidget {
  const _CartePrix({required this.abonnement});
  final Abonnement abonnement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final a = abonnement;
    final p = a.changementPrix!;
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.trendingUp, size: 16, color: c.or),
              const SizedBox(width: 8),
              const Etiquette('Le prix a changé'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${a.nom} : ${euros(p.ancien)} → ${euros(p.nouveau)} par mois (dernier prélèvement le ${jourMois(p.depuis)}).',
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => ouvrirFormulaireAbonnement(context, ref, abonnement: a),
                child: const Text('Corriger'),
              ),
              FilledButton(
                onPressed: () => _agir(context, ref, (api) => api.accepterPrix(a.id)),
                child: const Text('OK'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Prélèvement au-dessus du prix maximum (§ 7, point 8).
class _CarteDepassement extends ConsumerWidget {
  const _CarteDepassement({required this.abonnement});
  final Abonnement abonnement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final a = abonnement;
    final p = a.depassement!;
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.triangleAlert, size: 16, color: c.alerte),
              const SizedBox(width: 8),
              const Etiquette('Au-dessus du maximum'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${a.nom} a prélevé ${euros(p.montant)} le ${jourMois(p.date)}, au-dessus de ton maximum de '
            '${euros(a.prixMaximum!)}. Hors-forfait ou hausse de prix ?',
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => ouvrirFormulaireAbonnement(context, ref, abonnement: a),
                child: const Text('Modifier le maximum'),
              ),
              FilledButton(
                onPressed: () => _agir(context, ref, (api) => api.depassementVu(a.id)),
                child: const Text('Compris'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Fin d'un essai sans prélèvement vu : « Tu l'as gardé ? » (§ 11).
class _CarteEssaiTermine extends ConsumerWidget {
  const _CarteEssaiTermine({required this.abonnement});
  final Abonnement abonnement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    final a = abonnement;
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.gift, size: 16, color: c.or),
              const SizedBox(width: 8),
              const Etiquette('Essai terminé'),
            ],
          ),
          const SizedBox(height: 8),
          Text("Ton essai ${a.nom} s'est terminé le ${jourMois(a.essaiJusquAu!)}. Tu l'as gardé ?"),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => _agir(context, ref, (api) => api.modifierAbonnement(a.id, {'statut': 'cancelled'})),
                child: const Text('Non, résilié'),
              ),
              FilledButton(
                onPressed: () => _agir(context, ref, (api) => api.modifierAbonnement(a.id, {'essai_garde': true})),
                child: Text('Oui, ${euros(a.montant)}'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
