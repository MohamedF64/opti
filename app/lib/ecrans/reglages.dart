import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'apparence.dart';
import 'notifications.dart';
import 'securite.dart';
import '../data/api.dart';
import '../data/cache.dart';
import '../data/modeles.dart';
import '../theme/opti_theme.dart';
import '../util/format.dart';
import '../widgets/communs.dart';

/// Réglages : budget (limite manuelle, mode économies max, épargne visée, jours de paie), banques, apparence, compte.
class EcranReglages extends ConsumerStatefulWidget {
  const EcranReglages({super.key});

  @override
  ConsumerState<EcranReglages> createState() => _EcranReglagesState();
}

class _EcranReglagesState extends ConsumerState<EcranReglages> with WidgetsBindingObserver {
  Map<String, dynamic>? _enregistres; // réglages tels qu'en base
  Map<String, dynamic>? _budgetActuel; // limite avec les réglages enregistrés
  final Map<String, Object?> _modifs = {}; // ce que Mohamed a changé, pas encore enregistré
  Map<String, dynamic>? _budgetEssai; // limite avec les modifications
  String? _erreur;
  bool _enregistrement = false, _calcul = false, _retourBanque = false;
  Timer? _attente;

  final _limite = TextEditingController();
  final _epargne = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _charger();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _attente?.cancel();
    _limite.dispose();
    _epargne.dispose();
    super.dispose();
  }

  /// Retour de la page de la banque : on synchronise pour voir l'accès renouvelé.
  @override
  void didChangeAppLifecycleState(AppLifecycleState etat) {
    if (etat == AppLifecycleState.resumed && _retourBanque) {
      _retourBanque = false;
      ref.read(apiProvider).synchroniser().catchError((_) {}).whenComplete(() => ref.invalidate(accueilProvider));
    }
  }

  Future<void> _charger() async {
    try {
      final r = await ref.read(apiProvider).reglages();
      if (!mounted) return;
      final reglages = r['reglages'] as Map<String, dynamic>;
      setState(() {
        _enregistres = reglages;
        _budgetActuel = r['budget'] as Map<String, dynamic>;
        _budgetEssai = null;
        _modifs.clear();
        _limite.text = _texteMontant(reglages['limite_manuelle']);
        _epargne.text = _texteMontant(reglages['epargne_visee']);
      });
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    }
  }

  static String _texteMontant(Object? v) => v == null ? '' : (v as num).toStringAsFixed(2).replaceAll('.', ',');

  Object? _valeur(String cle) => _modifs.containsKey(cle) ? _modifs[cle] : _enregistres?[cle];

  /// Toute modification recalcule l'aperçu « ta limite passerait de X à Y » (après une courte pause de frappe).
  void _modifier(String cle, Object? valeur) {
    setState(() {
      if (valeur == _enregistres?[cle]) {
        _modifs.remove(cle);
      } else {
        _modifs[cle] = valeur;
      }
    });
    _attente?.cancel();
    if (_modifs.isEmpty) {
      setState(() => _budgetEssai = null);
      return;
    }
    _attente = Timer(const Duration(milliseconds: 400), _calculerApercu);
  }

  Future<void> _calculerApercu() async {
    final essai = Map<String, Object?>.of(_modifs);
    setState(() => _calcul = true);
    try {
      final r = await ref.read(apiProvider).apercuReglages(essai);
      if (mounted && _memes(essai, _modifs)) setState(() => _budgetEssai = r['budget'] as Map<String, dynamic>);
    } catch (e) {
      if (mounted) signaler(context, e);
    } finally {
      if (mounted) setState(() => _calcul = false);
    }
  }

  static bool _memes(Map<String, Object?> a, Map<String, Object?> b) =>
      a.length == b.length && a.entries.every((e) => b.containsKey(e.key) && b[e.key] == e.value);

  Future<void> _enregistrer() async {
    setState(() => _enregistrement = true);
    try {
      await ref.read(apiProvider).modifierReglages(Map.of(_modifs));
      ref.invalidate(accueilProvider);
      await _charger();
      if (mounted) signaler(context, 'Réglages enregistrés.');
    } catch (e) {
      if (mounted) signaler(context, e);
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  Future<void> _ouvrirBanque(String banque) async {
    try {
      final url = await ref.read(apiProvider).urlConnexionBanque(banque);
      _retourBanque = true;
      if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
        throw ApiException("Impossible d'ouvrir le navigateur.");
      }
    } catch (e) {
      _retourBanque = false;
      if (mounted) signaler(context, e);
    }
  }

  /// Pour finir le renouvellement sur l'ordinateur (QR code à scanner) quand le retour vers le navigateur échoue.
  Future<void> _copierLienBanque(String banque) async {
    try {
      final url = await ref.read(apiProvider).urlConnexionBanque(banque);
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        signaler(
          context,
          "Lien copié. Ouvre-le sur ton ordinateur dans l'heure, puis valide dans l'app de ta banque. "
          "Opti se mettra à jour à la prochaine synchro.",
        );
      }
    } catch (e) {
      if (mounted) signaler(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final accueil = ref.watch(accueilProvider).value ?? ref.read(cacheProvider).accueil();
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Réglages')),
      body: _enregistres == null
          ? (_erreur != null
                ? Erreur(message: _erreur!, reessayer: _charger)
                : const Center(child: CircularProgressIndicator()))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                _sectionBudget(c),
                const SizedBox(height: 20),
                const Etiquette('Mes banques'),
                const SizedBox(height: 8),
                for (final b in accueil?.banques ?? <Banque>[]) ...[
                  _CarteBanque(
                    banque: b,
                    renouveler: () => _ouvrirBanque(b.nom),
                    copierLien: () => _copierLienBanque(b.nom),
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  "Pour relier un autre compte (ton Livret A par exemple), renouvelle l'accès de la banque : "
                  'tu pourras choisir les comptes à partager.',
                  style: TextStyle(fontSize: 12.5, color: c.texteSecondaire),
                ),
                const SizedBox(height: 20),
                const Etiquette('Notifications'),
                const SizedBox(height: 8),
                const CarteNotifications(),
                const SizedBox(height: 20),
                const Etiquette('Sécurité'),
                const SizedBox(height: 8),
                const CarteSecurite(),
                const SizedBox(height: 20),
                const Etiquette('Apparence'),
                const SizedBox(height: 8),
                const CarteApparence(),
                const SizedBox(height: 20),
                const Etiquette('Compte'),
                const SizedBox(height: 8),
                Carte(
                  onTap: () async {
                    await ref.read(cacheProvider).vider();
                    await Supabase.instance.client.auth.signOut();
                    if (context.mounted) Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  child: Row(
                    children: [
                      Icon(LucideIcons.logOut, color: c.alerte),
                      const SizedBox(width: 12),
                      Text('Se déconnecter', style: TextStyle(color: c.alerte)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const VersionOpti(),
              ],
            ),
    );
  }

  Widget _sectionBudget(OptiColors c) {
    final limiteActive = _valeur('limite_manuelle') != null;
    final economiesMax = _valeur('mode_economies_max') == true;
    final epargneManuelle = _valeur('epargne_visee') != null;
    final proposee = (_budgetActuel?['epargne_proposee'] as num?)?.toDouble() ?? 0;
    final avant = (_budgetActuel?['limite_du_jour'] as num?)?.toDouble();
    final apres = (_budgetEssai?['limite_du_jour'] as num?)?.toDouble();
    final effet = (_budgetEssai?['effet_limite_manuelle'] as num?)?.toDouble() ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Etiquette('Mon budget'),
        const SizedBox(height: 8),
        Carte(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Limite manuelle'),
                subtitle: Text(
                  economiesMax
                      ? 'Plafond : jamais plus que ce montant par jour'
                      : 'Marge de sécurité : jamais moins que ce montant par jour',
                ),
                value: limiteActive,
                onChanged: (oui) {
                  if (oui) {
                    final v = lireMontant(_limite.text) ?? (avant ?? 50).roundToDouble();
                    _limite.text = _texteMontant(v);
                    _modifier('limite_manuelle', v);
                  } else {
                    _modifier('limite_manuelle', null);
                  }
                },
              ),
              if (limiteActive) ...[
                TextField(
                  controller: _limite,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: chiffres(),
                  decoration: const InputDecoration(
                    labelText: 'Par jour',
                    suffixText: '€',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (t) {
                    final v = lireMontant(t);
                    if (v != null && v > 0) _modifier('limite_manuelle', v);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mode économies max'),
                  subtitle: const Text('La limite manuelle devient un plafond'),
                  value: economiesMax,
                  onChanged: (oui) => _modifier('mode_economies_max', oui),
                ),
              ],
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Épargne visée choisie par moi'),
                subtitle: Text(
                  epargneManuelle
                      ? 'Pour ce cycle, à la place de la proposition'
                      : 'Proposée par tes objectifs : ${euros(proposee)} pour ce cycle',
                ),
                value: epargneManuelle,
                onChanged: (oui) {
                  if (oui) {
                    final v = lireMontant(_epargne.text) ?? proposee;
                    _epargne.text = _texteMontant(v);
                    _modifier('epargne_visee', v);
                  } else {
                    _modifier('epargne_visee', null);
                  }
                },
              ),
              if (epargneManuelle)
                TextField(
                  controller: _epargne,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: chiffres(),
                  decoration: const InputDecoration(
                    labelText: 'À mettre de côté sur ce cycle',
                    suffixText: '€',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (t) {
                    final v = lireMontant(t);
                    if (v != null && v >= 0) _modifier('epargne_visee', v);
                  },
                ),
              const Divider(height: 24),
              Row(
                children: [
                  const Expanded(child: Text('Ma paie arrive entre le')),
                  _jour('jour_paie_min'),
                  const Text('  et le  '),
                  _jour('jour_paie_max'),
                ],
              ),
            ],
          ),
        ),
        if (_modifs.isNotEmpty) ...[
          const SizedBox(height: 10),
          Carte(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_calcul || apres == null)
                  Text('Calcul de l\'effet…', style: TextStyle(color: c.texteSecondaire))
                else ...[
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: "Ta limite d'aujourd'hui passerait de "),
                        TextSpan(text: euros(avant ?? 0), style: chiffres()),
                        const TextSpan(text: ' à '),
                        TextSpan(
                          text: euros(apres),
                          style: chiffres(color: apres >= (avant ?? 0) ? c.ok : c.or),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                  if (effet.abs() >= 0.01)
                    Text(
                      effet > 0
                          ? 'Les jours suivants baisseraient de ${euros(effet)} chacun pour compenser.'
                          : 'Les jours suivants monteraient de ${euros(-effet)} chacun.',
                      style: TextStyle(fontSize: 13, color: c.texteSecondaire),
                    ),
                ],
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: _charger, child: const Text('Annuler')),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _enregistrement || _calcul ? null : _enregistrer,
                      child: const Text('Enregistrer'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _jour(String cle) {
    final valeur = (_valeur(cle) as num?)?.toInt() ?? 21;
    return DropdownButton<int>(
      value: valeur,
      underline: const SizedBox.shrink(),
      items: [for (var j = 1; j <= 31; j++) DropdownMenuItem(value: j, child: Text('$j'))],
      onChanged: (j) {
        if (j != null) _modifier(cle, j);
      },
    );
  }
}

class _CarteBanque extends StatelessWidget {
  const _CarteBanque({required this.banque, required this.renouveler, required this.copierLien});
  final Banque banque;
  final VoidCallback renouveler, copierLien;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final b = banque;
    final jours = b.joursRestants;
    final Color couleur = b.statut == 'expiree' || (jours != null && jours <= 7)
        ? c.alerte
        : (b.aRenouveler ? c.or : c.ok);
    final String acces = b.statut == 'expiree'
        ? 'Accès expiré'
        : (b.accesJusquAu != null ? "Accès jusqu'au ${dateLongue(b.accesJusquAu!)}" : 'Accès actif');
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.landmark, color: c.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(b.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Icon(b.statut == 'ok' ? LucideIcons.circleCheck : LucideIcons.circleAlert, size: 18, color: couleur),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [acces, if (jours != null && b.statut != 'expiree') '$jours jours restants'].join(' · '),
            style: TextStyle(fontSize: 13, color: couleur),
          ),
          if (b.derniereSynchro != null)
            Text(
              'Dernière synchro ${ilYa(b.derniereSynchro!)}${b.statut == 'erreur' ? ' (en échec)' : ''}',
              style: TextStyle(fontSize: 12.5, color: c.texteSecondaire),
            ),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              TextButton.icon(
                onPressed: copierLien,
                icon: const Icon(LucideIcons.copy, size: 16),
                label: const Text('Copier le lien'),
              ),
              TextButton.icon(
                onPressed: renouveler,
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: const Text("Renouveler l'accès"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
