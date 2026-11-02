/// Réglages › Notifications : un interrupteur par type, et une notification de test.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/api.dart';
import '../data/notifications.dart';
import '../theme/opti_theme.dart';
import '../widgets/communs.dart';

class CarteNotifications extends ConsumerStatefulWidget {
  const CarteNotifications({super.key});

  @override
  ConsumerState<CarteNotifications> createState() => _CarteNotificationsState();
}

class _CarteNotificationsState extends ConsumerState<CarteNotifications> {
  Map<String, bool>? _actives;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final r = await ref.read(apiProvider).reglagesNotifications();
      if (mounted) setState(() => _actives = {for (final e in r.entries) e.key: e.value == true});
    } catch (e) {
      if (mounted) signaler(context, e);
    }
  }

  Future<void> _basculer(String type, bool oui) async {
    final avant = _actives;
    setState(() => _actives = {...?_actives, type: oui});
    try {
      final r = await ref.read(apiProvider).modifierNotifications({type: oui});
      if (mounted) setState(() => _actives = {for (final e in r.entries) e.key: e.value == true});
    } catch (e) {
      if (!mounted) return;
      setState(() => _actives = avant);
      signaler(context, e);
    }
  }

  Future<void> _tester() async {
    setState(() => _envoi = true);
    try {
      // Le téléphone redonne son jeton d'abord : utile si l'autorisation vient d'être accordée.
      await enregistrerTelephone(ref.read(apiProvider));
      // Le serveur attend 10 s avant d'envoyer : Android n'affiche pas de bannière pour l'app ouverte.
      if (mounted) signaler(context, 'Quitte Opti maintenant : la notification arrive dans 10 secondes.');
      // Sans attendre la réponse : en quittant Opti, Android (Xiaomi) coupe sa connexion et la réponse se perd,
      // alors que le serveur envoie bien. La notification reçue est la seule preuve qui compte.
      unawaited(ref.read(apiProvider).testerNotification().then((_) {}, onError: (_) {}));
    } catch (e) {
      if (mounted) signaler(context, e);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    final actives = _actives;
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (actives == null)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            for (final MapEntry(key: type, value: (titre, detail)) in typesNotifications.entries)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(titre),
                subtitle: Text(detail, style: TextStyle(fontSize: 12, color: c.texteSecondaire)),
                value: actives[type] ?? true,
                onChanged: (oui) => _basculer(type, oui),
              ),
          const SizedBox(height: 4),
          Text(
            'Envoyées après les synchros de 8 h, 12 h, 17 h et 21 h : jamais la nuit. '
            'Le texte reste neutre (aucun montant) car il s\'affiche sur l\'écran verrouillé.',
            style: TextStyle(fontSize: 12, color: c.texteSecondaire),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _envoi ? null : _tester,
              icon: const Icon(LucideIcons.bellRing, size: 18),
              label: const Text('Envoyer une notification de test'),
            ),
          ),
        ],
      ),
    );
  }
}
