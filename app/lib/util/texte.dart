/// Texte simplifié pour les recherches : minuscules, sans accents (« Écouteurs » → « ecouteurs »).
String texteSimple(String texte) {
  const avec = 'àâäéèêëîïôöùûüçœ', sans = 'aaaeeeeiioouuuco';
  return String.fromCharCodes([
    for (final r in texte.toLowerCase().runes)
      avec.contains(String.fromCharCode(r)) ? sans.codeUnitAt(avec.indexOf(String.fromCharCode(r))) : r,
  ]);
}

/// Vrai si chaque mot cherché apparaît dans le texte, sans tenir compte des majuscules ni des accents.
bool correspond(String cherche, String texte) {
  final dans = texteSimple(texte);
  return texteSimple(cherche).split(' ').where((m) => m.isNotEmpty).every(dans.contains);
}
