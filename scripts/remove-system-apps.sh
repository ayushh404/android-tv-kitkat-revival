#!/bin/sh
# Remove preinstalled apps. Each APK is copied to this computer first so
# restore-system-apps.sh can put it back.
#   TV=192.168.1.15:5555 sh scripts/remove-system-apps.sh com.facebook.katana cm.aptoidetv.pt
#
# Apps in /data/app are uninstalled normally. Apps in /system/app (read-only, can't be
# uninstalled without root on KitKat) are deleted as root. Takes effect after a reboot.
#
# DO NOT remove: the launcher, com.android.systemui, settings, packageinstaller,
# keyboard (inputmethod.latin), android, com.mstar.* / TV services, anything with
# "factory" or "designmenu" in the name. See README "What is safe to remove".
. "$(dirname "$0")/common.sh"
[ $# -gt 0 ] || { echo "usage: TV=ip:5555 sh $0 <package> [package...]" >&2; exit 1; }

PROTECT='^(android|com\.android\.(systemui|settings|packageinstaller|shell|phone|providers\..*|inputmethod\.latin|keychain|defcontainer|location\.fused|externalstorage)|com\.mstar\..*)$'

mkdir -p "$OUT/apks"
did_system=0
for pkg in "$@"; do
  if echo "$pkg" | grep -Eq "$PROTECT"; then echo "REFUSED $pkg (core/TV package)"; continue; fi
  case "$pkg" in *factory*|*designmenu*|*fac.menu*) echo "REFUSED $pkg (factory menu - can break the TV)"; continue;; esac
  apk=$(adbsh pm path "$pkg" | sed -n 's/^package://p' | head -1)
  [ -n "$apk" ] || { echo "not installed: $pkg"; continue; }
  adbc pull "$apk" "$(localpath "$OUT/apks/$pkg.apk")" >/dev/null 2>&1 \
    || { echo "BACKUP FAILED for $pkg - not removing"; continue; }
  case "$apk" in
    /data/*)
      adbsh pm uninstall "$pkg" ;;
    /system/*)
      need_root
      [ $did_system = 1 ] || { system_rw; did_system=1; }
      asu rm "$apk"
      echo "$pkg $apk" >> "$OUT/apks/removed.txt"
      echo "removed $pkg ($apk)" ;;
  esac
done
if [ $did_system = 1 ]; then
  system_ro
  echo "Reboot the TV to finish:  adb -s $TV shell $SU reboot"
fi
