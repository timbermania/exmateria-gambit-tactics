# The ONE verdict reader — sourced by every test runner. #451, map #450.
#
# WHY THIS FILE EXISTS. `tests/run_all_tests.sh` and `tools/run_unlisted_audio_binders.sh`
# each carried a byte-identical copy of the rule below, and the frozen register
# `docs/TEST-BASELINE-E2.tsv` is built by merging the stdout of BOTH — so a drift
# between the two copies would put two different rules in one register with nothing
# saying which row came from which. One definition, sourced twice.
#
# `tools/freeze_test_baseline.py` does NOT re-implement it: it parses this rule's
# output (`  -> RESULT`) out of a runner's stdout and adds the assertion COUNTS the
# summary drops. That is deliberate — see its docstring. Keep it that way.
#
# THE ORDER IS THE SPEC:
#
#   1. HUNG        — killed at the wall clock. A process that did not finish has no
#                    verdict to report, whatever it managed to print first.
#   2. [VERDICT]   — the test's OWN aggregate result, and it outranks the markers.
#   3. [FAIL]      — any failure marker anywhere in the log.
#   4. [PASS]      — any pass marker, given no failure marker.
#   5. TIMEOUT     — the test declared its own tick-budget timeout and asserted nothing.
#   6. CRASHED     — the process died on a SIGNAL (exit >= 128) without reaching a
#                    verdict. Read from the exit code, like HUNG, because a
#                    process's fate is not something its stdout can report.
#   7. NOT_A_TEST  — the scene DECLARED that it asserts nothing: a capture rig, a
#                    render tool, a diagnostic probe. Read last of all the
#                    non-verdict rules, so it can never outrank a marker.
#   8. NO_VERDICT  — the log says nothing either way. Its own outcome, never folded
#                    into PASS or FAIL: a test that produced no verdict did not run.
#
#   ...and then, and ONLY against a PASS:
#
#   9. THREW       — the run emitted more (or fewer) `SCRIPT ERROR` lines than the
#                    test declared it expects. A green does not get to throw.
#
# WHY RULE 2 IS NOT "ANY [FAIL] IS FAIL, FULL STOP". Rules 3-4 scrape unstructured
# stdout and cannot tell an assertion from a quarantine. `GambitScenarioRunner`
# classifies known-open bugs XFAIL — each with a written `xfail_reason` — prints
# `  - [FAIL] ...` for their expectations, and then prints its aggregate at the line
# its source calls *"Aggregate verdict for run_all_tests.sh"*. Rule 3 found the
# quarantined markers and scored the test FAIL in all five full runs on record while
# the test itself reported 82 scenarios green. Rule 2 is the channel that was missing.
#
# It is symmetric on purpose: `[VERDICT] FAIL` turns a log full of `[PASS]` red. A
# channel that could only launder failures would be worse than none.
#
# WHY RULES 6 AND 7 EXIST (#463). `NO_VERDICT` was charted as holding tests that
# DID reach a verdict and merely phrased it in a dialect the reader cannot hear.
# Swept across all seven archived runs — five suite runs (2,057 verdicts) and two
# `run_unlisted_audio_binders.sh` runs (42) — that population is EMPTY. The one
# case the ticket named, `ScenarioWalkToAnimTest`, was already fixed on trunk by
# `2538dd4cc` and scores PASS in the three newest runs. What `NO_VERDICT`
# actually holds is two other things, and they are not each other:
#
#   - EIGHT SCENES THAT ARE NOT TESTS. `DeclickDebug`, `RenderInGameAudio`,
#     `RenderTypewriterOffline`, `RenderTypewriterOnline`, `SfxLiveStressTest`,
#     `SfxPopDiagTest`, `TypewriterClickCapture`, `TypewriterCollisionProbe`
#     — every one a capture rig, render tool or diagnostic probe that says so in
#     its own header docstring, runs to completion, prints telemetry and exits 0.
#     `RenderTypewriterOffline` ends `[tw-offline] done — the WAVs above are the
#     deterministic click oracle.` There is nothing for it to assert.
#     (`TypewriterGoldenDiff` was the ninth until #385 task 3. It diffed the
#     pre-limiter sum against `_combine_limited` — the GDScript mix stage — to say
#     whether a click came from the limiter or from threading. That stage is
#     deleted, so the diff had only one arm left; the question it asked is now
#     answered by Gate E's SFX arm, which compares the streamed render against the
#     lockstep one sample for sample.)
#     They are here because `tools/_runner_tests.py --unlisted` selects by SYMBOL
#     BINDING, not by test-ness, and a capture rig binds `ExMateriaAudioEngine` exactly the
#     way a test does.
#
#     The classification already existed — AS PROSE. `freeze_test_baseline.py`'s
#     `RED_REASONS` carries all nine, hand-written, each opening *"not a test —"*,
#     one of them reading *"NO_VERDICT is the right score"*. A dict of prose in a
#     Python tool is not a channel: the runner still cannot tell a rig from a
#     break, and the tenth rig needs a tenth hand-written entry that nothing
#     forces anyone to add. `[NOT_A_TEST] <why>` is that prose turned into a line
#     the reader can score.
#
#   - ONE SEGFAULT. `DetailStatsDeltaFrameRideTest` scores PASS with 11 green
#     assertions in four of the five full runs; in `e2-suite-confirm-2026-08-22`
#     it is a Vulkan device-lost crash — `handle_crash: Program crashed with
#     signal 11`, a 19-frame backtrace through
#     `RenderingDeviceDriverVulkan::on_device_lost()`, `timeout: the monitored
#     command dumped core`. `NO_VERDICT` means the log said NOTHING. A process
#     that died on a signal is not silence, and calling it silence is the same
#     conflation `HUNG` was split out of `TIMEOUT` to end.
#
# NEITHER RULE CAN LAUNDER ANYTHING, BY POSITION. Both are read only after every
# marker rule has already declined, so a log that reached a verdict keeps it, and
# rule 1 still takes a hang first — `TypewriterClickTest` WAS a rig with no exit
# condition that burned the full 360 s every binder run, and declaring itself a rig
# must not buy it out of that. (It was given a TOTAL_TIME budget in #472 and now
# scores NOT_A_TEST honestly, by ending. The ORDERING is unchanged and is the point:
# the fix for a hang is to stop hanging, never to relabel it.) `[NOT_A_TEST]` requires a WHY on the same line, the
# same rule `[EXPECT_ERRORS]` carries: a declaration without one is a silence with
# a label on it, and is ignored.
#
# ⚠️ THE CRASH RULE ONLY REFINES A NON-VERDICT, AND THAT IS MEASURED, NOT TIMID.
# 64 test names dump core in EVERY one of the five archived full runs (65/65/65/
# 65/64 blocks per run), and 57 of the 64 score `[PASS]` every time — 58 of the 61
# `GPU*` tests plus `GambitScenarioRunnerTest`, `CombatFaithfulPoseTest`,
# `FoldQuantizePolicyTest`, `ProgressionTesterTest`, `StrategyPhaseTest` and
# `UIInteractionTest`. Those greens are a real finding and a separate one (#471) —
# filed, not folded in here, because a rule that turned ~60 passes per run into
# crashes would bury the single case this rule is about. Blast radius as written:
# 324 verdicts re-scored at exit 139, ONE moved, out of 2,099 replayed.

# WHY RULE 9 EXISTS, AND WHY IT IS A VERDICT AND NOT A LINT (#462). Rules 2-8 read
# markers and NOTHING else, so a test could throw thousands of engine errors and
# still score PASS. In all five archived full runs, 13 tests emit `SCRIPT ERROR`
# lines and ALL 13 score PASS — no red test throws at all. `CameraFeelTunablesTest`
# asserts 10 things green while emitting 5,322 of them.
#
# A GDScript runtime error is not a warning. Measured on the 4.8 fork (probe,
# 2026-08-23): a bad property/index access or a wrong-arity dynamic call ABORTS
# THE ENCLOSING FUNCTION and returns its declared type's default, then resumes in
# the caller. Nothing raises; nothing fails. Two consequences, both of which the
# 13 exhibit:
#
#   - every assertion after the error, in that function, silently does not run —
#     `EffectScoreTimelineTest` guards on `has_method("edge_rect_for")`, which
#     cannot see arity, then calls the two-arg form and abandons the rest of the
#     function while still reporting 201 green assertions;
#   - the returned type default can walk through the guard written to catch the
#     degraded case — `SequenceProjector.absolute_frameset` returns 0 where its
#     docstring promises -1, so `_attach_frameset_follow` builds a follow row it
#     documents as "disabled", with a garbage index.
#
# RULE 9 ONLY EVER DOWNGRADES A PASS. It does not rewrite FAIL, TIMEOUT, HUNG,
# CRASHED, NOT_A_TEST or NO_VERDICT: a test that is already red keeps the more actionable verdict, and
# the blast radius is confined to greens by construction. Re-scored across all
# five archived runs, exactly the 13 move and nothing else does.
#
# `[EXPECT_ERRORS] <n> — <why>` is the escape hatch, so "expected errors" is a
# declaration rather than a silence the reader cannot interpret. It is SYMMETRIC
# (fewer than declared is also THREW — a test that quietly stopped exercising its
# error path is no longer testing what it says), and it has ZERO users today:
# #462 posited a second population of tests deliberately exercising an error path,
# all 13 were read, and that population is empty. The two tests in the tree that
# do document a deliberate error path (`TuneTest`, `ScenarioActorTest`) emit zero
# errors in their passing state — the hazard is guarded and the guard is the
# assertion.
#
# ANCHORED, unlike the marker rules — deliberately, and the asymmetry is the point.
# `SCRIPT ERROR:` is emitted by the ENGINE at line start; it is not a marker a test
# prints, so there is no `push_error` stderr variant to miss. Every one of the
# 5,424 occurrences in the 2026-08-23 full run is at line start, and anchoring
# keeps a test that merely DISCUSSES the phrase from failing itself.

# UNANCHORED, and last-occurrence-wins. Anchoring is the tempting tightening and it
# is wrong here for the reason `freeze_test_baseline.py` records against its own
# MARKER_RE: a marker emitted through `push_error` lands on stderr as
# `ERROR: [VERDICT] PASS`, and an anchored read silently drops it. Matching the
# looseness of the rule it overrides matters more than tightness. Last wins, so the
# line belongs in a test's summary.
#
# Tested by `tools/test_verdict_reader.py`, which drives THIS function rather than a
# Python restatement of it, and runs as a suite pre-flight.

# test_verdict <log-path> <exit-code>
#   -> PASS|FAIL|THREW|HUNG|TIMEOUT|CRASHED|NOT_A_TEST|NO_VERDICT
test_verdict() {
    local log="$1"
    local exit_code="$2"
    local declared

    if [ "$exit_code" -eq 124 ]; then
        echo "HUNG"
        return
    fi

    declared=$(grep -oE '\[VERDICT\] (PASS|FAIL)' "$log" 2>/dev/null | tail -1 | awk '{print $2}')
    if [ -n "$declared" ]; then
        # Still subject to rule 9: a test states its own ASSERTION aggregate, but
        # it cannot observe its own engine errors, so the declaration buys no
        # immunity from them.
        _threw_or "$declared" "$log"
        return
    fi

    local outcome
    if grep -q "\[FAIL\]" "$log"; then
        outcome="FAIL"
    elif grep -q "\[PASS\]" "$log"; then
        outcome="PASS"
    elif grep -q "TIMEOUT at tick" "$log"; then
        outcome="TIMEOUT"
    elif [ "$exit_code" -ge 128 ]; then
        # Killed by a signal (128 + signo). Checked here and not beside HUNG so a
        # log that DID reach a verdict keeps it — see the #463 block above for the
        # 64 tests that dump core in every archived run, most of them green (#471).
        outcome="CRASHED"
    elif grep -qE '\[NOT_A_TEST\][[:space:]]+[^[:space:]]' "$log"; then
        # The scene said it asserts nothing. Last of the non-verdict rules, so it
        # cannot outrank a marker, a hang or a crash.
        outcome="NOT_A_TEST"
    else
        outcome="NO_VERDICT"
    fi

    _threw_or "$outcome" "$log"
}


# Rule 9, applied last and ONLY to a PASS. Everything else passes straight through,
# so a test that is already red keeps its more actionable verdict.
_threw_or() {
    local outcome="$1"
    local log="$2"
    local expected actual

    if [ "$outcome" != "PASS" ]; then
        echo "$outcome"
        return
    fi

    expected=$(grep -oE '\[EXPECT_ERRORS\] [0-9]+' "$log" 2>/dev/null | tail -1 | awk '{print $2}')
    [ -n "$expected" ] || expected=0
    actual=$(grep -cE '^[[:space:]]*SCRIPT ERROR:' "$log" 2>/dev/null || true)
    [ -n "$actual" ] || actual=0

    if [ "$actual" -ne "$expected" ]; then
        echo "THREW"
    else
        echo "PASS"
    fi
}
