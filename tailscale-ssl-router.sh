#!/bin/sh
#
# tailscale-ssl-router.sh
#
# GL.iNet routers using nginx on port 443
# Flint / Slate / Puli / Beryl / etc
#
# Manual process - re-run about every 90 days
#

set -e

BACKUP_DIR="/root/ssl-backup"
NGINX_CRT="/etc/nginx/nginx.cer"
NGINX_KEY="/etc/nginx/nginx.key"

mkdir -p "$BACKUP_DIR"

log() {
    echo "[*] $*"
}

warn() {
    echo "[!] $*"
}

log "Detecting Tailnet domain..."
CERT_OUT="$(tailscale cert 2>&1 || true)"
TAILNET_DOMAIN="$(printf '%s\n' "$CERT_OUT" | grep -Eo '[A-Za-z0-9.-]+\.ts\.net' | head -n 1)"

if [ -z "$TAILNET_DOMAIN" ]; then
    warn "Could not detect Tailnet domain"
    printf '%s\n' "$CERT_OUT"
    exit 1
fi

log "Detected Tailnet domain: $TAILNET_DOMAIN"

log "Generating or refreshing Tailscale cert..."
tailscale cert "$TAILNET_DOMAIN"

CRT_SRC="/root/${TAILNET_DOMAIN}.crt"
KEY_SRC="/root/${TAILNET_DOMAIN}.key"

[ -f "$CRT_SRC" ] || CRT_SRC="./${TAILNET_DOMAIN}.crt"
[ -f "$KEY_SRC" ] || KEY_SRC="./${TAILNET_DOMAIN}.key"

if [ ! -f "$CRT_SRC" ] || [ ! -f "$KEY_SRC" ]; then
    warn "Cert files not found after tailscale cert"
    echo "    $CRT_SRC"
    echo "    $KEY_SRC"
    exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"

log "Backing up existing nginx cert/key..."
[ -f "$NGINX_CRT" ] && cp -a "$NGINX_CRT" "$BACKUP_DIR/nginx.cer.bak.$TS" 2>/dev/null || true
[ -f "$NGINX_KEY" ] && cp -a "$NGINX_KEY" "$BACKUP_DIR/nginx.key.bak.$TS" 2>/dev/null || true

log "Installing Tailscale cert/key into nginx..."
TMPCRT="$BACKUP_DIR/nginx.cer.new.$TS"
TMPKEY="$BACKUP_DIR/nginx.key.new.$TS"

cp -f "$CRT_SRC" "$TMPCRT"
cp -f "$KEY_SRC" "$TMPKEY"
chmod 600 "$TMPCRT" "$TMPKEY" 2>/dev/null || true
mv -f "$TMPCRT" "$NGINX_CRT"
mv -f "$TMPKEY" "$NGINX_KEY"

log "Verifying on-disk nginx cert..."
openssl x509 -in "$NGINX_CRT" -noout -subject -issuer -dates
openssl x509 -in "$NGINX_CRT" -noout -subject | grep -q "$TAILNET_DOMAIN" || {
    warn "On-disk cert does not match Tailnet domain"
    exit 1
}

log "Restarting nginx..."
/etc/init.d/nginx restart 2>/dev/null || killall -HUP nginx 2>/dev/null || true

log "Confirming cert served on localhost:443 (retry up to 15 seconds)..."
i=0
while [ "$i" -lt 15 ]; do
    OUT="$(openssl s_client -connect 127.0.0.1:443 -servername "$TAILNET_DOMAIN" </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates 2>/dev/null || true)"
    if [ -n "$OUT" ]; then
        echo "$OUT"
        break
    fi
    i=$((i+1))
    sleep 1
done

if [ -z "$OUT" ]; then
    warn "nginx restarted but no certificate was presented on port 443"
    exit 1
fi

echo "[OK] HTTPS enabled at:"
echo "     https://${TAILNET_DOMAIN}"
