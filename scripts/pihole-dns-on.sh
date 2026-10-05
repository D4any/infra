#!/usr/bin/env bash
# Bascule le DNS de CE laptop vers le Pi-hole (joignable via Tailscale).
# Usage : bash pihole-dns-on.sh   (demande le mot de passe sudo)
set -euo pipefail

PIHOLE_IP="<IP-tailscale-pi>"   # IP Tailscale du Pi (srv-cyber-infra)

# Détecte la connexion active Wi-Fi/Ethernet (ignore tailscale0, docker0, lo)
CONN="$(nmcli -t -f NAME,TYPE connection show --active \
        | awk -F: '$2 ~ /wireless|ethernet/ {print $1; exit}')"

if [ -z "$CONN" ]; then
  echo "✗ Aucune connexion Wi-Fi/Ethernet active trouvée." >&2
  exit 1
fi

echo "→ Connexion ciblée : « $CONN »"
echo "→ DNS forcé sur Pi-hole ($PIHOLE_IP), DNS du routeur ignoré (anti-fuite)..."
sudo nmcli connection modify "$CONN" ipv4.dns "$PIHOLE_IP"
sudo nmcli connection modify "$CONN" ipv4.ignore-auto-dns yes
sudo nmcli connection modify "$CONN" ipv6.ignore-auto-dns yes
sudo nmcli connection up "$CONN" >/dev/null

echo "✓ Fait. DNS actifs maintenant :"
resolvectl dns
echo
echo "Test rapide : 'nslookup doubleclick.net' doit renvoyer 0.0.0.0 (= bloqué)."
