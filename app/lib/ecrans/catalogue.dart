/// Catalogue de prix (règles : docs/regles-de-calcul.md § 12 du backend) : abonnements rattachés à une offre et
/// leurs offres moins chères, offres groupées « à étudier », catalogue daté et sourcé, profil.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/api.dart';
import '../data/catalogue.dart';
import '../theme/opti_theme.dart';
import '../util/format.dart';
import '../widgets/communs.dart';

part 'catalogue/rattaches.dart';
part 'catalogue/services.dart';
part 'catalogue/lignes.dart';

Future<bool> _agir(BuildContext context, WidgetRef ref, Future<void> Function(OptiApi api) action) async {
  try {
    await action(ref.read(apiProvider));
    ref.invalidate(catalogueProvider);
    return true;
  } catch (e) {
    if (context.mounted) signaler(context, e);
    return false;
  }
}

Future<void> _ouvrirPage(BuildContext context, String? url) async {
  if (url == null || !await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
    if (context.mounted) signaler(context, "Impossible d'ouvrir la page.");
  }
}

/// « 13,99 €/mois », « 34,95 €/an (2,91 €/mois) ».
String prixOffre(Offre o) => switch (o.frequence) {
  'annuel' => '${euros(o.prix)}/an (${euros(o.parMois)}/mois)',
  'hebdomadaire' => '${euros(o.prix)}/semaine (${euros(o.parMois)}/mois)',
  'quatre_semaines' => '${euros(o.prix)}/4 semaines (${euros(o.parMois)}/mois)',
  _ => '${euros(o.prix)}/mois',
};

class EcranCatalogue extends ConsumerStatefulWidget {
  const EcranCatalogue({super.key});

  @override
  ConsumerState<EcranCatalogue> createState() => _EcranCatalogueState();
}

class _EcranCatalogueState extends ConsumerState<EcranCatalogue> {
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
    final donnees = ref.watch(catalogueProvider);
    final d = donnees.value;
    final trouves = d == null || _recherche.isEmpty ? null : d.chercher(_recherche);
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Catalogue de prix')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(catalogueProvider.future),
        child: d == null
            ? (donnees.hasError
                  ? Erreur(message: donnees.error.toString(), reessayer: () => ref.invalidate(catalogueProvider))
                  : const Center(child: CircularProgressIndicator()))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                children: [
                  TextField(
                    controller: _champ,
                    textInputAction: TextInputAction.search,
                    onChanged: (v) => setState(() => _recherche = v.trim()),
                    decoration: InputDecoration(
                      hintText: 'Chercher (Prime, Sosh, 5G…)',
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
                  const SizedBox(height: 16),
                  if (trouves != null) ...[
                    Etiquette('${trouves.length} résultat${trouves.length > 1 ? 's' : ''}'),
                    const SizedBox(height: 8),
                    if (trouves.isEmpty)
                      Text('Aucune offre ne correspond.', style: TextStyle(color: c.texteSecondaire))
                    else
                      for (final (s, offres) in trouves) ...[
                        _CarteService(service: s, offres: offres, ouvert: true),
                        const SizedBox(height: 10),
                      ],
                  ] else ...[
                    for (final s in d.services.where((s) => s.modifiee)) ...[
                      _CartePageModifiee(service: s),
                      const SizedBox(height: 12),
                    ],
                    ..._sectionAbonnements(context, ref, d),
                    if (d.groupees.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Etiquette('Offres groupées à étudier'),
                      const SizedBox(height: 8),
                      for (final g in d.groupees) ...[_CarteGroupee(groupee: g), const SizedBox(height: 10)],
                      Text(
                        "Une offre groupée n'est jamais conseillée : à toi de voir si ce qu'elle apporte vaut l'écart.",
                        style: TextStyle(fontSize: 12, color: c.texteSecondaire),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Etiquette('Le catalogue'),
                    const SizedBox(height: 8),
                    for (final s in d.services) ...[_CarteService(service: s), const SizedBox(height: 10)],
                    Text(
                      'Prix publics, identiques pour tout le monde. Une offre vérifiée il y a plus de 12 mois '
                      "est marquée « à revérifier » et n'est plus proposée.",
                      style: TextStyle(fontSize: 12, color: c.texteSecondaire),
                    ),
                    const SizedBox(height: 20),
                    const Etiquette('Ton profil'),
                    const SizedBox(height: 8),
                    _CarteProfil(profil: d.profil),
                  ],
                ],
              ),
      ),
    );
  }

  List<Widget> _sectionAbonnements(BuildContext context, WidgetRef ref, DonneesCatalogue d) {
    final c = context.couleurs;
    final rattaches = d.abonnements.where((a) => a.rattache).toList();
    final proposes = d.abonnements.where((a) => !a.rattache && a.serviceProposeId != null).toList();
    final autres = d.abonnements.where((a) => !a.rattache && a.serviceProposeId == null).toList();
    return [
      const Etiquette('Tes abonnements'),
      const SizedBox(height: 8),
      for (final a in rattaches) ...[_CarteRattache(abonnement: a, ecran: d), const SizedBox(height: 10)],
      for (final a in proposes) ...[
        Carte(
          child: Row(
            children: [
              Icon(LucideIcons.link, color: c.accent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: a.nom,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: ' ressemble à ${d.services.firstWhere((s) => s.id == a.serviceProposeId).nom}.'),
                    ],
                  ),
                ),
              ),
              TextButton(
                onPressed: () => ouvrirLignes(context, ref, a, d, serviceId: a.serviceProposeId),
                child: const Text('Rattacher'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
      if (rattaches.isEmpty && proposes.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Aucun abonnement rattaché : rattache-en un pour voir les offres moins chères.',
            style: TextStyle(color: c.texteSecondaire),
          ),
        ),
      if (autres.isNotEmpty)
        Carte(
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text('Autres abonnements (${autres.length})'),
              subtitle: Text(
                'Sans équivalent proposé dans le catalogue',
                style: TextStyle(fontSize: 12, color: c.texteSecondaire),
              ),
              children: [
                for (final a in autres)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(a.nom),
                    subtitle: Text('${euros(a.parMois)}/mois', style: chiffres(fontSize: 12)),
                    trailing: TextButton(
                      onPressed: () => ouvrirLignes(context, ref, a, d),
                      child: const Text('Rattacher'),
                    ),
                  ),
              ],
            ),
          ),
        ),
    ];
  }
}
