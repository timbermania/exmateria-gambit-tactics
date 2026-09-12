"""Tests for the re-takeable test register — #454, map #450.

WHAT THIS INSTRUMENT HAS TO GET RIGHT, AND WHY EACH RULE HAS A FIRING ARM HERE.

`docs/TEST-BASELINE-E2.tsv` is a FROZEN pre-move measurement: it answers one
question about one move and `check_test_baseline.py` correctly refuses to
re-freeze it. #454 asks for the other shape — a register takeable on ANY commit
and diffable against ANY other. The hazard is that such a thing is trivially easy
to build WRONG, in exactly the ways this map has already paid for:

  1. A REGISTER THAT RE-DERIVES THE VERDICT is a second opinion nobody asked for.
     #451 collapsed two copies of the rule into `tests/lib/verdict.sh`; the
     register reads that reader's output out of a run log and never restates it.

  2. A REGISTER TAKEN FROM ONE RUN CANNOT REPORT A FLAKE SET, and one that leaves
     the column blank is claiming a stability it never measured. #417 adopted 275
     tests that are green exactly ONCE. The register says `UNMEASURED` for those,
     out loud, and the diff refuses to call any of them a mover.

  3. A DIFF OF TWO SINGLE RUNS REPORTS FLAKES AS MOVERS. `diff_arm_verdicts.py`
     learned this against the archived corpus — four tests are not constant across
     three same-tree runs, so a naive diff quarantines four innocent tests. Same
     lesson, different axis: there it was arm-vs-arm, here it is commit-vs-commit.

  4. PROVENANCE IS NOT SOMETHING YOU STAMP AT TAKE TIME. The commit, the engine,
     the harness mode, the addon-sync state and the cache state are properties of
     the RUN, and only the runner was present for it. Every one of them is read
     out of the runner's own banner; `take` never runs `git rev-parse`. Two run
     logs from different commits are a hard error, not a merge — that is the
     provenance error the map's headline number was built on.

Pure stdlib, `unittest`. Run from `tools/`.
"""
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import suite_register as tr


BANNER = """\
======================================
  GPU Combat Test Suite
  Running {n} tests
  code_commit {sha}
  godot 4.8.dev.custom_build.3e530a3e9
  addon_sync {addon}
  godot_cache {cache}
  test_coverage {cov}
  started 2026-08-25T04:00:00-07:00
======================================
"""

COVER = "744 scenes on disk; 687 listed, 33 declares, 24 skipped, 0 unclassified"


def run_log(tests, sha="abc1234", addon="in-step", cache="warm 12497 imported",
            coverage=True, parallel=None):
    """A synthetic runner stdout: pre-flights, banner, then the per-test block.

    `tests` is a list of (stem, verdict, seconds, exit); `seconds`/`exit` may be
    None to model an ARCHIVED run taken before the runner emitted them.
    """
    out = []
    cov = COVER if coverage else None
    banner = BANNER.format(n=len(tests), sha=sha, addon=addon, cache=cache,
                           cov=cov or "")
    if not coverage:
        banner = "\n".join(l for l in banner.splitlines()
                           if not l.strip().startswith("test_coverage")) + "\n"
    if parallel is None:
        out.append(banner)
    else:
        out.append(banner
                   .replace("  GPU Combat Test Suite\n  Running %d tests" % len(tests),
                            "  GPU Combat Test Suite — PARALLEL\n  Running %d tests, "
                            "%d workers, 1 in the sequential lane" % (len(tests), parallel)))
    for i, (stem, verdict, secs, code) in enumerate(tests, 1):
        out.append(f"[{i}/{len(tests)}] Running {stem}...")
        out.append(f"  -> {verdict}")
        if secs is not None:
            out.append(f"  seconds {secs}")
        if code is not None:
            out.append(f"  exit {code}")
        out.append("")
    return "\n".join(out)


def write(tmp, name, text):
    p = pathlib.Path(tmp) / name
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)
    return p


class ReadsTheOneReaderRatherThanRescoring(unittest.TestCase):
    """Rule 1. The verdict column is the reader's output, transcribed."""

    def test_verdict_comes_from_the_runner_line(self):
        with tempfile.TemporaryDirectory() as tmp:
            lg = write(tmp, "run.log", run_log([("AlphaTest", "THREW", 4.1, 0)]))
            reg = tr.take([lg], log_dir=pathlib.Path(tmp) / "logs")
            self.assertEqual(reg.row("AlphaTest").verdict, "THREW")

    def test_a_log_full_of_pass_markers_does_not_override_the_reader(self):
        """The register must not look at the per-test log to score. `THREW` and
        `NOT_A_TEST` are both verdicts a log full of `[PASS]` can carry, and a
        register that re-read the markers would silently undo rules 7 and 9."""
        with tempfile.TemporaryDirectory() as tmp:
            write(tmp, "logs/AlphaTest.log", "[PASS] one\n[PASS] two\n")
            lg = write(tmp, "run.log", run_log([("AlphaTest", "THREW", 4.1, 0)]))
            reg = tr.take([lg], log_dir=pathlib.Path(tmp) / "logs")
            self.assertEqual(reg.row("AlphaTest").verdict, "THREW")
            self.assertEqual(reg.row("AlphaTest").markers, 2)


class OneRunCannotReportAFlakeSet(unittest.TestCase):
    """Rule 2. The column that #417's 275 once-green adoptions land in."""

    def test_a_single_repeat_is_unmeasured_not_stable(self):
        self.assertEqual(tr.stability(["PASS"]), ("PASS", "UNMEASURED×1"))

    def test_agreeing_repeats_are_stable_and_say_how_many(self):
        self.assertEqual(tr.stability(["PASS", "PASS", "PASS"]),
                         ("PASS", "STABLE×3"))

    def test_disagreeing_repeats_are_flaky_and_carry_the_multiset(self):
        verdict, field = tr.stability(["PASS", "FAIL", "PASS"])
        self.assertEqual(verdict, "FLAKY")
        self.assertEqual(field, "FLAKY(PASS×2,FAIL×1)")

    def test_the_header_states_the_repeat_count_and_the_flake_count(self):
        with tempfile.TemporaryDirectory() as tmp:
            a = write(tmp, "a.log", run_log([("A", "PASS", 1.0, 0), ("B", "PASS", 1.0, 0)]))
            b = write(tmp, "b.log", run_log([("A", "PASS", 1.2, 0), ("B", "FAIL", 1.1, 0)]))
            reg = tr.take([a, b], log_dir=pathlib.Path(tmp) / "logs")
            self.assertEqual(reg.header["repeats"], "2")
            self.assertIn("1", reg.header["flakes"])

    def test_one_repeat_says_so_in_the_flakes_header_instead_of_zero(self):
        """`flakes 0` from a single run is the exact false-confidence #454 names.
        275 tests were adopted green-once; the header must not read as a clean
        bill of health for them."""
        with tempfile.TemporaryDirectory() as tmp:
            a = write(tmp, "a.log", run_log([("A", "PASS", 1.0, 0)]))
            reg = tr.take([a], log_dir=pathlib.Path(tmp) / "logs")
            self.assertIn("UNMEASURED", reg.header["flakes"])
            self.assertNotEqual(reg.header["flakes"].strip(), "0")


class ProvenanceIsReadFromTheRunNeverStampedAtTakeTime(unittest.TestCase):
    """Rule 4. `take` runs no `git rev-parse` — the run's banner is the source."""

    def test_commit_engine_addon_and_cache_come_from_the_banner(self):
        with tempfile.TemporaryDirectory() as tmp:
            lg = write(tmp, "run.log", run_log([("A", "PASS", 1.0, 0)],
                                               sha="deadbee", addon="in-step",
                                               cache="warm 12497 imported"))
            reg = tr.take([lg], log_dir=pathlib.Path(tmp) / "logs")
            self.assertEqual(reg.header["code_commit"], "deadbee")
            self.assertIn("4.8.dev", reg.header["godot"])
            self.assertEqual(reg.header["addon_sync"], "in-step")
            self.assertEqual(reg.header["godot_cache"], "warm 12497 imported")

    def test_two_logs_from_different_commits_are_a_hard_error(self):
        """Merging them is the provenance error the map's own headline was built
        on: a register from the 08:14 run read against a tally from 23:40."""
        with tempfile.TemporaryDirectory() as tmp:
            a = write(tmp, "a.log", run_log([("A", "PASS", 1.0, 0)], sha="aaaaaaa"))
            b = write(tmp, "b.log", run_log([("A", "FAIL", 1.0, 0)], sha="bbbbbbb"))
            with self.assertRaises(tr.ProvenanceError):
                tr.take([a, b], log_dir=pathlib.Path(tmp) / "logs")

    def test_a_log_with_no_banner_says_unknown_rather_than_guessing(self):
        with tempfile.TemporaryDirectory() as tmp:
            lg = write(tmp, "run.log", "[1/1] Running A...\n  -> PASS\n")
            reg = tr.take([lg], log_dir=pathlib.Path(tmp) / "logs")
            self.assertEqual(reg.header["code_commit"], "UNKNOWN")

    def test_the_harness_mode_is_the_runners_own_banner(self):
        with tempfile.TemporaryDirectory() as tmp:
            seq = write(tmp, "s.log", run_log([("A", "PASS", 1.0, 0)]))
            par = write(tmp, "p.log", run_log([("A", "PASS", 1.0, 0)], parallel=8))
            self.assertIn("sequential",
                          tr.take([seq], log_dir=pathlib.Path(tmp) / "l").header["runner"])
            self.assertIn("parallel N=8",
                          tr.take([par], log_dir=pathlib.Path(tmp) / "l").header["runner"])


class TheWallClockIsMeasuredOrAbsentNeverZero(unittest.TestCase):
    """Rule 3 of #454's `What it must carry`, and the archived-run trap."""

    def test_per_test_seconds_and_a_total(self):
        with tempfile.TemporaryDirectory() as tmp:
            lg = write(tmp, "run.log", run_log([("A", "PASS", 4.0, 0),
                                                ("B", "PASS", 6.0, 0)]))
            reg = tr.take([lg], log_dir=pathlib.Path(tmp) / "logs")
            self.assertEqual(reg.row("A").seconds, 4.0)
            self.assertIn("10.0", reg.header["wall_clock"])

    def test_a_run_that_did_not_time_itself_reports_a_dash(self):
        """Every archived run predates the runner emitting `  seconds`. A `0.0`
        there would read as an instant test and poison the budget."""
        with tempfile.TemporaryDirectory() as tmp:
            lg = write(tmp, "run.log", run_log([("A", "PASS", None, None)]))
            reg = tr.take([lg], log_dir=pathlib.Path(tmp) / "logs")
            self.assertIsNone(reg.row("A").seconds)
            self.assertIn("-", reg.render().splitlines()[-1])


class FailingAssertionNamesAreAttached(unittest.TestCase):
    """#454's `What it must carry` 1 — `PASS`/`FAIL` distinct AND the names."""

    def test_the_fail_marker_text_is_carried_into_the_row(self):
        with tempfile.TemporaryDirectory() as tmp:
            write(tmp, "logs/A.log",
                  "[PASS] warms up\n"
                  "  [FAIL] seek dispatches exactly one action: got=0 want=1\n"
                  "[FAIL] ADR-0032: firer never entered AWAITING_IMPACT\n")
            lg = write(tmp, "run.log", run_log([("A", "FAIL", 3.0, 0)]))
            reg = tr.take([lg], log_dir=pathlib.Path(tmp) / "logs")
            names = reg.row("A").failing
            self.assertIn("seek dispatches exactly one action: got=0 want=1", names)
            self.assertIn("ADR-0032: firer never entered AWAITING_IMPACT", names)

    def test_a_stale_per_test_log_is_not_read_for_a_test_this_run_never_reached(self):
        """`tests/logs/` is tracked and nothing marks it stale. A row the run did
        not produce must not borrow last month's evidence."""
        with tempfile.TemporaryDirectory() as tmp:
            write(tmp, "logs/Ghost.log", "[FAIL] from a run in July\n")
            lg = write(tmp, "run.log", run_log([("A", "PASS", 1.0, 0)]))
            reg = tr.take([lg], log_dir=pathlib.Path(tmp) / "logs")
            self.assertIsNone(reg.row("Ghost"))


class TheCoverageTripleIsOnItsFace(unittest.TestCase):
    """#454's `What it must not do` 3 — the register states what it scanned."""

    def test_the_triple_is_read_from_the_runs_own_banner_stamp(self):
        with tempfile.TemporaryDirectory() as tmp:
            lg = write(tmp, "run.log", run_log([("A", "PASS", 1.0, 0),
                                                ("B", "NO_VERDICT", 1.0, 0)]))
            reg = tr.take([lg], log_dir=pathlib.Path(tmp) / "logs")
            cov = reg.header["coverage"]
            self.assertIn("744", cov)     # scenes on disk
            self.assertIn("687", cov)     # listed
            self.assertIn("2 run", cov)   # this run reached two
            self.assertIn("1 verdict", cov)  # one of them produced one

    def test_the_figure_is_the_runs_not_the_trees_at_read_time(self):
        """The array grew by 275 entries in ONE commit (#417). A register that
        re-derived coverage when it was READ would print today's tree beside a
        run taken before it — a provenance error inside the field whose whole
        job is to expose one."""
        with tempfile.TemporaryDirectory() as tmp:
            lg = write(tmp, "run.log", run_log([("A", "PASS", 1.0, 0)]))
            text = lg.read_text().replace("744 scenes on disk", "412 scenes on disk")
            lg.write_text(text)
            reg = tr.take([lg], log_dir=pathlib.Path(tmp) / "logs")
            self.assertIn("412 scenes on disk", reg.header["coverage"])

    def test_a_log_with_no_coverage_stamp_says_so(self):
        with tempfile.TemporaryDirectory() as tmp:
            lg = write(tmp, "run.log", run_log([("A", "PASS", 1.0, 0)], coverage=False))
            reg = tr.take([lg], log_dir=pathlib.Path(tmp) / "logs")
            self.assertIn("UNKNOWN", reg.header["coverage"])


class ARegisterRoundTrips(unittest.TestCase):
    """`diff` consumes what `take` writes, so the file is the interface."""

    def test_render_then_parse_returns_the_same_rows_and_header(self):
        with tempfile.TemporaryDirectory() as tmp:
            lg = write(tmp, "run.log", run_log([("A", "PASS", 4.0, 0),
                                                ("B", "FAIL", 6.5, 1)]))
            reg = tr.take([lg], log_dir=pathlib.Path(tmp) / "logs")
            back = tr.parse_register(reg.render())
            self.assertEqual(back.header["code_commit"], reg.header["code_commit"])
            self.assertEqual(back.row("B").verdict, "FAIL")
            self.assertEqual(back.row("B").seconds, 6.5)
            self.assertEqual(back.row("A").verdict, "PASS")


class TheDiffRefusesToOvercallAMover(unittest.TestCase):
    """Rule 3. The whole reason this is not `diff <(a) <(b)`."""

    def test_same_verdict_is_same(self):
        d = tr.classify("T", tr.Row("T", "PASS", "STABLE×2", 1.0),
                             tr.Row("T", "PASS", "STABLE×2", 1.0))
        self.assertEqual(d.state, "SAME")

    def test_stable_on_both_sides_and_different_is_moved(self):
        d = tr.classify("T", tr.Row("T", "PASS", "STABLE×2", 1.0),
                             tr.Row("T", "FAIL", "STABLE×3", 1.0))
        self.assertEqual(d.state, "MOVED")

    def test_one_repeat_on_either_side_is_unconfirmed_not_moved(self):
        """A single run each side cannot tell a mover from a coin flip. Reporting
        MOVED here is how four innocent tests get quarantined."""
        d = tr.classify("T", tr.Row("T", "PASS", "UNMEASURED×1", 1.0),
                             tr.Row("T", "FAIL", "STABLE×3", 1.0))
        self.assertEqual(d.state, "UNCONFIRMED")

    def test_a_flaky_side_settles_it_before_a_move_is_considered(self):
        d = tr.classify("T", tr.Row("T", "FLAKY", "FLAKY(PASS×2,FAIL×1)", 1.0),
                             tr.Row("T", "FAIL", "STABLE×3", 1.0))
        self.assertEqual(d.state, "FLAKY")

    def test_flaky_on_both_sides_is_not_silently_same(self):
        """Both cells read `FLAKY`, so a naive equality test calls it SAME and
        loses the one fact the reader needs."""
        d = tr.classify("T", tr.Row("T", "FLAKY", "FLAKY(PASS×1,FAIL×1)", 1.0),
                             tr.Row("T", "FLAKY", "FLAKY(PASS×1,FAIL×1)", 1.0))
        self.assertEqual(d.state, "FLAKY")

    def test_present_in_one_register_only_is_missing(self):
        d = tr.classify("T", tr.Row("T", "PASS", "STABLE×2", 1.0), None)
        self.assertEqual(d.state, "MISSING")


class TheDiffPricesTheRunAsWellAsScoringIt(unittest.TestCase):
    """#454's `What it must carry` 3 — a cost regression is as visible as a
    verdict regression."""

    def test_seconds_delta_is_reported_per_test(self):
        d = tr.classify("T", tr.Row("T", "PASS", "STABLE×2", 4.0),
                             tr.Row("T", "PASS", "STABLE×2", 9.0))
        self.assertEqual(d.seconds_delta, 5.0)

    def test_an_unmeasured_side_yields_no_delta_rather_than_a_fake_one(self):
        d = tr.classify("T", tr.Row("T", "PASS", "STABLE×2", None),
                             tr.Row("T", "PASS", "STABLE×2", 9.0))
        self.assertIsNone(d.seconds_delta)

    def test_the_total_wall_clock_delta_is_in_the_diff_summary(self):
        a = tr.Register({"code_commit": "aaa"},
                        [tr.Row("T", "PASS", "STABLE×2", 4.0)])
        b = tr.Register({"code_commit": "bbb"},
                        [tr.Row("T", "PASS", "STABLE×2", 9.0)])
        self.assertIn("+5.0", tr.diff_report(a, b))


class TheDiffNamesExactlyTheTestThatMoved(unittest.TestCase):
    """#454's last Done bullet, in miniature."""

    def test_one_mover_among_many_stable_rows(self):
        rows_a = [tr.Row(f"T{i}", "PASS", "STABLE×2", 1.0) for i in range(5)]
        rows_b = [tr.Row(f"T{i}", "PASS", "STABLE×2", 1.0) for i in range(5)]
        rows_b[3] = tr.Row("T3", "FAIL", "STABLE×2", 1.0)
        a = tr.Register({"code_commit": "aaa"}, rows_a)
        b = tr.Register({"code_commit": "bbb"}, rows_b)
        moved = [d for d in tr.diff(a, b) if d.state == "MOVED"]
        self.assertEqual([d.test for d in moved], ["T3"])


if __name__ == "__main__":
    unittest.main()


class BothRunnersEmitWhatTheRegisterReads(unittest.TestCase):
    """The contract, checked against the runners themselves — not declared.

    Every column in this register is downstream of two lines of runner output.
    A guard that only tested the parser against synthetic logs would stay green
    through the exact failure it exists to catch: a runner that stopped printing
    them, and a register that then reported `-` for every wall clock and called
    it a measurement.
    """

    ROOT = pathlib.Path(__file__).resolve().parent.parent
    RUNNER = ROOT / "tests" / "run_all_tests.sh"

    def _per_test_block(self):
        """The runner's per-test loop, sliced FORWARD from the block start.

        `src.index("timeout 360")` from position 0 finds the first mention
        anywhere in a file that opens with 2,000 lines of array and prose, and
        this session's own comment about the wall clock already emptied that
        slice once in `test_run_tests_parallel`. Same lesson, applied on the way
        in rather than after.
        """
        src = self.RUNNER.read_text()
        start = src.index("EXTRA_ARGS=()")
        end = src.index("RESULTS SUMMARY", start)
        return src[start:end]

    def test_the_sequential_runner_prints_seconds_and_exit(self):
        block = self._per_test_block()
        self.assertIn("seconds %d.%02d", block,
                      "run_all_tests.sh no longer prints `  seconds` — the "
                      "register's wall-clock budget is silently unmeasured")
        self.assertIn('echo "  exit $EXIT_CODE"', block)

    def test_the_sequential_runner_stamps_the_harness(self):
        """The INVOCATION, not the word.

        Seeded red by deleting the `uv run` line and it stayed GREEN, because
        the comment block above it names the tool — the guard was reading the
        prose that explains the rule instead of the line that obeys it. That is
        the same defect as `test_run_tests_parallel`'s emptied slice, found in a
        guard written in the same session that fixed it. An assertion over a
        source file has to match something the shell would EXECUTE.
        """
        lines = [l.strip() for l in self.RUNNER.read_text().splitlines()
                 if not l.lstrip().startswith("#")]
        self.assertIn('(cd "$PROJECT_DIR" && uv run python tools/harness_stamp.py)',
                      lines,
                      "the banner no longer RUNS harness_stamp.py, so every "
                      "register taken from it says UNKNOWN for addon_sync and "
                      "godot_cache")

    def test_the_parallel_arms_progress_block_parses_back(self):
        """The parallel runner's own formatter, round-tripped through `take`."""
        sys.path.insert(0, str(self.ROOT / "tools"))
        import run_tests_parallel as rtp
        with tempfile.TemporaryDirectory() as tmp:
            text = rtp.format_progress(1, 2, "A", "PASS", 4.25, 0) \
                 + rtp.format_progress(2, 2, "B", "CRASHED", 1.5, 139)
            lg = write(tmp, "run.log", text)
            reg = tr.take([lg], log_dir=pathlib.Path(tmp) / "logs")
            self.assertEqual(reg.row("A").seconds, 4.25)
            self.assertEqual(reg.row("B").verdict, "CRASHED")
            self.assertEqual(reg.row("B").exit_code, 139)

    def test_an_arm_that_did_not_measure_prints_nothing_rather_than_zero(self):
        sys.path.insert(0, str(self.ROOT / "tools"))
        import run_tests_parallel as rtp
        out = rtp.format_progress(1, 1, "A", "PASS")
        self.assertNotIn("seconds", out)
        self.assertNotIn("exit", out)

    def test_the_verdict_line_shape_is_untouched_by_the_new_lines(self):
        """`freeze_test_baseline.verdicts()` and every archived-run replay read
        `  -> WORD`. Decorating it would corrupt the corpus this map is scored
        against."""
        sys.path.insert(0, str(self.ROOT / "tools"))
        import run_tests_parallel as rtp
        import freeze_test_baseline as fz
        with tempfile.TemporaryDirectory() as tmp:
            lg = write(tmp, "p.log",
                       rtp.format_progress(1, 1, "A", "THREW", 9.0, 0))
            self.assertEqual(fz.verdicts(lg), {"A": "THREW"})


class TheAggregateMarkerIsNotAnAssertionName(unittest.TestCase):
    """Found on the live #454 demonstration, not reasoned about in advance."""

    def test_a_bare_stem_fail_marker_is_dropped_from_the_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            write(tmp, "logs/CameraUnitsTest.log",
                  "[FAIL] 1 tile → raw 28 — expected 28, got 27\n"
                  "=== CameraUnitsTest: 22 passed, 3 failed ===\n"
                  "[FAIL] CameraUnitsTest\n")
            lg = write(tmp, "run.log", run_log([("CameraUnitsTest", "FAIL", 5.4, 1)]))
            reg = tr.take([lg], log_dir=pathlib.Path(tmp) / "logs")
            failing = reg.row("CameraUnitsTest").failing
            self.assertIn("1 tile → raw 28", failing)
            self.assertNotIn("| CameraUnitsTest", failing)

    def test_the_marker_count_still_counts_it(self):
        """It IS a marker. The row just does not call it an assertion."""
        with tempfile.TemporaryDirectory() as tmp:
            write(tmp, "logs/A.log", "[FAIL] real one\n[FAIL] A\n")
            lg = write(tmp, "run.log", run_log([("A", "FAIL", 1.0, 1)]))
            reg = tr.take([lg], log_dir=pathlib.Path(tmp) / "logs")
            self.assertEqual(reg.row("A").markers, 2)
            self.assertEqual(reg.row("A").failing, "real one")


# --- rule 5, added by #547 -----------------------------------------------------

DEVICE_LOST_LOG = """\
Godot Engine v4.8.dev.custom_build.3e530a3e9
Vulkan 1.4.341 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 5090
ERROR: Couldn't create Vulkan device (VkResult error -3).
   at: _initialize_device (drivers/vulkan/rendering_device_driver_vulkan.cpp:1503)
ERROR: Couldn't initialize Vulkan device. This may be caused by an incompatible or outdated graphics driver.
   at: initialize (drivers/vulkan/rendering_device_driver_vulkan.cpp:1862)
ERROR: Only local devices can submit and sync.
ERROR: Only local devices can submit and sync.
[PASS] Arena combat resolved - Team 1 won
"""

ENGINE_NEVER_STARTED_LOG = """\
Godot Engine v4.8.dev.custom_build.3e530a3e9
ERROR: Unable to create DisplayServer, all display drivers failed.
   at: setup2 (main/main.cpp:3733)
"""


class ADeviceThatNeverCameUpIsEvidenceNotAVerdict(unittest.TestCase):
    """Rule 5. Measured on the live #547 register run, not reasoned about first.

    `GPUArenaTest` on a box with 843 MiB of free VRAM: the engine's own display
    device came up, the TEST's local `RenderingDevice` did not, 5,698
    `Only local devices can submit and sync.` errors followed — not one compute
    dispatch reached the GPU — and the scene printed
    `[PASS] Arena combat resolved - Team 1 won` anyway. `tests/lib/verdict.sh`
    scored it PASS, correctly: the marker is what a verdict is read from, and
    re-reading the log to score would undo rules 7 and 9 (see rule 1).

    So the register does NOT rescore it. It carries the fact in an evidence
    column, because every other column on that row reads clean: 0 SCRIPT ERRORs,
    1 marker, no failing assertions. Without this column a GPU test whose GPU was
    never there is indistinguishable, in the artifact, from one that passed.

    This is #526's sibling and not #526. There the engine never started and the
    row scored NO_VERDICT — a false RED. Here the engine started, the test's own
    device did not, and the row scores PASS — a false GREEN.
    """

    def test_a_lost_device_is_counted_and_the_verdict_is_still_transcribed(self):
        with tempfile.TemporaryDirectory() as tmp:
            write(tmp, "logs/GPUArenaTest.log", DEVICE_LOST_LOG)
            lg = write(tmp, "run.log", run_log([("GPUArenaTest", "PASS", 25.4, 134)]))
            reg = tr.take([lg], log_dir=pathlib.Path(tmp) / "logs")
            row = reg.row("GPUArenaTest")
            self.assertEqual(row.verdict, "PASS")      # rule 1 is not touched
            self.assertEqual(row.device_lost, 1)
            self.assertEqual(row.script_errors, 0)     # every other column reads clean

    def test_an_engine_that_never_started_counts_too(self):
        """#526's shape. Different fact, same column: the run did not happen on a
        working device, whichever end of the startup it failed at."""
        with tempfile.TemporaryDirectory() as tmp:
            write(tmp, "logs/A.log", ENGINE_NEVER_STARTED_LOG)
            lg = write(tmp, "run.log", run_log([("A", "NO_VERDICT", 2.0, 1)]))
            reg = tr.take([lg], log_dir=pathlib.Path(tmp) / "logs")
            self.assertEqual(reg.row("A").device_lost, 1)

    def test_a_clean_log_is_zero_and_not_blank(self):
        """A blank cell reads as `not scanned`, which is what the stability
        column's whole existence is a warning about."""
        with tempfile.TemporaryDirectory() as tmp:
            write(tmp, "logs/A.log", "[PASS] one\n")
            lg = write(tmp, "run.log", run_log([("A", "PASS", 1.0, 0)]))
            reg = tr.take([lg], log_dir=pathlib.Path(tmp) / "logs")
            self.assertEqual(reg.row("A").device_lost, 0)

    def test_a_missing_log_is_unknown_rather_than_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            lg = write(tmp, "run.log", run_log([("A", "PASS", 1.0, 0)]))
            reg = tr.take([lg], log_dir=pathlib.Path(tmp) / "logs")
            self.assertIsNone(reg.row("A").device_lost)

    def test_every_repeats_log_dir_is_scanned_not_only_the_first(self):
        """The column has to pair with STABILITY, which is read across all
        repeats. A device lost in repeat 2 and not repeat 1 is exactly the
        contamination that manufactures a FLAKY row, so scanning only the first
        log dir would miss the case the column exists for."""
        with tempfile.TemporaryDirectory() as tmp:
            write(tmp, "l1/A.log", "[PASS] one\n")
            write(tmp, "l2/A.log", DEVICE_LOST_LOG)
            a = write(tmp, "a.log", run_log([("A", "FAIL", 1.0, 1)]))
            b = write(tmp, "b.log", run_log([("A", "PASS", 1.0, 0)]))
            reg = tr.take([a, b], log_dir=[pathlib.Path(tmp) / "l1",
                                           pathlib.Path(tmp) / "l2"])
            self.assertEqual(reg.row("A").device_lost, 1)
            self.assertTrue(tr.is_flaky(reg.row("A").stability))

    def test_the_header_names_the_count_and_how_many_log_dirs_it_scanned(self):
        """The stem here is deliberately unlikely-in-prose. A one-letter stem
        makes `assertIn(stem, env)` pass against the sentence around the list —
        the same defect as `assertIn("tools/harness_stamp.py", src)` matching the
        comment that names the tool (#454). Seeded: deleting `{named}` from the
        header leaves this green with `A`, red with this."""
        with tempfile.TemporaryDirectory() as tmp:
            write(tmp, "logs/GPUArenaTest.log", DEVICE_LOST_LOG)
            write(tmp, "logs/QuietTest.log", "[PASS] fine\n")
            lg = write(tmp, "run.log", run_log([("GPUArenaTest", "PASS", 1.0, 0),
                                                ("QuietTest", "PASS", 1.0, 0)]))
            reg = tr.take([lg], log_dir=pathlib.Path(tmp) / "logs")
            env = reg.header["environment"]
            self.assertIn("1 of 2", env)
            self.assertIn("GPUArenaTest(PASS", env)
            self.assertNotIn("QuietTest", env)

    def test_the_header_says_zero_out_loud_when_nothing_was_lost(self):
        with tempfile.TemporaryDirectory() as tmp:
            write(tmp, "logs/A.log", "[PASS] fine\n")
            lg = write(tmp, "run.log", run_log([("A", "PASS", 1.0, 0)]))
            reg = tr.take([lg], log_dir=pathlib.Path(tmp) / "logs")
            self.assertIn("0 of 1", reg.header["environment"])

    def test_the_column_round_trips(self):
        with tempfile.TemporaryDirectory() as tmp:
            write(tmp, "logs/A.log", DEVICE_LOST_LOG)
            lg = write(tmp, "run.log", run_log([("A", "PASS", 1.0, 0)]))
            reg = tr.take([lg], log_dir=pathlib.Path(tmp) / "logs")
            back = tr.parse_register(reg.render())
            self.assertEqual(back.row("A").device_lost, 1)

    def test_a_register_written_before_this_column_still_parses(self):
        """`diff` consumes the file, and #454's own artifacts in
        ~/fft-test-registers/454/ have ten columns, not eleven. A reader that
        crashed on them would make the instrument unable to read its own history."""
        old = ("# code_commit\tabc1234\n"
               "test\tverdict\tstability\tseconds\texit\tasserts_pass\t"
               "asserts_fail\tmarkers\tscript_errors\tfailing_assertions\n"
               "A\tPASS\tSTABLE×2\t1.00\t0\t3\t0\t3\t0\t-\n")
        back = tr.parse_register(old)
        self.assertEqual(back.row("A").verdict, "PASS")
        self.assertIsNone(back.row("A").device_lost)


class ADiffDoesNotCallAContaminatedRowAMover(unittest.TestCase):
    """The same refusal as UNCONFIRMED, on the environment axis.

    A verdict taken while the test's device was missing is not a statement about
    the commit, so a difference against it cannot be attributed to one. #453's
    lesson was that a flake reads as a mover; this is that lesson with the box
    as the cause instead of the test.
    """

    def _reg(self, sha, verdict, stability, device_lost):
        r = tr.Row("A", verdict, stability, 1.0, 0, 1, 0, 1, 0, "-", device_lost)
        return tr.Register({"code_commit": sha, "repeats": "2"}, [r])

    def test_a_differing_verdict_with_a_lost_device_is_environment_not_moved(self):
        a = self._reg("aaa", "PASS", "STABLE×2", 0)
        b = self._reg("bbb", "FAIL", "STABLE×2", 2)
        d = tr.classify("A", a.row("A"), b.row("A"))
        self.assertEqual(d.state, "ENVIRONMENT")

    def test_a_clean_pair_still_moves(self):
        a = self._reg("aaa", "PASS", "STABLE×2", 0)
        b = self._reg("bbb", "FAIL", "STABLE×2", 0)
        self.assertEqual(tr.classify("A", a.row("A"), b.row("A")).state, "MOVED")

    def test_agreement_is_still_same_even_with_a_lost_device(self):
        """The row is a lie on both sides, and that is the register's business,
        not the diff's — the diff answers `did this commit move it`."""
        a = self._reg("aaa", "PASS", "STABLE×2", 1)
        b = self._reg("bbb", "PASS", "STABLE×2", 1)
        self.assertEqual(tr.classify("A", a.row("A"), b.row("A")).state, "SAME")

    def test_an_old_register_with_no_column_is_not_environment(self):
        a = self._reg("aaa", "PASS", "STABLE×2", None)
        b = self._reg("bbb", "FAIL", "STABLE×2", None)
        self.assertEqual(tr.classify("A", a.row("A"), b.row("A")).state, "MOVED")
