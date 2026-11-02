/// Fond du thème Océan : l'aquarium de la maquette « Thème océan – Accueil aquarium » (ciel, vagues, rayons,
/// rochers, algues, corail, éponge, sable, bulles, 3 poissons), en plein jour ou la nuit (mode sombre).
/// Dessiné dans les coordonnées de la maquette (390 × 774, la barre du bas en moins), puis mis à l'échelle.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

const _largeur = 390.0, _hauteur = 774.0;
const _abysse = Color(0xFF04121F);

/// La nuit, chaque couleur glisse vers le bleu des abysses.
Color _c(int argb, bool nuit, [double vers = .45]) => nuit ? Color.lerp(Color(argb), _abysse, vers)! : Color(argb);

void peindreOcean(Canvas canvas, Size taille, double t, bool nuit) {
  canvas.save();
  canvas.scale(taille.width / _largeur, taille.height / _hauteur);
  _eau(canvas, nuit);
  if (nuit) {
    _lune(canvas, t);
  } else {
    _nuages(canvas, t);
  }
  _vagues(canvas, t, nuit);
  _rayons(canvas, t, nuit);
  _rochers(canvas, nuit);
  _fond(canvas, t, nuit);
  _bulles(canvas, t, nuit);
  _poissons(canvas, t, nuit);
  canvas.restore();
}

double _boucle(double t, double duree, [double decalage = 0]) => ((t + decalage) / duree) % 1;

void _eau(Canvas canvas, bool nuit) {
  final couleurs = nuit
      ? const [0xFF0A1A33, 0xFF16305A, 0xFF1B5E7A, 0xFF134E6E, 0xFF0E3B5C, 0xFF0A2B47, 0xFF061A2E]
      : const [0xFF7FD3F7, 0xFFB9E9FB, 0xFF5FE0E6, 0xFF2FB9D6, 0xFF1E8EC2, 0xFF17679F, 0xFF144E86];
  const arrets = [0.0, 96 / 844, 100 / 844, 260 / 844, 480 / 844, 680 / 844, 1.0];
  const zone = Rect.fromLTWH(0, 0, _largeur, _hauteur);
  canvas.drawRect(
    zone,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [for (final c in couleurs) Color(c)],
        stops: arrets,
      ).createShader(zone),
  );
}

void _nuages(Canvas canvas, double t) {
  final p = Paint()..color = Colors.white;
  for (final (haut, l, h, opacite, duree, decalage) in const [
    (18.0, 90.0, 26.0, .85, 40.0, 0.0),
    (46.0, 130.0, 32.0, .7, 55.0, 20.0),
  ]) {
    final x = 420 - 620 * _boucle(t, duree, decalage);
    canvas.drawRRect(
      RRect.fromLTRBR(x, haut, x + l, haut + h, Radius.circular(h / 2)),
      p..color = Colors.white.withValues(alpha: opacite),
    );
  }
}

/// La nuit : une lune et quelques étoiles au-dessus de l'eau.
void _lune(Canvas canvas, double t) {
  canvas.drawCircle(const Offset(318, 42), 26, Paint()..color = const Color(0x22F5F1D6));
  canvas.drawCircle(const Offset(318, 42), 17, Paint()..color = const Color(0xE6F5F1D6));
  final p = Paint();
  for (final (x, y, r, phase) in const [
    (30.0, 22.0, 1.2, .1),
    (72.0, 58.0, .9, .5),
    (118.0, 16.0, 1.1, .8),
    (160.0, 50.0, .8, .3),
    (205.0, 26.0, 1.3, .65),
    (250.0, 68.0, .9, .15),
    (372.0, 18.0, 1.0, .9),
    (360.0, 74.0, .8, .4),
  ]) {
    final eclat = .3 + .7 * (.5 + .5 * sin((t * .6 + phase) * 2 * pi));
    canvas.drawCircle(Offset(x, y), r, p..color = Colors.white.withValues(alpha: eclat));
  }
}

/// Une vague de période 195 px, sur 780 px de large, décalée de `decalage`.
Path _vague(double x0, double haut, double base, double creux, double crete) {
  final chemin = Path()..moveTo(x0, haut + base);
  for (var i = 0; i < 8; i++) {
    final xs = x0 + i * 97.5;
    chemin.quadraticBezierTo(xs + 48.75, haut + (i.isEven ? crete : creux), xs + 97.5, haut + base);
  }
  return chemin;
}

void _vagues(Canvas canvas, double t, bool nuit) {
  final x1 = -195 * _boucle(t, 6);
  final ligne1 = _vague(x1, 86, 12, 24, 0);
  final plein = Path.from(ligne1)
    ..lineTo(x1 + 780, 110)
    ..lineTo(x1, 110)
    ..close();
  canvas.drawPath(plein, Paint()..color = _c(0xFF5FE0E6, nuit, .55));
  canvas.drawPath(
    ligne1,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = (nuit ? const Color(0xFF9CC3D5) : Colors.white).withValues(alpha: nuit ? .45 : .9),
  );
  final x2 = -195 * (1 - _boucle(t, 9));
  canvas.drawPath(
    _vague(x2, 100, 8, 0, 16),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFE6FBFF).withValues(alpha: nuit ? .2 : .5),
  );
}

void _rayons(Canvas canvas, double t, bool nuit) {
  for (final (gauche, l, h, flou, duree, decalage) in const [
    (20.0, 46.0, 560.0, 4.0, 6.0, 0.0),
    (130.0, 80.0, 640.0, 6.0, 8.0, 3.0),
    (270.0, 36.0, 500.0, 4.0, 6.0, 2.0),
  ]) {
    final opacite = (.10 + .16 * (.5 - .5 * cos(2 * pi * _boucle(t, duree, decalage)))) * (nuit ? .35 : 1);
    final zone = Rect.fromLTWH(0, 0, l, h);
    canvas.save();
    // skewX(-14deg) autour du centre, comme en CSS.
    canvas.translate(gauche + l / 2, 100 + h / 2);
    canvas.transform(Float64List.fromList([1, 0, 0, 0, tan(-14 * pi / 180), 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));
    canvas.translate(-l / 2, -h / 2);
    canvas.drawRect(
      zone,
      Paint()
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, flou / 2)
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: opacite),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(zone),
    );
    canvas.restore();
  }
}

void _rochers(Canvas canvas, bool nuit) {
  canvas.save();
  canvas.translate(0, _hauteur - 230);
  final arriere = Path()
    ..moveTo(0, 120)
    ..cubicTo(30, 90, 50, 110, 70, 80)
    ..cubicTo(90, 50, 110, 90, 140, 70)
    ..cubicTo(170, 50, 190, 100, 220, 80)
    ..cubicTo(250, 60, 270, 30, 300, 60)
    ..cubicTo(330, 90, 360, 70, 390, 50)
    ..lineTo(390, 230)
    ..lineTo(0, 230)
    ..close();
  canvas.drawPath(arriere, Paint()..color = _c(0xFF2B6FA8, nuit).withValues(alpha: .55));
  final avant = Path()
    ..moveTo(0, 170)
    ..cubicTo(40, 150, 60, 160, 90, 140)
    ..cubicTo(120, 120, 150, 160, 190, 150)
    ..cubicTo(230, 140, 260, 120, 300, 140)
    ..cubicTo(340, 160, 370, 140, 390, 130)
    ..lineTo(390, 230)
    ..lineTo(0, 230)
    ..close();
  canvas.drawPath(avant, Paint()..color = _c(0xFF1F5C93, nuit).withValues(alpha: .8));
  canvas.restore();
}

Paint _trait(int couleur, double epaisseur, bool nuit) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeWidth = epaisseur
  ..color = _c(couleur, nuit);

/// Algue qui se balance autour de son pied (± 4°).
void _algue(Canvas canvas, Offset coin, Size taille, double t, double duree, double decalage, void Function() dessin) {
  final angle = 4 * pi / 180 * -cos(2 * pi * _boucle(t, duree, decalage));
  canvas.save();
  canvas.translate(coin.dx + taille.width / 2, coin.dy + taille.height);
  canvas.rotate(angle);
  canvas.translate(-taille.width / 2, -taille.height);
  dessin();
  canvas.restore();
}

void _fond(Canvas canvas, double t, bool nuit) {
  // Algue verte (gauche).
  _algue(canvas, const Offset(6, _hauteur - 140), const Size(40, 120), t, 4, 0, () {
    canvas.drawPath(
      Path()
        ..moveTo(20, 120)
        ..cubicTo(10, 90, 30, 70, 18, 45)
        ..cubicTo(8, 25, 26, 12, 20, 0),
      _trait(0xFF3FD48A, 8, nuit),
    );
    canvas.drawPath(
      Path()
        ..moveTo(24, 120)
        ..cubicTo(34, 95, 16, 80, 30, 58),
      _trait(0xFF2FB873, 7, nuit),
    );
  });

  // Corail rose.
  canvas.save();
  canvas.translate(52, _hauteur - 96);
  final corail = _trait(0xFFFF7A9A, 9, nuit);
  canvas.drawPath(
    Path()
      ..moveTo(45, 80)
      ..lineTo(45, 50)
      ..moveTo(45, 52)
      ..cubicTo(30, 40, 20, 30, 22, 10)
      ..moveTo(45, 50)
      ..cubicTo(60, 38, 72, 28, 68, 6)
      ..moveTo(45, 60)
      ..cubicTo(38, 50, 30, 48, 14, 46)
      ..moveTo(45, 58)
      ..cubicTo(54, 50, 64, 50, 80, 44),
    corail,
  );
  final bout = Paint()..color = _c(0xFFFFA3B8, nuit);
  for (final (x, y, r) in const [(22.0, 10.0, 6.0), (68.0, 6.0, 6.0), (14.0, 46.0, 5.0), (80.0, 44.0, 5.0)]) {
    canvas.drawCircle(Offset(x, y), r, bout);
  }
  canvas.restore();

  // Éponge orange.
  canvas.save();
  canvas.translate(150, _hauteur - 68);
  canvas.drawOval(
    Rect.fromCenter(center: const Offset(40, 34), width: 76, height: 40),
    Paint()..color = _c(0xFFFFB347, nuit),
  );
  final trou = Paint()..color = _c(0xFFFFD27F, nuit);
  for (final (x, y) in const [(22.0, 28.0), (38.0, 22.0), (54.0, 28.0), (30.0, 38.0), (48.0, 40.0)]) {
    canvas.drawCircle(Offset(x, y), 4, trou);
  }
  canvas.restore();

  // Rochers violets.
  canvas.save();
  canvas.translate(236, _hauteur - 86);
  canvas.drawCircle(const Offset(20, 50), 18, Paint()..color = _c(0xFFA98BFF, nuit));
  canvas.drawCircle(const Offset(44, 44), 22, Paint()..color = _c(0xFFB9A0FF, nuit));
  canvas.drawCircle(const Offset(56, 58), 12, Paint()..color = _c(0xFFA98BFF, nuit));
  canvas.restore();

  // Algue turquoise (droite).
  _algue(canvas, const Offset(338, _hauteur - 130), const Size(44, 110), t, 5, 2, () {
    canvas.drawPath(
      Path()
        ..moveTo(22, 110)
        ..cubicTo(12, 85, 32, 65, 20, 40)
        ..cubicTo(12, 22, 28, 10, 24, 0),
      _trait(0xFF2FD3C0, 8, nuit),
    );
  });

  // Sable.
  canvas.save();
  canvas.translate(0, _hauteur - 30);
  final crete = Path()
    ..moveTo(0, 14)
    ..cubicTo(60, 4, 120, 20, 190, 12)
    ..cubicTo(260, 4, 320, 18, 390, 10);
  canvas.drawPath(
    Path.from(crete)
      ..lineTo(390, 30)
      ..lineTo(0, 30)
      ..close(),
    Paint()..color = _c(0xFFF3D79A, nuit),
  );
  canvas.drawPath(crete, _trait(0xFFFFE9B8, 3, nuit));
  canvas.restore();
}

double _accelere(double x) => pow(x, 1.7).toDouble(); // « ease-in » du CSS, à peu près

void _bulles(Canvas canvas, double t, bool nuit) {
  for (final (x, y, taille, duree, decalage) in const [
    (30.0, 710.0, 12.0, 8.0, 0.0),
    (196.0, 730.0, 18.0, 11.0, 4.0),
    (340.0, 720.0, 9.0, 7.0, 2.0),
    (120.0, 740.0, 14.0, 10.0, 7.0),
  ]) {
    final p = _boucle(t, duree, decalage);
    final (dx, dy) = p < .5
        ? (8 * (p / .5), -360 * _accelere(p / .5))
        : (8 - 14 * ((p - .5) / .5), -360 - 360 * _accelere((p - .5) / .5));
    final opacite = (p < .1 ? .9 * p / .1 : .9 * (1 - (p - .1) / .9)) * (nuit ? .6 : 1);
    final centre = Offset(x + taille / 2 + dx, y + taille / 2 + dy);
    canvas.drawCircle(centre, taille / 2, Paint()..color = Colors.white.withValues(alpha: .25 * opacite));
    canvas.drawCircle(
      centre,
      taille / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFE6FBFF).withValues(alpha: opacite),
    );
  }
}

void _poissons(Canvas canvas, double t, bool nuit) {
  final ondule = 2 * pi * _boucle(t, 1.4);
  void nager(double x, double y, double largeur, double hauteur, bool versGauche, void Function(Canvas) dessin) {
    canvas.save();
    canvas.translate(x + largeur / 2, y + hauteur / 2 - 3 * (1 - cos(ondule)));
    canvas.rotate(-2 * pi / 180 * cos(ondule));
    if (versGauche) canvas.scale(-1, 1);
    canvas.translate(-largeur / 2, -hauteur / 2);
    dessin(canvas);
    canvas.restore();
  }

  Paint plein(int c) => Paint()..color = _c(c, nuit, .3);
  Paint raie(int c, double e, [double opacite = 1]) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = e
    ..color = _c(c, nuit, .3).withValues(alpha: opacite);
  void oeil(Canvas c, Offset blanc, double r, Offset pupille, double rp) {
    c.drawCircle(blanc, r, Paint()..color = Colors.white);
    c.drawCircle(pupille, rp, Paint()..color = const Color(0xFF0B2545));
  }

  // Poisson jaune rayé, vers la droite (16 s).
  nager(-90 + 570 * _boucle(t, 16), 330, 58, 34, false, (c) {
    c.drawPath(
      Path()
        ..moveTo(10, 17)
        ..lineTo(0, 6)
        ..lineTo(2, 17)
        ..lineTo(0, 28)
        ..close(),
      plein(0xFFFFC23D),
    );
    c.drawOval(Rect.fromCenter(center: const Offset(30, 17), width: 44, height: 28), plein(0xFFFFD23F));
    c.drawPath(
      Path()
        ..moveTo(24, 4)
        ..cubicTo(26, 12, 26, 22, 24, 30),
      raie(0xFF2B7FE0, 5),
    );
    c.drawPath(
      Path()
        ..moveTo(36, 5)
        ..cubicTo(38, 12, 38, 22, 36, 29),
      raie(0xFF2B7FE0, 4),
    );
    oeil(c, const Offset(44, 13), 3.5, const Offset(45, 13), 2);
    c.drawOval(
      Rect.fromCenter(center: const Offset(30, 10), width: 20, height: 6),
      Paint()..color = Colors.white.withValues(alpha: .45),
    );
  });

  // Poisson violet, vers la gauche (21 s).
  nager(480 - 570 * _boucle(t, 21, 6), 520, 44, 30, true, (c) {
    c.drawPath(
      Path()
        ..moveTo(8, 15)
        ..lineTo(0, 5)
        ..lineTo(1, 15)
        ..lineTo(0, 25)
        ..close(),
      plein(0xFF7A5CFF),
    );
    c.drawOval(Rect.fromCenter(center: const Offset(24, 15), width: 34, height: 24), plein(0xFF9B7BFF));
    c.drawPath(
      Path()
        ..moveTo(18, 4)
        ..cubicTo(20, 10, 20, 20, 18, 26),
      raie(0xFFFFFFFF, 3, .8),
    );
    oeil(c, const Offset(33, 12), 3, const Offset(34, 12), 1.7);
  });

  // Petit poisson turquoise, vers la droite (26 s).
  nager(-90 + 570 * _boucle(t, 26, 14), 640, 36, 24, false, (c) {
    c.drawPath(
      Path()
        ..moveTo(7, 12)
        ..lineTo(0, 4)
        ..lineTo(1, 12)
        ..lineTo(0, 20)
        ..close(),
      plein(0xFF26C9A8),
    );
    c.drawOval(Rect.fromCenter(center: const Offset(20, 12), width: 28, height: 18), plein(0xFF3BE8C3));
    oeil(c, const Offset(27, 10), 2.5, const Offset(28, 10), 1.4);
  });
}
