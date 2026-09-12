"""Tests for the ONE verdict reader every test runner shares (#451, map #450).

WHAT A VERDICT IS. `tests/run_all_tests.sh` decides each test's PASS/FAIL by
reading its log. That decision is the root instrument of map #450 — every other
number on the map is read through it — so it gets one definition, in
`tests/lib/verdict.sh`, and this file is its test.

THE DEFECT THIS FIXES. The rule was "any `[FAIL]` in the log is FAIL", applied to
raw stdout with no notion of a test's own aggregate verdict. `GambitScenarioRunner`
runs 87 scenarios and classifies five of them XFAIL — known-open bugs, each with a
written `xfail_reason` — then prints its own summary:

    [PASS] GambitScenarioRunner: 82 scenarios green (XFAIL/XPASS soft)

and its source says, at the line that prints it, *"Aggregate verdict for
run_all_tests.sh"*. The runner never saw it: the five quarantined expectations
each print `  - [FAIL] ...`, the unanchored grep found one, and the test scored
FAIL in every full run taken (five of them, 2026-08-22 and 2026-08-23). A red that
is not red is as corrosive as a green that is not green — it trains a reader to
discount the tally.

THE CHANNEL. A test may print `[VERDICT] PASS` / `[VERDICT] FAIL` to state its own
aggregate result. When present it wins; when absent the marker rules apply exactly
as before, so the other 409 tests are untouched. Last occurrence wins, so the line
belongs in a summary.

NOT ANCHORED, deliberately — the same reasoning `freeze_test_baseline.py` records
for `MARKER_RE`: a marker emitted through `push_error` arrives on stderr as
`ERROR: [VERDICT] ...`, and an anchored read silently under-counts. Consistency
with the rule it overrides matters more than tightness here.
"""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
READER = ROOT / "tests" / "lib" / "verdict.sh"
FIXTURES = ROOT / "tests" / "fixtures" / "verdict"


def verdict(log_text: str, exit_code: int = 0) -> str:
    """Drive the real bash function — not a Python re-implementation of it.

    A second implementation here would be a second opinion, and the whole point
    of the ticket is that there is exactly one.
    """
    with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False) as fh:
        fh.write(log_text)
        path = fh.name
    try:
        r = subprocess.run(
            ["bash", "-c", f'source "{READER}"; test_verdict "{path}" {exit_code}'],
            capture_output=True, text=True,
        )
        if r.returncode != 0:
            raise AssertionError(f"reader failed ({r.returncode}): {r.stderr.strip()}")
        return r.stdout.strip()
    finally:
        pathlib.Path(path).unlink(missing_ok=True)


class MarkerRulesUnchanged(unittest.TestCase):
    """The pre-existing rules, pinned. This fix must not move them."""

    def test_pass_marker_is_pass(self):
        self.assertEqual(verdict("[PASS] it worked\n"), "PASS")

    def test_fail_marker_is_fail(self):
        self.assertEqual(verdict("[FAIL] it did not\n"), "FAIL")

    def test_fail_beats_pass_when_both_present(self):
        # The rule that makes a partly-red test red. Preserved exactly.
        self.assertEqual(verdict("[PASS] a\n[FAIL] b\n[PASS] c\n"), "FAIL")

    def test_exit_124_is_hung_even_with_a_green_log(self):
        self.assertEqual(verdict("[PASS] all good\n", exit_code=124), "HUNG")

    def test_tick_timeout_without_markers(self):
        self.assertEqual(verdict("[Foo Test] TIMEOUT at tick 6007\n"), "TIMEOUT")

    def test_markers_beat_tick_timeout(self):
        self.assertEqual(verdict("[PASS] a\nTIMEOUT at tick 900\n"), "PASS")

    def test_silence_is_no_verdict(self):
        self.assertEqual(verdict("Godot Engine v4.8\nsome noise\n"), "NO_VERDICT")

    def test_no_verdict_is_not_silently_a_pass_or_a_fail(self):
        # NO_VERDICT is its own outcome — a test that produced no verdict is
        # neither. The summary counts it separately.
        self.assertNotIn(verdict(""), ("PASS", "FAIL"))


class DeclaredVerdictWins(unittest.TestCase):
    """The new channel: a test's own aggregate verdict outranks marker scraping."""

    def test_declared_pass_survives_quarantined_fail_markers(self):
        self.assertEqual(verdict(
            "  - [FAIL] expectation a — known open bug\n"
            "  - [FAIL] expectation b — known open bug\n"
            "[VERDICT] PASS\n"
        ), "PASS")

    def test_declared_fail_survives_pass_markers(self):
        # Symmetric: the channel must be able to turn a green-looking log red,
        # or it is just a way to launder failures.
        self.assertEqual(verdict("[PASS] a\n[PASS] b\n[VERDICT] FAIL\n"), "FAIL")

    def test_last_declaration_wins(self):
        self.assertEqual(verdict("[VERDICT] PASS\n[VERDICT] FAIL\n"), "FAIL")
        self.assertEqual(verdict("[VERDICT] FAIL\n[VERDICT] PASS\n"), "PASS")

    def test_declared_verdict_does_not_outrank_a_hang(self):
        # A process killed at the wall clock did not finish, whatever it managed
        # to print first. HUNG stays the outermost rule.
        self.assertEqual(verdict("[VERDICT] PASS\n", exit_code=124), "HUNG")

    def test_a_malformed_declaration_is_ignored_not_obeyed(self):
        # Only PASS/FAIL are words. Anything else falls through to the markers,
        # rather than becoming a third silent outcome.
        self.assertEqual(verdict("[VERDICT] MAYBE\n[FAIL] b\n"), "FAIL")

    def test_push_error_prefixed_declaration_is_seen(self):
        self.assertEqual(verdict(
            "  - [FAIL] a\nERROR: [VERDICT] PASS\n"), "PASS")


class TheGambitRegression(unittest.TestCase):
    """The failing arm, against a real excerpt of the log that showed it.

    `tests/fixtures/verdict/gambit_xfail_excerpt.log` is lifted verbatim from
    `tests/logs/GambitScenarioRunnerTest.log` of the 2026-08-23 full run, plus
    the `[VERDICT]` line the runner now emits.
    """

    def test_excerpt_before_the_fix_reads_fail(self):
        raw = (FIXTURES / "gambit_xfail_excerpt.log").read_text()
        pre_fix = raw.replace("[VERDICT] PASS", "")
        self.assertEqual(verdict(pre_fix), "FAIL",
                         "the excerpt must reproduce the defect without the new line")

    def test_excerpt_with_the_declaration_reads_pass(self):
        self.assertEqual(
            verdict((FIXTURES / "gambit_xfail_excerpt.log").read_text()), "PASS")

    def test_the_runner_still_reports_a_real_gambit_red(self):
        # The quarantine must not swallow an unexpected failure: when the gambit
        # runner counts a hard red it declares FAIL, and that must survive.
        raw = (FIXTURES / "gambit_xfail_excerpt.log").read_text()
        self.assertEqual(
            verdict(raw.replace("[VERDICT] PASS", "[VERDICT] FAIL")), "FAIL")


class OneImplementationInTheTree(unittest.TestCase):
    """#451: 'Do not add a third verdict implementation.' Two existed."""

    RUNNERS = ("tests/run_all_tests.sh", "tools/run_unlisted_audio_binders.sh")

    def test_every_runner_sources_the_shared_reader(self):
        for rel in self.RUNNERS:
            with self.subTest(runner=rel):
                sourced = 'source "$PROJECT_DIR/tests/lib/verdict.sh"' in (ROOT / rel).read_text()
                self.assertTrue(sourced, f"{rel} must source the one reader")

    def test_no_runner_carries_its_own_marker_rule(self):
        # The literal grep that WAS duplicated in both files. If it reappears the
        # two can drift, and the register is built by merging the stdout of both.
        for rel in self.RUNNERS:
            for rule in (r'grep -q "\[FAIL\]"', r'grep -q "\[PASS\]"'):
                with self.subTest(runner=rel, rule=rule):
                    self.assertFalse(rule in (ROOT / rel).read_text(),
                                     f"{rel} re-implements the verdict rule: {rule}")

    def test_the_summary_counts_every_outcome_separately(self):
        # #451: "NO_VERDICT, TIMEOUT and HUNG are distinct outcomes in the
        # summary." HUNG used to be folded into TIMEOUT — a process killed at the
        # wall clock and a test that declared its own tick budget blown are not
        # the same failure and must not share a number. #462 adds THREW on the
        # same reasoning: a test that threw is not a test that failed an
        # assertion, and folding it into FAILED loses the finding.
        text = (ROOT / "tests" / "run_all_tests.sh").read_text()
        # #463 adds two more on the same reasoning: a scene that asserts nothing
        # by design and a process that died on a signal are neither passes nor
        # failures, and neither is the "the log said nothing" that NO_VERDICT is.
        for line in ("  PASSED:", "  FAILED:", "  THREW:", "  TIMEOUT:", "  HUNG:",
                     "  CRASHED:", "  NOT_A_TEST:", "  NO_VERDICT:"):
            with self.subTest(line=line.strip()):
                self.assertTrue(f'echo "{line}' in text,
                                f"the summary must report {line.strip()} on its own line")

    def test_the_runner_tallies_every_outcome_the_reader_can_return(self):
        # A verdict the runner does not have a case arm for is counted as
        # nothing at all: it prints in the per-test line and then vanishes from
        # the totals, so `PASSED + FAILED + ... != TOTAL` and nobody notices.
        text = (ROOT / "tests" / "run_all_tests.sh").read_text()
        for outcome in ("PASS", "FAIL", "HUNG", "TIMEOUT", "NO_VERDICT", "THREW",
                        "CRASHED", "NOT_A_TEST"):
            with self.subTest(outcome=outcome):
                self.assertRegex(text, rf"(?m)^\s+{outcome}\)\s+\w+=",
                                 f"run_all_tests.sh has no tally arm for {outcome}")

    def test_the_gambit_runner_declares_its_aggregate_verdict(self):
        src = (ROOT / "tests" / "gambit_runner" / "GambitScenarioRunner.gd").read_text()
        self.assertTrue("[VERDICT]" in src,
                        "the test whose aggregate the runner could not hear must declare it")


class AGreenTestDoesNotGetToThrow(unittest.TestCase):
    """#462: the reader read markers and NOTHING else, so a test could throw
    thousands of engine errors and still score PASS.

    Measured on all five archived full runs: 13 tests emit `SCRIPT ERROR` lines
    and **all 13 score PASS** — no red test throws at all. The worst,
    `CameraFeelTunablesTest`, asserts 10 things green while emitting 5,322 errors
    (2,661 identical pairs), a figure stable to the unit across every run.

    WHY THIS IS A VERDICT RULE AND NOT A LINT. A GDScript runtime error is not a
    warning: measured on the 4.8 fork (probe, 2026-08-23), a bad property/index
    access or a wrong-arity dynamic call **aborts the enclosing function and
    returns its declared type's default**, then resumes in the caller. Nothing
    raises and nothing fails. So every assertion after the error, in that
    function, silently does not run — and the type default can walk straight
    through the guard written to catch the degraded case (`SequenceProjector`'s
    `absolute_frameset` returns 0 where its docstring promises -1, so a follow
    row it documents as "disabled" is built with a garbage index instead).

    THE RULE ONLY EVER DOWNGRADES A PASS. It does not rewrite FAIL, TIMEOUT,
    HUNG or NO_VERDICT — a test that is already red keeps the more actionable
    verdict, and the blast radius is confined to greens by construction.
    """

    def test_a_pass_that_threw_is_not_a_pass(self):
        self.assertEqual(verdict("SCRIPT ERROR: boom\n[PASS] a\n"), "THREW")

    def test_a_clean_pass_is_untouched(self):
        self.assertEqual(verdict("[PASS] a\n"), "PASS")

    def test_the_camera_feel_excerpt_reproduces_the_defect(self):
        # The real thing: a green log carrying the R5 pair that repeats 2,661
        # times in the full run.
        raw = (FIXTURES / "camera_feel_threw_excerpt.log").read_text()
        self.assertEqual(verdict(raw), "THREW")

    def test_the_same_excerpt_scored_pass_before_this_rule(self):
        # The failing arm, stated as the thing that used to happen: strip the
        # errors and the very same log is the PASS the runner reported.
        raw = (FIXTURES / "camera_feel_threw_excerpt.log").read_text()
        clean = "\n".join(l for l in raw.splitlines()
                          if not l.lstrip().startswith(("SCRIPT ERROR:", "at:", "GDScript backtrace")))
        self.assertEqual(verdict(clean), "PASS")

    def test_a_declared_pass_that_threw_is_also_caught(self):
        # `[VERDICT] PASS` is the test's own aggregate (#451) — but a test cannot
        # observe its own engine errors, so the declaration does not buy immunity.
        self.assertEqual(verdict("SCRIPT ERROR: boom\n[VERDICT] PASS\n"), "THREW")

    def test_it_does_not_rewrite_a_fail(self):
        self.assertEqual(verdict("SCRIPT ERROR: boom\n[FAIL] a\n"), "FAIL")
        self.assertEqual(verdict("SCRIPT ERROR: boom\n[VERDICT] FAIL\n"), "FAIL")

    def test_it_does_not_rewrite_a_hang_a_timeout_or_a_non_verdict(self):
        self.assertEqual(verdict("SCRIPT ERROR: boom\n[PASS] a\n", exit_code=124), "HUNG")
        self.assertEqual(verdict("SCRIPT ERROR: boom\nTIMEOUT at tick 6007\n"), "TIMEOUT")
        self.assertEqual(verdict("SCRIPT ERROR: boom\nnoise\n"), "NO_VERDICT")

    def test_only_the_engines_own_line_start_form_counts(self):
        # Every one of the 5,424 `SCRIPT ERROR` lines in the 2026-08-23 run is at
        # line start; nothing in the tree prints the string. Anchoring here is
        # safe and keeps a test that DISCUSSES the phrase from failing itself.
        self.assertEqual(verdict("[PASS] a\nthe docs mention SCRIPT ERROR: in prose\n"), "PASS")
        self.assertEqual(verdict("[PASS] a\n   SCRIPT ERROR: indented by the engine\n"), "THREW")


class ExpectedErrorsAreDeclared(unittest.TestCase):
    """The escape hatch, so "expected errors" is a declaration and not a silence.

    ⚠️ IT HAS ZERO USERS TODAY, and that is a finding, not an oversight. #462
    posited two populations — a real defect, and a test deliberately exercising
    an error path where the `SCRIPT ERROR` *is* the assertion. All 13 were read:
    **the second population is empty.** Not one of the 13 declares an expected
    error, and the only two tests in the tree that do document a deliberate error
    path (`TuneTest`, `ScenarioActorTest`) emit zero errors in their passing
    state — the hazard they exercise is guarded, and the guard is what they
    assert. The hatch exists so the rule can be adopted without making that test
    unwritable, and so the first one to need it has to say so out loud.
    """

    def test_a_declared_count_is_honoured(self):
        self.assertEqual(verdict(
            "[EXPECT_ERRORS] 1 — the freed-Callable hazard this test exercises\n"
            "SCRIPT ERROR: boom\n[PASS] a\n"), "PASS")

    def test_throwing_more_than_declared_is_still_caught(self):
        self.assertEqual(verdict(
            "[EXPECT_ERRORS] 1 — one hazard\n"
            "SCRIPT ERROR: boom\nSCRIPT ERROR: bang\n[PASS] a\n"), "THREW")

    def test_throwing_fewer_than_declared_is_caught_too(self):
        # Symmetric on purpose. A test that stopped exercising its error path is
        # no longer testing what it says it tests, and a one-sided rule would let
        # that rot silently — the same reasoning that made `[VERDICT]` symmetric.
        self.assertEqual(verdict(
            "[EXPECT_ERRORS] 2 — two hazards\n"
            "SCRIPT ERROR: boom\n[PASS] a\n"), "THREW")

    def test_declaring_zero_is_the_default_and_changes_nothing(self):
        self.assertEqual(verdict("[EXPECT_ERRORS] 0 — none\n[PASS] a\n"), "PASS")

    def test_last_declaration_wins(self):
        self.assertEqual(verdict(
            "[EXPECT_ERRORS] 5 — stale\n[EXPECT_ERRORS] 1 — current\n"
            "SCRIPT ERROR: boom\n[PASS] a\n"), "PASS")

    def test_every_declaration_in_the_tree_carries_a_reason(self):
        # Vacuous today (zero declarations) and stated as such. It bites the
        # first test that adds one: a bare number is a silence with a count on
        # it, which is the thing this ticket exists to remove.
        import re as _re
        found = 0
        for path in sorted((ROOT / "tests").rglob("*.gd")):
            for line in path.read_text(errors="replace").splitlines():
                if "[EXPECT_ERRORS]" not in line or line.lstrip().startswith("#"):
                    continue
                found += 1
                with self.subTest(file=path.name, line=line.strip()[:60]):
                    self.assertRegex(
                        line, r"\[EXPECT_ERRORS\]\s+\d+\s+—\s*\S",
                        "an expected-error declaration must state WHY, on the same line")
        self.assertGreaterEqual(found, 0)


# The NO_VERDICT sweep's population (#463): scenes that are rigs, not tests.
# `TypewriterGoldenDiff` was here until 6606a9cef deleted the scene; it is gone
# from this tuple because the scene is gone, not because the finding changed.
SWEPT_RIGS = ("DeclickDebug", "RenderInGameAudio", "RenderTypewriterOffline",
              "RenderTypewriterOnline", "SfxLiveStressTest", "SfxPopDiagTest",
              "TypewriterClickCapture", "TypewriterCollisionProbe")


class ARigIsNotASilentTest(unittest.TestCase):
    """#463: `NO_VERDICT` was never holding tests that reached a verdict.

    The ticket named two cases. Both are stale. `ScenarioWalkToAnimTest` — the
    one that printed `=== 16 passed, 0 failed ===` / `RESULT: PASS` and no
    marker — was already fixed on trunk by `2538dd4cc`, and it scores PASS in the
    three newest archived runs. `DetailStatsDeltaFrameRideTest` is not a
    convention mismatch at all (see `TheProcessDiedIsNotSilence`).

    SWEPT ACROSS ALL SEVEN ARCHIVED RUNS — five suite runs (2,057 verdicts) and
    two `run_unlisted_audio_binders.sh` runs (42) — the entire remaining
    `NO_VERDICT` population is **nine scenes that are not tests**:
    `DeclickDebug`, `RenderInGameAudio`, `RenderTypewriterOffline`,
    `RenderTypewriterOnline`, `SfxLiveStressTest`, `SfxPopDiagTest`,
    `TypewriterClickCapture`, `TypewriterCollisionProbe`, `TypewriterGoldenDiff`.
    Every one is a capture rig, render tool or diagnostic probe that says so in
    its own header docstring, runs to completion, prints its telemetry and exits
    0. `RenderTypewriterOffline` ends `[tw-offline] done — A/B the _nobus vs
    _withbus WAVs above.` There is nothing for it to assert.

    THE CLASSIFICATION ALREADY EXISTED — AS PROSE. `freeze_test_baseline.py`'s
    `RED_REASONS` carries all nine, hand-written, each beginning *"not a test —"*,
    and one of them literally reads *"NO_VERDICT is the right score"*. A dict of
    prose in a Python tool is not a channel: the runner still cannot tell a rig
    from a break, and the tenth rig to be written needs a tenth hand-written
    entry that nothing forces anyone to add. `[NOT_A_TEST] <why>` is that prose
    turned into a line the reader can score — the same move `[VERDICT]` made for
    the aggregate (#451) and `[EXPECT_ERRORS]` made for a deliberate error path
    (#462).

    IT CANNOT LAUNDER ANYTHING, BY POSITION. The declaration is read AFTER the
    marker rules, so any `[PASS]`, `[FAIL]` or `[VERDICT]` in the log outranks
    it, and rule 1 still takes a hang first. It speaks only where the log
    otherwise says nothing at all — exactly the silence it replaces — and
    `NOT_A_TEST` is never counted as a pass.
    """

    def test_a_declared_rig_is_not_a_non_verdict(self):
        self.assertEqual(verdict("[NOT_A_TEST] a capture rig, nothing to assert\n"),
                         "NOT_A_TEST")

    def test_silence_without_the_declaration_is_still_no_verdict(self):
        # The failing arm: this is what all nine score today.
        self.assertEqual(verdict("[tw-offline] done — A/B the WAVs above.\n"), "NO_VERDICT")

    def test_the_render_tool_excerpt_reproduces_the_defect(self):
        raw = (FIXTURES / "render_typewriter_rig_excerpt.log").read_text()
        self.assertEqual(verdict(raw), "NO_VERDICT")

    def test_the_same_excerpt_with_the_declaration_reads_not_a_test(self):
        raw = (FIXTURES / "render_typewriter_rig_excerpt.log").read_text()
        self.assertEqual(verdict(raw + "[NOT_A_TEST] offline render tool — writes WAVs for a human\n"),
                         "NOT_A_TEST")

    def test_a_pass_marker_outranks_the_declaration(self):
        # A rig that grows an assertion is a test, and the assertion wins.
        self.assertEqual(verdict("[NOT_A_TEST] a rig\n[PASS] but it asserted\n"), "PASS")

    def test_a_fail_marker_outranks_the_declaration(self):
        # The one that matters: the declaration must not be an escape from red.
        self.assertEqual(verdict("[NOT_A_TEST] a rig\n[FAIL] but it asserted\n"), "FAIL")

    def test_a_declared_verdict_outranks_the_declaration(self):
        self.assertEqual(verdict("[NOT_A_TEST] a rig\n[VERDICT] FAIL\n"), "FAIL")

    def test_a_tick_timeout_outranks_the_declaration(self):
        self.assertEqual(verdict("[NOT_A_TEST] a rig\nTIMEOUT at tick 6007\n"), "TIMEOUT")

    def test_a_hang_still_outranks_it(self):
        # `TypewriterClickTest` WAS a rig with no exit condition, burning the full
        # 360 s wall clock every binder run. Declaring itself a rig must not buy it
        # out of that — rule 1 is first for a reason. #472 gave it a budget, so it
        # now ends and scores NOT_A_TEST honestly; this case is synthesized, so it
        # goes on guarding the ordering regardless of what any scene does.
        self.assertEqual(verdict("[NOT_A_TEST] a rig\n", exit_code=124), "HUNG")

    def test_a_bare_declaration_with_no_reason_is_ignored(self):
        # Same rule as `[EXPECT_ERRORS]`: a declaration without a WHY is a
        # silence with a label on it.
        self.assertEqual(verdict("[NOT_A_TEST]\n"), "NO_VERDICT")
        self.assertEqual(verdict("[NOT_A_TEST]   \n"), "NO_VERDICT")

    def test_the_throw_rule_does_not_reach_it(self):
        # THREW only ever downgrades a PASS (#462). A rig is not a green.
        self.assertEqual(verdict("SCRIPT ERROR: boom\n[NOT_A_TEST] a rig\n"), "NOT_A_TEST")

    def test_push_error_prefixed_declaration_is_seen(self):
        self.assertEqual(verdict("ERROR: [NOT_A_TEST] a rig, via push_error\n"), "NOT_A_TEST")

    def test_every_declaration_in_the_tree_carries_a_reason(self):
        found = 0
        for path in sorted((ROOT / "tests").rglob("*.gd")):
            for line in path.read_text(errors="replace").splitlines():
                if "[NOT_A_TEST]" not in line or line.lstrip().startswith("#"):
                    continue
                found += 1
                with self.subTest(file=path.name, line=line.strip()[:60]):
                    self.assertRegex(
                        line, r"\[NOT_A_TEST\]\s+\S",
                        "a not-a-test declaration must state WHY, on the same line")
        self.assertGreaterEqual(found, len(SWEPT_RIGS),
                                "every swept rig must declare itself")

    def test_the_swept_rigs_declare_themselves(self):
        # Named, because the sweep is the evidence and a list nobody pins rots.
        # AND A PINNED LIST ROTS THE OTHER WAY TOO. `TypewriterGoldenDiff` was
        # deliberately deleted by 6606a9cef along with the GDScript mix stage it
        # diffed; this list was not updated, so `read_text` raised
        # FileNotFoundError, this module failed, and run_all_tests.sh aborted
        # with "the suite cannot score itself" BEFORE running a single Godot
        # test. The whole suite was unrunnable and the branch looked fine.
        #
        # So a name that no longer exists must say what it means rather than
        # crash: a deleted rig cannot score NO_VERDICT, and dropping it from the
        # sweep is correct.
        missing = [stem for stem in SWEPT_RIGS
                   if not (ROOT / "tests" / f"{stem}.gd").exists()]
        self.assertEqual(missing, [],
                         "SWEPT_RIGS names scenes that no longer exist — delete them "
                         "from the tuple when you delete the scene, or this module "
                         "takes the entire suite down with it")
        for stem in SWEPT_RIGS:
            with self.subTest(rig=stem):
                src = (ROOT / "tests" / f"{stem}.gd").read_text(errors="replace")
                self.assertIn("[NOT_A_TEST]", src,
                              f"{stem} scored NO_VERDICT in both archived binder runs")


class TheProcessDiedIsNotSilence(unittest.TestCase):
    """#463: the one NO_VERDICT left in the suite corpus is a SEGFAULT.

    `DetailStatsDeltaFrameRideTest` scores PASS with 11 green assertions in four
    of the five archived full runs. In `e2-suite-confirm-2026-08-22.log` it is
    `NO_VERDICT` — and the block is not a quiet log, it is a Vulkan device-lost
    crash: `ERROR: Last known breadcrumb: UI_PASS`, `handle_crash: Program
    crashed with signal 11`, a 19-frame C++ backtrace through
    `RenderingDeviceDriverVulkan::on_device_lost()`, and finally `timeout: the
    monitored command dumped core`.

    `NO_VERDICT` means *"the log said nothing either way"*, and its whole point
    (#451) is that a test producing no verdict **did not run**. A process that
    died on a signal is not silence, and reading it as silence is the same
    conflation `HUNG` was split out of `TIMEOUT` to end: the process's fate is
    not something its stdout can report, which is why both read the exit code
    and nothing else.

    IT ONLY EVER REFINES A NON-VERDICT. Checked after every marker rule, so a
    log that reached a verdict keeps it. That is deliberate and it is measured:
    63 of the 410 tests in EVERY archived run print `[PASS]` and then dump core
    at shutdown. Those greens are a real finding and a separate one — they are
    filed, not folded in here, because a rule that turned 63 passes into crashes
    would bury the one case this ticket is about.
    """

    def test_a_signal_death_with_no_verdict_is_not_silence(self):
        self.assertEqual(verdict("some telemetry\n", exit_code=139), "CRASHED")

    def test_the_same_log_at_exit_zero_is_still_no_verdict(self):
        # The distinction is the exit code, and only the exit code.
        self.assertEqual(verdict("some telemetry\n", exit_code=0), "NO_VERDICT")

    def test_the_detail_stats_excerpt_reproduces_the_defect(self):
        raw = (FIXTURES / "detail_stats_crash_excerpt.log").read_text()
        self.assertEqual(verdict(raw, exit_code=139), "CRASHED")

    def test_the_same_excerpt_scored_no_verdict_before_this_rule(self):
        # The failing arm, stated as the thing that used to happen.
        raw = (FIXTURES / "detail_stats_crash_excerpt.log").read_text()
        self.assertEqual(verdict(raw, exit_code=0), "NO_VERDICT")

    def test_a_crash_after_a_green_verdict_keeps_the_green(self):
        # 63 tests per run do exactly this. Out of scope on purpose; filed.
        self.assertEqual(verdict("[PASS] a\n", exit_code=139), "PASS")

    def test_a_crash_after_a_red_verdict_keeps_the_red(self):
        self.assertEqual(verdict("[FAIL] a\n", exit_code=139), "FAIL")
        self.assertEqual(verdict("[VERDICT] FAIL\n", exit_code=139), "FAIL")

    def test_a_hang_still_wins(self):
        # 124 is timeout's own code and it is checked first.
        self.assertEqual(verdict("noise\n", exit_code=124), "HUNG")

    def test_a_declared_rig_that_died_on_a_signal_is_a_crash(self):
        # A rig is allowed to assert nothing. It is not allowed to segfault.
        self.assertEqual(verdict("[NOT_A_TEST] a rig\n", exit_code=139), "CRASHED")

    def test_every_signal_death_counts_not_just_sigsegv(self):
        for code in (128 + 6, 128 + 9, 128 + 11, 128 + 15):
            with self.subTest(exit_code=code):
                self.assertEqual(verdict("noise\n", exit_code=code), "CRASHED")

    def test_timeouts_own_error_codes_are_not_crashes(self):
        # 125 (timeout failed), 126 (not executable), 127 (not found) are below
        # 128 and are not signal deaths. They stay NO_VERDICT.
        for code in (125, 126, 127):
            with self.subTest(exit_code=code):
                self.assertEqual(verdict("noise\n", exit_code=code), "NO_VERDICT")



if __name__ == "__main__":
    unittest.main()
