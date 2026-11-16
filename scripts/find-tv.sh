#!/usr/bin/env bash
# Find devices on your local network with the ADB port open.
#   bash scripts/find-tv.sh 192.168.1      (scans 192.168.1.1 - .254, port 5555)
#   bash scripts/find-tv.sh 192.168.0 5555
# Needs bash (uses /dev/tcp). On Windows without Git Bash, use find-tv.ps1.

NET="${1:-192.168.1}"
PORT="${2:-5555}"
echo "Scanning $NET.1-254 for port $PORT ..."
for i in $(seq 1 254); do
  (
    if timeout 1 bash -c "exec 3<>/dev/tcp/$NET.$i/$PORT" 2>/dev/null; then
      echo "OPEN  $NET.$i:$PORT"
    fi
  ) &
done
wait
echo "Done. Connect with:  adb connect <ip>:$PORT"
