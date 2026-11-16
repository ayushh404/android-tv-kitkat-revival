#!/bin/sh
# Turn off UI animations (noticeably snappier on 512 MB / weak-CPU TVs). No root needed.
#   TV=192.168.1.15:5555 sh scripts/tune-performance.sh
#   TV=... sh scripts/tune-performance.sh --revert
. "$(dirname "$0")/common.sh"
V=0; [ "$1" = "--revert" ] && V=1
for k in window_animation_scale transition_animation_scale animator_duration_scale; do
  adbsh settings put global $k $V
  echo "$k = $(adbsh settings get global $k)"
done
