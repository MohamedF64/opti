part of '../abonnements.dart';

// Formulaire d'ajout et de modification.

// ── Formulaire ────────────────────────────────────────────────────────────────

/// Ajout (abonnement null) ou modification.
/// `essai` : nouvel essai gratuit (prix après l'essai et date de fin).
Future<void> ouvrirFormulaireAbonnement(
  BuildContext context,
  WidgetRef ref, {
  Abonnement? abonnement,
  bool essai = false,
}) async {
  final valeurs = await showModalBottomSheet<Map<String, Object?>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.couleurs.fond,
    builder: (_) => _FormulaireAbonnement(abonnement: abonnement, essai: essai),
  );
  if (valeurs == null || valeurs.isEmpty || !context.mounted) return;
  await _agir(context, ref, (api) {
    if (abonnement == null) {
      return api.creerAbonnement(
        nom: valeurs['nom'] as String,
        montant: valeurs['montant'] as double,
        frequence: valeurs['frequence'] as String,
        categorie: valeurs['categorie'] as String?,
        libelle: valeurs['libelle'] as String?,
        essaiJusquAu: valeurs['essai_jusqu_au'] as DateTime?,
      );
    }
    return api.modifierAbonnement(abonnement.id, valeurs);
  });
}

class _FormulaireAbonnement extends StatefulWidget {
  const _FormulaireAbonnement({this.abonnement, this.essai = false});
  final Abonnement? abonnement;
  final bool essai;

  @override
  State<_FormulaireAbonnement> createState() => _FormulaireAbonnementState();
}

class _FormulaireAbonnementState extends State<_FormulaireAbonnement> {
  late final _nom = TextEditingController(text: widget.abonnement?.nom ?? '');
  late final _montant = TextEditingController(
    text: widget.abonnement == null ? '' : widget.abonnement!.montant.toStringAsFixed(2).replaceAll('.', ','),
  );
  late final _maximum = TextEditingController(
    text: widget.abonnement?.prixMaximum?.toStringAsFixed(2).replaceAll('.', ',') ?? '',
  );
  late final _categorie = TextEditingController(text: widget.abonnement?.categorie ?? '');
  late final _libelle = TextEditingController(text: widget.abonnement?.libelles.join(', ') ?? '');
  late String _frequence = widget.abonnement?.frequence ?? 'mensuel';
  late final Set<int> _pause = {...?widget.abonnement?.moisPause};
  DateTime? _finEssai;
  String? _erreur;

  Future<void> _choisirFinEssai() async {
    final aujourdhui = DateUtils.dateOnly(DateTime.now());
    final choix = await showDatePicker(
      context: context,
      initialDate: _finEssai ?? aujourdhui.add(const Duration(days: 30)),
      firstDate: aujourdhui,
      lastDate: aujourdhui.add(const Duration(days: 366)),
      helpText: "Fin de l'essai",
    );
    if (choix != null) setState(() => _finEssai = choix);
  }

  @override
  void dispose() {
    for (final c in [_nom, _montant, _maximum, _categorie, _libelle]) {
      c.dispose();
    }
    super.dispose();
  }

  void _valider() {
    final a = widget.abonnement;
    final montant = lireMontant(_montant.text);
    if (_nom.text.trim().isEmpty) return setState(() => _erreur = 'Donne un nom à cet abonnement.');
    if (montant == null || montant <= 0) return setState(() => _erreur = 'Indique le montant.');
    if (widget.essai && _finEssai == null) return setState(() => _erreur = "Choisis la date de fin de l'essai.");
    final maximum = _maximum.text.trim().isEmpty ? null : lireMontant(_maximum.text);
    if (_maximum.text.trim().isNotEmpty && (maximum == null || maximum <= 0)) {
      return setState(() => _erreur = 'Le prix maximum est illisible.');
    }
    if (maximum != null && maximum < montant - 0.005) {
      return setState(() => _erreur = 'Le maximum doit être au moins égal au montant (${euros(montant)}).');
    }
    final libelles = [
      for (final l in _libelle.text.split(','))
        if (l.trim().isNotEmpty) l.trim(),
    ];
    if (a == null) {
      Navigator.pop(context, {
        'nom': _nom.text.trim(),
        'montant': montant,
        'frequence': _frequence,
        'categorie': _categorie.text.trim().isEmpty ? null : _categorie.text.trim(),
        'libelle': libelles.firstOrNull,
        if (widget.essai) 'essai_jusqu_au': _finEssai,
      });
      return;
    }
    // Seul ce qui a changé part au serveur (un montant saisi devient « corrigé à la main »).
    Navigator.pop(context, {
      if (_nom.text.trim() != a.nom) 'nom': _nom.text.trim(),
      if ((montant - a.montant).abs() >= 0.005) 'montant': montant,
      if (maximum != a.prixMaximum) 'prix_maximum': maximum,
      if (_frequence != a.frequence) 'frequence': _frequence,
      if (_categorie.text.trim() != (a.categorie ?? '') && _categorie.text.trim().isNotEmpty)
        'categorie': _categorie.text.trim(),
      if (libelles.join(',') != a.libelles.join(',')) 'libelles': libelles,
      if (!_pause.containsAll(a.moisPause) || !a.moisPause.toSet().containsAll(_pause))
        'mois_pause': (_pause.toList()..sort()),
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final a = widget.abonnement;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              a != null ? 'Modifier' : (widget.essai ? 'Nouvel essai gratuit' : 'Nouvel abonnement'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nom,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Nom (ex. Netflix)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _montant,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: chiffres(),
              decoration: InputDecoration(
                labelText: widget.essai ? "Prix après l'essai" : 'Montant',
                // Un montant tapé devient fixe : le prix variable (moyenne des 3 derniers) disparaît.
                helperText: a != null && a.variable && !a.montantManuel
                    ? 'Moyenne de tes 3 derniers prélèvements. Le modifier le rend fixe.'
                    : null,
                helperMaxLines: 2,
                suffixText: '€',
                border: const OutlineInputBorder(),
              ),
            ),
            if (widget.essai) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _choisirFinEssai,
                icon: const Icon(LucideIcons.calendar, size: 18),
                label: Text(_finEssai == null ? "Fin de l'essai" : "Fin de l'essai : ${jourMois(_finEssai!)}"),
              ),
            ],
            if (a != null && !widget.essai) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _maximum,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: chiffres(),
                decoration: const InputDecoration(
                  labelText: 'Prix maximum (facultatif)',
                  helperText: 'Ce que le contrat peut coûter au plus (paliers, hors-forfait)',
                  suffixText: '€',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (a != null && a.montantManuel)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, {'montant_auto': true}),
                  child: const Text('Revenir au montant calculé sur les prélèvements'),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final (cle, libelle) in _frequences)
                  ChoiceChip(
                    label: Text(libelle),
                    selected: _frequence == cle,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _frequence = cle),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _categorie,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'Catégorie (ex. Streaming)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _libelle,
              decoration: const InputDecoration(
                labelText: 'Libellé sur le relevé (facultatif)',
                helperText: 'Plusieurs libellés : sépare-les par des virgules',
                border: OutlineInputBorder(),
              ),
            ),
            if (a != null && _frequence == 'mensuel') ...[
              const SizedBox(height: 14),
              const Etiquette('Mois sans prélèvement'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var m = 1; m <= 12; m++)
                    FilterChip(
                      label: Text(_moisCourts[m - 1]),
                      selected: _pause.contains(m),
                      showCheckmark: false,
                      onSelected: (oui) => setState(() => oui ? _pause.add(m) : _pause.remove(m)),
                    ),
                ],
              ),
            ],
            if (_erreur != null) ...[const SizedBox(height: 10), Text(_erreur!, style: TextStyle(color: c.alerte))],
            const SizedBox(height: 16),
            FilledButton(onPressed: _valider, child: Text(a == null ? 'Ajouter' : 'Enregistrer')),
          ],
        ),
      ),
    );
  }
}
