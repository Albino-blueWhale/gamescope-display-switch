# gamescope-display-switch

Switch **Game Mode** (gamescope-session-plus, as on Bazzite, ChimeraOS and similar) between a
laptop's built-in screen and an external display (a TV, projector or monitor) with one press,
from the couch, with a controller.

Built for **hybrid-GPU laptops**, where the HDMI port is wired to the dedicated GPU and the built-in
screen to the integrated one. On those machines Game Mode doesn't follow the cable on its own,
`xrandr` and `kscreen-doctor` don't work inside Game Mode, and Bazzite's `export-gpu` only asks
interactively.

## What it does

| You're on | External display | Press "Switch Display" |
|---|---|---|
| Built-in screen | Plugged in | Game Mode restarts on the external display |
| External display | (any) | Game Mode restarts on the built-in screen |
| Built-in screen | Nothing plugged in | Nothing: no restart into a black screen |

- **Any display, any port:** it finds the connected display and the GPU wired to that port by
  itself. Nothing is hard-coded. With several displays plugged in, it prefers one on the
  dedicated GPU, since games run on the GPU that drives the screen.
- **Knows what's really on screen:** it asks the running Game Mode which screen it uses, rather
  than trusting the settings files, so switching never goes the wrong way.
- **Boot safety net:** if the saved display isn't connected at boot (you left it set to a friend's
  TV), Game Mode starts on the built-in screen instead of a black one. It also repairs the GPU
  setting that `ujust fix-reset-steam` deletes, which otherwise stops Game Mode from starting.
- **No sudo needed** on Bazzite: it restarts just the Game Mode session, and the login manager
  logs straight back in.
- **Optional hotkey add-on:** switch with a laptop key that only sends a firmware event, such as
  Acer's Turbo / PredatorSense key. It includes a tool that finds your key's event.

## Install

```bash
git clone https://github.com/Albino-blueWhale/gamescope-display-switch.git
cd gamescope-display-switch
./install.sh
```

Run it as your normal user. It asks for your password only to install the boot-check service
(and the hotkey service, if you choose it). It adds a **Switch Display** shortcut to your Steam
library, which you can launch from Game Mode.

To check what it sees:

```bash
gamescope-display-switch --status
```

```
Built-in screen: eDP-1 on card1 (GPU 8086:9bc4)
External:        HDMI-A-3 on card0 (GPU 10de:1f15)
Now using:       laptop (output eDP-1,*, GPU 8086:9bc4, from running Game Mode)
```

`--dry-run` shows what a switch would do without changing anything. `--json` prints the status
as JSON, for front ends.

## Decky plugin

Prefer a menu in Game Mode? [Display Switch](https://github.com/Albino-blueWhale/decky-display-switch)
is a Decky Loader plugin with this tool built in: status, a Switch button and the boot safety net,
in the Quick Access menu. It needs no separate install.

## Uninstall

```bash
./uninstall.sh
```

## How it works

Every time Game Mode starts, it reads `~/.config/environment.d/*.conf` and passes two settings to gamescope:

| Setting | gamescope option | Meaning |
|---|---|---|
| `VULKAN_ADAPTER` | `--prefer-vk-device` | The GPU that renders **and** drives the screen |
| `OUTPUT_CONNECTOR` | `--prefer-output` | The port to show the picture on |

On a hybrid laptop each port belongs to one GPU, so both have to change together. The switch
works out the right pair from `/sys/class/drm`, writes them (to the same files Bazzite's
`export-gpu` and docs use), and restarts the Game Mode session.

**Restarts:** if SDDM has `Relogin=true` (Bazzite does), stopping the `gamescope-session-plus@…`
user unit is enough, and SDDM logs back in at once. Otherwise the installer adds a sudo rule for
just `systemctl restart display-manager`. To force one method, set
`RESTART_METHOD=session` or `RESTART_METHOD=display-manager` in
`~/.config/gamescope-display-switch/config`.

**Logs:** `~/.local/state/gamescope-display-switch/log`, plus `journalctl -u gamescope-display-switch-bootcheck`.

## Hotkey add-on

Some laptop keys (Acer's Turbo key, for example) don't send a key press at all. The firmware
raises a WMI event, which the kernel broadcasts on its `acpi_event` netlink channel. Any user can
listen there, so no root is needed. The installer runs `find-hotkey`: you press the key a few
times and it saves the event to `~/.config/gamescope-display-switch/hotkey.conf`:

```
EVENT_CLASS=wmi
EVENT_TYPE=0xbc
```

The listener only acts while Game Mode is running (in Desktop Mode a restart would close your
apps), and ignores presses for 15 seconds after a switch.

## Tested on

| Laptop | GPUs | Result |
|---|---|---|
| Acer Predator PH317-54 | Intel UHD + Nvidia RTX 2060 | ✅ Switch, boot check and Turbo key (`wmi 0xbc`) |

The test suite (`bash tests/run-tests.sh`) also covers AMD + AMD, AMD + Nvidia, handhelds with a
DSI panel, LVDS laptops and desktops, using simulated hardware. **Reports from real machines are
very welcome:** please open an issue with your laptop model and the output of
`gamescope-display-switch --status`.

## Known limits

- Game Mode briefly restarts on every switch (a few seconds). That's how gamescope picks a GPU.
- With the built-in screen chosen, games run on the integrated GPU. On a laptop that's expected.
- Laptops with a **MUX switch** in dedicated-GPU-only mode have a single GPU, and the switch
  simply changes the port.

## License

MIT
