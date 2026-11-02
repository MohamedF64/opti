/// Fonds animés des thèmes, portés de la maquette « Thèmes et fonds » (docs/refonte-apparence.md du backend).
/// Une seule horloge pour toute l'app (30 images/s) ; en arrière-plan Android ne demande plus d'images,
/// donc l'animation s'arrête d'elle-même ; « Réduire les animations » fige le fond.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/opti_theme.dart';
import 'fond_foret.dart';
import 'fond_holocron.dart';
import 'fond_ocean.dart';

/// Temps de l'animation, en secondes, partagé par tous les fonds affichés.
class HorlogeFond extends StatefulWidget {
  const HorlogeFond({super.key, required this.child});
  final Widget child;

  static ValueNotifier<double> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Horloge>()!.temps;

  @override
  State<HorlogeFond> createState() => _HorlogeFondState();
}

class _HorlogeFondState extends State<HorlogeFond> with SingleTickerProviderStateMixin {
  static const _pas = 1 / 30; // 30 images par seconde suffisent pour un mouvement aussi lent
  final _temps = ValueNotifier<double>(4);
  late final Ticker _ticker = createTicker((ecoule) {
    final t = 4 + ecoule.inMicroseconds / 1e6;
    if (t - _temps.value >= _pas) _temps.value = t;
  });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final fige = MediaQuery.of(context).disableAnimations;
    if (fige && _ticker.isActive) _ticker.stop();
    if (!fige && !_ticker.isActive) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _temps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Horloge(temps: _temps, child: widget.child);
}

class _Horloge extends InheritedWidget {
  const _Horloge({required this.temps, required super.child});
  final ValueNotifier<double> temps;

  @override
  bool updateShouldNotify(_Horloge old) => old.temps != temps;
}

/// Le fond animé du thème actif, sous les écrans principaux.
class FondAnime extends StatelessWidget {
  const FondAnime({super.key, required this.theme});
  final OptiTheme theme;

  @override
  Widget build(BuildContext context) {
    final c = context.couleurs;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _PeintreFond(theme, c.sombre, HorlogeFond.of(context)),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PeintreFond extends CustomPainter {
  _PeintreFond(this.theme, this.sombre, this.temps) : super(repaint: temps);
  final OptiTheme theme;
  final bool sombre;
  final ValueNotifier<double> temps;

  @override
  void paint(Canvas canvas, Size taille) {
    final t = temps.value;
    switch ((theme, sombre)) {
      case (OptiTheme.holocron, _):
        peindreHolocron(canvas, taille, t, sombre);
      case (OptiTheme.foret, _):
        peindreForet(canvas, taille, t, sombre);
      case (OptiTheme.ocean, _):
        peindreOcean(canvas, taille, t, sombre);
    }
  }

  @override
  bool shouldRepaint(_PeintreFond old) => old.theme != theme || old.sombre != sombre;
}
