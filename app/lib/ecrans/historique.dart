import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'depense.dart';
import '../data/api.dart';
import '../data/cache.dart';
import '../data/modeles.dart';
import '../theme/opti_theme.dart';
import '../util/format.dart';
import '../widgets/communs.dart';

/// Historique : toutes les opérations, regroupées par jour, avec recherche et filtre par banque.
class EcranHistorique extends ConsumerStatefulWidget {
  const EcranHistorique({super.key});

  @override
  ConsumerState<EcranHistorique> createState() => _EcranHistoriqueState();
}

class _EcranHistoriqueState extends ConsumerState<EcranHistorique> {
  final _defilement = ScrollController();
  final _champ = TextEditingController();
  Timer? _attenteFrappe;

  final List<Operation> _operations = [];
  DateTime? _suite; // date où reprendre ; null : tout est chargé
  bool _chargement = false, _toutCharge = false;
  bool _flecheVisible = false; // « remonter tout en haut », une fois descendu d'environ un écran
  String? _erreur;
  String? _banque; // null : toutes
  String _recherche = '';

  @override
  void initState() {
    super.initState();
    _defilement.addListener(() {
      if (_defilement.position.extentAfter < 600) _chargerSuite();
      final visible = _defilement.offset > 800;
      if (visible != _flecheVisible) setState(() => _flecheVisible = visible);
    });
    _recharger();
  }

  @override
  void dispose() {
    _defilement.dispose();
    _champ.dispose();
    _attenteFrappe?.cancel();
    super.dispose();
  }

  Future<void> _recharger() async {
    setState(() {
      _operations.clear();
      _suite = null;
      _toutCharge = false;
      _erreur = null;
    });
    await _charger();
  }

  Future<void> _chargerSuite() async {
    if (!_chargement && !_toutCharge && _erreur == null) await _charger();
  }

  Future<void> _charger() async {
    if (_chargement) return;
    setState(() => _chargement = true);
    final demande = (_recherche, _banque);
    try {
      final r = await ref.read(apiProvider).historique(jusquAu: _suite, recherche: _recherche, banque: _banque);
      if (!mounted || demande != (_recherche, _banque)) return; // la recherche a changé entre-temps
      setState(() {
        _operations.addAll(r.operations);
        _suite = r.suite;
        _toutCharge = r.suite == null;
      });
      // Une page vide (14 jours sans opération) : on enchaîne tant que l'écran n'est pas rempli.
      if (!_toutCharge && r.operations.isEmpty) {
        _chargement = false;
        await _charger();
      }
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  void _quandOnTape(String texte) {
    _attenteFrappe?.cancel();
    _attenteFrappe = Timer(const Duration(milliseconds: 400), () {
      if (texte.trim() == _recherche) return;
      _recherche = texte.trim();
      _recharger();
    });
  }

  void _choisirBanque(String? banque) {
    if (banque == _banque) return;
    _banque = banque;
    _recharger();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final objectifs = (ref.watch(objectifsProvider).value ?? ref.read(cacheProvider).objectifs())?.objectifs ?? [];
    String? payePar(Operation o) => objectifs.where((x) => x.id == o.objectifId).firstOrNull?.nom;

    // Regroupement par jour (les opérations arrivent de la plus récente à la plus ancienne).
    final jours = <DateTime, List<Operation>>{};
    for (final o in _operations) {
      jours.putIfAbsent(DateTime(o.date.year, o.date.month, o.date.day), () => []).add(o);
    }

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Historique')),
      floatingActionButton: AnimatedScale(
        scale: _flecheVisible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: FloatingActionButton.small(
          tooltip: 'Remonter tout en haut',
          onPressed: () =>
              _defilement.animateTo(0, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic),
          child: const Icon(LucideIcons.arrowUp),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _champ,
              onChanged: _quandOnTape,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Rechercher (Primark, Amazon…)',
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                suffixIcon: _champ.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer',
                        icon: const Icon(LucideIcons.x, size: 18),
                        onPressed: () {
                          _champ.clear();
                          _quandOnTape('');
                        },
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final (libelle, valeur) in const [('Toutes', null), ('CIC', 'CIC'), ('Revolut', 'Revolut')])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(libelle),
                      selected: _banque == valeur,
                      showCheckmark: false,
                      onSelected: (_) => _choisirBanque(valeur),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _recharger,
              child: ListView(
                controller: _defilement,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  for (final MapEntry(key: jour, value: liste) in jours.entries) ...[
                    _EnTeteJour(jour: jour, operations: liste),
                    Carte(
                      child: Column(
                        children: [
                          for (final o in liste)
                            LigneOperation(
                              operation: o,
                              payePar: payePar(o),
                              onTap: o.montant < 0 && !o.interne
                                  ? () async {
                                      await toucherDepense(context, ref, o);
                                      await _recharger();
                                    }
                                  : null,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_chargement)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_erreur != null)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Text(
                            _erreur!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.alerte),
                          ),
                          TextButton(onPressed: _charger, child: const Text('Réessayer')),
                        ],
                      ),
                    )
                  else if (_operations.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _recherche.isEmpty ? 'Aucune opération.' : 'Aucune opération pour « $_recherche ».',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.texteSecondaire),
                      ),
                    )
                  else if (_toutCharge)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _recherche.isEmpty ? 'Début de l\'historique' : '200 résultats au plus',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: c.texteSecondaire),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EnTeteJour extends StatelessWidget {
  const _EnTeteJour({required this.jour, required this.operations});
  final DateTime jour;
  final List<Operation> operations;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    // Dépensé ce jour-là : hors virements internes et hors dépenses payées par un objectif, comme l'accueil.
    final depense = -operations
        .where((o) => !o.interne && o.objectifId == null && o.montant < 0)
        .fold<double>(0, (total, o) => total + o.montant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(titreJour(jour), style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (depense > 0) Text('−${euros(depense)}', style: chiffres(fontSize: 13, color: c.texteSecondaire)),
        ],
      ),
    );
  }
}

/// Une opération (libellé, catégorie ou projet, banque, montant) ; aussi utilisée par les Stats.
class LigneOperation extends StatelessWidget {
  const LigneOperation({super.key, required this.operation, this.payePar, this.onTap});
  final Operation operation;
  final String? payePar;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final o = operation;
    final String detail;
    if (o.interne) {
      detail = 'Virement interne · ${o.banque}';
    } else if (payePar != null) {
      detail = 'Payé avec « $payePar » · ${o.banque}';
    } else {
      detail = '${o.categorie} · ${o.banque}${o.enAttente ? ' · en attente' : ''}';
    }
    final couleurTexte = o.interne ? c.texteSecondaire : c.texte;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    o.libelle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: couleurTexte),
                  ),
                  Text(
                    detail,
                    style: TextStyle(fontSize: 12, color: payePar != null && !o.interne ? c.accent : c.texteSecondaire),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              eurosSignes(o.montant),
              style: chiffres(color: o.interne ? c.texteSecondaire : (o.montant > 0 ? c.ok : c.texte)),
            ),
          ],
        ),
      ),
    );
  }
}
