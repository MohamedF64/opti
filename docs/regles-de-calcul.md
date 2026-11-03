# Règles de calcul d'Opti

Chaque calcul d'Opti est d'abord écrit ici en français, avec un exemple chiffré, puis codé et testé sur ces mêmes exemples (`backend/tests`). Les montants des exemples sont fictifs ; les marques d'abonnements (Prixtel, Imagine R, Amazon Prime…) sont de vraies offres publiques, utilisées pour rendre les exemples concrets.

## 1. Le cycle : de paie à paie

- **Début** : le jour où la dernière paie est arrivée (opération « Salaire »).
- **Fin prévue** : la veille de la prochaine paie, prise **au plus tard** (`salary_day_max`, ex. le 28) pour rester prudent ; l'app affiche aussi la date **au plus tôt** (`salary_day`, ex. le 21).
- Paie en retard après le jour au plus tard : le cycle continue, l'app le signale, jamais de division par zéro jour.

> Le 30/10 : cycle commencé le **26/10** (paie de 1 850,00 €), prochaine paie entre le **21/11** et le **28/11** → **29 jours** restants, aujourd'hui compris.

## 2. Ce qui compte comme une dépense

| Compte | Exemple |
| --- | --- |
| ✅ Toute sortie vers l'extérieur | courses, restaurant, Vinted, retrait au distributeur |
| ✅ Les abonnements | Imagine R, assurance auto, Prixtel, Claude, Prime |
| ➖ Les remboursements diminuent leur catégorie | Vinted +10,41 € |
| ❌ Les virements entre tes comptes (épargne) | BoursoBank → livret LCL |
| ❌ Les revenus | salaire, virements reçus |
| ❌ **Les dépenses rattachées à un projet** (voir § 5) | permis, carte grise, Airbnb… payés avec l'argent mis de côté pour eux |

Jour d'une dépense = jour de l'achat ; les paiements « en attente » comptent tout de suite.

## 3. « Tu peux encore dépenser X € aujourd'hui »

**Calcul de base : l'enveloppe de la paie.**

```
  enveloppe du cycle = paie reçue − épargne visée − abonnements à venir avant la prochaine paie
  reste du cycle     = enveloppe − dépensé depuis la paie (hors aujourd'hui, hors projets)
  limite du jour     = reste du cycle ÷ jours restants (aujourd'hui compris)
  tu peux encore     = limite du jour − dépensé aujourd'hui
```

Un dépassement est lissé tout seul sur les jours suivants.

**Limite manuelle (facultative)** : une limite du jour fixée à la main, désactivable à tout moment.
- **Par défaut, c'est une marge de sécurité (plancher)** : X = la **plus grande** des deux limites, l'app n'affiche jamais moins que ce montant. Si le plancher dépasse ce que l'enveloppe permet, l'écart est pris sur les jours suivants et « Pourquoi X € ? » le dit (« ta marge de sécurité de 30 € s'applique : tes prochains jours baissent de 2 € chacun »).
- **Option « mode économies max »** : X = la **plus petite** des deux limites, et « Pourquoi X € ? » indique « limitée par ton plafond de N € ».

**Cycle dépassé** (jamais « 0 € par jour ») : quand le reste du cycle est nul ou négatif, X = les **courses habituelles par jour** (dépenses « Alimentation » des 3 cycles terminés ÷ leur nombre de jours), sauf si la limite manuelle est plus haute. Transport exclu (souvent un abonnement, déjà compté). L'accueil dit de combien le cycle est dépassé et que ce sera pris sur l'épargne.
> 3 derniers cycles : 896,04 € de courses en 94 jours → **9,53 €/jour**. « Budget du cycle dépassé de 42,10 €. Pour finir le cycle, vise 9,53 € par jour pour l'essentiel : ce sera pris sur ton épargne. »

**Le solde du compte courant nuance les conseils** (pas le chiffre X) :
- solde < abonnements à venir + 7 jours de dépenses moyennes → alerte « solde bas » ;
- solde très au-dessus de ce dont le cycle a besoin → conseil de mettre de côté (§ 6).

**Exemple au 30/10** (épargne visée de 300 €) :

| Ligne de « Pourquoi X € ? » | Montant |
| --- | --- |
| Paie du 26/10 | + 1 850,00 € |
| Épargne visée | − 300,00 € |
| Abonnements à venir avant le 28/11 (Prime ~3/11, Prixtel ~5/11, assurance auto ~6/11, Imagine R ~7/11, Claude ~7/11) | − 148,78 € |
| Déjà dépensé depuis le 26/10 | − 254,22 € |
| **Reste du cycle** | **1 147,00 €** |
| ÷ 29 jours restants | **39,55 €/jour** |
| **Tu peux encore dépenser aujourd'hui** | **39,55 €** |

## 4. Épargne visée

L'épargne visée d'un cycle est **proposée** par l'app puis **ajustable** :
- point de départ : la somme de ce que demandent les objectifs actifs pour ce cycle ;
- si aucun objectif n'est actif : proposition basée sur ce qui a réellement été mis de côté sur les 3 derniers cycles (ex. 250 € ce cycle-ci) ;
- elle peut toujours être changée pour ce cycle.

## 5. Objectifs et projets

**Un projet = un objectif d'épargne qu'on finit par dépenser** (voyage, permis, voiture…). Les grosses dépenses ne sont donc pas « exceptionnelles » : elles sont **financées par l'épargne du projet**.

**Verser de l'argent sur un objectif, en deux temps :**
1. Dans l'app : « Je mets 150 € de côté pour le voyage » → versement **en attente de virement**.
2. À la banque : virement de 150 € vers le livret (ex. livret LCL).
3. À la synchro, l'app repère dans « Économies » une entrée du **même montant** dans les jours qui suivent → le versement passe à **confirmé**. Sans virement correspondant après 7 jours : rappel « tu n'as pas encore fait le virement de 150 € pour le voyage ». Filet de sécurité si la reconnaissance échoue : bouton « J'ai fait le virement » pour confirmer à la main.

**Dépenser un projet** : quand la dépense arrive (ex. Airbnb 247,80 €), on la **rattache au projet** dans l'app → elle sort de l'enveloppe du jour et se déduit de ce qui a été épargné pour le projet. L'app le propose d'elle-même quand une dépense dépasse 100 € et qu'un projet actif a assez d'épargne (« Rattacher à Voyage ? ») ; rien n'est rattaché sans confirmation.

**Calculs par objectif** : reste = cible − épargné (confirmé) ; à mettre de côté par jour / semaine / mois = reste ÷ jours jusqu'à l'échéance ; rythme actuel = moyenne des versements sur 90 jours ; date estimée ; faisabilité 0–100 ; échéance dépassée → proposer de la **repousser**.

**Précisions :**
- **Versé ≠ disponible.** *Versé* = versements confirmés − retraits confirmés : c'est lui qui fait avancer l'objectif vers sa cible. *Disponible* = versé − dépenses rattachées : ce qu'il reste dans la tirelire pour ce projet. Payer l'Airbnb ne fait pas reculer l'objectif.
- **Rythme** = versements confirmés des 90 derniers jours (ou depuis la création de l'objectif, 30 jours minimum) ; « par mois » = par jour × 30,4. **Pas de rythme le premier mois** : tant que le premier versement confirmé date de moins de 30 jours, l'app affiche « 10 € mis de côté depuis le 30/10 », sans date estimée ni faisabilité. Imprévus reste sans échéance.
- **Exemple** (fictif) : objectif « Permis » de 1 200 €, **échéance choisie : le 30/04/2027**. Le 30/10/2026, 300 € sont déjà versés, au rythme de 100 €/mois → il reste 900 € à mettre de côté en 182 jours, soit 4,95 €/jour, 34,62 €/semaine ou 150,33 €/mois ; à ce rythme, l'objectif serait atteint vers le 27/07/2027, après l'échéance : faisabilité 67/100.
- **Reconnaissance d'un versement** : virement du même montant vers « Économies » fait entre 2 jours avant et 7 jours après la déclaration dans l'app.
- **Contester** : sur un versement confirmé automatiquement, « Ce n'est pas ce virement » le remet en attente ; ce virement ne lui sera plus jamais proposé (et redevient « à attribuer »). **Justifier** : « J'ai fait le virement » confirme à la main, en choisissant si besoin l'opération de la réserve.
- **Virement non déclaré** : une entrée dans « Économies » qui ne correspond à aucun versement déclaré → l'app demande « 150 € arrivés dans ta tirelire : pour quel objectif ? », Imprévus présélectionné. Idem pour une sortie de la réserve (« pour quel objectif as-tu pioché ? »). Seuls les mouvements à partir de la date de départ des objectifs (réglage `objectifs_depuis`) sont concernés.
- **Tirelire, dépensé, épargne totale** : *dans la tirelire* = versé − repris ; les dépenses rattachées ne retirent rien de la tirelire (l'argent en est déjà sorti quand il a été repris : sinon une dépense de projet compterait deux fois). Progression d'un **projet** = (tirelire + dépensé) ÷ cible ; d'**Imprévus** = tirelire ÷ cible (coussin à reremplir après une urgence). Ex. Voyage : 350 versés, 247,80 repris, Airbnb rattaché → tirelire 102,20, dépensé 247,80, 100 %. Ex. Imprévus : 1 000 versés, 200 repris, garage 185 → 800, 80 %.
- **Reprise suivie jusqu'aux dépenses** : pour chaque sortie de la réserve pas encore traitée, l'app suit l'argent (livret → compte LCL ; puis LCL → BoursoBank si le même montant arrive sur BoursoBank dans les 2 jours) et regarde les dépenses **comptabilisées** des 3 jours suivants sur le compte d'arrivée. Si elles font au moins la moitié de la reprise : « Tu as repris 200 € de ta tirelire le 03/11. C'était pour : … », les plus grosses dépenses qui tiennent dans le montant repris étant cochées d'avance. Objectif choisi → la reprise lui est attribuée (sauf si elle l'était déjà, par une pioche déclarée : objectif imposé) et les dépenses cochées lui sont rattachées. « Non, dépense normale » → rien n'est rattaché, la reprise reste « à attribuer » si elle ne l'était pas. La question n'est jamais reposée (`suggestion_ignoree` sur la reprise).
- **Rattacher une dépense** : en touchant une dépense sur l'accueil, on choisit l'objectif qui la paie (projet ou Imprévus) ou on la détache. La suggestion automatique ne concerne que les **projets** actifs ayant un disponible suffisant, pour les dépenses comptabilisées de plus de 100 € depuis le départ des objectifs ; « Non, dépense normale » la fait disparaître pour de bon. Une dépense **en attente** ne se rattache pas encore (elle est remplacée à chaque synchro) : l'app demande d'attendre qu'elle soit comptabilisée.
- **« C'était une annulation »** : pour une sortie de la réserve non déclarée, en plus du choix de l'objectif, l'app propose « C'était une annulation (rendre l'argent) ». Elle cherche les versements confirmés antérieurs dont la somme fait exactement le montant repris (les plus récents d'abord), les montre, puis sur validation les supprime ; l'aller et le retour dans la réserve sont marqués `reserve_annulee` et ne sont plus jamais « à attribuer ».

**Objectif permanent « Imprévus »** : épargne de précaution sans échéance, cible proposée ≈ 1 mois de dépenses (≈ 1 000 €, ajustable). Sert à financer les vraies urgences (réparation, santé…) sans faire s'effondrer la limite du jour.

**Piocher dans la tirelire** (Imprévus ou projet), deux mécanismes complémentaires :
- **Déclaration** : dans l'app, « Je pioche dans ma tirelire : 200 € pour Imprévus » ; la synchro confirme ensuite le virement et les dépenses (comme pour un versement).
- **Détection (filet de sécurité)** : à partir d'un retrait du livret (ou d'un virement LCL → BoursoBank) de montant R, l'app suit la chaîne en rapprochant les montants identiques à ± 2 jours (« Retrait livret » → « Virement à Prénom Nom » → « Virement reçu de LCL »), puis regarde les dépenses des 3 jours suivants sur le compte d'arrivée. Si elles consomment au moins la moitié de R, elle demande : « Tu as repris 200 € de ta tirelire mardi, puis dépensé 185 € chez Garage Martin. C'était pour : Imprévus · Voyage · autre projet · non, dépense normale ? ». Rien n'est rattaché sans confirmation.

## 6. Conseils d'épargne

Règles générales dans [conseils-locaux.md](conseils-locaux.md) : épargne simple uniquement, jamais d'investissement ni de fiscalité, uniquement si les données le justifient, avec un montant réel, 3 au maximum.

**Conseil de fin de cycle** — « injecter le reste dans la tirelire » :
- quand : dans les 7 derniers jours avant la paie (au plus tôt) ;
- condition : il reste un **surplus** = reste du cycle − (jours restants × dépense moyenne réelle par jour) − 20 € de marge, et ce surplus est positif ;
- proposition : **la moitié du surplus**, plafonnée à ce que demande l'objectif choisi ;
- exemple : « Il te reste 300 € à 5 jours de ta paie. Tu en as besoin d'environ 150 €. Mets 150 € dans ta tirelire pour le voyage ? » → un clic crée le versement en attente (§ 5).

**Paie atypique** : quand une paie dépasse nettement la moyenne des 3 précédentes (ex. 1 850 € contre ≈ 940 €), proposer dès son arrivée de mettre une partie du supplément de côté.

**Catégories apprises** : quand on reclasse une opération, la catégorie choisie est retenue pour le même marchand à l'avenir.

**Conseils de l'accueil** : carte « Conseils », 3 au maximum, classés par montant en jeu ; chacun s'appuie sur des opérations réelles et cite son montant.

1. **Paie plus haute que d'habitude** : paie > moyenne des 3 précédentes × 1,3 ; pendant les 7 premiers jours du cycle ; proposer la moitié du supplément, arrondie à 10 €.
   > 26/10 : 1 850,00 € contre (910,00 + 880,00 + 1 040,00) / 3 = 943,33 € → supplément 906,67 € → « Ta paie est plus haute que d'habitude (+907 €). Mets 450 € de côté dans Imprévus ? »
2. **Surplus de fin de cycle** : dans les 7 derniers jours avant la paie au plus tôt ; surplus = reste du cycle − jours restants × dépense moyenne réelle par jour (3 derniers cycles terminés) − 20 € ; proposer la moitié, arrondie à 5 €.
   > (1 000,00 + 950,00 + 1 040,00) / (32 + 31 + 31) = 31,81 €/jour ; le 21/11, 450 € pour 7 jours → besoin 222,67 € + 20 € de marge → surplus 207,33 € → « Mets 100 € de côté dans Imprévus ? »
3. **Réserve d'imprévus faible** : Imprévus sous son objectif, 7 premiers jours du cycle, pas de conseil 1 ; proposer 10 % de la paie habituelle (moyenne des 3 précédentes), arrondis à 10 €.
   > « Ta réserve Imprévus est à 40 € sur 1 000 €. En y versant 90 € à chaque paie, elle est pleine en 11 mois. »
4. **Catégorie qui s'emballe** : dans le cycle en cours, une catégorie dépasse déjà sa moyenne d'un cycle entier (cycles terminés, 6 au plus) d'au moins 30 € ; montant en jeu = le dépassement ; pas de bouton.
   > Loisirs 148,87 € depuis le 26/10, moyenne 70,02 € par cycle → « Loisirs : 148,87 € depuis ta paie, 2 fois ta moyenne d'un cycle entier (70 €). Lève le pied d'ici le 21/11. »
5. **Abonnement à couper** : usage « jamais » ; montant en jeu = prix sur un an ; bouton vers l'abonnement.
6. **Offre moins chère** (§ 12) : la meilleure offre moins chère de chaque ligne rattachée, hors essai gratuit, offre groupée et offre à revérifier ; montant en jeu = économie sur un an ; bouton « Voir les offres » vers le Catalogue.
> « Claude : l'offre Pro annuel (216 € payés d'avance) te coûterait 3,60 € de moins par mois, soit 43,20 € par an. »

**Versements proposés** (conseils 1 à 3) : bouton « Mettre X € de côté » = versement en attente (§ 5), vers Imprévus tant qu'il n'est pas plein, sinon le projet actif à l'échéance la plus proche (sinon le premier), plafonné à ce qu'il lui manque. « Pas maintenant » masque le conseil jusqu'au cycle suivant.

## 7. Abonnements

1. **Écran** : total mensuel des abonnements actifs et nombre de rentables ; une carte par abonnement (nom, icône, prix/mois, prochain prélèvement, usage, statut unique partagé par tous les écrans) ; filtres Tous / À revoir / À couper / Résiliés ; détail avec historique des prélèvements, évolution du prix, verdict, économie par an ; ajout à la main, modifier, résilier, supprimer.
2. **Montant** : prix fixe = le dernier prélèvement si les 2 derniers sont identiques (Prime 6,99, Claude 21,60) ; prix variable = moyenne des 3 derniers (Prixtel (14,98 + 16,98 + 14,98) ÷ 3 = 15,65 €, affiché avec sa fourchette) ; un montant corrigé à la main l'emporte (Imagine R 43,70 €, sans 8 € de frais de dossier ponctuels).
3. **Reconnaissance** : plusieurs libellés par abonnement (« Anthropic » / « Anthropic* Claude Sub » ; « IMAGINE R » / « Imagine R - COMUTITRES »), libellé ajoutable à la main.
4. **Statuts** : actif ; à vérifier (pas vu depuis 1,5 intervalle, 45 jours pour un mensuel) ; résilié (seulement sur décision de l'utilisateur). Les actifs et « à vérifier » comptent dans les abonnements à venir de la limite du jour, pas les résiliés.
5. **Verdict selon l'usage** : Toujours / Souvent = Rentable, Parfois = À revoir, Jamais = À couper (économie = montant × 12 par an) ; usage non renseigné → l'app le demande.
6. **Changement de prix** : écart de plus de 10 % → carte « Prixtel : 4,99 € → 15,65 €/mois depuis mai », OK ou corriger.
7. **Détection** : sur les 3 derniers prélèvements d'un marchand, intervalle mensuel (25–35 j) ou annuel, montants à ± 40 %, dernier prélèvement de moins de 45 jours, hors Alimentation / Restauration / Shopping / Distributeur, marchand pas déjà suivi ni refusé → « Nouvel abonnement ? Ajouter / Ce n'en est pas un » (réponse mémorisée). Boulangeries et supermarchés sont ainsi écartés.
8. **Prix maximum** (facultatif) : ce que le contrat peut coûter au plus, saisi dans la fiche. Prixtel : box 9,99 → **13,99 €**, téléphone 4,99 → **8,99 €** → maximum **22,98 €**, affiché « 15,65 € en moyenne · jusqu'à 22,98 € ». Vide pour un prix fixe (la carte « changement de prix » suffit). Un maximum inférieur au montant retenu est refusé.
   - **Budget du jour** : les abonnements à venir réservent le **maximum** quand il existe (Prixtel 22,98 € au lieu de 15,65 €, soit 7,33 € de moins sur le cycle, ≈ 0,25 €/jour) ; une fois le prélèvement passé, c'est son vrai montant qui compte dans le déjà dépensé, l'écart revient donc dans la limite.
   - **Dépassement** : un prélèvement au-dessus du maximum (Prixtel 24,98 € > 22,98 €) → carte sur l'écran Abonnements et notification `abonnement` (« Prixtel a prélevé plus que ton maximum »), une seule fois par prélèvement ; texte de notification sans montant (règle du § 10).
9. **Total mensuel = estimation** : « Environ 148,81 € par mois » (somme des montants retenus des abonnements actifs : 55,88 + 43,70 + 21,60 + 15,65 + 6,99 + 4,99), puis la fourchette « entre 148,14 € et 156,14 € » quand au moins un abonnement est variable : bas = le plus petit des 3 derniers prélèvements (Prixtel 14,98), haut = le prix maximum s'il existe, sinon le plus grand des 3 derniers. Sans abonnement variable ni maximum : « Environ … » sans fourchette. Bouton ⓘ : « Estimation à partir de tes derniers prélèvements ; les montants variables, les hausses de prix et les mois de pause le font bouger. »

**Cas particuliers** :
- **Imagine R** : forfait étudiant payé en **9 mensualités** (43,70 €) d'octobre à juin, rien de juillet à septembre (conditions Île-de-France Mobilités) → **mois de pause** juillet, août, septembre : ni « à vérifier », ni compté dans les abonnements à venir ces mois-là.
- **Prixtel** : deux lignes cumulées (9,99 € routeur 4G + 4,99 € téléphone, soit ≈ 14,98 €) avec des paliers selon les données consommées (9,99 → 11,99 → 13,99 ; 4,99 → 6,99 → 8,99) : montant variable, moyenne des 3 derniers.
- **Prélèvements réguliers qui ne sont pas des abonnements** (ex. prélèvements erronés d'un éditeur de jeux) : « Ce n'en est pas un » pour que la détection ne les propose plus jamais.

## 8. Stats

**Période = cycle de paie** (§ 1), pas le mois civil : un cycle commence le jour d'une paie et finit la veille de la suivante. Filtres : **Ce cycle · Cycle précédent · 6 cycles · 12 cycles**. Seuls les cycles complets en données sont montrés (`stats.PREMIER_CYCLE` : début du premier cycle complet).

**Dépenses** = même règle que le budget (§ 2) : sorties vers l'extérieur, en attente comprises, abonnements compris, remboursements déduits de leur catégorie ; ni virements entre comptes, ni revenus. **Les dépenses rattachées à un projet sont à part** : ligne « Payé par ton épargne : X € », hors du total et du donut.

**Donut par catégorie** : les 5 plus grosses catégories, puis « Le reste » ; une catégorie à 0 € ou moins (remboursée) n'apparaît pas. Toucher une part = liste de ses opérations.

> Cycle 25/09 → 25/10, 1 023,93 € : Alimentation 434,93 € (42 %), Shopping 214,96 € (21 %), Autre 107,37 € (10 %), Transport 70,70 € (7 %), Assurance 55,88 € (5 %), le reste 140,09 € (14 %).

**Comparaison avec le cycle d'avant**, par catégorie, affichée seulement si l'écart dépasse **10 % et 20 €** ; une catégorie absente du cycle d'avant est marquée « nouveau ».

> 25/09 → 25/10 comparé à 25/08 → 24/09 : Alimentation **+56 %** (+155,79 €), Shopping **−46 %** (−181,36 €), Autre **+228 %** (+74,67 €) ; Transport −5,10 € (−7 %) n'est pas affiché.

**Cycle en cours** : comparé aux **mêmes premiers jours** du cycle d'avant (sinon 6 jours contre 31 donneraient « Alimentation −86 % »). Ex. le 31/10 : Alimentation 61,64 € contre 33,06 € les 6 premiers jours du cycle d'avant → +86 % (+28,58 €). **Vues 6 et 12 cycles** : donut sur le total de la période, sans comparaison.

**Évolution** (6 ou 12 cycles) : une barre de dépenses par cycle et une ligne pour la moyenne des cycles terminés ; le cycle en cours est grisé, marqué « en cours », et n'entre pas dans la moyenne.

**Bilan du cycle** : entré (paie + virements reçus) − dépensé = reste du cycle (positif : mis de côté ou resté sur le compte ; négatif : pris sur l'épargne).

> 25/09 → 25/10 : 1 070,00 − 1 023,93 = **+46,07 €**.

**Jours sous la limite** : nombre de jours du cycle où la dépense du jour est restée sous la limite du jour, recalculée jour par jour avec les règles actuelles (§ 3) et sans les réglages manuels passés (ils ne sont pas historisés). Pour le cycle en cours, les jours écoulés seulement (« 4 jours sur 6 »).

## 9. Changer de catégorie

**Où** : en touchant une dépense (accueil, Historique, Stats), une feuille propose « Changer la catégorie » ou « Payer avec l'épargne d'un projet ».

**Catégories proposées** : Alimentation, Restauration, Shopping (vêtements compris), Transport, Loisirs, Sport, Santé, Maison, Abonnement, Assurance, Distributeur, Cadeau, Dons, Virement émis, Autre. Les catégories anciennes et rares restent sur leurs opérations mais ne sont plus proposées.

**« Retenir pour ce marchand »** (coché par défaut) : le choix est mémorisé (table `merchant_categories`) et appliqué
- à **toutes les dépenses passées** de ce marchand ;
- à **toutes les futures** : à la synchro, il passe après la détection des virements entre comptes, mais **avant** l'historique et les mots-clés.

**Même marchand** : on compare les noms nettoyés (minuscules, sans chiffres, ponctuation ni ville entre parenthèses) ; c'est le même marchand si les deux noms sont égaux ou si l'un **commence par l'autre**, le plus court faisant au moins 5 caractères. Nécessaire parce qu'une banque peut nommer différemment une opération en attente et comptabilisée.

> « C ET A FRANCE ville » (en attente, 31/10) → `c et a france ville` ; « C ET A FRANCE (Ville) » (comptabilisée, 15/08) → `c et a france`. Le second est le début du premier : même marchand. Choisir Shopping sur la dépense du 31/10 passe en Shopping les **23,98 €** du 31/10 et les **5,99 €** du 15/08 ; les prochains achats C&A arrivent directement en Shopping.

**Décoché** : seule cette dépense change. Exception : une dépense **en attente** est remplacée à chaque synchro, donc pour elle le choix est toujours retenu (case cochée et grisée).

**Jamais touchés** : les virements entre tes comptes et les entrées d'argent (paie, virements reçus, remboursements) ; seules les dépenses changent. La limite du jour et les Stats se recalculent tout de suite.

**Changer d'avis** : choisir une autre catégorie pour le même marchand remplace la règle.

## 10. Notifications

**Synchros automatiques** : 4 par jour, à **8 h, 12 h, 17 h et 21 h** (heure de Paris), le maximum que les banques permettent sans l'utilisateur (DSP2) ; celles lancées depuis l'app ne comptent pas. Les notifications sont évaluées à chacune de ces synchros, donc **jamais entre 22 h et 8 h** ; une alerte peut arriver quelques heures après la dépense.

**Texte neutre** : aucun montant ni marchand, visible tel quel sur l'écran verrouillé ; un pourcentage quand il a du sens, et une invitation à ouvrir Opti.

| Notification | Quand | Une seule fois par | Texte |
|---|---|---|---|
| Renouvellement de la banque | à la synchro de 12 h, quand il reste 14, 7 ou 1 jour(s) | banque + date d'expiration + palier | « Accès BoursoBank : expire dans 7 jours. Renouvelle-le dans Opti › Réglages. » |
| Synchro en panne | dernière synchro réussie d'une banque il y a plus de 24 h, ou accès expiré | banque + dernière réussite (ou expiration) | « LCL ne se synchronise plus depuis hier. Ouvre Opti pour vérifier. » |
| Limite du jour dépassée | dépensé aujourd'hui > limite du jour | jour | « Limite du jour dépassée (131 %). Ouvre Opti pour voir le détail. » |
| Paie reçue | une opération « Salaire » de moins de 3 jours | opération | « Ta paie est arrivée. Ouvre Opti pour voir ton budget du cycle. » |

> 01/11 à 17 h : 72,40 € dépensés pour une limite de 55,27 € → 72,40 / 55,27 = **131 %** ; à 21 h, toujours dépassée : rien de plus (une fois par jour).
>
> Accès BoursoBank jusqu'au 29/04/2027 : notifications le 15/04, le 22/04 et le 28/04 à 12 h.

**Réglages › Notifications** : un interrupteur par type, tous activés par défaut. Toucher une notification ouvre l'accueil (Réglages pour les deux notifications de banque).

## 11. Essais gratuits, alertes d'abonnements, bilan de cycle

**Essai gratuit** (colonnes `subscriptions.is_trial` et `trial_end_date`) : ajouté à la main (nom, prix après l'essai, fréquence, date de fin).
- Pendant l'essai : statut « essai », hors du total mensuel ; si la fin tombe dans le cycle en cours, le prix compte dans les abonnements à venir (prudence).
> Netflix, essai jusqu'au 15/11, 13,49 € ensuite ; cycle jusqu'au 24/11 vu le 01/11 (24 jours) : 13,49 € à venir, soit environ −0,56 €/jour. Résilié avant : la limite remonte.
- Rappels à la synchro de 12 h, à J-3 et J-1, **avec le nom du service** (toujours sans montant) : « Ton essai Netflix se termine dans 3 jours. Ouvre Opti pour le garder ou le résilier. »
- Un prélèvement du même marchand à partir de 3 jours avant la fin → l'essai devient un abonnement actif, tout seul. Fin passée sans prélèvement : statut « essai terminé », l'app demande « Tu l'as gardé ? » (Oui → actif ; Non → résilié).

**Alertes d'abonnements** (textes neutres, une fois par cas) :
- changement de prix de plus de 10 % (règle du § 7) : « Un abonnement a changé de prix (+20 %). Ouvre Opti pour vérifier. » ;
- nouvel abonnement détecté (§ 7) : « Un nouvel abonnement a été détecté. Ouvre Opti pour confirmer. »
Toucher ces notifications ouvre l'onglet Abonnements.

**Bilan de cycle** : la notification de paie résume le cycle qui vient de finir (jours sous la limite, en %) : « Ta paie est arrivée. Cycle précédent : 20 jours sur 31 sous ta limite (65 %). Ouvre Opti pour ton bilan. » Sur l'accueil, pendant 3 jours après la paie, une carte « Bilan du cycle » (refermable) : dépensé et écart à la moyenne des cycles terminés, reste du cycle, jours sous la limite, catégorie qui a le plus bougé, lien vers les Stats.
> Cycle 25/09 → 25/10 : 1 023,93 € dépensés, reste +46,07 €, 20 jours sur 31 sous la limite (65 %), Alimentation +56 %.

Interrupteurs : « Essais gratuits » (`notif_essai`), « Abonnements » (`notif_abonnement`, prix et nouveaux) ; le bilan suit « Paie reçue ».

## 12. Catalogue de prix et bons plans

**But** : repérer une offre moins chère pour un abonnement, les essais gratuits et les grandes promos des enseignes où l'on achète déjà. Uniquement de l'épargne simple : payer moins, jamais acheter plus. Aucune API publique fiable n'existe pour ces prix en France ; trois sources sont combinées.

**1. Catalogue** (tables datées et sourcées, modifiables sans republier l'app ; données de départ dans `supabase/seed_catalogue.sql`) : forfaits mobiles, IA (Claude, Google AI), Amazon Prime. Pas d'assurances (prix personnalisés). Chaque offre : service, nom, prix, fréquence, essai gratuit éventuel (« 1 mois offert »), condition (étudiant, moins de 26 ans), engagement, lien vers la page officielle, date de vérification. Le catalogue est le même qu'on soit abonné ou non.

**Rattachement** : Opti propose le service d'après le nom de l'abonnement (« Forfait mobile Prixtel » → Prixtel) ; on confirme une fois et on choisit son offre actuelle. Un abonnement peut regrouper **plusieurs lignes** prélevées ensemble : chacune a sa propre offre et se compare seule.
> Prixtel (un prélèvement, deux lignes) : routeur 4G 9,99 → 13,99 € selon la conso, téléphone 4,99 → 8,99 €. Chaque ligne est comparée avec son prix moyen et ses Go.

**Recherche** : barre de recherche dans le Catalogue, sans tenir compte des accents ni des majuscules, sur le nom du service, de l'offre et de l'opérateur (« prime » → Amazon Prime et ses offres).

**Prix promotionnels** (« 12,99 € pendant 1 an ») : la comparaison utilise le **prix d'après la promo**, pour éviter les surprises ; la promo est affichée à titre d'info. Même règle pour un abonnement en cours à prix promotionnel (suivi comme essai, § 11).

**Offre moins chère** : autre offre du même service ; pour les forfaits mobiles seulement, aussi un autre opérateur avec au moins autant de Go (Go de la ligne inconnus : pas de comparaison, l'app les demande). Les IA ne se comparent pas entre elles (Claude ≠ Google AI). Signalée seulement si l'économie atteint **au moins 1 €/mois ou 10 %** (prix ramenés au mois : annuel / 12, hebdomadaire × 52 / 12, toutes les 4 semaines × 13 / 12 : Basic-Fit 24,99 € → 27,07 €/mois).
> Prix fictifs : Prixtel 15,65 € (100 Go) ; offre X 9,99 € (130 Go) → 5,66 €/mois, **67,92 €/an**, signalée. Offre Y 15,00 € → 0,65 € (4 %), non signalée. Offre Z 9,99 € mais 80 Go → écartée.

**Conditions** : Réglages › Profil, trois interrupteurs : « Étudiant ou alternant », « Moins de 26 ans » et « 18-24 ans » (aucune date de naissance stockée). Une offre peut avoir plusieurs conditions, une seule suffit : Prime « étudiants et 18-24 ans » (3,49 €/mois, 34,95 €/an) = étudiant OU 18-24 ans. Si le service refuse le statut, il suffit de décocher l'interrupteur.

**Offres groupées** (« forfait + Amazon Prime ») : comparées à la somme de ce qu'elles remplacent, chaque élément pris à son **meilleur prix accessible** (Prime étudiant compris). Jamais transformées en conseil direct : elles s'affichent comme « à étudier », avec avantages et inconvénients (économie ou surcoût, Go, engagement, changement d'opérateur, ce qu'on perd).
> B&You 170 Go + Prime à 17,99 € contre ligne téléphone (≈ 6,99 €) + Prime étudiant 3,49 € = 10,48 € → **surcoût de 7,51 €/mois** : affichée comme « plus chère », avec ce qu'elle apporte (170 Go).

**Conseil** : une offre moins chère (hors offre groupée) devient un conseil (§ 6, conseil 6) : un par ligne au plus (la meilleure), jamais pour un essai gratuit ni un abonnement résilié, classé avec les autres par **l'économie sur un an**. « Pas maintenant » le cache jusqu'au cycle suivant.

**12 mois** : une offre vérifiée il y a plus de 12 mois porte le badge « à revérifier » et ne sert plus aux conseils.
> Vérifiée le 01/11/2025 → « à revérifier » à partir du 02/11/2026.

**2. Surveillance des pages officielles** (le 1er du mois, à la synchro de 8 h, méthode semi-automatique sans IA) : le serveur lit chaque page et relève l'ensemble des montants en euros affichés. Si cet ensemble change, la page est « modifiée » : notification neutre « Une page de prix a changé. Ouvre Opti pour vérifier. » (interrupteur `notif_catalogue`). Dans l'app : ancien prix, montants trouvés, lien vers la page ; un clic sur le nouveau montant, ou sur « Rien ne change », met à jour le prix et la date de vérification. Page illisible (blocage, page en JavaScript) : « suivi manuel », sans notification répétée.
> 01/10 : {9,99 ; 19,99} ; 01/11 : {10,99 ; 19,99} → modifiée, une notification. 01/12 : {10,99 ; 19,99} → rien.

**3. Bons plans Dealabs** (flux RSS publics : tous, tendance, gratuit, forfaits mobiles, high-tech, mode, culture, services ; lus par le serveur à chaque synchro automatique, 30 derniers bons plans par flux, donc un signal et pas une liste complète ; chaque bon plan donne l'enseigne, le prix et le lien) :
- **Enseignes suivies** : déduites des dépenses des 12 derniers mois en Shopping, Loisirs, Maison et Sport (au moins 2 achats ou 40 € au total), puis liste modifiable (ajouter, retirer). Même enseigne : règle du § 9 (préfixe d'au moins 5 caractères), ou noms identiques pour les noms courts (« FNAC » = « Fnac »). « AMAZON PAYMENTS » et « AMAZON EU SARL » → Amazon.
- **Essais gratuits** : bons plans dont le titre parle d'essai ou de mois offert(s) pour un service du catalogue ; « Je le démarre » le crée comme essai (§ 11, rappels J-3 et J-1).
- Le filtrage se fait dans Opti : la liste des enseignes suivies ne sort jamais du serveur. Bons plans de moins de 7 jours, page « Bons plans » sans notification (pas d'incitation à acheter).
> Bon plan « Amazon — 449 € » : Amazon suivie → affiché. « Foot Locker — 76,50 € » : non suivie → ignoré.

**4. Calendrier des grandes promos** (dates rangées dans le catalogue, vérifiées chaque année sur Légifrance pour les soldes) : soldes d'hiver et d'été (4 semaines ; règle de l'arrêté du 27/05/2019 : 2ᵉ mercredi de janvier, avancé au 1ᵉʳ s'il tombe après le 12 ; dernier mercredi de juin, avancé à l'avant-dernier s'il tombe après le 28), Black Friday (lendemain du 4ᵉ jeudi de novembre). La veille, à la synchro de 12 h : « Les soldes commencent demain. Ouvre Opti pour voir ta marge ce mois-ci. » ; la notification ouvre le budget (interrupteur `notif_promos`).
> Black Friday 2026 : 4ᵉ jeudi = 26/11 → 27/11, notification le 26/11 à 12 h. Soldes d'hiver 2027 : 2ᵉ mercredi = 13/01, après le 12 → **06/01** (à confirmer).
