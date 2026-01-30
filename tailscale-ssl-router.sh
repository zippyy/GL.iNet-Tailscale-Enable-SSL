#!/bin/sh
#
# tailscale-ssl-router.sh (Flint 3 / BusyBox ash)
#
# DISCLAIMER:
# Manual process; run every ~90 days to renew the Tailscale cert.
#

set -e

BACKUP_DIR="/root/ssl-backup"
NGINX_CRT="/etc/nginx/nginx.cer"
NGINX_KEY="/etc/nginx/nginx.key"

mkdir -p "$BACKUP_DIR"

echo "[*] Running 'tailscale cert' and detecting Tailnet domain..."
CERT_OUT="$(tailscale cert 2>&1 || true)"
TAILNET_DOMAIN="$(printf '%s\n' "$CERT_OUT" | grep -Eo '[A-Za-z0-9.-]+\.ts\.net' | head -n1)"

if [ -z "$TAILNET_DOMAIN" ]; then
  echo "[!] Could not detect Tailnet domain from 'tailscale cert' output."
  printf '%s\n' "$CERT_OUT"
  exit 1
fi

echo "[*] Detected Tailnet domain: $TAILNET_DOMAIN"

CRT_SRC="/root/${TAILNET_DOMAIN}.crt"
KEY_SRC="/root/${TAILNET_DOMAIN}.key"
[ -f "$CRT_SRC" ] || CRT_SRC="./${TAILNET_DOMAIN}.crt"
[ -f "$KEY_SRC" ] || KEY_SRC="./${TAILNET_DOMAIN}.key"

if [ ! -f "$CRT_SRC" ] || [ ! -f "$KEY_SRC" ]; then
  echo "[!] Expected cert files not found:"
  echo "    $CRT_SRC"
  echo "    $KEY_SRC"
  exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"

echo "[*] Backing up existing nginx cert/key..."
if [ -f "$NGINX_CRT" ]; then
  cp -a "$NGINX_CRT" "$BACKUP_DIR/nginx.cer.bak.$TS" 2>/dev/null || true
fi
if [ -f "$NGINX_KEY" ]; then
  cp -a "$NGINX_KEY" "$BACKUP_DIR/nginx.key.bak.$TS" 2>/dev/null || true
fi

echo "[*] Installing Tailscale cert/key into nginx..."
# Write to temp files first, then move into place (atomic-ish)
TMPCRT="$BACKUP_DIR/nginx.cer.new.$TS"
TMPKEY="$BACKUP_DIR/nginx.key.new.$TS"

cp -f "$CRT_SRC" "$TMPCRT"
cp -f "$KEY_SRC" "$TMPKEY"
chmod 600 "$TMPCRT" "$TMPKEY" 2>/dev/null || true

mv -f "$TMPCRT" "$NGINX_CRT"
mv -f "$TMPKEY" "$NGINX_KEY"

echo "[*] Verifying on-disk nginx cert is the Tailnet cert..."
openssl x509 -in "$NGINX_CRT" -noout -subject -issuer -dates

openssl x509 -in "$NGINX_CRT" -noout -subject | grep -q "$TAILNET_DOMAIN" || {
  echo "[!] On-disk nginx cert subject does not contain $TAILNET_DOMAIN"
  echo "    Aborting before restart."
  exit 1
}

echo "[*] Restarting nginx..."
/etc/init.d/nginx restart 2>/dev/null || killall -HUP nginx 2>/dev/null || true

echo "[*] Confirming cert served on localhost:443 (retry up to 15s)..."
i=0
while [ "$i" -lt 15 ]; do
  CERT_INFO="$(openssl s_client -connect 127.0.0.1:443 -servername "$TAILNET_DOMAIN" </dev/null 2>/dev/null \
    | openssl x509 -noout -subject -issuer -dates 2>/dev/null || true)"

  if [ -n "$CERT_INFO" ]; then
    echo "$CERT_INFO"
    break
  fi

  i=$((i+1))
  sleep 1
done

if [ -z "$CERT_INFO" ]; then
  echo "[!] nginx restarted, but could not read a certificate from localhost:443."
  echo "    (This is usually a short startup race; try again or check: netstat -lntp | grep ':443')"
  exit 1
fi

echo "[✓] Done. Test in browser: https://${TAILNET_DOMAIN}"
