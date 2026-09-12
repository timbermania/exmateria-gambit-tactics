#!/bin/bash
# The suite's test list, its ~25 static pre-flight guards, and the SEQUENTIAL arm.
#
# ⚠️ THE SEQUENTIAL ARM IS NOT THE WAY TO RUN THE SUITE. It is 61 minutes against
# the parallel runner's 10.4 (ADR-0158, #453 — three repeats, same tree, both arms
# scored by tests/lib/verdict.sh). Run this with no arguments and it executes the
# pre-flight guards and then STOPS, printing the command you wanted. That gate is
# deliberate: agents and humans alike keep reaching for this file because handoffs
# quote its wall clock, and a session burned ~150 minutes on three sequential runs
# before anyone noticed.
#
# Usage:
#   uv run python tools/run_tests_parallel.py    # ← the way to run the suite
#   bash tests/run_all_tests.sh --preflight-only # the static guards, no Godot
#   bash tests/run_all_tests.sh --sequential     # the slow arm, on purpose
#
# WHY THE SLOW ARM STILL EXISTS, and why deleting this file is not an option:
#   - ADR-0158 adopted the parallel runner on the strength of a DIFF against this
#     one. `run_tests_parallel.py`'s SEQUENTIAL_LANE is filled BY that diff, never
#     by hand, so retaking it needs this arm.
#   - docs/TEST-BASELINE-E2.tsv records `sequential, never parallel` as a property
#     of the frozen register (ADR-0153).
#   - ELEVEN tools read this file. `_runner_tests.runner_tests()` slices the
#     TESTS array out and asks BASH to expand it — including on behalf of the
#     parallel runner, which has no test list of its own. The slice never executes
#     the script, so the gate below cannot affect it. (It anchors on the array's
#     opening token, so do NOT write that token anywhere above the array — this
#     comment said it once and the slice started HERE, which is what
#     test_run_tests_parallel.py caught.)

GODOT="${GODOT:-godot}"

SEQUENTIAL_OPT_IN=0
PREFLIGHT_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --sequential)     SEQUENTIAL_OPT_IN=1 ;;
        --preflight-only) PREFLIGHT_ONLY=1 ;;
        *) echo "unknown argument: $arg"; echo "usage: bash tests/run_all_tests.sh [--sequential|--preflight-only]"; exit 2 ;;
    esac
done

# Pre-flight: the engine-fold compositor is 4.8-fork-only. Under stock 4.7 it
# self-disables and folded effects (particles + callbacks) silently don't
# render — every render/compositor test would pass against a degraded frame.
# Fail loudly instead of running the suite on the wrong binary.
GODOT_VER="$("$GODOT" --version 2>/dev/null)"
if [[ "$GODOT_VER" != *"4.8.dev.custom_build"* ]]; then
    echo "ABORT: '$GODOT' is '$GODOT_VER', not the 4.8 compositor fork."
    echo "       The engine-fold compositor is fork-only; on stock 4.7 folded"
    echo "       effects don't render. Point \$GODOT at the fork, or symlink"
    echo "       /usr/local/bin/godot -> the fork build. Expected 4.8.dev.custom_build."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

# The ONE verdict reader (#451, map #450). Sourced, not re-implemented — this
# runner and tools/run_unlisted_audio_binders.sh both feed the frozen register,
# so they must score a log identically by construction.
source "$PROJECT_DIR/tests/lib/verdict.sh"

# Pre-flight: the combat buffer layout (UnitField/GambitField/AbilityField offsets)
# is generated from the shader. Fail fast if the committed region is stale before
# launching any Godot window. Pure Python - no Godot needed.
echo "Checking combat buffer layout is up to date..."
if ! (cd "$PROJECT_DIR" && uv run python tools/gen_gpu_layout.py --check); then
    echo "ABORT: combat buffer layout is stale. Run: uv run python tools/gen_gpu_layout.py"
    exit 1
fi

# Pre-flight: AbilityDatabase.gd + AbilityView.gd are generated from the ability
# JSON (ADR-0008). Fail fast if the committed files are stale. Pure Python.
echo "Checking ability database / view are up to date..."
if ! (cd "$PROJECT_DIR" && uv run python tools/generate_ability_database.py --check); then
    echo "ABORT: ability database/view is stale. Run: uv run python tools/generate_ability_database.py"
    exit 1
fi

# Pre-flight: the OWNED event / BattleConditional opcode catalogs
# (assets/scenarios/event_instructions.json + battle_conditional_opcodes.json) are transcribed
# from the reference XML under tools/data/vendor/. The same --check also
# regenerates the src/scenarios/EventInstruction.gd dispatch enum (ADR-0059) in
# memory and fails if the committed file drifted. Fail fast if a committed
# catalog's core (name + params + opcode-width) drifted from the XML, or the
# enum is stale. Pure Python, no Godot needed. (ADR-0001 in-housed authored data)
echo "Checking event opcode catalogs + EventInstruction enum are up to date..."
if ! (cd "$PROJECT_DIR" && uv run python tools/gen_opcode_catalog.py --check); then
    echo "ABORT: opcode catalog or EventInstruction enum is stale. Run: uv run python tools/gen_opcode_catalog.py"
    exit 1
fi

# Pre-flight: the UnitNames battle-cast sourcing table
# (addons/exmateria_catalogue/identity/unit_names.json, #1025 pass 3;
# navigator T3 / decision #181) is transcribed from the vendored FFTPatcher
# UnitNames.xml. Fail fast if the committed JSON drifted from the XML. Pure Python.
echo "Checking unit_names.json is up to date..."
if ! (cd "$PROJECT_DIR" && uv run python tools/build_unit_names.py --check); then
    echo "ABORT: unit_names.json is stale. Run: uv run python tools/build_unit_names.py"
    exit 1
fi

# Pre-flight: the derived story timeline (assets/scenarios/roster_timeline.json,
# ADR-0216) is folded over the 155 scenario groups from entd.json + the world-map
# enter scripts. Two consumers read it on every navigator boot -- RosterTimeline's
# roster/seek state and StoryMutationScript's cast -- and it is far too large to
# review by eye, so a drift against its sources has to fail here rather than turn
# up as a wrong party three chapters in. Pure Python.
echo "Checking roster_timeline.json is up to date..."
if ! (cd "$PROJECT_DIR" && uv run python tools/build_roster_timeline.py --check); then
    echo "ABORT: roster_timeline.json is stale. Run: uv run python tools/build_roster_timeline.py"
    exit 1
fi

# Pre-flight: that generator's own tests -- the story-order invariants, the recruit
# occurrence rules, the appearance scan, and the recruited-and-Red register whose
# burn-down is 1. ADR-0216 names this file as a guard, so it has to actually run.
echo "Running roster-timeline generator tests..."
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_build_roster_timeline); then
    echo "ABORT: roster-timeline generator tests failed. See ADR-0216."
    exit 1
fi

# Pre-flight: the EventInstruction slug rule (Option-A: unique verbatim,
# hex-suffix collisions, the Variable comparison symbol map, post-disambiguation
# uniqueness). Locks the transform so a catalog/generator edit can't silently
# produce a colliding or invalid enum member. Pure Python. (ADR-0059)
echo "Running EventInstruction slug-rule tests..."
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_gen_opcode_catalog); then
    echo "ABORT: EventInstruction slug-rule tests failed."
    exit 1
fi

# Pre-flight: the populated-body-rows manifest
# (addons/exmateria_sprite_rig/resources/populated_rows.json)
# is baked from the ISO-derived NN.palette.tga files. The event-script CLUT
# resolver (SpritePaletteResolver) clamps the ENTD palette byte against it, so a
# stale manifest could mis-clamp a real color. Fail fast if it drifted. Pure Python.
echo "Checking populated-body-rows manifest is up to date..."
if ! (cd "$PROJECT_DIR" && uv run python tools/bake_populated_rows.py --check); then
    echo "ABORT: populated_rows.json is stale. Run: uv run python tools/bake_populated_rows.py"
    exit 1
fi

# Pre-flight: LOGICAL_ACTIVITY_* / DisplayActivity / ActivityTranslator dispatch
# are generated from tools/activity_taxonomy.yaml. Fail fast if any of the
# emitted regions/files are stale. Pure Python, no Godot needed.
# Runs from tools/ so uv picks up tools/pyproject.toml (the generator imports
# pyyaml, which lives in the tools venv).
echo "Checking activity taxonomy is up to date..."
(cd "$PROJECT_DIR/tools" && uv run python gen_activity_taxonomy.py --check)
_taxonomy_rc=$?
if [ "$_taxonomy_rc" -eq 1 ]; then
    echo "ABORT: activity taxonomy is stale. Run: (cd tools && uv run python gen_activity_taxonomy.py)"
    exit 1
elif [ "$_taxonomy_rc" -ne 0 ]; then
    # rc 2 is a GenError: the generator could not REACH a destination. That is not
    # staleness and "run the generator" is the wrong advice -- the generator is the
    # thing that failed. #696 was exactly this: a doc split moved the CONTEXT region
    # into docs/context/ and the abort text sent everyone to a command that could not
    # help. Say which cause it is, and name the marker in the error above.
    echo "ABORT: the activity-taxonomy generator could not run (rc=$_taxonomy_rc)."
    echo "  This is NOT staleness -- regenerating will not fix it. Read the error above."
    echo "  A missing BEGIN/END marker usually means the generated region MOVED:"
    echo "    grep -rn 'BEGIN GENERATED: activity-taxonomy' --include='*.md' ."
    echo "  then point CONTEXT_PATH in tools/gen_activity_taxonomy.py at its new home."
    exit 1
fi

# Pre-flight: validator-rejection rules for the activity taxonomy. Locks in
# the schema contract so a future YAML/generator edit can't quietly slip
# past validation. Pure Python.
echo "Running activity-taxonomy validator tests..."
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_gen_activity_taxonomy); then
    echo "ABORT: activity-taxonomy validator tests failed."
    exit 1
fi

# Pre-flight: scenario-sourced placement decode (deployment zones + ENTD enemy
# positions). Locks the 1<<idx footprint-bitmap fix and the ROM ground truth
# (Gariland deployment idx 256 -> 8 tiles, maxsq 5). Pure Python. (ADR-0043)
echo "Running placement-parser tests..."
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_parse_placement); then
    echo "ABORT: placement-parser tests failed."
    exit 1
fi

# Pre-flight: the {78} results/intro screen assets. Pins the results overlay's
# load base (EVENT/REQUIRE.OUT @ VA 0x801BF000) and every table the screens draw
# from -- the glyph metrics, the cumulative string index, the settled colour
# records and the banner's six -- against the values BATTLE_RESULTS_SCREEN.md read
# INDEPENDENTLY out of savestate RAM. A wrong base decodes to plausible garbage,
# so this is the guard that the asset is really ROM-derived. Pure Python.
echo "Running results-screen (BONUS.BIN) parser tests..."
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_parse_bonus); then
    echo "ABORT: results-screen parser tests failed."
    exit 1
fi

# Pre-flight: the materialize codemod (ADR-0068 M1–M6) — the parser, literal
# formatting, content-revalidation, and the four skip paths (non-literal default,
# AUTOSAVE, stale snapshot, drain). Pure Python.
echo "Running materialize-tunables codemod tests..."
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_materialize_tunables); then
    echo "ABORT: materialize-tunables tests failed."
    exit 1
fi

# Pre-flight: the machine-state sentinel (ADR-0281 / #1149) — the 2x2 of
# (before, after) x (absent, present) over `config/tune_overrides.json`. The SENTINEL
# itself brackets the test loop and cannot live here; these are its arms, and they are
# here because the arm that matters is "absent before, present after" — the transition
# the per-test restore it replaces early-returned on for two days.
echo "Running machine-state sentinel tests..."
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_machine_state_sentinel); then
    echo "ABORT: machine-state sentinel tests failed."
    exit 1
fi

# Pre-flight: the key-location ownership scanner (ADR-0088 Amendment 2 §2) — the
# static-scan logic behind the ownership gate below (single owner, split namespace,
# consumer-const-not-owner, comment-example ignored). Pure Python.
echo "Running key-location ownership scanner tests..."
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_check_location_ownership); then
    echo "ABORT: key-location ownership scanner tests failed."
    exit 1
fi

# Pre-flight: the ONE verdict reader (#451, map #450) — the instrument every other
# number in this run is read through. Rule order (HUNG > [VERDICT] > [FAIL] >
# [PASS] > tick-TIMEOUT > CRASHED > NOT_A_TEST > NO_VERDICT, then THREW against a
# PASS), the marker
# rules pinned unchanged, and the
# regression that motivated it: GambitScenarioRunner's quarantined XFAIL
# expectations print `[FAIL]` and used to score the whole test red while it
# reported 82 scenarios green. Also asserts no runner has grown a second copy of
# the rule. Pure Python driving the real bash function.
echo "Running test-verdict reader tests..."
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_verdict_reader); then
    echo "ABORT: verdict reader tests failed. The suite cannot score itself."
    exit 1
fi

# Pre-flight: the SECOND arm and the register's provenance (#453, ADR-0158). The
# parallel runner is adoptable only because its verdicts were proven identical to
# this one's, and the three things that proof rests on are all code: the runner
# reads THIS file's TESTS array and sources `tests/lib/verdict.sh` rather than
# restating either; the arm diff separates "parallelism changed it" from "it was
# already flaky"; and the register derives `sequential` vs `parallel N=8` from the
# run's own banner instead of asserting it. Untested, any of the three would drift
# and the identity claim would quietly stop being about this tree.
#
# ⚠️ RECURSION. `test_run_tests_parallel.SequentialArmIsGated` invokes THIS SCRIPT to
# prove the gate below refuses — and this line runs that test. Left alone the two call
# each other forever (measured: a 10-minute hang, no output). The nested invocation
# exports FFT_SUITE_NESTED=1, and the only thing that changes is that this one guard is
# skipped there: every other pre-flight check still runs on both levels, and the gate is
# still exercised end to end. A skip is cheaper than the alternatives — moving the gate
# test out of the pre-flight would mean nothing ran it, which is the defect (#565) that
# put those two halves in the suite in the first place.
if [[ -z "${FFT_SUITE_NESTED:-}" ]]; then
    echo "Running parallel-arm and register-provenance tests..."
    if ! (cd "$PROJECT_DIR/tools" && FFT_SUITE_NESTED=1 uv run python -m unittest \
            test_run_tests_parallel test_diff_arm_verdicts test_freeze_test_baseline \
            test_check_adr_classification); then
        echo "ABORT: the parallel arm's own tests, or the ADR register guard's own tests,"
        echo "       failed. See #453 / ADR-0158 and #1163."
        exit 1
    fi
else
    echo "Running parallel-arm tests... SKIPPED (nested invocation, see comment above)"
fi

# Pre-flight: this run's own output is an INSTRUMENT, and two lines of it are the
# whole wall-clock budget (#454). `tools/suite_register.py` takes a per-test
# register on any commit and diffs two of them; every column it carries is
# downstream of the `  seconds` / `  exit` lines this loop prints and the
# `addon_sync` / `godot_cache` stamps its banner carries. If a runner stops
# printing them the register does not go red — it reports `-` for every wall
# clock and `UNKNOWN` for the harness, and reads exactly like a measurement.
# So the guard is against the RUNNERS, not against a synthetic log, and its own
# arms were each seeded red against the real files. `harness_stamp` runs at boot,
# in the banner, so a break in it breaks this suite and not just the register.
echo "Running suite-register and harness-stamp tests..."
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest \
        test_suite_register test_harness_stamp); then
    echo "ABORT: the re-takeable register's own tests failed. See #454."
    exit 1
fi

# Pre-flight: a scene that COUNTS assertions must declare a verdict the reader can
# score (#463). `ScenarioWalkToAnimTest` printed `16 passed, 0 failed` / `RESULT:
# PASS` and no marker, and scored NO_VERDICT — the label for a test that did not
# run — in the two oldest archived full runs. It was found by hand and fixed by
# hand; nothing would have caught the next one. Static (sources, not logs), so it
# also covers the ~300 marker-emitting scenes no runner runs yet (#417). Its own
# tests include the arm that proves it FIRES, against the real pre-fix file.
echo "Checking every asserting scene declares a readable verdict..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_test_verdict_channel.py); then
    echo "ABORT: a test scene counts assertions the runner cannot score. See #463."
    exit 1
fi
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_check_test_verdict_channel); then
    echo "ABORT: the verdict-channel guard's own tests failed."
    exit 1
fi

# Pre-flight: this array is not allowed to be the whole answer to "what tests are
# there" (#417). It was hand-maintained while the tree grew, and on trunk
# `6a25e54f7` it named 412 of the 744 scenes under `tests/` — 300 of the other 332
# emitting PASS/FAIL markers and reachable by no runner at all, for two months,
# under green summaries. The guard quantifies over EVERY scene and requires each
# to be listed here, to declare `[NOT_A_TEST] <why>` on the verdict reader's own
# channel, or to carry a row in `tests/skip_tests.tsv` — so a test nobody runs and
# a test nobody MEANT to run stop looking identical. Static; no Godot.
echo "Checking every scene under tests/ is run, declared or skipped with a reason..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_test_list_coverage.py); then
    echo "ABORT: a scene under tests/ is in no runner's list and nothing says why. See #417."
    exit 1
fi
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_check_test_list_coverage); then
    echo "ABORT: the test-list coverage guard's own tests failed."
    exit 1
fi

# Pre-flight: THE MECHANICAL HALF OF THE TEST CHARTER (docs/TEST-CHARTER.md).
# The two blocks above ask whether every scene is RUN and whether it can be SCORED.
# This one asks whether it is a test worth the 2.3 s process it costs: does it declare
# its KIND, does it QUIT ITSELF, is there anything on record that this test CAN fail,
# and does its verdict depend on how busy the box was. Five clauses of fourteen; the
# other nine are judgement and are audited one test at a time by
# `.claude/skills/test-audit-loop`, which is why TEST-CHARTER.md marks each clause (G)
# or (J) rather than letting a heading read as enforced.
#
# `tests/charter_allowlist.tsv` carries the 1,507 violations that existed when the
# charter landed and may only SHRINK -- a row whose violation is gone is itself an
# error, so it cannot rot into a permanent exemption. Static; no Godot; ~0.4 s.
echo "Checking the test charter's mechanical clauses..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_test_charter.py); then
    echo "ABORT: a new test-charter violation, or a stale allowlist row."
    echo "       See docs/TEST-CHARTER.md; the burn-down is --stats."
    exit 1
fi
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_check_test_charter); then
    echo "ABORT: the test-charter guard lost a seeded arm."
    exit 1
fi

# Pre-flight: THE SAME QUESTION ONE LEVEL UP (#770, ADR-0233). The block above asks
# whether every test is run; this one asks whether every GUARD is. `run_all_tests.sh` is
# the only definition of the pre-flight -- the parallel runner shells out to it -- so a
# `tools/check_*.py` this file does not invoke is a guard nobody runs, and the comment
# beside `check_addon_portability.py` further down already says that in those words.
# It had been true three times before it was measured: `check_vault_anchors.py`
# registered nowhere for months (#565); `check_addon_portability.py` NAMED by ADR-0003
# dec. 7 and given two more arms before ADR-0175 wired it in; `check_blueprint_walk.py`,
# which calls itself guard #24, sitting red on trunk with nobody reading it (#728, #770).
# The sweep that turned the pattern into a population: 58 guards, 10 in no pre-flight,
# 4 of those RED on trunk right now. Cost was not the reason -- all nine of the unwired
# ones were timed and the slowest is 4 s.
echo "Checking every guard under tools/ is invoked here or declared not to be..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_guard_registry.py); then
    echo "ABORT: a tools/check_*.py is in no pre-flight and on no row, or a row excuses a"
    echo "       guard that is now invoked. See tools/check_guard_registry.py."
    exit 1
fi
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_check_guard_registry); then
    echo "ABORT: the guard registry's own seed-red arms failed."
    exit 1
fi

# --- the six guards #770's sweep found unwired, and their reasons ------------------
# Each of these existed, passed, and was invoked by nothing. They are wired here rather
# than one per section because what they have in common is the FINDING, not the subject.
#
# check_blueprint_walk.py    guard #24 (ADR-0144 dec. 9). #728's and #770's reds are both
#                            paid now -- 0 unclassified -- so the invocation can land.
# check_baseline.py          docs/BASELINE.tsv, the frozen opening reading of the refactor
#                            series (ADR-0145). Silent edit and silent schema drift.
# check_residue.py           -- NOT here: RED on trunk, #880. Row in check_guard_registry.
# check_adr_quotes.py        a citation records WHERE; this is the only check on WHAT.
#                            Publishing an ADR is a four-step ritual and this is the step
#                            with no other enforcement.
# check_addon_sync.py        the host's deployment copy of an extracted package must equal
#                            the package. A no-op in a linked worktree, by construction.
# check_no_global_rd_for_compute.py
#                            a class that submits/syncs a RenderingDevice must own a LOCAL
#                            one; the global renderer's device rejects manual submission.
echo "Checking the blueprint walk classifies every source file (guard #24)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_blueprint_walk.py); then
    echo "ABORT: a source file is in no classify_blueprint bucket, or a rule is dead or"
    echo "       shadowed. See ADR-0144 dec. 9 / ADR-0156."
    exit 1
fi

echo "Checking the frozen baseline register..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_baseline.py); then
    echo "ABORT: docs/BASELINE.tsv was edited by hand or its schema drifted. See ADR-0145."
    exit 1
fi

echo "Checking quoted ADR spans are quotations of the ADR they cite..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_adr_quotes.py); then
    echo "ABORT: a quotation-shaped span does not match the ADR cited beside it."
    exit 1
fi

echo "Checking the deployment copy of each extracted package equals the package..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_addon_sync.py); then
    echo "ABORT: a deployment copy has drifted from its package. Run"
    echo "       tools/sync_exmateria_sound.sh."
    exit 1
fi

# The gambit lab's straddle table (ADR-0275 dec. 8, #1129). A static guard: two text parses,
# no Godot boot, so it costs nothing against the three runs of this block. `--selftest` proves
# each of its eight arms reds under a seeded break.
echo "Checking every gambit condition opcode has a hand-authored straddle row..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_gambit_straddle_table.py); then
    echo "ABORT: the kernel declares a COND_* with no straddle row, or a row is incomplete,"
    echo "       stale, or wired to no _straddle arm. See ADR-0275 dec. 8 / dec. 9."
    exit 1
fi

echo "Checking every hand-driven RenderingDevice is a LOCAL one..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_no_global_rd_for_compute.py); then
    echo "ABORT: a class submits or syncs a RenderingDevice it obtained from"
    echo "       RenderingServer.get_rendering_device(). That device refuses manual submit."
    exit 1
fi

# Pre-flight: the audio addons' global-name surface (ADR-0003, #383). Godot has
# no namespaces, so an addon's `class_name`s, its GDExtension registrations and
# the autoloads it depends on all land in THIS project's global scope — and when
# a name collides it is the ADDON's file that fails to parse, pointing the error
# at a file nobody here wrote. The guard lives in exmateria-sound because that is
# where the surface is; this is one of its two callers, and the monorepo has no
# CI, so it is only as live as the two of them.
echo "Checking the audio addons still own only their five global names..."
# ADR-0003's guard ships with the sound PACKAGE, not with this one. In a
# standalone checkout the sibling is not there and neither is the guard — the
# vendored addons still travel, but the tool that checks their global surface
# does not, so the honest thing is to say it was not run rather than to pass.
CHECK_GLOBALS="$PROJECT_DIR/../exmateria-sound/tools/check_globals.py"
if [[ ! -f "$CHECK_GLOBALS" ]]; then
    echo "SKIP: exmateria-sound/tools/check_globals.py is absent (standalone checkout)."
    echo "      ADR-0003's global-surface guard ships with that package."
elif ! python3 "$CHECK_GLOBALS"; then
    echo "ABORT: the audio addons' global surface drifted from ADR-0003. See #383."
    exit 1
fi

# Pre-flight: this package's four addons' global-name surface (ADR-0212, #718
# #719 #720 — widened from ADR-0211's single addon, #717). Same hazard as the
# audio check above, different addons and a different scope: this one scores the
# `class_name` channel ONLY. The autoload/host-global channel is
# check_addon_install.py's (axis B, ADR-0202 dec. 1), the res:// path channel is
# check_lattice_scene.py's criterion 4 (axis A, ADR-0205), and the shader
# `#include` channel is check_addon_portability.py arm 3's (ADR-0212 dec. 5) —
# never report one as another. Not a pass while a burn-down carries names; it
# exits 0 and SAYS the count per addon, because the creep, rot and citation arms
# are enforcing around the owed set from the day it lands (ADR-0212 dec. 6,
# ADR-0192 dec. 1's register-goes-first).
echo "Checking the four addons' global class_name surface..."
if ! python3 "$PROJECT_DIR/tools/check_addon_globals.py"; then
    echo "ABORT: an addon's global surface drifted from ADR-0212. See #718/#719/#720."
    exit 1
fi

# ...and the register's own seed-red tests, the way every sibling register in
# this file is checked. They were written with ADR-0211 dec. 6 and NOTHING RAN
# THEM: an arm that has never been seen to fire is indistinguishable from one
# that cannot, which is the defect the seeds exist to rule out. They construct
# every condition they grade — a creep `class_name` in each of the four addons,
# a stale burn-down entry in each, a rotted façade constant, an unlabelled
# sibling citation — and they derive the addon population from the TREE rather
# than from the guard's own dict, so narrowing that dict reds here.
echo "Running the addon-globals register's seed tests..."
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_check_addon_globals); then
    echo "ABORT: the addon-globals register's own arms are not firing (ADR-0212 dec. 6)."
    exit 1
fi

# Pre-flight: Phase-0 reference-scene parser goldens (issue #137, ADR-0057) —
# the anti-regression oracle for the PSX<->Godot spatial-transform
# consolidation. Regenerates each reference scene's entd/terrain/mesh/camera/
# cull snapshot and asserts it byte-matches the committed golden, plus the
# roster invariants (chapel orientation-blind, academy exercises facing 1/3,
# frog non-symmetric, monastery strong-cull). The runtime Render half lives in
# the ReferenceRenderDirectionTest scene below. Pure Python (map layers skip if
# the gitignored assets are absent). Regenerate: uv run python
# tools/gen_reference_goldens.py
echo "Running reference-scene parser-golden tests..."
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_reference_goldens); then
    echo "ABORT: reference-scene parser-golden tests failed (spatial oracle drift; ADR-0057)."
    exit 1
fi

# Pre-flight: every battle .gdshader that writes DEPTH must route through the
# unified Ordering-Table depth seam (ADR-0009) — no inline NDC-epsilon hacks.
# Pure Python, no Godot needed.
echo "Checking depth shaders use the ot_depth seam..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_depth_shaders.py); then
    echo "ABORT: a shader writes DEPTH outside the ot_depth seam (ADR-0009)."
    exit 1
fi

# Pre-flight: every colour-transforming shader recolours through the shared
# color_apply seam (ADR-0067) — no shader may reintroduce a deleted legacy
# per-uniform tint path (unit_tint_*/unit_luma_*/field_*/tint_color) or fold via
# color_apply without including the seam. Pure Python, no Godot needed.
echo "Checking colour shaders use the color_apply seam..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_color_shaders.py); then
    echo "ABORT: a shader recolours outside the color_apply seam (ADR-0067)."
    exit 1
fi

# Pre-flight: every Environment must use LINEAR tonemapping. The PSX clamps 5-bit
# colour in the framebuffer; only Godot's Linear tonemapper matches that. A
# non-linear tonemapper (Reinhard/Filmic/ACES/AgX) silently corrupts every
# additive/subtractive blend AND desyncs the forward render_mode blends from the
# display-space compositor fold. Linear is the default, so correct scenes OMIT
# tonemap_mode — this fails only on an explicit non-zero one. No Godot needed.
echo "Checking all Environments use Linear tonemapping..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_tonemap.py); then
    echo "ABORT: an Environment uses a non-linear tonemapper (breaks PSX blend fidelity)."
    exit 1
fi

# Pre-flight: every battle shader that writes POSITION must apply the horizontal
# PAR stretch through the shared seam (ADR-0060) — no shader may silently forget
# it and drift out of alignment with the units/map. Pure Python, no Godot needed.
echo "Checking POSITION shaders apply PAR through the pixel_aspect seam..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_par_shaders.py); then
    echo "ABORT: a shader writes POSITION outside the pixel_aspect seam (ADR-0060)."
    exit 1
fi

# Pre-flight: the universal compositor-routing scoreboard — every in-scene
# blend_add/blend_sub shader must be on the shrinking burn-down allowlist or
# carry a `// compositor-exempt:` marker. Ratchets both ways (new leaks AND
# stale entries fail); empty allowlist = ready for Forward+. Pure Python.
echo "Checking compositor-routing scoreboard (blend_add/blend_sub burn-down)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_compositor_routing.py); then
    echo "ABORT: an un-routed additive/subtractive shader leaked, or a stale allowlist entry remains."
    exit 1
fi
# ...and the scoreboard's own arms, seeded red. It carries three shrink-only ratchets
# across two axes and until this test nobody had ever watched one fail -- which is the
# "a guard nobody has watched fail" problem the guard itself exists to fix, one level up.
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_check_compositor_routing); then
    echo "ABORT: the compositor-routing scoreboard's own seed-red arms failed."
    exit 1
fi

# Pre-flight: no sRGB->linear pow() reachable from a compositor_layer shader. The fold
# blends in DISPLAY space with no tonemap after, so pow(color, psx_gamma) there is the
# gold-box wrong-color-space bug class. Resolves #includes; the 2 known-unfixed folds
# (cursor outline, orb rim) are on a burn-down allowlist that ratchets. Pure Python.
echo "Checking no sRGB->linear pow() leaks into a display-space fold..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_no_pow_in_fold.py); then
    echo "ABORT: a pow() is reachable from a compositor_layer shader (or a stale burn-down entry remains)."
    exit 1
fi

# Pre-flight: psx_brightness is the ÷255→÷128 pool-envelope conversion, NOT part of the fold
# contract. A display-native CLUT / direct-gouraud fold (box/orb/cursor) must compute gouraud/128
# directly, never ×psx_brightness (double-count = the overbright halo). Burn-down of the pool/decal/
# callback folds still on it ratchets toward deleting psx_brightness entirely (ADR-0074 color-math).
echo "Checking psx_brightness isn't double-counted into a display-space fold..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_no_psx_brightness_in_fold.py); then
    echo "ABORT: psx_brightness leaked into a non-pool fold (or a stale burn-down entry remains)."
    exit 1
fi

# Pre-flight: every compositor_layer shader declares its PSX primitive kind (// psx-prim: textured
# | untextured) and it matches reality (textured samples a texel; untextured outputs colour direct).
# The kind drives the color-math contract (ADR-0074): textured ⇒ texel×gouraud/128, untextured ⇒
# colour. Catches an untextured prim (tile_decal class) hiding among the textured folds.
echo "Checking every fold declares a matching PSX primitive kind..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_fold_primitive_kind.py); then
    echo "ABORT: a fold is missing its // psx-prim declaration or it mismatches what the shader does."
    exit 1
fi

# Pre-flight: a fold shader named from GDScript is a preloaded Shader, never a String path resolved
# with load(). ADR-0191 dec. 2 names the hazard — a load() of a mistyped path returns null, a null
# shader does not raise, and the fold "just stops, with no error" — and Amendment 4 §2 separates it
# from the PICK dec. 2 was deciding, because the hazard belongs to naming a fold shader at all. This
# class survived a BUILT census, a code review and a fix pass in UIVitalsBand (Amendment 3), so it
# gets a guard rather than a convention. Seeded on the SHADERS, not the predicate: it reads which
# files declare compositor_layer and asks who names them, so a producer that never mentions the fold
# is still visible. Scans tools/ and tests/ as well as the walk roots — both capture probes live
# outside walk_roots() and a guard that missed them would read clean over a real reach.
echo "Checking every GDScript reference to a fold shader is preloaded (not a load()ed path)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_fold_shader_preload.py); then
    echo "ABORT: a fold shader is named as a String path — a typo there fails SILENTLY."
    exit 1
fi

# Pre-flight: a folded prim's colour, when resolved on the CPU (GDScript), must be RAW display-space —
# no pow(gamma), no psx_brightness. The shader guards can't see colour-space math that hides in the
# helper that builds a fold prim's COLOR (the tile_decal / TileOverlayColor.flat_color bug). ADR-0074.
echo "Checking CPU fold-colour resolvers stay raw display-space (no pow/psx_brightness)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_no_cpu_color_math_in_fold.py); then
    echo "ABORT: colour-space math (pow/psx_brightness) hiding in a CPU fold-colour resolver."
    exit 1
fi

# Pre-flight: no battle mesh may opt out of OT depth via StandardMaterial3D
# (the escape hatch projectiles slipped through) — each use needs an explicit
# psx-ot-depth-exempt marker. Pure Python, no Godot needed.
echo "Checking battle meshes don't escape OT depth via StandardMaterial3D..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_battle_materials.py); then
    echo "ABORT: an unmarked StandardMaterial3D may escape the OT depth model (ADR-0009)."
    exit 1
fi

# Pre-flight: the dialogue-box open/close grow-shrink tween reads its curves
# from assets/ui/dialogue_box_curves.json (parsed from BATTLE.BIN). CI half of
# the anti-silent-failure contract: fail loudly if the asset is missing, wrong-
# shaped, or drifted from the live PCSX capture, rather than let the box silently
# lose its grow/shrink at runtime. Pure Python, no Godot needed.
echo "Checking dialogue-box open/close curves asset is present + matches the ROM capture..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_dialogue_box_curves.py); then
    echo "ABORT: dialogue_box_curves.json missing/drifted. Run: uv run python tools/parse_dialogue_box_curves.py"
    exit 1
fi

# Pre-flight: every unique's BODY sprite in assets/scenarios/template_assets.json
# must be the one the ROM's own ENTD gives that special_name. The hand-authored
# rows were read off the SPR FILENAME, and the romanization lies: GARU.SPR is
# Mustadio's sheet, not Gafgarion's, so the chapel painted Mustadio's portrait on
# Gafgarion. Nothing could see it — the wrong id is baked into a gitignored
# templates/ folder and UIPortrait PREFERS that folder over the (correct) id on
# the spawned Unit. Pure Python, no Godot needed.
echo "Checking template_assets.json body sprites match the ROM's ENTD..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_template_assets_entd.py); then
    echo "ABORT: a unique's body_sprite_id contradicts the ENTD. An SPR filename is not"
    echo "       the character — fix template_assets.json and re-run"
    echo "       tools/align_character_templates.py."
    exit 1
fi

# Pre-flight: scene configuration must flow through F3 debug panels, never
# OS.get_environment reads (ADR-0051) — env-as-config is invisible in the editor
# and leaks across shells (a stale SCENARIO_* export once silently quit a scene).
# Pure Python, no Godot needed.
echo "Checking no OS.get/has_environment scene-config reads in src/ or tests/..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_no_env_vars.py); then
    echo "ABORT: env var used for scene configuration (ADR-0051). Route it through a debug panel."
    exit 1
fi

# Pre-flight: the ADR corpus is self-consistent. Two guards, both pure Python:
#   - every ADR is classified exactly once and no number names two files, so an
#     `ADR-NNNN` citation resolves to ONE document;
#   - every `ADR-NNNN <anchor>` citation (a quarter of them name an amendment,
#     decision or § INSIDE an ADR) addresses a place that still exists.
# The second is what makes rewriting an ADR safe: fold or renumber a section a
# citation depends on and it fails here instead of going stale in silence.
echo "Checking the ADR corpus is self-consistent (classification + citation anchors)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_adr_classification.py); then
    echo "ABORT: an ADR is unclassified, a number is ambiguous, or a register is stale in a"
    echo "       column that is NOT measured (#1163). Re-run tools/gen_adr_index.py and"
    echo "       tools/gen_adr_audit.py and commit — never hand-edit INDEX.md/AUDIT.md."
    exit 1
fi
if ! (cd "$PROJECT_DIR" && uv run python tools/check_adr_anchors.py); then
    echo "ABORT: an ADR citation names a section its ADR no longer has."
    exit 1
fi
if ! (cd "$PROJECT_DIR" && uv run python tools/check_context_index.py); then
    echo "ABORT: CONTEXT.md is stale, or a vocabulary term is defined twice."
    exit 1
fi

# Root ADR-0001: nothing derived from the FFT disc is committed. The package ships
# as a standalone bring-your-own-ISO repo, so "reproduces from the disc" and "is not
# in git" have to name the same set. One manifest
# (tools/data/generated_assets.tsv) carries every artifact's provenance and, for
# disc derivations, its generator; the root .gitignore's managed block is rendered
# from it. ADR-0001 used to verify this with a one-time sweep, which is how seven
# artifacts reached the repo with no generator at all.
# godot-learning/vendor/ carries copies of two packages this one does not own —
# the sound addons and the ISO core — because the package ships standalone, where
# ../exmateria-sound/ and ../fft-iso-patcher/ do not exist. A copy with no guard
# is a cache with no invalidation; check_addon_sync.py already learned that about
# the host deployment copy, where 67 .gd files had silently drifted.
echo "Checking godot-learning/vendor/ mirrors its packages..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_vendor_sync.py); then
    echo "ABORT: a vendored package has drifted from the sibling it copies."
    echo "       Re-vendor with tools/vendor_packages.py and commit."
    exit 1
fi
# The guard's own arms, including the two checkout shapes it has to read its
# ignore rules in — `godot-learning/` in the monorepo, the repo root in the
# standalone `exmateria-gambit-tactics` clone. 17 tests, ~0.01 s.
# The export is the artifact that gets PUBLISHED, so its manifest is guarded here
# rather than checked by hand at push time (register step 10). Four rules, each
# mutation-verified to red exactly one arm: nothing stale left in a destination by
# an earlier export, nothing on EXCLUDE leaking through, no EXCLUDE rule rotted
# into a no-op, and every path a clone needs present. Static; no Godot; ~0.6 s.
echo "Checking the standalone export manifest (register step 10)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/export_standalone.py --check); then
    echo "ABORT: the standalone export manifest is unsound — a required path is"
    echo "       missing, or an EXCLUDE rule matches nothing. See register step 10."
    exit 1
fi
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_export_standalone); then
    echo "ABORT: export_standalone.py's own arms failed — the export guard cannot"
    echo "       be trusted until they pass."
    exit 1
fi
echo "Checking the ADR-0001 asset guard's own arms..."
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_check_generated_assets); then
    echo "ABORT: tools/check_generated_assets.py's own tests fail — the guard below"
    echo "       cannot be trusted until they pass."
    exit 1
fi
echo "Checking no disc-derived asset is committed (root ADR-0001)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_generated_assets.py); then
    echo "ABORT: a disc-derived artifact is tracked, an ignore rule went missing, or a"
    echo "       tracked artifact has no provenance. Classify it in"
    echo "       godot-learning/tools/data/generated_assets.tsv and re-render the"
    echo "       .gitignore block — see root docs/adr/0001."
    exit 1
fi
# An ADR states the NOW, so it carries at most ONE dated section. The cap is what
# this corpus lacked: ADR-0085 is a 39-line decision under 2,947 lines of 27
# successive positions. BURN_DOWN holds the 30 that already violate and may only
# shrink — a stale entry is reported too, so it cannot become an exemption.
if ! (cd "$PROJECT_DIR" && uv run python tools/check_adr_shape.py); then
    echo "ABORT: an ADR carries a second dated section — fold the standing one first."
    exit 1
fi

# Pre-flight: every key location `<ns>.loc.<name>` is DEFINED in exactly one owner class
# (ADR-0088 Amendment 2 §2). A key position is shared — many elements ride it via at() —
# so its literal must live in ONE place (its owner), or "which class owns this position"
# goes ambiguous and the §7 add-a-location injection has nowhere sound to write. Static
# scan of the quoted slug literals; consumers reference the owner's const, never
# re-literal. Pure Python, no Godot needed.
echo "Checking key-location ownership is unambiguous (one owner per namespace)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_location_ownership.py --check); then
    echo "ABORT: a key location is defined outside its owner class (ADR-0088 Amendment 2 §2)."
    exit 1
fi

# Pre-flight: PSX magnitude conversions live once, in PsxUnits/CameraCalib — no
# re-derived conversion idioms (14336/114688, /28, TAU/4096, 4096/360, >>12, -Y=UP)
# in the effect/scenario-camera/projectile surface (ADR-0091). Pure Python.
echo "Checking no re-derived PSX magnitude conversions in src/ (ADR-0091)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_no_raw_psx_units.py); then
    echo "ABORT: raw PSX magnitude conversion re-derived (ADR-0091). Route it through PsxUnits."
    exit 1
fi

# Pre-flight: the terrain LEVEL survives the build path (ADR-0219). The ROM's tile
# pointer takes three coordinates and bounds-checks the third (`level < 2`,
# @0x8018400c); the game read `terrain.level_0` and stopped, so 202 selectable tiles
# across 44 maps were never built and Algus walked UNDER the Igros bridge. Four arms:
# the build loop is index-driven, no query builds a ground key inline (so
# `grep -rn "TerrainCell.ground"` is the whole census of ground-plane assumptions),
# LEVEL_COUNT still holds the ROM's bound with a runtime assert behind it, and the
# exported corpus still carries a second level. Pure Python; arm 4 SKIPs without assets.
echo "Checking the terrain level survives the build path (ADR-0219)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_terrain_level.py); then
    echo "ABORT: the terrain level is being dropped again (ADR-0219). A cell is (x, z, level)."
    exit 1
fi

# Pre-flight: one slot, one writer (ADR-0221 dec. 3). A cell wears more than one
# marking at a time and a `Tile` renders exactly ONE, so `TileHighlights` arbitrates —
# one marking per SLOT per cell, topmost occupied to the tile. That only holds while
# nothing else writes the tile. It didn't: three writers shared the slot with no
# arbiter, so a march pick was erased by the cursor walking off it and `_process`
# re-asserted CURSOR_ACTIVE every frame to hide the same collision. Two arms — `Tile`
# declares the underscored spelling and no public twin, and `TileHighlights.gd` is the
# only caller. Walks the addon roots too: two of the three writers were INSIDE the addon,
# which is why ADR-0164 dec. 1's host-side census never saw them.
echo "Checking TileHighlights is the only highlight writer (ADR-0221 dec. 3)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_highlight_writer.py); then
    echo "ABORT: something other than TileHighlights writes a Tile's highlight (ADR-0221 dec. 3)."
    exit 1
fi

# Pre-flight: the unit-sprite compositor fork does not regrow (ADR-0189 dec. 8). No `.gd`
# outside Sprite Rig may name one of the THREE variant shader paths in CODE — comments are
# stripped, because ten files legitimately cross-reference them in prose. The disease is the
# DUPLICATION a path enables: SpriteLayerManager takes its material from the caller, and two
# consumers used that to swap `.shader`, one of which grew a 1,018-line hand-synced fork.
echo "Checking no unit shader paths outside Sprite Rig (ADR-0189 dec. 8)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_unit_shader_paths.py); then
    echo "ABORT: a .gd outside Sprite Rig names a unit shader path (ADR-0189 dec. 8). Ask UnitMaterial for a variant."
    exit 1
fi

# Pre-flight: every debug-panel value control routes through the TuneField factory,
# so it declares a persistence class — TUNABLE / AUTOSAVE / EPHEMERAL (ADR-0068). A
# raw SpinBox/CheckBox/etc. in a panel is undeclared state. Currently REPORT MODE
# (exits 0) while the panels are migrated; flip ENFORCE in the script to gate.
echo "Checking debug-panel value controls route through TuneField (ADR-0068)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_debug_panel_tunables.py); then
    echo "ABORT: a debug-panel value control bypasses the Tune system (ADR-0068)."
    exit 1
fi

# Pre-flight: every tunable owner registers ITSELF — a zero-arg static
# register_tunables() is called from its own _static_init, an autoload's from its
# own _ready — and src/core/Tune.gd names none of them (ADR-0173, #535). This is
# the static half of the pair that replaced Tune.register_all()'s hardcoded list
# of fifteen owner script paths across seven of the eleven systems; S2 is what
# makes re-centralizing the replay loud instead of convenient. Pure Python, no
# Godot needed. Runtime half: TuneOwnerSelfRegistrationTest, below.
echo "Checking every tunable owner self-registers and Tune names none (ADR-0173)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_tune_owner_self_registration.py); then
    echo "ABORT: a tunable owner does not register itself, or Tune.gd names one (ADR-0173)."
    exit 1
fi

# Pre-flight: the OUT-OF-BATTLE vitals builder is named only where somebody argued
# it is safe. `FormationScene.vitals_view_from_character` writes current_hp = max_hp
# by construction (UnitProgression holds no current HP), so a BATTLE surface pushing
# it shows every unit at full HP however hurt — and it reads as a refresh bug rather
# than a wrong-source bug. It shipped twice: the map-cursor hover pair, then the
# battlefield Status screen, where it was one wrong line spelled FOUR times. The
# guard counts the BUILDER rather than the push, because splitting a site into
# `var v := ...` + `set_unit_view(v)` walks past a push-shaped census while
# reintroducing the whole bug. Repo-wide: this replaces a census inside
# FormationMapHostTest that could only see ONE file. Pure Python, no Godot needed.
echo "Checking the out-of-battle vitals builder is named only where it is argued for..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_vitals_funnel.py); then
    echo "ABORT: a production file names the out-of-battle vitals builder outside its register."
    exit 1
fi

# Pre-flight: Unit._CARDINAL_TO_12BIT is the canonical chapel-calibrated
# cardinal→PSX-12-bit wheel (N=0xC00, E=0x000, S=0x400, W=0x800), so a combat
# unit (facing_angle == -1) renders the same world-locked cardinal the events
# path renders for the same world facing at every camera yaw. EAST/SOUTH were
# swapped once and rendered the perpendicular frame; this is the static half of
# that guard — it replaced tests/CombatFacingAngleTest.gd (test-audit #81
# DEMOTE), whose only live assertion was this table spelling. Pure Python, no
# Godot needed.
echo "Checking Unit._CARDINAL_TO_12BIT is the canonical cardinal wheel..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_cardinal_wheel.py); then
    echo "ABORT: Unit._CARDINAL_TO_12BIT is not the canonical cardinal→12-bit wheel."
    exit 1
fi

# (The code line also carried a `check_roster_base_inheritance.py` block here. Same
#  answer as the note below: ADR-0180 deleted that script and `check_path_extends.py`
#  replaced it. Two merges have now offered it back.)

# Pre-flight: every `Vault: [[Note]]` anchor names a note that exists on `main`
# (ADR-0111 dec. 7 / ADR-0147). An anchor is the one part of the refactor's
# instrument that must exist BEFORE the code it names is rewritten, and it was
# unregistered until #565 — a guard the suite does not list is a guard nobody runs.
echo "Checking vault anchors resolve to notes on main (ADR-0111 dec. 7)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_vault_anchors.py); then
    echo "ABORT: a Vault: anchor names a note that does not exist on main."
    exit 1
fi

# Pre-flight: EVERY extraction's move manifest and the vault edges riding on it —
# ADR-0168 (#565), written at pass 5, satisfied at pass 6, checked at pass 7.
# Five arms: every row is in exactly one of its two places (per disposition); the
# classifier books no `system` file the manifest does not name AND no `stays` entry
# declares; no `stays` entry is stale; the addon's file set equals the manifest
# exactly once it exists; and no registered vault note loses its LAST anchor. That
# last arm is the one check_vault_anchors.py above cannot report — it asserts on
# anchors PRESENT, never on an anchor that stopped being present, and is green
# through deleting a note's only edge or the whole file that carries it.
#
# 🔴 THE SUBJECT LIST IS A REGISTER AS OF #1216, and the reason is measured: this
# guard hardcoded extraction #3, ADR-0168's obligation is generic, and extractions
# #4, #5 and #6 WROTE NO MANIFEST AT ALL. Adding one is two TSVs and one row in
# `SUBJECTS`. The three lapsed manifests are NOT back-filled (#1199) — a register
# filled in by someone who did not measure the move is worse than an absent one.
echo "Checking every extraction's move manifest and vault edges (ADR-0168)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_move_manifest.py); then
    echo "ABORT: a move manifest is wrong, or a vault note lost its last anchor (ADR-0168)."
    exit 1
fi

# ...and the direction tests for it. Registered HERE, deliberately: this file names
# every tools/test_*.py it runs and there is no discovery loop, so "a guard the suite
# does not list is a guard nobody runs" (ADR-0175 arms 3/4, ADR-0003 dec. 7,
# tools/test_score_goals.py — three prior firings, #876 for the 64-of-88 census).
#
# It is not redundant with the run above. That run scores the tree as it IS; these
# 32 tests score the arms against a tree that DOES NOT EXIST — both ends of the
# `git mv` #1225 has not made yet (67-in-the-host -> 67-moved is the witness this
# register exists to produce), plus the red directions, which cannot be produced
# against a shared worktree without moving a file wrongly in it.
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_check_move_manifest); then
    echo "ABORT: the move-manifest register stopped discriminating (ADR-0168, #1216)."
    exit 1
fi

# The two terrain enum tables are spelled TWICE and must agree -- ADR-0226.
# `tools/fft_exporter/models/terrain.py` writes 13 slope-type and 50 surface-type
# NAMES into every shipped terrain.json; `RomTerrain.gd` reads them back as the BYTES
# the `{28} Walk To` planner indexes its movement-cost row with. A disagreement is
# invisible to everything else here: an unknown name reads as byte 0 (`Flat` /
# `NaturalSurface`, a legal tile) so a missing row silently FLATTENS the map, and a
# wrong byte simply ROUTES -- `Waterway` mis-indexed costs 1 instead of 2 and the
# Igros moat stops being a moat, with no crash, no error and no failing assertion
# anywhere. Set equality on the names, equality on every value, both directions.
echo "Checking the two terrain enum tables agree (ADR-0226)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_rom_terrain_tables.py); then
    echo "ABORT: RomTerrain.gd and fft_exporter's terrain enums disagree (ADR-0226)."
    echo "       A wrong byte does not crash -- it routes. Fix both copies together."
    exit 1
fi

# Pre-flight: goal #5's addon net -- ELEVEN arms over every root this repo calls
# portable. 1 no SYSTEM reach, 2 no host autoload NAME, 2b no host autoload named as
# a node-path STRING, 3 no `#include` leaving the addon roots, 4 no
# `[shader_globals]` name the package does not declare (4b and only a NON-system
# addon may declare one), 5 no SIBLING addon's `class_name` outside the kernel and
# the platform port, 6 no quoted `res://` literal addressing a target outside every
# addon root, 7 no `class_name` DECLARED outside every addon root -- arm 5 one level
# out, and the TYPE axis of arm 6's sentence -- 8 `plugin.cfg`'s `deps=` names every
# sibling addon arm 5 measures a reach into and no others, 8b the rig binary the
# dependency CLOSURE requires is registered beside the subject's own `engine=`
# (#1241: nothing in tools/ read `deps=` at all before it, and rig.sh picks the
# binary from the closure, so a `deps=` edit is a possible ENGINE change).
#
# The count in this banner has been wrong twice -- it read "five" while the file
# held six of them -- and spelling it out did not stop it: the tool's header then read
# "SEVEN" over an eight-label list. Both words are now recounted from the tool's own
# enumeration by `test_the_spelled_arm_count_equals_the_enumerated_arms`, which reads
# THIS file too. Do not hand-edit either word (#722, #658, #648).
#
# It was registered here by ADR-0175, and the reason is the finding: arms 3 and 4
# were BUILT (ADR-0169 dec. 5, ADR-0171 dec. 5) into a file `run_all_tests.sh` has
# never invoked. ADR-0003 dec. 7 measured that exact hole and named this exact file
# -- "the 8 that never run include check_addon_portability.py, the existing addon
# guard" -- and it stayed true across two more arms. A guard the suite does not list
# is a guard nobody runs; #555 and #565 are the same shape on other files.
# Pre-flight: every quoted `res://` SOURCE path in the tree resolves to a file that
# exists. Extraction #3's pass 6 re-pointed 284 of them in one commit, and the
# failure mode is the one ADR-0157 -> Soft spots, Spike A measured headful: a .tscn
# whose script ext_resource points at a moved path STILL LOADS, mounts the node
# stripped of its script, and the engine exits 0. rc is not the verdict and watching
# the scene come up is not a test -- so this reads the path instead of the outcome.
echo "Checking every quoted res:// source path resolves..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_res_paths.py); then
    echo "ABORT: a res:// source reference points at a file that does not exist."
    exit 1
fi

# Pre-flight: the OTHER half of the same failure. `check_res_paths.py` above reads
# quoted `res://` literals; a Python tool addresses the tree as
# `Path(__file__).parent.parent / "assets" / "sprites" / "x.json"`, which is not a
# res:// literal and is invisible to every guard that exists. #744 measured what
# happens when such a path goes stale: for a GUARD it is loud (four went red, one of
# them on this move's own commit), for a GENERATOR it is silent -- the tool writes to
# the dead address, the committed copy drifts, and rc stays 0. Same shape for
# `asset_census.py`'s booking prefixes: a prefix that matches nothing never fires.
# Pre-flight: the per-frame combat snapshot carries 34 of the unit record's 101
# fields (GPUCombatPacker.SNAPSHOT_HOT_UNION), because building all 101 for 16 units
# every ticking frame cost ~1.8 ms and never decayed as units died (W1). That trade's
# failure mode is SILENT: a consumer reading a field the union omits gets
# `state.get("x", default)` -- the default, no error, no crash, just a battle that
# behaves slightly wrong forever. Nothing else in this suite can see it, because
# every value that IS present is correct. This walks the call graph out of
# `_check_state_changes()` and asserts the union covers every read.
echo "Checking the per-frame snapshot union covers every field the combat path reads..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_snapshot_union.py); then
    echo "ABORT: a field is read on the per-frame combat path but is not in"
    echo "       GPUCombatPacker.SNAPSHOT_HOT_UNION -- it silently returns .get()'s"
    echo "       default at runtime. See tools/check_snapshot_union.py."
    exit 1
fi

echo "Checking hardcoded tool paths resolve and census booking prefixes match..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_tool_paths.py); then
    echo "ABORT: a tool names a tree path that does not exist, or the asset census holds"
    echo "       a booking prefix that matches nothing. Repoint it -- see #744's LOUD/SILENT"
    echo "       register in tools/check_tool_paths.py."
    exit 1
fi

echo "Checking host reaches INTO a mount scene's nodes are declared crossings (ADR-0217 dec. 3)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_mount_node_paths.py); then
    echo "ABORT: a host file names a node inside an addon's mount scene that no longer"
    echo "       exists, or reaches one without declaring it. Renaming such a node returns"
    echo "       null with NO engine diagnostic, and the two ScenarioDialogueBoxPool sites"
    echo "       swallow that null by design -- the box still draws, its anchor just moves"
    echo "       ~65-76 px. See tools/check_mount_node_paths.py."
    exit 1
fi

echo "Checking addon portability -- ELEVEN arms of goal #5 (ADR-0151/0169/0171/0175/0184/0190/0191/0223)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_addon_portability.py); then
    echo "ABORT: an addon reaches a system, names a host autoload -- as a bare identifier"
    echo "       or as a node-path string -- includes outside its root, binds or declares a"
    echo "       shader global it does not own, names a sibling addon's class_name,"
    echo "       addresses a res:// path outside every addon root, declares a \`deps=\` that"
    echo "       does not match the reach arm 5 measures, or boots a rig binary its own"
    echo "       \`engine=\` does not name and ARM8_CLOSURE_ENGINE does not register (goal #5)."
    exit 1
fi
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_check_addon_portability); then
    echo "ABORT: the addon-portability arms lost their seeded red arms (ADR-0175)."
    exit 1
fi

# UI is mid-extraction: its 122 members still live in `src/ui3/`, so arm 2a above --
# which only reads UNDER an addon root -- cannot see a bare `Tune.` in them. #1268
# routed all 107 through `ExMateriaPlatform.TunePort`; this owns the window until the
# `git mv`, at which point arm 2a takes over and this block is DELETED (the guard
# fails loudly on an empty subject rather than going quietly green).
if ! (cd "$PROJECT_DIR" && uv run python tools/check_ui_tune_port.py); then
    echo "ABORT: a UI member names the host autoload \`Tune\` -- an addon cannot ship"
    echo "       \`project.godot\` entries (ADR-0262 dec. 6), so the name would not"
    echo "       resolve in any project that does not autoload it. Route it through"
    echo "       \`const TunePort = ExMateriaPlatform.TunePort\` (ADR-0211 dec. 4)."
    exit 1
fi
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_check_ui_tune_port); then
    echo "ABORT: the TunePort guard lost a seeded arm -- including the STATEFUL-blanker"
    echo "       arm, without which a \`Tune.\` in a doc block reds a clean tree (ADR-0306 §4)."
    exit 1
fi

# `Tune` was never the problem; it was ONE OF SEVEN (ADR-0308). All eight stranger rigs
# declare an EMPTY `[autoload]` block, so a member may reach NO autoload identifier at
# all -- not just `Tune`. Six stood at ADR-0308 across 49 lines; ONE stands today across
# 1, after #1274 (EventBus -> EventPort), #1263 (PSXDisplay -> DisplayPort), #1271
# (DebugConfig -> UIDebug's slugs), #1272 (CharacterCatalog -> UIRoster) and #1273
# (SfxRouter -> INVERTED onto three signals, named by `src/scenes/UIWiring.gd`). The one
# left is `UI3Registry`, UI's OWN autoload, which dissolves into a preload at the move --
# there is no port to build for it. This is a RATCHET, not a gate: the suite stays green
# while they are paid off one port at a time, and it reds if one GROWS, if a NEW one
# appears, or if a debt is paid and its BASELINE row is left behind.
# Deleted with the `Tune` block above at the move.
if ! (cd "$PROJECT_DIR" && uv run python tools/check_ui_autoload_reach.py); then
    echo "ABORT: a UI member's reach to a host autoload grew, or a new one appeared."
    echo "       An addon cannot ship \`project.godot\` entries (ADR-0262 dec. 6) and every"
    echo "       stranger rig declares ZERO autoloads, so the identifier is undefined there."
    echo "       Route it through a port; do not raise the BASELINE to make this pass."
    exit 1
fi
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_check_ui_autoload_reach); then
    echo "ABORT: the arm-2a ratchet lost a seeded arm -- including the PAID-DOWN arm,"
    echo "       without which a stale BASELINE row silently re-admits a reach (ADR-0308)."
    exit 1
fi

# Goal #5's OTHER scorer, and the join between the two halves (ADR-0232).
# `score_goals.mechanical(5)` reads a BUDGET half (the cross-system reach count the
# block above also scores) and an INSTALL half (the stranger rig's declared debt), and
# `_walk_roots.RIGS` is the register that says which rig belongs to which addon --
# three arms, all of them raises, all seeded red in this file.
#
# 🔴 REGISTERED HERE BECAUSE IT WAS NOT. `tools/test_score_goals.py` landed with
# ADR-0228 dec. 5 carrying 11 seeds and NOTHING HAS EVER RUN IT: this script names every
# tools/test_*.py it runs, one line each, and there is no discovery loop. That is the
# third firing of the rule twenty lines below -- "A guard the suite does not list is a
# guard nobody runs" -- after ADR-0175's arms 3 and 4 and ADR-0003 dec. 7 before it.
# The census (64 of 88 tools/test_*.py invoked by nothing, most of them plausibly
# ROM-gated but none of them DECLARED so) is issue #876, not fixed here.
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_score_goals); then
    echo "ABORT: goal #5's conjunction or the stranger-rig register lost a seeded arm"
    echo "       (ADR-0232), or goal #7's comment model did (ADR-0228 dec. 5)."
    exit 1
fi

# Pre-flight: the TILE-DOOR register — ADR-0164 dec. 4 criterion 3, added by ADR-0166
# dec. 4. No `Battlefield` member reachable from OUTSIDE the addon may have `Tile` in a
# return or signal-payload position. It is the INBOUND half of goal #5 and the block
# above cannot see it: `check_addon_portability` arm 1 scores OUTBOUND reach, and
# `score_goals.mechanical(goal=5)` has no inbound term at all.
#
# Criteria 1 and 2 cannot do this job either — both are satisfied by retyping three lines
# while 56 sites still hold a live `Tile`, which is the hole ADR-0166 dec. 4 was written
# into. This one is PRODUCER-side because that is the only side that is decidable, and it
# makes the held-node shape impossible rather than merely counted.
#
# Registered here, and that placement is the point: ADR-0175's finding was that arms 3 and
# 4 were BUILT into a file this suite had never invoked, and ADR-0003 dec. 7 had already
# measured that exact hole naming this exact file. A guard the suite does not list is a
# guard nobody runs.
echo "Checking the Tile-door register -- goal #5's inbound half (ADR-0164 dec. 4 crit. 3)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_lattice_doors.py); then
    echo "ABORT: a Battlefield member hands a Tile across the addon boundary and is not on"
    echo "       DOOR_BURN_DOWN, or a listed row has gone stale (ADR-0166 dec. 4)."
    exit 1
fi
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_check_lattice_doors); then
    echo "ABORT: the Tile-door register lost its seeded red arms (ADR-0166 dec. 4)."
    exit 1
fi

# The duck-typed-door register -- criterion 2, the OUTBOUND half, and it is registered
# here BEFORE the port it enforces exists. ADR-0192 dec. 1: the port and holder 4 together
# consume this register's entire population, so a register written afterwards is a scanner
# that reads zero -- indistinguishable from one that is broken -- and the only independent
# evidence that its receiver-type inference is right (ADR-0170 dec. 5's hand-counted 15,
# ADR-0192's 27 = 15 + 12) exists only until the port lands. It reproduced 27/15/12 on its
# first run; PORT_BURN_DOWN is that count frozen, and the port drives it to 0.
echo "Checking the duck-typed-door register -- criterion 2 (ADR-0164 dec. 4, ADR-0192)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_lattice_ports.py); then
    echo "ABORT: a site reaches the battlefield lattice through a receiver that is not"
    echo "       provably \`Lattice\` and is not on PORT_BURN_DOWN, or a listed row has gone"
    echo "       stale (ADR-0192 dec. 2/3/7). A STALE row is what SUCCESS looks like -- the"
    echo "       port deletes this population -- so delete the row, do not restore the site."
    exit 1
fi
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_check_lattice_ports); then
    echo "ABORT: the duck-typed-door register lost its seeded red arms (ADR-0192 dec. 1)."
    exit 1
fi

# The published-symbol register -- criterion 1, and it is registered here BEFORE the enum
# it grades moves. ADR-0196 dec. 1 applies ADR-0192 dec. 1's ruling to the third criterion:
# after `Tile.HighlightType` becomes `CellMarking.Kind`, all ten of `Tile`'s host lines are
# gone, so a scanner that merely fails to RECOGNISE the old spelling is indistinguishable
# from a correct one. It reads 30 sites over 14 rows on its first run -- `Tile` 10,
# `TileCursor` 12, `CursorController` 8, and 0 for `TerrainIndex`, `MapComposer` and
# `PlayerCamera`. PUBLISH_BURN_DOWN is that count frozen, and the enum move is graded by
# watching `Tile`'s two rows go STALE.
echo "Checking the published-symbol register -- criterion 1 (ADR-0164 dec. 4, ADR-0196)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_lattice_publish.py); then
    echo "ABORT: a forbidden \`Battlefield\` \`class_name\` is named as a TYPE outside the"
    echo "       addon and is not on PUBLISH_BURN_DOWN, or a listed row has gone stale"
    echo "       (ADR-0196 dec. 4). A STALE row is what SUCCESS looks like -- the move"
    echo "       deletes the reference -- so delete the row, do not restore the site."
    exit 1
fi
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_check_lattice_publish); then
    echo "ABORT: the published-symbol register lost its seeded red arms (ADR-0196 dec. 1)."
    exit 1
fi

# The resource-path register -- criterion 4, the SECOND SPELLING of criterion 1's axis
# (ADR-0205). A host file naming `res://addons/exmateria_battlefield/...` reaches INTO the
# addon exactly as `var c: MapComposer` does; only the spelling differs. Both this and the
# publish register above are axis A, and both are a DIFFERENT NUMBER from the install
# register below -- ADR-0202 dec. 1 forbids reporting either axis as the other.
#
# 🔴 The population was called "the install term" by check_lattice_publish's own output and
# by ADR-0196 dec. 8, and the direction was wrong: delete the whole host tree and all 138
# rows stay behind, in the host. ADR-0205 corrects it and owns it.
#
# Registered BEFORE the moves it grades (dec. 7, applying ADR-0192 dec. 1 a third time):
# 115 of the 138 rows are `assembly/MapComposer.gd` and that population is about to move
# behind a host-owned indirection, after which a scanner blind to the old spelling is
# indistinguishable from a correct one. It reads 138 sites over 132 files on its first run
# -- tests/ 122, assets/ 11, tools/ 3, src/ 2 -- plus 1 declared mount (ADR-0204's
# `CombatCamera.tscn`). `tests/` ENFORCES here, unlike criterion 1's arm 2: ADR-0196
# dec. 3's reason is about `classify()` returning None for a test file, and a PATH needs no
# classifier. With src/ at 2 of 139, a reporting-only tests/ arm would leave 88% unscored.
# ADR-0217 dec. 4: the subject is a MAPPING now, not the one hardcoded addon above. It
# grades every addon in `SUBJECTS` -- each with its own section, its own two arms and its
# own verdict -- and the rc is the OR, because one addon at 0 and another carrying debt
# are two readings and not an average. `exmateria_sprite_rig` is seeded BEFORE extraction
# #4's move (ADR-0192 dec. 1, a fourth firing), so its one declared mount reads DEAD! at
# rc 0 until #744 lands it; that DEAD -> live flip is the evidence the mount landed rather
# than evidence the scanner changed.
echo "Checking the resource-path register -- criterion 4, host -> addon (ADR-0205)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_lattice_scene.py); then
    echo "ABORT: a file outside a graded addon names an \`res://addons/<that addon>/\`"
    echo "       path and is not on that addon's SCENE_BURN_DOWN, or a listed row has"
    echo "       gone stale (ADR-0205). Read the FAILING SUBJECT's section -- the rc is"
    echo "       the OR across subjects and does not say which one fired. A STALE row is"
    echo "       what SUCCESS looks like -- the move deletes the reach -- so delete the"
    echo "       row, do not restore it."
    exit 1
fi
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_check_lattice_scene); then
    echo "ABORT: the resource-path register lost its seeded red arms (ADR-0205)."
    exit 1
fi

# The install register -- goal #5's addon -> host direction, and the OPPOSITE axis from the
# three criteria above. ADR-0202 dec. 1: an addon can satisfy every one of ADR-0164 dec. 4's
# criteria and still fail to LOAD in a bare project, which is exactly today's state. The
# target (dec. 2) is a bare Godot 4.8-COMPOSITOR-FORK project holding `exmateria_schema`,
# `exmateria_platform` and the addon, and nothing else.
#
# Registered BEFORE the moves it grades (dec. 10, applying ADR-0192 dec. 1 through ADR-0196
# dec. 1): once `tile_overlay.tres` lives inside the addon, a scanner that never learned to
# read `res://` out of a `.gd` reports the same 0 as a correct one. It reads 49 sites over 29
# rows on its first run -- 11 asset reaches, 8 input actions over 12 rows, 6 shader globals --
# and INSTALL_BURN_DOWN is that count frozen. `check_addon_portability.py` above reports OK
# across all eleven asset sites: no arm of it reads a `res://` path out of a `.gd` body or a
# `.tscn` `ext_resource`, which is why this guard exists beside it rather than inside it.
echo "Checking the install register -- goal #5, addon -> host (ADR-0202)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_addon_install.py); then
    echo "ABORT: the addon depends on something a bare fork+kernel+port project does not"
    echo "       have and it is not on INSTALL_BURN_DOWN, or a listed row has gone stale"
    echo "       (ADR-0202). A STALE row is what SUCCESS looks like -- the move removes the"
    echo "       dependency -- so delete the row, do not restore the reach."
    exit 1
fi
if ! (cd "$PROJECT_DIR/tools" && uv run python -m unittest test_check_addon_install); then
    echo "ABORT: the install register lost its seeded red arms (ADR-0202 dec. 10)."
    exit 1
fi

# NOTE (merge of the code line into `main`, 2026-08-27): the code line also carried a
# `check_roster_base_inheritance.py` block here. It is NOT reinstated — ADR-0180 deleted
# that guard on `main` and replaced it with `check_path_extends.py` below, which checks the
# same ADR-0004 convention across EVERY path-extends in the walk rather than naming the two
# roster files. The script does not exist in this tree; re-adding the block aborts the suite.

# Pre-flight: a script that is EXTENDED BY PATH must not declare a class_name
# (ADR-0004). A class_name base hits Godot's stale-global-class-cache trap
# ("Could not find base class X") on a fresh checkout. This replaced the guard that
# named the roster files, which ADR-0180 deleted — the CONVENTION outlived them and
# is now checked across every path-extends in the walk. Pure Python, no Godot needed.
echo "Checking path-extended base scripts stay class_name-less (ADR-0004)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_path_extends.py); then
    echo "ABORT: a path-extended base script declares a class_name (ADR-0004)."
    exit 1
fi

# Pre-flight: the per-side rosters stay RETIRED (ADR-0180) — no autoload, no script,
# no use, no committed seed. ADR-0066 dec. 1 demoted the roster in 2026 and nothing
# enforced it, so the code stayed the inverse for a year and put a hand-invented
# "Marcus" on a Formation screen. Pure Python, no Godot needed.
echo "Checking the per-side rosters stay retired (ADR-0180)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_rosters_retired.py); then
    echo "ABORT: a retired roster store is back (ADR-0180)."
    exit 1
fi

# Pre-flight: UnitProgression stays one durable Resource shared by reference
# (ADR-0005) — never a Node, and the deleted field-by-field copy methods
# (_sync_progression_from_roster / update_unit_from_combat / progression.duplicate)
# never come back. Pure Python, no Godot needed.
echo "Checking UnitProgression stays a shared-by-reference Resource (ADR-0005)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_unit_progression_resource.py); then
    echo "ABORT: UnitProgression regressed the one-representation contract (ADR-0005)."
    exit 1
fi

# Pre-flight: the three per-taxonomy sprite-stretch channels stay wired on all
# three surfaces (ADR-0044) — PSXDisplay setter, project.godot [shader_globals],
# and a shader `global uniform`. A half-wired channel scrubs a value nothing
# reads (or reads a global never set). Pure Python, no Godot needed.
echo "Checking sprite-stretch channels stay fully wired (ADR-0044)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_sprite_stretch_globals.py); then
    echo "ABORT: a sprite-stretch channel is half-wired (ADR-0044)."
    exit 1
fi

# Pre-flight: unit sprite layers stay shader-multiplexed on one mesh (ADR-0019)
# — SpriteLayerManager toggles wep_enable/eff_enable uniforms, never per-layer
# Node3D `.visible` or a per-layer MeshInstance3D, and the shader reads them.
# Pure Python, no Godot needed.
echo "Checking sprite layers stay shader-multiplexed on one mesh (ADR-0019)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_sprite_layers_one_mesh.py); then
    echo "ABORT: sprite layers regressed toward scene-tree composition (ADR-0019)."
    exit 1
fi

# Pre-flight: the body sprite ID stays subject-qualified `body_sprite_id`
# (ADR-0027) — no bare `.sprite_id` dot-access and no bare `sprite_id` field on
# Unit/Character. (String dict keys `"sprite_id"` are a separate UI3
# view-model vocabulary and are intentionally not touched.) Pure Python.
echo "Checking body sprite ID stays subject-qualified (ADR-0027)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_body_sprite_id_naming.py); then
    echo "ABORT: a bare sprite_id leaked back (ADR-0027)."
    exit 1
fi

# Pre-flight: the over-unit feedback HUD stays observation-only (ADR-0063) — its
# billboard classes never read BattleUnitData / write battle state, connect to
# CombatLoop signals, and render as OT-depth combat_visuals. Pure Python.
# Pre-flight: `PlayerCamera.camera_mode` is never ASSIGNED from outside the rig — every
# caller asks for the EDGE it wants (request_takeover/release_takeover, or the by-fiat
# enter_takeover_framing/resume_cursor_framing). The setter only emits a signal, so an
# assignment flips the mode and silently skips the framing work the edge owns; that shipped
# at BOTH of NavigatorMain's sites and produced two separate reported defects. Pure Python.
echo "Checking camera_mode is written only by the rig..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_camera_mode_edges.py); then
    echo "ABORT: camera_mode assigned outside PlayerCamera — use a named edge method."
    exit 1
fi

echo "Checking feedback HUD is observation-only + OT-depth billboards (ADR-0063)..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_feedback_hud.py); then
    echo "ABORT: feedback HUD violates ADR-0063 (observation-only / combat_visuals / OT depth)."
    exit 1
fi

# Pre-flight: ADR-0013's two deferred bit-packed fields (anim_flags / rsm_flags in
# effects.json) stay RAW int and out of AbilityView — their bit semantics are not
# yet reverse-engineered, so there is nothing faithful to decode into (unlike
# weapon_flags / elements). This locks the deferral: raw in effects.json + absent
# from the generator whitelist. If it fails because you decoded them, amend
# ADR-0013 + the guard together. Pure Python, no Godot needed.
echo "Checking ADR-0013 deferred flags (anim_flags/rsm_flags) stay raw + un-surfaced..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_adr0013_deferred_flags.py); then
    echo "ABORT: anim_flags/rsm_flags deferral broken (ADR-0013). Decoding needs an ADR amendment."
    exit 1
fi

# Pre-flight: the world map's generated asset hub is present and well-shaped.
# `assets/world_map/` is gitignored, written by tools/parse_world_map.py, and
# SHARED by every worktree through a symlink — so nothing in a checkout, a diff
# or `git status` reports on it, and its two failure modes both surface as a
# cluster of ~10 unrelated-looking red Godot scenes:
#   * stale  — a hub older than the generator's `start_menu`/`place_list`/`town`/
#              `routes[].waypoints` keys still loads and still renders, so
#              WorldMapPrimitives.gd reads `polyline` and works while
#              WorldMapTravel.gd:155 reads `waypoints` on the SAME dict and throws.
#   * absent — merging PR #657 (which untracked the path) DELETES the symlink in
#              a worktree that still has it, until the linker is re-run.
# Both were mis-diagnosed as a branch conflict three sessions running. This says
# it once, in one line, before 692 scenes say it badly. Pure Python.
echo "Checking the world-map asset hub is present and current..."
if ! (cd "$PROJECT_DIR" && uv run python tools/check_world_map_assets.py); then
    echo "ABORT: assets/world_map is missing or stale — the world-map tests cannot mean anything."
    exit 1
fi

# Rebuild Godot's import / global-class cache from the current source BEFORE running
# any scene. The direct-scene runner does NOT reparse a `class_name` script that
# another script extends — it loads the cached version — so a fresh edit to a base
# (e.g. GPUCombatTestBase / CombatHost) would otherwise be ignored and subclasses
# would parse against the stale base ("Identifier not declared"). `--import` scans,
# reimports, and exits cleanly (it is NOT --headless, so it is allowed). It can exit
# non-zero on benign asset warnings; don't let that abort the suite.
# --- the gate (#453, ADR-0158) -----------------------------------------------
# Every static guard above has passed. Everything below is Godot, once per test,
# 687 times, in one process at a time.
#
# THE SENTINEL BELOW IS LOAD-BEARING (#823). Every guard above aborts with `exit 1`,
# so this line is printed if and only if the whole pre-flight passed — which makes it
# the only way a CALLER can tell "the guards ran and passed" from "a guard aborted
# several hundred lines up". Two consumers depend on it and both existed as bugs first:
#   * `tools/run_tests_parallel.py`'s ABORT message, which used to say a guard failed
#     without saying WHICH, leaving the reader to scroll;
#   * `tools/test_run_tests_parallel.py`'s `SequentialArmIsGated`, whose two
#     stdout-reading arms sit downstream of every guard here and therefore reported an
#     aborting guard as a defect in the GATE — four misreads in one evening.
# It is printed BEFORE the `--preflight-only` branch so both invocations carry it.
echo "PRE-FLIGHT COMPLETE: every static guard above passed."
if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
    echo ""
    echo "--preflight-only: every static guard above passed. Test loop skipped."
    exit 0
fi
if [[ "$SEQUENTIAL_OPT_IN" != 1 ]]; then
    echo ""
    echo "======================================"
    echo "  STOPPING: this is the SEQUENTIAL arm — 61 minutes."
    echo "======================================"
    echo ""
    echo "  Run the suite with the parallel runner instead (~10 min at N=8,"
    echo "  5.6-5.9x, adopted in ADR-0158 / #453 — same verdict reader, proven"
    echo "  identical across three repeats):"
    echo ""
    echo "      uv run python tools/run_tests_parallel.py"
    echo ""
    echo "  Iterating rather than verifying? Run only what the change can reach:"
    echo ""
    echo "      uv run python tools/scoped_tests.py --since <trunk> --run"
    echo ""
    echo "  The pre-flight guards above have already run; that is all this"
    echo "  invocation does now. If you genuinely want the slow arm — retaking"
    echo "  the ADR-0158 diff, or a SEQUENTIAL_LANE entry — say so:"
    echo ""
    echo "      bash tests/run_all_tests.sh --sequential"
    echo ""
    exit 2
fi

echo "Rebuilding Godot import cache (so edited class_name scripts load)..."
(cd "$PROJECT_DIR" && timeout 300 "$GODOT" --path . --import >/dev/null 2>&1) || true

# --- machine-state sentinel, open bracket (ADR-0281 / #1149) -----------------
# NOT a pre-flight guard, and it could not be one: it asks what the RUN did, so it has
# to bracket the test loop. Opened here rather than above the gate for the same reason
# the import-cache rebuild is here — everything from this line down is test-loop setup.
MACHINE_STATE_FILE="$LOG_DIR/machine_state.json"
mkdir -p "$LOG_DIR"
(cd "$PROJECT_DIR" && uv run python tools/machine_state_sentinel.py \
    --snapshot "$MACHINE_STATE_FILE") || true

# All tests except GPUDashPerfTest (benchmark, not a test)
TESTS=(
    # Pure-logic guard (no GPU): the shared JSON-asset loader (JsonAsset) that
    # the XDatabase-shape data stores call for open/parse/error handling —
    # root/key load, missing-key {}, Array-key guard, missing-file/malformed {}.
    "ChildSpawnSuppressionTest"
    "ColourRibbonResolveParityTest"
    "EffectAnimationDisplayLengthTest"
    "EffectParticleRendererColorCurveRefreshTest"
    "JsonAssetTest"
    # Pure-logic guard (no GPU): the gambit lab's SYNTHESIZER (GambitCellSynth, ADR-0275
    # decs. 1/2/8-12) — the straddle arithmetic lands ON the kernel's boundary (HP_BELOW(50)
    # straddles 49/50 because the kernel tests `<`), placement REFUSES off-board instead of
    # nudging, every mirror moves exactly ONE knob within its declared footprint, every refusal
    # says why, the ladder refuses a knob collision and an over-long climb, the tick budget is
    # derived from the actor's Speed (a throw cell runs at Speed 8 and needs 450 ticks), every
    # roster has both teams and <= 8 units, and the encoder-coverage measurement reports no
    # UNDECLARED gap. The expensive half — does the kernel agree — is the live arm's
    # (`--cell=`), which dec. 15 deliberately keeps out of the suite.
    "GambitCellSynthTest"
    # Pure-logic guard (no GPU): the DERIVED story timeline (RosterTimeline) that replaces
    # the four hand-authored mutation keys -- the Academy grants SIX generics and Gariland
    # grants none (the authored table had it backwards), Mustadio guests at Zaland before
    # joining at Goug, and seeking root 59 installs var[110]=10 so the world map offers
    # node 59 instead of chaining the walk back through Beoulve Residence. Ends by writing
    # the derived state into the LIVE Campaign store and asking what the map offers.
    "RosterTimelineTest"
    # Pure-logic guard (no GPU): the Tune tunable registry (ADR-0068) — the
    # coalescing bind/override read, staging-file save/load round-trip,
    # is_dirty/commit, and the bind lifecycle (immediate apply, re-apply on
    # change, auto-drop on owner tree-exit).
    "TuneTest"
    # Guard (no GPU): every tunable OWNER registers itself at its own boot path
    # (_static_init at class load / _ready for an autoload), and Tune.reset()
    # leaves those declarations standing — the pair that let #535 delete
    # Tune.register_all() and its list of fifteen owner paths (ADR-0173). The
    # owner set is DISCOVERED by walking the tree, so this test names no owner and
    # no slug. Catches a revert to a central replay, and an owner whose boot path
    # stops binding (which would leave a get_value() pull-read asserting, R5).
    # Static half: tools/check_tune_owner_self_registration.py, above.
    "TuneOwnerSelfRegistrationTest"
    # Guard (no GPU): extraction #3's 46 files are at their addon address and the two
    # moved scenes BIND THEIR SCRIPTS. tools/check_move_manifest.py asserts set
    # equality statically; this asserts the half a static check cannot reach --
    # instantiate each scene and read get_script() back off the nodes, because a
    # .tscn pointing at a moved script loads clean and stripped (ADR-0157 Spike A).
    "BattlefieldAddonAddressTest"
    # Guard: #589 — the assembler block that carries Battlefield's three outputs to
    # the host systems that consume them, now that the addon names none of them.
    # check_addon_portability.py enforces the SEVERANCE (the reaches are gone and
    # their ARM1_BURN_DOWN rows with them, so re-adding either goes red); this is
    # the half no static guard can see, and its failure mode is SILENT — a missed
    # wiring site does not error, the map just stops tinting during effects and
    # the sky keeps the fallback blue. Four arms on a duck-typed composer (replay,
    # connect, the empty-gradient case, the resolved gradient) plus one on a REAL
    # MapComposer that auto-built its map, without which the other four are a
    # closed loop over a fake this file wrote.
    "BattlefieldWiringTest"
    # Guard (no GPU): #588 — the two port façades (TunePort, DisplayPort) the
    # battlefield addon names in place of the Tune and PSXDisplay autoloads.
    # check_addon_portability.py enforces the RE-POINT statically (arm 2 loses 78
    # rows, arm 5 gains them as a counted platform dependency). This is the half no
    # static guard can reach: what the façade answers when the autoload is NOT in the
    # tree — the state the whole re-point exists for, and the one state no scene in
    # this repo boots in. Manufactured by renaming the autoload node, which is
    # truthful: _resolve() is a get_node_or_null against that name.
    "TunePortTest"
    # Guard (#1271): `src/ui3/UIDebug.gd` — UI's three diagnostic flags, read through
    # `TunePort` instead of the `DebugConfig` autoload. All three were ALREADY `Tune`
    # slugs (`DebugConfig._dbg_get`), so UI was reaching a host autoload to read a
    # registry the port already exposes; `addons/exmateria_sprite_rig/install/RigDebug.gd`
    # solved the same problem at #744 and is the shape. check_ui_autoload_reach.py
    # enforces the SEVERANCE and S1 enforces that `_static_init` calls
    # `register_tunables`; neither can see the failure this test exists for — a slug
    # READ but never BOUND. `TunePort.get_value`'s fallback answers only when the PORT
    # is absent, so with the port present the read is R5's pull-read and asserts; a
    # GDScript error then returns the TYPE DEFAULT, which does not crash, it silently
    # disables the feedback HUD. Seeded by deleting one `bind`: the arm reds for that
    # slug alone and the log carries the R5 assert. Arm order is load-bearing (the
    # registration arm runs FIRST, because reading a `DebugConfig` property binds
    # lazily and would make it vacuous), and the absent arm seeds all three OFF their
    # defaults first, for the reason #1263 records.
    "UIDebugSlugTest"
    # Guard (#1272): `src/ui3/UIRoster.gd` — UI's four roster reads, severed from the
    # `CharacterCatalog` autoload identifier. The catalogue had ALREADY ruled on the
    # spelling: `CharacterCatalog.live()` is an injection, documented as the default
    # "rather than a fourth verb over the port", so this door is a namespace of statics
    # over `live()`, not another port. check_ui_autoload_reach.py proves the six bare
    # reaches are gone; it cannot see what the door ANSWERS with no catalogue installed,
    # which is the only state the severance exists for. Three of the four fallbacks are
    # EMPTY (`[]`, `[]`, `null`) and a bare test scene boots an empty catalogue, so the
    # absent arm is vacuous unless a roster is seeded first -- arm 1 registers a
    # character, marks it owned, and asserts the verbs see it. Arm 3 asserts `live()`
    # resolves per call and caches nothing: a door that cached would pass arms 1 and 2
    # by ordering and then answer a stale catalogue in any host that mounts late.
    # Seeded three ways -- fallback flipped to `true`, `_live()` given a cache, and the
    # seed removed -- reds the absent arm, arm 3, and the vacuity guard respectively.
    "UIRosterDoorTest"
    # Guard (#1273): UI's five `SfxRouter` reaches, INVERTED rather than routed through
    # a door. #1263/#1271/#1272 all answered their autoload with a port because they
    # READ host state UI needs to render; this one only WRITES an effect UI never
    # consumes, and the thing written is a CUE NAME -- host vocabulary
    # (`GambitBattle.gd` plays "invalid" from seven of its own sites). `TileCursor` had
    # the identical reach at #589 and `BattlefieldWiring` is the precedent this copies.
    # The failure mode a static guard cannot see is a signal that is too WIDE:
    # `DialogueBox.advanced` already existed, fires on DISMISSAL, and is one word away
    # from `advance_page` -- folding the page-flip onto it would compile, pass the
    # ratchet, and blip on every close. Arms 1-2 pin that. Cues are observed through
    # `SfxRouter.cue_requested`, which is emitted BEFORE backend dispatch precisely so a
    # test with no SPU can see them; the return token is 0 both on an unknown cue and on
    # an absent backend, so asserting it would be vacuous. Seeded five ways, all run.
    "UICueInversionTest"
    # Guard (#743, ADR-0217 dec. 9): the sprite rig's CONTENT PORT — seven scalar
    # queries over FOUR key spaces, asserted BY VALUE against known rows because
    # every int key space typechecks against every other one. Also holds the half no
    # static guard can reach: what the port answers with no adapter in the tree,
    # manufactured by renaming the autoload the way TunePortTest does.
    "SpriteRigContentPortTest"
    # Guard (#744): the sprite rig's ONE written-out enum value. `UnitDisplay`'s
    # reaction default was `ReactionType.Type.TAKING_DAMAGE` — a compile-time reach
    # from the addon into `Battle`, and one of ADR-0215 P3a's 27. The rig never
    # branches on a reaction type, so #744 writes the number out and this test is
    # the seam that can see BOTH sides: it fails if the host renumbers the enum, and
    # its second arm asserts the ABSENCE of the reach so re-introducing it cannot
    # make the first arm pass quietly.
    "UnitDisplayReactionDefaultTest"
    # Guard (no GPU): PSXDisplay.live_par is a facade over the Tune
    # "render.pixel_aspect" tunable (ADR-0068 slice 2) — preserved getter, setter+dedup,
    # and live_par_changed, PLUS a Tune override driving it. Pairs with
    # PSXDisplaySingleSourceTest (which locks the project.godot-sourced default).
    "TunePsxParTest"
    # Guard (no GPU): the PSXDisplay single-source-of-truth seam (ADR-0036 Option
    # A + ADR-0068 slice 2) — the shader-backed mirrors carry NO rival default:
    # the three stretch mirrors equal their project.godot [shader_globals] value,
    # and live_par equals the Tune-coalesced override-over-that-default. Pairs
    # with TunePsxParTest.
    "PSXDisplaySingleSourceTest"
    # Guard (no GPU): #590 — `psx_camera_angle` is the PORT's, both halves.
    # `set_camera_angle` must drive `live_camera_angle` AND the two readers that
    # used to poll `DebugConfig.psx_camera_angle_12bit` (`Unit._build_view` for
    # Battle, `CameraRelativeRenderer` for Sprite Rig), and Debug must no longer
    # declare the member. check_addon_portability.py enforces the SEVERANCE (the
    # reach, and the burn-down row that goes stale with it); this is the half no
    # static guard can see -- a mirror that quietly stopped updating leaves every
    # guard green and freezes every unit on its spawn-time pose octant.
    "CameraAnglePortTest"
    # Pure-logic guard (no GPU/scene): EffectScoreModel — the projection that turns
    # a parsed EffectData into the Effect Studio score (phase sections + lanes +
    # spans on one absolute frame axis). Particle spans `[kf[N-1].time, kf[N].time)`
    # offset per phase (phase1→0, for_each→p1d, phase2→p1d+phase2_delay); screen/
    # palette color lanes with cumulative-duration spans; stable per-keyframe
    # identity + authored↔absolute coords. The testable core the timeline view glues.
    "EffectScoreModelTest"
    # Pure-logic guard (no GPU/scene): SPACER rendering (ADR-0087) — the disable-equivalence
    # verdict (SpacerVerdicts), the `fields.spacer` + `fields.enabled` projection through build +
    # live paths,
    # the restyle-on-flip layout flag from the colour channels, and grounding on real
    # E317/E015. FIFTH amendment: an enabled inert spacer is invisible empty space (no
    # slate fill, no note); a deliberately-disabled event stays drawn (dimmed + hatched).
    "EffectSpacerProjectionTest"
    # Pure-logic guard (no GPU/scene): the SPACER = INVISIBLE EMPTY SPACE predicate
    # (ADR-0087 FIFTH amendment) — EffectScoreTimeline.is_hidden_spacer, the single source
    # the painter + hit-test share: enabled inert → hidden; deliberately-disabled → drawn;
    # selected → always drawn; non-colour → never hidden.
    "EffectSpacerVisibilityTest"
    # Pure-logic guard (no GPU/scene): the SPACER clause of the boundary-drag GRIP (ADR-0086
    # decs. 22-23 / ADR-0087 dec. 29) — a grip's WRITE owner (whose end_frame /
    # time_value the drag stores) vs its SELECT IDENTITY (who it selects, inspects and draws
    # a handle for). Drawn span → itself; hidden hold → the next DRAWN span, whose visible
    # left edge that boundary is (and the hold must NOT reveal — the reported "left-handle
    # resize creates a spacer"); hold→hold (blind) and lane tail → grip with NO identity.
    # Camera and palette, since the registration is shared.
    "EffectSpacerEdgeGripTest"
    # Pure-logic guard (no GPU/scene): SpacerVerdicts (ADR-0087 decs. 17-22) —
    # the disable-equivalence fold oracle: with-event vs without-event folds compared
    # as colour TRANSFORMS (probe bases incl. clamp extremes, ramp breakpoints +
    # midpoints) under the consumer profiles (5-bit CLUT palette / 8-bit doubled
    # screen, both endpoints ANDed). Synthetic lanes: lead-in vs fade-out same bytes,
    # half-dim/luma never-intrinsic, restores over nothing vs after tints, Gradient
    # transform equality, cross-phase single-stream context.
    "SpacerVerdictsTest"
    # Pure-logic guard (no GPU/scene): SoundGhostProjector — the ADR-0085 tempo-map
    # projection that turns a FEDS sound's tick/opcode domain into a read-only length
    # on the effect FRAME axis (ticks →[tempo map, INTEGRATED not scaled]→ seconds
    # →[30 Hz effect clock]→ frames). Guards seconds/tick, mid-stream tempo change
    # integrated segment-by-segment, pair length = longer concurrent track, and the
    # trigger→SoundContainer→FEDS-pair resolution (first-fire representative) that
    # feeds the timeline's ghost bars. Synthetic events + synthetic FedsBank.
    "SoundGhostProjectorTest"
    # Pure stay-local gap arithmetic behind fire-drag (ADR-0085): moving trigger N
    # trades the two neighbouring duration_frames gaps so ONLY N moves; clamped, with
    # the first trigger pinned.
    "SoundGapMathTest"
    # Pure-logic guard (no GPU/scene): SoundContainerModel — the ADR-0085 TIER-2
    # sound-selection projection. Makes a shared, effect-global SoundContainer legible:
    # its mode name, the DISTINCT ids it can fire (enumerated by driving the real
    # EffectSoundResolver forward, so the 5-mode truth stays single-sourced), each id's
    # FEDS pair, and the "used by N" back-links to referencing triggers (windowed).
    "SoundContainerModelTest"
    # Pure-logic guard: SoundContainerProjector — the "container" target-kind projector
    # (ADR-0073) that reads the pre-projected view out of the score and formats the
    # mode / emitted ids / pairs section + used-by header links. Missing view = inert.
    "SoundContainerProjectorTest"
    # Pure-logic guard: SoundTriggerProjector — the SFX-lane inspector view keeps its
    # editable Sound-id / Gap cells AND adds the follow-the-reference "Plays" link that
    # drills into SoundContainer[sound_id-2] (ADR-0085 TIER-2).
    "SoundTriggerProjectorTest"
    # Differential guard (real effect, model vs runtime): the Studio score must draw
    # ONLY the palette keyframes PaletteSubsystem actually plays (window
    # 0..max_keyframe-2; the rest are terminators/padding). Loads E077 — whose
    # affected_units track is mostly padding — and asserts every model span start
    # equals a runtime-emitted frame, so the Studio can't show phantom tint keyframes.
    "EffectScoreWindowParityTest"
    # Pure-logic guard (real E317): the ADR-0085 sound-lane bijection — over the live
    # window [0, max_keyframe) every sound EVENT projects exactly one selectable handle
    # (audible or silent — a silent event is not a rest), plus exactly one INERT terminator
    # end-cap at index max_keyframe. max_keyframe==0 and padding project nothing; the tail
    # (ghost/energy) is the SOLE tell of sound and never rides a terminator.
    "EffectSoundEventHandleBijectionTest"
    # Pure-logic guard (no GPU/scene): TimelineAxis — the frame↔pixel transform the
    # Effect Studio timeline draws and hit-tests through (ported DAW piano-roll
    # math). frame_to_x/x_to_frame inverse round-trip, clamp-at-0, cursor-anchored
    # zoom (frame under cursor stays put), scale clamp, snap-to-grid rounding.
    "TimelineAxisTest"
    # Integration guard (real Control, bare tree): EffectScoreTimeline hit-test
    # routing — the CONTEXT invariant "seek here vs inspect this must never fight
    # over one click". Ruler/empty-lane clicks seek; span clicks select; the label
    # gutter is inert; a ruler press emits seek_requested and moves the playhead.
    # Exercises the pure layout+hit_test seam (no paint) over a real projected score.
    # Also guards click-drag SCRUB: a ruler press arms a continuous scrub, motion
    # seeks to the frame under the cursor (forward AND backward), release ends it,
    # a span press inspects and never scrubs, and bare hover is inert.
    "EffectScoreTimelineTest"
    # Headful paint acceptance (in-tree, real E317): the ADR-0085 sound handles + inert
    # terminator END-CAP glyph + terminator selection outline actually PAINT without a
    # crash. The layout guards above are paint-free; this exercises _draw_sound_terminator.
    "EffectSoundHandleDrawAcceptanceTest"
    # Integration guard (real page + fake host): EffectStudioPage COALESCES scrub
    # seeks — a drag's per-motion burst moves the playhead every event (cheap) but
    # applies exactly one host.studio_seek per _process tick (latest wins), because
    # a backward seek reset+repumps the effect from 0 (ADR-0070, 100+ ms). Discrete
    # transport seeks stay immediate.
    "EffectStudioSeekCoalesceTest"
    # Pure-logic guard (no GPU/scene): EffectScoreModel.resolve_audibility — the
    # Effect Studio Solo/Mute core. The DAW rule (a lane is silenced if muted, or if
    # any solo is active and it is not soloed; solo composes with mute), the particle
    # child-closure projection, and the PER-LANE exclusion filters for the folded
    # subsystems (muted_screen per phase, muted_palette per phase/channel, etc.) — muting
    # ONE color lane excludes only that lane, no whole-subsystem gate. Synthetic score.
    "EffectAudibilityTest"
    # Integration guard (real Control, bare tree): EffectScoreTimeline per-lane SOLO /
    # MUTE gutter buttons — layout builds an S+M hit-rect per lane inside the gutter,
    # a click routes to a mute/solo intent, a press toggles the state and fires
    # lane_audibility_changed, solo silences the other lanes (DAW rule), and load_score
    # clears the selection. Exercises the layout+hit_test+input seam, no paint.
    "EffectTimelineSoloMuteTest"
    # Integration guard (real page + fake host): EffectStudioPage forwards the timeline's
    # solo/mute selection to the host — on a toggle it resolves audibility and calls
    # host.studio_set_audibility(audibility); loading an effect re-applies (a fresh
    # instance starts fully audible).
    "EffectStudioAudibilityWiringTest"
    # Guard (real EffectViewerScene, bare tree): Studio camera ownership is a pure
    # function of the playhead — frame 0 returns the scene/cursor camera, ≠0 is an
    # effect TAKEOVER, and a natural end freezes at the last frame (effect keeps the
    # cam). reconcile_studio_camera enforces it; catches a revert to "no map cursor
    # at boot" or the effect never handing the cursor back.
    "EffectStudioCameraOwnershipTest"
    # Unit guard: PER-LANE mute of the folded subsystems. SCREEN set_muted({phase}) drops
    # that phase from build_stream so the folded backdrop returns toward the map baseline
    # (re-folded in place immediately). (Sound mute is per-channel at EffectInstance's
    # trigger handler — wiring guard. Camera is display-only, no mute.)
    "EffectSubsystemMuteTest"
    # Integration guard (real Control, bare tree): EffectKeyframeInspector renders a
    # selected span through ONE path — header rows (inspector_header) + projector
    # [Section] list (inspector_sections) — and clear() returns to empty. Thin-glue
    # guard; section content is locked in the model + projector tests. (ADR-0071)
    "EffectKeyframeInspectorTest"
    # F1 shared editor-widget kit (#264): the generic `int`/`enum`/`bitflags`/`curve` edit cells
    # every per-subsystem authoring build reuses. Guards each widget's range/seed/fan and that
    # seeding fires no spurious edit — the harness the Palette→…→Structure tickets plug into.
    "EffectStudioEditorKitTest"
    # The shaders are COMPILED here, not text-scanned. The three fold-routing tests below and the
    # check_*_in_fold.py guards all read shader SOURCE, so every one of them is happy with a shader
    # that does not parse — a syntax error in a fold material shipped straight to runtime, where a
    # broken compositor_layer carrier just silently stops compositing. Compiles all 81 .gdshader
    # (probe-uniform oracle: a shader that fails to parse reports an EMPTY uniform list) plus the
    # fold bracket's two .glsl passes FROM SOURCE with the SPIR-V cache off — so, unlike the deleted
    # tools/check_foldsurface_shaders.gd, it cannot pass on a stale .godot/imported/ artifact.
    "ShaderCompileTest"
    # Guard (no GPU/fork): callback → compositor fold routing (the E065 Shiva "spikes pierce the
    # flash" fix). Callbacks are scene meshes, so the static check_compositor_routing.py can only
    # LOCATE their shaders; this locks that a live callback actually ROUTES — the routing decision
    # (shader_path_for), the fold variant genuinely declaring compositor_layer, the exempt in-scene
    # fallback, uniform parity for the .shader swap, and every registered callback inheriting the
    # single _create_cb_mesh seam (a future callback that hand-rolls its material would bypass the fold).
    # ADR-0189 guard (no GPU/fork; reads shader source): the unit-sprite VARIANT contract.
    # ScenarioVM swaps .shader on a LIVE material mid dead-unit fade and FormationScene mounts the
    # flat variant on a duplicate of unit.tres — both rely on uniform names carrying over, and
    # nothing asserted it. Pins opaque/additive parity + flat-is-a-superset-plus-a-named-list.
    "UnitMaterialVariantTest"
    # ADR-0074 display-space-fold guards (no GPU/fork; read shader source + exercise the producer):
    # each light producer that left the particle pool to become a DIRECT fold node must (1) wear a
    # MONOMORPHIC compositor_layer material with its four axes BAKED and (2) route through Fold.add.
    # These were previously unwired — added with issue #229 so the routing is actually enforced.
    "CrystalSpriteCompositorTest"     # ④a: billboard / alpha-key / no-PAR / additive
    # ④b MOVED OUT, NOT DROPPED (ADR-0208 dec. 8, applying ADR-0194 / #652):
    # TileOverlayCompositorTest — world_quad (FLAT decal, THE fix) / PAR-full / additive —
    # reaches nothing but `addons/exmateria_battlefield/overlay/`, so it now lives in
    # addons/exmateria_battlefield/tests/ and is run by
    # `bash tests/stranger/exmateria_battlefield/run.sh`. That rig GLOBS its addon's
    # tests/*.tscn (shared/rig.sh:237), so the move enrols it; there is no second list.
    "TileCursorTakeoverTest"          # outline carrier hides atomically with the opaque body (06f18a547)
    # The BY-FIAT camera_mode edges (`enter_takeover_framing` / `resume_cursor_framing`) —
    # the pair TileCursorTakeoverTest does NOT cover, because no driver overwrites the pose
    # after them. The exit fold is what removes the 40-px image pop the frame a battle ends.
    "PlayerCameraDatumEdgeTest"
    # #228 Phase 3: the SHARED OT depth-ordering contract, at its own seam (OTDepthPrimOrder.order).
    # Extracted from CombatDisplaySpaceCompositeTest ahead of retiring the raw-RD GLSL fold — the
    # engine-fold still orders through it, so its coverage must outlive the deleted compositor.
    # ADR-0074 ⑤ guard: Trap's unified publish must keep working after the dead axis plumbing is
    # stripped from the pool/stager.
    "TintedSurfacesMergeTest"
    "TrapUnifiedPublishTest"
    # Per-archetype projectors (ADR-0071) — the seam that turns a lane event into the
    # inspector's [Section] list, keyed by EVENT TYPE not lane kind. EmitterProjector:
    # the two-level split (Event section + SHARED emitter groups + "shared by N" note).
    # ScreenTweenProjector: the Blend/Gradient split (live-fields-only) + lane summary.
    # TweenTrigger: palette/camera/sound single-section ports.
    "EmitterProjectorTest"
    "ScreenTweenProjectorTest"
    "TweenTriggerProjectorTest"
    # ADR-0087 palette authoring: the ONE shared human-label map for the 11 PSX Color
    # modes (ColorModeLabels), read by BOTH the screen Blend-mode row and the palette
    # tint's blend-mode selector so they can't drift to different words for the same op.
    "ColorModeLabelsTest"
    "PaletteTweenProjectorTest"
    # ADR-0087 palette tint result-picker: the palette byte is a SIGNED Δ (the #266 mislabel
    # + "seek-color renders wrong hue" bug), so the tint is a WYSIWYG pick back-solved by
    # PaletteTintSolver against the palette fold over a fixed mid-grey reference (the palette
    # analogue of the screen BlendTargetSolver). Pure; the host end-to-end pick + screen
    # regression are the headful EffectPaletteTintPickAcceptanceTest (out of this list).
    "PaletteTintSolverTest"
    # ADR-0087 palette boundary drag: palette is length-encoded (time_value×8, cumulative
    # start), so ColorLowering (shared with screen) maps absolute intervals ↔ time_value (÷8 snap, min 1-frame)
    # and a boundary drag is a SINGLE synthetic `boundary_end` scalar = a sum-preserving
    # duration trade in PaletteChannel (dragged span grows, neighbour absorbs, far edge pinned)
    # — reusing the camera edge-drag seam + coalesce, NOT SoundGapMath. Page wiring + the
    # timeline edge-grip gate are in EffectStudioEdgeDragWiringTest / EffectScoreTimelineTest.
    "ColorLoweringTest"
    "PaletteBoundaryEditTest"
    # ADR-0101 / ADR-0087 dec. 30 — the trade FREEZES the far edge. The two traded
    # lengths must sum to their original total EXACTLY: the pre-fix code handed the neighbour
    # `total - first` and let _set_duration re-snap it silently, sliding the far edge ±1 frame
    # in ~13% of drag positions (the reported "drag the left side and BOTH sides move"). An
    # exact pair always exists — a trade's total is by construction the sum of two storable
    # lengths — so ColorLowering.trade_durations never needs a drifting fallback, and
    # clamp_boundary_duration is retired. The corpus sweep is the companion guard: it asserts
    # the same invariant over every adjacent pair on every colour channel of all 401 effects
    # (12,530 boundaries, 87,710 trades, ~35s) rather than over a fixture someone thought to
    # write down.
    "ColourBoundaryFarEdgeTest"
    "ColourBoundaryCorpusSweepTest"
    # ADR-0086 dec. 26 — the colour edge drag re-plans from a snapshot taken at
    # grab instead of mutating in place, so replaying an earlier cursor position lands where
    # going there directly lands. The FOLD-DERIVED fixture is the point: EffectSpacerEdgeGripTest
    # stamps fields.spacer (SpacerVerdicts is the expensive oracle), so nothing exercised the one
    # mechanism colour has and camera does not. This fixture stamps nothing — an idempotent
    # repeat of a settled tint, which the real fold calls empty space. It also pins the bug the
    # bracket exposed: restore handed the live channel the SNAPSHOT'S OWN array, so one snapshot
    # survived exactly one restore and corrupted on the next.
    "ColourDragPristineTest"
    # ADR-0087 palette add/delete verbs: the camera span-lane verbs (ADR-0086) generalised to
    # palette — INSERT splits a covering span seeding a DISABLED null tween (invisible in any
    # mode, never a Δ-inherit), DELETE merges the length into a neighbour (downstream pinned),
    # both by RAW keyframe index (no ordinal) with snapshot undo through EffectEditSession.
    "PaletteInsertDeleteTest"
    # ADR-0087 palette Save seam: EffectPaletteSaver bridges the (previously unbridged) palette
    # half of studio_save — pads each live channel to the fixed 33 disk slots, refuses over-
    # capacity, and shells the write_effect_palette.py CLI, layered onto the screen+camera
    # output BIN. This guards the shape adapter; the live save round-trip + writer bytes are the
    # headful EffectPaletteSaveRoundTripTest + tools/test_write_effect_palette.py (out of this list).
    "EffectPaletteSaverAdapterTest"
    # ADR-0087 SCREEN lane verbs: the palette resize/split/move trio generalised to the third
    # colour lane (same time_value encoding, shared ColorLowering). Boundary drag = the same
    # sum-preserving `boundary_end` trade in ScreenChannel (1-D address: phase context only);
    # INSERT seeds an ACTIVE IDENTITY no-op tween (Blend mode 0, zero param — screen has no
    # enable bit; a param copy would double the tint); DELETE merges into a neighbour. Screen
    # save gains the palette-style 33-slot shape bridge (EffectScreenSaver.to_screen_json —
    # before it, a count change silently truncated or crashed the fixed-slot writer). Headful
    # end-to-end on real E015: EffectScreenEdgeDragAcceptanceTest /
    # EffectScreenInsertDeleteAcceptanceTest (out of this list).
    "ScreenBoundaryEditTest"
    "ScreenInsertDeleteTest"
    "EffectScreenSaverAdapterTest"
    # Camera Timeline authoring (#267): the camera projector, flipped from read-only to
    # EDITABLE, emits the F1-kit int/enum/bitflags rows (End frame + the decomposed command
    # word + the sub-channel value vec), each carrying a write-side field_ref on the "camera"
    # channel into the #255 choke point.
    "CameraTweenProjectorTest"
    # Camera COMPILED (storage/truth) lane (ADR-0085 observability): a strictly read-only
    # lane (kind:"camera_compiled", one per phase with a camera table) that shows the packed
    # keyframe schedule DIRECTLY — one POINT MARKER per real keyframe (channel_mask != 0, the
    # mask==0 empty SoA slots drop), each anchored AT its end_frame (storage stores no
    # duration, so markers not intervals; interleaved tracks would make intervals lie). A
    # split's coincident siblings both show. Its projector (CameraCompiledProjector) emits
    # only const rows (Index/End frame/Channels/Source/Interp/Param/Flags/Command word);
    # editing is impossible by construction. Also guards the sub-channel Event inspector's
    # read-only Length row.
    "EffectCameraCompiledLaneTest"
    # Camera coalescing lowerer (ADR-0085): the compiler between the AUTHORING model
    # (three independent sub-channel lanes) and the STORAGE model (packed channel_mask
    # keyframes). parse expands one masked keyframe → one event per set bit; lower folds
    # coincident+agreeing sub-channel events into one masked keyframe and SPLITS
    # disagreeing ones. Guards parse, merge, split, and the parse↔lower round-trip's
    # SEMANTIC equivalence (not byte-identity) on real E317 for_each. channel_mask is a
    # lowering artifact born only here — the orphan bug dies by construction.
    "CameraLoweringTest"
    # Generic inspection-target seam (ADR-0073): the inspector renders a {kind, ref}
    # target through a kind→projector registry, generalizing ADR-0071's span→projector.
    # InspectionTarget: constructors + opaque kind-specific ref + equality + title/label.
    # InspectorProjectorRegistry: built kinds resolve, declared seams are inert-not-crash.
    # SpanProjector: the behavior-preserving span refactor (header + Event/emitter sections
    # via {kind:"span"}). EmitterTargetProjector: the bare-emitter view + incoming-edge
    # provenance. InspectorLink: the clickable `link` field + navigate callback.
    "InspectionTargetTest"
    "InspectorProjectorRegistryTest"
    "SpanProjectorTest"
    "EmitterProjectorBareTest"
    # ADR-0089 inspector presentation (#291): group-stamped rows cluster into ONE
    # nested fold per parameter group (collapsed on fresh inspect, per-(emitter,group)
    # session memory survives show_target rebuilds), Expand/Collapse-all bulk controls
    # on fold-carrying sections, and the width-based two-per-line reflow deleted
    # inspector-wide (grids keep their intrinsic sub-column count at any width).
    "EffectStudioInspectorFoldsTest"
    "EmitterProvenanceTest"
    "InspectorLinkTest"
    "EffectStudioNavStackTest"
    "EffectStudioEmitterBrowserTest"
    # ADR-0085 TIER-2 exhaustive SoundContainer browser (real page + fake host): lists
    # every shared container (incl. an orphan referenced by no trigger) and drills to one
    # as a fresh inspection root — the follow-the-reference reachability guarantee.
    "EffectStudioContainerBrowserTest"
    # ADR-0075 per-edge child-spawn suppression — the SIM guard (ParticleSubsystem skips a
    # suppressed (parent, edge) spawn; accessor round-trip; survives reset()). The model +
    # inspector-wiring halves ride in EffectScoreModelTest / InspectorLinkTest above.
    # Authoring choke point (#255, pilot slice 1): EffectEditSession.apply_edit is the
    # SINGLE mutation entry over the raw-authoritative EffectData, routing by channel to
    # a per-channel raw↔value encoder (ScreenChannel). A screen-colour raw edit writes
    # the byte, recomputes the derived Color cache, and reports invalidates_sim=false
    # (read-live → repaint in place, zero re-seek — why Screen is the pilot, #253).
    "EffectEditSessionTest"
    # Shared-emitter parameter authoring channel (ADR-0089): EffectEditSession routes an
    # "emitter" edit to EmitterChannel.apply_raw — the raw PSX int is authoritative (raw_data
    # slot or the raw-consuming field), the converted Godot-unit cache re-derives with the
    # parser's proven conversion (tiles /28 + Y-flip, angles TAU/4096, radial /14336, accel
    # /114688), every edit invalidates_sim (particles are born at spawn — no read-live), and
    # out-of-range raw is a REFUSAL (no_edit), never a clamp. Scalar undo restores raw + cache.
    "EmitterChannelTest"
    # ParticleUnits (ADR-0089): the raw↔human affine for emitter authoring — only PROVEN
    # conversions get a descriptor (tiles 28/raw, degrees 4096=360°, inertia ×4096=1.0);
    # quantize keeps the honest achieved-value tell. Storage/writer/runtime stay raw.
    "ParticleUnitsTest"
    # EffectEmitterSaver (ADR-0089 slice 4): the emitter half of the game→json→bin repack —
    # live EffectEmitter objects → parser-shaped raw dicts (present-keys-only, child wiring
    # renormalized -1→255) for the byte-exact write_effect_emitters.py partial patch.
    "EffectEmitterSaverTest"
    # ADR-0089 acceptance (headful, real E019): a live emitter edit re-folds the parked
    # sim, reaches the byte-patched BIN via studio_save's layered chain, and survives a
    # reload — with every byte outside the edited fields identical to the source.
    "EffectEmitterSaveAcceptanceTest"
    # ADR-0089 amendment "directional Y authors game-up" (headful, real E019): the LIVE
    # Position "at start" Y cell authors game-up — a negative stored raw (PSX -Y up) shows a
    # POSITIVE tile value agreeing in sign with the sim cache, and dialing the cell UP moves
    # the particle UP (cache Y rises) while the stored byte moves the OPPOSITE way. Proves the
    # chirality flip end-to-end through the real projection + inspector widget + edit choke.
    "EffectStudioDirectionalYAcceptanceTest"
    # ADR-0090 dec. 4 "speed is a continuous 0.1×–4× scrub field": the pure page guard —
    # a parked forward transport advances the playhead TRANSPORT_HZ · speed · seconds (the
    # accumulator carries fractional frames), the 0.1–4 range clamps the reachable speed, and
    # the seed fires no value_changed. The toolbar control is a ScrubField, not a cycle button.
    "EffectStudioSpeedFieldTest"
    # ADR-0090 dec. 4 (headful, real E019): landing the LIVE toolbar speed ScrubField on
    # 0.25× / 2.0× re-labels it and changes _speed() so a fixed synthetic tick sequence advances
    # the real playhead proportionally (2.0× travels ~8× as far as 0.25×). Proves the widget →
    # speed → page-driven transport path end-to-end on a real effect.
    "EffectStudioSpeedFieldAcceptanceTest"
    # ESC-deselect + scroll-selected-into-view (headful, real E317 — many lanes). (A) clicking
    # the topmost span grows the inspector over the top lanes and the selection is scrolled back
    # into the visible window; (B) Esc reaches the Deselected (empty inspection) state (nav
    # emptied, inspector collapsed, no highlight); (C) two-stage Esc — a focused value cell eats
    # the first Esc (field cancel), only the next deselects. The pure decisions (scroll math, key
    # + focus predicates) are the scene-free EffectStudioDeselectScrollTest.
    "EffectStudioDeselectScrollAcceptanceTest"
    # Camera Timeline authoring channel (#267): EffectEditSession routes a "camera" edit to
    # CameraChannel.apply_raw — writing angle/position/zoom/end_frame raw and folding the
    # source/interp/mask/param/flags bitfields into command_raw (preserving the other bits),
    # recomputing the decoded cache, and declaring invalidates_sim=true (camera is folded, not
    # read-live). Undo replays the packed field back through the same fold.
    "EffectCameraEditTest"
    # Camera DECOUPLED sub-channel authoring (ADR-0085): editing a shared field (source /
    # interp / end / param / flags) on ONE sub-channel of a COALESCED keyframe splits it
    # out via CameraLowering instead of dragging its siblings (the position sibling keeps
    # its own source). Value edits never split; solo-keyframe field edits stay in place;
    # a split that overruns the native slots is a Faithful advisory (Free still applies).
    "EffectCameraDecoupleTest"
    # Camera ORDINAL ADDRESSING (ADR-0085 amendment, #286): a camera edit addresses a
    # sub-channel event by (sub-channel, ordinal) — its position in the lane — not the raw
    # keyframe index a split/merge renumbers. Guards that a follow-up edit + an undo replay
    # land on the RIGHT keyframe after a renumbering split, and that the sub-channel span id
    # (hence selection) survives the structural edit.
    "EffectCameraOrdinalAddressTest"
    # Camera ADD / DELETE lane verbs (ADR-0085 second amendment, #287-adjacent): the author
    # edits lanes — CameraChannel.insert_event cuts a covering span with a value INTERPOLATED
    # at the frame (a visual no-op) or seeds an empty lane; delete_event is the inverse; the
    # packer (CameraLowering.lower) coalesces only on exact-frame sibling agreement. Asserted
    # semantically by (sub-channel, ordinal), never by a raw keyframe count.
    "EffectCameraInsertDeleteTest"
    # The structural verbs through the #255 choke point + snapshot undo: EffectEditSession.
    # insert_event / delete_event record a pre-edit table SNAPSHOT (not a scalar before_raw),
    # and the HYBRID undo() restores the snapshot for structural ops while scalar edits keep
    # the fast replay path — unwinding a scalar-then-structural stack in LIFO to the original.
    "EffectCameraStructuralUndoTest"
    # Lane CONTEXT-MENU resolver (ADR-0085 second amendment): EffectStudioPage.
    # _lane_context_actions maps a right-clicked span + cursor frame to the menu verbs — a
    # camera sub-channel span offers Add (insert by frame) + Delete (by §#286 ordinal); the
    # read-only compiled lane and the out-of-scope channels offer nothing. Pure, scene-free.
    "EffectStudioLaneContextMenuTest"
    # Undo keybinding recognition (Ctrl+Z): the pure recognizer EffectStudioPage.
    # _is_undo_shortcut that the page's _unhandled_key_input fires undo on. Guards Ctrl+Z
    # key-down fires while plain Z / Ctrl+other / key-up / auto-repeat echo do not. The full
    # key → studio_undo → revert flow is the headful EffectStudioUndoTest (needs the E317
    # extract, kept out of this runner like the other headful acceptance scenes).
    "EffectStudioUndoShortcutTest"
    # ESC-deselect + scroll-selected-into-view PURE decisions (scene-free): compute_scroll_target
    # (−1 = already visible, span-above / span-below branches, headroom, clamp-at-0), the Esc key
    # recognizer (_is_escape) and the value-cell focus predicate (_is_text_focus) that drive the
    # two-stage Esc. The end-to-end flow is the headful EffectStudioDeselectScrollAcceptanceTest.
    "EffectStudioDeselectScrollTest"
    # Subsystem 1 — Palette / field tints editable (#266): the palette colour tracks made
    # editable through the same choke point. Guards the projector's shape:edit Tint
    # (gradient_color) + Blend mode (enum) cells with palette's two-dim address, the inspector
    # rendering + byte-write fan, and PaletteChannel writing the raw byte read-live (undo +
    # ctrl enabled-bit preservation). Byte-exact save is guarded in tools/test_write_effect_palette.
    "EffectStudioPaletteEditTest"
    # Subsystem 3 — Sound Timeline SFX triggers editable (#268): the trigger tracks made
    # editable through the same choke point. Guards the projector's shape:edit Sound id (u8)
    # + Duration (s16) int cells with sound's three-dim address (phase/channel_index/event),
    # the inspector rendering + write fan, and SoundChannel writing the raw dict field
    # (invalidates_sim=false, undo). Byte-exact save guarded in tools/test_write_effect_sound.
    "EffectStudioSoundEditTest"
    # ADR-0085 Slice 1b (anchor) — the page glue that turns a timeline anchor-drag into a
    # byte-faithful edit: resolves the trigger's three-dim address, lowers anchor_offset
    # (NOT sound_id/duration, so fire + bytes stay) through the host choke point, and
    # reprojects just the handle without a transport/selection reset.
    "EffectStudioAnchorWiringTest"
    # ADR-0085 fire-drag — the page glue that turns a timeline marker-drag into a
    # STAY-LOCAL trigger move: resolves the three-dim address, computes the two-gap edit
    # (SoundGapMath), lowers it as ONE compound (single undo) through the host, and
    # reprojects the marker to the CLAMPED fire. First trigger pinned.
    "EffectStudioFireDragWiringTest"
    # ADR-0086 boundary-drag — the page turns a timeline camera edge-drag into a single,
    # clamped, one-undo end_frame edit: abs→phase-local convert, clamp between neighbours
    # (min 1 frame; tail clamps left only), once-per-frame drain, begin/end_coalesce bracket.
    "EffectStudioEdgeDragWiringTest"
    # #267 follow-on — the inspector re-projects from the LIVE keyframe, never a stale
    # score-build snapshot. Edits go through EffectEditSession then re-select the SAME span;
    # camera/palette/sound must all show the NEW value (only screen resolved live before).
    "EffectStudioLiveReprojectTest"
    # #267 follow-on — the host's choke point re-folds the preview for FOLDED-channel edits.
    # A camera edit (invalidates_sim) must refold() (reset→re-pump), NOT seek(current_frame)
    # which is a same-frame no-op; a read-live edit redelivers in place with no re-fold.
    "EffectViewerRefoldTest"
    # F0 gap monitor (#263): the editability manifest (src/effects/studio/editability_
    # manifest.json) is the single source of truth for the coverage tracker. This guard
    # pins it to reality — every channel it marks "editable" must be emitted by a real
    # projector as a shape:edit row, and no projector may ship an edit for an unregistered
    # channel. Keeps the tracker's "editable %" honest as subsystem builds land.
    "EffectEditabilityManifestTest"
    # Frame/frameset editing (#278) and the UV drag-to-resize canvas (#279).
    "EffectStudioFramesetEditTest"
    "EffectStudioFramesetCanvasWiringTest"
    # LAYOUT regression for that canvas. It is the right-hand area of the inspector row,
    # so it can never cover the transport above it nor bleed into the timeline below.
    # Three shipped attempts hand-computed its rect against the page instead and each
    # broke differently — the last overran the timeline by 388px while every other guard
    # here stayed green, because none of them asserted a rect. Keep this one rect-based.
    "EffectStudioFramesetLayoutTest"
    # Sequence (Animation) editing (#275): the pure encoder (SequenceChannel), the
    # opcode-row projector (SequenceProjector — one row per opcode, Lua-sequences-tab
    # labels, named depth modes), and the #255 choke-point routing + undo. v1 is
    # in-place PARAMETER edits only: opcodes are variable-size, so type changes and
    # insert/delete/reorder are a structural rewrite, deferred.
    "EffectStudioSequenceEditTest"
    # Wiring guard: the "Sequences:" transport browser enumerates every sequence in the
    # loaded effect and roots the inspector on the chosen one (the exhaustive entry point
    # that reaches a sequence no emitter currently plays).
    "EffectStudioSequenceBrowserTest"
    # End-to-end acceptance on the REAL shipped E019 data (9 sequences / 251 opcodes):
    # registry projection, editable-row channels, a real duration edit + undo, and the
    # page browser — proof the pure seams compose against ROM-derived opcode streams.
    "EffectStudioSequenceAcceptanceTest"
    # Texture replacement (#280, ADR-0096/0097): the sheet is replaced wholesale from a
    # same-dimensions RGBA .tga with the CLUT held FIXED. The codec guard round-trips the
    # Lua extractor's OWN E019 output byte for byte (an independent oracle) and pins the
    # artist-tool variants a real save produces — a bottom-left-origin file must be flipped,
    # not read upside down. The edit guard covers the scope verdict (8bpp single-sub-palette
    # only; 4bpp is refused WITH A REASON because a flat export of a multi-sub-palette sheet
    # would itself be untruthful), the preview swap, snapshot undo, and export.
    "EffectStudioTextureTgaTest"
    "EffectStudioTextureEditTest"
    # The Texture inspection target: metadata rows plus the two round-trip actions, and NO
    # actions at all on a refused sheet.
    "EffectStudioTextureProjectorTest"
    # Host wiring for those actions: each opens the right file dialog and hands the chosen
    # path to the host (a host predating the feature must not crash the page).
    "EffectStudioTextureWiringTest"
    # End-to-end acceptance on the REAL shipped E019 sheet (128x256 @ 8bpp, sub-palette 0):
    # the scope verdict, the inspector's projection of the real geometry, an export that
    # reproduces the Lua extractor's own texture.tga byte for byte, and a re-import of it
    # that changes not one texel — the identity leg of ADR-0199's green bar.
    "EffectStudioTextureAcceptanceTest"
    # Pure search behind the WYSIWYG "target colour" screen-Blend authoring widget (#255):
    # BlendTargetSolver brute-forces the 256 signed-param bytes per channel through the REAL
    # forward blend fold (an eval callback) and returns the raw bytes nearest the target — an
    # unreachable target snaps to the nearest byte (honest "nearest match").
    "BlendTargetSolverTest"
    # Pure-logic guard (no GPU/scene): CurvePaintModel — the freehand-painting core
    # for FFT's dense integer curve LUTs (no control points). Single-column paint,
    # fast-sweep interpolation of skipped columns, reverse sweep, Y-range clamp
    # (0-255 lerp / 1-9 time-slow), inverted-Y pixel→cell mapping, and the
    # normalized-curve↔integer-grid bridge.
    "CurvePaintModelTest"
    # Integration guard (real Control, bare tree): EffectCurvePainter turns a mouse
    # drag into a dense stroke on the bound EffectCurve with preview-vs-commit
    # semantics — the drag mutates a local grid and only mouse-up writes the curve
    # (curve_changed). Stroke correctness is locked in CurvePaintModelTest.
    "EffectCurvePainterTest"
    # Wiring guard (ADR-0089 curve-UX amendment, bug #4): the painter's curve_changed
    # (curve CONTENTS edit) is wired to the page's live-refresh fan-out (rebuild score +
    # re-render inspector + re-seek at the parked frame) — was connected to nothing.
    # EPHEMERAL: it does NOT route through EffectEditSession (no undo, no writer — #292);
    # the painter panel carries an honest "Preview only" note.
    "EffectStudioCurvePreviewWiringTest"
    # Integration guard (real controls, bare tree): TuneField — the ONE builder for
    # a tunable row (ADR-0068), used by BOTH the generated dashboard AND bespoke
    # panels so there is no drift. Builds a type-inferred control, wires it two-way
    # to Tune (edit -> set_value; value_changed -> resync), carries the typographic
    # tunable/dirty markers (accent label + trailing " *"), and drives the per-field
    # Pin/Reset context-menu logic. The right-click gesture itself is verified by
    # hand in the F3 dashboard's Registry page (not routable headless); TuneSandbox,
    # which used to host it, was deleted with its dead preload — #459.
    "TuneFieldTest"
    # Color-type guard (ADR-0068): Color is a first-class Tune type — inferred to a
    # ColorPickerButton, and a committed Color override round-trips through the JSON
    # staging file (stored [r,g,b,a], coerced back to Color on read).
    "TuneColorTest"
    # Integration guard (bare tree): ADR-0068 "replace in place" — every
    # ScenarioUnitAlignmentDebugPanel knob (PAR/stretch AND batch-1 mesh scale / Y-lift /
    # loc_offset X/Y) is built by the shared TuneField (accent label + write-through to
    # the render.* slug), not the old hand-rolled _add_scrub. Catches a migration revert.
    "AlignmentPanelTuneFieldTest"
    # Move-1 guard (real Unit spawn, not GPUArena roster): ADR-0068 batch 1 — the Unit
    # spawn path sources mesh basis scale / Y-lift / base loc_offset through Tune, so a
    # committed override coalesces onto a fresh unit's first frame. The seam these knobs
    # scrub through; catches a revert of the spawn-side routing.
    "UnitVisualDefaultsTuneTest"
    # Guard (ADR-0068 R1–R8 pilot): Unit._static_init REGISTERS the per-unit render
    # tunables at boot (the pure bind), so the dashboard + alignment view can enumerate/read
    # them before any unit spawns. Catches a revert to lazy per-spawn registration (which
    # would leave the view rows blank when a panel builds first) or a lost Vector2 loc_offset.
    "PilotStaticInitTest"
    # Guard (no GPU): DebugConfig.psx_dither_enabled is a Tune bool tunable (ADR-0068
    # decision 10 — debug prefs are tunables too). The bool analog of live_par: the
    # property coalesces a committed `render.psx_dither_enabled` override over the
    # project.godot [shader_globals] default, and an override drives the bound
    # _apply_dither -> psx_dither_changed. Kills the old rival `= true` literal.
    "DebugDitherTunableTest"
    # Guard (no GPU): the map terrain carries the PSX framebuffer snap, in the right
    # place, at the right cell size. The real GPU dithers a primitive only when it is
    # GOURAUD and the texpage DTD bit is set; FFT's map terrain clears both (measured off
    # a live battle frame — terrain carries the 4x4 signature, the flat-rect UI windows
    # in the same frame carry none) and the port did neither until this landed. Arms: the
    # include is pulled and the snap is called ONCE; the call sits ABOVE the
    # map_light_debug chain so the diagnostic modes stay un-quantized; both battlefield
    # surfaces pass the SAME native width, and it is FFT's measured 256 rather than the
    # generic PSX 320 (at the 1024-wide viewport that is a 4px dither cell, not 3);
    # the width is a parameter, not re-welded into the platform include; and no sprite-rig
    # shader includes the dither, which was the include's own unenforced header sentence.
    # Plus the F3 row: MapRenderDebugPanel's "PSX dither + 15-bit snap" must EMIT a bound
    # CheckBox, not TuneField's silent "(unregistered — owner not booted)" placeholder —
    # that row's owner is the DebugConfig autoload rather than MapComposer like every other
    # slug on the panel, and a source grep for `TuneField.add` passes against a dead row.
    # All 10 arms falsified against seeded defects. 10 assertions.
    "MapDitherSnapTest"
    # Guard (no GPU): the 15 plain-var, panel-exposed DebugConfig debug flags are
    # Tune bool tunables (ADR-0068 decision 10 — batch 2). Each property coalesces a
    # committed `debug.*` override over its code default and an assignment writes
    # through Tune, so an F3/dashboard toggle persists across scene reloads. DebugConfig
    # owns the value; consumers read it live (no fan-out, decision 12). 45 assertions.
    "DebugLoggingFlagsTunableTest"
    # Guard (no GPU): the setter+signal DebugConfig flags (show_depth / perf_hud_enabled /
    # free_camera_enabled) are Tune bool tunables (ADR-0068 decision 10 — batch 2 cont.).
    # Each coalesces a `debug.*` override AND a bound _apply_* emits the flag's existing
    # signal, so a dashboard scrub (a Tune write, not a property assignment) reaches
    # consumers. 9 assertions.
    "DebugSignalFlagsTunableTest"
    # Move-2 guard (bare tree): LoggingDebugPanel's flag rows are TuneField-built
    # (accent label + write-through to the `debug.*` slug), not hand-rolled CheckBoxes.
    "LoggingPanelTuneFieldTest"
    # Move-2 guard: TileCursor OWNS the floating-dagger pose knobs (height/scale/bob/
    # pace/palette/blend) — it binds each cursor.* slug in _ready, so a pre-spawn
    # override coalesces at spawn AND a live scrub re-drives the cursor in any scene.
    "CursorTunablesTest"
    # Move-2 guard (bare tree): CursorDebugPanel's rows are TuneField-built (accent
    # label + write-through to the `cursor.*` slug), not SpinBoxes writing the node.
    "CursorPanelTuneFieldTest"
    # Move-2 guard: PlayerCamera OWNS the cursor-follow feel knobs (deadzone w/h, rot
    # speed, translation ease, concurrent rot+move, kickoff, overlay toggle) — it binds
    # each camera.* slug in _ready, so an override coalesces at boot AND a scrub re-drives.
    "CameraFeelTunablesTest"
    # The GAMEPLAY camera frames its tile on FFT's low optical row (native-Y 160, not the
    # midpoint 120) as a camera-LOCAL-up offset — so it survives yaw/pitch/zoom, the
    # deadzone box rides it, and it stands down under a cinematic takeover. Sibling of
    # ScenarioCameraVerticalDatumTest, which proves the same datum on the cinematic rig.
    "PlayerCameraVerticalDatumTest"
    # Move-2 guard (bare tree): CameraFeelDebugPanel's rows are TuneField-built (accent
    # label + write-through to the `camera.*` slug), not HSliders writing the node.
    "CameraFeelPanelTuneFieldTest"
    # Move-2 guard: ScenarioVM OWNS the EVTCHR cinematic-scrub overrides (segment/frame)
    # — it binds each scenario.* slug in _ready (re-firing the last cinematic on a scrub),
    # so an override coalesces at boot AND survives a scenario reload.
    "ScenarioCinematicTunablesTest"
    # The F3 Scenario picker's value AUTOSAVEs: DebugConfig.active_scenario_id is backed by
    # the scenario.active_id Tune slug, so a pick survives an app restart, not just a reload.
    "ScenarioActiveIdAutosaveTest"
    # Move-2 guard (bare tree): ScenarioCinematicDebugPanel's rows are TuneField-built
    # (accent label + write-through to the `scenario.*` slug), not node-writing SpinBoxes.
    "ScenarioCinematicPanelTuneFieldTest"
    # Move-2 guard: ScenarioWeather OWNS the {3C} look knobs (drop/splat intensity, width,
    # length, size, straddle gate) — it binds each weather.* slug in _ready, so an override
    # coalesces the instant the VM lazily spawns the node AND survives a reload.
    "ScenarioWeatherTunablesTest"
    # Move-2 guard (bare tree): ScenarioWeatherDebugPanel's rows are TuneField-built
    # (accent label + write-through to the `weather.*` slug), not node-writing SpinBoxes.
    "ScenarioWeatherPanelTuneFieldTest"
    # Move-2 guard: Unit OWNS the ot_unit_forward nudge — it binds render.ot_unit_
    # forward onto its own material, so an override coalesces at spawn AND a scrub re-drives
    # every unit (no UnitShaderDebugPanel fan-out over a units accessor).
    "UnitForwardTunableTest"
    # Move-2 guard (bare tree): UnitShaderDebugPanel's forward + center_bias rows are
    # TuneField-built (accent label + write-through to the `render.*` slugs).
    "UnitShaderPanelTuneFieldTest"
    # Move-2 guard: ScenarioDialogueBoxPool OWNS the boxed-dialogue placement knobs — the
    # VM calls box_pool.bind_tunables at boot, binding each dialbox.* slug (box_offset_px
    # split into X/Y), so an override coalesces AND survives a scenario reload.
    "ScenarioDialogueBoxTunablesTest"
    # Move-2 guard (bare tree): ScenarioDialogueBoxDebugPanel's rows are TuneField-built
    # (accent label + write-through to the `dialbox.*` slug), not box_pool-writing controls.
    "ScenarioDialogueBoxPanelTuneFieldTest"
    # Move-2 guard: UIChar OWNS the font palette colors/flags — set_palette reads each via
    # Tune.of (`font.*` slugs), so an override coalesces onto every char in any scene and is
    # read live on the next set_palette (no FontDebugPanel writing statics).
    "FontPaletteTunableTest"
    # Move-2 guard (bare tree): FontDebugPanel's rows are TuneField-built — Colors resolve
    # to ColorPickerButtons bound to the `font.*` slugs (accent label + write-through).
    "FontPanelTuneFieldTest"
    # Move-2 guard: PSXDisplay OWNS the color-calibration global psx_gamma — it binds
    # render.psx_gamma in _ready (default from project.godot), so an override applies at
    # boot in every scene. ShaderCalibrationPanelTuneFieldTest sat beside this and is
    # DELETED with its panel (ADR-0151): the panel declared nothing, and the chain it
    # guarded — bind, registry projection, rendered row — is held by this test plus
    # TunablesRegistryModelTest ("one row per registered slug") and TunablesRegistryViewTest.
    "PsxColorCalibrationTuneTest"
    # The Fold kernel's published surface (ADR-0191): owns(), the build predicate that was a verbatim
    # six-line copy at fourteen call sites reaching a host autoload by node-path string; shader(), the
    # two-way pick that hangs off it, asserted on BOTH branches (the off-fork half is unreachable here,
    # so the cached snapshot is overridden and restored); and the Fold.add contract, which used to be
    # asserted verbatim in both CallbackFoldRoutingTest and FormationFoldRoutingTest and now lives here.
    # owns() is checked against CompositorAutopilot.active — two independently computed values that
    # ADR-0191 dec. 1 claims are identical in every reachable state.
    "FoldTest"
    # The fold bracket as a SPEC (no GPU/scene): Pass A and Pass C were two ~90-line CompositorEffect
    # classes differing in five values; they now share one FullscreenPass and each adapter supplies
    # only its stage, shader, source, destination and quantization. Those five ARE the passes after
    # the collapse — a wrong adapter would run correct shared code against the wrong inputs — so this
    # asserts them, plus the bracket ORDER (seed's stage precedes resolve's) and setup(), the addon's
    # published interface, which had no test at all. Pixels stay FoldQuantizePolicyTest's job.
    "FoldSurfaceTest"
    # Goal #8 guard (ADR-0152): the fold's framebuffer quantization is a POLICY the bracket
    # is given, not a constant welded into its GLSL. Runs foldsurface_resolve.glsl on a local
    # RenderingDevice: an off-lattice value moves at levels=31 and not at levels=0, an
    # on-lattice value moves at neither, and the default is still 31.0 (PSX RGB555).
    "FoldQuantizePolicyTest"
    # Move-2 guard (bare tree): Projectile3D OWNS the thrown-weapon spin rate (reads
    # projectile.spin_deg_per_tick via Tune.of at its per-frame use-site); ProjectileDebugPanel
    # is a TuneField view, not a static the projectile reads.
    "ProjectilePanelTuneFieldTest"
    # Move-2 guard: ExMateriaEffectSfx OWNS the typewriter-click retrigger fade — it binds
    # audio.click_retrigger_fade_ms in _ready (setter re-arms the native mixer); SpuAudioDebugPanel
    # is a TuneField view.
    "SpuAudioPanelTuneFieldTest"
    # Whole-game volume: ExMateriaAudioEngine OWNS master_volume — applies to the Godot Master bus
    # (index 0, where music+SFX+UI re-sum) and persists it per-machine in UserSettings.
    # SpuAudioDebugPanel exposes a plain slider that delegates to ExMateriaAudioEngine.
    "AudioMasterVolumeTest"
    # The bus layout is REAL (D3 dec. 6 / #385 task 2): a committed AudioBusLayout
    # declares Master <- {Music, SFX, Ambient}, the music stream plays on Music and the
    # effect-SFX stream on SFX instead of both hardcoding Master. Transparent routing —
    # unity gain, empty racks — with the Amplify -> HardLimiter rack still MasterBus's.
    "AudioBusLayoutTest"
    # Move-2 guard: PSXDisplay.live_ui_par is now a facade over the Tune tunable
    # render.ui_pixel_aspect (bound in _ready, getter coalesces, setter routes through Tune,
    # _apply_ui_par emits live_ui_par_changed); UIDisplayDebugPanel is a TuneField view.
    "UiDisplayPanelTuneFieldTest"
    # Move-2 guard: UICombatManager OWNS the roster-view placement knobs — it binds per-column
    # roster.friendly.* / roster.enemy.* slugs (independent namespaces, screen_pos split X/Y),
    # so an override coalesces onto a column AND a scrub re-drives it.
    "RosterViewTunablesTest"
    # Move-2 guard: SkirtConfig's parameters are Tune tunables — each property getter
    # coalesces the skirt.* override over its PROPERTY_META default; readers use
    # SkirtConfig.<prop> unchanged; SkirtDebugPanel is a data-driven TuneField view.
    "SkirtConfigTuneTest"
    # ADR-0068 R1 / ADR-0167 (#555): the map's two panels are mounted HOST-side by
    # MapDebugPanels, not by MapComposer — the production owner of the tunables must not
    # instantiate their view. Three arms: the mount wires the composer that was passed in;
    # a second call rebinds instead of stacking a copy; and no file under src/map/ names
    # DebugOverlay or either panel class IN CODE, which is the only arm that reports the
    # REMOVAL (the first two pass with the old registration still sitting beside the new).
    "MapDebugPanelMountTest"
    # Move-2 guard: TileOverlayConfig's per-type params + UV crop are Tune tunables —
    # get_param / uv_* getters coalesce tile.* overrides, set_param routes through Tune, a
    # Tune.value_changed→changed bridge re-applies tiles; TilesDebugPanel's per-type rows
    # rebind to the selected type's slugs.
    "TileOverlayConfigTuneTest"
    # Move-2 guard: UIUnitInfoWindow OWNS its vitals layout — it binds every vitals.* slug in
    # _ready (Vector2 split X/Y, per-stat arrays split by index), so an override coalesces into
    # the property at boot AND a scrub re-drives it; VitalsLayoutDebugPanel is a TuneField view.
    "VitalsLayoutTunablesTest"
    # Cross-board sync (bare tree): two TuneField rows on the SAME slug (as if in two
    # panels, or a panel + the registry) stay in lockstep — the "repeat controllers"
    # property the framework gives for free via the per-row Tune binding (ADR-0068).
    "TuneFieldSyncTest"
    # Registry page (ADR-0068 decision 9): the pure projection of every registered slug
    # + metadata (default/value/type/range/dirty), and the view that renders it as a
    # table whose value cells are TuneField-bound (so a registry edit writes the slug).
    # The View arms also hold the find box, graded by the ROW SLUGS a driven
    # `text_changed` produces, and the build/filter split behind it: filtering toggles
    # `visible` on all six cells of a row (the table is ~505 ms to construct on the live
    # registry), so the arms assert a keystroke burst moves neither rebuilds() nor
    # table_builds(), while a lazily registered slug still moves both.
    "TunablesRegistryModelTest"
    "TunablesRegistryViewTest"
    # Pure-logic schema guard (no GPU): unit encode round-trip (ADR-0003)
    "UnitEncodeSchemaTest"
    # Pure-logic guard (no GPU) for the LEVER LAYER (ADR-0277): the strict
    # partition over all 512 abilities, ten DIRECTION-TESTED guard arms (each
    # seeds one defect and then re-asserts the corrected control, so an arm
    # cannot pass by rejecting everything), the three tiers multiplying,
    # round-half-away-from-zero with the capability/cost floors, the partial-
    # coverage report, and that the digest hashes the OUTPUT (it moves on a
    # factor and not on a reworded `why`).
    "LeverSetTest"
    # Pure-logic turn-queue guard (no GPU): the turn meter arithmetic, the
    # round-robin-deep forecast, and its closed-form jump checked against a
    # brute-force one-tick-at-a-time oracle (ADR-0236).
    "TurnQueueTest"
    # The view over it (#893, design S6): one frame per TURN and not per unit (a
    # fast unit appears twice in one round-robin), the strip's order IS the
    # forecast's, the two teams face each other, and an unchanged queue reuses its
    # frame objects rather than rebuilding every portrait on every turn edge.
    # Driven through `show_entries`, so no GPU, no director and no battle.
    "TurnQueueHudTest"
    # Pure-logic interpreter guards (no GPU/scene): the interpreters are pure
    # RefCounted modules reading only the string-keyed snapshot dict. These
    # tests already existed but were never wired into the harness — registering
    # them locks the pure-module contract against drift. Movement: new/
    # continuing/no-move step classification + per-unit step-id dedup +
    # staleness guard (ADR-0017). Combat: event sequencing, death precedence,
    # hp/mp/stat/projectile diffs, cast-step dedup (ADR-0018).
    "GPUMovementInterpreterTest"
    # Pure-logic guard (no GPU): a pass-through step spans SEVERAL tiles — the
    # mover lands a unit past an ally — so the visualizer walks it one tile edge
    # at a time and jumps the edges that are cliffs. Read end to end, a `1 2 1`
    # row with an ally on the 2 has y_delta 0, took the flat branch, and slid the
    # sprite a full half-step INSIDE the tile it should have hopped: "units walk
    # through walls". Arms sample the rendered path against the terrain under it.
    # Also holds the phase scaling a HASTE-halved budget needs.
    "GPUPassthroughLegTest"
    "GPUCombatInterpreterTest"
    # Pure-logic guard (no GPU): body anim id is one field with two writers —
    # UnitDisplay.play_body funnel across SEQ/EVTCHR + idle reset, and the
    # Unit.current_anim_id read-only getter (ADR-0053). Existed unwired.
    "UnitCurrentAnimIdTest"
    # Pure-logic gambit encode guards (no GPU): config-dict->buffer (ADR-0016)
    # and Gambit-object->config projection + UNSUPPORTED skip (ADR-0023)
    "GambitEncodeSchemaTest"
    "GambitEncoderTest"
    # Pure-logic guard (no GPU): the encoder-injected safety-net gambit at slot
    # MAX_USER_GAMBITS — ATTACK/NEAREST_ENEMY/ALWAYS, authored cap, buffer slot 5
    # (ADR-0048)
    "GambitSafetyNetTest"
    # Pure-logic guard (no GPU): the gambit's ENGLISH, 60 strings pinned as
    # literals — every noun, team word, resolution word, action line, six-line
    # shape and all 19 condition sentences, plus `str(gambit)`, which
    # `GambitBattle._report_prune` prints to a PLAYER. Written BEFORE #1160
    # moved the surface out of the almanac (ADR-0280 dec. 4) so a byte-identical
    # run on the far side is evidence rather than a pin on the destination.
    "GambitProseTest"
    # Pure-logic rollout guards (no GPU), #895 §7. Candidates: the incumbent is
    # candidate 0, no operator touches ADR-0048's safety-net slot, the list is
    # deterministic and deduped, and the STATIC-only legality prefilter bites
    # (an ability past the unit's MAX MP is never offered) with a positive
    # control so "never offered" cannot pass by offering nothing. Seeds: the
    # common-random-number spacing, proved against the shader RNG's actual hash
    # inputs from BOTH sides of the boundary rather than against its own formula.
    "RolloutCandidatesTest"
    "RolloutCrnSeedsTest"
    # Pure-logic guard (no GPU): #896's value function. Arm 1 is a CROSS-LANGUAGE
    # pin — `RolloutValueFunction.feature_vector` and `features_from` in
    # tools/fit_value_function.py are one function written twice, and a
    # divergence between them is invisible (every score stays a probability, every
    # candidate still ranks, the AI just plays worse than its calibration claims).
    # Also: the two perspectives must sum to 1, a malformed row must refuse rather
    # than return a plausible 0.5, and a tie must fall to ADR-0246 dec. 2's
    # unmutated incumbent so the AI does not re-plan a working posture every turn.
    "RolloutValueFunctionTest"
    # Pure-logic guard (no GPU): #897's BUDGET. The AI's cap is spent by
    # PREDICTION and never by a stopwatch — a beat sized by a clock would search a
    # different number of candidates every time the box was busy, and the AI would
    # play a different move on the same position. Arm 1 is the only one that can
    # catch a fiction: it compares the cost model against ADR-0253 dec. 9's own
    # measured milliseconds, where every other arm would pass against any smooth
    # curve. The rest: the ladder drops M before K and never H, it refuses rather
    # than shorten the horizon, and the SHIPPED defaults take no rung at all.
    "RolloutDriverTest"
    # Pure-logic guard (no GPU): StatusRegistry name↔bit map mirrors
    # combat_common.glslinc; drift assertion + bitmask helpers (#67)
    "StatusRegistryTest"
    # Pure-logic guard (no GPU): FFTPatcher CamelCase -> StatusRegistry bit
    # translation at the encode boundary (issue #98)
    "StatusEncoderTest"
    # End-to-end inflict_mode=all tracer (issue #98): Poison spell + Blind
    # Knife both inflict via the encode boundary -> GPU buffer -> compute
    # shader path
    "GPUStatusInflictTest"
    # End-to-end inflict_mode=cancel tracer (issue #100): Antidote on a
    # poisoned self -- bit clears + decay-timer slot frees
    "GPUStatusCancelTest"
    # The decay engine, producer AND consumer (#1116). Was in skip_tests.tsv as
    # red since #542 ("HASTE timer clears 8 ticks off a +/-3 tolerance") — the
    # rule was never wrong, the instrument was: the bit is sampled per FRAME and a
    # frame banks as much wall clock as it took, so the window measured the box.
    # One-sided now (early is the defect, late is the sampler and the cinematic
    # pause), and it gained the arm nothing in the suite had: a status INFLICTED
    # in battle, whose countdown is read out of the buffer and must be the ROM's
    # 24 CT, clearing on its own.
    "GPUStatusDecayTest"
    # Faith-scaled hit% for formula-10/11 status (issue #103): Faith=0 immune,
    # Faith=90 inflicted reliably across the test window
    "GPUStatusHitRateTest"
    # The two modes the shader used to drop (#1117): LookofDevil (random, five
    # statuses) must set EXACTLY ONE, and GrandCross (separate, nine statuses,
    # radius 2) must roll each of them per target -- 27 independent rolls in one
    # cast, so its three targets must not all come out alike. The arm no other
    # mode can satisfy is that third one; ALL, CANCEL and the old fall-through
    # all make the three targets identical.
    "GPUInflictModeTest"
    # GPUEsunaAllyTest was HERE and is DELETED (2026-08-22) — see ADR-0049's
    # "Known drop" note. It witnessed the ADR-0049 hit policy end-to-end and
    # was removed for load-dependent flakiness, not because the claim stopped
    # mattering. What it uniquely held is the COMPOSITION; the two halves are
    # still guarded (scenarios_I_aoe.gd, GPUStatusCancelTest).
    # Issue #110 element-defense witness pair: Fire vs Flame Shield (id 135)
    # composed from items.json absorbs into a heal; Fire vs Fire-cancel target
    # deals 0 damage. Together they cover the encode-boundary path (item ->
    # mask composition) and the shader apply site (Phase 2 negative amount /
    # Phase 3 cancel short-circuit).
    "GPUElementAbsorbTest"
    "GPUElementCancelTest"
    # Issue #111 job-innate element-defense witness: Bomb job (0x64) absorbs
    # Fire from its job innate alone (no Flame Shield) — covers the
    # _build_gpu_config job_id plumb that mirrors the production
    # _extract_unit_config OR.
    "GPUBombFireAbsorbTest"
    # Issue #112 status-driven element-defense overlay (apply_element_defense
    # in combat_common.glslinc). Float×Earth → 0 damage (cancel), Oil×Fire →
    # ×2 BEFORE the equipment matrix. Composition tests lock in the ordering:
    # Oil+Fire-Half nets ×1, Oil+Fire-Absorb heals 2×, Float+Earth-Absorb
    # still HP-flat (Float preempts the absorb path).
    "GPUFloatEarthCancelTest"
    "GPUOilFireDoubleTest"
    "GPUOilFireHalfCompositionTest"
    "GPUOilFireAbsorbCompositionTest"
    "GPUFloatEarthAbsorbCompositionTest"
    # Issue #116 weapon-element defense on basic attacks (apply_weapon_element_
    # defense in combat_common.glslinc). Mirrors BATTLE.BIN FUN_80186FD0 at
    # 0x80186FD0: equipment matrix only, NO status overlay. Absorb/Half/Weak
    # ratios on Flame Rod basic-attack damage; the load-bearing NoStatusTest
    # locks in the ROM-faithful divergence from FUN_80186FF8 (spell path);
    # NoElementUnaffected covers the element_id == 0 pass-through.
    "GPUWeaponFireAbsorbTest"
    "GPUWeaponFireHalfTest"
    "GPUWeaponFireWeakTest"
    "GPUWeaponElementNoStatusTest"
    "GPUWeaponNoElementUnaffectedTest"
    # Issue #117 -- attacker-side Strengthen-Elem (BoostElem). 5/4 AbPower scale
    # on the spell-side queue site. Two-Mage relational shape (unblocked by
    # #118 concurrent cinematics): StrengthenMage + ControlMage cast Fire on
    # separate defenseless targets the same tick; asserts strengthen_delta ==
    # (control_delta * 5) / 4 with no hard-coded baseline. Doubles as a #118
    # regression witness alongside GPUSimultaneousCinematicTest.
    "GPUStrengthenFireTest"
    # Issue #118 -- per-caster cinematic timer + U_PAUSED ref-count. Two Mages
    # finish Fire (ct=4) cinematic on the same GPU tick; both targets must take
    # the EXPECTED_BASE_DAMAGE (168) hit. Pre-fix the second cinematic stomped
    # the battle-scoped BH_CINEMATIC_CASTER_IDX slot and the loser's stamps got
    # wiped by the winner's teardown -- one cast silently void'd.
    "GPUSimultaneousCinematicTest"
    # Pure-logic pump guard (no GPU/SPU/overlays): effect timeline orchestration (ADR-0012)
    # Deterministic scrub seek (ADR-0070): EffectTimeline.seek() is frame-exact,
    # forward-pumps the delta / backward reset()s+re-pumps from 0, and reset()
    # re-applies the per-instance RNG seed. Pure stub-track logic, no GPU.
    # Per-instance seeded RNG determinism (ADR-0070): the physics spawn helpers,
    # a real ParticleSubsystem's full cloud, and camera shake all reproduce
    # bit-identically under a seeded RNG — and a back-and-forth scrub lands the
    # exact same frame-N cloud. Loads a real effect dir; RD-free.
    "EffectRngDeterminismTest"
    # Particle homing SIGN gate: negative homing_strength REPELS (flee/dispersal), it is
    # not "no homing". Regression for E142 emitter 15 (outward radial orientation).
    # Derived effect END (EffectEndModel): simulates the cast (RD-free, the ADR-0070
    # harness) to the frame the real engine reaps it — particles gone, NOT the last
    # authored keyframe — so the Studio marks the real end + clamps the playhead to
    # it (a screen tint authored far past the particles, e.g. E173, is trimmed).
    "EffectEndModelTest"
    # Pure-logic façade guard (no GPU/DB): AbilityView coercion/defaults (ADR-0008)
    "AbilityViewTest"
    # Pure-logic guard (no GPU/DB): the ability-picker full-CATALOG rules (ADR-0197 scaffold) —
    # AbilityCandidates.build_catalog: R/S/M every-of-type + secondary every-job-by-skillset-name,
    # placeholder ("(Nothing)"/blank/nameless-monster) rows dropped, {id,name} name-sorted id tie-break.
    "AbilityCandidatesTest"
    # Pure-logic guard (no GPU/scene): the Learn job-picker's full-CATALOGUE rules — the job
    # sibling of AbilityCandidatesTest. JobCandidates.build_catalog: every job in jobs.json
    # carrying >=1 JP-costed learnable (80 of 160, generic + special + monster; the barren 80
    # dropped as hygiene, not a gate), {hex-string id, name} name-sorted with the JOB INDEX as
    # tie-break — the six colliding "Squire" indices (01/02/03/04/07/4a, 03 carrying Ultima)
    # are what makes the index, not the name, the key.
    "JobCandidatesTest"
    # MOVED OUT, NOT DROPPED (ADR-0194 / #652), the battlefield half: TileCursorCompositorTest,
    # MapAtlasDilateTest, MapIlluminationDDATest, MapUVClampBakeTest and
    # ScenarioEventPathfinderTest now live in addons/exmateria_battlefield/tests/ and are run
    # by `bash tests/stranger/exmateria_battlefield/run.sh`. That rig carries a NAMED burn-down
    # of three files that do not compile in a stranger project at all
    # (tests/stranger/exmateria_battlefield/known_failures.tsv) — goal #5 unmet, on record.
    # MOVED OUT, NOT DROPPED (ADR-0194 / #652). DepthModeTest, ColorRecipeTest and
    # ColorStackGpuParityTest reach nothing but addons/exmateria_schema, so they now
    # live in it — addons/exmateria_schema/tests/ — and are run by
    # `bash tests/stranger/exmateria_schema/run.sh` in a project that did nothing
    # for the addon. Listing them here would run them in the host project, which is
    # exactly the project whose absence is the claim (dec. 4). Their pre-move
    # assertion counts are recorded as `# moved` rows in docs/TEST-BASELINE-E2.tsv;
    # ColorStackTest stays, because it names a host autoload.
    # Pure-logic guard (no GPU/scene): ColorStack — the unified colour model's CPU
    # source of truth (ADR-0067). Per-surface layer list, DDA progress eval at `now`,
    # symbolic merge of settled affines (bounds the 8-layer budget), luma/mask/source
    # packing, and the material uniform push. The ColorStack.gd side of the include.
    "ColorStackTest"
    # Pure-logic guard (no GPU/scene): PaletteSubsystem drives the combat-colour
    # ColorStack faithfully from parsed keyframes (ADR-0067 deferred combat route,
    # issue #164) — the palette applier color_tint_blend_apply @0x8008f710 mirror
    # (5-bit CLUT, quantize=true, absolute base). Additive stays on-grid; luma and
    # modes 4-7 fold over the real base (the fix vs the old delta-on-0 short-circuit).
    "PaletteSubsystemTest"
    # Pure-logic guard (no GPU/scene): MapTintOverlay delivers the map illumination as the
    # additive `map_illum_add` uniform alongside the 5-bit CLUT color_layer_* stack —
    # per-owner sum, neutral 0 when idle, cleared on effect removal.
    # Pure-logic guard (no GPU/scene): UnitTintOverlay concatenates per-owner combat
    # ColorStack snapshots into the color_layer_* uniforms (ADR-0067 combat route,
    # issue #164) instead of the retired additive unit_tint uniform; additive bridge
    # (TrapPaletteController) + empty-clears-to-no-op covered.
    "UnitTintOverlayTest"
    # Pure-logic guard (no GPU/scene): ScreenSubsystem blend math applies params at
    # ×1, not the spurious ×2 (ADR-0067 combat Task B, issue #164 — screen applier
    # screen_tint_apply @0x80090840 is the 16.16 framebuffer engine, param ×1). Mode
    # structure (byte_register source, luma divisors, restore/stop) pinned unchanged.
    "ScreenSubsystemTest"
    # Pure-logic wiring guard (no GPU, no SPU): game-event SFX routing (ADR-0006)
    "SfxRouterTest"
    # Pure-data guard (no GPU/map): scenario-sourced placement — deployment-zone
    # + ENTD databases, can_source/red-first/clamp (ADR-0043)
    "ScenarioPlacementDataTest"
    # Pure-logic guard (no scene/VM): PsxNum event-script numeric conventions —
    # sign extension, u16 LE packing, the 12-bit CW facing wheel, ADR-0052 depth-flip
    "PsxNumTest"
    # Pure-logic guard (no scene/VM): PsxUnits continuous magnitude ↔ game-unit
    # conversions (ADR-0091) — the ONE home for tiles/angles/velocity/accel scales,
    # golden-valued against parse_effect.py so a regression can disagree.
    "PsxMagnitudeTest"
    # Pure-logic guard (no scene): PSXCameraConvert facade → PsxUnits/CameraCalib
    # (ADR-0091 step 3) — golden angle/tile/zoom↔ortho numbers unchanged post-repoint.
    "CameraConvertParityTest"
    # Pure-logic guard (no scene): ParticlePhysics.angle_to_direction golden cloud
    # (ADR-0091 step 6) — emission launch base locked byte-identical (DOWN convention).
    # Pure-logic guard (no scene/VM): ScenarioDecode opcode decode layer — Warp Unit
    # intent (placement + spawn facing) and Sprite Move axis-remap + Beta duration
    "ScenarioDecodeTest"
    # Pure-logic guard (no scene/VM): ScenarioPlayerScene._chunk_reveals_first —
    # frame-0 unit visibility is chunk-derived ({44} Draw / {45} Add Draw=1 hide;
    # {46} Erase / Add Draw=0 / no-op show), NOT the ENTD always_present flag.
    # Oracle = scn6 (Ovelia/Delita/chocobo hidden, Agrias visible despite a later
    # Draw) + scn1 (walk-ins hidden, Simon visible). SCENARIO6_UNIT_REVEAL_VISIBILITY.md
    "ScenarioUnitVisibilityTest"
    # Integration guard (real scene): PATH-MODE boot to member scenario 6 spawns
    # the roster once against the group-ROOT chunk (scn3 Setup, no Ovelia vis-op),
    # then walks to member 6. Parks at PC 115 and asserts Ovelia(0x0C)+Delita(0x05)
    # are BOTH hidden — the case the pure test can't catch (visibility must follow
    # the LOADED member chunk, not the boot chunk). SKIPS if scn3/6 chunks absent.
    "ScenarioDoorwayRevealTest"
    # Integration guard (real scene): the LATE-ADD sibling of the doorway case.
    # scn6 units 0x01 @ (0,4) / 0x04 @ (0,3) are always_present=false, introduced
    # only by a lone {45} Add Draw=0 at pc434 (next-scene setup, camera panned away).
    # Path-boots member 6, parks at PC 382, and asserts BOTH stay hidden — render
    # visibility gates on PRESENCE, so a not-yet-added unit isn't drawn ~434 instrs
    # early. SKIPS if scn3/6 chunks absent.
    "ScenarioLateAddVisibilityTest"
    # Integration guard (real scene): a hidden-but-PRESENT unit stays a team-
    # broadcast target. scn6 Ovelia (0x0C, always_present, spawns hidden) must be
    # turned by the pc31 player-team broadcast Rotate — the roster keys on
    # scenario_present (allocated), not render .visible. Parks past the pc25-31
    # Facing=8 rotates and asserts Ovelia's facing == Agrias's. SKIPS if scn3/6 absent.
    "ScenarioBroadcastRotateHeldTest"
    # EventInstructionSet catalog loader (ADR-0059): descriptor lookup by opcode
    # byte / EventInstruction value returns the expected name/params/verified, and
    # the Unknown set (48 unnamed opcodes) the byte-keyed dispatch auto-skips.
    "ScenarioEventInstructionSetTest"
    # EventInstruction coverage gate (ADR-0059): every verified:true opcode is
    # bound-or-skipped in the ScenarioVM registrar (else it halts mid-scene);
    # mirrors the VM's soft boot push_warning.
    "ScenarioEventInstructionCoverageTest"
    # VM guard: {43} Call Function has a loud NON-halting stub (screams via
    # push_error every call but keeps _running=true, unlike {92} Inflict Status),
    # and the play_through_skip_unknown setter re-arms _running on OFF->ON so the
    # "Play-through" checkbox resumes a halted VM. Regression for the scn6 Delita
    # render blocker (issue #155 / 2026-07-05 handoff).
    "ScenarioCallFunctionStubTest"
    # VM guard: {43} Call Function 4 = the battle->scenario-6 dead-unit fade
    # (SCENARIO6_DEAD_UNIT_FADE.md, ROM FUN_80147cf0). Sweep selects on-field
    # non-persisting-side units (scenario_team_color != 0 AND scenario_present),
    # runs the two-pass mode-4 fade (Δ=-31,-31,0 then -31,-31,-31 -> black), hides
    # them, and holds the VM 120 ticks. Spares the persisting side + staged actors.
    "ScenarioDeadUnitFadeTest"
    # Combat->scenario POSE CARRY at the woven victory-beat start() ("dead units
    # stand up before the scn6 fade"): reset_scenario_cutscene_state(preserve_pose)
    # keeps the combat-committed current_anim_id (corpse/kneel/idle) instead of
    # re-arming idle, threaded start(fresh, preserve)->reset_all->unit. Default off
    # keeps the rewind/replay + non-victory idle baseline; facing/cinematic still reset.
    "ScenarioCombatPoseCarryTest"
    # Pure-logic guard (no scene/VM): EventInstructionArgs (ADR-0059 Phase 2) —
    # the typed operand reader replacing _params_dict. Name + positional access,
    # duplicate-name preservation ({6A} two-Unknown), width/type/signed decode.
    "EventInstructionArgsTest"
    # Pure-logic guard (no scene/VM/nodes): ScenarioApply — the apply layer that
    # turns a decoded intent into world mutation through ScenarioWorld verbs
    # (ADR-0058), asserted against a FakeScenarioWorld that records the verb calls
    "ScenarioApplyTest"
    # Pure-logic guard (no scene/VM/nodes): ScenarioMotion — the scene-free cutscene
    # motion value object (ADR-0055). Lerp endpoints/midpoint, advance/is_done/frac
    # clamp, snap_to_end, and the bit-exact _sprite_move_curve easing port (4 types)
    "ScenarioMotionTest"
    # Pure-logic guard (no scene/VM/nodes): ScenarioPathMotion — the {28} Walk To
    # per-tile route/gravity-arc stepper (ADR-0055). Polyline cadence, flat = no arc,
    # descending = staircase-not-ramp (the scn6 Agrias regression), accelerating
    # gravity drop, turning route + per-segment re-face, snap_to_end.
    "ScenarioPathMotionTest"
    # Pure-logic guard (no scene/VM/combat): ScenarioDirector — the BattleConditionals
    # Pure-logic guard (no scene): BattleConditionalSet — the catalog loader +
    # descriptor + shared-reader mint for the BattleConditionals mini-ISA
    # (ADR-0059 sibling of EventInstructionSet). Descriptor-by-opcode, enum
    # round-trip, and args() reading operands by name.
    "BattleConditionalSetTest"
    # interpreter. Orbonne deploy/chat/victory chain + Mandalia menu-choice and
    # Algus-alive-vs-KO'd victory branches, evaluated against the real BTLEVT artifact
    "ScenarioDirectorTest"
    # Pure-logic guard (no scene/VM/combat): ScenarioPath — the debug-navigation
    # planner. Plans the Orbonne route to member 5 against the real BTLEVT artifact,
    # asserts the synthesized ForcedDirectorStates drive the director to each member,
    # and that first-match-wins preemption is reported (not lied about).
    "ScenarioPathTest"
    # Pure-logic guard (no scene/VM/GPU): GameNavigator — the story-graph WALK
    # planner (decision #179). Reads the real transition_graph.json + groups and
    # emits the ordered beat sequence: one linear group's SCENARIO member beats, a
    # battle group's setup/opener/victory weave (mid beat skipped), and the full
    # Orbonne milestone walk group 1 -> 3(battle) -> 7 with ATTACK/exit chaining.
    "GameNavigatorTest"
    # Pure-logic guard (no scene/VM/GPU): ENTD battle-init (navigator T3, decisions
    # #180/#181). UnitNames special_name->story name resolver; Character.from_entd_slot
    # canonical-vs-factory build (job/level/brave/faith/equipment/gender) over the real
    # ENTD-387; and the team_color split (9 Blue/7 Red). Data-driven, no rendering.
    "EntdBattleInitTest"
    # Pure-logic guard (no live scene/VM/GPU): NavigatorRunner — the runtime
    # navigator's orchestration state machine (T2/T4/T5, decision #179). Drives an
    # injected fake executor through the Orbonne walk SCENARIO -> opener -> combat ->
    # victory -> terminal SCENARIO, advancing on the finish callbacks; v1 defeat halts.
    "NavigatorRunnerTest"
    # Bare-construct guard (no scene/GPU boot): COMMAND MODE toggle (ADR-0082). Tab is the ONE
    # command-mode ⇄ Live toggle — Deployment→Live (resume_pre_battle), Live→Paused (freeze the
    # loop), Paused→Live (re-arm) — and go-live swaps IDLE→the pending COMBAT gambits. The real
    # frozen-loop build + cursor-seeded-on-leader are proven headful (NavigatorCommandModeProofTest).
    "NavigatorCommandModeTest"
    # Bare-construct guard (no scene/GPU boot): the "melee attacks spawn almost no hit-cloud traps"
    # bug, re-grounded on ADR-0083. Combat bodies were double-advanced (CombatLoop.tick + the VM idle
    # pump), racing the SEQ 0xDE hit-cloud opcode ahead of the GPU damage tick → is_hit read stale →
    # traps never spawned. Now _go_live hands the cast off SCENARIO→COMBAT and the VM pump skips
    # COMBAT-owned, so a combat body rides ONE clock — while an ambient SCENARIO NPC keeps breathing.
    # Headful-verified on real Gariland: 0 clouds (double-pump) → 3 clouds (single clock) over the span.
    "NavigatorLiveCombatDoublePumpTest"
    # Pure-logic guard (no scene): CatalogueReplay (ADR-0201) — folds a beat-keyed
    # mutation script (create/join/leave/die) into a fake catalogue; fold(N) == union
    # of deltas 0..N-1, idempotent + composable.
    "CatalogueReplayTest"
    # Pure-logic guard (no scene): SlugBinding (ADR-0201) — lifts (context, uid) -> slug,
    # hit returns the Catalog Character, miss falls back to ENTD-slot construction and is
    # recorded as a shrinking coverage gap; uid is context-local; specials bind first.
    "SlugBindingTest"
    # Guard (no scene): the DERIVED mutation script (ADR-0216) folded over the real
    # transition graph — Gariland grants nobody and the Academy grants Delita + six
    # cadets (the authored table had it backwards), a group's joins land at its END, the
    # fold equals RosterTimeline.roster_before, guests are catalogued but never owned,
    # repeat appearances emit nothing, and the protagonist is minted new-game rather than
    # read off his Chapter-2 cinematic ENTD slot.
    "StoryMutationScriptTest"
    # Integration guard (no scene boot): the REAL NavigatorRunner driving the REAL
    # CharacterCatalog through the derived script (ADR-0201/0216) — a seek resets to
    # new-game and folds the skipped beats' cast, preserves the roster baseline, is
    # reproducible.
    "SeekIntegrationTest"
    # Guard (no scene boot/render/sim): a direct SEEK to combat settles the fresh battle
    # world by fast-forwarding the group's opener cinematic (camera/color/{Reveal}); this
    # guards the belt-and-braces fade-reveal GUARANTEE that snaps the fade fully clear
    # (the opener's timed fade can lag past end-of-fast-play; also the sole reveal when a
    # group has no opener). Opener-replay wiring itself is scene-bound, verified headful.
    "NavigatorCombatRevealTest"
    # Masonry layout guard (headful build, no GPU/SPU): a debug panel hosted in the
    # DebugMasonryContainer must not report a combined min WIDTH > max_column_width, or it
    # bursts its column and breaks the layout (bit NavigatorDebugPanel via a non-wrapping
    # intro paragraph). Builds each scenario panel as the scenes do and measures it.
    "DebugPanelMasonryWidthTest"
    # Pure-logic guard (no GPU/SPU): global SFX bank semantic labels resolve
    "SfxCatalogTest"
    # Pure-logic guard (no GPU/SPU): equipped weapon graphic -> sound_class ->
    # swing/hit/block for basic-attack SFX (knife=1, sword=2, fists=0; PCSX-confirmed)
    "AttackSfxResolverTest"
    # Unit binding guard (no GPU): equipped weapon loads its WEP frames on bind
    "UnitWeaponBindTest"
    # Weapon/effect-sprite teardown on death/victory (no GPU): a mid-swing slash
    # must not survive the terminal state change and reappear on camera rotation
    "UnitEffectCleanupOnStateChangeTest"
    # C0 characterization golden (issue #144): pins the CURRENT resolved paint
    # output of Unit's painting complex — the (layer, frame_id, first, reversion,
    # palette, v_offset) tuples pushed to load_frame_by_id — across an (anim ×
    # facing × camera × frame × react) matrix. The safety net every commit of the
    # UnitDisplay extraction (C1a→C3b) must keep green; C4 converts it to the
    # scene-free UnitDisplay unit test. Re-record: append `-- --record`.
    "UnitDisplayPaintGoldenTest"
    # Formula tests (fast, one-shot damage checks)
    "GPUFormula01Test"
    "GPUFormula08Test"
    "GPUFormula12Test"
    "GPUFormula32Test"
    "GPUFormula36Test"
    "GPUFormula49Test"
    "GPUFormula55Test"
    "GPUFormula78Test"
    # Combat tests
    "AttackPeriodTest"
    "GPUMeleeCombatTest"
    "GPURangedCombatTest"
    "GPUSpellCombatTest"
    "GPUThrowItemTest"
    "GPUItemFallthroughTest"
    "GPUThrowStoneTest"
    "GPUPhysicalAbilityTest"
    "GPUItemCombatTest"
    "GPUAOECombatTest"
    # Which SIDE an AoE ability draws its effect on is a FAMILY question (#1148).
    # Non-cinematic only — a charged ability spawns through CinematicManager instead.
    "GPUAOEEffectSideTest"
    # System tests
    "GPUDashMovementTest"
    "GPUMoveToUnitTest"
    # RETREAT is a verb again, and it is one tile then a fresh decision (ADR-0301).
    "GPURetreatStepTest"
    "GPUTargetDiedMidWalkTest"
    "GPUSEQMovementTest"
    "GPUSpellTrackingTest"
    "GPUAOETrackingTest"
    "GPUStatusNoDamageTest"
    # Fixed tests (previously problematic)
    "GPUKnightBreakTest"
    "GPUVerticalToleranceTest"
    "GPUBreakTrapTest"
    # Hit cloud is triggered by the PostGenericAttack (0xDE) opcode, not damage
    "GPUMeleeHitCloudTest"
    "GPUDashNoHitCloudTest"
    "GPUHasteSlowTest"
    "GPUDistanceFieldTest"
    "GPUProtectTest"
    "GPUShellTest"
    "GPUAOEHealTest"
    "GPUReactDurationTest"
    # Evasion tests (slow, statistical — run manually when needed)
    # "GPUEvasionMeleeHitTest"
    # "GPUEvasionMeleeEvadeTest"
    # "GPUEvasionMeleeBlockTest"
    # "GPUEvasionMeleeParryTest"
    # "GPUEvasionRangedHitTest"
    # "GPUEvasionRangedEvadeTest"
    # "GPUEvasionRangedBlockTest"
    # "GPUEvasionMixedTest"
    # Hot path coverage tests
    "UIInteractionTest"
    # 3D-collider UI: window bodies absorb clicks (no through-click to menus or
    # tiles behind). UIFrame owns a frame-sized click-absorber Area3D.
    "ProgressionTesterTest"
    # Sprite orientation (facing vs camera) regression
    "UnitOrientationTest"
    # ADR-0057 Stage 2 single-source-of-truth: the combat-vs-cinematic idle mode
    # rides the explicit is_cinematic_unit flag, NOT the facing_angle == -1 sentinel,
    # so a combat unit carrying a real facing_angle still renders combat idle (not the
    # cinematic tent). Also pins that a combat facing write syncs facing_angle.
    "UnitCinematicIdleModeTest"
    # Phase-0 runtime Render oracle (#137, ADR-0057): each reference scene's
    # committed ENTD spawn facings → screen cardinal + camera variant + pose
    # octant through the LIVE converters. The anti-regression gate #138 (one
    # converter / derived views) must keep green. Re-record: append `-- --record`.
    "ReferenceRenderDirectionTest"
    # Phase-1 Render converter golden (#138, ADR-0057): the angle→FacingDirection,
    # angle→cardinal-bucket, and pose-octant→sprite-LUT-cardinal converters at
    # all four cardinals + between-cardinal cases. Locks the derived views so a
    # future "harmonization" can't silently flip a direction (the E/S-swap class).
    "RenderCardinalConverterTest"
    # Cinematic camera facing resolver: analytic terrain gate (ADR-0039)
    "CinematicFacingResolverTest"
    # Scenario-camera ease curve (LINEAR / COSINE_A / COSINE_B) + lerp envelope:
    # PSX dynamic capture (2026-06-24) verified LINEAR; pins curve shape +
    # `_advance_camera_lerp` constant per-tick Δ to keep the stutter fix from
    # silently regressing if the cosine modes get reordered or _curve removed.
    "ScenarioCameraEaseTest"
    # VERTICAL scenario-camera fix (camera_aim_floor_y, F8/F9): loads the real
    # ScenarioPlayer, settles, and asserts the floor-aim lands Agrias' feet
    # within ~3px of the PSX-probed native-Y 158 (vs ~29px low without it).
    "ScenarioCameraFloorAimCalibTest"
    # VERTICAL scenario-camera fix (camera_vertical_datum, F20): loads the real
    # ScenarioPlayer, settles, and asserts the screen-datum shift lands Agrias'
    # native-Y within 3px of the live-probed PSX 160 (vs ~40px high without it).
    # Root: FFT's affine-ortho projection (screen = R·SV/4096 + TR) frames the
    # optical centre at native 160, not the midpoint 120 (GTE TR decomposition).
    "ScenarioCameraVerticalDatumTest"
    # Swoop regression guard (F11/F12): drives the chapel fusion bracket with
    # floor-aim ON + a jumpy mock map; asserts the body Y descends SMOOTHLY (no
    # per-tick terrain pin, the F11 jerk) yet still floors at the settled shot.
    # Roots: scenario camera Y is a pure opcode value (FUN_801474a4 / ticker
    # 0x801439c0 read no terrain), tile-marriage only in FUN_801aab90.
    "ScenarioCameraSwoopMonotonicTest"
    # {73} Camera Move (relative) + {63} Camera Speed Curve — the {1F}-Focus-style
    # pre-patchers for the scenario-6 PC 386 orbit. Byte-exact {73} pre-patch (the
    # Zoom=0 → wide-shot teleport fix), 0x2710 keep-sentinel, no-prior-camera
    # fallback, {63} nibble decode + bit-exact §4.7 ease curve, and dispatch wiring.
    # RE: CAMERA_ROTATION_OPCODES_63_73_19_INVESTIGATION.md.
    "ScenarioCameraRelativeMoveTest"
    # Scenario-1 ENTD-sprite invariants: every referenced unit_id has the
    # right sprite_set in ENTD record 256, and every chunk-referenced uid is
    # covered by ENTD (so the Add Unit handler's visibility-only semantics
    # — mirroring BATTLE.BIN FUN_8008d05c — produce correct sprites without
    # needing Load EVTCHR parsing).
    "ScenarioEntdSpriteMapTest"
    # ENTD sprite_set -> SPR resolution rule (research/key_documents/
    # SPRITE_SET_RESOLUTION.md). Pins the scenario-6 chocobo fix and the
    # value-keyed discriminator (0x82 resolves via job even when the flags1
    # monster bit is clear; < 0x80 never reroutes).
    "ResolveSpriteSetTest"
    # ENTD special_name -> unique template folder at the scenario spawn seam
    # (ScenarioPlayerScene._resolve_template_folder, ADR-0072 #223). Pins: residue
    # unique -> owned folder; generic/absent special_name -> "" (flat store). The
    # spawn seam that feeds the DialogueBox in-battle portrait its OWNED portrait.tga.
    "ScenarioTemplateFolderTest"
    # ADR-0081 appearance-type templates + the formation "all templates" view.
    # CharacterTemplateResolver's fifth dialect: a Character with a template_token
    # resolves TEMPLATE_ROOT+token -> folder (the townsperson/monster sheets no job
    # points at); the other four dialects stay byte-identical.
    "CharacterTemplateResolverTest"
    # FFT stores no zodiac byte — the sign is DERIVED from the ENTD birthday. Pins
    # UnitProgression.zodiac_from_birthday (12-way partition + calendar-wrap edges),
    # the UnitBirthdays special_name->birthday table (Agrias=Cancer, Ramza=Capricorn),
    # and Character.from_entd_slot setting the zodiac from a concrete birthday.
    "ZodiacFromBirthdayTest"
    # The seeder mints one owned Character per body-bearing template (unique by
    # special_name, appearance/generic by token) and proves EVERY one resolves to a
    # real body.tga folder — the "no un-routable unit" spec, checked vs the filesystem.
    "AllTemplatesSeederTest"
    # Row-granular scroll windowing of the 8-cell grid over a >8 roster: window slice,
    # last-page + advance-clamp, short/empty rosters. Pure index math.
    "FormationScrollWindowTest"
    # The formation render path resolves clean inputs (folder + seq/shp from the
    # template's own metadata) for all ~156 body-bearing templates, so mounting the
    # full roster raises ZERO "[Formation] no sprite/animation" warnings.
    "FormationAllTemplatesMountTest"
    # Scroll-perf caching (follow-up to ADR-0081): the body-material template is built
    # ONCE and duplicated per cell (not re-loading unit.tres + its WEP1/EFF1 TGAs per
    # scroll), and returning to an already-shown scroll offset re-binds cached body
    # textures instead of re-decoding them off disk — the ~9x scroll-hitch fix.
    "FormationScrollCacheTest"
    # Scroll-refresh (ADR-0081 follow-up): a ↓ at the bottom row scrolls the window so a
    # NEW unit slides under the STATIONARY cursor; _try_scroll must route through
    # _update_vitals_for_selection so the vitals panel + RIGHT info panel + portrait
    # follow the freshly-windowed unit instead of showing the stale pre-scroll one.
    "FormationScrollSelectionTest"
    # Unified BODY palette-row resolver (SpritePaletteResolver, two-axis CLUT
    # rule — research/working_documents/EVTCHR_CLUT_RESOLUTION.md §3.1). Pins:
    # monster -> JOB row; generic human -> ENTD byte passes (rows 0-4); named
    # unique SPR (Delita 0x05) -> byte 2 CLAMPS to row 0 (else all-black row).
    "ResolveBodyPaletteRowTest"
    # Combat / roster-spawn BODY palette axis (SpritePaletteResolver.
    # job_body_palette_row — the single JOB-axis owner shared by Unit.change_job,
    # UnitSpawn.build, and the resolver's monster branch). Pins: monster ->
    # variant row, special non-humanoid (Holy Dragon 0x48=3) NOT clamped away,
    # humanoid -> 0; and that roster spawn propagates the row onto the live Unit.
    "CombatBodyPaletteRowTest"
    # On-map DialogueOverlay (event opcode 0x10, Dialog=0x09 prayer): the
    # token-walking typewriter contract ({Delay} spends exact frames, one glyph/
    # tick, control tokens drain free) and the 60 Hz tick-lock (refresh-rate-
    # invariant reveal — 1s @144fps == @60fps).
    "DialogueOverlayTest"
    # Boxed-portrait DialogueBox (event opcode 0x10, Dialog=0x1X/0x9X): the ui3
    # assembly's typewriter reveal, header/body palette runs, triangle up/down/
    # flip, and in-place {51} swap (boxed_dialog_decode.md).
    "DialogueBoxTest"
    # Pure-logic guard (no scene/VM): DialogueBoxPlacement — the native-px PSX
    # box/tail/portrait/▼-arrow order-of-ops, pinned against the live authored-
    # operand captures (dialogue_box_triangle_aim_decode.md §2 tri_boxX + §7.4
    # arrow/portrait-side). Locks the projection→centre→clamp→+=authored→clamp
    # sequence so the clamps interact with the authored offsets identically.
    "DialogueBoxPlacementTest"
    # Boxed Display Message wiring in ScenarioVM: Dialog-byte routing, advance
    # gate (Wait For Instruction), Change Dialog close/swap, auto-advance dwell,
    # driven against the real scenario_1 chunk.
    "ScenarioBoxedDialogTest"
    # {0x50} Portrait Row: the EVTFACE event-dialogue portrait selector (Balbanes
    # deathbed, scn14). ScenarioDecode.portrait_row/column/visible (col = byte-1,
    # face IFF (Dialog & 0x70)==0x10 AND byte in [1,8] — replaces the incomplete
    # `!= 0x09` gate), the VM binding + row latch (scn14 real chunk no longer
    # HALTS at instr 34), EvtFaceCatalog (row,col)->texture, and the end-to-end
    # scn14 {50} 0x00 + {10} Portrait 0x01 => EVTFACE(row0,col0) resolution. See
    # research/working_documents/PORTRAIT_ROW_OPCODE_50_EVTFACE.md.
    "ScenarioPortraitRowTest"
    # {1A} Map Darkness "oxide" screen tint (prayer-scene darken/untint):
    # Blend==4 byte-add target math, Time*8 duration, the accumulator ramping as
    # pure PSX RAM state (the subtractive quad was a proven phantom and has been
    # removed), and the real chapel chunk's two prayer arms not halting.
    # See research/.../map_darkness_oxide_decode.md.
    "ScenarioMapDarknessTest"
    # Shared ScreenOverlayQuad base — the cull-proof NDC-quad recipe every
    # full-screen overlay ({76}/{3E}/{7D}/{91}) shares: 2x2 QuadMesh, material
    # override, shadows off, the oversized custom_aabb that dodges frustum cull,
    # and that all four effect classes actually extend the base.
    "ScreenOverlayQuadTest"
    # {3E} Color Screen full-screen ABR-blended colour ramp (scn8 fade-to-black
    # scene-out): ScenarioDecode.color_screen 9-byte body, the ScenarioColorScreen
    # ramp stepping (0,51,102,153,204,255 every 2 ticks, Mode->blend shader,
    # draw-skip at black), the {E5} Task=12 kind-0xC blocking, and the real scn8
    # chunk's {3E} not halting. See research/working_documents/COLOR_SCREEN_OPCODE_3E.md.
    "ScenarioColorScreenTest"
    # {0x32} Color Unit per-unit palette tint (the Orbonne door-exit fade):
    # ScenarioColorTint's affine (scale,bias) model vs a live PSX CLUT capture
    # (mode 1 = byte-exact >>1 halve, mode 8 = ramp back to base, fast=8 frames),
    # plus _op_color_unit wiring + Reset Palette clearing the tint.
    # See research/working_documents/UNIT_FADE_COLOR_UNIT_OPCODE.md.
    "ScenarioColorUnitTest"
    # Color modes 2/3/6/7 LUMA (the sepia/brown flashback wash in scn 8/14/203/285):
    # ScenarioColorTint.luma_out5 byte-exact vs the live scn8 CLUT (227/227), apply()
    # latching the luma spec (div/from_base/delta5), the VM pushing luma uniforms to
    # unit + map shaders (field luma dominates each unit), and the Time>0 delta ramp.
    # See research/working_documents/COLOR_TINT_LUMA_MODE_SEPIA.md.
    "ScenarioLumaTintTest"
    # {0x66} Commit Palette: bakes the live {33} Color Field field-tint into the
    # BASE map palette (MapComposer.bake_field_tint / commit_field_tint, byte-exact
    # vs the PSX committed blue base), the VM handler + post-sweep bind, and the
    # end-to-end regression (a later flash mode-8 restore lands on the committed
    # blue base, not the raw warm palette — the scenario-3/4/5/6 map-hue bug).
    # See research/working_documents/MAP_HUE_WEATHER_STATE_CLUT_BAKE.md §0.
    "ScenarioCommitPaletteTest"
    # settle_screen_effects(): the "all pre-battle scenario effects are RESOLVED
    # before the battle starts" rule (NavigatorMain.run_combat). A direct combat
    # SEEK fast-forwards the opener at 30× and parks with a time-driven ramp (the
    # {33} Color Field sepia wash, {1A} oxide, {2E} background, {Reveal} fade, the
    # {76}/{3E} overlays, {6B} BG-sound fade) mid-flight — this snaps each to its
    # committed target so the seek lands where the 1× linear walk does.
    "ScenarioSettleScreenEffectsTest"
    # Rain keeps falling once combat begins: weather ({3C}) is a VM time-driven
    # effect ticked behind _tick_once's `if not paused` gate. A seek-to-combat's
    # opener fast-forward leaves the VM `_paused` (_finish_fast_play), and combat
    # reuses that world WITHOUT calling start() — so settle_screen_effects() (the
    # pre-combat seam) also clears the halt, else the rain freezes on combat start.
    "ScenarioCombatWeatherKeepsFallingTest"
    # {6B} BG Sound / {6A} Edit BG Sound: the env-bank ambient channel + its
    # linear StartVol→Volume volume ramp (ScenarioBgSound), positional operand
    # parse (the {6A} two-"Unknown" collision), tracked/overlay stacking, kind
    # 0x35 liveness, and the scenario-4 PC-5 rain fade-in (0→24 over 255f). See
    # research/working_documents/BGSOUND_OPCODE_6B_INVESTIGATION.md.
    "ScenarioBgSoundTest"
    # {7C} End Sound: the scenario-tail opcode that stops the currently-playing
    # event SFX/BGM before the battle hand-off (scenario 6 idx 455). PSX
    # SUB_800440cc zeroes the active-sound handle + 8-voice teardown; Godot mirror
    # is SfxRouter.stop_all_event_sound() + the VM handler dropping live bg ramps.
    # See research/working_documents/SCENARIO6_UNKNOWN_OPCODES_6D_71_7C_82_INVESTIGATION.md §4.
    "ScenarioEndSoundTest"
    # Unit Anim (0x11) + Rotate Unit (0x2D) opcode decode + the low-range vs
    # EVTCHR-range dispatch split in ScenarioVM._op_unit_anim.
    "ScenarioFacingAnimDecodeTest"
    # Type-aware routing of low-range event Unit Anims (idle/walk) for non-TYPE1
    # sprites: the priest (TYPE3) walk resolves to its own SEQ slot, not the
    # TYPE1-shaped `(anim-1)*2` static pose. See HANDOFF_priest_walk_animation.md.
    "ScenarioEventAnimTypeAwareTest"
    # {3B}/{6E} Sprite Move + {6F} Wait Sprite Move: the per-unit straight-line
    # position lerp, with the easing curves pinned bit-exact to live PSX traces, plus
    # the {28} Walk To grid relocation and its travel-heading facing. See
    # SPRITE_MOVE_INVESTIGATION.md, ROM handler FUN_80149C48. (Carried a `red` row
    # until #752.)
    "ScenarioSpriteMoveTest"
    # {28} Walk To movement-walk animation: drives anim_id 15 → SEQ seq 28/29
    # (the ROM movement walk, byte-exact to the live PSX capture), NOT the combat
    # resolver's seq 8/9, and ticks at natural cadence (no freeze). See
    # HANDOFF_walk_to_animation.md.
    "ScenarioWalkToAnimTest"
    # Regression: seeking (fast-play) to a PC must not truncate the {28} walks on the
    # way in. The seek forces play_through_skip_unknown on, which used to cap every
    # walk at 60 ROM frames — scenario 29's are 169-217 — leaving units a quarter of
    # the way along their routes, in the Igros moat, with their transform contradicting
    # the seat latched at arm time (ADR-0219 dec. 6).
    "ScenarioSeekWalkTruncationTest"
    # Regression: a {28} Walk To sent to the tile the unit already stands on must be
    # INERT. The ROM's planner returns a zero-STEP route (a bare [0] buffer) and
    # RomWalkStepper.step() bails on route[0]==0 before _arm_walk, so hardware writes
    # no facing and latches no anim. ScenarioApply's Godot-side pre-face had no
    # degenerate case and heading_to_12bit(0,0) is NORTH — scenario 29 pc 388 spun
    # Delita 90 degrees off Teta and walked him in place through the hug.
    "ScenarioZeroLengthWalkTest"
    # Regression: a scenario-driven walk anim must keep animating through a
    # concurrent Rotate Unit cascade — a cardinal flip must NOT re-resolve the
    # body back to idle and freeze the slide (Gafgarion Orbonne door-exit). See
    # handoff_gafgarion_slide_no_anim.md + Unit._on_facing_direction_changed.
    "ScenarioWalkFrameAdvanceTest"
    # {11} Unit Anim pending-pose latch: {11} dispatch LATCHES the anim (mirrors
    # the PSX writer's unit+0x0C slot) and the per-tick consumer paints it on the
    # NEXT elapsed tick, so the visible pose update lands on the following Wait, not
    # on {11} itself (SCENARIO_WAIT_SEMANTICS.md §6b/§7b/§8i-j). Asserts the pc216
    # latch → pc217 paint sequence + the Gap B frame-0-then-1 off-by-one.
    "ScenarioUnitAnimLatchTest"
    # The {44} Draw Unit REVEAL POSE (scenario 29 pc76). {11} latches and paints
    # one tick later (above); {44} flips `visible` at dispatch — so a block that
    # reveals a unit and dresses it on the SAME tick rendered one frame of the
    # unit's PRE-reveal pose. Unit 8 is a tiny thrown EVTCHR prop, so that frame
    # drew its full-size TYPE1 human sprite on Algus's seat. Asserts the reveal
    # frame already wears the new pose AND (arm 2) that an already-visible unit
    # keeps the §8i one-tick latch.
    "ScenarioDrawUnitRevealPoseTest"
    # Regression: {28} Walk To must write the ORIENTATION source of truth
    # (Unit.facing_angle via PsxNum.heading_to_12bit), not just the derived
    # FacingDirection enum — else the VM renderer draws the unit's stale pre-walk
    # facing for the whole walk (the scenario-6 chocobo walked NORTH facing WEST).
    # CHOCOBO_WALK_OCTANT_28.md, ADR-0057 "one truth, derived views".
    "ScenarioWalkFacingAngleTest"
    # {64} Wait Rotate Unit / {65} Wait Rotate All barriers + the generic
    # `wait_until` predicate-hold primitive (PSX FUN_801498fc). See
    # HANDOFF_wait_rotate_unit.md.
    "ScenarioWaitRotateTest"
    # ADR-0065 render-clock unification: motion / camera / unit anim clock advance
    # off the single 60 Hz VM tick, so a scenario beat is a pure function of
    # tick-count-since-resync, host-rate-independent (the scn6 carry beat-match
    # drift). Drives jittery vs clean-60 deltas and asserts identical render state
    # at equal ticks; blocks a "re-add delta interpolation for smoothness" regress.
    "ScenarioClockUnificationTest"
    # Wait For Instruction(Task=N) cooperative-task barrier: the per-kind
    # `wait_until` predicate dispatch (camera / dialog overlay / child cutscene
    # block) plus fall-through for unmodeled kinds. See
    # wait_for_instruction_halt_decode.md.
    "ScenarioWaitForInstructionTest"
    # Event variable system (Wait Value path): writers Zero (0xBE) / Add (0xB0)
    # + reader Wait Value (0x7E) signed >= barrier, plus the var-87 prayer
    # frame-counter incrementer. Pins the real scenario_1 pc 319–326 block — the
    # two altar rotations fire ~28/30 ticks after the reset while the main thread
    # races on, no halt. See event_instruction_a0_d5_variable_readers.md.
    "ScenarioVarWaitValueTest"
    # {53} Face Unit look-at math: the affected unit rotates to face the faced
    # unit's tile. Pins ScenarioVM.face_unit_look_at_12bit_psx against the §8
    # controlled-call octant table + the captured 0x0c→0x84 ground truth
    # (face_unit_decode.md).
    "ScenarioFaceUnitTest"
    # {92} Inflict Status (Status=0 only): the VM handler + ScenarioApply verb +
    # ScenarioWorld.revive_and_normalise + Unit.scenario_revive_and_normalise. Pins
    # revive-if-dead(1 HP) / normalise-to-Standing on a real Unit, the FakeScenarioWorld
    # apply wiring, and the FAIL-LOUD halt on any Status != 0 (issue #154). See
    # research/working_documents/scenario_1_captures/inflict_status_op92_decode.md.
    "ScenarioInflictStatusTest"
    # Thrash detection
    "GPUThrashTest"
    # Visual teleport detection
    "GPUTeleportTest"
    # Special
    "GPUSeedReproTest"
    # Lean per-tick column reads == full snapshot (perf refactor contract guard)
    "GPULeanColumnReadTest"
    # ADR-0235 / #888 — the GambitBattle keystone. snapshot/restore is bit-identical
    # over an ODD tick count (so the second run starts on the opposite ping-pong
    # half), and `reconfigure` overlays a config onto a LIVE unit without resetting
    # the 57 offsets that are live state. Its pure, exhaustive-over-all-102-offsets
    # half is arms 5-6 of UnitEncodeSchemaTest.
    "GPUBattleSnapshotTest"
    # ADR-0236 / #889 — the turn meter. The kernel's `+= max(1, Speed)` per tick,
    # its clamp at TURN_METER_FULL, `consume_turn`'s carry, and "a unit mid-cast
    # still gets its turn" are all checked against TurnQueue's CPU mirror, so the
    # forecast the player reads cannot drift from the clock the shader runs.
    "GPUTurnMeterTest"
    # The settle brake — the battle does not end on top of a unit mid-step. The
    # kernel's #897 "the fight is over" flip used to write CELEBRATING over a walker,
    # and a state leaving the movement set is the visual bridge's cue to snap the
    # sprite to the DESTINATION of the step it just abandoned — one tick before
    # `CombatLoop.victory` even fires, which is why no host-side gate could catch it.
    # A braked battle and an unbraked `restore_battle` fork of the same image, side
    # by side: the fork must still flip mid-step and win at once (the positive
    # control, the off-by-default proof, and the "cannot ride a fork" proof), the
    # braked one must withhold the win until every survivor has drained.
    "GPUSettleBrakeTest"
    # ADR-0239 / #891 — the turn director, on a BARE CombatLoop with no host scene
    # and no Unit nodes (design S1's stated consequence, and the reason the
    # director is a component rather than a third host). Exact-tick freeze (one
    # 60-tick frame must stop on the crossing tick, not at the frame boundary),
    # commit's carry, a bit-identical cancel over all four snapshot slices, and
    # the playback rate proved to be a VIEWING rate: the stretch's tick length
    # matches TurnQueue's closed form at 1x/2x/4x while the frame count falls.
    "TurnDirectorTest"
    # ADR-0242 / #892 — the GambitBattle host, end to end on the REAL Gariland
    # scenario: one integer boots map + cast + zone, the ROM-placed side stands on
    # its authored ENTD tiles (never in the player's zone), deployment is a turn
    # with the clock stopped and NO GPU battle yet, commit is the one write that
    # sizes the sim by the squad that took the field, and the battle is played to
    # annihilation with every turn committed unchanged. ~13 s.
    "GambitBattleTest"
    # 🔴 TRANSIENT, ADR-0264 PR 3: DELETE THIS ROW AND THE FILE WITH `GambitBattle`.
    # Both hosts on the same battle in one process, measuring the three differences
    # ADR-0264 names — gambit writes no camera pose, hardcodes the authored cast's
    # facing over ENTD 388's `facing_raw`, and ticks nothing through deployment while
    # the navigator's ten units march-idle. Every arm asserts the two hosts DIFFER, so
    # once gambit IS a seek the arms go red and the file goes away. ~9 s.
    "GambitVsNavigatorBattleDiffTest"
    # ADR-0247 / #941 — the deployment PICKER: the half of deployment that decides WHO
    # fights. ○ on an empty zone tile opens the map-hosted Formation screen on the BENCH
    # (a pick list, because a benched unit stands on no tile the cursor could name),
    # ←/→ walk it through real key events, and the fourth row set's one row lands the
    # unit on the tile the picker was opened FROM. Plus the eligibility arm: with the
    # reserve holding the last Gariland slot the picker offers exactly one name.
    "GambitDeploymentPickerTest"
    # The pure half of the same ticket: the editable deployment assignment (cap,
    # tile exclusivity, the mandatory-unit flag honoured BY CONSTRUCTION rather
    # than by roster order, and `clear` as deployment's only undo), against the
    # real extracted zone 256.
    "DeploymentAssignmentTest"
    # ADR-0252 / #894 — the ADJUSTMENT TURN, the pure half: the turn as an editing
    # window. Steerability as a CONJUNCTION (owned AND the moment — both terms are
    # seeded), cancel restoring the SAME Character instance rather than a fresh one
    # (three holders point at it, so an equality check is not enough), a commit that
    # writes BOTH the unit block and the gambit SSBO because they are different
    # buffers, and the job-change prune dropping only stale ABILITY rows while the
    # job-independent verbs survive.
    "AdjustmentTurnTest"
    # ADR-0255 / #1007 — the GAMBIT SURFACE, the fourth adjustment type, on a real
    # Gariland turn. The menu carries a "Gambit" row on the four-row adjustment set,
    # dispatched BY LABEL (row 3 is "Gambit" there and "Remove Unit" in the ROM's five,
    # so an index-keyed dispatch reaches a roster verb); the surface opens onto four
    # EMPTY slots because a scenario-booted cast has no authored gambits; the
    # slot → part → choice drill lands an edit the slot row reads back; and the edit
    # crosses at commit, read out of the gambit SSBO rather than off the CPU object.
    "GambitSurfaceTest"
    # #895 §7's thinking beat on a real 8-battle fleet. `step_tick` dispatches
    # over the WHOLE batch -- no per-battle active mask -- so a beat carries the
    # LIVE battle forward too and only `restore_battle` puts it back. The arm
    # that matters compares two raw four-slice snapshots of battle 0 across a
    # beat, with the fleet's own clocks as the positive control: a harness that
    # ran zero ticks would pass a bare identity check perfectly.
    "GPURolloutHarnessTest"
    # #897's DECISION on top of that machine. Arm 1 is the ticket's headline and it
    # needs the GPU: the same position thought about twice must choose the same
    # move, which `plan` alone can never prove — a plan is arithmetic and was
    # always going to be deterministic. What could fail is everything after it (a
    # seed from a clock, a candidate order from a Dictionary, a tie broken by float
    # noise). Also: `apply` writes ONLY the acting unit's gambit rows, a beat
    # announced on the wrong team refuses rather than rank backwards, and a cap
    # that cannot fit runs no beat at all.
    "GPURolloutDriverTest"
    # W1: a real battle with every NON-union field of the lean per-frame snapshot
    # poisoned. The runtime half of the union's defence -- check_snapshot_union.py
    # below proves the union covers the CODE, this proves it covers the RUN.
    "GPUSnapshotUnionTest"
    # The behaviour half of the same defence, and the arm that catches what the
    # poison arm above structurally cannot: a missing union field whose only job is
    # to GATE a branch never propagates an absurd value anywhere, so nothing
    # watching for a poisoned NUMBER can see it. prev_move_pos / move_step_id were
    # exactly that -- omitted, GPUMovementInterpreter.classify() said NO_MOVE every
    # frame and units teleported between tiles instead of walking.
    "GPUVisualBridgeInterpolationTest"
    "GPUArenaStressCastTest"
    "GPUArenaTest"
    # Effect sound (offline FEDS audio capture: audible + correct onset + replay)
    "EffectSoundCaptureTest"
    # ADR-0085 note-chip AUDITION CONSOLE render-reliability (2904a5de6 fix): the managed
    # ExMateriaEffectSfx.audition_note_on/off path, driven deterministically in capture_mode.
    # Locks the force-active fix — a held note stays audible PAST the 720-sub idle tail
    # (remove session_count=1 and its late window goes silent), repeats reliably, tail rings.
    "FedsNoteAuditionEngineTest"
    # ADR-0085 per-edit-freeze fix: the pair panel's §3 energy bands + joint waveform now
    # render CHUNKED through _energy_queue (pumped from _process) instead of 3 synchronous
    # render_pair calls (3-8 s block) on every FEDS edit. Locks: scheduling is non-blocking,
    # the chunked assembly equals the old synchronous _render_pair_energy, and a superseding
    # edit discards the in-flight render (debounce-by-supersede).
    "EffectStudioEnergyRenderChunkedTest"
    # ADR-0085 "everything as we go": the studio's ghost/energy renders run on a DEDICATED
    # capture SPU (ExMateriaEffectSfx.init_as_capture) so they never park the live-audio producer
    # (capture_mode gates only that instance). Locks parity (capture render == live render) and
    # isolation (a capture render leaves the live engine's capture_mode false → audio never stops).
    "EffectCaptureEngineTest"
    # ADR-0085 climax cue: the sound ghost bar's ENERGY ENVELOPE is the REAL rendered
    # amplitude (offline SPU capture → per-frame RMS, peak-normalised), not an opcode
    # guess — deterministic, normalised, shaped, one curve per firing sound_id.
    "SoundEnvelopeCaptureTest"
    # Studio SFX-replay regression: a backward EffectInstance.seek() (Stop/loop-restart)
    # re-arms the sound cast so the second play re-fires (was silent — the controller
    # restart lived only in reset(), which the seek path never calls).
    "EffectInstanceReplaySoundTest"
    # Studio sound edits reach playback: an EffectData.sound edit through the choke
    # point re-fires the controller with the new value on replay (single source of
    # truth — was a stale second parse, so edits were audibly a no-op: BUG #2).
    "EffectSoundEditReachesPlaybackTest"
    # Effect sound routing: UNLOCKED puts each concurrent cast on its own SPU unit
    "SfxUnitRoutingTest"
    # The OTHER half of that policy: fire-and-forget game-event SFX (SfxRouter's
    # play_one_shot lane) must NOT spread one-cast-per-unit. A burst must leave the
    # transient pool untouched, pack onto the bounded reserved event lane, and drain
    # inside the one-shot grace — saturating the pool put the audio clock at half
    # real-time and stalled the main thread for seconds.
    "SfxOneShotPoolTest"
    # The parity TRACE probes in tick_irq_start_for_runtime run on the live audio
    # path, once per 240 Hz IRQ per active SPU unit, and their gate did not include
    # "is anyone recording" — so they built (and threw away) 49 get_voice_debug_info
    # dictionaries per unit per sub. 818 us against a 4.16 ms budget put the ceiling
    # at FOUR concurrent casts; past it the audio clock halved, the scheduler lead
    # went seconds negative and the main thread waited 33 ms for _audio_mutex.
    "SfxTraceProbeGateTest"
    # Ambient ({6B} BG Sound) path: a persistent bed binds a RESERVED unit outside
    # the MAX_UNITS combat pool (own bus limiter + sub-level knob), so it never
    # costs combat a slot.
    "AmbientAudioPathTest"
    # W11/R28 — the ONE-SHOT silence reap. `_reap_dead_sessions`' "still audible"
    # test asks the UNIT, but every play_one_shot cast packs onto the 2 reserved
    # event cores, so one audible blip vetoed reaping every other session on that
    # core: 240 drained sessions still sequenced every sub, the SPU scheduler over
    # its 4.16 ms/sub budget, and a main-thread cue waiting 25.7 ms on _audio_mutex.
    # Pins both halves — one-shot casts drain while their core stays audible, and
    # nothing else ever takes that path. The fixture OVERLAPS its blips on purpose;
    # at a slower cadence the ordinary reap drains everything and the arm cannot fail.
    "SfxOneShotSessionDrainTest"
    # Gambit scenario suite (issue #57): declarative behavioral tests for the
    # gambit system. One entry aggregates all scenarios; per-scenario verdicts
    # live in the log, the single PASS/FAIL line here keys off aggregate.
    "GambitScenarioRunnerTest"
    # Map-state selection (ADR-0056): a scenario picks its map environment (sky
    # gradient + ambient + lights + palette) by RAW weather index + night flag
    # against scene_manifest states[], never by label.
    #
    # SPLIT, NOT DROPPED (ADR-0210 dec. 4, applying ADR-0194 / #652). The five
    # synthetic legs that pin the selection RULE reach nothing but
    # `addons/exmateria_battlefield/assembly/MapStateSelector.gd`, so they moved to
    # addons/exmateria_battlefield/tests/MapStateSelectorTest.gd and are run by
    # `bash tests/stranger/exmateria_battlefield/run.sh`, which GLOBS its addon's
    # tests/*.tscn — there is no second list. That paid arm 3's 8-site row.
    #
    # The sixth leg read the real MAP056 scene_manifest. HOST content: a stranger
    # project has none, so travelling with the others would have made it a
    # permanent [SKIP] — the ADR-0148 failure. It stayed, re-expressed as a claim
    # about the EXPORT (do the shipped rows still carry the raw keys the rule
    # reads) rather than about the selector, which is why it names no addon class.
    "MapStateExportTest"
    # Map storage-buffer bounds guard: GPUBatchSimulator.build_map_data is sized
    # from the WALKABLE bounds but filled from get_all_tiles() (impassable ones
    # included). An out-of-bounds tile must be skipped, not indexed — else it runs
    # off the buffer (the `index '936'` crash that killed GPU-sim init) or wraps
    # into a live cell. Pure-logic guard, no GPU.
    "MapBufferBoundsTest"
    # ADR-0224's P1, over all 119 exported maps: the map buffer grew a second
    # level-major plane, so level 0's six planes and the distance field's flat
    # array must come out byte-identical to the golden taken before the widening
    # (tests/data/map_buffer_golden.json). Also asserts the upper block IS
    # written -- every other arm is green on a widening that landed nothing.
    # ~15s, pure logic, no GPU.
    "GPUMapBufferLevelRatchetTest"
    # ADR-0224's P4 and P6, over the 125 walkable upper cells across 35 maps.
    # P4: the height plane the shader now reads at a unit's OWN level holds the
    # same number `GPUCombatPacker` packs into `U_HEIGHT` -- the two that
    # ADR-0224 opens with disagreeing by 9 on MAP083. P6: `EventPathfinder` and
    # the GPU distance field return the same step count and the same
    # reachable/unreachable verdict for the same start, target and climb, which
    # is what "dec. 5 ADOPTS dec. 6 rather than restating it" has to mean.
    # ~20s, pure logic, no GPU.
    "GPUBridgeMoverAcceptanceTest"
    # ADR-0224's P4 and P5 END TO END ON THE GPU, on the map the ADR argues from.
    # A unit is deployed onto MAP083's bridge deck at (4, 6, 1) -- record 405's
    # cell -- and the compute pipeline is run for real: its U_HEIGHT is the
    # deck's 9 and not the column's 0, and it walks OFF the deck to the ground
    # with no step that holds (x, z) and changes only the level. The only
    # GPUCombatTestBase scene that runs on a real exported map rather than the
    # flat procedural arena, which cannot express this defect at all.
    "GPUBridgeDescentTest"
    # Observation-only over-unit feedback HUD (ADR-0063, #89/#90): a DamageNumber3D
    # spawns on hp_changed + survives the killing blow's death-frame (map-anchored);
    # a StatusBubble3D rides SPELL_CHARGING / active status. combat_visuals members,
    # driven only by CombatLoop signals — no BattleUnitData read, no state write.
    "FeedbackHudTest"
    # ROM-faithful damage-number "trending" step machine (NumberPopupTrend,
    # DAMAGE_NUMBER_DISPLAY_INVESTIGATION.md Round 5.2): the generalized per-digit
    # Q12 scale ramp reproduces the asset's pre-staggered tables, the 1.5 overshoot
    # + right-to-left reveal, lifecycle bands, and the fade->black brightness ramp.
    # Pure-logic guard, no GPU — the value object DamageNumber3D drives per phase.
    "NumberPopupTrendTest"
    # Headful integration of the same trending on the REAL shader path: a real
    # DamageNumber3D pumped through the 60 Hz phase lifecycle wires the ROM ramp
    # to per-digit MeshInstance3D scales (1.5 overshoot + R->L reveal), swaps to
    # the additive fade twin (surfaces a shader compile failure), and tears down.
    "DamageNumberTrendTest"
    # The two `pacing.*` pacing knobs are LIVE, not inert. FFT's numbers were
    # calibrated against a TURN; this kernel is turnless, so `pacing.damage_scale`
    # and `pacing.move_time_scale` re-time that balance from SimConfig. Both arms
    # carry a positive control (damage actually landed / units actually walked)
    # before the direction assertion, because a silenced battle and a dead knob
    # both read as "the numbers did not move". Guards the batched path in
    # particular: `_run_ticks_batched` binds `_config_buffer_pair` and never calls
    # `_update_config`, so a config field wired only to the live buffer is
    # invisible to every tick a `step_tick(K>1)` caller runs.
    "PacingKnobsTest"
    # The pacing knobs are REACHABLE from the gambit host, and the Pacing rows BUILD.
    # A plain boot of GambitBattle.tscn is NOT this check: register_panel only appends
    # to a list, so a host that registers nothing and a host that registers a broken
    # panel print the same zero errors (WorldMapDebugPanelTest records the same trap).
    # Written against a real defect — GambitBattle printed "F3 - debug overlay" while
    # registering no panels at all. Source arm + build arm, the playback row asserted in
    # BOTH directions because its first gate (Tune.is_registered) was a predicate that
    # could not fail: naming the slug class-loads its owner, which binds it everywhere.
    "GambitBattlePacingPanelTest"
    # The panel-applicability discriminator separates a CONSUMER from a debug ROW (ADR-0263).
    # Written against a self-certifying instrument: TuneField.build_control subscribes every
    # row it renders, so a raw Tune._subscriber_count answer is true for any slug with a
    # visible control — every knob would read "live" on every screen and look right. Direction
    # tests: view-only row stays DECLARED, non-view subscriber goes CONSUMED, peek does not
    # stamp the pull clock while get_value does, and no state label claims "dead".
    "PanelApplicabilityTest"
    # Damage-number FADE-band -> compositor fold routing (#89 fire-on-a-fading-number artifact fix,
    # ADR-0074). The opaque grow/steady phase stays in-scene; the additive fade phase routes through
    # the engine fold like every other additive PSX prim so it can't flash an overlapping routed prim
    # (Fire). Locks the routing decision (fade_shader_path), the fold variant declaring compositor_layer
    # and NOT being exempt-marked, the in-scene fallback staying exempt, uniform parity for the .shader
    # swap, and the display-space pow(2.2) being dropped. Pure source read — no GPU/fork.
    "FeedbackHudFoldRoutingTest"
    # ADR-0037 dec. 10 spawn-time freeze: a combat_visuals member spawned mid-cinematic
    # (e.g. the {92} crystal billboard) must freeze on spawn, not animate until the
    # next transition refresh. Guards CombatLoop._on_scene_node_added.
    "CombatVisualsSpawnFreezeTest"
    # Post-battle "return to normal" decoupling (ADR-0026 follow-up): the GPU
    # win handshake (stage_victory keys on the CELEBRATING settled state) is
    # decoupled from the RENDERED pose. celebrate_on_victory off (default,
    # faithful) settles a living unit to IDLE (resolver auto-picks the kneel for
    # a critical unit) and leaves a KO'd unit as its DEAD corpse; on = the dance.
    # Pins CombatLoop.settled_victory_activity. Pure-logic guard, no GPU.
    "CombatVictoryPoseTest"
    # Live end-to-end of the same decoupling: a real 1v1 driven to victory with
    # celebrate_on_victory OFF — the GPU still declares the win (settled state
    # unchanged) but the full-HP winner must render IDLE, not the dance. Reuses
    # the melee fixture. Complements the pure-logic guard across the real pump.
    "CombatFaithfulPoseTest"
    # RANGETILE atlas manifest (#88 + §15.15/§15.16): digits + status icons + the
    # detail-screen Ability icons (5 cells, CLUT 0x7d7c) + Eqp slot icons (two-layer
    # lit/dark + 2H variant). Guards the cell rects + CLUT presence vs a stale JSON.
    "RangeTileAtlasTest"
    # Unit-detail / Status screen (FORMATION_SCREEN.md §15). The box-open animator
    # (§15.17): the byte-exact WORLD easing curve [10,10,60,60,90,90,95,95,100…] and
    # the ROM-integer center-out scale, pinned to the live-confirmed p=60 grab
    # ({4,126,250,108} -> {54,148,150,64}).
    "BoxOpenAnimatorTest"
    # The ○-press SLIDE animator (§15.1): the byte-exact keyframe table
    # {144,139,67,31,13,4,0} (WORLD.BIN 0xAABD6) + the one-index-per-frame walk/settle.
    "VitalsSlideAnimatorTest"
    # The composable unit-info group (§15.5): the ONE vitals-panel + nameplate pair
    # both screens reuse, its two menu layouts (docked/top), and the keyframe slide
    # between them (docked → top, landing at top_y + offset, settling at the top).
    "UnitInfoClusterTest"
    # The Status-screen composition: the §15.14 window rects + container centre, and
    # that the lower panel builds 3 window frames + 5 Ability icons (§15.15) + the
    # two-layer Eqp slot icons (§15.16), with the box-open a SCISSOR reveal (§15.17) —
    # a center-out clip aperture, NOT a scale (2H-collapse hides the L.Hand row).
    "DetailScreenLayoutTest"
    # The ○-press transition arc (§15.5): the cluster slides bottom→top with the lower
    # Eqp/Ability panel held closed, a dead gap, then the §15.17 box-open — ordered.
    "DetailTransitionTest"
    # The DETAIL-screen frame tunables (ADR-0068): every window/aperture/tab/band is a
    # `static var` bound to a `detail.*` slug at the §15.14 defaults, and a scrub drives
    # the var + rebuilds the settled lower panel live (F3 "Detail Screen" panel view).
    "DetailFrameTunablesTest"
    # The "frame = movable origin + relative content" model: each on-screen frame's chrome AND its
    # content are children of ONE origin node, positioned relative to it. (A) every drawn quad lands
    # on the exact pre-refactor world position (visual no-op); (B) moving a frame origin moves its
    # content by the same delta (grab-the-frame). DetailScene stats + lower panels; the picker window.
    "DetailFrameGroupTest"
    "EquipPickerFrameGroupTest"
    # The START action-menu migrated to ADR-0088 registered elements (window + inset-chrome +
    # unclipped title/glove elements; the shared BOX_OPEN beat replaced the third accumulator
    # copy): (A) golden position multiset = visual no-op; (B) grab-the-window capability;
    # (C) registration audit zero unowned payload; (D) window rect follows the host container.
    "StartMenuFrameGroupTest"
    # The stats band group migrated to the registered element `detail.stats` (ADR-0088): identity,
    # engine-discovered clip over chrome+legend+glyphs (hand _stats_*_mats pushes retired),
    # mount-time coverage on a shut-state text rebuild (stale-clip kill), sweep-container aperture
    # via aperture_pad covering the R44-nudged chrome.
    "DetailStatsElementTest"
    # The Eqp/Ability lower panel migrated to the registered element `detail.lower` (ADR-0088):
    # identity, engine-discovered clip over frame+bands+tabs+icons+equip-items (hand
    # _lower_mats/_equip_item_mats pushes retired), §15.22 pager buttons exempt (outside the
    # element), mount coverage on a shut-state equip-items rebuild, sweep aperture via aperture_pad.
    "DetailLowerElementTest"
    # The Change-Job title plate migrated to ADR-0088 (changejob.title window: MENU_TILE chrome via
    # the frame criterion + shared BOX_OPEN beat; changejob.level = UNCLIPPED Lv line): golden
    # multiset no-op + grab-the-window + registration audit + declared-clip honesty.
    "ChangeJobTitleElementTest"
    # The roster SORT HEADER housed in the registered element formation.sort_header (ADR-0088):
    # screen-anchored assembly (chrome + labels + L2/R2 mount absolute), UNCLIPPED declared;
    # golden multiset no-op + identity + grab-the-header.
    "FormationSortHeaderElementTest"
    # The roster backdrop (cobble floor + §14.6.6 band, one blend-ordered holder) housed in the
    # registered element formation.background (screen-anchored, UNCLIPPED; RP_BACKGROUND fold-Z
    # lift hand-applied pending a depth criterion): golden no-op + identity + grab.
    "FormationBackdropElementTest"
    # The gold selection-box trail housed in the registered element formation.gold_box
    # (screen-anchored assembly, UNCLIPPED cursor-class answer): 64-quad golden no-op +
    # identity + the §15.23 visibility latch.
    "FormationGoldBoxElementTest"
    # ADR-0088 §8 registration audit for the Status screen, both modes (status + equip/slot-focus):
    # every rendering payload housed under a registered element (vitals band / pager / slot-cursor
    # elements landed), guard-local allowlist EMPTY and shrink-only.
    "DetailRegistrationAuditTest"
    # UIFrame's optional center_region: the tiled 9-slice CENTER samples a separate atlas patch from
    # the border/edges. Default OFF ⇒ every existing caller byte-identical; propagates to the material.
    "UIFrameCenterRegionTest"
    # The equip-picker keeps its STRIPE frame chrome but tiles a CLEAN fine-dither interior (the patch
    # the Eqp/Ability/stats panels tile) instead of STRIPE's coarse 5px body — the "noise resolution
    # way off" fix. Border stays STRIPE; center_region wired to the body_dither_patch tuneable.
    "EquipPickerInteriorTest"
    # The BROWN vertical strip top-to-bottom on the LEFT of the picker (a subtractive UIVitalsBand
    # column band, §15.19): exists, revealed by the box-open, rides _frame_origin, vertical + left.
    "EquipPickerLeftStripTest"
    # The picker interior-patch + left-strip geometry is FULLY tuneable (ADR-0068): every knob a
    # `static var` bound to an `equipicker.*` slug, and a scrub rebuilds the live picker subtree.
    "EquipPickerTunablesTest"
    # The immutable asset manifests behind the UI3 text/atlas stack (font_meta.json 275 KB,
    # RANGETILE.json 43 KB) are parsed ONCE per process, not once per constructed instance.
    # Counter-based, so it goes red on the exact regression without wall-clock flake. This was
    # ~20 ms of the ~44 ms synchronous build behind "opening a UI3 picker lags the game".
    "UI3ManifestCacheTest"
    # §15.26 DEFECT #8: the picker-preview delta/compare panel is a duplicate() of the base stats text;
    # it must clone only the CURRENT glyphs. A deferred queue_free of the prior view let duplicate()
    # capture stale glyphs (≈2×) → the "garbage/kanji '-'" that persisted until a frame-dim rebuild.
    "DetailStatsDeltaGlyphDupTest"
    # §15.26 DEFECT #8 follow-on: the picker-preview delta/compare band is its OWN movable frame group
    # (origin = base origin + 2px, both re-derived from the live STATS_FRAME) so it RIDES a stats-frame
    # position scrub. Regression for the user-reported "move the stats panel, the second band stays behind".
    "DetailStatsDeltaFrameRideTest"
    # ADR-0077 amendment (no *unauthored depth*): every depth-writing UI prim in the Status-window
    # subtree (stats + lower + delta frames, icons, glyphs, item names) must AUTHOR a fold rung — the
    # z_rung=-1 floor sentinel is banned (a floor-parked opaque prim is composited OVER by the
    # F3-draggable vitals band, which occludes only by nearer depth). Keys on the authored rung meta,
    # not runtime world-Z (rung 0 is legal; off-fork every rung collapses to Z=0). RED on the old
    # floor-parked stats panel; GREEN after the migration.
    "DetailUnauthoredDepthTest"
    # The numeric equip stat-DELTA computation (EQUIP_STAT_PREVIEW.md): preview−base per
    # field read from items.json. FULL BAND COVERAGE — every changed field (Move/Jump/Speed,
    # PA, S-EV, A-EV, wp/wev, hp/mp), not just weapon+vitals; empty base=0. Pure.
    "EquipStatDeltaTest"
    # Full-coverage delta RENDER: the picker preview paints a signed delta on Move/Jump/Speed and the
    # AT row's AT · S-EV · A-EV (a shield shows S-EV, a speed hat Speed, a PA hat AT); job-only C-EV and
    # a plain (no-delta) preview dash. The fix for "picking a shield shows no stats."
    "DetailStatsDeltaCoverageTest"
    # End-to-end over the transition: cursoring a shield in the L.Hand picker previews its S-EV
    # (physical block) and leaves HP/MP dashed (shields have none) — the user-reported regression.
    "FormationEquipShieldPreviewTest"
    # The equip stat-DELTA colour CLUTs: FRAME.BIN palette 15 (0x7FFC) via the atlas +
    # the index-bias helper ([13]blue positive / [9]red negative / [1]tan). EQUIP_STAT_PREVIEW §5.
    "EquipDeltaPaletteTest"
    # The Weap.Power delta RENDER: set_stats_preview_delta fills the focused hand's row with
    # signed coloured numbers (+4/+5 blue, -1 red, evade-0 dash). EQUIP_STAT_PREVIEW.md §6.
    "DetailEquipDeltaRenderTest"
    # Armor/accessory delta routes to the vitals HP/MP NUMERATORS: set_hpmp_delta fills "+5" blue /
    # "-5" red, 0 → dash (Clothes onto Body → HP +5). EQUIP_STAT_PREVIEW.md §6.
    "VitalsDeltaPreviewTest"
    # End-to-end WIRING: the picker cursor (selection_changed) drives the transition to compute
    # preview−base and push it live into the stats + vitals compare panel. EQUIP_STAT_PREVIEW.md.
    "FormationEquipDeltaWiringTest"
    # The first-class chrome entry slide (§15.1/§15.6) extracted from the ○-press transition:
    # play_entry_slide raises the vitals+nameplate PAIR docked→top WITHOUT the box-open, emits
    # entry_slide_done at settle, and a delta spike is clamped so the slide can't teleport.
    "DetailEntrySlideTest"
    # FormationScene ○-press split (§15.5): Enter/○ on a unit → unit_activated(character)
    # (+ selected_character()), Esc/△ → dismissed (the #234 E contract preserved).
    "FormationDetailActivateTest"
    # End-to-end host wire: a formation ○-press overlays a DetailScene bound to the
    # selected unit and starts the slide; Esc closes it back to the roster.
    "FormationDetailTransitionTest"
    # ○-press REFINEMENTS: the band cross-fade (bottom out / top in, §15.6) + the overlay
    # depth lift (the Status screen sorts above the formation grid, ADR-0077).
    "FormationDetailRefineTest"
    # The Item→Equip unit sprite-slide animator (§15.23, RE round 22): an EMERGENT
    # (no ROM table — OT rebuilt per frame) ease-in tween between caller endpoints;
    # pins the measured settle (166,173) + duration 16 + the accelerating/clamp shape.
    "SpriteSlideAnimatorTest"
    # The Item→Equip unit slide on the REAL grid (§15.23, RE round 22): begin latches
    # docked origins; the selected unit settles at (166,173), non-selected slide off the
    # right edge, ease-in, no scale (only anchor position is touched).
    "FormationEquipSlideTest"
    # The Item→Equip host wire (§15.23): START menu "Item" closes the lower Status panels
    # (vitals+nameplate cluster stays), slides the units, and reopens the Eqp panel at settle.
    "FormationEquipTransitionTest"
    # place_at's first production consumer (§15.23 / ADR-0088 Amendment 2 §4): the Item→Equip
    # and Ability sub-menu switches RE-HOME the LIVE StartActionMenu (park → place_at + set_rows
    # + box-open replay) instead of teardown+rebuild — the SAME menu instance survives, matching
    # the ROM's in-place slot-6 re-render. Covers both the roster and detail-screen entry contexts.
    "FormationMenuRehomeTest"
    # The Eqp slot-list FOCUS sub-state (§15.25 RE33): ○ on the Equip list-menu's "Equip" row hands the
    # glove cursor into the panel (anchored on the frame's left edge, slot row 0), the list-menu goes to
    # background (§15.21 CLUT swap), ↑/↓ cycle the 5 slot rows, and △/× returns focus to the list-menu.
    "FormationEquipSlotFocusTest"
    # The equipment PICKER sub-state (§15.26 RE34): ○ on a focused Eqp slot row opens the item-select
    # picker (multi-column: name + NN/NN counts; icons/counts stubbed), hands the cursor into it, blues
    # the Eqp slot panel (stats band STAYS tan in preview), flips vitals+stats to "-" preview mode, and
    # △/× closes back to §15.25 slot focus. (The equip COMMIT is the out-of-scope next layer.)
    "FormationEquipPickerTest"
    # The equip/remove COMMIT must refresh the VITALS HP/MP gauge from the live unit, not just the
    # stats band: equipment usually moves HP/MP (armor), which live on the vitals cluster. Regression
    # for "stats don't update as I equip/remove" — the commit path called set_stats_view but not
    # set_unit_view, so the deferred set_vitals_preview(false) on close re-applied the stale view and
    # the +N delta shown in preview snapped the numerator back to the OLD value. Equip + remove sides.
    "FormationEquipVitalsRefreshTest"
    "FormationEquipRemoveVitalsTest"
    # The START-"Ability" host wire (§15.23 RE27): the mirror of the Equip wire — choosing
    # "Ability" (row 1) plays the SAME slide and settles to the ability_only panel (LEFT-relocated
    # Ability window, LOWER_FRAME_ABILITY) + the Set/Remove/Learn 3-item menu at (200,132,56,64).
    "FormationAbilityTransitionTest"
    # The Change-Job wheel pure model (§15.24 RE28): one member per gender-appropriate generic job
    # (0x4A-0x5D minus the opposite-sex-locked Bard/Dancer = 19/sex), data-derived sprites + names,
    # and the oval ring placement — all from JobDatabase (ADR-0001), no hand-encoded job list.
    "ChangeJobWheelTest"
    # The START-"Change Job" host wire (§15.24 RE28): a NEW full-screen (not a lower-panel sub-state)
    # — the roster SPLITS (upper rows exit left / lower right), the selected unit slides to the oval
    # CENTRE, a ring of gender-appropriate job bodies is built, the job title shows bottom-middle, the
    # sort-header is hidden and the ◄L1/R1► pager shown (reused Status chrome). Back-out tears it down.
    "FormationChangeJobTransitionTest"
    # Main-menu sub-screen entries SLIDE the top chrome (§15.1/§15.5) instead of snapping (the
    # "binary flip" fix): START-on-roster → Change-Job / Item / Ability plays play_entry_slide, and
    # each sub-transition (job wheel / Equip roster slide) begins only after entry_slide_done.
    "FormationMainMenuEntrySlideTest"
    # Main-menu sub-screen EXITS SLIDE the top chrome back down (ADR-0084) — the mirror of the entry
    # slide: Esc from the Equip/Ability screen replays the chrome slide REVERSED (top→docked) with the
    # §15.6 band cross-fade backward, tearing the overlay down only ON SETTLE (not the old teleport).
    "FormationMainMenuExitSlideTest"
    # The Formation-transition COORDINATOR seam (ADR-0084): enter(state)/leave() over the LIFO
    # screen stack, the settled(to) signal, current_state()/is_moving(), a byte-restore enter→leave
    # round-trip (Equip + Change-Job), and gaps observable (leave at IDLE / enter(IDLE) are no-ops).
    "FormationCoordinatorSeamTest"
    # The coordinator's HAND-BACK (ADR-0181): `dismissed` re-emitted at rest so a host can take
    # the display back, and the two cases it must stay silent — over an OPEN screen (where ✕
    # LEAVES it, and where `settled(IDLE)` would have fired) and on the PERSISTENT MAP host.
    # Guards a failure that is a HANG rather than a wrong value: the coordinator CONSUMES
    # FormationScene.dismissed, so before this the navigator's `await` never returned, silently.
    "FormationHandBackTest"
    # The Formation SCREEN-IN (ADR-0172): the 2-frame ramp landing exactly ON RAMP_TICKS,
    # seek==advance==value_at, counted in VSYNCS not display frames, input gated by SWALLOWING
    # (a bare `return` falls through to the roster grid's _unhandled_input), the NDC quad FREED on
    # landing rather than zeroed (ADR-0162's hazard), and the MAP host raising none. Pins the ramp
    # as a SHAPE, never as truth — 30 is borrowed from a measurement of a different mechanism.
    "FormationScreenInTest"
    # The ADR-0084 beat/recipe ENGINE the coordinator plays on (scene-free unit test): forward play,
    # reversed play via each beat's distinct reverse driver, the group barrier, the MAX_CATCHUP
    # accumulator clamp, and the boot-time reversibility audit (invariant 1).
    "FormationTransitionEngineTest"
    # ADR-0084 invariant 1 at the coordinator: the recipe TABLE the coordinator can enter is present
    # and every beat carries a reverse driver (a forgotten exit fails this boot audit, not the user's
    # first Esc). Grows as screens are ported onto the engine.
    "FormationRecipeAuditTest"
    # ADR-0084 invariants 3 & 4 on the live coordinator: an EQUIP round-trip preserves roster cell
    # membership (beats never reparent/reassign — membership is derived by role, inv 3), and the real
    # recipe table has no concurrent-target overlap (inv 4). The disjoint LOGIC is unit-tested in
    # FormationTransitionEngineTest; this asserts the coordinator's actual recipes satisfy it.
    "FormationTransitionInvariantsTest"
    # A delta spike does not collapse the host per-tick steppers (Equip / Change-Job slide, entry,
    # rotate, exit) into one frame — the teleport clamp companion to DetailEntrySlideTest.
    "FormationStepperClampTest"
    # The Formation START sub-menu (§15.20): the 5 action rows + up/down wrap, the §15.17
    # box-open SCISSOR (container {172,120,84,96}, p=60 ⇒ ~{188,140,50,56}), the "Menu"
    # title drawn full outside the body clip, the two-layer glove cursor (bob axis = X,
    # idle period 46) + its menu_glove_cursor atlas set, and confirm/cancel outcomes.
    "FormationStartMenuTest"
    # ADR-0088 slice 1: the UI3Element construction surface (collect-all spec validation,
    # authored_home freeze default, the absorbed rel_world/z_for display→world math) and the
    # UI3Registry index (parent = nearest registered ancestor on _enter_tree, self-placement
    # against the parent's authored home, roots/children_of/signals following the tree).
    "UI3ElementSpecTest"
    # ADR-0088 slice 2: the cacheless clip engine — push = fresh pull-walk (no cached
    # material list, no cached rect), mount-time coverage via the deferred coalesced
    # node_added push, the explicit UNCLIPPED sentinel, PARENT_APERTURE ancestor
    # resolution, and the f8442784d stale-scrub regression (aperture re-derives from
    # the LIVE rect).
    "UI3ClipEngineTest"
    # ADR-0088 slice 3: the shared transition engine — the ADR-0084 beat player extracted
    # (one clamped stepper, per-beat tick cadence, derived reverse). box_open open()/close()
    # reverse symmetry against the ROM curve literals, settle signals fire exactly once,
    # the MAX_CATCHUP spike clamp, instant NONE/RIDE_PARENT settles, and the boot-time
    # reversibility audit (unregistered beat + irreversible beat both reported).
    "UI3TransitionEngineTest"
    # ADR-0088 slice 4a: auto-bind threading — literal spec fields mint id-named slugs
    # (composite Rect2 rect, enum-hinted criteria, beat params; id/authored_home mint
    # nothing), the generalized R8 write-through (a rect scrub moves the origin, the
    # aperture rides), derived placements (no slug, driver scrubs re-place), the
    # answer() class-scoped widget path, and the criteria() page model
    # (AUTHORED/INHERITED/DERIVED + slug).
    "UI3AutoBindTest"
    # ADR-0088 slice 4b: the UI3 dashboard page — UI3RegistryView is a pure view over
    # roots/children_of/criteria (registers nothing), AUTHORED rows edit through the
    # shared TuneField control (a page edit lands via the element's own on_update —
    # decision 12), INHERITED/DERIVED rows read-only, rebuild on register while
    # visible, and DebugDashboard's 4th "UI3" page hosts it (ADR-0035 dec. 8).
    "UI3RegistryPageTest"
    # ADR-0088 Amendment 6: the ownership map — false-color each element's OWN payload by
    # a stable, sibling-distinct owner color (UI3OwnerColors palette), a LOSSLESS debug
    # material swap (activate→deactivate leaves material_override byte-identical; no
    # production-shader edits), unowned payload → the reserved ALARM color (visual
    # registration audit), and Mute (pure `visible`, captured + restored EXACTLY, multi-mute
    # stacks, orthogonal to the swap). The page surfaces (swatch/Mute/toggle/Clear-all +
    # auto-clear on hide) are guarded in UI3RegistryPageTest.
    "UI3OwnershipMapTest"
    # Click-to-navigate over the ownership map: the map is already a false-color ID buffer, so a
    # framebuffer pixel names its owner. EXACT match, then a MEASURED +/-1-per-channel fallback
    # that must resolve to exactly one owner — not a nearest-color match, because the ramp
    # compresses as N grows (min pairwise L1: 44 at N=18, 8 at N=80, 3 at N=200). Also pins that
    # the ramp's min per-channel separation stays >1, which is what makes +/-1 unambiguous.
    # Registering elements while the UI3 page is OPEN must not freeze the game. It used to cost
    # 1.6-2.0 SECONDS: a full page rebuild PER registered element (~328 ms each, four per picker
    # open). A registration is additive, so the page now updates only what changed, coalesces a
    # frame's burst, and spends a bounded budget per frame. Load-bearing assertion is EQUALITY —
    # an incrementally-updated page must be indistinguishable from a rebuilt one.
    "UI3RegistryPageIncrementalTest"
    "UI3OwnerPickTest"
    # ...and the end-to-end form, which is the only place the load-bearing assumption is actually
    # tested: through the real scene + camera + compositor engine-fold, a sampled framebuffer
    # pixel must name the element whose color it is, and the page (in a separate OS Window) must
    # unfold its ancestors and scroll to it.
    "UI3OwnerPickAcceptanceTest"
    # ADR-0088 Amendment 2: key locations — at(location_slug) is the third rect answer
    # form (a DerivedRect driven by ONE location slug read live through Tune; mints no
    # <id>.rect slug; a location scrub re-places every at() consumer, the aperture rides,
    # the authored home stays frozen), and place_at(location_slug) re-homes a live
    # element (rect follows the NEW location, old-location scrubs are inert no-ops —
    # the stale driver-subscription hazard — and repeated re-homing dedups).
    "UI3KeyLocationTest"
    # ADR-0088 Amendment 2 on the REAL widget: the START menu's shared offsets (frame
    # inset / title tab offset / row insets) are live startmenu.* driver binds — a scrub
    # re-places the chrome/title elements or rebuilds the row block, a clear restores the
    # golden layout — and the startmenu.loc.* sweep: place_at each of the 5 homes, scrub
    # the location, EVERY menu quad moves by the delta (the empty-drivers no-op killer);
    # the bobbing glove is multiset-exempt but its element origin must ride.
    "StartMenuLocationSweepTest"
    # ADR-0088 Amendment 2 §4 widget verbs: the LIVE menu RE-HOMES — place_at(loc) + set_rows(rows)
    # on a built StartActionMenu renders EXACTLY a menu built fresh at that home with those rows
    # (quad multiset match; frame chrome re-derives its SIZE from the new home, selection resets to
    # row 0). The §15.23 in-place re-render at the widget seam, under FormationMenuRehomeTest.
    "StartMenuRehomeTest"
    # ADR-0088 slice 6: the registration audit — unowned ShaderMaterial payload under
    # an audited UI root is reported with its owning class; the tracked allowlist is
    # two-sided shrink-only (unlisted violation fails; a listed class with zero
    # violations fails with "remove" — an entry cannot linger past its migration).
    "UI3RegistrationAuditTest"

    # ------------------------------------------------------------------------
    # ADOPTED 2026-08-24 by #417, and adopted as a BLOCK on purpose.
    #
    # These 275 scenes existed under `tests/`, emitted `[PASS]`/`[FAIL]` markers,
    # and were reachable by NO runner. `run_scene_smoke_tests.sh` covers none of
    # them (its six scenes are `assets/scenes/*.tscn`); `run_tombstone_tests.sh`
    # delegates; only `run_unlisted_audio_binders.sh` reached 13, via a derived
    # list. So 287 scenes were run by nothing at all, for two months, under green
    # summaries reading `PASSED: 408 / 410`.
    #
    # EVERY ONE WAS RUN BEFORE IT WAS LISTED. Serial, at the same 360 s wall clock,
    # scored by `tests/lib/verdict.sh` and nothing else, at trunk `6a25e54f7`:
    # 300 scenes, 57.7 min, mean 11.5 s. **275 PASS · 17 FAIL · 4 THREW ·
    # 2 NO_VERDICT · 2 NOT_A_TEST.** All 300 got a real Vulkan device and
    # `[compositor-autopilot] ACTIVE` — no VRAM-degraded verdicts. The 23 that did
    # not reach green are NOT here: each has a row in `tests/skip_tests.tsv`
    # naming the ticket that holds it (#539 #541 #542 #543 #544, plus #513 #514).
    #
    # THE ORDER "RUN, THEN LIST" IS THE POINT, and it paid for itself twice.
    # `PsxChiralityTest` fails because THE TEST demands `(-pi, pi]` from a
    # function returning `[0, 2pi)` — adopting it unclassified would have turned
    # the suite red on a test that is itself wrong. And 97 of these were first
    # measured in a worktree missing `project-assets/`; re-run with it present,
    # two verdicts moved from red to green.
    #
    # THEY CARRY NO PER-ENTRY PROSE, unlike the entries above, and that is honest:
    # they were adopted by one measurement, not reasoned about one at a time.
    # Writing 275 invented purpose-sentences would look like documentation and be
    # fiction. A scene that later earns a comment should get one.
    #
    # WALL CLOCK: this adds ~53 min to a ~44 min serial suite. That cost is real
    # and it belongs to #453/#526 (parallelism is ADOPTED but untrustworthy while
    # vllm holds the VRAM), not to a decision to keep 287 tests invisible.
    # ------------------------------------------------------------------------
    "AbilityLoadoutProgressionTest"
    "AbilityLoadoutTest"
    "AbilityPickerMenuTest"
    "AnimationFrameCalculatorMemoTest"
    "BattleDeploymentTest"
    # The DATA half of "every battle hands the player somebody" (ADR-0265 Amendment 1):
    # 72 battle roots, each named by exactly one of the two Commandable writers — the
    # ENTD control flag (Orbonne, the only one) or a deployment zone (the other 71).
    "BattleCommandableCastTest"
    "CameraHoldClosureCorpusSweepTest"
    "CameraMotionTest"
    "CameraUnitsTest"
    "CameraValueSemanticsTest"
    "ChangeJobCommitCutsceneTest"
    "CharacterCatalogOwnedTest"
    "CharacterCatalogTest"
    "CharacterFormSetTest"
    "CharacterRosterParityTest"
    "CinematicLowRangeSeqKeyTest"
    "CinematicPoseLUTTest"
    "ColorTimelineModelTest"
    "ColorTweenRowsTest"
    "ColourBoxPickerTest"
    "ColourKeyframeFitTest"
    "ColourKeyframeSessionTest"
    "ColourKeyframeTrackTest"
    "ColourLifeColumnTest"
    "ColourMoveCorpusSweepTest"
    "ColourMovePadShapeTest"
    "CombatCameraMountTest"
    # ADR-0207 dec. 4: the map-composer mount, COUNTED. 109 consumer scenes instance
    # `assets/scenes/ProceduralMap.tscn` and the composer ARRIVES in each — the one
    # thing `check_lattice_scene.py` cannot see, since a mount whose `script =` line
    # was dropped still names the script and still reads green (measured).
    "ProceduralMapMountTest"
    "ColourMoveTest"
    "ColourMuxTest"
    "ColourRibbonRulerTest"
    "ColourRibbonTest"
    "ColourStructureFreeDragTest"
    # MOVED OUT, NOT DROPPED (ADR-0207 dec. 6, applying ADR-0194 / #652):
    # TileCursorBobTest — the ROM-faithful bob step machine — reaches nothing but
    # addons/exmateria_battlefield/cursor/ (one preload, and its tile_knife.json fixture is
    # tracked inside the addon), so it now lives in addons/exmateria_battlefield/tests/ and is
    # run by `bash tests/stranger/exmateria_battlefield/run.sh`. That rig GLOBS its addon's
    # tests/*.tscn (shared/rig.sh:237), so the move enrols it; there is no second list.
    "CursorConfirmEndToEndTest"
    "CurveGeneratorsTest"
    "CurvePlayheadMarkerTest"
    "CurveShapeSetTest"
    "DeploymentPlanTest"
    "DepthCenterBboxTest"
    "DetailAbilitySlotFocusTest"
    "DetailColumnBandFoldEnrollTest"
    "DetailItemNameBackgroundTest"
    "DetailStatsDeltaPanelTest"
    "DetailUnitClusterElementTest"
    "DetailVitalsBandElementTest"
    "EffectCameraEdgeDragAcceptanceTest"
    "EffectCameraInsertDeleteAcceptanceTest"
    "EffectCameraMoveTest"
    "EffectCameraRippleTest"
    "EffectCameraSaverAdapterTest"
    "EffectCameraSaveRoundTripTest"
    "EffectCameraSpacerTest"
    "EffectCameraUnitAuthoringSaveTest"
    "EffectColourMovePadAcceptanceTest"
    "EffectCurveOwnershipTest"
    "EffectCurvePainterMarkerTest"
    "EffectCurveSparklineMarkerTest"
    "EffectDataSoundContainersTest"
    "EffectEmitterInspectorUxAcceptanceTest"
    "EffectFlagsChannelTest"
    "EffectFlagsSaverTest"
    "EffectFramesBarRegionTest"
    "EffectFramesBarTest"
    "EffectKeyframeInspectorMarkerTest"
    "EffectLoopRegionViewTest"
    "EffectManagerNode3DAnchorTest"
    "EffectPaletteByteCoverageAcceptanceTest"
    "EffectPaletteEdgeDragAcceptanceTest"
    "EffectPaletteInsertDeleteAcceptanceTest"
    "EffectPaletteInsertPositionTest"
    "EffectPaletteSaveRoundTripTest"
    "EffectPaletteTintPickAcceptanceTest"
    "EffectParticleTimelineSaverAdapterTest"
    "EffectPhase2EndFloorTest"
    "EffectPickerVerdictFreshnessTest"
    "EffectScoreModelChildLinkRelevanceTest"
    "EffectScoreTimelinePhaseBoundaryTest"
    "EffectScreenEdgeDragAcceptanceTest"
    "EffectScreenInsertDeleteAcceptanceTest"
    "EffectScreenInsertPositionTest"
    "EffectScriptPatternTest"
    "EffectScriptReflowTest"
    "EffectScriptSaverAcceptanceTest"
    "EffectScriptSwapTest"
    "EffectSettingsProjectorTest"
    "EffectSettingsTargetTest"
    "EffectSoundInsertDeleteAcceptanceTest"
    "EffectSoundInsertDeleteTest"
    "EffectSoundSaveTest"
    "EffectSpacerEmptySpaceAcceptanceTest"
    "EffectSpacerRestyleAcceptanceTest"
    "EffectStudioAsyncGhostLoadTest"
    "EffectStudioCameraSplitSelectionTest"
    "EffectStudioChainInspectionTest"
    "EffectStudioColorCurveLiveEditTest"
    "EffectStudioColorEditTest"
    "EffectStudioColourColumnTest"
    "EffectStudioColourEnableTest"
    "EffectStudioColourKeyframeAcceptanceTest"
    "EffectStudioColourRibbonAcceptanceTest"
    "EffectStudioColourRibbonWiringTest"
    "EffectStudioCurveOwnershipAcceptanceTest"
    "EffectStudioCurvePlayheadMarkerAcceptanceTest"
    "EffectStudioDrillDownTest"
    "EffectStudioEffectFlagsAcceptanceTest"
    "EffectStudioEmitterColumnTest"
    "EffectStudioEmitterSequenceSubjectTest"
    "EffectStudioFrameQuadTransformTest"
    "EffectStudioFramesetCanvasAcceptanceTest"
    "EffectStudioFramesetRailTest"
    "EffectStudioGroupHandlesTest"
    "EffectStudioHideInertAcceptanceTest"
    "EffectStudioHideInertToggleTest"
    "EffectStudioKindSelectorTest"
    "EffectStudioParticleDragPreviewAcceptanceTest"
    "EffectStudioPathBarAcceptanceTest"
    "EffectStudioPathBarTest"
    "EffectStudioPhaseBoundaryAcceptanceTest"
    "EffectStudioPlayheadDisplayTest"
    "EffectStudioQuadTransformAcceptanceTest"
    "EffectStudioRegionLoopAcceptanceTest"
    "EffectStudioRegionScopeTest"
    "EffectStudioSaveTest"
    "EffectStudioScriptPatternAcceptanceTest"
    "EffectStudioSequenceCanvasTest"
    "EffectStudioSequenceCellColourTest"
    "EffectStudioSequenceThumbnailTest"
    "EffectStudioSequenceTimelineTest"
    "EffectStudioSequenceViewportTest"
    "EffectStudioSoundDefEditTest"
    "EffectStudioSpriteMuxAcceptanceTest"
    "EffectStudioStaleSurfaceTest"
    "EffectStudioTextureImportAcceptanceTest"
    "EffectStudioTexturePlayheadTest"
    "EffectStudioTextureTabTest"
    "EffectStudioTimelineHeaderAcceptanceTest"
    "EffectStudioTimeScaleAcceptanceTest"
    "EffectStudioTransportTest"
    "EffectStudioUndoTest"
    "EffectStudioUnifiedAnimationAcceptanceTest"
    "EffectStudioUnifiedAnimationTest"
    "EffectStudioUnitCellTest"
    "EffectTimelineHeaderSaverTest"
    "EffectTimelineModelTest"
    "EffectTimeScaleSaverTest"
    "EmitterFieldRelevanceSimGuardTest"
    "EmitterFieldRelevanceTest"
    "EmitterRelevanceAcceptanceTest"
    "EmitterRelevanceViewTest"
    "EmitterSpriteColorTest"
    "EmitterViewClockDomainTest"
    "EntdBattleComposeTest"
    "EquipCandidatesTest"
    "EquipPickerRowMechanismTest"
    "FedsInstrumentMetaTest"
    "FedsNoteAuditionTest"
    "FedsPairEditorTest"
    "FedsPrunePersistenceTest"
    "FieldInspectControllerTest"
    "FormationAbilityPickerTest"
    "FormationAbilityRemoveTest"
    "FormationBandTest"
    "FormationChangeJobConfirmTest"
    "FormationChangeJobExitReversalTest"
    "FormationCursorGlideTest"
    "FormationEquipCommitTest"
    "FormationEquipRemoveTest"
    "FormationFloorSpotlightTest"
    "FormationFoldRoutingTest"
    "FormationInfoPanelViewTest"
    "FormationLearnPickerTest"
    "FormationMainMenuNavTest"
    "FormationMapHostTest"
    "FormationPlacementTest"
    "FormationSortColumnTest"
    "FormationUnitClusterElementTest"
    "FormationUnitLightingTest"
    "FormationVitalsBandElementTest"
    "FormationVitalsViewTest"
    "GameStateTest"
    "GetPoseOctantTest"
    "GPUBatchedTickParityTest"
    "GPUBerserkTest"
    "GPUBladeGraspTest"
    "GPUCinematicSingleSpawnTest"
    "GPUEvasionMixedTest"
    "GPUPoisonTest"
    "GPUReactionCounterTest"
    "GPURegenTest"
    "GPUReraiseTest"
    "GPURiseTimingTest"
    "GPUStatusEnforceTest"
    "GPUUndeadInvertTest"
    "LoopRegionTest"
    "LoopTransportTest"
    "MapFieldObjectPaletteWiringTest"
    "MapPaletteFieldObjectTest"
    "MapTextureAnimatorTest"
    "MusicTypewriterStressTest"
    # ADR-0264 — "play battle N" is a SEEK, and this is its permanent guard. `--battle=9`
    # plans Gariland's group alone and enters at pre_battle; the three assertions it takes
    # at the deployment pause are the three defects the seek removes — the camera on the
    # opener's terminal `{19}` (scn 10 PC 35: 302 / 5632 / 4096), the squad on the zone's
    # authored `unit_facing` (0x000, `zone_facing` NOT folded in — this is
    # `parse_placement.py`'s second live oracle), and the idle frames ADVANCING rather than
    # a register being populated. ~6 s.
    "NavigatorBattleLaunchTest"
    "NavigatorCommandModeProofTest"
    "NavigatorDeployedIdlePumpTest"
    "NavigatorFormationViewTest"
    # A gambit edit made on the NAVIGATOR host must reach the kernel — the buffer is read back
    # off `snapshot_battle()["gambits"]`, not off the Character that was written. Both routes an
    # edit can take are here: authored at the Deployment park and armed by Space, and authored
    # MID-BATTLE with the formation screen up and crossed when it closes. Each carries its own
    # control (an explicit `set_unit_gambits` for the first, the same read coming back EMPTY
    # while the screen is still open for the second), because "the row is absent" and "the probe
    # is not looking" are the same output. ~3 s.
    "NavigatorGambitEditCrossingTest"
    "NavigatorGarilandVictoryTest"
    # Mandalia Plains (root 15) is the first battle whose OPENER addresses the player's
    # formation squad — it erases `0x01` + `0x78`-`0x7C` and draws them back before
    # focusing `0x01`. Placement used to happen one action later, so the Focus resolved
    # to nothing and the camera fell back to the authored pose: it panned to empty
    # terrain and popped Ramza's dialogue there. Gariland cannot catch this — its opener
    # (scn 10) names no party unit, so the whole class of defect was invisible to the
    # suite while 28 of 72 battle groups carried it.
    "NavigatorMandaliaOpenerFocusTest"
    # THE PREDETERMINED BATTLE. The Gariland twin below walks a roster-fed cast and is
    # structurally unable to see Orbonne's defect: steerability was resolved off
    # `_deployed_owned`, which a control>0 ENTD never fills, so the one battle in the game
    # whose cast the ENTD bakes in handed the player nobody and stopped on no turn at all
    # (ADR-0265 Amendment 1). A second process because it is a second battle root.
    "NavigatorOrbonneBattleModeTest"
    # The F3 Catalogue's switches on a scene that is NOT a combat host. Its twin above pins
    # WHICH panels this scene owns; this one pins that the user's on/off set decides, in
    # both directions and on all three of its mounting paths — the gate used to live inside
    # the combat mount, so off was a no-op here and on mounted nothing.
    "NavigatorPanelCatalogGateTest"
    "NavigatorPanelOwnershipTest"
    "NavigatorPreBattleTest"
    "NavigatorRebootFadeTest"
    "NavigatorRewindResumeTest"
    # HEADFUL, real GPU (#898, design S11): the WALK mounts the turn director. NavigatorMain
    # runs a bare CombatLoop and extends no CombatHost, so this is the check on ADR-0239's
    # component placement — and on ADR-0244's soft spot, since the forecast strip rides the
    # CAMERA and comes across for free. Arms: the director is a child of the LOOP; the strip
    # is a child of the camera at a NEGATIVE depth (at z=0 it draws and is invisible, which
    # no layout test can see); turns are really SPENT (distinct takers, not one clamped head
    # re-announced); the world never freezes and the pump mirror never disagrees with
    # `CombatLoop.combat_active`; and the walk still reaches victory — a director that
    # stopped for a turn nobody can take would hang the walk instead.
    "NavigatorTurnDirectorMountTest"
    # HEADFUL, real GPU (ADR-0264): the OPTED-IN half of the walk's turn policy,
    # `navigator.stop_on_turn`. The mount test above owns the DEFAULT (hands-off, which the
    # three end-to-end walks depend on); this owns the other side, and cannot share its
    # process because a stopping walk is a different walk. The load-bearing arms are about
    # the SECOND WRITER the stop creates on `CombatLoop.combat_active`: the pump mirror
    # follows the director's freeze on every frame, Esc refuses under an open turn (the
    # documented hazard), and Space — the real action, through `_unhandled_input` — ends the
    # stop and the battle advances. Plus: autoplay forces the stop off, or a sweep hangs.
    "NavigatorTurnStopTest"
    "NumberFontTest"
    "ParticleTimelineEnableRetargetTest"
    "ParticleTimelineMoveTest"
    "ParticleTimelineStructuralTest"
    "PickerContractTest"
    "PortraitCallSiteRoutingTest"
    "ResidueManifestTest"
    "RosterBindingIntegrationTest"
    "RosterDebugViewTest"
    "ScenarioActorTest"
    "ScenarioBackgroundTest"
    "ScenarioCastInitialFacingTest"
    "ScenarioChapelChainSplineTest"
    "ScenarioChapelChainTraceTest"
    "ScenarioChapelJerkProbeTest"
    "ScenarioCinematicBandRoutingTest"
    "ScenarioMirrorSpriteTest"
    "ScenarioCinematicWalkerTest"
    "ScenarioColorFieldTest"
    "ScenarioDarkScreenTest"
    "ScenarioFieldObjectTest"
    "ScenarioFocusTest"
    "ScenarioGroupFinishedTest"
    "ScenarioLatchStepBoundaryTest"
    "ScenarioMapTitleTest"
    "ScenarioNameMacroTest"
    "ScenarioPaletteResolutionTest"
    "ScenarioPrayerOverlayTest"
    "ScenarioRemoveUnitTest"
    "ScenarioShowGraphicTest"
    "ScenarioStartClearsPauseTest"
    "ScenarioStartPreservesMarchIdleTest"
    "ScenarioSteppingConsistencyTest"
    "ScenarioWaitCadenceTest"
    "ScenarioWarpFacingTest"
    "ScenarioWeatherTest"
    "ScoreReprojectReuseParityTest"
    "ScreenDataRoundTripTest"
    "ScreenEnabledToggleTest"
    "ScrubFieldTest"
    "ShadowFoldOrderTest"
    "ShopAvailabilityDatabaseTest"
    "SequenceLifeMapTest"
    "SoundContainerChannelTest"
    "SoundRenderQueueTest"
    "SpacerVerdictShortcutParityTest"
    "SpacerVerdictsPerfTest"
    "SpuClippingMetricsTest"
    "StartMenuBackgroundedFrameSwapTest"
    "TemplateFolderLoaderTest"
    "TileCursorIntegrationTest"
    # MOVED OUT, NOT DROPPED (ADR-0208 dec. 8 / ADR-0194): TileOverlayColorTest — the CPU
    # barber-pole port — now lives in addons/exmateria_battlefield/tests/, beside
    # TileOverlayCompositorTest, for the same reason: its only reach was the addon script
    # under test. Listing it here would run it in the host project, which is exactly the
    # project whose absence is the claim (ADR-0194 dec. 4).
    "TimelineHeaderChannelTest"
    "TimelineHeaderReflowTest"
    "TimeScaleChannelTest"
    "UI3ElementRoleTest"
    "UI3ScreenAnchoredAuditTest"
    "UIComponentBootAuditTest"
    "UIComponentContractTest"
    "UIFrameOutlineTest"
    "UIMenuTextNumberSizeTest"
    "UIVitalsRosterRoleAuditTest"
    "UnitInfoPresenterTest"
    "UnitScenarioRotateTest"
    "UnitScenarioSpawnCombatIdleTest"
    "UnitThrowBodyDispatchTest"
    "VitalsPreviewFieldWidthTest"
    "WorldMapBlendTest"
    "WorldMapMountTest"
    "WorldMapNavigatorTest"
    "WorldMapPrimitivesTest"
    "WorldMapProgressTest"

    # ---- the world map screen (world-map line) ---------------------------------
    # HEAD registered TEN; #417's block above already adopted five of them, so only
    # the five it did not are added here. A blind union of the two blocks registers
    # WorldMapProgress/Primitives/Blend/Mount/Navigator TWICE.
    "WorldMapCursorTest"
    "WorldMapTravelTest"
    "WorldMapPlaceListTest"
    "WorldMapStartMenuTest"
    "WorldMapTownTest"

    # ---- the eleven the coverage guard found unlisted -----------------------------
    # `tools/check_test_list_coverage.py` is trunk's, and it landed after this line
    # branched — so these were written green and registered nowhere, which is the exact
    # state that guard exists to make impossible. Each was run headful on the 4.8 fork
    # before being added here: all eleven PASS with zero SCRIPT ERRORs.
    #
    # The screen-in ramp as NUMBERS (ADR-0161/0174); its picture half is the
    # `--menu=screenin` contact sheet, which asserts nothing and is not a test.
    "WorldMapScreenInTest"
    # ADR-0174's OUT arm as numbers and as a GATE: the endpoints (32 -> full black,
    # which a reversed in-arm gets wrong in BOTH directions), the ascent, the landing
    # frame, and that `world_map.screen_out` actually turns the fade off. Its picture
    # half is the `--menu=screenout` contact sheet.
    "WorldMapScreenOutTest"
    # A second hop from a node already arrived at — the travel case a single walk misses.
    "WorldMapSecondHopTest"
    # The navigator crossings (ADR-0181): the map hands the display back to the Formation
    # COORDINATOR, arrival loads the node, and the press precedence between the two.
    "NavigatorWorldMapArrivalTest"
    "NavigatorWorldMapChainTest"
    "NavigatorWorldMapFormationTest"
    "NavigatorWorldMapFormationRenderTest"
    "NavigatorWorldMapPressPrecedenceTest"
    # Campaign's payload (ADR-0179): ONE game-variable array, the node scripts that read
    # it, and the chain that advances it.
    "CampaignVariableStoreTest"
    "CampaignNodeScriptTest"
    "CampaignChainTest"
    # ADR-0230: the reveal pass — the ordered drain that turns a reveal emit into a known
    # node. `MASK_REVEAL` had zero callers, so the map could never open up past its
    # opening capture. Data-driven over all 19 story beats plus the two that no story
    # counter can make live.
    "CampaignRevealPassTest"
    # ADR-0231: the same pass PACED — the reveal animation. The console's three animation
    # pages (`0x32` look-at, `0x35` ribbon, `0x36` node) read out of WLDCORE and ported as
    # holds on the vsync clock, plus the arrival interlock the pacing creates.
    "WorldMapRevealAnimationTest"
    # A SEEK must re-root the party MARKER, not just the story variables: the marker is
    # what `WorldMapScene` draws AND what it hands its opening reveal pass, so one stale
    # value put Ramza in the wrong town and hid the reveals the walk had just earned.
    "NavigatorSeekPartyNodeTest"
    # The focus STACK itself (ADR-0177) — push/pop, delivery gating, tree_exiting drop.
    "FocusStackTest"
    # ADR-0051's world-map panel as a VIEW: fixture/zoom/boot_menu are WorldMapScene's
    # properties and the panel reads and writes them THERE, and its Capture button must not
    # quit the session. The panel arrived untested; `register_panel()` only appends to a
    # list, so `_build_ui` had never run in any check. Both defects are seed-proven.
    "WorldMapDebugPanelTest"
    # W13 (#955): a debug panel is a VIEW and must not run its _process when nobody can
    # see it. Godot's NOTIFICATION_READY arms _process for any script that defines one
    # BEFORE _ready, so a set_process(false) in a pre-tree builder is inert, and
    # DebugDashboard.add_panel() then calls on_shown() at registration. The F3 bus mixer
    # metered every AudioServer bus every frame of every session with the window closed.
    # Asserts counted work (is_processing), not milliseconds — W8's standing ruling.
    "DebugPanelProcessGateTest"
    # W14 (#956): the dialogue tail's ADR-0036 PAR correction read pixel_aspect through
    # RenderingServer.global_shader_parameter_get, which is EDITOR-ONLY — it returned
    # null in the shipped game, so the correction had never run and every call printed an
    # error + backtrace (286k of a 288k-line walk log). Reads PSXDisplay.live_par now.
    "DialogueBoxAnchorParTest"
    # W6: CombatLoop's tick catch-up drain is bounded, and the bound is REAL wall clock
    # so a deliberate fast-forward (the four navigator proofs at SIM_TIME_SCALE 40) keeps
    # its throughput while the shipped path cannot compound a slow frame into a slower
    # one. TWO drains, not one — the ticket named the combat drain and missed the
    # post-victory one; arm 5 counts the second separately. Counted work, not wall clock.
    "CombatLoopCatchupClampTest"
    # W4 (#866): the F3 overlay costs ~26 % fps WHILE OPEN and the goal is a fast game with
    # it up, so "close it" is not the fix. PerfMonitor is right to sample every frame — the
    # ring buffer the graph draws has to stay dense — but the panel did full-fidelity work
    # on every emission: a nine-field string format and a 240-sample polyline redraw, ~46 %
    # of the overlay's cost between them. Now ~10 Hz. Asserts counted work (label updates
    # per simulated second, graph draw emissions), not milliseconds — W8's standing ruling.
    "PerfPanelThrottleTest"
    # ADR-0275 dec. 18 / #1127. The kernel stamps a per-slot gambit VERDICT (dec. 4), and
    # `VERDICT_NONE == 0` is a REAL answer — "this call did not reach this slot" — so a write
    # that never fires is indistinguishable from "nothing declined". Nine battles in one batch,
    # one rigged failure point each, asserting the exact code AND payload on the decoded field;
    # the codes and bit shifts are PARSED out of `combat_common.glslinc` rather than mirrored,
    # and a coverage assertion fails if the kernel grows a verdict no cell names.
    "GambitVerdictCellsTest"
)

TOTAL=${#TESTS[@]}
# ADR-0194 dec. 10. After the moves `run_all_tests.sh` names 684 tests where it
# named 692, and a green 684-suite would be green BECAUSE IT STOPPED LOOKING —
# ADR-0148's named failure, and the sentence `Audio` goal #4 is already scored
# `open` for. So the landing run invokes the rigs too. This does NOT contradict
# dec. 4: dec. 4 forbids running an addon-owned test as `res://tests/X.tscn` in
# the host project; invoking a rig that builds its own stranger project is a
# different act, and the only one that can close goal #4.
#
# `shared/` is not a rig — see tools/_runner_tests.stranger_rigs(), which is the
# one reading this, the register header and scoped_tests.py all use.
RIGS=()
if [ -d "$PROJECT_DIR/tests/stranger" ]; then
    for _r in "$PROJECT_DIR"/tests/stranger/*/run.sh; do
        [ -f "$_r" ] && RIGS+=("$_r")
    done
fi
RIG_TOTAL=${#RIGS[@]}
RIG_PASSED=0
PASSED=0
FAILED=0
ERRORS=0
TIMEOUT=0
HUNG=0
THREW=0
CRASHED=0
NOT_A_TEST=0

# PROVENANCE, and it is not decoration (#453 §5.1). This stdout IS the archive —
# `docs/archive/` holds five full suite runs and NOT ONE of them records the tree it
# measured, so "are these two runs the same code?" is unanswerable about every one of
# them, and the map has already been burned by exactly that provenance error. The
# dirty marker is half the point: a run against a modified tree is not a run against
# `$SHA`, and the same wording as `freeze_test_baseline.py`'s `code_commit` header so
# the two stamps read as one fact.
SUITE_SHA="$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || echo UNKNOWN)"
if ! git -C "$PROJECT_DIR" diff --quiet HEAD 2>/dev/null; then
    SUITE_SHA="$SUITE_SHA  (WORKING TREE DIRTY at capture)"
fi

echo "======================================"
echo "  GPU Combat Test Suite"
echo "  Running $TOTAL tests"
# A SEPARATE line, never folded into the one above: `freeze_test_baseline._banner`
# anchors the provenance match across the title and a line starting `Running `,
# and decorating that line would make every archived run unreadable.
echo "  plus $RIG_TOTAL stranger rig(s) — ADR-0194 dec. 10, run after the array"
echo "  code_commit $SUITE_SHA"
echo "  godot $GODOT_VER"
# The other two harness facts a re-takeable register needs, and the only place
# they can be recorded truthfully is the run itself — the addon deployment copy
# and the `.godot/` cache can both change between this run and whenever somebody
# reads the register (#454). ONE owner: both arms print
# `tools/harness_stamp.py`'s lines, so the sequential and parallel banners
# cannot drift from each other or from the fields `tools/suite_register.py`
# reads. Printed here, INSIDE the banner block and after `Running N tests`, so
# `freeze_test_baseline._banner`'s two-line title match is untouched.
(cd "$PROJECT_DIR" && uv run python tools/harness_stamp.py)
echo "  started $(date -Is)"
echo "======================================"
echo ""

SUMMARY=""

for i in "${!TESTS[@]}"; do
    TEST="${TESTS[$i]}"
    NUM=$((i + 1))
    SCENE="res://tests/${TEST}.tscn"
    LOG="$LOG_DIR/${TEST}.log"

    echo "[$NUM/$TOTAL] Running $TEST..."

    # Interactive diagnostic scenes need --ci to run their checks and quit.
    EXTRA_ARGS=()
    if [ "$TEST" = "UnitOrientationTest" ]; then
        EXTRA_ARGS=(-- --ci)
    fi

    # The wall clock is measured HERE rather than from the per-test log's mtime,
    # which is how map #450's original per-test cost figures were taken. An mtime
    # is when the last byte was written, so a test that hangs silently for five
    # minutes and then gets killed reads as fast, and under the parallel arm the
    # mtimes interleave and mean nothing at all. #454 wants a wall-clock budget
    # that a diff can price a regression against; that has to be the runner's own
    # measurement. Nanoseconds via `date`, integer arithmetic, no `bc`.
    T0=$(date +%s%N)

    # Run with a 360s default timeout (6 min per test), using --path . from
    # project dir. Bumped from 180s when issue #53's cinematic orchestrator
    # started doubling the 4v4 arena's resolution time (every other unit freezes
    # during a ~600-tick Fire cast). The 3-min budget worked for most tests but
    # the arena legitimately needs more.
    #
    # A name in the case below RAISES its own wall clock, because its honest run
    # does not fit the default. This is not an escape hatch for a hang: every
    # entry carries the MEASURED solo wall clock that justifies it, and a test
    # that stops making progress still dies — later. `run_tests_parallel.py`
    # mirrors this table as TIMEOUT_OVERRIDES and
    # `tools/test_run_tests_parallel.py` reads BOTH and asserts they are equal,
    # so the two arms cannot drift into scoring the same test differently.
    TEST_TIMEOUT=360
    case "$TEST" in
        # 82 GPU scenarios in ONE process. Measured 678 s solo (11m18s, [PASS],
        # 82 scenarios green) on 2026-08-29. At 360 s it reached 56 of 82 and was
        # scored HUNG — it is not hung, it does not fit (#709).
        GambitScenarioRunnerTest) TEST_TIMEOUT=1200 ;;
    esac

    (cd "$PROJECT_DIR" && timeout "$TEST_TIMEOUT" "$GODOT" --path . "$SCENE" "${EXTRA_ARGS[@]}") 2>&1 | tee "$LOG"
    EXIT_CODE=${PIPESTATUS[0]}

    # The verdict comes from the ONE reader (#451) — see tests/lib/verdict.sh for
    # the rule order and why a test's own `[VERDICT]` line outranks the markers.
    RESULT="$(test_verdict "$LOG" "$EXIT_CODE")"
    case "$RESULT" in
        PASS)               PASSED=$((PASSED + 1)) ;;
        FAIL)               FAILED=$((FAILED + 1)) ;;
        HUNG)               HUNG=$((HUNG + 1)) ;;
        TIMEOUT)            TIMEOUT=$((TIMEOUT + 1)) ;;
        CRASHED)            CRASHED=$((CRASHED + 1)) ;;
        NOT_A_TEST)         NOT_A_TEST=$((NOT_A_TEST + 1)) ;;
        NO_VERDICT)         ERRORS=$((ERRORS + 1)) ;;
        THREW)              THREW=$((THREW + 1)) ;;
    esac

    SUMMARY="$SUMMARY\n  [$RESULT] $TEST"
    echo "  -> $RESULT"
    # Two NEW lines, never folded into the one above: `  -> WORD` is the exact
    # shape `freeze_test_baseline.verdicts()` pairs with a `Running` line, and
    # decorating it would corrupt every register and every archived-run replay
    # that reads it. The exit code is here because it is the one thing the
    # verdict rules read that a test's stdout cannot report — HUNG is 124 and
    # CRASHED is >= 128 — so a register that carries it can show the 64 test
    # names that dump core in every archived run while scoring green (#471).
    T1=$(date +%s%N)
    ELAPSED_MS=$(( (T1 - T0) / 1000000 ))
    printf '  seconds %d.%02d\n' $((ELAPSED_MS / 1000)) $(((ELAPSED_MS % 1000) / 10))
    echo "  exit $EXIT_CODE"
    echo ""
done

# --- the stranger phase (ADR-0194 dec. 10) ----------------------------------
# THE LINE SHAPES HERE ARE DELIBERATELY NOT THE LOOP'S. `freeze_test_baseline.verdicts()`
# pairs `^\[\d+/\d+\] Running X\.\.\.` with `^  -> WORD`, and every archived-run
# replay reads that pairing. A rig is not a `res://tests/X.tscn` scene and must not
# arrive in that register wearing one's clothes, so it prints `[rig i/n] <addon>`
# and `  => WORD` — visibly the same information, deliberately a different shape.
if [ "$RIG_TOTAL" -gt 0 ]; then
    echo "======================================"
    echo "  STRANGER RIGS — $RIG_TOTAL"
    echo "  Each builds its own throwaway project and installs ONE addon into it."
    echo "  This is the arm that can close docs/GOALS.tsv Audio goal #4: not"
    echo "  \"a guard entered the package\" but \"a guard exists that can only be"
    echo "  green if the package stands alone\"."
    echo "======================================"
    echo ""
    for j in "${!RIGS[@]}"; do
        RIG="${RIGS[$j]}"
        ADDON_NAME="$(basename "$(dirname "$RIG")")"
        RIG_LOG="$LOG_DIR/stranger_${ADDON_NAME}.log"
        echo "[rig $((j + 1))/$RIG_TOTAL] $ADDON_NAME"
        (cd "$PROJECT_DIR" && timeout 1800 bash "$RIG") 2>&1 | tee "$RIG_LOG"
        RIG_EXIT=${PIPESTATUS[0]}
        # The rig's own contract, and the reason it has three exit codes: 2 is
        # COULD NOT RUN and is loudly not a pass. `NO_VERDICT` is this suite's
        # word for "the log said nothing / it did not run", which is the same
        # claim; scoring a 2 as FAIL would report a portability defect where
        # what happened is a missing engine.
        case "$RIG_EXIT" in
            0) RIG_RESULT=PASS; PASSED=$((PASSED + 1)); RIG_PASSED=$((RIG_PASSED + 1)) ;;
            1) RIG_RESULT=FAIL; FAILED=$((FAILED + 1)) ;;
            *) RIG_RESULT=NO_VERDICT; ERRORS=$((ERRORS + 1)) ;;
        esac
        SUMMARY="$SUMMARY\n  [$RIG_RESULT] stranger:$ADDON_NAME"
        echo "  => $RIG_RESULT"
        echo "  exit $RIG_EXIT"
        echo ""
    done
fi

echo "======================================"
echo "  RESULTS SUMMARY"
echo "======================================"
echo -e "$SUMMARY"
echo ""
# Eight outcomes, eight lines. Each is a DIFFERENT thing and they must not share a
# number: TIMEOUT is a test declaring its OWN tick budget blown (it ran, it spoke,
# it gave up); HUNG is the 360 s wall clock killing a process that never reached a
# verdict at all (#451); THREW is a test that reached a green verdict while the
# ENGINE threw under it, so an unknown number of its assertions never ran (#462).
# A thrower is not an assertion failure and reading it as one loses the finding.
# CRASHED is a process that died on a SIGNAL without reaching a verdict, and
# NOT_A_TEST is a scene that declared it asserts nothing — a capture rig, a render
# tool, a probe. Both were `NO_VERDICT` until #463, which is the label for "the log
# said nothing", and neither of them is that: one is a segfault and the other is a
# scene doing exactly what it was written to do. NOT_A_TEST is NOT a pass, and it
# is not counted as one; it is subtracted from the denominator instead, because a
# rig in the numerator would inflate a coverage figure with something that never
# asserted.
echo "  PASSED:     $PASSED / $((TOTAL + RIG_TOTAL - NOT_A_TEST))"
# NAMED, not folded. dec. 10's whole argument is that a drop of N in one count
# has to be visibly paired with a rise in the other, so the rigs are in the
# denominator above AND on a line of their own — a reader who wants the array's
# figure can subtract, and a reader who does not know the rigs ran cannot miss it.
echo "  STRANGER:   $RIG_PASSED / $RIG_TOTAL rig(s), each an addon in a project that did nothing for it"
echo "  FAILED:     $FAILED"
echo "  THREW:      $THREW"
echo "  TIMEOUT:    $TIMEOUT"
echo "  HUNG:       $HUNG"
echo "  CRASHED:    $CRASHED"
echo "  NOT_A_TEST: $NOT_A_TEST"
echo "  NO_VERDICT: $ERRORS"
echo "======================================"

# --- machine-state sentinel, close bracket (ADR-0281 / #1149) ---------------
# Reported, not folded into an exit code: this arm has never had one (it falls off the
# end), and inventing one here would change what `--sequential` means in the same edit
# that adds a check. The PARALLEL runner — the arm anybody actually lands on — does
# score it red, which is where the enforcement lives.
if ! (cd "$PROJECT_DIR" && uv run python tools/machine_state_sentinel.py \
        --compare "$MACHINE_STATE_FILE"); then
    echo ""
    echo "  MACHINE STATE: the run changed it (see the ABORT above). Every verdict"
    echo "  printed after the write describes the poison, not the tree."
fi
