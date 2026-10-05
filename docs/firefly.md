# Firefly III — Traceur de dépenses familial (multi-utilisateur isolé)

> Déployé le 2026-06-25 en conteneur Docker, derrière nginx (TLS).
> Source de vérité : `infra/firefly/` dans ce repo. Le Pi exécute une copie
> dans `/data/docker/firefly/`.

## Rôle
Firefly III est un gestionnaire de finances perso auto-hébergé : chaque membre
de la famille a son propre compte isolé (ses comptes, budgets et dashboard,
invisibles des autres), avec saisie manuelle des dépenses, règles
d'auto-catégorisation et API REST.

## Pourquoi Firefly III (et pas Actual Budget)
Choisi pour le multi-utilisateur isolé natif, le moteur de règles, l'API REST
(customisation future) et le dashboard riche.

## Pas de connexion bancaire
Aucun lien avec une banque : les dépenses sont saisies à la main (web ou
téléphone) ou importées en CSV. Aucun identifiant bancaire ne transite. Des
connecteurs existent en option — non installés (pas dans le compose).

## Architecture
```
tailnet ──443/HTTPS──▶ [nginx] ──réseau "proxy"──▶ firefly-app:8080
 (Tailscale only)       seul port            │
                        web exposé           └──réseau privé "internal"──▶ firefly-db (PostgreSQL)
                                                                       └──▶ firefly-cron
```
- 3 conteneurs : `firefly-app` (Firefly) + `firefly-db` (PostgreSQL 16) +
  `firefly-cron` (tâches récurrentes, 03:00).
- Aucun `ports:` publié, donc rien ne contourne UFW (cf. dette `DOCKER-USER`).
  nginx est le seul point d'entrée web.
- Segmentation réseau : `firefly-app` est le seul pont entre `proxy` (face à
  nginx) et `internal` (face à la db). La db vit sur `internal` uniquement :
  ni nginx ni Pi-hole ne peuvent l'atteindre. Même logique de moindre
  privilège que les ACL Tailscale.

## Où c'est installé
- Pi : `/data/docker/firefly/` — `docker-compose.yml`, `.env`, `pgdata/`
  (données Postgres), `upload/` (pièces jointes). `pgdata/` et `upload/` vivent
  sur la carte `/data`, donc survivent à toute recréation de conteneur.
- Repo : `infra/firefly/` — `docker-compose.yml` + `.env.example` versionnés.
  Jamais le `.env` (secrets), ni `pgdata/`/`upload/` (cf. `.gitignore`).

## Secrets (.env, non versionné)
| Variable | Rôle | Génération |
|---|---|---|
| `APP_KEY` | clé de chiffrement (exactement 32 car.) | `head /dev/urandom \| LC_ALL=C tr -dc 'A-Za-z0-9' \| head -c 32 ; echo` |
| `STATIC_CRON_TOKEN` | token du cron (exactement 32 car.) | idem |
| `DB_PASSWORD` | mot de passe PostgreSQL | `openssl rand -base64 24` |

Le `.gitignore` couvre `.env`, `**/.env`, `**/pgdata/`, `**/upload/`. Vérif :
`git check-ignore -v infra/firefly/.env` doit renvoyer une ligne (= ignoré).

## Routage nginx (rappel)
Tailscale n'émet un cert que pour le nom exact de la machine (pas de wildcard),
d'où le routage par chemin, dans le `server{}` unique
(`infra/nginx/conf.d/srv-cyber-infra.conf`) :
| URL | Service |
|---|---|
| `https://srv-cyber-infra.<tailnet>.ts.net/` | Firefly III (racine) |
| `https://srv-cyber-infra.<tailnet>.ts.net/pihole/admin` | Pi-hole (admin) |

Firefly servi à la racine = config officiellement supportée (le sous-répertoire
est déconseillé par Firefly). Pi-hole a donc été repassé de `/` vers
`/pihole/admin` à cette occasion, via le mécanisme reverse-proxy de Pi-hole v6
(`webserver.paths.prefix`) — nécessaire car son API `/api` entrait sinon en
collision avec Firefly (racine). Détails et piège `webhome` : cf. docs/pihole.md.

## Déploiement (fait le 2026-06-25, via Tailscale `pi5-vpn`)
```bash
# 1. Copier les fichiers vers le Pi (sans pgdata/upload)
rsync -av --exclude pgdata --exclude upload \
  ~/Documents/server-paris/infra/firefly/ pi5-vpn:/data/docker/firefly/

# 2. Démarrer la stack
ssh pi5-vpn 'cd /data/docker/firefly && docker compose up -d'
ssh pi5-vpn 'cd /data/docker/firefly && docker compose logs -f app'   # attendre "ready"

# 3. Prouver que l'app répond sur "proxy" AVANT de toucher nginx
ssh pi5-vpn 'docker run --rm --network proxy curlimages/curl -sI http://firefly-app:8080'
#   → HTTP/1.1 302 Found (Location: /login)

# 4. Bascule nginx (Firefly à la racine, Pi-hole vers /admin)
rsync -av ~/Documents/server-paris/infra/nginx/conf.d/ pi5-vpn:/data/docker/nginx/conf.d/
ssh pi5-vpn 'rm -f /data/docker/nginx/conf.d/pihole.conf'
ssh pi5-vpn 'cd /data/docker/nginx && docker compose exec -T nginx nginx -t'  # tester AVANT
ssh pi5-vpn 'cd /data/docker/nginx && docker compose restart nginx'           # puis appliquer
```
Méthode anti-lockout appliquée : l'app prouvée joignable avant la bascule, la
conf nginx testée (`nginx -t`) avant le reload, Pi-hole + DNS revérifiés après
(on ne ferme l'ancien chemin qu'une fois le nouveau prouvé). Changement
web-only : ne touche ni SSH, ni UFW, ni le DNS (port 53).

## Validation (faite le 2026-06-25)
```bash
curl -sI https://srv-cyber-infra.<tailnet>.ts.net/         # 302 → /login → /register
curl -sI https://srv-cyber-infra.<tailnet>.ts.net/pihole/  # 301 → /pihole/admin/login (Pi-hole OK)
dig +short @<IP-tailscale-pi> doubleclick.net                   # 0.0.0.0 (DNS intact)
ssh pi5-vpn 'sudo ss -tlnp | grep -E ":8080|:5432"'         # (rien : db/app non exposés)
```

## Comptes famille (mode isolation)
1. Ouvrir `https://srv-cyber-infra.<tailnet>.ts.net/` (Tailscale up) → Register.
2. Premier compte = owner/admin (`<email-admin>`).
3. Inviter : page `/settings/users` (menu Options → Administration → Users).
   Encart « Invite a new user » → saisir l'e-mail → Firefly affiche un lien
   d'invitation `/invitee/<code>` à copier (pas besoin de SMTP) ; le membre
   ouvre le lien et choisit son propre mot de passe.
   (NB : l'admin Firefly est sous `/settings`, Pi-hole sous `/pihole`, donc
   aucune collision de chemins.)
4. Isolation native : chaque user ne voit que ses données. L'owner administre
   l'instance (users, réglages) mais ne voit pas les transactions des autres.

## Règles d'auto-catégorisation
`Rules → Create new rule` · trigger *Description contains « Carrefour »* ·
action *Set category to « Courses »*. Les règles sont par utilisateur.

## API REST (customisation future)
`Options/Profile → OAuth → Personal Access Tokens` → générer un token Bearer.
Base : `https://srv-cyber-infra.<tailnet>.ts.net/api/v1/`.

## Téléphone
Interface responsive → « Ajouter à l'écran d'accueil » (PWA) pour une saisie
rapide. Apps mobiles tierces possibles via un Personal Access Token (API).

## Gestion (depuis `/data/docker/firefly/`)
- État : `docker compose ps` · Logs : `docker compose logs -f app`
- Mise à jour : `docker compose pull && docker compose up -d` (pgdata/upload
  conservés). Migrations DB jouées automatiquement au boot.
- Cron : `docker compose logs cron` (déclenche `/api/v1/cron/<token>` à 03:00).

## Sauvegarde (à mettre en place)
Les données = `pgdata/` (Postgres) + `upload/`. Sauvegarde propre de la db :
`docker compose exec -T db pg_dump -U firefly firefly > backup.sql`
→ à automatiser vers `/data/backups/` à l'étape « automatisation » de la roadmap.
