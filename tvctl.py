#!/usr/bin/env python3
"""
tvctl - control an Android TV from your laptop over Wi-Fi (ADB).

Zero dependencies (Python 3.8+ standard library). Works on Windows, macOS and Linux.

    python tvctl.py setup-adb          # download Google's platform-tools if you have no adb
    python tvctl.py find               # scan your Wi-Fi for TVs with ADB open
    python tvctl.py connect 192.168.1.15
    python tvctl.py remote             # use your keyboard as the TV remote
    python tvctl.py type "hello world" # type into the focused text box
    python tvctl.py open smarttube     # launch an app (alias or package name)
    python tvctl.py help               # everything else

First connection: the TV shows "Allow USB debugging?" - tick "Always allow" and press Allow.
Enable it first on the TV: Settings > About > press OK on "Build" 7 times > Developer
options > USB debugging ON.
"""
import json
import os
import platform
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.request
import zipfile
from concurrent.futures import ThreadPoolExecutor

HOME_DIR = os.path.join(os.path.expanduser("~"), ".tvctl")
CONFIG = os.path.join(HOME_DIR, "config.json")
PORT = 5555

# Android key codes (android.view.KeyEvent)
KEYS = {
    "up": 19, "down": 20, "left": 21, "right": 22, "ok": 23, "center": 23,
    "back": 4, "home": 3, "menu": 82, "settings": 176,
    "volup": 24, "voldown": 25, "mute": 164, "power": 26, "sleep": 223, "wakeup": 224,
    "playpause": 85, "play": 126, "pause": 127, "stop": 86, "next": 87, "prev": 88,
    "rewind": 89, "forward": 90, "chup": 166, "chdown": 167, "input": 178,
    "enter": 66, "del": 67, "search": 84, "info": 165, "guide": 172,
    "red": 183, "green": 184, "yellow": 185, "blue": 186,
}

# Friendly names for `open`. Add your own in ~/.tvctl/config.json under "apps".
APP_ALIASES = {
    "smarttube": "org.smarttube.stable",
    "smarttube-beta": "org.smarttube.beta",
    "kodi": "org.xbmc.kodi",
    "youtube": "com.google.android.youtube.tv",
    "settings": "com.android.settings",
    "browser": "com.android.browser",
    "firefox": "org.mozilla.firefox",
    "netflix": "com.netflix.ninja",
    "vlc": "org.videolan.vlc",
}

REMOTE_HELP = """
  Keyboard remote  (focus this window; keys go to the TV)
  ---------------------------------------------------------
  Arrows       move            Enter / Space   OK
  Backspace    Back            Esc             Back
  h            Home            m               Menu
  + / -        Volume up/down  0               Mute
  p            Play/Pause      [ / ]           Rewind / Forward
  n / b        Next / Previous , / .           Channel down / up
  i            TV input/source s               Settings
  t            TYPE text (then Enter to send)
  y            open SmartTube  k               open Kodi
  P            Power (standby) r               refresh this help
  q            quit
"""


# ----------------------------------------------------------------- config / adb
def load_config():
    try:
        with open(CONFIG, "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_config(cfg):
    os.makedirs(HOME_DIR, exist_ok=True)
    with open(CONFIG, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)


def find_adb():
    """ADB from $ADB, ~/.tvctl/platform-tools, PATH, or the usual SDK folders."""
    exe = "adb.exe" if os.name == "nt" else "adb"
    candidates = [
        os.environ.get("ADB"),
        os.path.join(HOME_DIR, "platform-tools", exe),
        shutil.which("adb"),
        os.path.join(os.path.expanduser("~"), "platform-tools", exe),
        os.path.join(os.environ.get("LOCALAPPDATA", ""), "Android", "Sdk", "platform-tools", exe),
        os.path.join(os.path.expanduser("~"), "Library", "Android", "sdk", "platform-tools", exe),
        os.path.join(os.path.expanduser("~"), "Android", "Sdk", "platform-tools", exe),
    ]
    for c in candidates:
        if c and os.path.isfile(c):
            return c
    return None


def setup_adb():
    """Download Google's official platform-tools into ~/.tvctl/platform-tools."""
    osname = {"Windows": "windows", "Darwin": "darwin", "Linux": "linux"}.get(platform.system())
    if not osname:
        sys.exit("Unsupported OS for automatic download; install adb yourself.")
    url = f"https://dl.google.com/android/repository/platform-tools-latest-{osname}.zip"
    os.makedirs(HOME_DIR, exist_ok=True)
    zpath = os.path.join(HOME_DIR, "platform-tools.zip")
    print(f"Downloading {url} ...")
    urllib.request.urlretrieve(url, zpath)
    with zipfile.ZipFile(zpath) as z:
        z.extractall(HOME_DIR)
    os.remove(zpath)
    adb = os.path.join(HOME_DIR, "platform-tools", "adb.exe" if os.name == "nt" else "adb")
    if os.name != "nt":
        os.chmod(adb, 0o755)
    print("Installed:", adb)
    print(subprocess.run([adb, "version"], capture_output=True, text=True).stdout.strip())


ADB = None
TV = None


def adb_path():
    global ADB
    if ADB is None:
        ADB = find_adb()
        if ADB is None:
            sys.exit("adb not found. Run:  python tvctl.py setup-adb   (or set ADB=/path/to/adb)")
    return ADB


def run(args, check=False, timeout=60):
    p = subprocess.run([adb_path()] + args, capture_output=True, text=True,
                       timeout=timeout, errors="replace")
    out = (p.stdout + p.stderr).replace("\r", "").strip()
    if check and p.returncode != 0:
        sys.exit(out or f"adb {' '.join(args)} failed")
    return out


def tv_addr():
    global TV
    if TV:
        return TV
    TV = os.environ.get("TV") or load_config().get("tv")
    if not TV:
        sys.exit("No TV selected. Run:  python tvctl.py find   then   python tvctl.py connect <ip>")
    if ":" not in TV:
        TV += f":{PORT}"
    return TV


def ensure_connected():
    tv = tv_addr()
    if f"{tv}\tdevice" in run(["devices"]):
        return tv
    out = run(["connect", tv])
    time.sleep(0.5)
    state = run(["devices"])
    if f"{tv}\tdevice" in state:
        return tv
    if f"{tv}\tunauthorized" in state or "authenticate" in out:
        sys.exit("The TV hasn't allowed this computer yet. Look at the TV: accept "
                 "'Allow USB debugging?' (tick 'Always allow'), then try again.")
    sys.exit(f"Can't reach {tv}: {out}\nIs the TV on, on the same Wi-Fi, with USB debugging on?")


def sh(cmd, timeout=60):
    """Run a shell command on the TV and return its output."""
    return run(["-s", ensure_connected(), "shell", cmd], timeout=timeout)


def quote(s):
    return "'" + s.replace("'", "'\\''") + "'"


# ----------------------------------------------------------------- discovery
def local_subnet():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))  # no packet is sent; just picks the LAN interface
        ip = s.getsockname()[0]
    except OSError:
        ip = "192.168.1.2"
    finally:
        s.close()
    return ip.rsplit(".", 1)[0]


def find(subnet=None):
    subnet = subnet or local_subnet()
    print(f"Scanning {subnet}.1-254 for ADB (port {PORT}) ...")

    def probe(i):
        ip = f"{subnet}.{i}"
        with socket.socket() as s:
            s.settimeout(0.6)
            return ip if s.connect_ex((ip, PORT)) == 0 else None

    with ThreadPoolExecutor(max_workers=64) as ex:
        hits = [ip for ip in ex.map(probe, range(1, 255)) if ip]
    if not hits:
        print("Nothing found. Check the TV is on, on this Wi-Fi, and USB debugging is enabled.")
        print("Some newer TVs use 'Wireless debugging' with a pairing code instead: "
              "adb pair <ip>:<port>")
        return
    for ip in hits:
        print(f"  found  {ip}:{PORT}")
    print(f"\nNext:  python tvctl.py connect {hits[0]}")


def connect(ip):
    global TV
    TV = ip if ":" in ip else f"{ip}:{PORT}"
    out = run(["connect", TV])
    print(out)
    time.sleep(1)
    state = run(["devices"])
    if f"{TV}\tunauthorized" in state or "authenticate" in out:
        print("\n>>> Look at the TV now: accept 'Allow USB debugging?' "
              "(tick 'Always allow from this computer').")
        for _ in range(30):
            time.sleep(2)
            run(["connect", TV])
            if f"{TV}\tdevice" in run(["devices"]):
                break
    if f"{TV}\tdevice" in run(["devices"]):
        cfg = load_config()
        cfg["tv"] = TV
        save_config(cfg)
        model = sh("getprop ro.product.model")
        ver = sh("getprop ro.build.version.release")
        print(f"Connected to {model} (Android {ver}) at {TV}. Saved as your default TV.")
    else:
        sys.exit("Not connected.")


# ----------------------------------------------------------------- actions
def key(name):
    code = KEYS.get(name.lower(), name)
    sh(f"input keyevent {code}")


def type_text(text):
    # `input text` needs %s for spaces; quote everything else for the TV's shell.
    sh("input text " + quote(text.replace(" ", "%s")))


def resolve_app(name):
    apps = dict(APP_ALIASES)
    apps.update(load_config().get("apps", {}))
    return apps.get(name.lower(), name)


def open_app(name):
    pkg = resolve_app(name)
    out = sh(f"monkey -p {pkg} -c android.intent.category.LAUNCHER 1")
    if "No activities found" in out or "monkey aborted" in out:
        # leanback-only apps have no LAUNCHER category on some TVs
        out = sh(f"monkey -p {pkg} -c android.intent.category.LEANBACK_LAUNCHER 1")
    if "No activities found" in out or "monkey aborted" in out:
        sys.exit(f"Can't open {pkg} - is it installed?  (python tvctl.py apps)")
    print(f"opened {pkg}")


def list_apps():
    pk = sorted(l.replace("package:", "") for l in sh("pm list packages -3").splitlines() if l)
    print("Installed apps (yours):")
    for p in pk:
        alias = next((a for a, v in APP_ALIASES.items() if v == p), "")
        print(f"  {p}" + (f"   (alias: {alias})" if alias else ""))
    print("\nOpen one with:  python tvctl.py open <package or alias>")


def install(apk):
    if not os.path.isfile(apk):
        sys.exit(f"no such file: {apk}")
    print(run(["-s", ensure_connected(), "install", "-r", apk], timeout=600))


def info():
    props = ["ro.product.manufacturer", "ro.product.model", "ro.build.version.release",
             "ro.build.version.sdk", "ro.product.cpu.abi", "ro.build.type"]
    for p in props:
        print(f"  {p:28} {sh('getprop ' + p)}")
    mem = [l for l in sh("cat /proc/meminfo").splitlines() if l.strip()][:2]
    print("  " + "\n  ".join(mem))
    print(f"  focused: {current_app()}")


def current_app():
    out = sh("dumpsys window windows | grep -E 'mCurrentFocus|mFocusedApp'")
    return out.splitlines()[0].strip() if out else "?"


def screenshot(path="tv-screenshot.png"):
    sh("screencap -p /data/local/tmp/tvctl.png")
    run(["-s", ensure_connected(), "pull", "/data/local/tmp/tvctl.png", path])
    sh("rm /data/local/tmp/tvctl.png")
    size = os.path.getsize(path) if os.path.exists(path) else 0
    if size == 0:
        print("Screenshot is empty - many MStar TVs block screen capture.")
    else:
        print(f"saved {path} ({size // 1024} KB)")


# ----------------------------------------------------------------- keyboard remote
class TVShell:
    """One long-lived `adb shell`, so key presses don't pay adb's startup cost each time."""

    def __init__(self):
        # Binary pipe: in text mode Windows would send "\r\n" and the TV's shell would
        # see "input keyevent 4\r", which fails.
        self.p = subprocess.Popen([adb_path(), "-s", ensure_connected(), "shell"],
                                  stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL)
        self.lock = threading.Lock()

    def _write(self, cmd):
        self.p.stdin.write((cmd + "\n").encode("utf-8"))
        self.p.stdin.flush()

    def send(self, cmd):
        with self.lock:
            try:
                self._write(cmd)
            except (OSError, ValueError):
                self.__init__()  # reconnect once
                self._write(cmd)

    def close(self):
        try:
            self._write("exit")
        except (OSError, ValueError):
            pass
        self.p.terminate()


def read_key():
    """Return a key name: 'up','down','left','right','enter','backspace','esc' or a char."""
    if os.name == "nt":
        import msvcrt
        ch = msvcrt.getwch()
        if ch in ("\x00", "\xe0"):
            return {"H": "up", "P": "down", "K": "left", "M": "right"}.get(msvcrt.getwch(), "")
        return {"\r": "enter", "\x08": "backspace", "\x1b": "esc", "\x03": "q"}.get(ch, ch)
    import termios
    import tty
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        ch = sys.stdin.read(1)
        if ch == "\x1b":
            import select
            if select.select([sys.stdin], [], [], 0.05)[0]:
                seq = sys.stdin.read(2)
                return {"[A": "up", "[B": "down", "[D": "left", "[C": "right"}.get(seq, "esc")
            return "esc"
        return {"\r": "enter", "\n": "enter", "\x7f": "backspace", "\x03": "q"}.get(ch, ch)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


def remote():
    tv = ensure_connected()
    model = sh("getprop ro.product.model")
    print(f"Connected to {model} at {tv}")
    print(REMOTE_HELP)
    shell = TVShell()
    mapping = {
        "up": "up", "down": "down", "left": "left", "right": "right",
        "enter": "ok", " ": "ok", "backspace": "back", "esc": "back",
        "h": "home", "m": "menu", "+": "volup", "=": "volup", "-": "voldown", "0": "mute",
        "p": "playpause", "[": "rewind", "]": "forward", "n": "next", "b": "prev",
        ",": "chdown", ".": "chup", "i": "input", "s": "settings", "P": "power",
    }
    try:
        while True:
            k = read_key()
            if k == "q":
                break
            if k == "r":
                print(REMOTE_HELP)
            elif k == "t":
                text = input("\n  text to type on TV> ")
                if text:
                    shell.send("input text " + quote(text.replace(" ", "%s")))
                    print("  sent.")
            elif k == "y":
                shell.send(f"monkey -p {resolve_app('smarttube')} "
                           f"-c android.intent.category.LAUNCHER 1 >/dev/null 2>&1")
                print("  opening SmartTube")
            elif k == "k":
                shell.send(f"monkey -p {resolve_app('kodi')} "
                           f"-c android.intent.category.LAUNCHER 1 >/dev/null 2>&1")
                print("  opening Kodi")
            elif k in mapping:
                shell.send(f"input keyevent {KEYS[mapping[k]]}")
                print(f"  {mapping[k]}", end="\r\n" if os.name != "nt" else "\n")
    except KeyboardInterrupt:
        pass
    finally:
        shell.close()
        print("bye")


# ----------------------------------------------------------------- CLI
HELP = """tvctl - control an Android TV over Wi-Fi

  setup-adb               download Google's adb into ~/.tvctl (only if you don't have adb)
  find [subnet]           scan for TVs, e.g.  find   or   find 192.168.0
  connect <ip>            connect + remember the TV (accept the prompt on the TV)
  disconnect              drop the connection
  remote                  keyboard remote control (arrows, Enter, Backspace, ...)
  key <name|code>...      send keys:  up down left right ok back home menu volup voldown
                          mute power playpause next prev chup chdown input settings
                          red green yellow blue  (or any Android keycode number)
  type "<text>"           type into the focused text field
  open <app>              launch app: smarttube kodi settings browser ... or a package name
  apps                    list installed apps
  install <file.apk>      install an APK
  info                    model, Android version, memory, focused app
  screenshot [file.png]   grab the screen (blocked on some MStar TVs)
  shell [cmd]             run a command on the TV (no cmd = interactive shell)
  reboot                  restart the TV

  TV address: last 'connect', or set TV=ip:port.  adb: auto, or set ADB=/path/to/adb.
"""


def main(argv):
    if not argv or argv[0] in ("help", "-h", "--help"):
        print(HELP)
        return
    cmd, args = argv[0], argv[1:]
    if cmd == "setup-adb":
        setup_adb()
    elif cmd == "find":
        find(args[0] if args else None)
    elif cmd == "connect":
        if not args:
            sys.exit("usage: tvctl.py connect <ip>")
        connect(args[0])
    elif cmd == "disconnect":
        print(run(["disconnect", tv_addr()]))
    elif cmd == "remote":
        remote()
    elif cmd == "key":
        for k in args:
            key(k)
    elif cmd == "type":
        type_text(" ".join(args))
    elif cmd == "open":
        open_app(args[0] if args else sys.exit("usage: tvctl.py open <app>"))
    elif cmd == "apps":
        list_apps()
    elif cmd == "install":
        install(args[0] if args else sys.exit("usage: tvctl.py install <file.apk>"))
    elif cmd == "info":
        info()
    elif cmd == "screenshot":
        screenshot(args[0] if args else "tv-screenshot.png")
    elif cmd == "shell":
        if args:
            print(sh(" ".join(args)))
        else:
            subprocess.call([adb_path(), "-s", ensure_connected(), "shell"])
    elif cmd == "reboot":
        sh("reboot")
        print("rebooting (press the remote's power button if it stays off)")
    else:
        sys.exit(f"unknown command '{cmd}'. Try:  python tvctl.py help")


if __name__ == "__main__":
    main(sys.argv[1:])
