#!/bin/sh
# Read-only report: what TV is this, what can it run, is it rooted, what is missing.
#   TV=192.168.1.15:5555 sh scripts/device-info.sh | tee tv-backup/device-info.txt
. "$(dirname "$0")/common.sh"

sec() { printf '\n===== %s\n' "$1"; }

sec "Identity"
for p in ro.product.manufacturer ro.product.brand ro.product.model ro.product.device \
         ro.board.platform ro.hardware ro.build.version.release ro.build.version.sdk \
         ro.build.display.id ro.build.type ro.build.date ro.product.cpu.abi ro.adb.secure; do
  printf '%-28s %s\n' "$p" "$(adbsh getprop $p)"
done
adbsh cat /proc/version

sec "Memory"
adbsh cat /proc/meminfo | grep -E 'MemTotal|MemFree|SwapTotal'

sec "Storage"
adbsh df

sec "Root"
adbsh ls -l /system/xbin/su /system/bin/su 2>/dev/null
asu id 2>/dev/null

sec "Board build (MStar TVs)"
asu cat /tvconfig/config/buildsetting 2>/dev/null
asu cat /tvcustomer/Customer/ServerURL.txt 2>/dev/null && echo "  ^ the firmware's update server"

sec "Partitions"
asu ls -l /dev/block/platform/*/by-name 2>/dev/null

sec "Hardware video decoders"
adbsh cat /system/etc/media_codecs.xml | grep -o 'name="OMX[^"]*Decoder" type="video/[^"]*"'

sec "Widevine DRM (needed by Netflix / Hotstar / Prime)"
found=$(adbsh "ls /system/vendor/lib/mediadrm /system/lib/mediadrm /vendor/lib/mediadrm 2>/dev/null; ls /system/lib /system/vendor/lib 2>/dev/null" | grep -i -E 'widevine|wvdrm|oemcrypto')
if [ -n "$found" ]; then echo "$found"; else echo "NONE FOUND - DRM streaming services cannot work on this TV"; fi

sec "Let's Encrypt root certificate (ISRG Root X1)"
if adbsh ls /system/etc/security/cacerts | grep -qx '6187b673.0'; then
  echo "present"
else
  echo "MISSING - many HTTPS sites/apps fail; see scripts/install-isrg-root.sh"
fi

sec "Installed packages"
echo "system:";      adbsh pm list packages -s | sort
echo "third-party:"; adbsh pm list packages -3 | sort
