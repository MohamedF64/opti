part of '../objectifs.dart';

// Feuilles d'action : verser, piocher, confirmer, formulaire d'objectif.

// ── Feuilles d'action ─────────────────────────────────────────────────────────

Future<void> _ouvrirMouvement(BuildContext context, WidgetRef ref, Objectif o, {required bool piocher}) async {
  final resultat = await showModalBottomSheet<(double, String)>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.couleurs.fond,
    builder: (_) => _FeuilleMontant(objectif: o, piocher: piocher),
  );
  if (resultat == null || !context.mounted) return;
  final (montant, note) = resultat;
  await _agir(
    context,
    ref,
    (api) => api.declarerMouvement(o.id, piocher ? -montant : montant, note: note.isEmpty ? null : note),
  );
}

class _FeuilleMontant extends StatefulWidget {
  const _FeuilleMontant({required this.objectif, required this.piocher});
  final Objectif objectif;
  final bool piocher;

  @override
  State<_FeuilleMontant> createState() => _FeuilleMontantState();
}

class _FeuilleMontantState extends State<_FeuilleMontant> {
  final _montant = TextEditingController();
  final _note = TextEditingController();
  String? _erreur;

  @override
  void dispose() {
    _montant.dispose();
    _note.dispose();
    super.dispose();
  }

  void _valider() {
    final montant = lireMontant(_montant.text);
    if (montant == null || montant <= 0) {
      setState(() => _erreur = 'Indique un montant.');
      return;
    }
    if (widget.piocher && montant > widget.objectif.disponible + 0.001) {
      setState(() => _erreur = 'Il n\'y a que ${euros(widget.objectif.disponible)} disponibles.');
      return;
    }
    Navigator.pop(context, (montant, _note.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final o = widget.objectif;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.piocher ? 'Piocher dans ${o.nom}' : 'Mettre de côté pour ${o.nom}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _montant,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: chiffres(fontSize: 22),
            decoration: InputDecoration(
              labelText: 'Montant',
              suffixText: '€',
              errorText: _erreur,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _valider(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Note (facultatif)', border: OutlineInputBorder()),
          ),
          Text(
            widget.piocher
                ? 'Ensuite, fais le virement depuis ta réserve « Économies » sur Revolut : Opti le reconnaîtra tout seul.'
                : 'Ensuite, fais le virement vers ta réserve « Économies » sur Revolut : Opti le reconnaîtra tout seul.',
            style: TextStyle(color: c.texteSecondaire, fontSize: 13),
          ),
          const SizedBox(height: 14),
          FilledButton(onPressed: _valider, child: Text(widget.piocher ? 'Piocher' : 'Mettre de côté')),
        ],
      ),
    );
  }
}

Future<void> _confirmerALaMain(BuildContext context, WidgetRef ref, MouvementObjectif m) async {
  // Les mouvements de la réserve du même sens, pour indiquer lequel correspond.
  final candidates = (ref.read(objectifsProvider).value?.aAttribuer ?? [])
      .where((t) => (t.montant > 0) == (m.montant > 0))
      .toList();
  final choix = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    backgroundColor: context.couleurs.fond,
    builder: (contexte) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Quel virement de ${euros(m.montant.abs())} ?',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final t in candidates)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.piggyBank),
                title: Text('${eurosSignes(t.montant)} le ${jourMois(t.date)}'),
                subtitle: Text(t.libelle, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(contexte, t.id),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.pop(contexte, ''),
              child: const Text('Je ne le vois pas encore : confirmer quand même'),
            ),
          ],
        ),
      ),
    ),
  );
  if (choix == null || !context.mounted) return;
  await _agir(context, ref, (api) => api.confirmer(m.id, operationId: choix.isEmpty ? null : choix));
}

Future<DateTime?> _choisirDate(BuildContext context, DateTime? initiale) {
  final demain = DateTime.now().add(const Duration(days: 1));
  return showDatePicker(
    context: context,
    initialDate: initiale != null && initiale.isAfter(demain) ? initiale : demain,
    firstDate: demain,
    lastDate: DateTime(demain.year + 10),
  );
}

/// Création (objectif null) ou modification d'un objectif.
Future<void> ouvrirFormulaireObjectif(BuildContext context, WidgetRef ref, {Objectif? objectif}) async {
  final resultat = await showModalBottomSheet<Map<String, Object?>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.couleurs.fond,
    builder: (_) => _FormulaireObjectif(objectif: objectif),
  );
  if (resultat == null || !context.mounted) return;
  await _agir(context, ref, (api) {
    if (objectif == null) {
      return api.creerObjectif(
        nom: resultat['nom'] as String,
        cible: resultat['cible'] as double,
        echeance: resultat['echeance'] as DateTime?,
        icone: resultat['icone'] as String?,
      );
    }
    return api.modifierObjectif(objectif.id, resultat);
  });
}

class _FormulaireObjectif extends StatefulWidget {
  const _FormulaireObjectif({this.objectif});
  final Objectif? objectif;

  @override
  State<_FormulaireObjectif> createState() => _FormulaireObjectifState();
}

class _FormulaireObjectifState extends State<_FormulaireObjectif> {
  late final _nom = TextEditingController(text: widget.objectif?.nom ?? '');
  late final _cible = TextEditingController(
    text: widget.objectif == null ? '' : widget.objectif!.cible.toStringAsFixed(2).replaceAll('.', ','),
  );
  late DateTime? _echeance = widget.objectif?.echeance;
  late String? _icone = widget.objectif?.icone ?? 'piggy-bank';
  String? _erreur;

  bool get _imprevus => widget.objectif?.imprevus ?? false;

  @override
  void dispose() {
    _nom.dispose();
    _cible.dispose();
    super.dispose();
  }

  void _valider() {
    final cible = lireMontant(_cible.text);
    if (_nom.text.trim().isEmpty) return setState(() => _erreur = 'Donne un nom à ton objectif.');
    if (cible == null || cible <= 0) return setState(() => _erreur = 'Indique le montant à atteindre.');
    final valeurs = <String, Object?>{'nom': _nom.text.trim(), 'cible': cible, 'icone': _icone};
    if (!_imprevus) valeurs['echeance'] = _echeance;
    Navigator.pop(context, valeurs);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.objectif == null ? 'Nouvel objectif' : 'Modifier',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nom,
              maxLength: 60,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nom (ex. Permis, Voyage)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _cible,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: chiffres(),
              decoration: const InputDecoration(
                labelText: 'Montant à atteindre',
                suffixText: '€',
                border: OutlineInputBorder(),
              ),
            ),
            if (!_imprevus) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(LucideIcons.calendarClock, size: 18, color: c.texteSecondaire),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_echeance == null ? 'Sans échéance' : 'Pour le ${dateLongue(_echeance!)}')),
                  if (_echeance != null)
                    IconButton(
                      tooltip: 'Retirer l\'échéance',
                      onPressed: () => setState(() => _echeance = null),
                      icon: const Icon(LucideIcons.x, size: 18),
                    ),
                  TextButton(
                    onPressed: () async {
                      final date = await _choisirDate(context, _echeance);
                      if (date != null) setState(() => _echeance = date);
                    },
                    child: Text(_echeance == null ? 'Choisir' : 'Changer'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Etiquette('Icône'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in iconesObjectif.entries)
                  ChoiceChip(
                    label: Icon(e.value, size: 18),
                    selected: _icone == e.key,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _icone = e.key),
                  ),
              ],
            ),
            if (_erreur != null) ...[const SizedBox(height: 10), Text(_erreur!, style: TextStyle(color: c.alerte))],
            const SizedBox(height: 16),
            FilledButton(onPressed: _valider, child: Text(widget.objectif == null ? 'Créer' : 'Enregistrer')),
          ],
        ),
      ),
    );
  }
}
