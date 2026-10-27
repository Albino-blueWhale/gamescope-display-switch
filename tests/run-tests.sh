#!/bin/bash
# Test suite for gamescope-display-switch. It builds fake /sys/class/drm trees and fake settings files
# in a temp folder, so it never touches the real machine.
# Usage: bash tests/run-tests.sh [path/to/gamescope-display-switch]
SCRIPT=${1:-"$(dirname "$0")/../bin/gamescope-display-switch"}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0

# Machine layouts: "card:vendor:device:port,port,...", first port of the built-in card is the built-in screen
declare -A LAYOUT=(
    [intel-nvidia]="card1:8086:9bc4:eDP-1,DP-1,HDMI-A-1 card0:10de:1f15:HDMI-A-3,DP-4"   # e.g. Acer Predator, RTX 2060
    [amd-amd]="card0:1002:1638:eDP-1,DP-1 card1:1002:73df:HDMI-A-1,DP-2"                  # AMD iGPU + Radeon dGPU
    [amd-nvidia]="card0:1002:1681:eDP-1,DP-1 card1:10de:2860:HDMI-A-1"                    # Ryzen iGPU + RTX
    [handheld]="card0:1002:15bf:DSI-1,DP-1"                                               # one GPU, DSI panel, USB-C out
    [old-laptop]="card0:8086:0166:LVDS-1,VGA-1,HDMI-A-1"                                  # LVDS panel, one GPU
    [desktop]="card0:10de:2684:HDMI-A-1,DP-1,DP-2"                                        # no built-in screen
)

setup() {  # setup "connected ports..." "VULKAN_ADAPTER" "OUTPUT_CONNECTOR" [layout]
    local layout=${4:-intel-nvidia} spec card v d ports p first
    rm -rf "$T/drm" "$T/home"; mkdir -p "$T/drm" "$T/home/.config/environment.d"
    for spec in ${LAYOUT[$layout]}; do
        IFS=: read -r card v d ports <<< "$spec"
        mkdir -p "$T/drm/$card/device"
        echo "0x$v" > "$T/drm/$card/device/vendor"; echo "0x$d" > "$T/drm/$card/device/device"
        first=1
        for p in ${ports//,/ }; do
            mkdir -p "$T/drm/$card-$p"
            if [[ $first -eq 1 && "$p" =~ ^(eDP|LVDS|DSI)- ]]; then echo connected; else echo disconnected; fi > "$T/drm/$card-$p/status"
            first=0
        done
    done
    for p in $1; do echo connected > "$T/drm/$p/status"; done
    [[ -n "$2" ]] && echo "VULKAN_ADAPTER=$2" > "$T/home/.config/environment.d/00-vulkan-device.conf"
    [[ -n "$3" ]] && echo "OUTPUT_CONNECTOR=$3" > "$T/home/.config/environment.d/10-gamescope-session.conf"
    return 0
}

run() { GDS_TEST=1 GDS_BOOT_WAIT_GPU=${WAIT_GPU:-0} GDS_BOOT_WAIT_DISPLAY=${WAIT:-0} HOME="$T/home" XDG_CONFIG_HOME= XDG_STATE_HOME= GDS_DRM_ROOT="$T/drm" bash "$SCRIPT" "$@" 2>&1; }

check() {  # check "name" "expected text in --dry-run output"
    out=$(run --dry-run)
    if [[ "$out" == *"$2"* ]]; then PASS=$((PASS+1)); echo "PASS  $1"
    else FAIL=$((FAIL+1)); echo "FAIL  $1"; echo "      expected: $2"; echo "$out" | sed 's/^/      | /'; fi
}

check_boot() {  # check_boot "name" "expected VULKAN_ADAPTER" "expected OUTPUT_CONNECTOR" (really writes the fake files)
    out=$(run --boot-check)
    local v o
    v=$(grep -oP '^VULKAN_ADAPTER=\K.*' "$T/home/.config/environment.d/00-vulkan-device.conf" 2>/dev/null)
    o=$(grep -oP '^OUTPUT_CONNECTOR=\K.*' "$T/home/.config/environment.d/10-gamescope-session.conf" 2>/dev/null)
    if [[ "$v" == "$2" && "$o" == "$3" ]]; then PASS=$((PASS+1)); echo "PASS  boot: $1"
    else FAIL=$((FAIL+1)); echo "FAIL  boot: $1"; echo "      expected: $2 / $3   got: ${v:-none} / ${o:-none}"; echo "$out" | sed 's/^/      | /'; fi
}

echo "── Switching (Intel + Nvidia laptop) ──"
setup "" 8086:9bc4 "eDP-1,*"
check "built-in, nothing plugged in -> stay"                 "Staying on the built-in screen"
setup "card0-HDMI-A-3" 8086:9bc4 "eDP-1,*"
check "built-in, TV on HDMI -> external (Nvidia)"            "laptop -> external (VULKAN_ADAPTER=10de:1f15, OUTPUT_CONNECTOR=HDMI-A-3,*)"
setup "card0-HDMI-A-3" 10de:1f15 "HDMI-A-3,*"
check "on HDMI display -> back to built-in"                  "external -> laptop (VULKAN_ADAPTER=8086:9bc4, OUTPUT_CONNECTOR=eDP-1,*)"
setup "" 10de:1f15 "HDMI-A-3,*"
check "on HDMI display, it got unplugged -> built-in"        "external -> laptop"
setup "card1-DP-1" 8086:9bc4 "eDP-1,*"
check "monitor on an iGPU-wired port -> external"            "laptop -> external (VULKAN_ADAPTER=8086:9bc4, OUTPUT_CONNECTOR=DP-1,*)"
setup "card1-DP-1" 8086:9bc4 "DP-1,*"
check "on iGPU-wired monitor (same GPU) -> built-in"         "external -> laptop (VULKAN_ADAPTER=8086:9bc4, OUTPUT_CONNECTOR=eDP-1,*)"
setup "card1-HDMI-A-1 card0-DP-4" 8086:9bc4 "eDP-1,*"
check "two monitors -> picks the dedicated-GPU one"          "OUTPUT_CONNECTOR=DP-4,*"
setup "card0-HDMI-A-3" "" ""
check "settings deleted (fix-reset-steam), TV in -> external" "unknown -> external"
setup "" "" ""
check "settings deleted, nothing plugged in -> repair"       "unknown -> laptop"
setup "card0-HDMI-A-3" 10de:1f15 "c0ad8852-0348-4a82-b0e9-c0de08ed9ffa"
check "stray ID in OUTPUT_CONNECTOR -> uses GPU"             "external -> laptop"

echo "── Other hardware ──"
setup "card1-HDMI-A-1" 1002:1638 "eDP-1,*" amd-amd
check "AMD + AMD: TV on dGPU HDMI -> external on Radeon"     "laptop -> external (VULKAN_ADAPTER=1002:73df, OUTPUT_CONNECTOR=HDMI-A-1,*)"
setup "card0-DP-1 card1-HDMI-A-1" 1002:1638 "eDP-1,*" amd-amd
check "AMD + AMD: two monitors -> picks the dGPU one"        "OUTPUT_CONNECTOR=HDMI-A-1,*"
setup "card1-HDMI-A-1" 1002:1681 "eDP-1,*" amd-nvidia
check "AMD + Nvidia: TV on HDMI -> external on RTX"          "laptop -> external (VULKAN_ADAPTER=10de:2860, OUTPUT_CONNECTOR=HDMI-A-1,*)"
setup "card0-DP-1" 1002:15bf "DSI-1,*" handheld
check "handheld: USB-C dock -> external"                     "laptop -> external (VULKAN_ADAPTER=1002:15bf, OUTPUT_CONNECTOR=DP-1,*)"
setup "card0-DP-1" 1002:15bf "DP-1,*" handheld
check "handheld: on dock -> back to DSI panel"               "external -> laptop (VULKAN_ADAPTER=1002:15bf, OUTPUT_CONNECTOR=DSI-1,*)"
setup "card0-HDMI-A-1" 8086:0166 "LVDS-1,*" old-laptop
check "old laptop with LVDS panel -> external"               "OUTPUT_CONNECTOR=HDMI-A-1,*"
setup "card0-DP-1" 10de:2684 "" desktop
check "desktop (no built-in screen) -> explains, no change"  "No built-in screen found"

echo "── Boot check ──"
setup "card0-HDMI-A-3" 10de:1f15 "HDMI-A-3,*"
check_boot "set to HDMI, plugged in -> unchanged"              10de:1f15 "HDMI-A-3,*"
setup "" 10de:1f15 "HDMI-A-3,*"
check_boot "set to HDMI, nothing plugged in -> built-in"        8086:9bc4 "eDP-1,*"
setup "card1-DP-1" 10de:1f15 "HDMI-A-3,*"
check_boot "set to HDMI, a different monitor in -> built-in"    8086:9bc4 "eDP-1,*"
setup "card0-HDMI-A-3" 8086:9bc4 "eDP-1,*"
check_boot "set to built-in, TV in -> unchanged (no auto-switch)" 8086:9bc4 "eDP-1,*"
setup "" "" "eDP-1,*"
check_boot "fix-reset-steam deleted GPU, built-in -> repaired"  8086:9bc4 "eDP-1,*"
setup "card0-HDMI-A-3" "" "HDMI-A-3,*"
check_boot "fix-reset-steam deleted GPU, HDMI in -> repaired"   10de:1f15 "HDMI-A-3,*"
setup "card0-HDMI-A-3" "" ""
check_boot "both settings missing -> built-in"                  8086:9bc4 "eDP-1,*"
setup "card0-HDMI-A-3" 10de:1f15 "c0ad8852-0348-4a82-b0e9-c0de08ed9ffa"
check_boot "stray ID, Nvidia, HDMI in -> kept, cleaned up"      10de:1f15 "HDMI-A-3,*"
setup "" 10de:1f15 "c0ad8852-0348-4a82-b0e9-c0de08ed9ffa"
check_boot "stray ID, Nvidia, nothing in -> built-in"           8086:9bc4 "eDP-1,*"
setup "" 10de:1f15 "HDMI-A-3,*"
( sleep 2; echo connected > "$T/drm/card0-HDMI-A-3/status" ) &
WAIT=5 check_boot "slow display reports in after 2s -> unchanged" 10de:1f15 "HDMI-A-3,*"
wait
setup "card0-HDMI-A-3" 10de:1f15 "HDMI-A-3,*"
mv "$T/drm/card0-HDMI-A-3" "$T/drm/.late-HDMI"   # dGPU driver not loaded yet
( sleep 2; mv "$T/drm/.late-HDMI" "$T/drm/card0-HDMI-A-3" ) &
WAIT_GPU=5 check_boot "dGPU driver loads 2s late, HDMI in -> unchanged" 10de:1f15 "HDMI-A-3,*"
wait
setup "" 10de:2684 "HDMI-A-1,*" desktop
check_boot "desktop -> leaves settings alone"                   10de:2684 "HDMI-A-1,*"

check_json() {  # check_json "name" "python expression on the parsed output j"
    out=$(run --json)
    if python3 -c 'import json,sys; j=json.loads(sys.argv[1]); sys.exit(0 if eval(sys.argv[2]) else 1)' "$out" "$2" 2>/dev/null
    then PASS=$((PASS+1)); echo "PASS  json: $1"
    else FAIL=$((FAIL+1)); echo "FAIL  json: $1"; echo "      expected: $2"; echo "$out" | sed 's/^/      | /'; fi
}

echo "── JSON status ──"
setup "card0-HDMI-A-3" 8086:9bc4 "eDP-1,*"
check_json "built-in, TV in -> next is external" \
    "j['current']=='laptop' and j['next']=='external' and j['external']['port']=='HDMI-A-3' and j['external']['gpu']=='10de:1f15' and j['builtin']['port']=='eDP-1' and j['game_mode_running'] is False"
setup "" 8086:9bc4 "eDP-1,*"
check_json "nothing plugged in -> next is none" "j['external'] is None and j['connected_externals']==[] and j['next']=='none'"
setup "card1-HDMI-A-1 card0-DP-4" 10de:1f15 "DP-4,*"
check_json "two monitors, on DP-4 -> next is laptop" "j['current']=='external' and j['next']=='laptop' and sorted(j['connected_externals'])==['DP-4','HDMI-A-1']"
setup "" "" ""
check_json "settings deleted -> unknown, null output" "j['current']=='unknown' and j['output'] is None and j['next']=='laptop'"
setup "card0-HDMI-A-1" 10de:2684 "HDMI-A-1,*" desktop
check_json "desktop -> error" "j['error']=='no_builtin_screen'"

echo "== $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
