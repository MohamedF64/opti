import 'package:flutter_test/flutter_test.dart';
import 'package:opti/data/cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CoffreMemoire implements Coffre {
  final Map<String, String> contenu = {};
  @override
  Future<Map<String, String>> toutLire() async => {...contenu};
  @override
  Future<void> ecrire(String cle, String valeur) async => contenu[cle] = valeur;
  @override
  Future<void> effacer(String cle) async => contenu.remove(cle);
}

void main() {
  test("le cache en clair d'une ancienne version passe dans le coffre et disparaît des préférences", () async {
    SharedPreferences.setMockInitialValues({
      'cache_objectifs': '{"ancien": true}',
      'cache_stats_cycle': '{"x": 1}',
      'apparence': '{"theme": "foret"}', // pas une donnée personnelle : reste en clair
    });
    final prefs = await SharedPreferences.getInstance();
    final coffre = CoffreMemoire();
    final cache = await CacheLocal.charger(prefs, coffre);

    expect(coffre.contenu.keys.toSet(), {'cache_objectifs', 'cache_stats_cycle'});
    expect(prefs.getKeys(), {'apparence'});
    expect(cache.apparence(), {'theme': 'foret'});

    await cache.garderAbonnements({'total_par_mois': 1});
    expect(coffre.contenu['cache_abonnements'], '{"total_par_mois":1}');
    expect(prefs.getKeys(), {'apparence'}); // jamais rien de personnel en clair

    await cache.vider();
    expect(coffre.contenu, isEmpty);
    expect(cache.objectifs(), isNull);
  });

  test('au démarrage suivant, le cache est relu depuis le coffre', () async {
    SharedPreferences.setMockInitialValues({});
    final coffre = CoffreMemoire()..contenu['cache_accueil'] = '{}';
    final cache = await CacheLocal.charger(await SharedPreferences.getInstance(), coffre);
    expect(coffre.contenu.keys, ['cache_accueil']);
    expect(cache.accueil(), isNull); // format illisible ici : on attend le serveur, sans planter
  });
}
