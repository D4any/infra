# nginx — Reverse proxy + TLS (point d'entrée unique)

> Déployé le 2026-06-10 en conteneur Docker. Termine le TLS et route vers
> les services internes. Source de vérité : `infra/nginx/` dans ce repo.

## Rôle
nginx est le seul service web exposé (port 443) : il déchiffre le HTTPS
(terminaison TLS) puis relaie en interne vers les conteneurs, qui ne
publient plus aucun port web.

## Architecture
```
tailnet ──443/HTTPS──▶ [nginx] ──réseau docker "proxy"──▶ pihole:80
                        seul port                      ──▶ (services suivants)
                        web exposé
```
- Avant : chaque service publiait son port (Pi-hole :80, etc.), donc une
  surface d'attaque qui grossit à chaque service, et chaque port publié par
  Docker contourne UFW (cf. `docs/pihole.md`).
- Après : les services vivent sur le réseau interne `proxy`
  (`docker network create proxy`), sans `ports:`. Un conteneur non publié ne
  perce aucun trou dans le firewall ; ajouter un service = 0 changement UFW.

## Où c'est installé
- Pi : `/data/docker/nginx/` — compose + `conf.d/` + `certs/`.
- Repo : `infra/nginx/` (compose + conf versionnés, pas les certs).
  Toute modif se fait dans le repo puis est copiée sur le Pi.

## TLS — certificat Tailscale
- Nom : `srv-cyber-infra.<tailnet>.ts.net` (vrai cert Let's Encrypt, émis via
  `tailscale cert`, prérequis : HTTPS Certificates activé dans la console admin
  Tailscale). Assumé : le nom de machine est publié dans le journal public des
  certificats (Certificate Transparency).
- Émission (sur le Pi, root) :
  ```bash
  sudo tailscale cert \
    --cert-file /data/docker/nginx/certs/srv-cyber-infra.<tailnet>.ts.net.crt \
    --key-file  /data/docker/nginx/certs/srv-cyber-infra.<tailnet>.ts.net.key \
    srv-cyber-infra.<tailnet>.ts.net
  ```
- Validité 90 jours. Renouvellement automatisé depuis le 2026-07-02 (avant :
  manuel). Source de vérité : [`infra/cert-renew/`](../infra/cert-renew/).

## Renouvellement automatique (2026-07-02)
- Déclencheur : `cert-renew.timer` (systemd), quotidien + `Persistent=true`
  (run rattrapé au boot si le Pi était éteint). Quotidien parce qu'un échec ne
  coûte alors que 24 h avant la tentative suivante.
- Script : `/usr/local/sbin/renew-cert.sh` (copie de
  `infra/cert-renew/renew-cert.sh`), idempotent :
  1. `tailscale cert` (no-op tant que le cert est loin de l'expiration) ;
  2. si le cert a changé : `nginx -t` puis `nginx -s reload` (pas de restart,
     zéro coupure) ;
  3. vérification de bout en bout : le cert servi sur :443 doit être identique
     au cert sur disque, sinon échec bruyant (exit ≠ 0 → unité `failed`) ;
  4. dépose les métriques d'expiration + dernier succès pour Prometheus
     (→ [docs/monitoring.md](monitoring.md), dashboard « Cert TLS »).
- Gestion :
  ```bash
  systemctl list-timers cert-renew.timer   # prochain run planifié
  journalctl -u cert-renew.service         # logs des runs
  sudo systemctl start cert-renew.service  # run manuel
  ```
- Testé le 2026-07-02 : idempotence (2 runs sans reload), chemin « cert
  changé » forcé (reload + vérif OK, uptime nginx conservé), échec simulé
  visible en `failed`.

## Routage : par chemin, pas par sous-domaine
Contrainte : Tailscale n'émet des certs que pour le nom exact de la machine
(pas de wildcard, donc pas de `pihole.xxx.ts.net`). D'où un routage par chemin :
| URL | Service |
|---|---|
| `https://srv-cyber-infra.<tailnet>.ts.net/` | Firefly III (traceur de dépenses) |
| `https://srv-cyber-infra.<tailnet>.ts.net/grafana/` | Grafana (monitoring) |
| `https://srv-cyber-infra.<tailnet>.ts.net/pihole/admin` | Pi-hole (admin) |

Le `server{}` unique (port 443) vit dans `infra/nginx/conf.d/srv-cyber-infra.conf`
(a remplacé `pihole.conf` le 2026-06-25, quand Firefly a pris la racine `/`).

## Ajouter un service derrière le proxy (recette)
1. Dans le compose du service : `networks: [default, proxy]`, aucun `ports:`.
2. Dans `infra/nginx/conf.d/` : un bloc `location /monservice/ { proxy_pass http://<conteneur>:<port>/; }`.
3. Copier sur le Pi, `docker compose up -d` (service) + `docker compose restart nginx`.

## Gestion (depuis `/data/docker/nginx/`)
- État : `docker compose ps` · Logs : `docker compose logs -f`
- Tester une conf avant de recharger : `docker compose exec nginx nginx -t`
- Recharger après modif de conf : `docker compose restart nginx`

## Méthode anti-lockout, appliquée au web
Le port 80 du Pi-hole n'a été retiré qu'après vérification complète de la
nouvelle voie HTTPS (HTTP 302 du Pi-hole à travers nginx + cert valide).
Même principe que pour un firewall : ne fermer l'ancien chemin qu'une fois
le nouveau prouvé, jamais les deux changements dans le même mouvement.

## Test de validation (fait le 2026-06-10)
```
curl -sI https://srv-cyber-infra.<tailnet>.ts.net/admin/   # → 302 /admin/login (Pi-hole via nginx)
openssl s_client -connect srv-cyber-infra.<tailnet>.ts.net:443  # → issuer Let's Encrypt
curl -sI http://<ip-du-pi>/admin/                           # → ne répond plus (port fermé)
dig +short @<ip-tailscale-pi> doubleclick.net               # → 0.0.0.0 (DNS intact)
```
