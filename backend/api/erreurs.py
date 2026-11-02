"""Erreurs métier communes : l'API les traduit une seule fois en réponses HTTP (voir index.py)."""


class ActionRefusee(Exception):
    """Action impossible dans l'état actuel : 409, avec un message affichable tel quel dans l'app."""
