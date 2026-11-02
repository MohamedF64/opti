# Apparence : thèmes, modes et fonds

## Principe
Le **thème** choisit l'univers (Holocron, Forêt ou Océan), le **mode** choisit clair, sombre ou auto (suit le téléphone, par défaut). Chaque combinaison a ses propres couleurs **et** son propre fond : le texte reste toujours lisible, jamais de texte sombre sur fond sombre.

Règles de lisibilité :
- le fond suit le mode (pas de mode clair posé sur un ciel étoilé) ;
- le fond est toujours sous un voile et sous des cartes opaques à 78 % minimum ;
- icônes uniquement (pas d'emojis mélangés), libellés en français ;
- code couleur : vert = OK / rentable, or = conseil / à revoir, rouge = dépassement.

## Couleurs
| Token | Holocron sombre | Holocron clair | Forêt sombre | Forêt clair |
| --- | --- | --- | --- | --- |
| Fond | `#0F0A22` | `#FFF7EE` | `#0D1D15` | `#F1F6F0` |
| Surface | `#1B1436` à 78 % | `#FFFFFF` à 90 % | `#13261C` à 80 % | `#FFFFFF` à 90 % |
| Texte | `#F1ECFF` | `#2A1A24` | `#E9F4EC` | `#13221A` |
| Texte secondaire | `#ABA0CB` | `#7E6E76` | `#A3BEAD` | `#56665C` |
| Accent | `#A67CF8` | `#D42A7C` | `#74D39C` | `#1D7A48` |
| Or (accent 2) | `#F5B342` | `#D98A17` | `#E3C77A` | `#A66B00` |
| OK | `#34D399` | `#0A8F63` | `#74D39C` | `#1D7A48` |
| Alerte | `#F87171` | `#D42B2B` | `#F28B82` | `#C62828` |

**Océan** : clair fond `#EAF6FB`, texte `#0B2545`, accent `#0B6FA4`, corail `#C2410C` ; sombre fond `#061826`, texte `#E6F6FB`, accent `#2DD4BF`, corail `#FB923C`.

Les couleurs vivent dans `app/lib/theme/opti_theme.dart` (`OptiColors.de`) ; les éléments dérivés (boutons, curseurs…) viennent de `ColorScheme.fromSeed` sur l'accent.

**Polices**, intégrées à l'APK (aucun téléchargement, l'app marche hors ligne) : Holocron = DM Sans + DM Mono (montants) ; Forêt = Fraunces (titres) + Figtree ; Océan = Fredoka (titres) + Nunito.

## Fonds animés
Dessinés en `CustomPainter`, avec une seule horloge à 30 images/s (`app/lib/widgets/fond_anime.dart`) ; en pause quand l'app est en arrière-plan, figés si « Réduire les animations » est activé.
- **Holocron** : ciel d'étoiles presque noir, voile violet discret, lueur dorée, croix bleues qui scintillent, étoile filante ; en clair, croix violettes et framboise sur fond crème.
- **Forêt** : vallée de montagne (nuages, sommets enneigés, brume, collines, lac, sapins) ; la nuit, lucioles. Nature seulement.
- **Océan** : aquarium en plein jour (rayons, rochers, algues, corail, bulles, poissons) ; la nuit, la même scène sous la lune.

## Réglages › Apparence
- Mode : Clair / Sombre / Auto.
- Thème : Holocron / Forêt / Océan.
- Fond : Animé / Uni / Image (choisie dans la galerie, copiée dans le dossier de l'app ; un seul fichier conservé). Pas de vidéo : trop lourd pour l'intérêt.
- Lisibilité de l'image : flou 0–20 px, voile 0–70 % (noir en sombre, crème en clair) ; par défaut après un import : flou 8 px, voile 35 %.
- Accent tiré de l'image : couleur dominante, ajustée pour rester lisible dans le mode actif.

Les réglages d'apparence ne sont pas des données personnelles : ils restent sur le téléphone (en clair) et sont gardés à la déconnexion.
