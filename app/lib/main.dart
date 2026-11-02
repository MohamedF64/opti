import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/apparence.dart';
import 'data/cache.dart';
import 'data/double_auth.dart';
import 'data/verrou.dart';
import 'ecrans/connexion.dart';
import 'ecrans/double_auth.dart';
import 'ecrans/navigation.dart';
import 'ecrans/verrou.dart';
import 'theme/opti_theme.dart';
import 'widgets/fond_anime.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Polices intégrées à l'APK (assets/google_fonts) : jamais de téléchargement, l'app marche hors ligne.
  GoogleFonts.config.allowRuntimeFetching = false;
  await Firebase.initializeApp(); // configuration lue dans android/app/google-services.json
  // Session chiffrée (coffre Android), même clé que celle de supabase_flutter par défaut.
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
    authOptions: FlutterAuthClientOptions(
      localStorage: SessionChiffree('sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token'),
    ),
  );
  final cache = await CacheLocal.charger(await SharedPreferences.getInstance(), CoffreChiffre());
  dossierApp = (await getApplicationDocumentsDirectory()).path; // image de fond importée
  final verrou = Verrou(CoffreAndroid());
  await verrou.charger();
  runApp(
    ProviderScope(
      overrides: [cacheProvider.overrideWithValue(cache), verrouProvider.overrideWithValue(verrou)],
      child: const OptiApp(),
    ),
  );
}

class OptiApp extends ConsumerWidget {
  const OptiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apparence = ref.watch(apparenceProvider);
    return MaterialApp(
      title: 'Opti',
      debugShowCheckedModeBanner: false,
      theme: construireTheme(apparence.theme, Brightness.light, accent: apparence.accentPour(Brightness.light)),
      darkTheme: construireTheme(apparence.theme, Brightness.dark, accent: apparence.accentPour(Brightness.dark)),
      themeMode: apparence.mode,
      home: const _Portail(),
      builder: (context, child) => HorlogeFond(child: GardeVerrou(child: child!)),
    );
  }
}

/// Connexion (mot de passe puis code à 6 chiffres) tant que la session n'est pas complète, l'accueil ensuite.
class _Portail extends StatelessWidget {
  const _Portail();

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) => switch (etapeActuelle(auth)) {
        EtapeConnexion.connexion => const EcranConnexion(),
        EtapeConnexion.activerCode => const EcranActiverCode(),
        EtapeConnexion.saisirCode => const EcranSaisirCode(),
        EtapeConnexion.ouverte => const Navigation(),
      },
    );
  }
}
