# Opti

**Opti** est une app Android de budget personnel, construite pour un usage réel au quotidien : elle lit les comptes bancaires (CIC et Revolut, via l'accès DSP2 d'[Enable Banking](https://enablebanking.com)) et répond chaque jour à une seule question : **combien puis-je encore dépenser aujourd'hui ?**

> ⚠️ Opti est un **projet personnel**, publié pour montrer son fonctionnement. Ce n'est ni un service financier ni une app grand public : chaque personne qui veut l'utiliser doit l'installer **chez elle**, avec ses propres comptes Supabase, Vercel, Enable Banking et Firebase (voir [INSTALLATION.md](INSTALLATION.md)). Les conseils sont uniquement de l'épargne simple, jamais d'investissement ni de fiscalité.

## Ce que fait l'app

- **Accueil** : la limite du jour (« Tu peux encore dépenser 39,55 € »), calculée de paie à paie, avec le détail « Pourquoi X € ? » ; opérations du jour, comptes, bilan du cycle et conseils.
- **Objectifs** : projets et réserve « Imprévus », versements reconnus automatiquement dans la réserve Revolut, dépenses payées avec l'épargne d'un projet.
- **Stats** : dépenses par cycle de paie, donut par catégorie, comparaison avec le cycle précédent, jours passés sous la limite.
- **Abonnements** : détection automatique, prix variables, prix maximum, essais gratuits avec rappels, verdict selon l'usage.
- **Catalogue de prix** : offres moins chères pour ses propres abonnements (forfaits mobiles, IA, Amazon Prime), pages officielles surveillées chaque mois, bons plans Dealabs pour les enseignes où l'on achète déjà.
- **Sécurité** : double authentification (code à 6 chiffres), verrou par code et empreinte, cache et session chiffrés sur le téléphone, base fermée par RLS, aucune clé secrète dans l'app.
- **Apparence** : trois thèmes (Holocron, Forêt, Océan), clair / sombre / auto, fonds animés dessinés à la main.

Chaque règle de calcul est écrite en français avec un exemple chiffré **avant** d'être codée, puis testée sur ce même exemple : voir [docs/regles-de-calcul.md](docs/regles-de-calcul.md).

## Architecture

```
app/        Flutter (Android) : écrans, cache chiffré, notifications FCM
backend/    Python FastAPI sur Vercel : calculs, synchro bancaire, notifications, catalogue
supabase/   PostgreSQL (Supabase) : schéma, règles d'accès (RLS), données de départ du catalogue
docs/       règles de calcul, conseils, apparence
```

- **Tous les calculs sont côté serveur** (`backend/api/*.py`, fonctions pures testées) ; l'app affiche les résultats et les garde en cache pour s'ouvrir instantanément.
- **Synchro bancaire** : 4 fois par jour (le maximum DSP2 sans action de l'utilisateur), déclenchée par un cron Supabase protégé par un secret ; opérations en attente importées puis remplacées par leur version comptabilisée ; virements entre ses propres comptes reconnus comme de l'épargne.
- **Authentification** : Supabase Auth avec double authentification (TOTP) ; le backend vérifie localement chaque jeton (ES256, clé publique), son niveau `aal2` et son propriétaire ; la base exige la même chose par RLS.
- **Aucune IA** pour les montants ni les conseils : des règles explicables et testées.

## Tests

```bash
cd backend && python -m pytest -q tests      # 183 tests : calculs, routes, sécurité
cd app && flutter test                        # modèles, cache chiffré, recherche
```

Un test vérifie que **toute** route non publique refuse une requête sans session : une route ajoutée sans protection fait échouer la suite.

## Licence

[MIT](LICENSE).
