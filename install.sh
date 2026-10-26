#!/bin/bash
# Installer for gamescope-display-switch. Run it as your normal user (not with sudo);
# it asks for your password only for the parts that need it.
#
#   ./install.sh                 interactive
#   ./install.sh --hotkey        also install the firmware hotkey add-on (e.g. Acer Turbo key)
#   ./install.sh --no-hotkey     skip the hotkey question
#   ./install.sh --no-steam      don't add a "Switch Display" shortcut to Steam
set -euo pipefail

SRC=$(cd "$(dirname "$0")" && pwd)
BIN="$HOME/.local/bin"
SHARE="$HOME/.local/share/gamescope-display-switch"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/gamescope-display-switch"
UNIT_DIR=/etc/systemd/system
USER_NAME=$(id -un)

HOTKEY=ask STEAM=yes
for arg in "$@"; do
    case "$arg" in
        --hotkey)    HOTKEY=yes ;;
        --no-hotkey) HOTKEY=no ;;
        --no-steam)  STEAM=no ;;
        *) echo "Unknown option: $arg"; exit 2 ;;
    esac
done

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
ask()  { local reply; read -r -p "$1 [y/N] " reply; [[ "$reply" =~ ^[Yy] ]]; }

[[ $EUID -eq 0 ]] && { echo "Run this as your normal user, not with sudo."; exit 1; }
command -v systemctl >/dev/null || { echo "This needs systemd."; exit 1; }

say "Checking this machine"
"$SRC/bin/gamescope-display-switch" --status || {
    echo "No built-in screen was found, so there is nothing to switch on this machine."; exit 1; }
if ! command -v gamescope-session-plus >/dev/null && ! ls /usr/share/gamescope-session-plus >/dev/null 2>&1; then
    echo "Warning: gamescope-session-plus wasn't found. This tool is built for Game Mode on Bazzite,"
    echo "ChimeraOS and similar; it may not work on other setups."
fi

say "Backing up your current display settings"
BACKUP="$STATE/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
for f in 00-vulkan-device.conf 10-gamescope-session.conf; do
    if [[ -f "$CONFIG_HOME/environment.d/$f" ]]; then cp -v "$CONFIG_HOME/environment.d/$f" "$BACKUP/"; fi
done
echo "Backup folder: $BACKUP"

say "Installing the switch"
install -Dm755 "$SRC/bin/gamescope-display-switch" "$BIN/gamescope-display-switch"
echo "Installed $BIN/gamescope-display-switch"

# Game Mode restarts: prefer the sudo-free way (SDDM Relogin=true, as on Bazzite)
if grep -rhsE '^\s*Relogin\s*=\s*true' /etc/sddm.conf /etc/sddm.conf.d/ /usr/lib/sddm/sddm.conf.d/ >/dev/null; then
    echo "Game Mode restarts: no sudo needed (your login manager logs back in automatically)."
    NEED_SUDOERS=no
else
    echo "Game Mode restarts: your login manager doesn't log back in automatically, so switching"
    echo "needs permission to restart it. I'll add a sudo rule for just that one command."
    NEED_SUDOERS=yes
fi

if [[ "$HOTKEY" == ask ]]; then
    echo
    if ask "Install the hotkey add-on (switch with a firmware key such as Acer's Turbo key)?"; then HOTKEY=yes; else HOTKEY=no; fi
fi
if [[ "$HOTKEY" == yes ]]; then
    mkdir -p "$SHARE/hotkey"
    install -m644 "$SRC/extras/hotkey/acpi_events.py" "$SHARE/hotkey/"
    install -m755 "$SRC/extras/hotkey/gamescope-display-switch-hotkey" "$SRC/extras/hotkey/find-hotkey" "$SHARE/hotkey/"
    ln -sf "$SHARE/hotkey/find-hotkey" "$BIN/gamescope-display-switch-find-hotkey"
    if [[ ! -f "$CONFIG_HOME/gamescope-display-switch/hotkey.conf" ]]; then
        say "Finding your hotkey"
        if "$SHARE/hotkey/find-hotkey" | tee "$STATE/find-hotkey.txt"; then
            CLASS=$(grep -oP '^\s*EVENT_CLASS=\K\S+' "$STATE/find-hotkey.txt" | head -1 || true)
            TYPE=$(grep -oP '^\s*EVENT_TYPE=\K\S+' "$STATE/find-hotkey.txt" | head -1 || true)
            if [[ -n "$CLASS" && -n "$TYPE" ]] && ask "Use class=$CLASS type=$TYPE as your hotkey?"; then
                mkdir -p "$CONFIG_HOME/gamescope-display-switch"
                printf 'EVENT_CLASS=%s\nEVENT_TYPE=%s\n' "$CLASS" "$TYPE" > "$CONFIG_HOME/gamescope-display-switch/hotkey.conf"
            fi
        fi
        [[ -f "$CONFIG_HOME/gamescope-display-switch/hotkey.conf" ]] || {
            echo "No hotkey set. Run gamescope-display-switch-find-hotkey later, then rerun this installer."; HOTKEY=no; }
    fi
fi

say "Setting up system services (needs your password)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
sed -e "s|@USER@|$USER_NAME|g" -e "s|@BIN@|$BIN|g" "$SRC/systemd/gamescope-display-switch-bootcheck.service.in" \
    > "$TMP/gamescope-display-switch-bootcheck.service"
sudo install -m644 "$TMP/gamescope-display-switch-bootcheck.service" "$UNIT_DIR/"
if [[ "$HOTKEY" == yes ]]; then
    sed -e "s|@USER@|$USER_NAME|g" -e "s|@SHARE@|$SHARE|g" -e "s|@BIN@|$BIN|g" \
        "$SRC/systemd/gamescope-display-switch-hotkey.service.in" > "$TMP/gamescope-display-switch-hotkey.service"
    sudo install -m644 "$TMP/gamescope-display-switch-hotkey.service" "$UNIT_DIR/"
fi
command -v restorecon >/dev/null && sudo restorecon "$UNIT_DIR"/gamescope-display-switch-*.service 2>/dev/null || true
if [[ "$NEED_SUDOERS" == yes ]]; then
    echo "$USER_NAME ALL=(root) NOPASSWD: /usr/bin/systemctl restart display-manager" > "$TMP/sudoers"
    sudo visudo -cf "$TMP/sudoers" >/dev/null && sudo install -m440 "$TMP/sudoers" /etc/sudoers.d/gamescope-display-switch
    echo "Added /etc/sudoers.d/gamescope-display-switch (only allows: systemctl restart display-manager)"
fi
sudo systemctl daemon-reload
sudo systemctl enable gamescope-display-switch-bootcheck.service
echo "Boot check enabled: Game Mode won't start on a display that isn't connected."
if [[ "$HOTKEY" == yes ]]; then
    sudo systemctl enable --now gamescope-display-switch-hotkey.service
    echo "Hotkey listener running. Logs: journalctl -u gamescope-display-switch-hotkey"
fi

if [[ "$STEAM" == yes ]] && command -v steamos-add-to-steam >/dev/null; then
    say "Adding \"Switch Display\" to Steam"
    mkdir -p "$SHARE/steam"
    printf '#!/bin/bash\nexec "%s/gamescope-display-switch"\n' "$BIN" > "$SHARE/steam/Switch Display"
    chmod +x "$SHARE/steam/Switch Display"
    steamos-add-to-steam "$SHARE/steam/Switch Display" && echo "Added. It shows up under Non-Steam in your library." \
        || echo "Couldn't add it automatically. Add \"$SHARE/steam/Switch Display\" as a non-Steam game."
fi

say "Done"
if [[ "$HOTKEY" == yes ]]; then
    echo "Switch from Game Mode with the \"Switch Display\" shortcut or your hotkey."
else
    echo "Switch from Game Mode with the \"Switch Display\" shortcut."
fi
echo "Check the setup anytime with: gamescope-display-switch --status"
