"""Connecte (ou renouvelle) une banque sans passer par l'app.

Usage : python tools/connecter_banque.py CIC      (ou Revolut)

Le script ouvre une session Opti, demande au backend l'adresse d'autorisation de la
banque et l'ouvre dans le navigateur. La suite se passe sur le site de la banque, qui
renvoie vers /banque/retour.
"""
import sys
import webbrowser

from _session import appeler_backend, jeton_opti


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("Usage : python tools/connecter_banque.py CIC|Revolut")
    banque = sys.argv[1]
    reponse = appeler_backend("/banque/connexion", jeton_opti(), {"banque": banque})
    print(f"Ouverture de la page d'autorisation de {banque} dans le navigateur…")
    webbrowser.open(reponse["url"])
    print("Termine l'autorisation sur le site de la banque : la page finale doit afficher « … est connecté ».")


if __name__ == "__main__":
    main()
