#!/bin/bash
# Run the `Audio`-binding test scenes that `tests/run_all_tests.sh` does NOT list.
#
# #401 found 21 of the 39 test files binding an ADR-0153 dec. 2 moving symbol or
# `addons/exmateria_sound/` are absent from that runner's TESTS array — including
# SpuClippingMetricsTest and FedsPairEditorTest, which #400 names as prior art.
# A test nobody runs cannot be diffed after the move, which is the one thing the
# pre-move baseline is for. So they are run here, separately and on the record,
# rather than written down as 21 unknowns.
#
# Deliberately the SAME per-test invocation and 360 s timeout as run_all_tests.sh,
# and the SAME `[i/n] Running X...` / `  -> RESULT` output shape, so
# tools/freeze_test_baseline.py reads both logs with one parser. Sequential,
# never parallel, 4.8 fork only.
#
# Usage: bash tools/run_unlisted_audio_binders.sh

GODOT="${GODOT:-godot}"
GODOT_VER="$("$GODOT" --version 2>/dev/null)"
if [[ "$GODOT_VER" != *"4.8.dev.custom_build"* ]]; then
    echo "ABORT: '$GODOT' is '$GODOT_VER', not the 4.8 compositor fork."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_DIR/tests/logs"
mkdir -p "$LOG_DIR"

# The ONE verdict reader (#451, map #450). Sourced, not re-implemented — this
# runner and tools/run_unlisted_audio_binders.sh both feed the frozen register,
# so they must score a log identically by construction.
source "$PROJECT_DIR/tests/lib/verdict.sh"

# Derived, not a hand-kept list — and derived by the SAME code the register uses.
# This block used to inline its own copy of both the TESTS-array read and the
# binder grep, so "which tests are the subset" had two definitions: the one
# freeze_test_baseline.py writes into docs/TEST-BASELINE-E2.tsv, and the one this
# runner actually runs. That pairing is the only thing the `not-run` state is good
# for, and two copies of it is exactly what it cannot afford.
mapfile -t TESTS < <(cd "$PROJECT_DIR" && uv run python tools/_runner_tests.py --unlisted)

TOTAL=${#TESTS[@]}
echo "======================================"
echo "  Unlisted Audio-binder scenes"
echo "  Running $TOTAL scenes"
echo "======================================"
echo ""

for i in "${!TESTS[@]}"; do
    TEST="${TESTS[$i]}"
    NUM=$((i + 1))
    LOG="$LOG_DIR/${TEST}.log"
    echo "[$NUM/$TOTAL] Running $TEST..."
    (cd "$PROJECT_DIR" && timeout 360 "$GODOT" --path . "res://tests/${TEST}.tscn") 2>&1 | tee "$LOG"
    EXIT_CODE=${PIPESTATUS[0]}
    # Same reader as run_all_tests.sh, by construction (#451). This block used to
    # be a byte-identical copy of that one, and the frozen register merges the
    # stdout of BOTH runners — two copies of the rule is a drift the register
    # could not have detected.
    RESULT="$(test_verdict "$LOG" "$EXIT_CODE")"
    echo "  -> $RESULT"
    echo ""
done
