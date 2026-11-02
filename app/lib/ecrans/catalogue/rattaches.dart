part of '../catalogue.dart';

// Abonnements rattachés, leurs lignes et alternatives ; offres groupées.

// ── Abonnement rattaché ───────────────────────────────────────────────────────

class _CarteRattache extends ConsumerWidget {
  const _CarteRattache({required this.abonnement, required this.ecran});
  final AbonnementCatalogue abonnement;
  final DonneesCatalogue ecran;

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
              Expanded(
                child: Text(a.nom, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: 'Modifier le rattachement',
                visualDensity: VisualDensity.compact,
                onPressed: () => ouvrirLignes(context, ref, a, ecran),
                icon: const Icon(LucideIcons.pencil, size: 18),
              ),
            ],
          ),
          for (final l in a.lignes) ...[const SizedBox(height: 6), _Ligne(ligne: l, seule: a.lignes.length == 1)],
          if (a.lignes.length > 1) ...[
            const SizedBox(height: 8),
            Text(
              'Un seul prélèvement de ${euros(a.parMois)}/mois en moyenne pour ${a.lignes.length} lignes.',
              style: TextStyle(fontSize: 12, color: c.texteSecondaire),
            ),
          ],
        ],
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({required this.ligne, required this.seule});
  final LigneAbonnement ligne;
  final bool seule;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final l = ligne;
    final details = [if (!seule) l.nom, if (l.offre != null) l.offre!.nom, if (l.go != null) '${l.go} Go'].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(details, style: TextStyle(color: c.texteSecondaire)),
            ),
            if (l.prix != null) Text('${euros(l.prix!)}/mois', style: chiffres(fontSize: 14)),
          ],
        ),
        if (l.goManquants)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Indique tes Go pour comparer avec les autres opérateurs.',
              style: TextStyle(fontSize: 12, color: c.or),
            ),
          )
        else if (l.alternatives.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(LucideIcons.badgeCheck, size: 14, color: c.ok),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Pas moins cher dans le catalogue.',
                    style: TextStyle(fontSize: 12, color: c.texteSecondaire),
                  ),
                ),
              ],
            ),
          )
        else
          for (final alt in l.alternatives.take(3)) _Alternative(offre: alt),
      ],
    );
  }
}

class _Alternative extends StatelessWidget {
  const _Alternative({required this.offre});
  final Offre offre;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final o = offre;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.ok.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.ok.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.trendingDown, size: 16, color: c.ok),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    o.memeService ? o.nom : '${o.service} · ${o.nom}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${prixOffre(o)} : ${euros(o.economieParMois!)} de moins par mois, '
              '${eurosCourts(o.economieParAn!)} par an',
              style: chiffres(fontSize: 13),
            ),
            const SizedBox(height: 6),
            _Badges(offre: o),
          ],
        ),
      ),
    );
  }
}

/// Conditions, promo, paiement d'avance, essai, engagement, date de vérification.
class _Badges extends StatelessWidget {
  const _Badges({required this.offre, this.verification = false});
  final Offre offre;
  final bool verification;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final o = offre;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (o.aReverifier) _Badge('À revérifier', c.or),
        if (o.texteConditions != null) _Badge(o.texteConditions!, c.accent),
        if (o.prixPromo != null)
          _Badge(
            'Promo ${euros(o.prixPromo!)}${o.promoDuree != null ? ' ${o.promoDuree}' : ''}, puis ${euros(o.prix)}',
            c.or,
          ),
        if (o.paiementDAvance != null) _Badge("${eurosCourts(o.paiementDAvance!)} payés d'avance", c.or),
        if (o.essai != null) _Badge(o.essai!, c.texteSecondaire),
        if (o.engagement != null && o.engagement != 'sans engagement' && o.paiementDAvance == null)
          _Badge(o.engagement!, c.texteSecondaire),
        if (verification) _Badge('Vérifié le ${jourMois(o.verifieLe)}/${o.verifieLe.year}', c.texteSecondaire),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.texte, this.couleur);
  final String texte;
  final Color couleur;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: couleur.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
    child: Text(texte, style: TextStyle(fontSize: 11, color: couleur)),
  );
}

// ── Offres groupées ───────────────────────────────────────────────────────────

class _CarteGroupee extends StatelessWidget {
  const _CarteGroupee({required this.groupee});
  final OffreGroupee groupee;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final g = groupee;
    final o = g.offre;
    final ecart = g.ecartParMois;
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.package, size: 18, color: c.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(o.nom, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Text('${euros(o.parMois)}/mois', style: chiffres(fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          Text('Avantages', style: TextStyle(fontSize: 12, color: c.ok)),
          Text(
            [
              'Inclut ${o.inclut.join(', ')}',
              if (ecart < 0) '${euros(-ecart)} de moins par mois',
              if (g.goEnPlus > 0) '${g.goEnPlus} Go de plus',
              'une seule facture',
            ].join(' · '),
          ),
          const SizedBox(height: 8),
          Text('Inconvénients', style: TextStyle(fontSize: 12, color: c.or)),
          Text(
            [
              if (ecart > 0) '${euros(ecart)} de plus par mois',
              'tout est lié : résilier l\'un touche l\'autre',
            ].join(' · '),
          ),
          const SizedBox(height: 8),
          Text(
            'Aujourd\'hui : ${g.remplace.map((r) => '${r.nom} ${euros(r.parMois)}').join(' + ')} '
            '= ${euros(g.coutActuel)}/mois.',
            style: TextStyle(fontSize: 12, color: c.texteSecondaire),
          ),
        ],
      ),
    );
  }
}
