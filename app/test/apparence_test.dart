import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opti/data/apparence.dart';

double luminance(Color c) => .2126 * c.r + .7152 * c.g + .0722 * c.b;

void main() {
  test("l'accent tiré d'une image sombre est éclairci en mode sombre", () {
    final bleuNuit = accentLisible(const Color(0xFF1A2A6C), Brightness.dark);
    expect(luminance(bleuNuit), closeTo(.55, .01));
  });

  test("l'accent tiré d'une image claire est assombri en mode clair", () {
    final jaune = accentLisible(const Color(0xFFFFE066), Brightness.light);
    expect(luminance(jaune), closeTo(.40, .01));
  });

  test('une couleur déjà lisible reste telle quelle', () {
    const violet = Color(0xFFA67CF8);
    expect(accentLisible(violet, Brightness.dark), violet);
  });

  test("les réglages d'apparence survivent à l'enregistrement", () {
    const a = Apparence(
      fond: Fond.image,
      image: 'fond_1.jpg',
      flou: 12,
      voile: .4,
      accentImage: true,
      couleurImage: 0xFF336699,
    );
    final b = Apparence.depuisJson(a.enJson());
    expect(
      (b.fond, b.image, b.flou, b.voile, b.accentImage, b.couleurImage),
      (Fond.image, 'fond_1.jpg', 12.0, .4, true, 0xFF336699),
    );
  });
}
