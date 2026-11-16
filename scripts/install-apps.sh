#!/bin/sh
# Download from official sources, verify, and install apps that still run on KitKat.
#   TV=192.168.1.15:5555 sh scripts/install-apps.sh smarttube kodi
#
#   smarttube  latest STABLE SmartTube from github.com/yuliskov/SmartTube (armeabi-v7a)
#   kodi       Kodi 16.1 "Jarvis" - the last Kodi for Android 4.x - from mirrors.kodi.tv
#              (checksum checked against the mirror's .sha256)
# Set ARCH=arm64-v8a for a 64-bit TV (check: adb shell getprop ro.product.cpu.abi).
. "$(dirname "$0")/common.sh"
ARCH="${ARCH:-armeabi-v7a}"
D="$OUT/apps"; mkdir -p "$D"

install_apk() { echo "installing $1 ..."; adbc install -r "$(localpath "$1")"; }

for app in "$@"; do
  case "$app" in
    smarttube)
      url=$(curl -fsS https://api.github.com/repos/yuliskov/SmartTube/releases/latest \
            | grep -o "https://[^\"]*SmartTube_stable_[^\"]*_${ARCH}\.apk" | head -1)
      [ -n "$url" ] || { echo "could not find a stable $ARCH SmartTube release" >&2; continue; }
      echo "SmartTube: $url"
      curl -fsSL -o "$D/smarttube.apk" "$url" && install_apk "$D/smarttube.apk" ;;
    kodi)
      base=https://mirrors.kodi.tv/releases/android/arm/old/kodi-16.1-Jarvis-armeabi-v7a.apk
      curl -fsSL -o "$D/kodi-16.1.apk" "$base" || continue
      want=$(curl -fsSL "$base.sha256" | cut -d' ' -f1)
      have=$(sha256sum "$D/kodi-16.1.apk" | cut -d' ' -f1)
      [ "$want" = "$have" ] || { echo "Kodi checksum mismatch - not installing" >&2; continue; }
      install_apk "$D/kodi-16.1.apk" ;;
    *) echo "unknown app: $app (smarttube | kodi)" ;;
  esac
done
