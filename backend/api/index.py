"""API d'Opti (FastAPI sur Vercel) : assemble les routes de chaque écran et traduit les erreurs en réponses HTTP.

Les routes sont dans routes/, les calculs dans les modules voisins (budget.py, objectifs.py…)."""
import os
import sys

# Vercel charge ce fichier sans mettre son dossier dans le chemin d'import :
# on l'ajoute pour que les modules voisins (enable_banking…) soient trouvés.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi import FastAPI, Request  # noqa: E402
from fastapi.responses import JSONResponse  # noqa: E402
from mangum import Mangum  # noqa: E402

import banque as bq  # noqa: E402,F401  (les tests remplacent ses fonctions)
import bons_plans  # noqa: E402,F401
import db  # noqa: E402
import enable_banking as eb  # noqa: E402
import erreurs  # noqa: E402
import notifications  # noqa: E402,F401
import veille  # noqa: E402,F401
from routes import abonnements, accueil, apercus, banque, catalogue, notifications as routes_notifications  # noqa: E402
from routes import objectifs, publiques, reglages  # noqa: E402
from routes.commun import EST_PRODUCTION, _jwks_client, require_owner  # noqa: E402,F401

app = FastAPI(
    docs_url=None if EST_PRODUCTION else "/docs",
    redoc_url=None,
    openapi_url=None if EST_PRODUCTION else "/openapi.json",
)


# ── Erreurs : traduites une seule fois pour toutes les routes ────────────────

@app.exception_handler(erreurs.ActionRefusee)
async def _action_refusee(_: Request, e: erreurs.ActionRefusee):
    """Refus métier (« Ce versement n'est pas confirmé. ») : message affichable tel quel dans l'app."""
    return JSONResponse({"detail": str(e)}, status_code=409)


@app.exception_handler(db.DatabaseError)
async def _base_indisponible(_: Request, e: db.DatabaseError):
    return JSONResponse({"detail": f"Base de données indisponible : {e}"}, status_code=502)


@app.exception_handler(eb.EnableBankingError)
async def _banque_indisponible(_: Request, e: eb.EnableBankingError):
    return JSONResponse({"detail": str(e)}, status_code=502)


# ── Routes ───────────────────────────────────────────────────────────────────

if not EST_PRODUCTION:
    app.include_router(apercus.router)
for module in (publiques, accueil, reglages, abonnements, catalogue, objectifs, banque, routes_notifications):
    app.include_router(module.router)

handler = Mangum(app)
