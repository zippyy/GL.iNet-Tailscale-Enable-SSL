#!/bin/sh
#
# update-kvmd-tailscale-cert.sh
#
# DISCLAIMER:
# This is a MANUAL process and must be run every ~90 days
# to keep the Tailscale certificate up to date.
#

set -e

BACKUP_DIR="/root/ssl-backup"
CRT_DST="/etc/kvmd/user/ssl/server.crt"
KEY_DST="/etc/kvmd/user/ssl/server.key"

echo "[*] Running 'tailscale cert' to determine Tailnet domain and generate cert..."

# Capture output (tailscale cert prints the name it used, on many systems)
CERT_OUT="$(tailscale cert 2>&1 || true)"

# Try to extract a *.ts.net domain from output
TAILNET_DOMAIN="$(printf '%s\n' "$CERT_OUT" | grep -Eo '[A-Za-z0-9.-]+\.ts\.net' | head -n1)"

if [ -z "$TAILNET_DOMAIN" ]; then
  echo "[!] Could not detect Tailnet domain from 'tailscale cert' output."
  echo "---- tailscale cert output ----"
  printf '%s\n' "$CERT_OUT"
  echo "------------------------------"
  echo
  echo "[!] Fallback suggestion: use 'tailscale whoami --json' or pass the domain in manually."
  exit 1
fi

echo "[*] Detected Tailnet domain: $TAILNET_DOMAIN"

# Now ensure we have a cert for that domain (some builds may not actually generate on the first call)
# If the earlier call already did, this is harmless.
tailscale cert "$TAILNET_DOMAIN"

CRT_SRC="/root/${TAILNET_DOMAIN}.crt"
KEY_SRC="/root/${TAILNET_DOMAIN}.key"

if [ ! -f "$CRT_SRC" ] || [ ! -f "$KEY_SRC" ]; then
  echo "[!] Expected cert files not found:"
  echo "    $CRT_SRC"
  echo "    $KEY_SRC"
  exit 1
fi

echo "[*] Backing up existing SSL certs..."
mkdir -p "$BACKUP_DIR"
cp -a "$CRT_DST" "$BACKUP_DIR/server.crt.bak" 2>/dev/null || true
cp -a "$KEY_DST" "$BACKUP_DIR/server.key.bak" 2>/dev/null || true

echo "[*] Installing Tailscale SSL cert into kvmd..."
cp -f "$CRT_SRC" "$CRT_DST"
cp -f "$KEY_SRC" "$KEY_DST"
chmod 600 /etc/kvmd/user/ssl/server.*

echo "[*] Restarting kvmd and nginx..."
/etc/init.d/kvmd restart 2>/dev/null || \
service kvmd restart 2>/dev/null || \
/etc/init.d/nginx restart 2>/dev/null || \
killall -HUP nginx 2>/dev/null || true

echo "[*] Confirming certs are valid..."
openssl s_client -connect 127.0.0.1:443 -servername "$TAILNET_DOMAIN" </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates

echo "[✓] Done. Test in browser: https://${TAILNET_DOMAIN}"
