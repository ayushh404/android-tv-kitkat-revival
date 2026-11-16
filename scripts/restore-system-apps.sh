#!/bin/sh
# Put back system apps removed by remove-system-apps.sh (reads $OUT/apks/removed.txt).
#   TV=192.168.1.15:5555 sh scripts/restore-system-apps.sh            (all)
#   TV=192.168.1.15:5555 sh scripts/restore-system-apps.sh com.facebook.katana
. "$(dirname "$0")/common.sh"
need_root
LIST="$OUT/apks/removed.txt"
[ -f "$LIST" ] || { echo "No $LIST - nothing recorded as removed." >&2; exit 1; }

system_rw
while read -r pkg path; do
  [ -n "$pkg" ] || continue
  if [ $# -gt 0 ]; then echo " $* " | grep -q " $pkg " || continue; fi
  [ -f "$OUT/apks/$pkg.apk" ] || { echo "missing backup for $pkg"; continue; }
  push_root "$OUT/apks/$pkg.apk" "$path" && echo "restored $pkg -> $path"
done < "$LIST"
system_ro
echo "Reboot the TV to finish:  adb -s $TV shell $SU reboot"
