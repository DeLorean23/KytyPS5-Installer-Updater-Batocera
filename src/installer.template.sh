#!/bin/bash
# KytyPS5 Installer & Updater for Batocera
# Installs the newest KytyPS5 Linux build (https://github.com/KytyPS5/KytyPS5),
# wires PS5 into Batocera as a normal system and updates it when a newer
# build is available. Run it from Ports.
# Created by DeLorean23
# https://github.com/DeLorean23/KytyPS5-Installer-Updater-Batocera
# License: MIT

set -uo pipefail

KYTY_DIR=/userdata/system/add-ons/kytyps5
BACKUP_DIR=/userdata/system/add-ons/kytyps5-backup
WORK=/userdata/system/.kyty-install-tmp
VERSION_FILE="$KYTY_DIR/.installer-version"
CONFIGGEN_COPY=/userdata/system/configgen
CFG=/userdata/system/configs/emulationstation/es_systems_ps5.cfg
BATOCERA_CONF=/userdata/system/batocera.conf
CUSTOM_SH=/userdata/system/custom.sh
ROM_DIR=/userdata/roms/ps5
DESKTOP=/userdata/system/.local/share/applications/kytyps5.desktop
RELEASES_API="https://api.github.com/repos/KytyPS5/KytyPS5/releases?per_page=15"
LOG_DIR=/userdata/system/logs
LOG="$LOG_DIR/kyty-installer.log"

SELF="$(readlink -f "$0")"
SELF_DIR="$(dirname "$SELF")"
SELF_NAME="$(basename "$SELF")"
SELF_STEM="${SELF_NAME%.*}"

# ---------------------------------------------------------------------------
# Open a visible terminal window (Ports scripts run without one by default)
# ---------------------------------------------------------------------------
if [[ "${1:-}" != "--in-terminal" ]]; then
    mkdir -p "$LOG_DIR"
    export DISPLAY="${DISPLAY:-:0.0}"
    if command -v xterm >/dev/null 2>&1; then
        exec xterm -fullscreen -fa "Monospace" -fs 11 -bg black -fg white \
            -T "KytyPS5 Installer & Updater" -e /bin/bash "$SELF" --in-terminal
    fi
    echo "xterm not found - cannot open a terminal window." >> "$LOG"
    exit 1
fi

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG") 2>&1
echo "===== $(date) ====="

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
show_banner() {
cat <<'BANNER'
                                                                                                      .    .
                                                                                                 .      *
                                                                                       _
                                   _       ____,--'`                      __|"/_____ __\"!_   .---.  *   .
                           __..--"`..-='"``                   _________.-----------.'o8888_\-" _." \       .
                     _.-""` .oooo"                        _.-"  `````.' .-"'````""\ \ '. / ""--"". __|  .
                  .-  ,`  '""'`                     ___<"_-._____ .-"_."-._________! \  "-!-``-._   \    *
                ."   /_.-_.-`      ____..--------`"'__..-----''`  \ "----'           |     ____  ".  \  .
              ,"  ` _.-._ _ ___  /'--====--.---''`      __.._      "           _____ /__ ." __ ".  \ | -- - -
          -- /  `    _/        -'--/.^^.7__/__        ." ___ '. ====\=========""''`," "`/ ."  \`||  \
            | ``    <_ -       \____...______/\_____ / `/   '.\\     \       ____.'____/  |(^ | !| _!
             \ ``     '--.      \.._______  /   `'""!|`| (^  ||`"-----===="""          |` '.__' /"`
              "-.`    `._ ._              `"'"------||  \__ .'/ ----================""" "._____. ____
                 `"Oo._     `"oo.____                `'._____' ____
                      `"==-..______. ```                                                               
                                 ````                                                         ____________
                                                                    ________________.

                         
                    KytyPS5 Installer & Updater
                       Created by DeLorean23
BANNER
printf '\n'
}

fail() {
    echo
    echo "[ERROR] $*"
    echo "Log: $LOG"
    rm -rf "$WORK"
    echo
    wait_key
    exit 1
}

log()  { echo "[ps5] $*"; }

extract_payload() {  # extract_payload <name> <target file>
    awk -v n="$1" '$0=="__"n"_BEGIN__"{f=1;next} $0=="__"n"_END__"{f=0} f' "$SELF" | base64 -d > "$2"
}

# Cover for this Ports entry: write it into the Ports gamelist
update_gamelist() {
python3 - "$SELF_DIR/gamelist.xml" "./$SELF_NAME" "./images/$SELF_STEM.jpg" "$SELF_STEM" <<'PY'
import os, sys
import xml.etree.ElementTree as ET
gl, path, image, name = sys.argv[1:5]
if os.path.exists(gl):
    tree = ET.parse(gl); root = tree.getroot()
else:
    root = ET.Element("gameList"); tree = ET.ElementTree(root)
game = None
for g in root.findall("game"):
    p = g.findtext("path") or ""
    if os.path.basename(p) == os.path.basename(path):
        game = g; break
if game is None:
    game = ET.SubElement(root, "game")
    ET.SubElement(game, "path").text = path
for tag, val in (("name", name), ("image", image), ("thumbnail", image)):
    el = game.find(tag)
    if el is None:
        el = ET.SubElement(game, tag)
    el.text = val
tree.write(gl, encoding="utf-8", xml_declaration=True)
print("gamelist updated")
PY
}

warn() { echo "[ps5] WARNING: $*"; }

set_conf() {  # set_conf key value  (adds or updates a line in batocera.conf)
    if grep -q "^$1=" "$BATOCERA_CONF" 2>/dev/null; then
        sed -i "s|^$1=.*|$1=$2|" "$BATOCERA_CONF"
    else
        [ -f "$BATOCERA_CONF" ] && [ -n "$(tail -c1 "$BATOCERA_CONF")" ] && echo >> "$BATOCERA_CONF"
        echo "$1=$2" >> "$BATOCERA_CONF"
    fi
}

write_pad_helper() {
cat > "$1" <<'PY'
import sys, select
try:
    from evdev import InputDevice, list_devices, ecodes as e
except Exception:
    sys.exit(0)
devs = []
for p in list_devices():
    try:
        d = InputDevice(p)
        keys = set(d.capabilities().get(e.EV_KEY, []))
        if e.BTN_SOUTH in keys and e.BTN_EAST in keys:
            devs.append(d)
        else:
            d.close()
    except Exception:
        pass
if not devs:
    sys.exit(0)
fds = {d.fd: d for d in devs}
while True:
    r, _, _ = select.select(list(fds), [], [], 1.0)
    for fd in r:
        try:
            for ev in fds[fd].read():
                if ev.type == e.EV_KEY and ev.value == 1:
                    if ev.code == e.BTN_SOUTH:
                        print("y", flush=True); sys.exit(0)
                    if ev.code == e.BTN_EAST:
                        print("n", flush=True); sys.exit(0)
        except OSError:
            fds.pop(fd, None)
    if not fds:
        sys.exit(0)
PY
}

ask_yes_no() {  # returns 0 for yes, 1 for no
    local prompt="$1" answer="" key pad_pid helper out
    helper="$(mktemp /tmp/kyty-pad-XXXX.py)"
    out="$(mktemp /tmp/kyty-pad-XXXX.txt)"
    write_pad_helper "$helper"
    python3 "$helper" > "$out" 2>/dev/null &
    pad_pid=$!
    printf '%s [y/n] (Controller: A = yes, B = no): ' "$prompt"
    while [[ -z "$answer" ]]; do
        if read -rsn1 -t 0.2 key; then
            case "$key" in
                y|Y) answer="y" ;;
                n|N) answer="n" ;;
            esac
        fi
        if [[ -z "$answer" && -s "$out" ]]; then
            answer="$(head -c1 "$out")"
        fi
    done
    kill "$pad_pid" 2>/dev/null; wait "$pad_pid" 2>/dev/null
    rm -f "$helper" "$out"
    echo "$answer"
    [[ "$answer" == "y" ]]
}

wait_key() {  # waits for Enter (keyboard) or A / B (controller)
    local key pad_pid helper out
    helper="$(mktemp /tmp/kyty-pad-XXXX.py)"
    out="$(mktemp /tmp/kyty-pad-XXXX.txt)"
    write_pad_helper "$helper"
    python3 "$helper" > "$out" 2>/dev/null &
    pad_pid=$!
    printf 'Press A / Enter to exit '
    while true; do
        if read -rsn1 -t 0.2 key; then break; fi
        [[ -s "$out" ]] && break
    done
    kill "$pad_pid" 2>/dev/null; wait "$pad_pid" 2>/dev/null
    rm -f "$helper" "$out"
    echo
}

# ---------------------------------------------------------------------------
# Start
# ---------------------------------------------------------------------------
clear
show_banner

[ "$(id -u)" = "0" ]          || fail "This installer must run as root."
[ -d /userdata ]              || fail "/userdata not found. Is this Batocera?"
[ "$(uname -m)" = "x86_64" ]  || fail "KytyPS5 only has x86_64 builds. This machine is $(uname -m)."
command -v curl >/dev/null    || fail "curl not found."
command -v python3 >/dev/null || fail "python3 not found."

SRC=$(ls -d /usr/lib/python3*/site-packages/configgen 2>/dev/null | head -n1)
[ -n "$SRC" ] || fail "Could not find the Batocera configgen folder."

# The generator below is written for the Batocera generator format.
# Stop instead of breaking anything if this Batocera looks different.
[ -f "$SRC/generators/importer.py" ] && grep -q "'sdlpop': (" "$SRC/generators/importer.py" \
    || fail "This Batocera version uses a different emulator format (importer.py). Nothing was changed."
SDLPOP_GEN="$SRC/generators/sdlpop/sdlpopGenerator.py"
[ -f "$SDLPOP_GEN" ] && grep -q "from \.\.\. import Command" "$SDLPOP_GEN" && grep -q "getHotkeysContext" "$SDLPOP_GEN" \
    || fail "This Batocera version uses a different emulator format (generators). Nothing was changed."

echo "Checking for the latest KytyPS5 build..."
RELEASE_JSON="$(mktemp /tmp/kyty-rel-XXXX.json)"
if ! curl -fsSL -H "Accept: application/vnd.github+json" "$RELEASES_API" -o "$RELEASE_JSON"; then
    rm -f "$RELEASE_JSON"
    fail "Could not reach GitHub. Check the internet connection."
fi

INFO="$(python3 - "$RELEASE_JSON" <<'PY'
import json, sys
try:
    rels = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
if not isinstance(rels, list):
    sys.exit(1)
rels = [r for r in rels if not r.get("draft")]
rels.sort(key=lambda r: r.get("published_at") or "", reverse=True)
for r in rels:
    for a in r.get("assets", []):
        if a.get("name", "").endswith("Linux-x86_64.tar.gz"):
            print(r["tag_name"])
            print(a["browser_download_url"])
            print(a["size"])
            print(a.get("digest") or "")
            sys.exit(0)
sys.exit(2)
PY
)"
rc=$?
rm -f "$RELEASE_JSON"
(( rc == 0 )) || fail "No KytyPS5 Linux build found on GitHub (or the GitHub API limit was reached, try again later)."

mapfile -t R <<< "$INFO"
TAG="${R[0]}"; URL="${R[1]}"; SIZE="${R[2]}"; DIGEST="${R[3]:-}"

INSTALLED=""
[[ -f "$VERSION_FILE" ]] && INSTALLED="$(head -n1 "$VERSION_FILE")"
FRESH=1
[[ -n "$INSTALLED" && -x "$KYTY_DIR/kyty_emulator" ]] && FRESH=0

echo "Latest build:    $TAG"
echo "Installed build: ${INSTALLED:-none}"
echo

if (( FRESH == 0 )) && [[ "$INSTALLED" == "$TAG" ]]; then
    echo "up to date"
    echo
    mkdir -p "$SELF_DIR/images"
    [[ -f "$SELF_DIR/images/$SELF_STEM.jpg" ]] || extract_payload POSTER "$SELF_DIR/images/$SELF_STEM.jpg"
    update_gamelist >> "$LOG" 2>&1
    wait_key
    exit 0
fi

echo "----------------------------------------------------------------------"
echo " WARNING: This is an unofficial system."
echo " Future Batocera updates may affect it."
if (( FRESH == 1 )); then
    echo
    echo " After the installation Batocera needs a REBOOT."
    echo " You will be asked before it reboots."
fi
echo "----------------------------------------------------------------------"
echo

if (( FRESH == 1 )); then
    QUESTION="Install KytyPS5 ($TAG)?"
else
    echo "Update found: $TAG"
    echo
    QUESTION="Install the update?"
fi

if ! ask_yes_no "$QUESTION"; then
    echo
    echo "Cancelled. Nothing was changed."
    echo
    wait_key
    exit 0
fi
echo

# ---------------------------------------------------------------------------
# 1. Download + install the KytyPS5 build
# ---------------------------------------------------------------------------
rm -rf "$WORK"
mkdir -p "$WORK/extract" || fail "Cannot create $WORK"

echo "Downloading KytyPS5 $TAG..."
curl -fL --retry 3 -o "$WORK/kyty.tar.gz" "$URL" || fail "Download failed."
GOT="$(stat -c %s "$WORK/kyty.tar.gz" 2>/dev/null || echo 0)"
[[ "$GOT" == "$SIZE" ]] || fail "The download is incomplete ($GOT of $SIZE bytes)."
echo

if [[ -n "$DIGEST" ]]; then
    EXPECTED=${DIGEST#sha256:}
    ACTUAL=$(sha256sum "$WORK/kyty.tar.gz" | cut -d' ' -f1)
    [[ "$EXPECTED" == "$ACTUAL" ]] || fail "Checksum mismatch. Not installing."
    echo "SHA-256 checksum OK."
else
    warn "No checksum available to verify the download."
fi

echo "Unpacking..."
tar -xzf "$WORK/kyty.tar.gz" -C "$WORK/extract" || fail "Unpacking failed."
EMU=$(find "$WORK/extract" -name kyty_emulator -type f | head -n1)
[ -n "$EMU" ] || fail "kyty_emulator not found inside the archive."
EMU_DIR=$(dirname "$EMU")

echo "Installing KytyPS5..."
if [[ -d "$KYTY_DIR" ]]; then
    rm -rf "$BACKUP_DIR"
    cp -a "$KYTY_DIR" "$BACKUP_DIR" || fail "Could not back up the previous version."
    echo "Previous version saved to: $BACKUP_DIR"
fi
mkdir -p "$KYTY_DIR"
# copy over the old files: your own settings in this folder are kept
cp -a "$EMU_DIR"/. "$KYTY_DIR"/ || fail "Could not copy KytyPS5 files to $KYTY_DIR."
for f in kyty_emulator kyty_launcher kyty_updater launcher; do
    [ -f "$KYTY_DIR/$f" ] && chmod +x "$KYTY_DIR/$f"
done
rm -rf "$WORK"
[ -x "$KYTY_DIR/kyty_emulator" ] || fail "$KYTY_DIR/kyty_emulator is missing or not executable."
echo "$TAG" > "$VERSION_FILE"
log "KytyPS5 installed to $KYTY_DIR"

# ---------------------------------------------------------------------------
# 2. Editable copy of configgen + bind mount
# ---------------------------------------------------------------------------
if [ ! -d "$CONFIGGEN_COPY" ]; then
    cp -r "$SRC" "$CONFIGGEN_COPY" || fail "Could not copy configgen."
    log "Copied configgen to $CONFIGGEN_COPY"
fi
[ -d "$CONFIGGEN_COPY/generators" ] || fail "$CONFIGGEN_COPY exists but looks broken (no generators folder)."

if ! grep -q " $SRC " /proc/mounts; then
    mount --bind "$CONFIGGEN_COPY" "$SRC" || fail "Bind mount failed."
    log "Bind-mounted $CONFIGGEN_COPY over $SRC"
else
    log "Bind mount already active."
fi

# ---------------------------------------------------------------------------
# 3. Generator
# ---------------------------------------------------------------------------
GEN_DIR="$CONFIGGEN_COPY/generators/ps5"
mkdir -p "$GEN_DIR"
touch "$GEN_DIR/__init__.py"
cat > "$GEN_DIR/ps5Generator.py" <<'PYEOF'
from __future__ import annotations

from typing import TYPE_CHECKING

from ... import Command
from ..Generator import Generator

if TYPE_CHECKING:
    from ...types import HotkeysContext

class Ps5Generator(Generator):
    def getHotkeysContext(self) -> HotkeysContext:
        return {"name": "ps5", "keys": {"exit": ["KEY_LEFTALT", "KEY_F4"]}}

    def generate(self, system, rom, playersControllers, metadata, guns, wheels, gameResolution):
        return Command.Command(array=["/userdata/system/add-ons/kytyps5/kyty.sh", str(rom)], env={})
PYEOF
log "Wrote generator."

# ---------------------------------------------------------------------------
# 4. Register the generator (key = emulator name "kyty")
# ---------------------------------------------------------------------------
IMPORTER="$CONFIGGEN_COPY/generators/importer.py"
if grep -q "'kyty': (" "$IMPORTER"; then
    log "Generator already registered."
else
    sed -i "/'sdlpop': (/i\    'kyty': ('ps5.ps5Generator', 'Ps5Generator')," "$IMPORTER"
    grep -q "'kyty': (" "$IMPORTER" || fail "Could not register the generator in importer.py."
    log "Registered generator in importer.py"
fi

# ---------------------------------------------------------------------------
# 5. batocera.conf (without this: "emulator missing")
# ---------------------------------------------------------------------------
set_conf ps5.emulator kyty
set_conf ps5.core kyty
set_conf ps5.bezel none
log "Set ps5.emulator / ps5.core / ps5.bezel=none in batocera.conf"

# ---------------------------------------------------------------------------
# 6. System definition
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$CFG")" "$ROM_DIR"
cat > "$CFG" <<'CFGEOF'
<?xml version="1.0" encoding="UTF-8"?>
<systemList>
  <system>
    <fullname>PlayStation 5</fullname>
    <name>ps5</name>
    <manufacturer>Sony</manufacturer>
    <release>2020</release>
    <hardware>console</hardware>
    <path>/userdata/roms/ps5</path>
    <extension>.elf .bin .self .json .ps5</extension>
    <command>emulatorlauncher %CONTROLLERSCONFIG% -system %SYSTEM% -rom %ROM% -gameinfoxml %GAMEINFOXML% -systemname %SYSTEMNAME%</command>
    <platform>ps5</platform>
    <theme>ps5</theme>
    <emulators><emulator name="kyty"><cores><core name="kyty" default="true" /></cores></emulator></emulators>
  </system>
</systemList>
CFGEOF
log "Wrote $CFG"

# ---------------------------------------------------------------------------
# 7. kyty.sh launch wrapper (games) and kyty-config.sh (settings)
# ---------------------------------------------------------------------------
EXTRA_FLAGS=""
grep -q AuthenticAMD /proc/cpuinfo && EXTRA_FLAGS=" --amd-cpu"

cat > "$KYTY_DIR/kyty.sh" <<'SHEOF'
#!/bin/bash
# Auto-detect the X display (it can be :0 or :1 depending on how X started)
export DISPLAY=:$(ls /tmp/.X11-unix | head -n1 | tr -dc 0-9).0
export QT_QPA_PLATFORM=xcb
KYTY_DIR=/userdata/system/add-ons/kytyps5
cd "$KYTY_DIR" || exit 1
TARGET="${@: -1}"
GAME_PATH="$TARGET"
if [ -d "$TARGET" ]; then
  if [ -f "$TARGET/eboot.bin" ]; then GAME_PATH="$TARGET/eboot.bin"
  elif [ -f "$TARGET/sce_module/eboot.bin" ]; then GAME_PATH="$TARGET/sce_module/eboot.bin"; fi
fi
unset WAYLAND_DISPLAY
export SDL_VIDEODRIVER=x11
# exec keeps Kyty in the foreground so emulatorlauncher waits for it
exec "$KYTY_DIR/kyty_emulator" --game "$GAME_PATH" --fullscreen__EXTRA_FLAGS__ > /userdata/system/logs/kyty.log 2>&1
SHEOF
sed -i "s|__EXTRA_FLAGS__|$EXTRA_FLAGS|" "$KYTY_DIR/kyty.sh"
chmod +x "$KYTY_DIR/kyty.sh"
log "Wrote $KYTY_DIR/kyty.sh"

cat > "$KYTY_DIR/kyty-config.sh" <<'SHEOF'
#!/bin/bash
# Opens the KytyPS5 settings (F1 file manager -> Applications -> KytyPS5)
export DISPLAY=:$(ls /tmp/.X11-unix | head -n1 | tr -dc 0-9).0
export QT_QPA_PLATFORM=xcb
unset WAYLAND_DISPLAY
KYTY_DIR=/userdata/system/add-ons/kytyps5
cd "$KYTY_DIR" || exit 1
APP="$KYTY_DIR/kyty_launcher"
[ -x "$APP" ] || APP="$KYTY_DIR/launcher"
exec "$APP" "$@" > /userdata/system/logs/kyty-launcher.log 2>&1
SHEOF
chmod +x "$KYTY_DIR/kyty-config.sh"

# Entry under "Applications" in the F1 file manager
mkdir -p "$(dirname "$DESKTOP")"
cat > "$DESKTOP" <<'DESKTOPEOF'
[Desktop Entry]
Type=Application
Name=KytyPS5
Comment=PS5 emulator settings
Exec=/userdata/system/add-ons/kytyps5/kyty-config.sh
Path=/userdata/system/add-ons/kytyps5
Terminal=false
Categories=Game;batocera.linux;
DESKTOPEOF
chmod +x "$DESKTOP"
log "Added KytyPS5 to F1 -> Applications"

# ---------------------------------------------------------------------------
# 8. Keep the bind mount across reboots
# ---------------------------------------------------------------------------
SERVICE_DIR=/userdata/system/services
SERVICE_FILE="$SERVICE_DIR/ps5_configgen"
if command -v batocera-services >/dev/null 2>&1; then
    mkdir -p "$SERVICE_DIR"
    cat > "$SERVICE_FILE" <<'SVCEOF'
#!/bin/bash
# PS5 (KytyPS5): re-mount the editable configgen copy over the read-only original
case "$1" in
  start)
    SRC=$(ls -d /usr/lib/python3*/site-packages/configgen)
    grep -q " $SRC " /proc/mounts || mount --bind /userdata/system/configgen "$SRC"
    ;;
  status)
    grep -q configgen /proc/mounts; exit $?
    ;;
esac
exit 0
SVCEOF
    chmod +x "$SERVICE_FILE"
    batocera-services enable ps5_configgen >/dev/null 2>&1
    if batocera-services list 2>/dev/null | grep -q "ps5_configgen"; then
        log "Enabled boot service: ps5_configgen"
    else
        warn "Could not confirm the ps5_configgen service is enabled."
    fi
else
    warn "batocera-services not found (older Batocera?). Relying on custom.sh only."
fi

# Fallback for older Batocera versions where custom.sh still runs directly
if grep -q "mount --bind /userdata/system/configgen" "$CUSTOM_SH" 2>/dev/null; then
    log "custom.sh already re-mounts configgen on boot."
else
    [ -f "$CUSTOM_SH" ] || echo '#!/bin/bash' > "$CUSTOM_SH"
    [ -n "$(tail -c1 "$CUSTOM_SH")" ] && echo >> "$CUSTOM_SH"
    echo 'SRC=$(ls -d /usr/lib/python3*/site-packages/configgen); grep -q " $SRC " /proc/mounts || mount --bind /userdata/system/configgen "$SRC"' >> "$CUSTOM_SH"
    log "Added fallback boot-time mount to $CUSTOM_SH"
fi
chmod +x "$CUSTOM_SH"

# Cover for this Ports entry
mkdir -p "$SELF_DIR/images"
extract_payload POSTER "$SELF_DIR/images/$SELF_STEM.jpg"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo
echo "======================================================================"
echo " KytyPS5 $TAG"
echo
echo " Place your games in:  $ROM_DIR"
echo " Settings: F1 file manager -> Applications -> KytyPS5"
echo " If a game exits right away, see: /userdata/system/logs/kyty.log"
echo "======================================================================"
echo

if (( FRESH == 0 )); then
    update_gamelist >> "$LOG" 2>&1
    echo "Update complete"
    echo
    wait_key
    exit 0
fi

echo "Installation complete"
echo
if ! ask_yes_no "Reboot now?"; then
    update_gamelist >> "$LOG" 2>&1
    echo
    echo "No reboot. Reboot Batocera later to finish the installation."
    echo
    wait_key
    exit 0
fi

# Reboot: stop EmulationStation first so it can't overwrite the Ports gamelist.
# Runs detached, because stopping EmulationStation also closes this window.
echo "Rebooting..."
declare -f update_gamelist > /tmp/kyty-gamelist.sh
FINISH="/tmp/kyty-finish.sh"
cat > "$FINISH" <<SH
#!/bin/bash
LOG="$LOG"
sleep 1
if [[ -x /etc/init.d/S31emulationstation ]]; then
    /etc/init.d/S31emulationstation stop >> "\$LOG" 2>&1
else
    killall -TERM emulationstation >> "\$LOG" 2>&1
fi
for i in \$(seq 1 30); do pgrep -x emulationstation >/dev/null || break; sleep 1; done
SELF_DIR="$SELF_DIR"; SELF_NAME="$SELF_NAME"; SELF_STEM="$SELF_STEM"
source /tmp/kyty-gamelist.sh
update_gamelist >> "\$LOG" 2>&1
sync
reboot
SH
chmod +x "$FINISH"
setsid nohup /bin/bash "$FINISH" >/dev/null 2>&1 < /dev/null &
sleep 1
exit 0

__POSTER_BEGIN__
@@POSTER@@
__POSTER_END__
