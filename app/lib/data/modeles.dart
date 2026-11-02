/// Données renvoyées par GET /budget/aujourdhui (voir opti-backend/api/budget.py).
library;

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;

class LigneBudget {
  LigneBudget(this.libelle, this.montant);
  final String libelle;
  final double montant;
}

class AbonnementAVenir {
  AbonnementAVenir(this.nom, this.montant, this.date);
  final String nom;
  final double montant;
  final DateTime date;
}

class Budget {
  Budget.depuisJson(Map<String, dynamic> j)
    : debutCycle = DateTime.parse(j['debut_cycle']),
      paie = _d(j['paie']),
      paieAuPlusTot = DateTime.parse(j['paie_au_plus_tot']),
      paieAuPlusTard = DateTime.parse(j['paie_au_plus_tard']),
      paieEnRetard = j['paie_en_retard'] == true,
      joursRestants = j['jours_restants'] as int,
      epargneVisee = _d(j['epargne_visee']),
      sourceEpargne = j['source_epargne'] as String,
      abonnementsAVenir = [
        for (final a in j['abonnements_a_venir'] as List)
          AbonnementAVenir(a['nom'], _d(a['montant']), DateTime.parse(a['date'])),
      ],
      depenseAujourdhui = _d(j['depense_aujourdhui']),
      resteDuCycle = _d(j['reste_du_cycle']),
      limiteCalculee = _d(j['limite_calculee']),
      limiteDuJour = _d(j['limite_du_jour']),
      tuPeuxEncore = _d(j['tu_peux_encore']),
      limiteAppliquee = j['limite_appliquee'] as String,
      effetLimiteManuelle = _d(j['effet_limite_manuelle']),
      depassement = _d(j['depassement']),
      pourquoi = [for (final l in j['pourquoi'] as List) LigneBudget(l['libelle'], _d(l['montant']))];

  final DateTime debutCycle, paieAuPlusTot, paieAuPlusTard;
  final double paie, epargneVisee, depenseAujourdhui, resteDuCycle, limiteCalculee, limiteDuJour, tuPeuxEncore;
  final double effetLimiteManuelle, depassement;
  final bool paieEnRetard;
  final int joursRestants;
  final String sourceEpargne, limiteAppliquee;
  final List<AbonnementAVenir> abonnementsAVenir;
  final List<LigneBudget> pourquoi;

  /// Reste du cycle une fois comptées les dépenses d'aujourd'hui (ce que le calcul prendra demain matin).
  double get resteApresAujourdhui => resteDuCycle - depenseAujourdhui;

  /// Estimation de la limite de demain : reste après aujourd'hui ÷ jours restants moins un
  /// (hors limite manuelle, que le serveur appliquera demain).
  double get limiteDemain =>
      joursRestants <= 1 ? 0 : (resteApresAujourdhui > 0 ? resteApresAujourdhui : 0) / (joursRestants - 1);

  /// Part de la limite du jour déjà dépensée (0 à 1, au-delà = dépassement).
  double get progression => limiteDuJour <= 0 ? (depenseAujourdhui > 0 ? 1.0 : 0.0) : depenseAujourdhui / limiteDuJour;
}

class Operation {
  Operation.depuisJson(Map<String, dynamic> j)
    : id = j['id'] as String? ?? '',
      date = DateTime.parse(j['date'] as String),
      interne = j['is_internal'] == true,
      objectifId = j['goal_id'] as String?,
      libelle = (j['merchant'] as String?)?.trim().isNotEmpty == true ? j['merchant'] : (j['description'] ?? ''),
      categorie = j['category'] as String? ?? 'Autre',
      montant = _d(j['amount']),
      enAttente = j['status'] == 'pending',
      banque = j['bank_name'] as String? ?? '';

  final String id, libelle, categorie, banque;
  final String? objectifId; // dépense payée avec l'épargne de cet objectif
  final DateTime date;
  final bool interne; // virement entre les comptes de Mohamed
  final double montant;
  final bool enAttente;
}

class CompteBancaire {
  CompteBancaire(this.libelle, this.solde);
  final String libelle;
  final double? solde;
}

class Banque {
  Banque.depuisJson(Map<String, dynamic> j)
    : nom = j['banque'],
      statut = j['statut'],
      joursRestants = j['jours_restants'] as int?,
      aRenouveler = j['a_renouveler'] == true,
      accesJusquAu = j['consentement_jusqu_au'] == null ? null : DateTime.parse(j['consentement_jusqu_au']).toLocal(),
      derniereErreur = j['derniere_erreur'],
      derniereSynchro = j['derniere_synchro'] == null ? null : DateTime.parse(j['derniere_synchro']).toLocal(),
      comptes = [
        for (final c in j['comptes'] as List)
          CompteBancaire(c['libelle'] ?? '', c['solde'] == null ? null : _d(c['solde'])),
      ];

  final String nom, statut;
  final int? joursRestants;
  final bool aRenouveler;
  final DateTime? derniereSynchro, accesJusquAu;
  final String? derniereErreur;
  final List<CompteBancaire> comptes;
}

class Accueil {
  Accueil.depuisJson(Map<String, dynamic> j)
    : budget = Budget.depuisJson(j['budget']),
      operations = [for (final o in j['operations_du_jour'] as List) Operation.depuisJson(o)],
      banques = [for (final b in j['comptes']['banques'] as List) Banque.depuisJson(b)],
      soldeTotal = _d(j['comptes']['solde_total']);

  final Budget budget;
  final List<Operation> operations;
  final List<Banque> banques;
  final double soldeTotal;

  /// Synchro la plus ancienne des banques (la plus pessimiste), pour la pastille d'état.
  DateTime? get derniereSynchro {
    final dates = banques.map((b) => b.derniereSynchro).whereType<DateTime>().toList()..sort();
    return dates.isEmpty ? null : dates.first;
  }

  bool get synchroEnErreur => banques.any((b) => b.statut != 'ok');
  bool get consentementARenouveler => banques.any((b) => b.aRenouveler);
}
