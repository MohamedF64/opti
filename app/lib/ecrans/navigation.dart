import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/api.dart';
import '../data/notifications.dart';
import '../theme/opti_theme.dart';
import '../widgets/communs.dart';
import 'abonnements.dart';
import 'accueil.dart';
import 'catalogue.dart';
import 'objectifs.dart';
import 'reglages.dart';
import 'stats.dart';

/// Onglet affiché : changeable d'ailleurs (« Voir les stats », notification d'abonnement).
class Onglet extends Notifier<int> {
  @override
  int build() => 0;

  void aller(int onglet) => state = onglet;
}

final ongletProvider = NotifierProvider<Onglet, int>(Onglet.new);

/// Barre du bas, comme la maquette « Refonte 2026 ».
class Navigation extends ConsumerStatefulWidget {
  const Navigation({super.key});

  @override
  ConsumerState<Navigation> createState() => _NavigationState();
}

class _NavigationState extends ConsumerState<Navigation> {
  final _abonnements = <StreamSubscription<RemoteMessage>>[];

  @override
  void initState() {
    super.initState();
    enregistrerTelephone(ref.read(apiProvider));
    // Notification touchée, app fermée ou en arrière-plan : ouvrir le bon écran.
    FirebaseMessaging.instance.getInitialMessage().then((m) => m == null ? null : _ouvrir(m));
    _abonnements.add(FirebaseMessaging.onMessageOpenedApp.listen(_ouvrir));
    // App ouverte : Android n'affiche rien, on le dit dans l'app.
    _abonnements.add(
      FirebaseMessaging.onMessage.listen((m) {
        final texte = m.notification?.body;
        if (texte != null && mounted) signaler(context, texte);
      }),
    );
  }

  @override
  void dispose() {
    for (final a in _abonnements) {
      a.cancel();
    }
    super.dispose();
  }

  void _ouvrir(RemoteMessage message) {
    if (!mounted) return;
    final ecran = ecranDe(message);
    ref.read(ongletProvider.notifier).aller(ecran == 'abonnements' || ecran == 'catalogue' ? 3 : 0);
    ref.invalidate(accueilProvider);
    if (ecran == 'abonnements') ref.invalidate(abonnementsProvider);
    if (ecran == 'catalogue') {
      ref.invalidate(catalogueProvider);
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EcranCatalogue()));
    }
    if (ecran == 'reglages') {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EcranReglages()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return Scaffold(
      // IndexedStack garde chaque écran en mémoire : pas de nouvelle synchro en revenant sur l'accueil.
      body: IndexedStack(
        index: ref.watch(ongletProvider),
        children: const [EcranAccueil(), EcranObjectifsListe(), EcranStatsOnglet(), EcranAbonnementsListe()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: ref.watch(ongletProvider),
        onDestinationSelected: (i) => ref.read(ongletProvider.notifier).aller(i),
        backgroundColor: c.fond,
        indicatorColor: c.accent.withValues(alpha: 0.18),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(icon: Icon(LucideIcons.house), label: 'Accueil'),
          NavigationDestination(icon: Icon(LucideIcons.target), label: 'Objectifs'),
          NavigationDestination(icon: Icon(LucideIcons.chartPie), label: 'Stats'),
          NavigationDestination(icon: Icon(LucideIcons.calendarSync), label: 'Abonnements'),
        ],
      ),
    );
  }
}
