"""Lance une synchronisation des comptes sans passer par l'app.

Usage : python tools/synchroniser.py
"""
from _session import appeler_backend, jeton_opti


def main() -> None:
    print("Synchronisation en cours (jusqu'à une minute)…")
    reponse = appeler_backend("/banque/synchro", jeton_opti(), timeout=290)
    for c in reponse["comptes"]:
        if "erreur" in c:
            print(f"✗ {c['compte']} : {c['erreur']}")
            continue
        solde = f"{c['solde']:.2f} €".replace(".", ",") if c.get("solde") is not None else "?"
        print(f"✓ {c['compte']} : solde {solde}, {c['nouvelles']} nouvelles, "
              f"{c['deja_connues']} déjà connues, {c['en_attente']} en attente")


if __name__ == "__main__":
    main()
