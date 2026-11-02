/// Fond du thème Forêt : une vallée de montagne façon peinture d'animation (d'après l'image de référence de
/// Mohamed, scène originale, nature seulement : choix du 01/11/2026) : ciel et gros nuages, deux sommets enneigés,
/// brume, collines, lac turquoise, sapins au premier plan. La nuit (mode sombre) : ciel étoilé, lune, lucioles.
/// Dessiné dans les coordonnées 390 × 774 (la barre du bas en moins), puis mis à l'échelle.
library;

import 'dart:math';

import 'package:flutter/material.dart';

const _largeur = 390.0, _hauteur = 774.0;
const _nuitProfonde = Color(0xFF0A1424);

/// La nuit, chaque couleur glisse vers le bleu de la nuit.
Color _c(int argb, bool nuit, [double vers = .55]) =>
    nuit ? Color.lerp(Color(argb), _nuitProfonde, vers)! : Color(argb);

Paint _p(int argb, bool nuit, [double vers = .55]) => Paint()..color = _c(argb, nuit, vers);

double _boucle(double t, double duree, [double decalage = 0]) => ((t + decalage) / duree) % 1;

void peindreForet(Canvas canvas, Size taille, double t, bool nuit) {
  canvas.save();
  canvas.scale(taille.width / _largeur, taille.height / _hauteur);
  _ciel(canvas, t, nuit);
  _nuages(canvas, t, nuit);
  _montagnes(canvas, nuit);
  _brume(canvas, t, nuit, 300);
  _collines(canvas, nuit);
  _lac(canvas, t, nuit);
  _prairie(canvas, nuit);
  _sapins(canvas, t, nuit);
  if (nuit) _lucioles(canvas, t);
  canvas.restore();
}

void _ciel(Canvas canvas, double t, bool nuit) {
  const zone = Rect.fromLTWH(0, 0, _largeur, 420);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, _largeur, _hauteur),
    Paint()..color = nuit ? const Color(0xFF16284A) : const Color(0xFFDDEFFC),
  );
  canvas.drawRect(
    zone,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: nuit
            ? const [Color(0xFF070F22), Color(0xFF0F1E3D), Color(0xFF1C3358)]
            : const [Color(0xFF3D8FE0), Color(0xFF8EC5F2), Color(0xFFDDEFFC)],
        stops: const [0, .55, 1],
      ).createShader(zone),
  );
  if (!nuit) return;
  // Lune et étoiles.
  canvas.drawCircle(const Offset(312, 78), 34, Paint()..color = const Color(0x1FF5F1D6));
  canvas.drawCircle(const Offset(312, 78), 20, Paint()..color = const Color(0xF2F5F1D6));
  final r = Random(3), p = Paint();
  for (var i = 0; i < 60; i++) {
    final x = r.nextDouble() * _largeur, y = r.nextDouble() * 230, phase = r.nextDouble();
    final eclat = .25 + .75 * (.5 + .5 * sin((t * (.2 + r.nextDouble() * .6) + phase) * 2 * pi));
    canvas.drawCircle(Offset(x, y), .5 + r.nextDouble() * .9, p..color = Colors.white.withValues(alpha: eclat));
  }
}

/// Gros nuage peint : des bulles blanches, ombrées en dessous.
void _nuage(Canvas canvas, double x, double y, double echelle, bool nuit) {
  const bulles = [(0.0, 18.0, 22.0), (26.0, 4.0, 30.0), (60.0, 10.0, 26.0), (88.0, 22.0, 20.0), (40.0, 26.0, 24.0)];
  final ombre = Paint()..color = nuit ? const Color(0x553A4A6E) : const Color(0xFFC9CDEB);
  final blanc = Paint()..color = nuit ? const Color(0x667F8FB0) : Colors.white;
  for (final (bx, by, r) in bulles) {
    canvas.drawCircle(Offset(x + bx * echelle, y + (by + 6) * echelle), r * echelle, ombre);
  }
  for (final (bx, by, r) in bulles) {
    canvas.drawCircle(Offset(x + bx * echelle, y + by * echelle), r * echelle * .94, blanc);
  }
}

void _nuages(Canvas canvas, double t, bool nuit) {
  for (final (y, echelle, duree, decalage) in const [
    (30.0, 1.1, 90.0, 0.0),
    (95.0, .8, 70.0, 35.0),
    (150.0, 1.3, 120.0, 70.0),
    (210.0, .7, 80.0, 10.0),
  ]) {
    final x = 430 - 600 * _boucle(t, duree, decalage);
    _nuage(canvas, x, y, echelle, nuit);
  }
}

void _montagnes(Canvas canvas, bool nuit) {
  // Sommet secondaire (droite), derrière.
  final second = Path()
    ..moveTo(170, 400)
    ..lineTo(300, 175)
    ..lineTo(318, 196)
    ..lineTo(332, 170)
    ..lineTo(430, 400)
    ..close();
  canvas.drawPath(second, _p(0xFFE6ECF6, nuit, .5));
  canvas.drawPath(
    Path()
      ..moveTo(318, 196)
      ..lineTo(332, 170)
      ..lineTo(430, 400)
      ..lineTo(330, 400)
      ..close(),
    _p(0xFFC3CCE2, nuit, .5),
  );
  // Grand sommet (gauche).
  final grand = Path()
    ..moveTo(-60, 410)
    ..lineTo(150, 110)
    ..lineTo(330, 410)
    ..close();
  canvas.drawPath(grand, _p(0xFFF4F7FB, nuit, .5));
  canvas.drawPath(
    Path()
      ..moveTo(150, 110)
      ..lineTo(330, 410)
      ..lineTo(175, 410)
      ..lineTo(168, 240)
      ..close(),
    _p(0xFFCBD4E8, nuit, .5),
  );
  // Rochers apparents.
  final roche = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..color = _c(0xFF9C8F86, nuit, .5);
  for (final (x1, y1, x2, y2, e) in const [
    (140.0, 140.0, 118.0, 190.0, 4.0),
    (110.0, 210.0, 86.0, 262.0, 5.0),
    (160.0, 175.0, 150.0, 230.0, 3.0),
    (200.0, 220.0, 222.0, 270.0, 4.0),
    (300.0, 200.0, 286.0, 238.0, 3.0),
    (70.0, 290.0, 50.0, 330.0, 5.0),
  ]) {
    canvas.drawLine(Offset(x1, y1), Offset(x2, y2), roche..strokeWidth = e);
  }
}

/// Bande de brume blanche qui ondule doucement.
void _brume(Canvas canvas, double t, bool nuit, double y) {
  final p = Paint()
    ..color = (nuit ? const Color(0xFF9FB0D0) : Colors.white).withValues(alpha: nuit ? .18 : .55)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
  for (var i = 0; i < 6; i++) {
    final x = (i * 80 + 30 * sin(t * .12 + i)) - 20;
    canvas.drawOval(Rect.fromCenter(center: Offset(x, y + 10 * sin(i * 1.7)), width: 140, height: 34), p);
  }
}

void _collines(Canvas canvas, bool nuit) {
  // Collines lointaines (vert pâle), puis la grande pente de droite.
  canvas.drawPath(
    Path()
      ..moveTo(0, 360)
      ..cubicTo(70, 330, 130, 380, 200, 372)
      ..cubicTo(260, 366, 320, 340, 390, 330)
      ..lineTo(390, 480)
      ..lineTo(0, 480)
      ..close(),
    _p(0xFFA9D27A, nuit),
  );
  canvas.drawPath(
    Path()
      ..moveTo(150, 470)
      ..cubicTo(230, 420, 300, 330, 390, 270)
      ..lineTo(390, 480)
      ..close(),
    _p(0xFF7DBB52, nuit),
  );
  // Bande de terre rose sur la pente.
  canvas.drawPath(
    Path()
      ..moveTo(260, 410)
      ..cubicTo(300, 380, 340, 345, 390, 320)
      ..lineTo(390, 336)
      ..cubicTo(345, 362, 305, 395, 268, 422)
      ..close(),
    _p(0xFFD4927F, nuit),
  );
  // Petite colline du milieu.
  canvas.drawPath(
    Path()
      ..moveTo(110, 480)
      ..cubicTo(140, 440, 170, 420, 200, 430)
      ..cubicTo(225, 440, 245, 465, 270, 480)
      ..close(),
    _p(0xFF6FAE48, nuit),
  );
}

void _lac(Canvas canvas, double t, bool nuit) {
  canvas.drawRect(const Rect.fromLTWH(0, 476, _largeur, 22), _p(0xFF4CC3E8, nuit, .5));
  final reflet = Paint()
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round;
  for (var i = 0; i < 9; i++) {
    final x = 20.0 + i * 42, y = 482.0 + (i % 3) * 5;
    final eclat = .5 + .5 * sin(t * 1.4 + i * 1.9);
    canvas.drawLine(Offset(x, y), Offset(x + 10, y), reflet..color = Colors.white.withValues(alpha: .6 * eclat));
  }
  if (nuit) {
    // Reflet de la lune.
    canvas.drawLine(
      const Offset(300, 480),
      const Offset(324, 480),
      Paint()
        ..strokeWidth = 3
        ..color = const Color(0x99F5F1D6),
    );
  }
}

void _prairie(Canvas canvas, bool nuit) {
  const zone = Rect.fromLTWH(0, 494, _largeur, _hauteur - 494);
  canvas.drawPath(
    Path()
      ..moveTo(0, 500)
      ..cubicTo(90, 490, 200, 506, 390, 494)
      ..lineTo(390, _hauteur)
      ..lineTo(0, _hauteur)
      ..close(),
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_c(0xFF6DB34C, nuit), _c(0xFF3F8A35, nuit)],
      ).createShader(zone),
  );
  // Chemin de terre.
  canvas.drawPath(
    Path()
      ..moveTo(140, _hauteur)
      ..cubicTo(170, 690, 230, 640, 300, 600)
      ..cubicTo(330, 584, 360, 576, 390, 572)
      ..lineTo(390, 584)
      ..cubicTo(350, 592, 300, 612, 262, 646)
      ..cubicTo(220, 684, 200, 730, 196, _hauteur)
      ..close(),
    _p(0xFFB98B5E, nuit),
  );
  // Quelques pierres.
  for (final (x, y, l, h) in const [(30.0, 700.0, 26.0, 14.0), (330.0, 740.0, 34.0, 16.0), (250.0, 560.0, 18.0, 9.0)]) {
    canvas.drawOval(Rect.fromLTWH(x, y, l, h), _p(0xFFAEB7C0, nuit, .5));
  }
}

/// Sapin : trois étages de triangles, qui se balancent très légèrement au vent.
void _sapin(Canvas canvas, double x, double base, double hauteur, double t, double phase, bool nuit) {
  canvas.save();
  canvas.translate(x, base);
  canvas.rotate(1.5 * pi / 180 * sin(t * .7 + phase));
  final sombre = _p(0xFF2F6B3A, nuit, .5), clair = _p(0xFF3E8448, nuit, .5);
  canvas.drawRect(Rect.fromLTWH(-hauteur * .03, -hauteur * .12, hauteur * .06, hauteur * .12), _p(0xFF5B4030, nuit));
  for (var i = 0; i < 3; i++) {
    final bas = -hauteur * (.1 + i * .26), haut = bas - hauteur * .42, demi = hauteur * (.24 - i * .055);
    canvas.drawPath(
      Path()
        ..moveTo(-demi, bas)
        ..lineTo(0, haut)
        ..lineTo(demi, bas)
        ..close(),
      sombre,
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, haut)
        ..lineTo(demi, bas)
        ..lineTo(demi * .3, bas)
        ..close(),
      clair,
    );
  }
  canvas.restore();
}

void _sapins(Canvas canvas, double t, bool nuit) {
  for (final (x, base, h) in const [
    (300.0, 470.0, 46.0),
    (320.0, 476.0, 38.0),
    (64.0, 482.0, 40.0),
    (20.0, 640.0, 120.0),
    (290.0, 680.0, 160.0),
    (338.0, 700.0, 130.0),
    (372.0, 660.0, 96.0),
  ]) {
    _sapin(canvas, x, base, h, t, x / 40, nuit);
  }
}

void _lucioles(Canvas canvas, double t) {
  final r = Random(5);
  for (var i = 0; i < 14; i++) {
    final x0 = r.nextDouble() * _largeur, y0 = 540 + r.nextDouble() * 220, phase = r.nextDouble() * 2 * pi;
    final centre = Offset(x0 + 14 * sin(t * .4 + phase), y0 + 10 * cos(t * .5 + phase));
    final eclat = max(0.0, sin(t * (.8 + r.nextDouble()) + phase));
    if (eclat < .05) continue;
    canvas.drawCircle(
      centre,
      7,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFE8F57A).withValues(alpha: .5 * eclat),
            const Color(0x00E8F57A),
          ],
        ).createShader(Rect.fromCircle(center: centre, radius: 7)),
    );
    canvas.drawCircle(centre, 1.6, Paint()..color = const Color(0xFFF6FFB0).withValues(alpha: eclat));
  }
}
