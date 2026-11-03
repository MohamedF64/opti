# Installer Opti chez soi

Opti est prévu pour **une seule personne par installation** : la base, le serveur et l'app n'acceptent qu'un compte. Compter environ une soirée. Tout est gratuit dans les limites d'un usage personnel (Supabase Free, Vercel Hobby, Firebase Spark, Enable Banking en production restreinte).

**Règle d'or** : aucune clé secrète dans le code ni dans l'app. Les secrets vont dans les variables d'environnement Vercel et dans le Vault Supabase.

## 1. Supabase (base de données et connexion)

1. Crée un projet sur [supabase.com](https://supabase.com) (région Europe).
2. **Authentication › Users › Add user** : crée ton compte (e-mail + mot de passe). Copie son identifiant (UUID).
3. **Authentication › Sign In / Providers** : désactive les inscriptions (« Allow new users to sign up »). Vérifie dans **Multi-Factor** que TOTP est activé (c'est le cas par défaut).
4. Dans `supabase/schema.sql`, remplace `00000000-0000-0000-0000-000000000000` par ton UUID (rechercher-remplacer), puis lance le fichier dans **SQL Editor**.
5. Lance `supabase/seed_catalogue.sql` : le catalogue de prix de départ (à mettre à jour, les prix changent).
6. Note l'URL du projet, la clé **publiable** (`sb_publishable_…`, prévue pour être publique) et la clé **secrète** (`sb_secret_…`, jamais dans l'app).

## 2. Enable Banking (accès aux comptes)

1. Crée un compte sur le [Control Panel](https://enablebanking.com/cp) (active la double authentification) et une application **Production** en mode restreint : elle ne voit que les comptes que tu relies toi-même.
2. URL de retour : `https://<ton-backend>.vercel.app/banque/retour` ; pages légales : `/confidentialite` et `/conditions` (servies par le backend).
3. Garde la clé privée `.pem` en lieu sûr (archive chiffrée), hors de tout dépôt.

## 3. Vercel (serveur)

1. Importe ce dépôt sur [vercel.com](https://vercel.com) avec **Root Directory = `backend`**. La région est fixée à Dublin dans `vercel.json` (près de Supabase en Irlande).
2. Variables d'environnement (Production et Preview, en « Sensitive » pour les secrets) :

| Variable | Valeur |
| --- | --- |
| `SUPABASE_URL` | URL du projet Supabase |
| `OWNER_USER_ID` | ton UUID Supabase |
| `SUPABASE_SERVICE_ROLE_KEY` | clé secrète Supabase |
| `EB_APP_ID` | identifiant de l'application Enable Banking |
| `EB_PRIVATE_KEY` | contenu du `.pem` |
| `CRON_SECRET` | une longue valeur aléatoire (Production seulement) |
| `FCM_SERVICE_ACCOUNT` | JSON du compte de service Firebase (étape 4) |
| `EB_REDIRECT_URL` | facultatif : par défaut `https://<domaine de production>/banque/retour` |

3. **Garde la protection des Preview activée** (Settings › Deployment Protection) : les routes `…/apercu` des Preview lisent tes vraies données sans session, seule cette protection les garde.
4. Facultatif : copie `backend/api/perso_exemple.py` en `backend/api/perso.py` (ton nom tel qu'il apparaît sur tes virements, les commerces de ton quartier). Garde alors ton dépôt **privé**.

## 4. Firebase (notifications)

1. Crée un projet [Firebase](https://console.firebase.google.com) et une app Android `fr.opti.opti` (ou change `applicationId` dans `app/android/app/build.gradle.kts`).
2. Place `google-services.json` dans `app/android/app/` (jamais publié).
3. **Project settings › Service accounts › Generate new private key** : colle le JSON dans `FCM_SERVICE_ACCOUNT` sur Vercel, puis supprime le fichier.

## 5. Synchros automatiques

Dans Supabase, active les extensions `pg_cron` et `pg_net`, range `CRON_SECRET` dans le Vault sous le nom `cron_secret`, puis adapte et lance `supabase/cron.sql`.

## 6. L'app

1. Installe [Flutter](https://docs.flutter.dev/get-started/install) (Android SDK, JDK 21).
2. Copie `app/lib/config_exemple.dart` en `app/lib/config.dart` et remplis-le (URL Supabase, clé publiable, URL du backend, prénom).
3. `cd app && flutter build apk --release --split-per-abi`, puis installe l'APK `arm64-v8a` sur ton téléphone.
4. À la première ouverture : connexion, puis activation de la double authentification (Google Authenticator ; active sa sauvegarde dans ton compte Google).

## 7. Relier tes banques

1. Copie `backend/tools/config_locale_exemple.py` en `config_locale.py` et remplis-le.
2. `python backend/tools/connecter_banque.py` : choisis la banque, autorise l'accès sur son site (valable 180 jours, renouvelable depuis l'app).
3. `python backend/tools/synchroniser.py` pour une première synchro, ou tire vers le bas sur l'accueil de l'app.

Le nettoyage des libellés et la reconnaissance des virements entre tes comptes sont écrits pour les deux banques de l'auteur (`backend/api/synchro.py` : `nettoyer_libelle`, `date_achat`, `virement_interne`) : adapte-les à tes banques.
