#!/bin/sh
# Make the remote's OK button send DPAD_CENTER instead of ENTER.
#
# Symptom: in SmartTube (and other Android TV / leanback apps) pressing OK on a search
# box does not open the keyboard, while everything else works. Cause: the IR remote's
# key layout maps OK (Linux KEY_ENTER, scancode 28) to Android ENTER; leanback widgets
# expect DPAD_CENTER, the standard Android TV select key.
#
#   TV=192.168.1.15:5555 sh scripts/remap-ok-key.sh            (auto-detect remote)
#   TV=... sh scripts/remap-ok-key.sh /system/usr/keylayout/Vendor_0208_Product_0001.kl
#   TV=... sh scripts/remap-ok-key.sh --restore
# Needs a full reboot afterwards (standby/suspend does not reload key layouts).
#
# To see what your remote really sends:  adb shell su 0 getevent -l   (press keys)
. "$(dirname "$0")/common.sh"
need_root

KL="$1"
if [ -z "$KL" ] || [ "$KL" = "--restore" ]; then
  # The input device whose name contains "IR" (remote receiver) and its layout file.
  KL=$(adbsh dumpsys input | awk '
      /^ *[0-9]+: / { ir = ($0 ~ /IR|[Rr]emote/) }
      ir && /KeyLayoutFile:/ { print $2; exit }')
  [ -n "$KL" ] || { echo "Could not detect the remote. Pass the .kl path (see: adb shell dumpsys input)." >&2; exit 1; }
fi
NAME=$(basename "$KL")
BK="$OUT/$NAME.original"

if [ "$1" = "--restore" ]; then
  [ -f "$BK" ] || { echo "no backup $BK" >&2; exit 1; }
  system_rw; push_root "$BK" "$KL"; system_ro; echo "restored $KL - reboot to apply"; exit 0
fi

echo "remote key layout: $KL"
[ -f "$BK" ] || adbc pull "$KL" "$(localpath "$BK")" >/dev/null
grep -E '^key[[:space:]]+28[[:space:]]' "$BK" || { echo "no 'key 28' line - nothing to change"; exit 0; }
sed -E 's/^(key[[:space:]]+28[[:space:]]+)ENTER([[:space:]]*)$/\1DPAD_CENTER\2/' "$BK" > "$OUT/$NAME"
cmp -s "$BK" "$OUT/$NAME" && { echo "already DPAD_CENTER (or not ENTER) - nothing to do"; exit 0; }

system_rw
push_root "$OUT/$NAME" "$KL"
system_ro
asu cat "$KL" | grep -E '^key[[:space:]]+28[[:space:]]'
echo "Done. Reboot the TV fully:  adb -s $TV shell $SU reboot"
