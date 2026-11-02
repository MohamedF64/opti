"""Connexion à Opti depuis un script local : mot de passe puis code à 6 chiffres (jamais affichés ni enregistrés).

Adresses et e-mail : tools/config_locale.py (dépôt privé uniquement ; modèle : config_locale_exemple.py)."""
import getpass
import json
import sys
import urllib.error
import urllib.request

try:
    import config_locale as config
except ImportError:
    sys.exit("Copie tools/config_locale_exemple.py en tools/config_locale.py et remplis-le.")

SUPABASE_URL = config.SUPABASE_URL
# Clé publiable : conçue pour être publique (elle est aussi dans l'app). Sans mot de passe
# ni code, elle ne donne accès à rien grâce à la RLS et aux inscriptions fermées.
SUPABASE_PUBLISHABLE_KEY = config.SUPABASE_PUBLISHABLE_KEY
BACKEND_URL = config.BACKEND_URL
EMAIL = config.EMAIL


def post(url: str, body: dict, headers: dict, timeout: int = 60) -> dict:
    req = urllib.request.Request(url, json.dumps(body).encode(), {"Content-Type": "application/json", **headers})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:300]
        sys.exit(f"Échec ({e.code}) sur {url.split('?')[0]} : {detail}")


def jeton_opti() -> str:
    """Session complète (aal2) : le backend refuse une session ouverte avec le seul mot de passe."""
    mot_de_passe = getpass.getpass(f"Mot de passe Opti pour {EMAIL} (rien ne s'affiche) : ")
    session = post(f"{SUPABASE_URL}/auth/v1/token?grant_type=password",
                   {"email": EMAIL, "password": mot_de_passe}, {"apikey": SUPABASE_PUBLISHABLE_KEY})
    facteurs = [f for f in session.get("user", {}).get("factors") or []
                if f.get("factor_type") == "totp" and f.get("status") == "verified"]
    if not facteurs:
        sys.exit("Aucun code de vérification activé : ouvre d'abord l'app pour activer la double authentification.")
    entetes = {"apikey": SUPABASE_PUBLISHABLE_KEY, "Authorization": f"Bearer {session['access_token']}"}
    facteur = facteurs[0]["id"]
    defi = post(f"{SUPABASE_URL}/auth/v1/factors/{facteur}/challenge", {}, entetes)
    code = getpass.getpass("Code à 6 chiffres de Google Authenticator (rien ne s'affiche) : ").strip()
    session = post(f"{SUPABASE_URL}/auth/v1/factors/{facteur}/verify", {"challenge_id": defi["id"], "code": code},
                   entetes)
    print("Connexion à Opti réussie.")
    return session["access_token"]


def appeler_backend(chemin: str, jeton: str, corps: dict | None = None, timeout: int = 60) -> dict:
    return post(f"{BACKEND_URL}{chemin}", corps or {}, {"Authorization": f"Bearer {jeton}"}, timeout)
