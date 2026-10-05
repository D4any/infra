# Pare-feu (UFW)

## Politique
- deny incoming, allow outgoing
- logging : `low`

## Règles actives
| To | Action | From | Rôle |
|---|---|---|---|
| `tailscale0` (v4 + v6) | ALLOW IN | Anywhere | admin via Tailscale (couvre SSH sur le VPN) |
| `22/tcp` | ALLOW IN | `192.168.1.0/24` | SSH depuis le réseau local |

Tout autre entrant est bloqué. Les 2 accès (`ssh pi5` LAN + `ssh pi5-vpn`
Tailscale) restent ouverts : c'est l'anti-lockout.

## Commandes utiles
```bash
sudo ufw status verbose          # état + règles
sudo ufw allow <règle>           # ajouter
sudo ufw delete <règle|num>      # supprimer (sudo ufw status numbered)
sudo ufw disable / enable
```

## Méthode anti-lockout (à refaire à chaque changement de règle)
Avant tout `enable` ou règle restrictive, poser un filet qui rouvre tout seul :
```bash
echo "ufw --force disable" | sudo at now + 10 minutes   # annuler après validation : sudo atrm $(atq | cut -f1)
```
Et toujours garder une session ouverte + vérifier LAN et Tailscale avant de fermer.

## Notes
- Reverse proxy (2026-06-10) : aucune règle UFW ajoutée pour le 443 — le port est
  publié par Docker, qui contourne UFW (exposition assumée, cf. `docs/pihole.md`).
  Les services derrière nginx ne publient aucun port, donc rien à ouvrir pour eux
  non plus.
- Si je change de réseau/box : ajuster la règle LAN (`192.168.1.0/24`) au nouveau
  sous-réseau — ou passer par Tailscale en attendant.
