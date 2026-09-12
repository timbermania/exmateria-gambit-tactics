#!/bin/bash
# Tombstone coverage suite: run all unit tests + scene smoke tests.
#
# Use this before dead code cleaning to maximize function call coverage.
# Workflow:
#   1. Instrument: uv run python tools/instrument_functions.py
#   2. Run this:   bash tests/run_tombstone_tests.sh
#   3. Report:     uv run python tools/instrument_functions.py --report
#   4. Delete:     uv run python tools/delete_dead_code.py --dry-run
#
# Usage: bash tests/run_tombstone_tests.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo "  Tombstone Coverage Suite"
echo "  Unit tests + Scene smoke tests"
echo "============================================"
echo ""

# Phase 1: Unit tests
echo ">>> Phase 1: Unit tests"
echo ""
bash "$SCRIPT_DIR/run_all_tests.sh"
UNIT_EXIT=$?
echo ""

# Phase 2: Scene smoke tests
echo ">>> Phase 2: Scene smoke tests"
echo ""
bash "$SCRIPT_DIR/run_scene_smoke_tests.sh"
SMOKE_EXIT=$?
echo ""

echo "============================================"
echo "  Tombstone Suite Complete"
echo "  Unit tests exit: $UNIT_EXIT"
echo "  Smoke tests exit: $SMOKE_EXIT"
echo "============================================"
