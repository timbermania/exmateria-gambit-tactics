#!/bin/bash
# Smoke test: open each standalone scene briefly to exercise _ready() code paths.
# Used with tombstone tracing to mark more functions as "called".
#
# Each scene runs for a short timeout then gets killed. This exercises
# initialization, autoload setup, UI building, and data loading — where
# most unique function calls happen.
#
# Usage: bash tests/run_scene_smoke_tests.sh

GODOT="${GODOT:-godot}"

# The engine-fold compositor is 4.8-fork-only; stock 4.7 renders folded effects
# blank. Fail loudly rather than smoke-test scenes on the wrong binary.
GODOT_VER="$("$GODOT" --version 2>/dev/null)"
if [[ "$GODOT_VER" != *"4.8.dev.custom_build"* ]]; then
    echo "ABORT: '$GODOT' is '$GODOT_VER', not the 4.8 compositor fork (expected 4.8.dev.custom_build)."
    echo "       Point \$GODOT at the fork or symlink /usr/local/bin/godot -> the fork build."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

# Seconds to let each scene run before killing it
SMOKE_TIMEOUT=15

# Scenes to smoke-test (ordered by expected value for tombstone coverage)
SCENES=(
    # Main game scene — roster loading, strategy phase, debug panels, combat UI
    "GPUArena|res://assets/scenes/GPUArena.tscn"
    # Tool scenes — each exercises unique code paths
    "EffectViewer|res://assets/scenes/EffectViewer.tscn"
    "ProgressionTester|res://assets/scenes/ProgressionTester.tscn"
    # The sprite rig's exerciser SHIPS INSIDE THE ADDON (#744, ADR-0217 dec. 4/10):
    # an addon whose exerciser lives in the host cannot be exercised where the host
    # is absent. This is the only entry here that is not under `assets/scenes/`.
    "SequenceViewer|res://addons/exmateria_sprite_rig/viewer/SequenceViewer.tscn"
    "ProjectileTester|res://assets/scenes/ProjectileTester.tscn"
    "CombatUITest|res://assets/scenes/CombatUITest.tscn"
)

TOTAL=${#SCENES[@]}

echo "======================================"
echo "  Scene Smoke Tests (tombstone coverage)"
echo "  Opening $TOTAL scenes for ${SMOKE_TIMEOUT}s each"
echo "======================================"
echo ""

SUMMARY=""
OPENED=0
ERRORED=0

for i in "${!SCENES[@]}"; do
    IFS='|' read -r NAME SCENE <<< "${SCENES[$i]}"
    NUM=$((i + 1))
    LOG="$LOG_DIR/smoke_${NAME}.log"

    echo "[$NUM/$TOTAL] Opening $NAME for ${SMOKE_TIMEOUT}s..."

    # Run scene with timeout — it will be killed after SMOKE_TIMEOUT seconds
    (cd "$PROJECT_DIR" && timeout "$SMOKE_TIMEOUT" "$GODOT" --path . "$SCENE") 2>&1 | tee "$LOG"
    EXIT_CODE=${PIPESTATUS[0]}

    # 124 = timeout killed it (expected), 0 = scene quit on its own (also fine)
    if [ $EXIT_CODE -eq 124 ] || [ $EXIT_CODE -eq 0 ]; then
        RESULT="OK"
        OPENED=$((OPENED + 1))
    else
        RESULT="ERROR (exit $EXIT_CODE)"
        ERRORED=$((ERRORED + 1))
    fi

    SUMMARY="$SUMMARY\n  [$RESULT] $NAME"
    echo "  -> $RESULT"
    echo ""
done

echo "======================================"
echo "  SMOKE TEST SUMMARY"
echo "======================================"
echo -e "$SUMMARY"
echo ""
echo "  OPENED: $OPENED / $TOTAL"
echo "  ERRORS: $ERRORED"
echo "======================================"
