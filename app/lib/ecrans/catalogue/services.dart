part of '../catalogue.dart';

// Catalogue des services, page de prix modifiée, profil.

// ── Catalogue ─────────────────────────────────────────────────────────────────

class _CarteService extends StatelessWidget {
  const _CarteService({required this.service, this.offres, this.ouvert = false});
  final ServiceCatalogue service;
  final List<Offre>? offres; // résultat d'une recherche : seulement les offres trouvées
  final bool ouvert;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final s = service;
    final offres = this.offres ?? s.offres;
    final verifie = s.offres.isEmpty ? null : s.offres.map((o) => o.verifieLe).reduce((a, b) => a.isBefore(b) ? a : b);
    final suivi = s.suiviManuel
        ? 'Suivi manuel${verifie != null ? ' · vérifié le ${jourMois(verifie)}/${verifie.year}' : ''}'
        : 'Page surveillée chaque mois${s.pageLueLe != null ? ' · lue le ${jourMois(s.pageLueLe!.toLocal())}' : ''}';
    return Carte(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: ouvert,
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Text(s.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${offres.length} offre${offres.length > 1 ? 's' : ''} · $suivi',
            style: TextStyle(fontSize: 12, color: c.texteSecondaire),
          ),
          children: [
            for (final o in offres) ...[
              const Divider(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(o.nom)),
                  const SizedBox(width: 8),
                  Text(prixOffre(o), style: chiffres(fontSize: 13)),
                  _BoutonVerifier(offre: o),
                ],
              ),
              if (o.go != null || o.inclut.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    [
                      if (o.go != null) '${o.go} Go',
                      if (o.inclut.isNotEmpty) 'inclut ${o.inclut.join(', ')}',
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: c.texteSecondaire),
                  ),
                ),
              const SizedBox(height: 6),
              _Badges(offre: o, verification: true),
            ],
            if (s.pageUrl != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _ouvrirPage(context, s.pageUrl),
                  icon: const Icon(LucideIcons.externalLink, size: 16),
                  label: const Text('Page officielle'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BoutonVerifier extends ConsumerWidget {
  const _BoutonVerifier({required this.offre});
  final Offre offre;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    tooltip: 'Vérifier ce prix',
    visualDensity: VisualDensity.compact,
    onPressed: () => _verifier(context, ref),
    icon: Icon(LucideIcons.calendarCheck, size: 16, color: offre.aReverifier ? context.couleurs.or : null),
  );

  Future<void> _verifier(BuildContext context, WidgetRef ref) async {
    final o = offre;
    final champ = TextEditingController(text: o.prix.toStringAsFixed(2).replaceAll('.', ','));
    // null : annulé ; (prix: null) : toujours le même prix.
    final choix = await showDialog<({double? prix})>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(o.nom),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Vérifié le ${jourMois(o.verifieLe)}/${o.verifieLe.year}. Regarde la page officielle, puis confirme '
              'le prix ou corrige-le.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: champ,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: chiffres(),
              decoration: InputDecoration(
                labelText: switch (o.frequence) {
                  'annuel' => 'Prix par an',
                  'hebdomadaire' => 'Prix par semaine',
                  'quatre_semaines' => 'Prix pour 4 semaines',
                  _ => 'Prix par mois',
                },
                suffixText: '€',
                border: const OutlineInputBorder(),
              ),
            ),
            if (o.sourceUrl != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _ouvrirPage(context, o.sourceUrl),
                  icon: const Icon(LucideIcons.externalLink, size: 16),
                  label: const Text('Page officielle'),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final prix = lireMontant(champ.text);
              if (prix == null || prix < 0) return;
              Navigator.pop(context, (prix: (prix - o.prix).abs() < 0.005 ? null : prix));
            },
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    champ.dispose();
    if (choix == null || !context.mounted) return;
    if (await _agir(context, ref, (api) => api.verifierOffre(o.id, choix.prix)) && context.mounted) {
      signaler(context, choix.prix == null ? 'Prix confirmé.' : 'Nouveau prix enregistré.');
    }
  }
}

// ── Page de prix modifiée ─────────────────────────────────────────────────────

/// « Une page de prix a changé » : les montants apparus et disparus, et pour chaque offre le nouveau prix
/// en un toucher (ou « Rien ne change »).
class _CartePageModifiee extends ConsumerStatefulWidget {
  const _CartePageModifiee({required this.service});
  final ServiceCatalogue service;

  @override
  ConsumerState<_CartePageModifiee> createState() => _CartePageModifieeState();
}

class _CartePageModifieeState extends ConsumerState<_CartePageModifiee> {
  final Map<String, double> _nouveaux = {};
  bool _envoi = false;

  Future<void> _valider() async {
    setState(() => _envoi = true);
    final ok = await _agir(context, ref, (api) => api.validerPage(widget.service.id, _nouveaux));
    if (ok && mounted) signaler(context, _nouveaux.isEmpty ? 'Prix confirmés.' : 'Nouveaux prix enregistrés.');
    if (mounted) setState(() => _envoi = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final s = widget.service;
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.circleAlert, color: c.or, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'La page ${s.nom} a changé'
                  '${s.pageModifieeLe != null ? ' (${jourMois(s.pageModifieeLe!.toLocal())})' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (s.montantsApparus.isNotEmpty)
            Text(
              'Nouveaux montants : ${s.montantsApparus.map(eurosCourts).join(' · ')}',
              style: chiffres(fontSize: 13),
            ),
          if (s.montantsDisparus.isNotEmpty)
            Text(
              'Disparus : ${s.montantsDisparus.map(eurosCourts).join(' · ')}',
              style: chiffres(fontSize: 13, color: c.texteSecondaire),
            ),
          const SizedBox(height: 8),
          Text(
            'Ouvre la page, puis touche le nouveau prix de chaque offre qui a changé.',
            style: TextStyle(fontSize: 12, color: c.texteSecondaire),
          ),
          for (final o in s.offres) ...[
            const SizedBox(height: 10),
            Text('${o.nom} · ${prixOffre(o)}'),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('Inchangé'),
                  selected: !_nouveaux.containsKey(o.id),
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _nouveaux.remove(o.id)),
                ),
                for (final m in s.montantsApparus)
                  ChoiceChip(
                    label: Text(eurosCourts(m), style: chiffres(fontSize: 13)),
                    selected: _nouveaux[o.id] == m,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _nouveaux[o.id] = m),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _ouvrirPage(context, s.pageUrl),
                icon: const Icon(LucideIcons.externalLink, size: 16),
                label: const Text('Voir la page'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _envoi ? null : _valider,
                child: Text(_nouveaux.isEmpty ? 'Rien ne change' : 'Enregistrer'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Profil ────────────────────────────────────────────────────────────────────

class _CarteProfil extends ConsumerStatefulWidget {
  const _CarteProfil({required this.profil});
  final Map<String, bool> profil;

  @override
  ConsumerState<_CarteProfil> createState() => _CarteProfilState();
}

class _CarteProfilState extends ConsumerState<_CarteProfil> {
  final Map<String, bool> _local = {};

  Future<void> _basculer(String cle, bool oui) async {
    setState(() => _local[cle] = oui);
    final ok = await _agir(context, ref, (api) => api.modifierProfil({cle: oui}));
    if (!ok && mounted) setState(() => _local.remove(cle));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final MapEntry(key: cle, value: libelle) in const {
            'etudiant': 'Statut étudiant',
            'moins_26': 'Moins de 26 ans',
            'age_18_24': 'Entre 18 et 24 ans',
          }.entries)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(libelle),
              value: _local[cle] ?? widget.profil[cle] ?? false,
              onChanged: (oui) => _basculer(cle, oui),
            ),
          Text(
            'Sert seulement à savoir quelles offres te sont accessibles (Prime étudiant…). '
            'Rien de ce profil ne sort d\'Opti.',
            style: TextStyle(fontSize: 12, color: c.texteSecondaire),
          ),
        ],
      ),
    );
  }
}
