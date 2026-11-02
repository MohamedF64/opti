part of '../catalogue.dart';

// Rattachement : les lignes d'un abonnement.

// ── Rattachement : les lignes d'un abonnement ────────────────────────────────

/// Rattacher un abonnement à une ou plusieurs offres du catalogue (Prixtel : 2 lignes, un seul prélèvement).
Future<void> ouvrirLignes(
  BuildContext context,
  WidgetRef ref,
  AbonnementCatalogue abonnement,
  DonneesCatalogue ecran, {
  String? serviceId,
}) async {
  final lignes = await showModalBottomSheet<List<Map<String, Object?>>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.couleurs.fond,
    builder: (_) => _FormulaireLignes(abonnement: abonnement, ecran: ecran, serviceId: serviceId),
  );
  if (lignes == null || !context.mounted) return;
  await _agir(context, ref, (api) => api.changerLignes(abonnement.id, lignes));
}

class _LigneSaisie {
  _LigneSaisie({required String nom, this.offreId, double? prix, int? go})
    : nom = TextEditingController(text: nom),
      prix = TextEditingController(text: prix == null ? '' : prix.toStringAsFixed(2).replaceAll('.', ',')),
      go = TextEditingController(text: go?.toString() ?? '');

  final TextEditingController nom, prix, go;
  String? offreId;

  void liberer() {
    nom.dispose();
    prix.dispose();
    go.dispose();
  }
}

class _FormulaireLignes extends StatefulWidget {
  const _FormulaireLignes({required this.abonnement, required this.ecran, this.serviceId});
  final AbonnementCatalogue abonnement;
  final DonneesCatalogue ecran;
  final String? serviceId;

  @override
  State<_FormulaireLignes> createState() => _FormulaireLignesState();
}

class _FormulaireLignesState extends State<_FormulaireLignes> {
  late String? _serviceId = widget.serviceId ?? widget.ecran.serviceDe(widget.abonnement.lignes.firstOrNull?.offre)?.id;
  late final List<_LigneSaisie> _lignes = widget.abonnement.lignes.isEmpty
      ? [_LigneSaisie(nom: 'Ligne 1')]
      : [
          for (final l in widget.abonnement.lignes)
            _LigneSaisie(nom: l.nom, offreId: l.offre?.id, prix: l.prixSaisi, go: l.goSaisi),
        ];
  String? _erreur;

  ServiceCatalogue? get _service => widget.ecran.services.where((s) => s.id == _serviceId).firstOrNull;

  @override
  void dispose() {
    for (final l in _lignes) {
      l.liberer();
    }
    super.dispose();
  }

  void _valider() {
    if (_service == null) return setState(() => _erreur = 'Choisis le service.');
    final resultat = <Map<String, Object?>>[];
    for (final l in _lignes) {
      final prix = l.prix.text.trim().isEmpty ? null : lireMontant(l.prix.text);
      final go = l.go.text.trim().isEmpty ? null : int.tryParse(l.go.text.trim());
      if (l.nom.text.trim().isEmpty) return setState(() => _erreur = 'Donne un nom à chaque ligne.');
      if (l.offreId == null) return setState(() => _erreur = 'Choisis une offre pour « ${l.nom.text.trim()} ».');
      if (l.prix.text.trim().isNotEmpty && (prix == null || prix < 0)) {
        return setState(() => _erreur = 'Prix illisible pour « ${l.nom.text.trim()} ».');
      }
      if (l.go.text.trim().isNotEmpty && go == null) {
        return setState(() => _erreur = 'Go illisibles pour « ${l.nom.text.trim()} ».');
      }
      resultat.add({'nom': l.nom.text.trim(), 'offre_id': l.offreId, 'prix': prix, 'go': go});
    }
    Navigator.pop(context, resultat);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final service = _service;
    final plusieurs = _lignes.length > 1;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.abonnement.nom, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              '${euros(widget.abonnement.parMois)}/mois en moyenne',
              style: chiffres(fontSize: 13, color: c.texteSecondaire),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in widget.ecran.services)
                  ChoiceChip(
                    label: Text(s.nom),
                    selected: s.id == _serviceId,
                    showCheckmark: false,
                    onSelected: (_) => setState(() {
                      _serviceId = s.id;
                      for (final l in _lignes) {
                        l.offreId = null;
                      }
                    }),
                  ),
              ],
            ),
            if (service != null)
              for (final (i, l) in _lignes.indexed) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: l.nom,
                        maxLength: 40,
                        decoration: const InputDecoration(
                          labelText: 'Nom de la ligne (ex. Téléphone, Box 4G)',
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                      ),
                    ),
                    if (plusieurs)
                      IconButton(
                        tooltip: 'Retirer cette ligne',
                        onPressed: () => setState(() => _lignes.removeAt(i).liberer()),
                        icon: const Icon(LucideIcons.trash2, size: 18),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: service.offres.any((o) => o.id == l.offreId) ? l.offreId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Offre', border: OutlineInputBorder()),
                  items: [
                    for (final o in service.offres)
                      DropdownMenuItem(
                        value: o.id,
                        child: Text('${o.nom} · ${prixOffre(o)}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (id) => setState(() => l.offreId = id),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: l.prix,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: chiffres(),
                        decoration: InputDecoration(
                          labelText: plusieurs ? 'Ce que tu paies' : 'Prix (facultatif)',
                          suffixText: '€/mois',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    if (service.mobile) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: l.go,
                          keyboardType: TextInputType.number,
                          style: chiffres(),
                          decoration: const InputDecoration(
                            labelText: 'Go',
                            suffixText: 'Go',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            if (service != null) ...[
              const SizedBox(height: 8),
              Text(
                plusieurs
                    ? 'Plusieurs lignes, un seul prélèvement : indique ce que coûte chaque ligne en moyenne.'
                    : 'Laisse le prix vide : Opti prend ce que tu paies vraiment.'
                          '${service.mobile ? ' Les Go servent à comparer avec les autres opérateurs.' : ''}',
                style: TextStyle(fontSize: 12, color: c.texteSecondaire),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _lignes.add(_LigneSaisie(nom: 'Ligne ${_lignes.length + 1}'))),
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const Text('Ajouter une ligne'),
                ),
              ),
            ],
            if (_erreur != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_erreur!, style: TextStyle(color: c.alerte)),
              ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _valider, child: const Text('Enregistrer')),
            if (widget.abonnement.rattache)
              TextButton.icon(
                onPressed: () => Navigator.pop(context, <Map<String, Object?>>[]),
                icon: const Icon(LucideIcons.unlink, size: 16),
                label: const Text('Détacher du catalogue'),
              ),
          ],
        ),
      ),
    );
  }
}
