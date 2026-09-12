#!/usr/bin/env bash
set -u
P="$(cd "$(dirname "$0")" && pwd)"
restore () { hyprctl keyword misc:render_unfocused_fps 60 >/dev/null 2>&1; echo "restored: $(hyprctl getoption misc:render_unfocused_fps 2>/dev/null | head -1)"; }
trap restore EXIT INT TERM
# The package root is this script's own grandparent. It used to be the hard
# path to the asset hub, which meant a perf run launched from ANY worktree
# silently measured `main` instead of the branch under test.
cd "$P/../.."
hyprctl keyword misc:render_unfocused_fps 144 >/dev/null 2>&1
echo "cap lifted: $(hyprctl getoption misc:render_unfocused_fps 2>/dev/null | head -1)"
run () {
  local NAME="$1" SECS="$2"; shift 2
  local OUT="$P/run_r13_$NAME"; mkdir -p "$OUT"
  nvidia-smi --query-gpu=utilization.gpu,power.draw --format=csv,noheader,nounits -l 1 > "$OUT/nvidia.csv" 2>/dev/null &
  local NV=$!
  cat /proc/loadavg > "$OUT/loadavg.start"
  godot "$@" --path . res://assets/scenes/GPUArena.tscn -- \
    --combat-autostart --perf-debug --combat-seed=424242 --quit-after="$SECS" > "$OUT/godot.log" 2>&1
  kill $NV 2>/dev/null
  echo "--- $NAME done ---"
}
run x11_vsync    60 --display-driver x11
run wl_vsync     60 --display-driver wayland
run wl_novsync   60 --display-driver wayland --disable-vsync
