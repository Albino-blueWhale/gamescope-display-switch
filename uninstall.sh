#!/bin/bash
# Removes gamescope-display-switch. Run as your normal user.
# Your current display settings (~/.config/environment.d) are left as they are: they're valid
# settings Game Mode keeps using. Backups from install time stay in ~/.local/state/gamescope-display-switch.
set -uo pipefail

BIN="$HOME/.local/bin"
SHARE="$HOME/.local/share/gamescope-display-switch"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

[[ $EUID -eq 0 ]] && { echo "Run this as your normal user, not with sudo."; exit 1; }

echo "Removing system services (needs your password)"
for unit in gamescope-display-switch-hotkey.service gamescope-display-switch-bootcheck.service; do
    if [[ -f "/etc/systemd/system/$unit" ]]; then
        sudo systemctl disable --now "$unit"
        sudo rm -v "/etc/systemd/system/$unit"
    fi
done
[[ -f /etc/sudoers.d/gamescope-display-switch ]] && sudo rm -v /etc/sudoers.d/gamescope-display-switch
sudo systemctl daemon-reload

echo "Removing files"
rm -fv "$BIN/gamescope-display-switch" "$BIN/gamescope-display-switch-find-hotkey"
rm -rfv "$SHARE"
rm -rfv "$CONFIG_HOME/gamescope-display-switch"

echo
echo "Done. If you added the \"Switch Display\" shortcut to Steam, remove it from your library."
echo "Install-time backups of your display settings: ${XDG_STATE_HOME:-$HOME/.local/state}/gamescope-display-switch/"
