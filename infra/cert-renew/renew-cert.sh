#!/usr/bin/env bash
# renew-cert.sh — renouvelle le cert TLS (Let's Encrypt via tailscale cert),
# recharge nginx SEULEMENT si le cert a changé, vérifie le cert réellement
# servi, puis dépose les métriques pour node_exporter (textfile collector).
#
# Source de vérité : infra/cert-renew/ (repo server-paris).
# Copie exécutée : /usr/local/sbin/renew-cert.sh (root), via cert-renew.timer.
# Tout échec → exit ≠ 0 → l'unité systemd passe en "failed" (visible).
set -euo pipefail

# CERT_HOST surchargeable par l'environnement (sert aux tests d'échec).
HOST="${CERT_HOST:-srv-cyber-infra.<tailnet>.ts.net}"
CERT_DIR="/data/docker/nginx/certs"
CERT="$CERT_DIR/$HOST.crt"
KEY="$CERT_DIR/$HOST.key"
COMPOSE_DIR="/data/docker/nginx"
METRICS_DIR="/data/docker/monitoring/textfile"
METRICS_FILE="$METRICS_DIR/cert_expiry.prom"

fingerprint() {
  # Empreinte SHA-256 du cert, ou "absent" si le fichier manque/est illisible.
  openssl x509 -in "$1" -noout -fingerprint -sha256 2>/dev/null || echo "absent"
}

avant="$(fingerprint "$CERT")"

# No-op tant que le cert est loin de l'expiration (c'est ce qui rend le
# run quotidien gratuit) ; réémet via Let's Encrypt sinon.
tailscale cert --cert-file "$CERT" --key-file "$KEY" "$HOST"

apres="$(fingerprint "$CERT")"

if [[ "$avant" != "$apres" ]]; then
  echo "Cert changé → test de conf puis reload nginx (zéro coupure)"
  docker compose --project-directory "$COMPOSE_DIR" exec -T nginx nginx -t
  docker compose --project-directory "$COMPOSE_DIR" exec -T nginx nginx -s reload
  sleep 2
  # Vérification de bout en bout : le cert SERVI doit être le cert DISQUE.
  servi="$(echo | openssl s_client -connect "$HOST:443" -servername "$HOST" 2>/dev/null \
           | openssl x509 -noout -fingerprint -sha256)"
  if [[ "$servi" != "$apres" ]]; then
    echo "ERREUR : cert servi ≠ cert sur disque (reload raté ?)" >&2
    exit 1
  fi
  echo "Reload OK, cert servi vérifié"
else
  echo "Cert inchangé, rien à recharger"
fi

# Métriques pour node_exporter — écriture ATOMIQUE (tmp puis mv) pour que
# le collector ne lise jamais un fichier à moitié écrit.
install -d -m 755 "$METRICS_DIR"
expiration_epoch="$(date -d "$(openssl x509 -in "$CERT" -noout -enddate | cut -d= -f2)" +%s)"
tmp="$(mktemp "$METRICS_DIR/.cert_expiry.XXXXXX")"
cat > "$tmp" <<EOF
# HELP tls_cert_expiry_timestamp_seconds Date d'expiration (notAfter) du cert TLS, en epoch.
# TYPE tls_cert_expiry_timestamp_seconds gauge
tls_cert_expiry_timestamp_seconds{host="$HOST"} $expiration_epoch
# HELP cert_renew_last_success_timestamp_seconds Dernier run REUSSI de renew-cert.sh, en epoch.
# TYPE cert_renew_last_success_timestamp_seconds gauge
cert_renew_last_success_timestamp_seconds $(date +%s)
EOF
chmod 644 "$tmp"
mv "$tmp" "$METRICS_FILE"
echo "Métriques écrites dans $METRICS_FILE"
