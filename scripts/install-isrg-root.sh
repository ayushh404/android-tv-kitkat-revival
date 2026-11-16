#!/bin/sh
# Add Let's Encrypt's ISRG Root X1 to the system trust store (Android < 7.1 lacks it).
# Without it, any site or app server using a Let's Encrypt certificate fails HTTPS.
#   TV=192.168.1.15:5555 sh scripts/install-isrg-root.sh
#   TV=... sh scripts/install-isrg-root.sh --remove
# Needs root, curl and openssl on this computer (Git Bash ships both).
. "$(dirname "$0")/common.sh"
need_root
DST=/system/etc/security/cacerts/6187b673.0   # Android names certs by OpenSSL subject_hash_old

if [ "$1" = "--remove" ]; then
  system_rw; asu rm -f "$DST"; system_ro; echo "removed $DST"; exit 0
fi

EXPECT="96:BC:EC:06:26:49:76:F3:74:60:77:9A:CF:28:C5:A7:CF:E8:A3:C0:AA:E1:1A:8F:FC:EE:05:C0:BD:DF:08:C6"
D="$OUT/cert"; mkdir -p "$D"
curl -fsS -o "$D/isrgrootx1.pem" https://letsencrypt.org/certs/isrgrootx1.pem || exit 1
FP=$(openssl x509 -in "$D/isrgrootx1.pem" -noout -fingerprint -sha256 | cut -d= -f2)
HASH=$(openssl x509 -in "$D/isrgrootx1.pem" -noout -subject_hash_old)
[ "$FP" = "$EXPECT" ] || { echo "FINGERPRINT MISMATCH ($FP) - not installing" >&2; exit 1; }
[ "$HASH" = "6187b673" ] || { echo "unexpected hash $HASH" >&2; exit 1; }
echo "ISRG Root X1 verified ($FP)"

# Android's own format: the PEM followed by the human-readable dump.
{ cat "$D/isrgrootx1.pem"; openssl x509 -in "$D/isrgrootx1.pem" -noout -text -fingerprint; } > "$D/6187b673.0"

adbsh ls /system/etc/security/cacerts > "$OUT/cacerts-before.txt"
system_rw
push_root "$D/6187b673.0" "$DST"
system_ro
adbsh ls -l "$DST"
echo "Installed. Reboot (or at least restart apps) for it to apply everywhere."
