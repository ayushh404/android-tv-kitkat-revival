# Reviving an old Android TV (Android 4.4 KitKat) over Wi-Fi

This guide takes a cheap, outdated Android smart TV, where YouTube has stopped working and nothing gets updates, and makes it useful again. It works **from a laptop over Wi-Fi with ADB**, starting from nothing installed, and doesn't open the TV.

It was written while fixing a real TV: a **Video-scape VST358C** (MStar MSD6A358 "Mainz" board, 512 MB RAM, Android 4.4.4). Most cheap MStar/"universal board" TVs from 2015–2020 behave the same way. The scripts detect what they need and refuse unsafe actions.

> **Read this first.** You change your own TV at your own risk. Back up before every system change (step 4). The scripts only remove or replace individual files and never flash firmware. Even so, a wrong file in `/system` can stop a TV from booting.

---

## What you can and can't get

| Goal | Result | Why |
|---|---|---|
| YouTube | ✅ **Works** with [SmartTube](https://github.com/yuliskov/SmartTube) | Google retired the official YouTube app on old Android, so its servers reject it. SmartTube supports Android 4.2+, uses the TV's hardware decoder, lets you sign in, and has no ads. |
| Websites that "stopped working" | ✅ **Mostly fixed** | Android 4.4 lacks the Let's Encrypt root certificate (ISRG Root X1). Installing it fixes HTTPS for a large part of the web. |
| Fewer ads and trackers | ✅ System-wide hosts blocklist | |
| Local media (USB, network) | ✅ Kodi 16.1 | The last Kodi version for Android 4.x |
| Casting from a phone | ✅ SmartTube "Link with TV code" and Miracast screen mirroring | |
| **Netflix / Hotstar / Prime Video** | ❌ **Impossible on these TVs** | They need Android 5+ **and Widevine DRM keys**, which are provisioned per device at the factory. These TVs ship with no Widevine at all, and no software, ROM or patch can add it. Use a streaming stick in the HDMI port. |
| Newer Android / custom ROM / Linux | ❌ Not realistic | There's no public source for MStar's GPU, video decoder or TV drivers, and newer builds only exist for 1 GB+ boards. Flashing wrong firmware usually means a boot-logo brick that needs a UART cable to fix. |

---

## Quick start: control the TV from your laptop (`tvctl`)

[`tvctl.py`](tvctl.py) is a single-file tool that needs only Python 3.8+ and no other installs. It finds the TV on your Wi-Fi, connects to it, and turns your laptop keyboard into the TV remote.

```sh
python tvctl.py setup-adb              # only if you don't have adb: downloads Google's platform-tools
python tvctl.py find                   # scans your Wi-Fi for TVs with ADB open
python tvctl.py connect 192.168.1.15   # accept "Allow USB debugging?" on the TV; remembered
python tvctl.py remote                 # arrows / Enter / Backspace / h=Home / +- volume / t=type / q=quit
```

| Command | What it does |
|---|---|
| `remote` | Keyboard remote: arrows, Enter = OK, Backspace/Esc = Back, `h` Home, `m` Menu, `+`/`-` volume, `0` mute, `p` play/pause, `[` `]` rewind/forward, `,` `.` channel, `i` input/source, `s` settings, `t` type text, `y` SmartTube, `k` Kodi, `P` power, `q` quit |
| `key ok back home volup …` | Send one or more keys. Names or any Android keycode number. |
| `type "text"` | Type into the focused text box, much faster than the on-screen keyboard |
| `open smarttube` / `open <package>` | Launch an app. Add your own aliases under `"apps"` in `~/.tvctl/config.json`. |
| `apps`, `install file.apk`, `info`, `screenshot`, `shell [cmd]`, `reboot`, `disconnect` | What they say |

First you need to turn on **USB debugging** on the TV (step 1 below). Everything else in this guide also works with plain `adb`.

## 0. What you need

- A computer (Windows, macOS or Linux) on the **same Wi-Fi** as the TV.
- **On Windows, Git Bash.** It comes with [Git for Windows](https://git-scm.com/download/win) and includes `curl` and `openssl`. All scripts are POSIX `sh`.
- **ADB (Android platform-tools)**, which needs no installer:
  - Windows: download `https://dl.google.com/android/repository/platform-tools-latest-windows.zip`, unzip it, and use `platform-tools\adb.exe`.
  - macOS: `brew install android-platform-tools`. Linux: `sudo apt install adb`.
- About 1.5 GB free disk space for the firmware backup.

If `adb` isn't on your PATH, point the scripts at it:
```sh
export ADB="$HOME/platform-tools/adb.exe"
```

## 1. Turn on debugging on the TV

1. Go to **Settings > Device Preferences > About** (sometimes just Settings > About) and press OK on **Build** **7 times**. You'll see "You are now a developer".
2. Go back to **Developer options** and turn on **USB debugging**. If there's a **Network/ADB debugging** switch, turn it on too. Many KitKat TVs don't have one and still listen on port 5555 once USB debugging is on.
3. Keep the TV on.

## 2. Find and connect to the TV

```sh
bash scripts/find-tv.sh 192.168.1        # use your network's first three numbers
# Windows PowerShell alternative: scripts\find-tv.ps1 -Net 192.168.1
adb connect 192.168.1.15:5555            # the address it found
```
The first `connect` prints `failed to authenticate` / `unauthorized`. **Look at the TV:** a popup asks **"Allow USB debugging?"**. Tick *Always allow from this computer* and press **Allow**. Then run:
```sh
adb devices            # should show: 192.168.1.15:5555   device
export TV=192.168.1.15:5555
```
Every script below reads `TV` (and optionally `ADB` and `OUT`, the backup folder, which defaults to `./tv-backup`).

## 3. See what you have (read-only)

```sh
sh scripts/device-info.sh | tee device-info.txt
```
This shows the Android version, RAM, CPU type, whether it's rooted, the partitions, hardware video decoders, **whether Widevine exists**, whether the Let's Encrypt root is missing, and all installed packages.

### Is the TV rooted?
Many cheap TVs ship **`userdebug` builds with `test-keys` and a working `su`**. Look for `ro.build.type userdebug` and `uid=0(root)` in the report. If `su` works, you can change `/system`. If it doesn't, you can still sideload apps (step 7) and tune animations, but steps 5, 6, 8 and 9 need root. This guide does **not** cover exploiting a TV to get root.

## 4. Back up the firmware first

```sh
sh scripts/backup-firmware.sh
```
- This makes a read-only image of every partition (bootloader, kernel, recovery, system, TV config) in `tv-backup/firmware/`, and **md5-verifies each image against the TV**. It skips `userdata` and `cache`.
- It takes about 15–20 minutes for about 1 GB over Wi-Fi.
- **Keep these images private.** `tvcertificate`, `tee` and `MBOOT` contain keys unique to your TV (HDCP, CI+). Never upload them. `.gitignore` excludes them.

## 5. Remove preinstalled junk

```sh
sh scripts/remove-system-apps.sh com.facebook.katana com.amazon.avod.thirdpartyclient \
  com.android.noisefield com.android.phasebeam com.android.dreams.phototable com.android.dreams.basic
adb -s $TV shell su 0 reboot
```
Each APK is **copied to `tv-backup/apks/` first**. Undo with `sh scripts/restore-system-apps.sh`.
On KitKat, `pm uninstall` / `pm disable` of system apps returns `Failure` without root, so the script deletes the APK from `/system/app` as root and records it in `removed.txt`.

**Safe on the reference TV:** Facebook, the old Amazon Prime Video app (`com.amazon.avod.thirdpartyclient`), Aptoide TV (`cm.aptoidetv.pt`), the old YouTube TV app (`com.google.android.youtube.tv`), and the screensavers (`noisefield`, `phasebeam`, `dreams.phototable`, `dreams.basic`).

**Keep:**
- The launcher (`com.vstv.tvoslauncher` or similar), `com.android.systemui`, settings, the package installer and `android`.
- **Every `com.mstar.*` package**, which handles TV input, HDMI and the tuner.
- The keyboard (`com.android.inputmethod.latin`).
- **Screen mirroring** (`com.vstv.wifi.miracast`) and the cast service (`com.android.mcast`), if you want to cast from a phone.
- Text-to-speech (`com.svox.pico`), if unsure.

**Never open or remove factory apps** (`*factory*`, `com.vstv.designmenu`, `*fac.menu*`). On MStar boards, opening one can set factory flags that break inputs. The script refuses them.

## 6. Fix HTTPS: install the Let's Encrypt root

```sh
sh scripts/install-isrg-root.sh          # --remove to undo
```
Android older than 7.1 doesn't trust **ISRG Root X1**. Since the old cross-signed DST Root CA X3 expired, every site or app server using a Let's Encrypt certificate fails on these TVs. The script downloads the certificate from letsencrypt.org, **checks the published SHA-256 fingerprint**, and installs it as `/system/etc/security/cacerts/6187b673.0`.

## 7. Install apps that still work on KitKat

```sh
sh scripts/install-apps.sh smarttube kodi
```
- **SmartTube:** the latest **stable** release from the official GitHub. Set `ARCH=arm64-v8a` on a 64-bit TV, and check with `adb shell getprop ro.product.cpu.abi`.
- **Kodi 16.1 "Jarvis":** from `mirrors.kodi.tv`, checked against the mirror's `.sha256`. Kodi 17+ needs Android 5.
- **Browser (optional):** **Firefox 68** is the last Firefox for Android 4.x and has its own engine and certificate store. It handles far more sites than the built-in browser, whose WebView is about Chrome 33. Get it from Mozilla's archive (`ftp.mozilla.org/pub/mobile/releases/68.12.0/`). Phone browsers are clumsy with a TV remote, so an air mouse or USB mouse helps.

Install any other APK with `adb -s $TV install app.apk`. Use only official sources or APKMirror, which verifies signatures, and never "modded" APKs.

## 8. Block ads and trackers system-wide

```sh
sh scripts/install-adblock-hosts.sh       # --restore to put the original back
```
This installs Peter Lowe's list of about 3,500 ad and tracking domains as `/system/etc/hosts`. The list is deliberately small for a 512 MB TV, and I measured the lookup cost at about 10 ms. It blocks ad domains like `doubleclick.net` and `ads.youtube.com`, not video servers. It doesn't remove YouTube's in-video ads; SmartTube does that.

## 9. Fix: OK button doesn't open the keyboard in SmartTube

**Symptom:** OK works everywhere else, but on SmartTube's search box nothing happens.
**Cause:** the IR remote's key layout maps OK (Linux `KEY_ENTER`, scancode 28) to Android `ENTER`. Android TV ("leanback") apps expect **`DPAD_CENTER`**.
```sh
adb -s $TV shell su 0 getevent -l       # press OK: shows KEY_ENTER -> confirms the cause (Ctrl+C to stop)
sh scripts/remap-ok-key.sh              # auto-detects the IR remote's .kl file; --restore to undo
adb -s $TV shell su 0 reboot            # a FULL reboot; standby does not reload key layouts
```

## 9b. Make the remote's YouTube button open SmartTube

On these TVs, the YouTube button sends a vendor key (`KEY_FN_E`, code `0x1e1`, labelled `VS_APP2` in the key layout). The stock launcher used it to open the old YouTube app. Once that app is gone, the button does nothing.
```sh
sh scripts/install-app-button.sh                     # YouTube button -> SmartTube, at every boot
KEYCODE=0x1e1 PKG=org.xbmc.kodi ACT=org.xbmc.kodi.Splash sh scripts/install-app-button.sh   # any button -> any app
sh scripts/install-app-button.sh --remove
```
- **How it works:** a small root listener ([`device-files/install-recovery.sh`](device-files/install-recovery.sh)) reads the remote's input device and runs `am start` when it sees the button. It starts at boot through the stock `init.rc` service **`flash_recovery`**, which runs `/system/etc/install-recovery.sh`. Most KitKat TVs don't have that file, so the boot image doesn't need editing.
- The installer **refuses** if the TV has no such service, or if an `install-recovery.sh` already exists that isn't ours. On some devices that file flashes recovery or starts SuperSU.
- It **self-tests** by injecting a fake button press with `sendevent`, then checks that the app came up.
- **Find any button's code:** run `adb shell su 0 getevent` and press the button. `0001 01e1 00000001` means `KEYCODE=0x1e1`.
- **Gotcha we hit:** `getevent | while read …` doesn't work on KitKat, because getevent buffers its output when piped, so the listener reads `/dev/input/eventN` directly with `dd` and `od`. KitKat's toolbox also has no `basename`, so use `busybox basename`.

## 10. Make it faster

```sh
sh scripts/tune-performance.sh          # animations off (--revert to undo); no root needed
```
These TVs have about 440 MB usable RAM, and SmartTube alone uses about 120 MB, so some slowness is unavoidable. Recommended **SmartTube** settings, under **Settings > Player**:
- **Video format: AVC (H.264).** This decodes in hardware (`OMX.MS.AVC.Decoder`) and is the most reliable path on these chips.
- **Video buffer: Medium.** It fixes stalls mid-video. High may crash low-RAM TVs, so try it only if Medium still buffers.
- **Quality:** Auto is fine. If it keeps stalling, pick a fixed 720p, which matches these 1366×768 panels anyway.
- Turn off home-screen sections you don't use.

To find out whether buffering is your network or the TV, test the TV's real download speed:
```sh
adb -s $TV shell "busybox time busybox wget -q -O /dev/null http://dl.google.com/android/repository/platform-tools-latest-windows.zip"
```
About 8 MB in under 3 seconds means the network is fine.

## 11. Cast to the TV

- **YouTube from your phone (best):** in SmartTube, go to **Settings > Remote control / Link with phone** and note the TV code. In the phone's YouTube app, go to **Settings > Watch on TV > Enter TV code**. After that, the cast button on the phone shows your TV.
- **Mirror any screen (Miracast):** open the TV's **Wireless Display** app. On an Android phone, use **Smart View / Screen Cast / Cast**. On a Windows laptop, press **Win + K**. iPhones can't do this, because they only support AirPlay. DRM apps like Netflix and Hotstar usually show a black screen when mirrored.
- **Signing in to SmartTube:** use **Settings > Accounts > Add account** and enter the code at `youtube.com/activate` on your phone. Google's sign-in page often doesn't work in the TV's old browser.

## 12. When you're done: close ADB

Port 5555 is **unencrypted**. Anyone on your Wi-Fi who connects and has been authorised once can control the TV.
```sh
adb disconnect $TV
```
Then turn **USB debugging off** on the TV under Developer options, and turn it back on next time you need it.

---

## Restore / undo cheat sheet

| Change | Undo |
|---|---|
| Removed apps | `sh scripts/restore-system-apps.sh [package…]`, then reboot |
| Let's Encrypt root | `sh scripts/install-isrg-root.sh --remove` |
| Ad-block hosts | `sh scripts/install-adblock-hosts.sh --restore` |
| OK-key remap | `sh scripts/remap-ok-key.sh --restore`, then reboot |
| YouTube-button → app | `sh scripts/install-app-button.sh --remove` |
| Animations | `sh scripts/tune-performance.sh --revert` |
| Installed apps | `adb -s $TV uninstall org.smarttube.stable` (Kodi: `org.xbmc.kodi`) |

## Troubleshooting

| Problem | Fix |
|---|---|
| `/system/...` paths turn into `C:/Program Files/Git/...` | Git Bash path conversion. The scripts set `MSYS_NO_PATHCONV=1`. Do the same for manual commands, or run `adb` from PowerShell. |
| `adb pull` "No such file or directory" for the local path | With path conversion off, adb.exe needs `C:\...` paths. The scripts convert them with `cygpath -w`. |
| `su -c '...'` gives `exec failed ... No such file or directory` | This `su` takes the command as separate arguments: `su 0 mount -o remount,rw /system`. Set `SU="su -c"` if yours is the other kind. |
| Streaming a partition with `adb exec-out` gives empty files | KitKat's adbd has no `exec-out`. Use `backup-firmware.sh`, which copies each partition with dd, pulls it and compares md5s. |
| `mount -o remount,ro /system`: "Device or resource busy" | Harmless. It's read-only again after the next boot. |
| The TV doesn't come back after `reboot` | Press power on the remote. If nothing happens, unplug it for 10 seconds. These boards often stay in standby after a software reboot. |
| `screencap` gives an empty or black image | MStar TVs often block screen capture. Use `uiautomator dump` to read the screen layout instead. |
| `adb install` says `INSTALL_FAILED_OLDER_SDK` | That app needs a newer Android. Find an older version that lists "Min: Android 4.4 (API 19)". |

## Findings from the reference TV (VST358C)

- **Board:** `build_Mainz_VS_MSD6A358_DTMB_512_TEE`, MStar MSD6A358 ("mainz"), 4× ARMv7, 512 MB RAM, 3.8 GB eMMC.
- **Software:** Android 4.4.4 `userdebug`/`test-keys` from 2019, Linux 3.10.86, SELinux permissive, `su` at `/system/xbin/su`.
- **Updates:** the update server is set to a private factory address, so **this TV can never receive updates.**
- **DRM:** `widevine/config.ini` points to a `KeyBox.bin` that doesn't exist, and there are no Widevine libraries. That's the definitive reason Netflix, Hotstar and Prime can't work.
- **Hardware decoders:** AVC, HEVC, VP8 and VP9 (VP9 limited below 1440p), MPEG-2 and others.
- **Remote:** "Vstv Smart TV IR Receiver" (`/dev/input/event0`), layout file `Vendor_0208_Product_0001.kl`. OK = `KEY_ENTER` (scancode 28). YouTube button = `KEY_FN_E` (481, `0x1e1`, `VS_APP2`). The colored keys send `KEY_FN_F`, `KEY_FN_S` and `KEY_FN_B` (`VS_APP3`–`VS_APP5`).
- **Boot hook:** `init.rc` defines `service flash_recovery /system/etc/install-recovery.sh` (class main, oneshot), and the file is absent on stock firmware.

## Credits and further reading

- [SmartTube](https://github.com/yuliskov/SmartTube) by yuliskov
- [CleanYourTV](https://github.com/Gathin23/cleanyourtv): debloat plus a new launcher for **Android 8+** TVs. Its launcher needs API 26, so use it instead of this guide if your TV is newer.
- [Let's Encrypt: Android 4.4 and ISRG Root X1](https://community.letsencrypt.org/t/help-which-certificates-to-install-on-android-4-4/212077)
- [XDA: MStar Android TV firmware tools](https://xdaforums.com/t/tools-mstar-android-tv-firmware-tools.3559227/): unpacking and repacking MStar `.bin` files, not new OSes
- [Peter Lowe's ad server list](https://pgl.yoyo.org/adservers/)

## License

MIT. See [LICENSE](LICENSE). Third-party apps and lists keep their own licenses. This repo contains none of them, only scripts that download them from their official sources.
