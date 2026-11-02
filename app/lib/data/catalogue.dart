/// Données renvoyées par GET /catalogue (voir opti-backend/api/catalogue.py, règles § 12).
library;

import '../util/texte.dart';

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
double? _dn(Object? v) => (v as num?)?.toDouble();
DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);
List<String> _textes(Object? v) => [for (final t in (v as List?) ?? const []) t as String];

/// Conditions d'accès d'une offre : une seule suffit.
const libellesConditions = {'etudiant': 'Étudiant', 'moins_26': 'Moins de 26 ans', 'age_18_24': '18-24 ans'};

/// Une offre du catalogue ; pour une offre moins chère, l'économie en plus.
class Offre {
  Offre.depuisJson(Map<String, dynamic> j)
    : id = j['offre_id'],
      service = j['service'],
      nom = j['nom'],
      prix = _d(j['prix']),
      frequence = j['frequence'] ?? 'mensuel',
      parMois = _d(j['par_mois']),
      go = j['go'] as int?,
      conditions = _textes(j['conditions']),
      engagement = j['engagement'],
      essai = j['essai'],
      prixPromo = _dn(j['prix_promo']),
      promoDuree = j['promo_duree'],
      sourceUrl = j['source_url'],
      verifieLe = DateTime.parse(j['verifie_le']),
      inclut = _textes(j['inclut']),
      aReverifier = j['a_reverifier'] == true,
      memeService = j['meme_service'] == true,
      economieParMois = _dn(j['economie_par_mois']),
      economieParAn = _dn(j['economie_par_an']),
      paiementDAvance = _dn(j['paiement_d_avance']);

  final String id, service, nom, frequence;
  final double prix, parMois;
  final int? go;
  final List<String> conditions, inclut;
  final String? engagement, essai, promoDuree, sourceUrl;
  final double? prixPromo, economieParMois, economieParAn, paiementDAvance;
  final DateTime verifieLe;
  final bool aReverifier, memeService;

  /// « Étudiant ou 18-24 ans ».
  String? get texteConditions =>
      conditions.isEmpty ? null : conditions.map((c) => libellesConditions[c] ?? c).join(' ou ');
}

class LigneAbonnement {
  LigneAbonnement.depuisJson(Map<String, dynamic> j)
    : id = j['id'],
      nom = j['nom'],
      prix = _dn(j['prix']),
      go = j['go'] as int?,
      prixSaisi = _dn(j['prix_saisi']),
      goSaisi = j['go_saisi'] as int?,
      offre = j['offre'] == null ? null : Offre.depuisJson(j['offre']),
      alternatives = [for (final a in (j['alternatives'] as List?) ?? const []) Offre.depuisJson(a)],
      goManquants = j['go_manquants'] == true;

  final String id, nom;
  final double? prix, prixSaisi;
  final int? go, goSaisi;
  final Offre? offre;
  final List<Offre> alternatives;
  final bool goManquants;
}

class AbonnementCatalogue {
  AbonnementCatalogue.depuisJson(Map<String, dynamic> j)
    : id = j['id'],
      nom = j['nom'],
      parMois = _d(j['par_mois']),
      statut = j['statut'],
      rattache = j['rattache'] == true,
      serviceProposeId = j['service_propose']?['id'],
      lignes = [for (final l in (j['lignes'] as List?) ?? const []) LigneAbonnement.depuisJson(l)];

  final String id, nom, statut;
  final double parMois;
  final bool rattache;
  final String? serviceProposeId;
  final List<LigneAbonnement> lignes;
}

/// Offre groupée « à étudier » : jamais un conseil.
class OffreGroupee {
  OffreGroupee.depuisJson(Map<String, dynamic> j)
    : offre = Offre.depuisJson(j),
      remplace = [
        for (final r in (j['remplace'] as List?) ?? const [])
          (nom: (r['ligne'] ?? r['service']) as String, parMois: _d(r['par_mois'])),
      ],
      coutActuel = _d(j['cout_actuel']),
      ecartParMois = _d(j['ecart_par_mois']),
      goEnPlus = j['go_en_plus'] as int? ?? 0;

  final Offre offre;
  final List<({String nom, double parMois})> remplace;
  final double coutActuel, ecartParMois;
  final int goEnPlus;
}

class ServiceCatalogue {
  ServiceCatalogue.depuisJson(Map<String, dynamic> j)
    : id = j['id'],
      nom = j['nom'],
      famille = j['famille'],
      pageUrl = j['page_url'],
      pageEtat = j['page_etat'] ?? 'ok',
      pageLueLe = _date(j['page_lue_le']),
      pageModifieeLe = _date(j['page_modifiee_le']),
      montantsApparus = [for (final m in (j['montants_apparus'] as List?) ?? const []) _d(m)],
      montantsDisparus = [for (final m in (j['montants_disparus'] as List?) ?? const []) _d(m)],
      offres = [for (final o in (j['offres'] as List?) ?? const []) Offre.depuisJson(o)];

  final String id, nom, famille;
  final String? pageUrl;
  final String pageEtat; // ok, modifiee, illisible
  final DateTime? pageLueLe, pageModifieeLe;
  final List<double> montantsApparus, montantsDisparus;
  final List<Offre> offres;

  bool get mobile => famille == 'mobile';
  bool get modifiee => pageEtat == 'modifiee';
  bool get suiviManuel => pageEtat == 'illisible';
}

class DonneesCatalogue {
  DonneesCatalogue.depuisJson(Map<String, dynamic> j)
    : profil = {for (final e in (j['profil'] as Map).entries) e.key as String: e.value == true},
      abonnements = [for (final a in j['abonnements'] as List) AbonnementCatalogue.depuisJson(a)],
      groupees = [for (final g in (j['groupees'] as List?) ?? const []) OffreGroupee.depuisJson(g)],
      services = [for (final s in j['catalogue'] as List) ServiceCatalogue.depuisJson(s)];

  final Map<String, bool> profil;
  final List<AbonnementCatalogue> abonnements;
  final List<OffreGroupee> groupees;
  final List<ServiceCatalogue> services;

  /// Recherche dans le nom du service (l'opérateur) et des offres, sans accents ni majuscules (§ 12) :
  /// un service trouvé par son nom garde toutes ses offres, sinon seules les offres trouvées restent.
  List<(ServiceCatalogue, List<Offre>)> chercher(String texte) => [
    for (final s in services)
      if (correspond(texte, '${s.nom} ${s.famille}'))
        (s, s.offres)
      else if (s.offres.where((o) => correspond(texte, '${s.nom} ${o.nom}')).toList() case final offres
          when offres.isNotEmpty)
        (s, offres),
  ];

  ServiceCatalogue? serviceDe(Offre? offre) =>
      offre == null ? null : services.where((s) => s.nom == offre.service).firstOrNull;
}
