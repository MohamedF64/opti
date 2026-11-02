/// Données renvoyées par GET /objectifs (voir opti-backend/api/objectifs.py).
library;

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
double? _dn(Object? v) => (v as num?)?.toDouble();
DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);

class MouvementObjectif {
  MouvementObjectif.depuisJson(Map<String, dynamic> j)
    : id = j['id'],
      montant = _d(j['montant']),
      enAttente = j['statut'] == 'en_attente',
      note = j['note'],
      declareLe = DateTime.parse(j['declare_le']),
      confirmeLe = _date(j['confirme_le']),
      reconnuAutomatiquement = j['reconnu_automatiquement'] == true,
      rappel = j['rappel'] == true;

  final String id;
  final double montant; // + mis de côté, − pioché
  final bool enAttente, reconnuAutomatiquement, rappel;
  final String? note;
  final DateTime declareLe;
  final DateTime? confirmeLe;
}

class Objectif {
  Objectif.depuisJson(Map<String, dynamic> j)
    : id = j['id'],
      nom = j['nom'],
      imprevus = j['type'] == 'imprevus',
      icone = j['icone'],
      archive = j['statut'] == 'archive',
      cible = _d(j['cible']),
      echeance = _date(j['echeance']),
      verse = _d(j['verse']),
      depense = _d(j['depense']),
      epargneTotale = _d(j['epargne_totale'] ?? j['verse']),
      disponible = _d(j['disponible']),
      enAttente = _d(j['en_attente']),
      reste = _d(j['reste']),
      progression = _d(j['progression']),
      atteint = j['atteint'] == true,
      joursRestants = j['jours_restants'] as int?,
      parJour = _dn(j['par_jour']),
      parSemaine = _dn(j['par_semaine']),
      parMois = _dn(j['par_mois']),
      rythmeMensuel = _d(j['rythme_mensuel']),
      rythmeConnu = j['rythme_connu'] == true,
      premierVersement = _date(j['premier_versement']),
      dateEstimee = _date(j['date_estimee']),
      faisabilite = j['faisabilite'] as int?,
      echeanceDepassee = j['echeance_depassee'] == true,
      echeanceSuggeree = _date(j['echeance_suggeree']),
      mouvements = [for (final m in j['mouvements'] as List) MouvementObjectif.depuisJson(m)],
      depenses = [for (final t in (j['depenses'] as List?) ?? const []) OperationReserve.depuisJson(t)];

  final String id, nom;
  final String? icone;
  final bool imprevus, archive, atteint, echeanceDepassee, rythmeConnu;
  final double cible, verse, depense, epargneTotale, disponible, enAttente, reste, progression, rythmeMensuel;
  final double? parJour, parSemaine, parMois;
  final DateTime? echeance, dateEstimee, echeanceSuggeree, premierVersement;
  final int? joursRestants, faisabilite;
  final List<MouvementObjectif> mouvements;
  final List<OperationReserve> depenses; // dépenses payées avec l'épargne de cet objectif
}

/// Opération courte (date, montant, libellé), pour les dépenses rattachées.
class OperationReserve {
  OperationReserve.depuisJson(Map<String, dynamic> j)
    : id = j['id'],
      date = DateTime.parse(j['date']),
      montant = _d(j['montant']),
      libelle = j['libelle'] ?? '';

  final String id, libelle;
  final DateTime date;
  final double montant;
}

/// « Rattacher à un projet ? » : grosse dépense qu'un projet pourrait payer.
class SuggestionRattachement {
  SuggestionRattachement.depuisJson(Map<String, dynamic> j)
    : id = j['id'],
      date = DateTime.parse(j['date']),
      montant = _d(j['montant']),
      libelle = j['libelle'] ?? '',
      objectifIds = [for (final i in j['objectifs'] as List) i as String];

  final String id, libelle;
  final DateTime date;
  final double montant;
  final List<String> objectifIds;
}

/// Mouvement de la réserve « Économies » qu'aucun versement déclaré n'explique.
class OperationAAttribuer {
  OperationAAttribuer.depuisJson(Map<String, dynamic> j)
    : id = j['id'],
      date = DateTime.parse(j['date']),
      montant = _d(j['montant']),
      libelle = j['libelle'] ?? '';

  final String id, libelle;
  final DateTime date;
  final double montant;
}

/// Versement qu'un retrait de la réserve annulerait.
class VersementAnnulable {
  VersementAnnulable.depuisJson(Map<String, dynamic> j)
    : id = j['id'],
      objectif = j['objectif'],
      montant = _d(j['montant']),
      date = DateTime.parse(j['date']),
      note = j['note'];

  final String id, objectif;
  final double montant;
  final DateTime date;
  final String? note;
}

/// « Tu as repris 200 € de ta tirelire, puis dépensé… C'était pour : »
class Reprise {
  Reprise.depuisJson(Map<String, dynamic> j)
    : id = j['id'],
      date = DateTime.parse(j['date']),
      montant = _d(j['montant']),
      arrivee = j['arrivee'] ?? 'Revolut',
      objectifId = j['objectif_id'],
      depenses = [
        for (final d in j['depenses'] as List) (operation: OperationReserve.depuisJson(d), cochee: d['cochee'] == true),
      ];

  final String id, arrivee;
  final String? objectifId; // déjà attribuée (pioche déclarée) : l'objectif est imposé
  final DateTime date;
  final double montant; // positif : la somme reprise
  final List<({OperationReserve operation, bool cochee})> depenses;
}

class EcranObjectifs {
  EcranObjectifs.depuisJson(Map<String, dynamic> j)
    : objectifs = [for (final o in j['objectifs'] as List) Objectif.depuisJson(o)],
      aAttribuer = [for (final t in j['a_attribuer'] as List) OperationAAttribuer.depuisJson(t)],
      suggestions = [for (final s in (j['suggestions'] as List?) ?? const []) SuggestionRattachement.depuisJson(s)],
      reprises = [for (final r in (j['reprises'] as List?) ?? const []) Reprise.depuisJson(r)];

  final List<Objectif> objectifs;
  final List<OperationAAttribuer> aAttribuer;
  final List<SuggestionRattachement> suggestions;
  final List<Reprise> reprises;

  List<Objectif> get actifs => objectifs.where((o) => !o.archive).toList();
  List<Objectif> get archives => objectifs.where((o) => o.archive).toList();
}
