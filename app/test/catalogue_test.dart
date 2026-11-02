import 'package:flutter_test/flutter_test.dart';
import 'package:opti/data/catalogue.dart';
import 'package:opti/ecrans/catalogue.dart';

Map<String, dynamic> offre(String id, String service, String nom, double prix, {Map<String, dynamic>? plus}) => {
  'offre_id': id,
  'service': service,
  'nom': nom,
  'prix': prix,
  'frequence': 'mensuel',
  'par_mois': prix,
  'go': null,
  'conditions': null,
  'engagement': 'sans engagement',
  'essai': null,
  'prix_promo': null,
  'promo_duree': null,
  'source_url': null,
  'verifie_le': '2026-11-01',
  ...?plus,
};

void main() {
  // Exemple du § 12 : ligne Prixtel à 13,99 €, RED 120 Go à 12,99 € → 1 € de moins par mois.
  final json = {
    'profil': {'etudiant': true, 'moins_26': true, 'age_18_24': false},
    'abonnements': [
      {
        'id': 'a1',
        'nom': 'Prixtel',
        'par_mois': 22.98,
        'statut': 'actif',
        'rattache': true,
        'service_propose': null,
        'lignes': [
          {
            'id': 'l1',
            'nom': 'Box 4G',
            'prix': 13.99,
            'go': 100,
            'prix_saisi': 13.99,
            'go_saisi': 100,
            'offre': offre('o1', 'Prixtel', 'Oxygène', 9.99, plus: {'go': 100}),
            'alternatives': [
              offre(
                'o2',
                'RED by SFR',
                'RED 120 Go 5G',
                12.99,
                plus: {'go': 120, 'meme_service': false, 'economie_par_mois': 1.0, 'economie_par_an': 12.0},
              ),
            ],
            'go_manquants': false,
          },
        ],
      },
      {
        'id': 'a2',
        'nom': 'Google AI plus',
        'par_mois': 4.99,
        'statut': 'essai',
        'rattache': false,
        'service_propose': {'id': 's2', 'nom': 'Google One'},
        'lignes': [],
      },
    ],
    'groupees': [
      {
        ...offre('o3', 'B&You', 'B&You 170 Go + Amazon Prime', 17.99, plus: {'go': 170}),
        'inclut': ['Amazon Prime'],
        'remplace': [
          {'ligne': 'Prixtel · Téléphone', 'par_mois': 6.99},
          {'service': 'Amazon Prime', 'par_mois': 3.49},
        ],
        'cout_actuel': 10.48,
        'ecart_par_mois': 7.51,
        'go_en_plus': 70,
      },
    ],
    'catalogue': [
      {
        'id': 's1',
        'nom': 'Prixtel',
        'famille': 'mobile',
        'page_url': 'https://www.prixtel.com',
        'page_etat': 'ok',
        'page_lue_le': '2026-11-01T19:43:09+00:00',
        'page_modifiee_le': null,
        'montants_apparus': [],
        'montants_disparus': [],
        'offres': [
          {
            ...offre('o1', 'Prixtel', 'Oxygène', 9.99, plus: {'go': 100}),
            'inclut': null,
            'a_reverifier': false,
          },
        ],
      },
      {
        'id': 's3',
        'nom': 'Amazon Prime',
        'famille': 'amazon',
        'page_url': null,
        'page_etat': 'illisible',
        'offres': [
          {
            ...offre(
              'o4',
              'Amazon Prime',
              'Prime étudiants annuel',
              34.95,
              plus: {
                'frequence': 'annuel',
                'par_mois': 2.91,
                'conditions': ['etudiant', 'age_18_24'],
              },
            ),
            'a_reverifier': true,
          },
        ],
      },
    ],
  };

  test("lit l'écran Catalogue renvoyé par le serveur", () {
    final d = DonneesCatalogue.depuisJson(json);
    expect(d.profil, {'etudiant': true, 'moins_26': true, 'age_18_24': false});
    final ligne = d.abonnements.first.lignes.single;
    expect(ligne.alternatives.single.economieParMois, 1.0);
    expect(ligne.alternatives.single.memeService, isFalse);
    expect(d.serviceDe(ligne.offre)?.id, 's1');
    expect(d.abonnements[1].serviceProposeId, 's2');
    expect(d.groupees.single.remplace.map((r) => r.nom), ['Prixtel · Téléphone', 'Amazon Prime']);
    expect(d.services[1].suiviManuel, isTrue);
    expect(d.services[1].offres.single.aReverifier, isTrue);
  });

  test('prix et conditions affichés', () {
    final prime = DonneesCatalogue.depuisJson(json).services[1].offres.single;
    expect(prixOffre(prime).replaceAll(' ', ' ').replaceAll(' ', ' '), '34,95 €/an (2,91 €/mois)');
    expect(prime.texteConditions, 'Étudiant ou 18-24 ans');
  });
}
