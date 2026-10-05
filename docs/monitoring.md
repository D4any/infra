# Monitoring — Observabilité du Pi (Prometheus + Grafana)

> Déployé le 2026-06-27 en conteneurs Docker, derrière nginx (TLS).
> Source de vérité : `infra/monitoring/` dans ce repo. Le Pi exécute une copie
> dans `/data/docker/monitoring/`.

## Rôle
Collecter en continu les métriques du Pi (température, disque, RAM, CPU) et de
chaque conteneur, les stocker dans le temps, les visualiser et alerter dans un
dashboard web. C'est aussi la fondation pour la détection plus tard (CrowdSec).

## Monitoring ≠ détection (note pour moi)
Le monitoring répond à « est-ce que ça marche bien ? » (métriques : des chiffres
dans le temps). La détection répond à « est-ce qu'on m'attaque ? » (events/logs :
qui a fait quoi). Même réflexe — collecter, centraliser, alerter — mais sur des
données différentes. Le monitoring vient avant : une fois qu'on sait
collecter/alerter des métriques, ajouter les logs (Loki) puis la détection
(CrowdSec) est le même geste sur une autre source.

## Les rôles (un outil = une tâche)
| Rôle | Conteneur | Fait quoi |
|---|---|---|
| Vitrine | `grafana` | Affiche + alerte. Ne stocke/mesure rien. Seul « web ». |
| Entrepôt | `prometheus` | Va chercher (scrape) les capteurs toutes les 15 s + stocke (base time-series). |
| Capteur hôte | `node_exporter` | Métriques du Pi : temp, disque, RAM, CPU. |
| Capteur conteneurs | `cadvisor` | Métriques par conteneur : CPU/RAM/IO/état. |

Prometheus ne mesure rien lui-même : il interroge les exporters (capteurs)
posés au plus près de la donnée. Grafana ne parle qu'à Prometheus (sa
datasource) et dessine.

## Architecture
```
tailnet ──443/HTTPS──▶ [nginx] ──réseau "proxy"──▶ grafana:3000
 (Tailscale only)       /grafana/      │
                                       └──réseau privé "monitoring"──▶ prometheus:9090
                                                                        │ scrape ▼
                                                            node_exporter:9100  cadvisor:8080
```
- 4 conteneurs (socle). Aucun `ports:` publié, donc rien ne contourne UFW.
  nginx est le seul point d'entrée web.
- Segmentation réseau : seul `grafana` est sur les deux réseaux (`proxy` pour
  être servi par nginx, `monitoring` pour lire Prometheus). Prometheus et les
  capteurs vivent sur `monitoring` uniquement, invisibles de l'extérieur.
  Même logique de moindre privilège que les ACL Tailscale et la db Firefly.
- Capteurs en lecture seule : `node_exporter` monte `/proc`, `/sys`, `/` en
  `:ro` ; `cadvisor` monte le runtime Docker en `:ro`. Ils observent sans
  pouvoir modifier l'hôte.

## Où c'est installé
- Pi : `/data/docker/monitoring/` — `docker-compose.yml`, `.env`,
  `prometheus/prometheus.yml`, `grafana/provisioning/`. Les données vivent dans
  des volumes nommés Docker (`grafana-data`, `prometheus-data`), donc survivent
  à toute recréation de conteneur. (Volume nommé plutôt que bind : Grafana
  tourne en uid 472, un bind sur `/data` imposerait un `chown` manuel.)
- Repo : `infra/monitoring/` — compose + `.env.example` + configs Prometheus et
  provisioning Grafana versionnés. Jamais le `.env` (secret admin).

## Secrets (.env, non versionné)
| Variable | Rôle | Génération |
|---|---|---|
| `GF_SECURITY_ADMIN_PASSWORD` | mot de passe admin Grafana (login `admin`) | `openssl rand -base64 24` |

Couvert par `.gitignore` (`.env`, `**/.env`). Vérif :
`git check-ignore -v infra/monitoring/.env` doit renvoyer une ligne (= ignoré).

## Datasource provisionnée
`infra/monitoring/grafana/provisioning/datasources/prometheus.yml` est monté en
`:ro` dans Grafana (`/etc/grafana/provisioning`). Grafana le lit au démarrage
et crée tout seul la datasource Prometheus (`access: proxy`,
`url: http://prometheus:9090`) : zéro clic, reproductible. `access: proxy` =
le serveur Grafana interroge Prometheus côté réseau interne ; le navigateur ne
voit jamais Prometheus directement.

## Routage nginx
Par chemin, dans le `server{}` unique (`infra/nginx/conf.d/srv-cyber-infra.conf`) :
| URL | Service |
|---|---|
| `https://srv-cyber-infra.<tailnet>.ts.net/grafana/` | Grafana |
| `https://srv-cyber-infra.<tailnet>.ts.net/` | Firefly III (racine) |
| `https://srv-cyber-infra.<tailnet>.ts.net/pihole/admin` | Pi-hole (admin) |

Subtilité : Grafana tourne avec `GF_SERVER_SERVE_FROM_SUB_PATH=true` et
`ROOT_URL=.../grafana/`, donc il attend les requêtes avec `/grafana/` intact.
Le `proxy_pass http://grafana:3000;` est sans `/` final (conserve le préfixe),
contrairement à Pi-hole qui lui le strippe.

## Déploiement (fait le 2026-06-27, via Tailscale `pi5-vpn`)
```bash
# 1. Copier les fichiers vers le Pi
rsync -av ~/Documents/server-paris/infra/monitoring/ pi5-vpn:/data/docker/monitoring/

# 2. Créer le secret admin Grafana
ssh pi5-vpn 'cd /data/docker/monitoring && \
  printf "GF_SECURITY_ADMIN_PASSWORD=%s\n" "$(openssl rand -base64 24)" > .env && chmod 600 .env'

# 3. Démarrer la stack
ssh pi5-vpn 'cd /data/docker/monitoring && docker compose up -d'

# 4. Prouver que Prometheus collecte AVANT de toucher nginx
ssh pi5-vpn 'docker exec prometheus wget -qO- "http://localhost:9090/api/v1/targets?state=active"'
#   → les 3 jobs (prometheus, node, cadvisor) en "health":"up"

# 5. Bascule nginx (Grafana sous /grafana/)
rsync -av ~/Documents/server-paris/infra/nginx/conf.d/ pi5-vpn:/data/docker/nginx/conf.d/
ssh pi5-vpn 'docker exec nginx nginx -t'        # tester AVANT
ssh pi5-vpn 'docker exec nginx nginx -s reload' # reload SEULEMENT si -t OK
```
Méthode anti-lockout : Prometheus prouvé collecteur avant la bascule, conf
nginx testée (`nginx -t`) avant le reload (sinon nginx garde l'ancienne conf,
zéro coupure). Changement web-only : ne touche ni SSH, ni UFW, ni le DNS.

## Validation (faite le 2026-06-27)
```bash
curl -sI https://srv-cyber-infra.<tailnet>.ts.net/grafana/        # 302 → /grafana/login
curl -sI https://srv-cyber-infra.<tailnet>.ts.net/grafana/login   # 200
curl -sI https://srv-cyber-infra.<tailnet>.ts.net/                # 302 (Firefly intact)
curl -sI https://srv-cyber-infra.<tailnet>.ts.net/pihole/admin/   # 302 (Pi-hole intact)
ssh pi5-vpn 'sudo ss -tlnp | grep -E ":9090|:9100|:3000|:8080"'    # (rien : non exposés)
```

## Premiers pas dans Grafana
1. Ouvrir `https://srv-cyber-infra.<tailnet>.ts.net/grafana/` (Tailscale up).
2. Login `admin` / mot de passe du `.env`. Changer le mot de passe au 1er login.
3. La datasource Prometheus est déjà là (provisionnée).
4. Dashboards prêts à l'emploi (`Dashboards → New → Import`, par ID) :
   - 1860 — Node Exporter Full (hôte : temp, disque, RAM, CPU du Pi).
   - 14282 — cAdvisor (métriques par conteneur).

## Gotcha — RAM par conteneur à 0 : cgroup mémoire désactivé (corrigé 2026-06-29)
Au départ cAdvisor remontait 0 sur la RAM par conteneur. Cause : sur Raspberry
Pi OS le contrôleur cgroup `memory` est coupé d'usine (le firmware injecte
`cgroup_disable=memory` au boot), donc les fichiers `memory.current` des
conteneurs n'existent pas — cAdvisor n'a rien à lire.

Fix (sur le Pi, nécessite reboot) : ajouter à la fin de l'unique ligne de
`/boot/firmware/cmdline.txt` :
```
cgroup_enable=memory cgroup_memory=1
```
(backup `cmdline.txt.bak-2026-06-29` fait avant ; `cgroup_enable=memory`
l'emporte sur le `cgroup_disable=memory` du firmware). Après `sudo reboot` :
```bash
ssh pi5-vpn 'cat /sys/fs/cgroup/cgroup.controllers'   # doit contenir "memory"
```
`memory` apparaît, `memory.current` existe par conteneur, Grafana affiche la RAM.

## Gestion (depuis `/data/docker/monitoring/`)
- État : `docker compose ps` · Logs : `docker compose logs -f grafana`
- Cibles Prometheus : `docker exec prometheus wget -qO- localhost:9090/api/v1/targets`
- Mise à jour : `docker compose pull && docker compose up -d` (volumes conservés).

## Stockage — garde-fous (la SD est petite)
Le `data-root` Docker est encore sur la carte SD (29 Go), pas sur `/data`
(109 Go quasi vide). Deux postes peuvent remplir la SD, donc bornés :
- Base Prometheus (le seul qui stocke des métriques) : rétention bornée en
  temps (15 j) ET en taille (1 Go) via son `command`
  (`--storage.tsdb.retention.time=15d`, `--storage.tsdb.retention.size=1GB`).
  Le premier seuil atteint purge les vieux blocs. Grafana ne stocke qu'une
  petite base SQLite (dashboards/réglages) ; les capteurs ne stockent rien.
- Logs Docker (json-file, illimités par défaut) : rotation via l'anchor YAML
  `x-logging` appliqué aux 4 services → 10 Mo × 3 = 30 Mo max par conteneur.
  NB : les stacks nginx/Pi-hole/Firefly n'ont pas encore cet anchor, à
  corriger (cf. README, à faire).

Vérif : `docker inspect prometheus --format '{{json .Args}}'` (flags de
rétention) et `docker inspect <c> --format '{{.HostConfig.LogConfig.Config}}'`
(rotation).

Fix durable : migration du `data-root` Docker sur `/data` (procédure dans le
README) → images + volumes + logs sur la carte 109 Go au lieu de la SD 29 Go.

## Capteur cert TLS — textfile collector (2026-07-02)
Premier capteur « custom » : le script de renouvellement du cert
([docs/nginx.md](nginx.md)) dépose ses métriques dans
`/data/docker/monitoring/textfile/cert_expiry.prom` ; `node_exporter` publie
tout `.prom` de ce dossier (flag `--collector.textfile.directory`, montage
`:ro`, voir le compose). Écriture atomique (tmp puis `mv`) pour ne jamais lire
un fichier à moitié écrit.

| Métrique | Surveille | Panneau Grafana (dashboard `cert-tls`) |
|---|---|---|
| `tls_cert_expiry_timestamp_seconds` | le cert (date notAfter) | « jours restants » : rouge < 14 j, orange 14-30 j, vert > 30 j |
| `cert_renew_last_success_timestamp_seconds` | le script lui-même | « heures depuis succès » : vert < 26 h, orange 26-50 h, rouge > 50 h (2 runs quotidiens ratés) |

L'idée : surveiller aussi le surveillant. Si le script meurt en silence, la
première métrique a l'air saine ; c'est la deuxième qui vieillit et trahit la
panne. Dashboard « Cert TLS — renouvellement automatique » créé via l'API Grafana.

## Prochaines étapes (capteurs bonus + alerting)
- blackbox_exporter : sondes actives « point de vue utilisateur » (HTTPS nginx,
  DNS Pi-hole, HTTP Firefly) — attrape « le conteneur tourne mais le service ne
  répond plus ».
- pihole_exporter : requêtes DNS / % bloqué par Pi-hole (vue réseau).
- Alerting Grafana : seuils température / disque plein → notification.
- (plus tard) Loki + CrowdSec : passer du monitoring à la détection.
