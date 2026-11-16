#!/bin/sh
# Shared helpers for the scripts in this folder. Source it, don't run it.
#
#   TV=192.168.1.15:5555 sh scripts/device-info.sh
#
# Environment:
#   TV    the TV's ADB address, ip:port (required)
#   ADB   path to adb (default: adb on PATH)
#   OUT   folder on this computer for backups (default: ./tv-backup)

ADB="${ADB:-adb}"
OUT="${OUT:-./tv-backup}"
if [ -z "$TV" ]; then
  echo "Set TV to the TV's address first, e.g.  TV=192.168.1.15:5555 sh $0" >&2
  exit 1
fi

# Git Bash on Windows rewrites arguments that look like /unix/paths into
# C:/Program Files/Git/... before adb.exe sees them. That silently breaks every
# on-device path (/system/..., /data/local/tmp/...). Turn the rewriting off.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

mkdir -p "$OUT"

# A local path in the form adb.exe understands (C:\...) when running on Windows.
localpath() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

adbc()  { "$ADB" -s "$TV" "$@"; }
adbsh() { "$ADB" -s "$TV" shell "$@" | tr -d '\r'; }

# Root shell. The su on many MStar KitKat builds takes the command as separate
# arguments ("su 0 cmd args") and fails with "exec failed" on su -c 'quoted string'.
# Override with SU="su -c" if your su needs that form.
SU="${SU:-su 0}"
asu() { "$ADB" -s "$TV" shell $SU "$@" | tr -d '\r'; }

need_root() {
  if ! asu id 2>/dev/null | grep -q 'uid=0'; then
    echo "This step needs root and '$SU id' did not return uid=0 on the TV." >&2
    echo "Check: adb shell ls -l /system/xbin/su   (see README, 'Is the TV rooted?')" >&2
    exit 1
  fi
}

system_rw() { asu mount -o remount,rw /system; }
system_ro() {
  asu sync
  # Often refused with "Device or resource busy" while Android runs. Harmless:
  # /system mounts read-only again on the next boot.
  asu mount -o remount,ro /system 2>/dev/null || true
}

# Copy a local file to an on-device path as root, root:root 0644.
push_root() { # local_file device_path
  adbc push "$(localpath "$1")" /data/local/tmp/.upload >/dev/null
  asu cp /data/local/tmp/.upload "$2"
  asu chmod 644 "$2"
  asu chown root:root "$2"
  asu rm /data/local/tmp/.upload
}
