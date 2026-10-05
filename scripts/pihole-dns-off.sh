#!/usr/bin/env bash
# SECOURS : remet le DNS automatique du routeur.
# À lancer si le Pi est éteint/injoignable et que tu n'as plus internet.
# Usage : bash pihole-dns-off.sh   (demande le mot de passe sudo)
set -euo pipefail

CONN="$(nmcli -t -f NAME,TYPE connection show --active \
        | awk -F: '$2 ~ /wireless|ethernet/ {print $1; exit}')"

if [ -z "$CONN" ]; then
  echo "✗ Aucune connexion Wi-Fi/Ethernet active trouvée." >&2
  exit 1
fi

echo "→ Connexion ciblée : « $CONN »"
echo "→ Restauration du DNS automatique (DHCP / routeur)..."
sudo nmcli connection modify "$CONN" ipv4.dns ""
sudo nmcli connection modify "$CONN" ipv4.ignore-auto-dns no
sudo nmcli connection modify "$CONN" ipv6.ignore-auto-dns no
sudo nmcli connection up "$CONN" >/dev/null

echo "✓ DNS automatique restauré. DNS actifs maintenant :"
resolvectl dns
