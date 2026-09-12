#!/usr/bin/env bash
# Usage: run_arena.sh <tag> <seconds> [extra godot user args...]
set -u
P="$(cd "$(dirname "$0")" && pwd)"
TAG="$1"; SECS="$2"; shift 2
OUT="$P/run_${TAG}"
mkdir -p "$OUT"
# The package root is this script's own grandparent. It used to be the hard
# path to the asset hub, which meant a perf run launched from ANY worktree
# silently measured `main` instead of the branch under test.
cd "$P/../.."

# GPU sampler: 1 Hz
nvidia-smi --query-gpu=timestamp,utilization.gpu,utilization.memory,clocks.sm,clocks.mem,power.draw,memory.used \
  --format=csv,noheader,nounits -l 1 > "$OUT/nvidia.csv" 2>/dev/null &
NVPID=$!

godot --path . res://assets/scenes/GPUArena.tscn -- \
  --combat-autostart --perf-debug --quit-after="$SECS" "$@" \
  > "$OUT/godot.log" 2>&1 &
GPID=$!

# CPU sampler: per-thread for the godot process, 1 Hz
( sleep 3; top -b -H -d 1 -n "$SECS" -p "$GPID" > "$OUT/top.txt" 2>/dev/null ) &
TPID=$!

wait $GPID; RC=$?
kill $NVPID $TPID 2>/dev/null
echo "rc=$RC log=$OUT/godot.log"
