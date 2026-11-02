/// Activation de la double authentification et saisie du code à la connexion.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/cache.dart';
import '../data/double_auth.dart';
import '../theme/opti_theme.dart';
import '../widgets/communs.dart';

const _conseilSauvegarde =
    "Dans Google Authenticator, connecte-toi à ton compte Google : tes codes y sont sauvegardés et "
    'reviennent sur un nouveau téléphone.';

Future<void> _deconnecter(WidgetRef ref) async {
  await ref.read(cacheProvider).vider();
  await Supabase.instance.client.auth.signOut();
}

/// Première ouverture après la mise à jour : le code devient obligatoire.
class EcranActiverCode extends ConsumerStatefulWidget {
  const EcranActiverCode({super.key});

  @override
  ConsumerState<EcranActiverCode> createState() => _EcranActiverCodeState();
}

class _EcranActiverCodeState extends ConsumerState<EcranActiverCode> {
  final _auth = Supabase.instance.client.auth;
  late Future<TOTPEnrollment> _activation;
  String? _facteurId;

  @override
  void initState() {
    super.initState();
    _activation = commencerActivation(_auth, (id) => _facteurId = id);
  }

  Future<void> _ouvrirApp(TOTPEnrollment totp) async {
    final ok = await launchUrl(Uri.parse(totp.uri), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && mounted) signaler(context, 'Installe Google Authenticator depuis le Play Store, puis réessaie.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return _Page(
      titre: 'Double authentification',
      intro:
          'Pour protéger tes comptes, Opti demande désormais un code à 6 chiffres en plus du mot de passe, '
          'à chaque connexion (pas à chaque ouverture).',
      child: FutureBuilder<TOTPEnrollment>(
        future: _activation,
        builder: (context, s) {
          if (s.hasError) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Activation impossible pour le moment. Vérifie ta connexion internet.',
                  style: TextStyle(color: c.alerte),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => setState(() => _activation = commencerActivation(_auth, (id) => _facteurId = id)),
                  child: const Text('Réessayer'),
                ),
              ],
            );
          }
          final totp = s.data;
          if (totp == null) return const Center(child: CircularProgressIndicator());
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('1. Ajoute Opti dans Google Authenticator', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => _ouvrirApp(totp),
                icon: const Icon(LucideIcons.externalLink, size: 18),
                label: const Text('Ouvrir Google Authenticator'),
              ),
              const SizedBox(height: 10),
              Text('Ou saisis cette clé à la main :', style: TextStyle(fontSize: 13, color: c.texteSecondaire)),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      cleLisible(totp.secret),
                      style: const TextStyle(fontFamily: 'DM Mono', fontSize: 15),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copier la clé',
                    icon: const Icon(LucideIcons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: totp.secret));
                      signaler(context, 'Clé copiée.');
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(_conseilSauvegarde, style: TextStyle(fontSize: 13, color: c.texteSecondaire)),
              const SizedBox(height: 22),
              const Text('2. Tape le code affiché', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              _ChampCode(
                valider: (code) => _auth.mfa.challengeAndVerify(factorId: _facteurId!, code: code),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Après le mot de passe : le code de l'app d'authentification.
class EcranSaisirCode extends ConsumerWidget {
  const EcranSaisirCode({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = Supabase.instance.client.auth;
    final c = context.couleurs;
    return _Page(
      titre: 'Code de vérification',
      intro: 'Ouvre Google Authenticator et tape le code à 6 chiffres affiché pour Opti.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ChampCode(
            valider: (code) => auth.mfa.challengeAndVerify(factorId: facteurVerifie(auth)!, code: code),
          ),
          const SizedBox(height: 24),
          Text(
            "Plus accès à ton app de codes ? Réinstalle Google Authenticator et connecte-toi à ton compte Google : "
            'tes codes reviennent. Sinon, le code peut être retiré depuis le tableau de bord Supabase.',
            style: TextStyle(fontSize: 13, color: c.texteSecondaire),
          ),
        ],
      ),
    );
  }
}

class _Page extends ConsumerWidget {
  const _Page({required this.titre, required this.intro, required this.child});
  final String titre, intro;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.couleurs;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(LucideIcons.shieldCheck, size: 40, color: c.accent),
                const SizedBox(height: 12),
                Text(
                  titre,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  intro,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.texteSecondaire),
                ),
                const SizedBox(height: 28),
                child,
                const SizedBox(height: 16),
                TextButton(onPressed: () => _deconnecter(ref), child: const Text('Se déconnecter')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Champ à 6 chiffres ; une fois le code accepté, la session passe en aal2 et l'app s'ouvre d'elle-même.
class _ChampCode extends StatefulWidget {
  const _ChampCode({required this.valider});
  final Future<void> Function(String code) valider;

  @override
  State<_ChampCode> createState() => _ChampCodeState();
}

class _ChampCodeState extends State<_ChampCode> {
  final _code = TextEditingController();
  bool _enCours = false;
  String? _erreur;

  Future<void> _envoyer() async {
    if (_code.text.length != 6 || _enCours) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await widget.valider(_code.text);
    } on AuthException {
      _code.clear();
      setState(() => _erreur = 'Code incorrect ou expiré. Tape le code affiché maintenant.');
    } catch (_) {
      setState(() => _erreur = 'Vérification impossible. Vérifie ta connexion internet.');
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 26, letterSpacing: 10, fontFamily: 'DM Mono'),
          decoration: const InputDecoration(hintText: '000000', border: OutlineInputBorder()),
          onChanged: (texte) {
            if (texte.length == 6) _envoyer();
          },
        ),
        if (_erreur != null) ...[const SizedBox(height: 10), Text(_erreur!, style: TextStyle(color: c.alerte))],
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _enCours ? null : _envoyer,
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          child: _enCours
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Valider'),
        ),
      ],
    );
  }
}
