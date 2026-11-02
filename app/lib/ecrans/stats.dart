import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'depense.dart';
import '../data/api.dart';
import '../data/cache.dart';
import '../data/modeles.dart';
import '../data/stats.dart';
import '../theme/opti_theme.dart';
import '../util/format.dart';
import '../widgets/communs.dart';
import 'historique.dart';

const _periodes = [('cycle', 'Ce cycle'), ('precedent', 'Cycle précédent'), ('6', '6 cycles'), ('12', '12 cycles')];

/// Couleurs des parts du donut, dans l'ordre (la dernière, grise, est « Le reste »).
/// Teintes bien distinctes dans les 4 combinaisons (en Forêt, accent et « OK » sont le même vert).
List<Color> _palette(OptiColors c) => [
  c.accent,
  c.or,
  _troisieme(c),
  c.sombre ? const Color(0xFFF472B6) : const Color(0xFFDB2777), // rose
  _cinquieme(c),
  c.texteSecondaire.withValues(alpha: 0.55),
];

/// Bleu, sauf quand l'accent est déjà bleu (Océan clair) : jaune.
Color _troisieme(OptiColors c) {
  final teinte = HSLColor.fromColor(c.accent).hue;
  if (teinte >= 185 && teinte <= 240) return c.sombre ? const Color(0xFFFACC15) : const Color(0xFFCA8A04);
  return c.sombre ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);
}

/// Turquoise avec Holocron (accent violet), violet avec Forêt (accent vert) : jamais proche de l'accent.
Color _cinquieme(OptiColors c) {
  final accentVert = HSLColor.fromColor(c.accent).hue.clamp(80, 200) == HSLColor.fromColor(c.accent).hue;
  if (accentVert) return c.sombre ? const Color(0xFFC4B5FD) : const Color(0xFF7C3AED);
  return c.sombre ? const Color(0xFF2DD4BF) : const Color(0xFF0F766E);
}

class EcranStatsOnglet extends ConsumerStatefulWidget {
  const EcranStatsOnglet({super.key});

  @override
  ConsumerState<EcranStatsOnglet> createState() => _EcranStatsOngletState();
}

class _EcranStatsOngletState extends ConsumerState<EcranStatsOnglet> {
  String _periode = 'cycle';

  @override
  Widget build(BuildContext context) {
    final donnees = ref.watch(statsProvider(_periode));
    final s = donnees.value ?? ref.read(cacheProvider).stats(_periode);
    return Scaffold(
      body: FondOpti(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(statsProvider(_periode).future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text('Stats', style: context.titre(26)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (cle, libelle) in _periodes)
                      ChoiceChip(
                        label: Text(libelle),
                        selected: _periode == cle,
                        onSelected: (_) => setState(() => _periode = cle),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (s == null)
                  donnees.hasError
                      ? Erreur(
                          message: donnees.error.toString(),
                          reessayer: () => ref.invalidate(statsProvider(_periode)),
                        )
                      : const Padding(
                          padding: EdgeInsets.only(top: 80),
                          child: Center(child: CircularProgressIndicator()),
                        )
                else if (s.cycles.isEmpty)
                  const Carte(child: Text('Pas encore de cycle complet pour cette période.'))
                else ...[
                  _CarteBilan(stats: s),
                  const SizedBox(height: 12),
                  _CarteCategories(stats: s),
                  if (s.cycles.length > 1) ...[const SizedBox(height: 12), _CarteEvolution(stats: s)],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// « Paie du 26/10 · en cours · 6 jours » ou « 6 cycles depuis la paie du 27/05 ».
String _titrePeriode(EcranStats s) {
  if (s.cycles.length == 1) {
    final c = s.cycles.first;
    return 'Paie du ${jourMois(c.debut)}${c.enCours ? ' · en cours' : ''} · ${c.jours} jour${c.jours > 1 ? 's' : ''}';
  }
  return '${s.cycles.length} cycles depuis la paie du ${jourMois(s.cycles.first.debut)}';
}

// ── Bilan ─────────────────────────────────────────────────────────────────────

class _CarteBilan extends StatelessWidget {
  const _CarteBilan({required this.stats});
  final EcranStats stats;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final s = stats;
    final plusieurs = s.cycles.length > 1;
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Etiquette(_titrePeriode(s)),
          const SizedBox(height: 10),
          Text('Dépensé', style: TextStyle(color: c.texteSecondaire)),
          Text(
            euros(s.depense),
            style: chiffres(fontSize: 32, fontWeight: FontWeight.w500, color: c.texte),
          ),
          const SizedBox(height: 12),
          _Ligne(libelle: 'Entré (paie et virements reçus)', valeur: eurosSignes(s.entre), couleur: c.ok),
          _Ligne(
            libelle: s.reste >= 0 ? 'Reste (mis de côté ou sur le compte)' : "Pris sur l'épargne",
            valeur: eurosSignes(s.reste),
            couleur: s.reste >= 0 ? c.ok : c.alerte,
          ),
          if (s.payeParEpargne > 0)
            _Ligne(libelle: 'Payé par ton épargne (projets)', valeur: euros(s.payeParEpargne), couleur: c.accent),
          if (plusieurs && s.moyenne != null)
            _Ligne(libelle: 'Moyenne par cycle terminé', valeur: euros(s.moyenne!), couleur: c.texte),
          const SizedBox(height: 10),
          _JoursSousLimite(sous: s.joursSousLimite, jours: s.jours),
        ],
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({required this.libelle, required this.valeur, required this.couleur});
  final String libelle, valeur;
  final Color couleur;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(libelle, style: TextStyle(color: context.couleurs.texteSecondaire)),
        ),
        const SizedBox(width: 12),
        Text(valeur, style: chiffres(color: couleur)),
      ],
    ),
  );
}

class _JoursSousLimite extends StatelessWidget {
  const _JoursSousLimite({required this.sous, required this.jours});
  final int sous, jours;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final part = jours == 0 ? 0.0 : sous / jours;
    final couleur = part >= 0.7 ? c.ok : (part >= 0.5 ? c.or : c.alerte);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$sous jour${sous > 1 ? 's' : ''} sur $jours',
                style: TextStyle(color: couleur, fontWeight: FontWeight.w600),
              ),
              TextSpan(
                text: ' sous ta limite du jour',
                style: TextStyle(color: c.texteSecondaire),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: part, minHeight: 6, color: couleur, backgroundColor: c.ligne),
        ),
      ],
    );
  }
}

// ── Donut par catégorie ───────────────────────────────────────────────────────

class _CarteCategories extends StatelessWidget {
  const _CarteCategories({required this.stats});
  final EcranStats stats;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final categories = stats.categories;
    if (categories.isEmpty) {
      return const Carte(child: Text('Aucune dépense sur cette période.'));
    }
    final palette = _palette(c);
    Color couleurDe(int i, CategorieStats cat) =>
        cat.nom == 'Le reste' ? palette.last : palette[min(i, palette.length - 2)];
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Etiquette('Par catégorie'),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              width: 180,
              height: 180,
              child: CustomPaint(
                painter: _Donut(
                  parts: [for (final cat in categories) cat.montant],
                  couleurs: [for (final (i, cat) in categories.indexed) couleurDe(i, cat)],
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(euros(stats.depense), style: chiffres(fontSize: 18, fontWeight: FontWeight.w500)),
                      Text('dépensés', style: TextStyle(fontSize: 12, color: c.texteSecondaire)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final (i, cat) in categories.indexed)
            _LigneCategorie(categorie: cat, couleur: couleurDe(i, cat), stats: stats),
          if (stats.cycles.length == 1 && stats.cycles.first.enCours)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Comparé aux ${stats.cycles.first.jours} premiers jours du cycle précédent.',
                style: TextStyle(fontSize: 12, color: c.texteSecondaire),
              ),
            ),
        ],
      ),
    );
  }
}

class _LigneCategorie extends StatelessWidget {
  const _LigneCategorie({required this.categorie, required this.couleur, required this.stats});
  final CategorieStats categorie;
  final Color couleur;
  final EcranStats stats;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final cat = categorie;
    String? evolution;
    Color couleurEvolution = c.texteSecondaire;
    if (cat.nouveau) {
      evolution = 'nouveau';
    } else if (cat.ecart != null) {
      // Dépenser plus : en rouge ; dépenser moins : en vert.
      evolution = '${cat.ecart! > 0 ? '+' : '−'}${cat.pourcent!.abs()} % (${eurosSignes(cat.ecart!)})';
      couleurEvolution = cat.ecart! > 0 ? c.alerte : c.ok;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _ouvrirCategorie(context, stats, cat),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: couleur, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cat.nom, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    [
                      '${cat.part.toStringAsFixed(0)} %',
                      '${cat.nombre} opération${cat.nombre > 1 ? 's' : ''}',
                      if (cat.inclut.isNotEmpty) cat.inclut.join(', '),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.texteSecondaire),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(euros(cat.montant), style: chiffres()),
                if (evolution != null) Text(evolution, style: chiffres(fontSize: 11.5, color: couleurEvolution)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Donut extends CustomPainter {
  _Donut({required this.parts, required this.couleurs});
  final List<double> parts;
  final List<Color> couleurs;

  @override
  void paint(Canvas canvas, Size size) {
    final total = parts.fold(0.0, (a, b) => a + b);
    if (total <= 0) return;
    const epaisseur = 20.0, ecart = 0.03; // petit espace entre les parts (en radians)
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.shortestSide / 2 - epaisseur / 2);
    var angle = -pi / 2;
    for (var i = 0; i < parts.length; i++) {
      final balayage = parts[i] / total * 2 * pi;
      canvas.drawArc(
        rect,
        angle + ecart / 2,
        max(balayage - ecart, 0.01),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = epaisseur
          ..color = couleurs[i],
      );
      angle += balayage;
    }
  }

  @override
  bool shouldRepaint(_Donut ancien) => ancien.parts != parts || ancien.couleurs != couleurs;
}

// ── Évolution (6 ou 12 cycles) ────────────────────────────────────────────────

class _CarteEvolution extends StatelessWidget {
  const _CarteEvolution({required this.stats});
  final EcranStats stats;

  static const _hauteur = 140.0;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final cycles = stats.cycles;
    final plusHaut = cycles.map((x) => x.depense).fold(stats.moyenne ?? 0, max);
    double hauteur(double v) => plusHaut <= 0 ? 0 : _hauteur * v / plusHaut;
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Etiquette('Dépensé par cycle'),
          const SizedBox(height: 16),
          SizedBox(
            height: _hauteur + 18,
            child: Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final cy in cycles)
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              cy.depense.round().toString(),
                              style: chiffres(fontSize: 10, color: c.texteSecondaire),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: hauteur(cy.depense),
                              margin: const EdgeInsets.symmetric(horizontal: 5),
                              decoration: BoxDecoration(
                                color: cy.enCours ? c.texteSecondaire.withValues(alpha: 0.35) : c.accent,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (stats.moyenne != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: hauteur(stats.moyenne!),
                    child: Container(height: 1.5, color: c.or),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final cy in cycles)
                Expanded(
                  child: Text(
                    cy.enCours ? 'en cours' : jourMois(cy.debut),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10.5, color: c.texteSecondaire),
                  ),
                ),
            ],
          ),
          if (stats.moyenne != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Container(width: 14, height: 1.5, color: c.or),
                const SizedBox(width: 8),
                Text(
                  'Moyenne des cycles terminés : ${euros(stats.moyenne!)}',
                  style: TextStyle(fontSize: 12, color: c.texteSecondaire),
                ),
              ],
            ),
          ],
          if (stats.periode == '12' && cycles.length < 12)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(LucideIcons.info, size: 14, color: c.texteSecondaire),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Données complètes depuis la paie du ${jourMois(cycles.first.debut)} : ${cycles.length} cycles disponibles.',
                      style: TextStyle(fontSize: 12, color: c.texteSecondaire),
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

// ── Opérations d'une catégorie ────────────────────────────────────────────────

void _ouvrirCategorie(BuildContext context, EcranStats stats, CategorieStats categorie) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _EcranCategorie(stats: stats, categorie: categorie),
    ),
  );
}

class _EcranCategorie extends ConsumerStatefulWidget {
  const _EcranCategorie({required this.stats, required this.categorie});
  final EcranStats stats;
  final CategorieStats categorie;

  @override
  ConsumerState<_EcranCategorie> createState() => _EcranCategorieState();
}

class _EcranCategorieState extends ConsumerState<_EcranCategorie> {
  late Future<List<Operation>> _operations = _charger();

  Future<List<Operation>> _charger() => ref
      .read(apiProvider)
      .operationsCategorie(widget.stats.cycles.first.debut, widget.stats.cycles.last.fin, widget.categorie.categories);

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final cat = widget.categorie;
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text(cat.nom)),
      body: FutureBuilder<List<Operation>>(
        future: _operations,
        builder: (context, instantane) {
          if (instantane.hasError) {
            return Erreur(
              message: instantane.error.toString(),
              reessayer: () => setState(() => _operations = _charger()),
            );
          }
          final operations = instantane.data;
          if (operations == null) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
            children: [
              Text(
                '${_titrePeriode(widget.stats)} · ${euros(cat.montant)} · '
                '${operations.length} opération${operations.length > 1 ? 's' : ''}',
                style: TextStyle(color: c.texteSecondaire),
              ),
              const SizedBox(height: 4),
              Text(
                "Touche une dépense pour changer sa catégorie, ou la rattacher à un projet payé avec ton épargne.",
                style: TextStyle(fontSize: 12, color: c.texteSecondaire),
              ),
              const SizedBox(height: 12),
              Carte(
                child: Column(
                  children: [
                    for (final o in operations)
                      LigneOperation(
                        operation: o,
                        onTap: o.montant < 0
                            ? () async {
                                await toucherDepense(context, ref, o);
                                ref.invalidate(statsProvider);
                                setState(() => _operations = _charger());
                              }
                            : null,
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
