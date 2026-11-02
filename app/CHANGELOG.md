# Journal des versions d'Opti

Numérotation `MAJEUR.MINEUR.CORRECTIF+construction` (dans `pubspec.yaml`) :
- **MINEUR** : un nouvel écran ou une nouvelle fonction ;
- **CORRECTIF** : une correction sans nouveauté ;
- **construction** : augmente à chaque APK publié (Android refuse une mise à jour qui le fait reculer).

L'app reste en `0.x` tant que la refonte (chantier 3) n'est pas terminée ; `1.0.0` marquera la première version complète.
Publier une version : `./publier.sh 0.7.0` (voir le script).

## 1.0.0 (41) — 02/11/2026
**Première version complète d'Opti** : fin de la refonte (chantier 3).
- Accueil (limite du jour et son « pourquoi », cycle de paie, bilan, conseils), Objectifs et projets, Stats, Abonnements (essais, prix maximum, total estimé), Catalogue de prix et Bons plans, Historique, Réglages (budget, banques, notifications, apparence, sécurité).
- Sécurité : verrou à 4 chiffres et empreinte, cache et session chiffrés, double authentification, aucune sauvegarde Google.
- Dans cette version : fond plein pour la pastille de synchro de l'accueil ; dans la fiche d'un abonnement à prix variable, le champ « Montant » prévient que le modifier le rend fixe ; paquet d'icônes iPhone inutilisé retiré.

## 0.26.0 (40) — 02/11/2026
- **Abonnements** : « Prix maximum » facultatif dans la fiche (Prixtel : 22,98 €), affiché « en moyenne · jusqu'à » ; la limite du jour réserve ce maximum ; un prélèvement au-dessus fait apparaître une carte « Au-dessus du maximum » et une notification.
- **Total par mois** présenté comme une estimation : « Environ … », fourchette quand un montant varie, et ⓘ qui explique pourquoi il bouge.
- **Catalogue de prix** : barre de recherche (service, opérateur, offre ; sans accents ni majuscules).

## 0.25.0 (39) — 02/11/2026
- **Sécurité** : double authentification. À la connexion, après le mot de passe, Opti demande un code à 6 chiffres de Google Authenticator (une seule fois par connexion, pas à chaque ouverture ; le verrou et l'empreinte ne changent pas). À la première ouverture, l'activation est obligatoire : « Ouvrir Google Authenticator » (ou clé à saisir à la main), puis le premier code. Réglages › Sécurité rappelle quoi faire en cas de téléphone perdu (codes sauvegardés dans le compte Google).

## 0.24.0 (38) — 02/11/2026
- **Sécurité** : le cache des écrans (soldes, opérations, objectifs, abonnements, stats) et la session de connexion sont désormais **chiffrés** dans le coffre Android (clé du Keystore), comme le code du verrou ; les anciennes copies en clair sont déplacées puis effacées à la première ouverture (pas besoin de se reconnecter).
- Opti est exclue de la **sauvegarde Google** et du transfert vers un nouveau téléphone : après un changement de téléphone, il faudra se reconnecter.

## 0.23.0 (37) — 01/11/2026
- **Cycle dépassé** : la limite du jour ne tombe plus à 0 € ; elle devient tes courses habituelles par jour (3 derniers cycles), et l'accueil dit de combien le cycle est dépassé.
- Détail d'un abonnement : « Moins cher dans le catalogue », avec l'économie par an (une option, qui ne contredit pas le verdict).

## 0.22.0 (36) — 01/11/2026
- **Conseil « offre moins chère »** sur l'accueil : la meilleure offre du catalogue pour chaque ligne rattachée (hors essai gratuit et offre groupée), classé avec les autres conseils par l'économie sur un an ; bouton « Voir les offres » vers le Catalogue.

## 0.21.1 (35) — 01/11/2026
- Bons plans : **barre de recherche** (titre et enseigne, sans tenir compte des accents ni des majuscules).
- Boutons « Catalogue de prix » et « Bons plans » sur fond plein, lisibles par-dessus le fond animé.
- Fin d'essai affichée avec l'année quand ce n'est pas l'année en cours (Google AI plus : 27/10/2027).

## 0.21.0 (34) — 01/11/2026
- **Catalogue de prix** (Abonnements › Catalogue de prix) : rattacher un abonnement à une offre, avec plusieurs lignes si besoin (Prixtel : téléphone + box 4G, Go de chaque ligne) ; jusqu'à 3 offres moins chères avec l'économie par mois et par an, et leurs badges (étudiant ou 18-24 ans, promo, payé d'avance, à revérifier) ; offres groupées « à étudier » (avantages, inconvénients, jamais conseillées) ; catalogue daté et sourcé ; profil à 3 interrupteurs.
- **Page de prix modifiée** : montants apparus et disparus, nouveau prix en un toucher ou « Rien ne change » ; vérification d'une offre à la main (Sosh et Claude : suivi manuel). La notification ouvre le Catalogue.
- **Bons plans** (Abonnements › Bons plans) : bons plans Dealabs des 7 derniers jours par enseigne, essais gratuits, enseignes ajoutées ou retirées.
- Réglages › Notifications : « Catalogue de prix » et « Soldes et Black Friday ».

## 0.20.1 (33) — 01/11/2026
- Holocron clair : étoiles bien visibles sur la crème (croix violettes et framboise, petits points violets qui scintillent) au lieu du doré pâle qui s'y perdait.

## 0.20.0 (32) — 01/11/2026
- **Forêt refait** : une vallée de montagne peinte (gros nuages qui dérivent, deux sommets enneigés, brume, collines, lac turquoise qui scintille, sapins qui se balancent) ; la nuit : ciel étoilé, lune, reflet sur le lac, lucioles.
- **Fond › Image** : ta propre image depuis la galerie (un seul fichier gardé, dans l'app), avec **flou** (0 à 20 px) et **voile** (0 à 70 %) pour garder le texte lisible (8 px et 35 % par défaut), et **accent tiré de l'image** (couleur dominante, ajustée au mode).

## 0.19.1 (31) — 01/11/2026
- **Holocron refait** : ciel d'étoiles presque noir avec un voile violet très discret et une petite lueur dorée en haut ; ~150 étoiles blanches qui scintillent, ~25 étoiles en croix bleues qui brillent puis s'éteignent, une étoile filante toutes les 30 s environ. En clair : ciel crème et croix dorées discrètes. (Planètes et bandes orbitales retirées.)

## 0.19.0 (30) — 01/11/2026
- **Thème Océan** (maquette « aquarium ») : ciel et nuages, vagues, rayons de lumière, rochers, algues qui se balancent, corail, éponge, sable, bulles qui montent et 3 poissons qui traversent ; la nuit en mode sombre (lune, étoiles, eau profonde). Titres en Fredoka, texte en Nunito (intégrées).
- Donut : 3e teinte jaune quand l'accent est déjà bleu (Océan clair).

## 0.18.0 (29) — 01/11/2026
- **Fonds animés** (comme la maquette) : Holocron sombre (lueur dorée qui respire, 3 planètes, 3 bandes orbitales qui ondulent, 80 étoiles qui scintillent), Holocron clair (crème, lueur dorée, bandes rose pâle), Forêt (5 halos de brume qui dérivent).
- Réglages › Apparence › Fond : **Animé** ou **Uni**. Animation à 30 images/s, arrêtée en arrière-plan, figée si le téléphone demande de réduire les animations.

## 0.17.3 (28) — 01/11/2026
- Donut : 5e teinte violette en Forêt (elle se confondait avec le vert de l'accent), turquoise en Holocron.
- « Vêtements » n'est plus proposé : fusionné dans Shopping.

## 0.17.2 (27) — 01/11/2026
- Donut des Stats : 6 teintes bien distinctes dans chaque thème (en Forêt, Loisirs et Vêtements avaient le même vert).
- Pastilles, sélecteurs et onglet actif suivent la couleur du thème (plus de violet en Forêt).
- Conseils : « Mettre 520 € de côté » (sans centimes) ; le « € » ne passe plus seul à la ligne.

## 0.17.1 (26) — 01/11/2026
- Polices intégrées à l'app (DM Sans, DM Mono, Fraunces, Figtree : 684 Ko) : plus aucun téléchargement, le thème Forêt s'affiche correctement même hors ligne.

## 0.17.0 (25) — 01/11/2026
- **Réglages › Apparence** : mode Clair / Sombre / **Auto** (suit le téléphone, par défaut) et thème **Holocron** (violet et or) ou **Forêt** (vert et brume, titres en Fraunces, texte en Figtree).
- Les 4 combinaisons ont chacune leurs couleurs (plus jamais de texte sombre sur fond sombre) ; barre d'état lisible en clair comme en sombre.
- Boutons principaux en dégradé, comme la maquette.

## 0.16.0 (24) — 01/11/2026
- **Conseils** sur l'accueil (3 au plus, avec leur montant) : paie plus haute que d'habitude, surplus de fin de cycle, réserve d'imprévus faible, catégorie qui s'emballe, abonnement jamais utilisé.
- « Mettre X € de côté » crée le versement en attente dans Imprévus (ou le projet le plus proche) ; « Pas maintenant » masque le conseil jusqu'au cycle suivant.

## 0.15.0 (23) — 01/11/2026
- **Essais gratuits** (bouton cadeau dans Abonnements) : prix après l'essai et date de fin ; rappels à J-3 et J-1 avec le nom du service ; le prix compte dans ta limite si l'essai finit dans le cycle ; à la fin, « Tu l'as gardé ? » (ou abonnement actif tout seul dès le premier prélèvement).
- **Alertes d'abonnements** : changement de prix et nouvel abonnement détecté ; toucher la notification ouvre l'onglet Abonnements.
- **Bilan du cycle** : la notification de paie donne tes jours sous la limite du cycle fini ; carte « Bilan du cycle » sur l'accueil pendant 3 jours (dépensé / moyenne, reste, jours sous la limite, catégorie qui a le plus bougé, « Voir les stats »).
- Réglages › Notifications : interrupteurs « Essais gratuits » et « Abonnements ».

## 0.14.2 (22) — 01/11/2026
- Notification de test : plus de faux « Serveur injoignable » en revenant dans Opti (la réponse du serveur n'est plus attendue).

## 0.14.1 (21) — 01/11/2026
- Notification de test envoyée 10 secondes après le toucher, le temps de quitter Opti (Android n'affiche pas de bannière pour l'app ouverte).

## 0.14.0 (20) — 01/11/2026
- **Notifications** (Firebase) : limite du jour dépassée (avec le pourcentage), paie reçue, accès bancaire à renouveler (14, 7 et 1 jour avant), synchro en panne. Texte neutre, sans montant.
- Envoyées après les synchros automatiques de 8 h, 12 h, 17 h et 21 h : jamais la nuit.
- Réglages › Notifications : un interrupteur par type et « Envoyer une notification de test ».
- Toucher une notification ouvre l'accueil (ou les Réglages pour une banque).

## 0.13.0 (19) — 01/11/2026
- **Code à 4 chiffres et empreinte** (Réglages › Sécurité) : Opti se verrouille à l'ouverture et au retour après 1 minute ailleurs (ou tout de suite, ou 5 minutes) ; l'empreinte est demandée toute seule, le code reste en secours.
- 5 codes faux ou « Code oublié ? » : déconnexion, puis nouveau code proposé après la reconnexion.
- Le code reste sur le téléphone (haché dans le coffre Android) ; les apps récentes ne montrent pas tes soldes.
- Le compte Revolut courant s'appelle « Principal ».

## 0.12.0 (18) — 01/11/2026
- Toucher une dépense (accueil, Historique, Stats) propose **Changer la catégorie** ou **Payer avec l'épargne d'un projet**.
- « Retenir pour ce marchand » (coché par défaut) : toutes ses dépenses passées et futures passent dans la catégorie choisie ; toujours retenu pour une dépense en attente.

## 0.11.0 (17) — 31/10/2026
- Onglet **Stats**, par cycle de paie (de ta paie à la veille de la suivante) : Ce cycle, Cycle précédent, 6 cycles, 12 cycles.
- Bilan : dépensé, entré, reste (ou pris sur l'épargne), payé par ton épargne (projets, hors du total), jours sous ta limite du jour.
- Donut par catégorie (5 plus grosses puis « Le reste ») avec l'évolution par rapport au cycle d'avant quand elle dépasse 10 % et 20 € ; le cycle en cours est comparé aux mêmes premiers jours.
- Évolution sur 6 ou 12 cycles : une barre par cycle, ligne de la moyenne des cycles terminés.
- Toucher une catégorie : la liste de ses dépenses, avec la possibilité d'en rattacher une à un projet.

## 0.10.2 (16) — 31/10/2026
- Banques : bouton « Copier le lien » à côté de « Renouveler l'accès », pour finir le renouvellement sur l'ordinateur (QR code à scanner avec le téléphone) si le retour vers le navigateur échoue (cas de Revolut). Le lien reste valable une heure.

## 0.10.1 (15) — 31/10/2026
- Réglages : le numéro de version n'est plus coupé par la barre de navigation du téléphone, et s'affiche sans le numéro de construction (« Opti 0.10.1 »).
- Banques : les jours restants sont comptés en jours du calendrier (accès jusqu'au 29 avril vu le 31 octobre → 180 jours, plus 179).
- Renouvellement d'accès : une heure (au lieu de 15 minutes) pour valider chez la banque, Revolut pouvant être lent.

## 0.10.0 (14) — 31/10/2026
- **Réglages** (roue dentée en haut de l'accueil) : limite manuelle (marge de sécurité, ou plafond en mode économies max), épargne visée (proposée par tes objectifs ou choisie), jours de paie ; l'effet sur ta limite s'affiche avant d'enregistrer (« passerait de 60,92 € à 70,00 € »).
- Banques : date d'expiration de l'accès, dernière synchro, « Renouveler l'accès » (ouvre la banque dans le navigateur, bouton « Revenir à Opti », synchro au retour). Sert aussi à relier un autre compte (Livret A).
- Accueil : carte de rappel 14 jours avant l'expiration d'un accès bancaire (rouge à 7 jours).
- « Se déconnecter » et la version de l'app passent dans les Réglages.

## 0.9.3 (13) — 31/10/2026
- Accueil, carte du cycle : dès qu'il y a des dépenses dans la journée, « après aujourd'hui : 1 501,33 € · ≈ 55,60 €/jour dès demain » (en orange si la limite de demain baisse). Le reste du cycle affiché au-dessus reste celui du début de journée, qui fixe la limite du jour.

## 0.9.2 (12) — 31/10/2026
- Correction d'affichage : un libellé long (« Imagine R - COMUTITRES SAS ») ne se colle plus au montant, dans les prélèvements d'un abonnement comme dans l'accueil, l'historique et les objectifs.

## 0.9.1 (11) — 31/10/2026
- Abonnements : l'usage choisi (Jamais → Toujours) et le verdict s'affichent dès le toucher ; l'enregistrement se fait en arrière-plan (retour en arrière avec un message s'il échoue) et l'accueil n'est plus recalculé pour rien.

## 0.9.0 (10) — 31/10/2026
- Onglet **Abonnements** : total par mois, nombre de rentables, filtres (Tous, À revoir, À couper, Résiliés), une carte par abonnement avec son statut et le prochain prélèvement.
- Détail : montant (fixe, variable avec sa fourchette, ou corrigé à la main), usage (Jamais → Toujours) et verdict, économie par an si « à couper », historique des prélèvements, mois sans prélèvement.
- « Nouvel abonnement ? » (détection sur les 3 derniers prélèvements) et « Le prix a changé » (écart de plus de 10 %).
- Ajouter, modifier, « J'ai résilié », supprimer.
- La limite du jour compte Prixtel à son montant réel (≈ 15,65 €) et respecte la pause d'été d'Imagine R.

## 0.8.0 (9) — 31/10/2026
- « Repris de ta tirelire » : quand de l'argent sort de ta réserve puis est dépensé dans les 3 jours (sur Revolut, ou au CIC s'il y a été viré), l'app demande pour quel objectif et propose de rattacher ces dépenses (cochées d'avance, modifiables).
- Correction : une dépense payée avec la tirelire ne compte plus deux fois. Un projet avance avec « dans la tirelire + déjà dépensé » ; Imprévus avec ce qui est dans la tirelire (à reremplir après une urgence).

## 0.7.1 (8) — 31/10/2026
- Historique : flèche en bas à droite pour remonter tout en haut (apparaît une fois descendu d'environ un écran).

## 0.7.0 (7) — 31/10/2026
- Historique (« Tout voir » sur l'accueil) : toutes les opérations regroupées par jour avec le total dépensé, chargement au fil du défilement, recherche, filtre CIC / Revolut.
- Les virements entre tes comptes y apparaissent en gris (« Virement interne »).
- Toucher une dépense de l'historique : la payer avec un objectif, comme sur l'accueil.

## 0.6.0 (6) — 31/10/2026
- Toucher une dépense de l'accueil pour la payer avec l'épargne d'un objectif (ou la détacher).
- « Payé avec ton épargne ? » : proposition pour une dépense de plus de 100 € qu'un projet peut couvrir ; « Non, dépense normale » la fait disparaître.
- Détail d'un objectif : liste des dépenses qu'il a payées.

## 0.5.0 (5) — 31/10/2026
- Ouverture instantanée : les derniers chiffres connus s'affichent pendant la synchro (cache effacé à la déconnexion).
- Pas de nouvelle synchro à l'ouverture si la dernière a moins de 2 minutes.
- Côté serveur : Dublin, connexions réutilisées, lectures en parallèle (budget 3,6 → 0,3 s ; synchro 9 → 3,7 s) ; solde CIC = comptabilisé + opérations en attente.

## 0.4.0 (4) — 31/10/2026
- « C'était une annulation » : un retrait de la tirelire qui annule des versements les efface de l'historique.

## 0.3.0 (3) — 30/10/2026
- Écran Objectifs et barre de navigation : liste, détail, mettre de côté, piocher, « J'ai fait le virement », « Ce n'est pas ce virement », virements à attribuer.
- Pas de rythme ni d'estimation avant un mois d'historique.

## 0.2.0 (2) — 30/10/2026
- Polices DM Sans (texte) et DM Mono (montants), d'après la maquette « Refonte 2026 ».

## 0.1.0 (1) — 30/10/2026
- Connexion, écran d'accueil (« tu peux encore dépenser », « Pourquoi X € ? », cycle de paie, opérations du jour, comptes), synchro à l'ouverture.
