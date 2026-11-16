#!/system/bin/sh
# Runs as root at every boot (init.rc service "flash_recovery", class main, oneshot).
# Watches the IR remote and opens SmartTube when the YouTube button (Linux scancode 0x1e1
# = KEY_FN_E = 481) is pressed. Android itself drops this vendor key.
#
# Change PKG/ACT for another app, and KEY for another button
# (find it with:  adb shell su 0 getevent  and press the button; the middle number).
#
# NOTE: do not "getevent | while read": Android 4.4's getevent buffers its output when
# piped, so events arrive late or never. We read the input device directly instead:
# one 16-byte struct input_event (32-bit ARM) at a time, with the device kept open.
PKG=org.smarttube.stable
ACT=com.liskovsoft.smartyoutubetv2.tv.ui.main.SplashActivity
KEY="0001 01e1 0001 0000"      # od -tx2 of: type=EV_KEY code=0x1e1 value=1 (down)
REMOTE_NAME="IR Receiver"      # part of the input device name of the remote
BB=/system/bin/busybox
LOG=/data/local/tmp/ytkey.log

# wait for Android to finish booting
while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done
sleep 5

# find the remote's /dev/input/eventN by name
dev=
for d in /sys/class/input/input*; do
  if $BB grep -q "$REMOTE_NAME" "$d/name" 2>/dev/null; then
    # KitKat's toolbox has no basename/ls -1 quirks: use busybox for everything
    e=$($BB ls "$d" | $BB grep '^event' | $BB head -n 1)
    [ -n "$e" ] && dev=/dev/input/$e
  fi
done
[ -c "$dev" ] || dev=/dev/input/event0
echo "$($BB date) listening on $dev" > $LOG

exec 3<"$dev"
last=0
while :; do
  ev=$($BB dd bs=16 count=1 <&3 2>/dev/null | $BB od -An -v -tx2 -w16)
  case "$ev" in
    *"$KEY"*)
      now=$($BB date +%s)
      if [ $((now - last)) -ge 2 ]; then          # ignore key repeats
        last=$now
        am start -n "$PKG/$ACT" >> $LOG 2>&1
      fi ;;
  esac
done
