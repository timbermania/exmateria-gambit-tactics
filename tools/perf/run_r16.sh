#!/usr/bin/env bash
set -u
P="$(cd "$(dirname "$0")" && pwd)"
trap 'hyprctl keyword misc:render_unfocused_fps 60 >/dev/null 2>&1' EXIT
# The package root is this script's own grandparent. It used to be the hard
# path to the asset hub, which meant a perf run launched from ANY worktree
# silently measured `main` instead of the branch under test.
cd "$P/../.."
hyprctl keyword misc:render_unfocused_fps 144 >/dev/null 2>&1
run () {
  local NAME="$1" TS="$2"
  local OUT="$P/run_r16_$NAME"; mkdir -p "$OUT"
  godot --print-fps --disable-vsync --path . res://assets/scenes/GPUArena.tscn -- \
    --combat-autostart --perf-debug --combat-seed=424242 --time-scale=$TS --quit-after=45 \
    > "$OUT/godot.log" 2>&1 &
  local GP=$!
  sleep 15; hyprctl dispatch sendshortcut ",F3,class:godot-standalone" >/dev/null 2>&1
  wait $GP
  echo "--- $NAME (time-scale $TS) done ---"
}
run ts1 1.0
run ts2 2.0
