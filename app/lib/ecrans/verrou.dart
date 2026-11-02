/// Écran de verrouillage, création et vérification du code, masque dans les apps récentes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/cache.dart';
import '../data/verrou.dart';
import '../theme/opti_theme.dart';

/// Au 5e code faux ou sur « Code oublié ? » : déconnexion ; un nouveau code sera proposé après la reconnexion.
Future<void> deconnecterApresOubli(WidgetRef ref) async {
  await ref.read(verrouProvider).reinitialiser();
  await ref.read(cacheProvider).vider();
  await Supabase.instance.client.auth.signOut();
}

/// Enveloppe toute l'app (MaterialApp.builder) : verrou par-dessus quand il le faut.
class GardeVerrou extends ConsumerStatefulWidget {
  const GardeVerrou({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<GardeVerrou> createState() => _GardeVerrouState();
}

class _GardeVerrouState extends ConsumerState<GardeVerrou> with WidgetsBindingObserver {
  bool _masque = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState etat) {
    final verrou = ref.read(verrouProvider);
    if (etat == AppLifecycleState.resumed) {
      verrou.revenir(DateTime.now());
      setState(() => _masque = false);
    } else {
      // Masqué dès que l'app perd la main : la capture des apps récentes ne montre pas les soldes.
      if (etat == AppLifecycleState.hidden || etat == AppLifecycleState.paused) verrou.quitter(DateTime.now());
      if (verrou.actif && !_masque) setState(() => _masque = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final verrou = ref.watch(verrouProvider);
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) => ListenableBuilder(
        listenable: verrou,
        builder: (context, _) {
          final connecte = auth.currentSession != null;
          Widget? dessus;
          if (connecte && verrou.verrouille) {
            dessus = const _EcranVerrou();
          } else if (connecte && verrou.aRecreer) {
            dessus = EcranNouveauCode(onFini: () {}, proposition: true);
          } else if (_masque) {
            dessus = const _Masque();
          }
          return Stack(
            children: [
              widget.child,
              if (dessus != null)
                Positioned.fill(
                  child: Material(color: context.couleurs.fond, child: dessus),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Masque extends StatelessWidget {
  const _Masque();

  @override
  Widget build(BuildContext context) =>
      Center(child: Icon(LucideIcons.lock, size: 40, color: context.couleurs.texteSecondaire));
}

class _EcranVerrou extends ConsumerStatefulWidget {
  const _EcranVerrou();

  @override
  ConsumerState<_EcranVerrou> createState() => _EcranVerrouState();
}

class _EcranVerrouState extends ConsumerState<_EcranVerrou> {
  String? _erreur;
  bool _confirmerOubli = false;

  @override
  void initState() {
    super.initState();
    // L'empreinte est demandée toute seule ; le pavé reste là en secours.
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(verrouProvider).essayerEmpreinte());
  }

  Future<void> _code(String code) async {
    final verrou = ref.read(verrouProvider);
    switch (await verrou.essayer(code)) {
      case Essai.bon:
        break;
      case Essai.faux:
        final n = verrou.essaisRestants;
        setState(() => _erreur = 'Code faux. Encore $n essai${n > 1 ? 's' : ''}.');
      case Essai.bloque:
        await deconnecterApresOubli(ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    final verrou = ref.watch(verrouProvider);
    final c = context.couleurs;
    return ClavierCode(
      titre: 'Opti est verrouillé',
      message: _erreur ?? 'Tape ton code',
      erreur: _erreur != null,
      onCode: _code,
      onEmpreinte: verrou.empreinte ? verrou.essayerEmpreinte : null,
      bas: _confirmerOubli
          ? Column(
              children: [
                Text(
                  'Tu seras déconnecté ; reconnecte-toi avec ton e-mail et ton mot de passe, puis choisis un nouveau code.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: c.texteSecondaire),
                ),
                TextButton(
                  onPressed: () => deconnecterApresOubli(ref),
                  child: Text('Me déconnecter', style: TextStyle(color: c.alerte)),
                ),
              ],
            )
          : TextButton(onPressed: () => setState(() => _confirmerOubli = true), child: const Text('Code oublié ?')),
    );
  }
}

/// Choisir un code : tapé deux fois. `proposition` : après une reconnexion, avec « Plus tard ».
class EcranNouveauCode extends ConsumerStatefulWidget {
  const EcranNouveauCode({super.key, required this.onFini, this.proposition = false});
  final VoidCallback onFini;
  final bool proposition;

  @override
  ConsumerState<EcranNouveauCode> createState() => _EcranNouveauCodeState();
}

class _EcranNouveauCodeState extends ConsumerState<EcranNouveauCode> {
  String? _premier, _erreur;

  Future<void> _code(String code) async {
    if (_premier == null) {
      setState(() {
        _premier = code;
        _erreur = null;
      });
    } else if (code == _premier) {
      await ref.read(verrouProvider).definirCode(code);
      widget.onFini();
    } else {
      setState(() {
        _premier = null;
        _erreur = 'Les deux codes sont différents. Recommence.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClavierCode(
      titre: widget.proposition ? 'Choisis un nouveau code' : 'Choisis ton code',
      message: _erreur ?? (_premier == null ? '${Verrou.longueur} chiffres' : 'Tape-le une seconde fois'),
      erreur: _erreur != null,
      onCode: _code,
      bas: widget.proposition
          ? TextButton(
              onPressed: () => ref.read(verrouProvider).plusTard(),
              child: const Text('Plus tard (dans Réglages)'),
            )
          : null,
    );
  }
}

/// Vérifie le code actuel avant de le changer ou de le désactiver ; `true` si c'est le bon.
Future<bool> verifierCodeActuel(BuildContext context) async {
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: const _CodeActuel(),
      ),
    ),
  );
  return ok == true;
}

class _CodeActuel extends ConsumerStatefulWidget {
  const _CodeActuel();

  @override
  ConsumerState<_CodeActuel> createState() => _CodeActuelState();
}

class _CodeActuelState extends ConsumerState<_CodeActuel> {
  String? _erreur;

  Future<void> _code(String code) async {
    final verrou = ref.read(verrouProvider);
    final navigateur = Navigator.of(context);
    switch (await verrou.essayer(code)) {
      case Essai.bon:
        navigateur.pop(true);
      case Essai.faux:
        final n = verrou.essaisRestants;
        setState(() => _erreur = 'Code faux. Encore $n essai${n > 1 ? 's' : ''}.');
      case Essai.bloque:
        navigateur.popUntil((route) => route.isFirst);
        await deconnecterApresOubli(ref);
    }
  }

  @override
  Widget build(BuildContext context) =>
      ClavierCode(titre: 'Ton code actuel', message: _erreur ?? '', erreur: _erreur != null, onCode: _code);
}

/// Points du code et pavé numérique ; `onCode` reçoit les 4 chiffres.
class ClavierCode extends StatefulWidget {
  const ClavierCode({
    super.key,
    required this.titre,
    required this.message,
    required this.onCode,
    this.erreur = false,
    this.onEmpreinte,
    this.bas,
  });
  final String titre, message;
  final bool erreur;
  final Future<void> Function(String code) onCode;
  final Future<bool> Function()? onEmpreinte;
  final Widget? bas;

  @override
  State<ClavierCode> createState() => _ClavierCodeState();
}

class _ClavierCodeState extends State<ClavierCode> {
  String _saisie = '';
  bool _occupe = false;

  Future<void> _chiffre(String chiffre) async {
    if (_occupe || _saisie.length >= Verrou.longueur) return;
    setState(() => _saisie += chiffre);
    if (_saisie.length == Verrou.longueur) {
      _occupe = true;
      await widget.onCode(_saisie);
      if (mounted) {
        setState(() {
          _saisie = '';
          _occupe = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    Widget touche(Widget contenu, VoidCallback? action) => SizedBox(
      width: 76,
      height: 76,
      child: action == null
          ? null
          : InkWell(
              customBorder: const CircleBorder(),
              onTap: action,
              child: Center(child: contenu),
            ),
    );
    Widget chiffre(String n) => touche(
      Text(
        n,
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w500, color: c.texte),
      ),
      () => _chiffre(n),
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          children: [
            const Spacer(),
            Icon(LucideIcons.lock, size: 32, color: c.accent),
            const SizedBox(height: 16),
            Text(widget.titre, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: TextStyle(color: widget.erreur ? c.alerte : c.texteSecondaire),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < Verrou.longueur; i++)
                  Container(
                    width: 14,
                    height: 14,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _saisie.length ? c.accent : Colors.transparent,
                      border: Border.all(color: i < _saisie.length ? c.accent : c.texteSecondaire, width: 1.5),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            for (final ligne in [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
            ])
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [for (final n in ligne) chiffre(n)]),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                touche(
                  Icon(LucideIcons.fingerprint, size: 28, color: c.accent),
                  widget.onEmpreinte == null ? null : () => widget.onEmpreinte!(),
                ),
                chiffre('0'),
                touche(
                  Icon(LucideIcons.delete, size: 24, color: c.texteSecondaire),
                  () => setState(() => _saisie = _saisie.isEmpty ? '' : _saisie.substring(0, _saisie.length - 1)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(height: 72, child: widget.bas),
          ],
        ),
      ),
    );
  }
}
