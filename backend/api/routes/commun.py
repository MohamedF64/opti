"""Ce que partagent toutes les routes : l'authentification et la date du jour."""
import os
from datetime import date, datetime

import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

import budget

# La page de test /docs et les routes …/apercu n'existent qu'en Preview et en local, jamais en production.
EST_PRODUCTION = os.environ.get("VERCEL_ENV") == "production"

# Supabase signe les jetons en ES256 et publie la clé de vérification :
# aucun secret n'est nécessaire côté backend.
SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
OWNER_USER_ID = os.environ.get("OWNER_USER_ID")
_jwks_client = jwt.PyJWKClient(f"{SUPABASE_URL}/auth/v1/.well-known/jwks.json", cache_keys=True)
_bearer = HTTPBearer(auto_error=False)


def require_owner(creds: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> str:
    """Refuse toute requête qui ne porte pas un jeton Supabase valide émis pour le propriétaire."""
    if not SUPABASE_URL or not OWNER_USER_ID:
        # Configuration incomplète : on refuse plutôt que de laisser passer.
        raise HTTPException(500, "Authentification non configurée côté serveur")
    if creds is None:
        raise HTTPException(401, "Connexion requise", headers={"WWW-Authenticate": "Bearer"})

    try:
        signing_key = _jwks_client.get_signing_key_from_jwt(creds.credentials)
        claims = jwt.decode(
            creds.credentials,
            signing_key.key,
            algorithms=["ES256"],
            audience="authenticated",
            issuer=f"{SUPABASE_URL}/auth/v1",
        )
    except (jwt.PyJWTError, jwt.PyJWKClientError):
        raise HTTPException(401, "Session invalide ou expirée", headers={"WWW-Authenticate": "Bearer"})

    if claims.get("sub") != OWNER_USER_ID:
        raise HTTPException(403, "Accès réservé")
    # Double authentification : « aal2 » = mot de passe + code à 6 chiffres validés à la connexion.
    if claims.get("aal") != "aal2":
        raise HTTPException(403, "Code de vérification requis")
    return claims["sub"]


# À poser sur chaque groupe de routes de l'app : APIRouter(dependencies=PROPRIETAIRE).
PROPRIETAIRE = [Depends(require_owner)]


def aujourdhui() -> date:
    return datetime.now(budget.PARIS).date()
