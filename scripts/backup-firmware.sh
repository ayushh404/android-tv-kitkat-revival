#!/bin/sh
# Read-only full backup of the TV's firmware partitions to this computer, with an
# md5 check of every image against the TV. Skips userdata (your apps/data) and cache.
#   TV=192.168.1.15:5555 sh scripts/backup-firmware.sh
#
# Takes ~15-20 min for ~1 GB over Wi-Fi. Needs root and ~1 GB free in /data on the TV
# for the largest partition (each image is staged in /data/local/tmp, pulled, deleted).
#
# Why staged and not streamed: Android 4.4's adbd has no "exec-out", and
# "adb shell dd" mangles binary data. dd -> pull -> md5 compare is the reliable way.
#
# KEEP THESE IMAGES PRIVATE. tvcertificate / tee / MBOOT contain device-unique keys
# (HDCP, CI+). Never upload them anywhere.
. "$(dirname "$0")/common.sh"
need_root

DEST="$OUT/firmware"
mkdir -p "$DEST"
MANIFEST="$DEST/MANIFEST.txt"
: > "$MANIFEST"

BYNAME=$(asu ls -d '/dev/block/platform/*/by-name' | head -1)   # quoted: expand on the TV, not here
[ -n "$BYNAME" ] || { echo "No /dev/block/platform/*/by-name on this TV." >&2; exit 1; }

# "name -> /dev/block/mmcblk0pN" pairs, plus the eMMC hardware boot areas.
LIST=$(asu ls -l "$BYNAME" | sed -n 's/.* \([^ ]*\) -> \(\/dev\/block\/[^ ]*\)$/\1 \2/p')
for b in mmcblk0boot0 mmcblk0boot1; do
  asu ls /dev/block/$b >/dev/null 2>&1 && LIST="$LIST
emmc_$b /dev/block/$b"
done

MD5="busybox md5sum"
asu busybox md5sum /system/build.prop >/dev/null 2>&1 || MD5="md5sum"

echo "$LIST" | while read -r name dev; do
  [ -n "$name" ] || continue
  case "$name" in userdata|cache|data) echo "skip $name (personal data / cache)"; continue;; esac
  printf 'reading %-14s %s ... ' "$name" "$dev"
  asu dd if="$dev" of=/data/local/tmp/fw.img bs=1048576 >/dev/null 2>&1
  asu chmod 644 /data/local/tmp/fw.img
  remote=$(asu $MD5 "$dev" 2>/dev/null | cut -d' ' -f1)
  adbc pull /data/local/tmp/fw.img "$(localpath "$DEST/$name.img")" >/dev/null 2>&1
  asu rm -f /data/local/tmp/fw.img
  local_md5=$(md5sum "$DEST/$name.img" 2>/dev/null | cut -d' ' -f1)
  size=$(wc -c < "$DEST/$name.img" 2>/dev/null | tr -d ' ')
  if [ -n "$remote" ] && [ "$remote" = "$local_md5" ]; then st=OK
  elif [ -z "$remote" ]; then st="UNVERIFIED (no md5 tool on TV)"
  else st="MISMATCH tv=$remote"; fi
  echo "$st"
  echo "$name $dev $size $local_md5 $st" >> "$MANIFEST"
done

echo
echo "Saved to $DEST  (checksums in MANIFEST.txt)"
grep -c ' OK$' "$MANIFEST" | xargs echo "verified OK:"
grep -v ' OK$' "$MANIFEST" && echo "^ re-run for the lines above" || true
