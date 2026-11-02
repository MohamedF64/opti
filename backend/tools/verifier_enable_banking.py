"""Vérifie localement que la clé Enable Banking fonctionne (lecture seule).

Usage : python tools/verifier_enable_banking.py <chemin du fichier .pem>
L'identifiant de l'application est le nom du fichier. La clé n'est jamais affichée.
"""
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

import enable_banking as eb  # noqa: E402


async def main(pem_path: Path) -> None:
    creds = {"app_id": pem_path.stem, "private_key": pem_path.read_text()}
    aspsps = await eb.list_aspsps("FR", **creds)
    print(f"Connexion OK : {len(aspsps)} banques françaises disponibles.")
    for a in aspsps:
        if a.get("name", "").lower() in {"cic", "revolut"}:
            secondes = a.get("maximum_consent_validity")
            jours = f"{secondes // 86400} jours" if secondes else "non précisé"
            print(f"- {a['name']} : consentement max {jours}, méthodes {[m.get('name') for m in a.get('auth_methods', [])]}")


if __name__ == "__main__":
    asyncio.run(main(Path(sys.argv[1])))
