/// Fond du thème Holocron : un ciel d'étoiles (choix de Mohamed le 01/11/2026, d'après son image de référence).
/// Sombre : presque noir, voile violet très discret et petite lueur dorée en haut ; ~150 points blancs qui
/// scintillent, ~25 étoiles en croix bleues qui brillent puis s'éteignent, une étoile filante de temps en temps.
/// Clair : ciel crème, lueur dorée, croix violettes et framboise, petits points violets (plus foncés que la crème).
library;

import 'dart:math';

import 'package:flutter/material.dart';

class _Hasard {
  _Hasard(this._s);
  int _s;
  double call() => (_s = (_s * 16807) % 2147483647) / 2147483647;
}

class _Point {
  _Point(_Hasard r) : x = r(), y = r(), taille = .35 + r() * 1.1, phase = r(), vitesse = .15 + r() * .6;
  final double x, y, taille, phase, vitesse;
}

class _Croix {
  _Croix(_Hasard r) : x = r(), y = r(), taille = 3 + r() * 5, phase = r(), periode = 3 + r() * 5;
  final double x, y, taille, phase, periode;
}

final _points = () {
  final r = _Hasard(7);
  return [for (var i = 0; i < 150; i++) _Point(r)];
}();

final _croix = () {
  final r = _Hasard(17);
  return [for (var i = 0; i < 25; i++) _Croix(r)];
}();

const _bleu = Color(0xFF7DD3FC);
// En clair, des étoiles plus foncées que la crème (le doré pâle s'y perdait) : violet profond et framboise.
const _violet = Color(0xFF6D3FD8), _framboise = Color(0xFFD42A7C);

void peindreHolocron(Canvas canvas, Size s, double t, bool sombre) {
  final w = s.width, h = s.height, zone = Offset.zero & s;
  final respire = .5 + .5 * sin(t * .3);

  if (sombre) {
    canvas.drawRect(zone, Paint()..color = const Color(0xFF07050F));
    // Voile violet très discret, un peu plus présent en bas.
    canvas.drawRect(
      zone,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(.3, .6),
          radius: 1.1,
          colors: [const Color(0xFF6B3FD6).withValues(alpha: .14), const Color(0xFF6B3FD6).withValues(alpha: 0)],
        ).createShader(zone),
    );
    // Petite lueur dorée en haut, qui respire.
    _lueur(canvas, zone, Offset(w * .5, -h * .02), w * (.55 + .05 * respire), [
      Color.fromRGBO(255, 196, 110, .20 + .06 * respire),
      const Color.fromRGBO(214, 140, 90, .06),
      const Color.fromRGBO(214, 140, 90, 0),
    ]);
  } else {
    canvas.drawRect(
      zone,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFAF3), Color(0xFFFCEBD9)],
        ).createShader(zone),
    );
    _lueur(canvas, zone, Offset(w * .5, h * .12), w * (.6 + .05 * respire), [
      Color.fromRGBO(252, 214, 140, .45 + .1 * respire),
      const Color.fromRGBO(252, 214, 140, .12),
      const Color.fromRGBO(252, 214, 140, 0),
    ]);
  }

  // Petits points : blancs la nuit, violet doux sur la crème (un sur deux seulement, pour rester discret).
  final echelle = w / 390;
  final p = Paint();
  for (final (i, e) in _points.indexed) {
    if (!sombre && i.isOdd) continue;
    final eclat = .25 + .75 * (.5 + .5 * sin((t * e.vitesse + e.phase) * 2 * pi));
    final couleur = sombre ? Colors.white : _violet.withValues(alpha: .55);
    canvas.drawCircle(
      Offset(e.x * w, e.y * h),
      e.taille * echelle * (sombre ? 1 : 1.2),
      p..color = couleur.withValues(alpha: couleur.a * eclat),
    );
  }

  // Étoiles en croix : elles grossissent, brillent, puis s'éteignent.
  for (final (i, c) in _croix.indexed) {
    final couleur = sombre ? _bleu : (i.isEven ? _violet : _framboise);
    final cycle = sin(((t / c.periode) + c.phase) * 2 * pi);
    final eclat = max(0.0, cycle); // la moitié du temps éteinte
    if (eclat < .02) continue;
    _croixEtoile(
      canvas,
      Offset(c.x * w, c.y * h),
      c.taille * echelle * (.6 + .4 * eclat),
      couleur,
      eclat * (sombre ? 1 : .8),
    );
  }

  if (sombre) _etoileFilante(canvas, s, t);
}

void _lueur(Canvas canvas, Rect zone, Offset centre, double rayon, List<Color> couleurs) {
  canvas.drawRect(
    zone,
    Paint()
      ..shader = RadialGradient(
        colors: couleurs,
        stops: const [0, .45, 1],
      ).createShader(Rect.fromCircle(center: centre, radius: rayon)),
  );
}

/// Étoile à 4 branches fines, avec un petit halo.
void _croixEtoile(Canvas canvas, Offset centre, double rayon, Color couleur, double opacite) {
  canvas.drawCircle(
    centre,
    rayon * 1.4,
    Paint()
      ..shader = RadialGradient(
        colors: [
          couleur.withValues(alpha: .35 * opacite),
          couleur.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: centre, radius: rayon * 1.4)),
  );
  final fin = rayon * .16;
  final branches = Path()
    ..moveTo(centre.dx, centre.dy - rayon)
    ..lineTo(centre.dx + fin, centre.dy - fin)
    ..lineTo(centre.dx + rayon, centre.dy)
    ..lineTo(centre.dx + fin, centre.dy + fin)
    ..lineTo(centre.dx, centre.dy + rayon)
    ..lineTo(centre.dx - fin, centre.dy + fin)
    ..lineTo(centre.dx - rayon, centre.dy)
    ..lineTo(centre.dx - fin, centre.dy - fin)
    ..close();
  canvas.drawPath(branches, Paint()..color = couleur.withValues(alpha: opacite));
  canvas.drawCircle(centre, fin * 1.2, Paint()..color = Colors.white.withValues(alpha: opacite));
}

/// Une étoile filante toutes les 30 s environ, visible moins d'une seconde.
void _etoileFilante(Canvas canvas, Size s, double t) {
  const periode = 30.0, duree = .9;
  final numero = (t / periode).floor();
  final r = _Hasard(1000 + numero);
  final depart = r() * (periode - duree);
  final p = t - numero * periode - depart;
  if (p < 0 || p > duree) return;
  final avance = p / duree;
  final debut = Offset(s.width * (.15 + .6 * r()), s.height * (.05 + .3 * r()));
  final direction = Offset(s.width * .35, s.height * .12);
  final tete = debut + direction * avance;
  final queue = tete - direction * .35;
  final opacite = sin(avance * pi);
  canvas.drawLine(
    queue,
    tete,
    Paint()
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: opacite),
        ],
      ).createShader(Rect.fromPoints(queue, tete)),
  );
}
