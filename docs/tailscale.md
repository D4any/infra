# Tailscale (VPN mesh)

## Rôle
Accès admin distant chiffré (WireGuard), sans ouvrir aucun port sur la box.
Le Pi reste invisible depuis l'Internet public.

## Réseau (tailnet)
| Nœud | IP Tailscale | Auth |
|---|---|---|
| `srv-cyber-infra` (Pi) | `<IP-tailscale-pi>` | GitHub (D4any) |
| laptop d'admin | `<IP-tailscale-laptop>` | GitHub (D4any) |

- Expiration de clé désactivée sur les 2 nœuds (console admin), donc plus de
  déconnexion automatique. C'est l'oubli qui avait causé le lockout précédent.
- `tailscaled` activé au boot : remonte tout seul après redémarrage ou
  changement de réseau.

## Accès SSH
| Depuis | Commande |
|---|---|
| Réseau local | `ssh pi5` (mDNS `srv-cyber-infra.local`) |
| N'importe où | `ssh pi5-vpn` (via Tailscale `<IP-tailscale-pi>`) |

## Commandes utiles
```bash
tailscale status        # voir les machines du tailnet
tailscale ip -4         # IP Tailscale locale
sudo tailscale up       # (re)connecter / ré-authentifier
sudo tailscale down     # déconnecter
systemctl status tailscaled
```

## ACL — micro-segmentation du tailnet (syntaxe `grants`)
But : remplacer le tout ouvert par défaut (réseau plat) par du moindre
privilège. Tout converge vers le serveur ; aucun appareil ne parle à un autre.

Règle que je m'impose : les gens se désignent par identité (email, dans des
`groups`) ; le serveur se désigne par tag (`tag:server-paris`). On ne tague
jamais l'appareil d'une personne.

Matrice d'accès :

| De \ Vers | Appareils perso | Pi : SSH (22) | Pi : DNS (53) | Pi : web (443) |
|---|---|---|---|---|
| Admin (moi) | non (coupé) | oui | oui | oui |
| Famille / invités | non | non | oui | oui |

(màj 2026-07-01 : le web 443 est ouvert à la famille depuis le déploiement de
Firefly III le 2026-06-25 — la matrice n'avait pas été mise à jour à l'époque,
corrigé ici. Cf [`docs/firefly.md`](firefly.md) et le grant dans
[`infra/tailscale/policy.template.hujson`](../infra/tailscale/policy.template.hujson).)

- Template versionné (anonymisé) : [`infra/tailscale/policy.template.hujson`](../infra/tailscale/policy.template.hujson).
- La policy réelle (avec les vrais emails) vit uniquement dans la console
  Tailscale, jamais dans ce repo (vie privée).
- Principe `grants` : `src → dst`, et les ports vont dans le champ `ip`
  (`["udp:53","tcp:53"]`), contrairement à l'ancienne syntaxe `acls`.
- Conséquence : tout ce qui n'est pas écrit est interdit (la famille ne peut
  pas faire SSH sans que j'aie eu à l'interdire explicitement).

## Règle anti-lockout
Ne jamais restreindre SSH à la seule interface `tailscale0`. Toujours garder
un accès LAN en parallèle — c'est le point central à respecter côté UFW.
Idem pour les ACL : garder une session `ssh pi5` (LAN) ouverte avant de
sauvegarder une policy, et tester `ssh pi5-vpn` juste après le Save.
