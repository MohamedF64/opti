import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../theme/opti_theme.dart';

/// Connexion à faire une seule fois : la session est ensuite gardée sur le téléphone.
class EcranConnexion extends StatefulWidget {
  const EcranConnexion({super.key});

  @override
  State<EcranConnexion> createState() => _EcranConnexionState();
}

class _EcranConnexionState extends State<EcranConnexion> {
  final _email = TextEditingController(text: emailParDefaut);
  final _motDePasse = TextEditingController();
  bool _enCours = false;
  String? _erreur;

  Future<void> _seConnecter() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(email: _email.text.trim(), password: _motDePasse.text);
    } on AuthException catch (e) {
      setState(() => _erreur = e.statusCode == '400' ? 'E-mail ou mot de passe incorrect.' : e.message);
    } catch (_) {
      setState(() => _erreur = 'Connexion impossible. Vérifie ta connexion internet.');
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _motDePasse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Opti',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 44, fontWeight: FontWeight.w700, color: c.accent),
                ),
                const SizedBox(height: 6),
                Text(
                  'Ton budget, au calme.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.texteSecondaire),
                ),
                const SizedBox(height: 36),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _motDePasse,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _seConnecter(),
                  decoration: const InputDecoration(labelText: 'Mot de passe', border: OutlineInputBorder()),
                ),
                if (_erreur != null) ...[const SizedBox(height: 12), Text(_erreur!, style: TextStyle(color: c.alerte))],
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: _enCours ? null : _seConnecter,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _enCours
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Se connecter'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
