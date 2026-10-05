# srv-cyber-infra — Homelab (Raspberry Pi 5)

Notes d'état du serveur, pour m'y retrouver. Dernière mise à jour : 2026-07-03.

Sur l'IA : je maintiens ce repo avec l'aide de Claude (d'où les
`Co-Authored-By` dans l'historique), configuré en mode prof via `CLAUDE.md` :
il me pose des questions et me fait réexpliquer au lieu de faire à ma place.
Les choix d'architecture, les manips sur le Pi et les erreurs sont les miens ;
l'IA m'aide à les challenger et à les documenter.

---

## En bref
Pi 5 réinstallé de zéro le 2026-05-31, après un lockout total (voir les notes
plus bas). Accessible de façon résiliente par `ssh pi5`. Base saine.

---

## État actuel
- OS neuf : Raspberry Pi OS Lite 64-bit (Debian Trixie, kernel 6.12).
- Hostname : `srv-cyber-infra`. Utilisateur : `<user>` (sudo).
- SSH actif, avec 2 accès indépendants :
  - clé SSH (méthode principale),
  - mot de passe (secours console).
- Adressage stable via mDNS : joignable par `srv-cyber-infra.local`, donc
  insensible aux changements d'IP DHCP et même de box. Résolution `.local`
  activée sur le laptop (`libnss-mdns`).
- Connexion en Ethernet sur la box actuelle.

---

## Me connecter (depuis le laptop)

| Élément | Valeur |
|---|---|
| Commande (LAN) | `ssh pi5` (ou `ssh srv-cyber-infra.local`) |
| Commande (à distance) | `ssh pi5-vpn`  |
| Nom réseau | `srv-cyber-infra.local` (mDNS, suit l'IP automatiquement) |
| Utilisateur | `<user>` |
| Clé privée | `~/.ssh/id_ed25519_pi5` (sur le laptop) |
| Mot de passe | celui choisi lors de la réinstall (secours) |
| Alias SSH | dans `~/.ssh/config` (bloc `Host srv-cyber-infra pi5`) |

---

## À ne pas oublier
1. La clé privée `~/.ssh/id_ed25519_pi5` est sauvegardée ailleurs (gestionnaire
   de mots de passe + clé USB). C'est ma sécurité n°1 contre un re-lockout.
2. Cause du lockout précédent : SSH restreint à la seule interface Tailscale,
   plus clé perdue. Quand Tailscale est tombé, plus aucun accès. À ne jamais refaire.
3. Pas d'accès admin au routeur actuel (mot de passe inconnu), d'où le mDNS
   plutôt qu'une réservation DHCP.

---

## Fait (journal)
- [x] Clé privée `id_ed25519_pi5` sauvegardée (2026-05-31).
- [x] Carte 128 Go `/data` reformatée en ext4 propre (2026-05-31). Label `DATA`,
  UUID `<UUID-carte-data>` (celui du fstab).
- [x] `/data` monté sur le Pi (fstab, `noatime,nodev,nosuid,nofail`) → [docs/stockage-data.md](docs/stockage-data.md).
- [x] Tailscale (expiration de clé désactivée) → [docs/tailscale.md](docs/tailscale.md)
- [x] ACL Tailscale, micro-segmentation (2026-06-25, syntaxe `grants`) :
  tailnet passé du tout ouvert au moindre privilège. Admin → le Pi sur tout,
  famille → DNS (53) uniquement, zéro device-to-device. Serveur = `tag:server-paris`,
  gens = identité. Template anonymisé dans [`infra/tailscale/`](infra/tailscale/)
  (les vrais emails restent dans la console) → [docs/tailscale.md](docs/tailscale.md).
- [x] UFW (deny in / allow out, SSH LAN + Tailscale) → [docs/ufw.md](docs/ufw.md)
- [x] Arborescence `/data/{docker,apps,backups}` créée (2026-06-05).
- [x] Docker installé (moteur + plugin compose, dépôt officiel Trixie),
  `<user>` dans le groupe `docker` (2026-06-05).
- [x] Pi-hole (DNS filtrant anti-pubs) en conteneur Docker, testé OK
  → [docs/pihole.md](docs/pihole.md) (2026-06-05).
- [x] Décision exposition Docker/LAN (2026-06-10) : les ports publiés par Docker
  contournent UFW (chaîne `DOCKER` avant les règles UFW dans FORWARD). Exposition
  LAN du Pi-hole assumée et documentée → [docs/pihole.md](docs/pihole.md).
- [x] Reverse proxy nginx + TLS (2026-06-10) : seul point d'entrée web (443),
  vrai cert Let's Encrypt via `tailscale cert`, Pi-hole ne publie plus que le DNS
  → [docs/nginx.md](docs/nginx.md). Composes versionnés dans [`infra/`](infra/).
- [x] Firefly III (traceur de dépenses familial, multi-utilisateur isolé)
  en Docker derrière nginx : servi à la racine `/`, Pi-hole repassé sous
  `/pihole/admin` (reverse-proxy prefix). Stack PostgreSQL + cron, aucun port
  publié, accès Tailscale only, pas de connexion bancaire (saisie manuelle)
  → [docs/firefly.md](docs/firefly.md) (2026-06-25).
- [x] Monitoring (2026-06-27) : Prometheus + Grafana (4 conteneurs) derrière
  nginx, servi sous `/grafana/`, Tailscale only. `node_exporter` (hôte :
  temp/disque/RAM/CPU) + `cadvisor` (par conteneur), capteurs en lecture seule,
  aucun port publié, datasource provisionnée → [docs/monitoring.md](docs/monitoring.md).
- [x] Fix cgroup mémoire (2026-06-29) : `cgroup_enable=memory cgroup_memory=1`
  dans `/boot/firmware/cmdline.txt` + reboot (coupé d'usine sur Raspberry Pi OS).
  cAdvisor remonte enfin la RAM par conteneur (affichait 0 avant)
  → [docs/monitoring.md](docs/monitoring.md).
- [x] Schéma des flux réseau (2026-06-29) : cartographie vérifiée des flux
  (ingress :443/:53/:22, segmentation en tiers privés, jonctions contrôlées)
  → [docs/flux-reseau.md](docs/flux-reseau.md).
- [x] Renouvellement auto du cert TLS (2026-07-02) : timer systemd quotidien
  (`Persistent=true`), script idempotent `tailscale cert` + reload nginx
  seulement si changement + vérification du cert servi. Expiration et santé du
  script visibles dans Grafana (textfile collector) → [docs/nginx.md](docs/nginx.md).
  Fichiers dans [`infra/cert-renew/`](infra/cert-renew/).

## Ce qu'il me reste à faire (rien d'urgent)
- [ ] Rotation des logs Docker : l'anchor `x-logging` (10 Mo × 3) n'est que dans
  le compose monitoring. nginx, Pi-hole et Firefly logguent en illimité sur la SD.
  Copier l'anchor dans les 3 composes, `up -d`, vérifier avec
  `docker inspect <c> --format '{{.HostConfig.LogConfig.Config}}'`.
  À faire avant la migration data-root.
- [ ] Migration `data-root` Docker → `/data/docker-root` :
  1. rotation des logs d'abord (item ci-dessus) ;
  2. `systemctl stop docker docker.socket` ;
  3. `rsync -aHAX /var/lib/docker/ /data/docker-root/`
     (`/data/docker/` est déjà pris par les composes) ;
  4. `data-root` dans `/etc/docker/daemon.json` + drop-in
     `RequiresMountsFor=/data` sur docker.service (sans ça, `/data` étant en
     `nofail`, une carte non montée au boot ferait recréer un data-root vide
     sur la SD — rien de perdu dans ce cas, mais piège à panique) ;
  5. vérifier conteneurs, images et `docker info | grep -i root` ; garder
     l'ancien `/var/lib/docker` quelques jours avant suppression.
- [ ] Capteurs bonus monitoring (blackbox, pihole_exporter) + alerting Grafana
  → liste en fin de [docs/monitoring.md](docs/monitoring.md).
- [ ] Durcir les ports publiés par Docker avec la chaîne `DOCKER-USER`
  (filtrage admin évalué avant les règles Docker — la méthode propre).
  Dette assumée pour l'instant.
- [ ] CrowdSec (pas urgent, rien d'exposé à Internet) : agent seul en détection
  pure d'abord — aucun bouncer, donc pas de risque de lockout. Acquisition à
  déclarer : journald (sshd) + docker (conteneurs). Vérif : `cscli metrics`,
  puis test brute force SSH → `cscli alerts list`. Bouncer firewall plus tard,
  avec whitelist LAN + Tailscale au préalable.

---

## Règles anti-lockout (à respecter pour la suite)
1. Toujours 2 accès indépendants avant d'activer une règle restrictive.
2. Ne jamais limiter SSH à la seule interface Tailscale. Garder une voie LAN.
3. Tester un firewall en gardant une session de secours ouverte.
4. Tailscale : expiration de clé désactivée sur le nœud serveur (admin console).
5. Clé privée sauvegardée + mot de passe console connu.

---

## Docs détaillées (par sujet, dans `docs/`)
- [stockage-data.md](docs/stockage-data.md) — carte `/data` : format, montage fstab, organisation
- [tailscale.md](docs/tailscale.md) — VPN mesh : IPs du tailnet, accès SSH, ACL, commandes
- [ufw.md](docs/ufw.md) — pare-feu : politique, règles actives, méthode anti-lockout
- [pihole.md](docs/pihole.md) — DNS filtrant : déploiement Docker, accès, gestion, exposition
- [nginx.md](docs/nginx.md) — reverse proxy : terminaison TLS, routage, renouvellement du cert
- [firefly.md](docs/firefly.md) — traceur de dépenses : multi-user isolé, déploiement, comptes
- [monitoring.md](docs/monitoring.md) — Prometheus + Grafana : capteurs, dashboards, garde-fous stockage
- [flux-reseau.md](docs/flux-reseau.md) — schéma des flux : qui parle à qui, segmentation

Les `docker-compose` des services sont versionnés dans [`infra/`](infra/)
(source de vérité — le Pi exécute une copie).

---

## Annexe — comment l'accès a été rétabli (référence)
Utile si ça se reproduit :
- `rpi-imager` en version snap n'écrit pas la personnalisation OS sur la carte
  (hostname/user/SSH), même en confirmant « appliquer ». Vérifié 2 fois.
- Contournement fiable (sur une image fraîche jamais démarrée, partition de boot
  `bootfs` en FAT, éditable sans sudo) :
  - fichier vide `ssh` → active SSH à chaque boot (service `sshswitch`) ;
  - `userconf.txt` = `<user>:$6$<hash>` (hash via `openssl passwd -6`) → crée l'utilisateur.
- Trouver le Pi sur le réseau sans nmap : ping-sweep du `/24` puis `ip neigh` ;
  test infaillible : débrancher l'Ethernet et voir quelle IP disparaît.
- mDNS : sur le Pi `avahi-daemon` diffuse `srv-cyber-infra.local` ; sur le laptop,
  `sudo apt install libnss-mdns` pour résoudre les `.local`.
