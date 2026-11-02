/// Réglages › Sécurité : verrouiller Opti, empreinte, délai, changer le code.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/verrou.dart';
import '../theme/opti_theme.dart';
import '../widgets/communs.dart';
import 'verrou.dart';

class CarteSecurite extends ConsumerStatefulWidget {
  const CarteSecurite({super.key});

  @override
  ConsumerState<CarteSecurite> createState() => _CarteSecuriteState();
}

class _CarteSecuriteState extends ConsumerState<CarteSecurite> {
  final _empreintePossible = Verrou.empreinteDisponible();

  Future<bool> _choisirCode() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (contexte) => Scaffold(
          appBar: AppBar(backgroundColor: Colors.transparent),
          body: EcranNouveauCode(onFini: () => Navigator.pop(contexte, true)),
        ),
      ),
    );
    return ok == true;
  }

  Future<void> _activer(bool oui) async {
    final verrou = ref.read(verrouProvider);
    if (oui) {
      if (await _choisirCode() && mounted && await _empreintePossible && mounted) {
        final avecEmpreinte = await showDialog<bool>(
          context: context,
          builder: (contexte) => AlertDialog(
            title: const Text("Déverrouiller avec l'empreinte ?"),
            content: const Text('Le code restera toujours possible en secours.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(contexte, false), child: const Text('Non')),
              FilledButton(onPressed: () => Navigator.pop(contexte, true), child: const Text('Oui')),
            ],
          ),
        );
        if (avecEmpreinte == true) await _empreinte(true);
      }
    } else if (await verifierCodeActuel(context)) {
      await verrou.desactiver();
    }
  }

  Future<void> _empreinte(bool oui) async {
    final verrou = ref.read(verrouProvider);
    if (!oui) return verrou.activerEmpreinte(false);
    // Une empreinte réussie d'abord, pour être sûr que le capteur marche.
    await verrou.activerEmpreinte(true);
    if (!await verrou.essayerEmpreinte()) {
      await verrou.activerEmpreinte(false);
      if (mounted) signaler(context, "Empreinte non reconnue : elle n'est pas activée.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final verrou = ref.watch(verrouProvider);
    final c = context.couleurs;
    return ListenableBuilder(
      listenable: verrou,
      builder: (context, _) => Carte(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(LucideIcons.lock, color: c.accent),
              title: const Text('Verrouiller Opti'),
              subtitle: const Text('Code à 4 chiffres à chaque ouverture'),
              value: verrou.actif,
              onChanged: _activer,
            ),
            if (verrou.actif) ...[
              FutureBuilder<bool>(
                future: _empreintePossible,
                builder: (context, possible) => possible.data == true
                    ? SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: Icon(LucideIcons.fingerprint, color: c.accent),
                        title: const Text("Déverrouiller avec l'empreinte"),
                        value: verrou.empreinte,
                        onChanged: _empreinte,
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 8),
              Text('Verrouiller au retour dans Opti', style: TextStyle(fontSize: 13, color: c.texteSecondaire)),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 0, label: Text('Tout de suite')),
                  ButtonSegment(value: 60, label: Text('Après 1 min')),
                  ButtonSegment(value: 300, label: Text('Après 5 min')),
                ],
                selected: {verrou.delai},
                onSelectionChanged: (choix) => verrou.choisirDelai(choix.first),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () async {
                    if (await verifierCodeActuel(context) && mounted && await _choisirCode() && mounted) {
                      signaler(this.context, 'Code changé.');
                    }
                  },
                  child: const Text('Changer le code'),
                ),
              ),
            ],
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(LucideIcons.shieldCheck, color: c.accent),
              title: const Text('Double authentification activée'),
              subtitle: const Text(
                'Code de Google Authenticator à chaque connexion. Téléphone perdu : réinstalle Google '
                'Authenticator et connecte-toi à ton compte Google, tes codes reviennent.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
