#!/bin/sh
# Make a remote button (e.g. the YouTube button) open an app of your choice, at every boot.
#
#   TV=192.168.1.15:5555 sh scripts/install-app-button.sh                 (YouTube btn -> SmartTube)
#   TV=... KEYCODE=0x1e1 PKG=org.xbmc.kodi ACT=org.xbmc.kodi.Splash sh scripts/install-app-button.sh
#   TV=... sh scripts/install-app-button.sh --remove
#
# How it works: a tiny root listener (device-files/install-recovery.sh) reads the remote's
# input device and runs "am start" when it sees the button. It's started at boot by the
# stock init.rc service "flash_recovery" (class main), which runs
# /system/etc/install-recovery.sh - a file most KitKat TVs don't have. No boot image edits.
#
# Find a button's code:  adb shell su 0 getevent   -> press it -> "0001 01e1 00000001"
# means EV_KEY, code 0x01e1. Pass that as KEYCODE=0x1e1.
. "$(dirname "$0")/common.sh"
need_root
DST=/system/etc/install-recovery.sh
SRC="$(dirname "$0")/../device-files/install-recovery.sh"

if [ "$1" = "--remove" ]; then
  system_rw; asu rm -f "$DST"; system_ro
  asu setprop ctl.stop flash_recovery
  echo "removed (takes full effect after reboot)"; exit 0
fi

# 1. the boot hook must exist
if ! asu cat /init.rc | grep -q 'service flash_recovery /system/etc/install-recovery.sh'; then
  echo "This TV's init.rc has no flash_recovery service - no boot hook to use. Aborting." >&2
  exit 1
fi
# 2. never clobber a real install-recovery.sh (recovery flasher / SuperSU daemon on some TVs)
if adbsh ls "$DST" 2>/dev/null | grep -qx "$DST" && \
   ! asu cat "$DST" | grep -q 'opens SmartTube\|tvctl-app-button'; then
  echo "$DST already exists and isn't ours. Inspect it first:  adb shell cat $DST" >&2
  exit 1
fi

# 3. customise the listener
KEYCODE="${KEYCODE:-0x1e1}"
PKG="${PKG:-org.smarttube.stable}"
ACT="${ACT:-com.liskovsoft.smartyoutubetv2.tv.ui.main.SplashActivity}"
hex=$(printf '%04x' "$KEYCODE")
tmp="$OUT/install-recovery.sh"
sed -e "s|^PKG=.*|PKG=$PKG|" -e "s|^ACT=.*|ACT=$ACT|" \
    -e "s|^KEY=.*|KEY=\"0001 $hex 0001 0000\"      # tvctl-app-button|" \
    "$SRC" | tr -d '\r' > "$tmp"

system_rw
push_root "$tmp" "$DST"
asu chmod 755 "$DST"
system_ro

# 4. start it now (no reboot needed) and self-test with a fake button press
asu setprop ctl.stop flash_recovery; sleep 1; asu setprop ctl.start flash_recovery
sleep 10
asu cat /data/local/tmp/ytkey.log
dev=$(asu cat /data/local/tmp/ytkey.log | sed -n 's/.*listening on //p')
code=$(printf '%d' "$KEYCODE")
asu sendevent "$dev" 1 "$code" 1; asu sendevent "$dev" 0 0 0
asu sendevent "$dev" 1 "$code" 0; asu sendevent "$dev" 0 0 0
sleep 5
if adbsh dumpsys window windows | grep mCurrentFocus | grep -q "$PKG"; then
  echo "OK: the button now opens $PKG (and will after every boot)."
else
  echo "Installed, but the self-test didn't see $PKG come up. Check: adb shell su 0 cat /data/local/tmp/ytkey.log"
fi
