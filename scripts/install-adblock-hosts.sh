#!/bin/sh
# System-wide ad/tracker blocking through /system/etc/hosts.
#   TV=192.168.1.15:5555 sh scripts/install-adblock-hosts.sh
#   TV=... sh scripts/install-adblock-hosts.sh --restore     (put the original back)
#
# Uses Peter Lowe's list (~3,500 domains). Kept small on purpose: KitKat reads
# /etc/hosts on lookups and these TVs have 512 MB RAM. It blocks ad/tracking domains
# (e.g. ads.youtube.com, doubleclick.net), not video servers. It does NOT remove
# YouTube's in-video ads - SmartTube does that.
. "$(dirname "$0")/common.sh"
need_root

if [ "$1" = "--restore" ]; then
  [ -f "$OUT/hosts.original" ] || { echo "no $OUT/hosts.original" >&2; exit 1; }
  system_rw; push_root "$OUT/hosts.original" /system/etc/hosts; system_ro
  echo "original hosts restored"; exit 0
fi

D="$OUT/hosts"; mkdir -p "$D"
[ -f "$OUT/hosts.original" ] || adbc pull /system/etc/hosts "$(localpath "$OUT/hosts.original")" >/dev/null

curl -fsS -o "$D/pgl.txt" \
  "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext" || exit 1
# Keep only well-formed "127.0.0.1 domain" lines.
{ printf '127.0.0.1 localhost\n::1 localhost\n'
  tr -d '\r' < "$D/pgl.txt" | grep -E '^127\.0\.0\.1 [A-Za-z0-9._-]+$' | grep -v ' localhost$'
} > "$D/hosts"
n=$(wc -l < "$D/hosts" | tr -d ' ')
[ "$n" -gt 100 ] || { echo "list looks wrong ($n lines) - not installing" >&2; exit 1; }

system_rw
push_root "$D/hosts" /system/etc/hosts
system_ro
echo "Installed $n entries. Check: adb -s $TV shell ping -c1 doubleclick.net  (-> 127.0.0.1)"
