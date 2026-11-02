import 'package:intl/intl.dart';

final _euros = NumberFormat.currency(locale: 'fr_FR', symbol: '€', decimalDigits: 2);

/// « 44,93 € », « −20,00 € » : format français, jamais « 44.93 € ».
String euros(num montant) => _euros.format(montant).replaceAll('-', '−');

/// « 520 € » quand le montant est rond (boutons, conseils), sinon « 520,50 € ».
String eurosCourts(num montant) =>
    montant == montant.roundToDouble() ? '${NumberFormat.decimalPattern('fr_FR').format(montant)} €' : euros(montant);

/// « +1 850,00 € » pour les entrées, « −5,30 € » pour les sorties.
String eurosSignes(num montant) => montant > 0 ? '+${euros(montant)}' : euros(montant);

/// « 26/10 ».
String jourMois(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

/// « il y a 3 h », « il y a 12 min », « hier ».
String ilYa(DateTime quand, {DateTime? maintenant}) {
  final ecart = (maintenant ?? DateTime.now()).difference(quand);
  if (ecart.inMinutes < 1) return "à l'instant";
  if (ecart.inMinutes < 60) return 'il y a ${ecart.inMinutes} min';
  if (ecart.inHours < 24) return 'il y a ${ecart.inHours} h';
  if (ecart.inDays == 1) return 'hier';
  return 'il y a ${ecart.inDays} jours';
}

const _mois = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

const _joursSemaine = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

/// « Aujourd'hui », « Hier », sinon « Lundi 27 octobre » (l'année seulement si ce n'est pas l'année en cours).
String titreJour(DateTime d, {DateTime? maintenant}) {
  final m = maintenant ?? DateTime.now();
  final jour = DateTime(d.year, d.month, d.day), auj = DateTime(m.year, m.month, m.day);
  final ecart = auj.difference(jour).inDays;
  if (ecart == 0) return "Aujourd'hui";
  if (ecart == 1) return 'Hier';
  final texte =
      '${_joursSemaine[d.weekday - 1]} ${d.day == 1 ? '1er' : d.day} ${_mois[d.month - 1]}'
      '${d.year != m.year ? ' ${d.year}' : ''}';
  return texte[0].toUpperCase() + texte.substring(1);
}

/// « 27 juillet 2027 » (sans dépendre des données de dates d'intl).
String dateLongue(DateTime d) => '${d.day == 1 ? '1er' : d.day} ${_mois[d.month - 1]} ${d.year}';

/// « 150 », « 150,5 », « 1 200,00 € » → 150.0 / 150.5 / 1200.0 ; null si illisible.
double? lireMontant(String texte) {
  final propre = texte.replaceAll(RegExp(r'[\s €]'), '').replaceAll(',', '.');
  return double.tryParse(propre);
}
