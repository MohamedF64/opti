# Moteur de conseils local

Les conseils budget sont produits par des **règles écrites dans le code**, pas par une IA. Une ancienne version de l'app le faisait déjà, mais pas de façon fiable à 100 % : les défauts constatés sont listés plus bas, avec la règle qui les corrige.

Pourquoi : gratuit, aucun fournisseur d'IA à gérer, résultats explicables et testables.

## Périmètre des conseils
Uniquement de l'**épargne simple** : mettre de l'argent de côté, dépenser moins, garder une réserve pour les imprévus, surveiller les abonnements. **Jamais** de conseil d'investissement (placements, bourse, crypto), ni de fiscalité ou d'impôts.

## Rôle de chaque compte
- **CIC** : compte courant, où arrive la paie et d'où partent les dépenses du quotidien.
- **Revolut** : la tirelire. On y verse de l'argent pour les imprévus et les économies (réserve « Économies »), et des abonnements peuvent y être prélevés.

Conséquences pour les calculs :
- Un **virement entre ses propres comptes** (CIC → Revolut, ou vers une réserve Revolut) est de l'**épargne**, pas une dépense. Il ne doit compter ni dans les dépenses du jour, ni dans le budget du mois, ni dans le donut « Cette semaine » (l'ancienne app y affichait « Transfert 3 € »). Il apparaît plutôt comme « mis de côté ce mois-ci ».
- Les conseils peuvent proposer un **montant à mettre de côté** (par exemple ce qui reste sous la limite du jour ou en fin de mois), avec un objectif de réserve pour les imprévus.
- La **détection d'abonnements** regarde tous les comptes reliés.
- Enable Banking expose la réserve Revolut comme un compte d'épargne séparé.

## Ce qu'une ancienne version affichait (accueil)
- **Solde total** et une carte par compte.
- **Dépenses du jour** : montant, badge OK, barre, « limite : X € » / « reste : Y € ».
- **Bloc d'état du mois** : titre selon la situation (« Garde le cap », « Tu vas dépasser ton budget »), phrase « Tu es à X % de ton budget après Y % du mois. Il reste N jours jusqu'à la paie », deux barres « Mois écoulé » et « Budget consommé ».
- **Au plus tard / dès** : jours restants avant la paie, sur la fenêtre `salary_day` (21) → `salary_day_max` (28) de la table `settings`.
- **Vise par jour** : budget restant ÷ jours restants, comparé à `daily_limit`.
- **Conseils** : 2 à 4 puces.
- **Bilan abonnements** : « potentiellement résiliés » (pas vus depuis 2 cycles ou plus) et « nouveaux détectés », avec boutons Résilier / Ajouter.
- **Cette semaine** : donut des dépenses par catégorie.

## Défauts constatés et règles à respecter
| Défaut constaté | Règle pour la nouvelle version |
| --- | --- |
| « Vise 0,00 €/jour au lieu de 10,00 € » quand le budget est déjà dépassé | Ne jamais proposer 0 €. Si le budget est dépassé : dire de combien, et proposer un plancher réaliste (dépenses essentielles moyennes par jour), en signalant que l'objectif du mois n'est plus tenable. |
| « Privilégie cuisine maison (~10-15 €/jour vs livraison) » sans données de livraison | Un conseil n'apparaît que si les transactions le justifient (catégorie présente sur la période, montant réel cité dans la phrase). |
| « jusqu'au entre le 23 et le 28 mai » | Modèles de phrases complets, pas d'assemblage de morceaux : « d'ici ta paie (entre le 23 et le 28 mai) ». |
| Mêmes conseils génériques chaque jour | Classer les conseils candidats selon l'économie estimée en euros, n'en afficher que 2 ou 3, pas de conseil sans chiffre. |
| Abonnement « résilié » et « nouveau » à la fois, doublons | Dédoublonner par marchand normalisé avant d'afficher le bilan. |
| Pourcentages contradictoires (147 % du budget à 48 % du mois, mais « Dépenses du jour OK ») | Les états du jour et du mois sont calculés à partir des mêmes données et ne doivent pas se contredire sans explication. |

## Où le coder
Dans le **backend** (`api/conseils.py`, fonctions pures testées en Python, règles au § 6 de [regles-de-calcul.md](regles-de-calcul.md)) ; l'app affiche le résultat, gardé en cache.
