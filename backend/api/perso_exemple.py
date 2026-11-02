"""Réglages propres à une installation d'Opti : copie ce fichier en perso.py et remplis-le.

perso.py n'est jamais publié. Sans lui, Opti utilise ce modèle (aucun nom, aucun mot-clé en plus)."""

# Ton nom tel qu'il apparaît sur les virements entre tes comptes, en minuscules : ("prenom nom",).
# Sert à reconnaître une épargne reprise (virement de ta réserve vers ton compte courant).
NOMS_TITULAIRE: tuple[str, ...] = ()

# Mots-clés en plus de ceux de synchro.REGLES, par catégorie (« Alimentation », « Restauration », « Salaire »…) :
# les commerces de ton quartier, ton employeur… Exemple : {"Salaire": ("mon employeur",)}.
MOTS_CLES: dict[str, tuple[str, ...]] = {}
