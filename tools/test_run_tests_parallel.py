"""Tests for the parallel test runner (#453, map #450).

The deliverable of #453 is NOT "the suite runs in parallel". It is "parallel is
proven verdict-identical to sequential, and everything that is not runs
sequentially". These tests lock the parts of that which are mechanically
checkable without launching Godot:

  - the runner reads ONE test list, the same bash expansion every other
    instrument reads (`tools/_runner_tests.py`);
  - it reads ONE verdict, by SOURCING `tests/lib/verdict.sh` rather than
    restating its nine rules in Python;
  - the two places where a parallel runner would otherwise hold a private COPY
    of something `run_all_tests.sh` owns — the `-- --ci` argument set and the
    360 s timeout — are guarded against the runner's own text, so a copy cannot
    drift silently;
  - the summary block it prints is the block `freeze_test_baseline.py` parses;
  - the worker count is derived from free RAM, not from core count.

The last one is the ticket's headline: a test process is ~1 GB RSS and ~0.2 GB
VRAM on 24 cores, so cores are never the binding constraint and a runner that
picked `nproc` would thrash.
"""
import os
import pathlib
import re
import subprocess
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import run_tests_parallel as rtp

ROOT = pathlib.Path(__file__).resolve().parent.parent
RUNNER = ROOT / "tests" / "run_all_tests.sh"


class WorkerCountIsRamDerived(unittest.TestCase):
    """N comes from free RAM. Cores are not the constraint (#453)."""

    def test_ram_is_the_constraint_not_cores(self):
        # 24 cores, but only enough RAM for 4 processes.
        n = rtp.worker_count(avail_kb=6 * 1024 * 1024, cores=24)
        self.assertLessEqual(n, 5)

    def test_more_ram_buys_more_workers(self):
        few = rtp.worker_count(avail_kb=4 * 1024 * 1024, cores=24)
        many = rtp.worker_count(avail_kb=16 * 1024 * 1024, cores=24)
        self.assertGreater(many, few)

    def test_never_zero(self):
        self.assertGreaterEqual(rtp.worker_count(avail_kb=1, cores=24), 1)

    def test_never_exceeds_cores(self):
        # A box with 512 GB free and 2 cores gains nothing from 500 workers.
        self.assertLessEqual(rtp.worker_count(avail_kb=512 * 1024 * 1024, cores=2), 2)

    def test_reserves_headroom_for_everything_else(self):
        # The measured per-test peak is ~1.02 GB. With 10 GB available a runner
        # that ignored headroom would pick 9; it must leave the box some room.
        self.assertLessEqual(rtp.worker_count(avail_kb=10 * 1024 * 1024, cores=24), 8)

    def test_the_documented_ceiling_is_reachable(self):
        # The ticket's N=8 must be a value this function can actually return,
        # or the measured wall clock is against a number nobody adopts.
        self.assertEqual(rtp.worker_count(avail_kb=10 * 1024 * 1024, cores=24), 8)


class ReadsTheOneTestList(unittest.TestCase):
    """No second reading of the TESTS array — `_runner_tests.py` already owns it."""

    def test_list_is_the_runners_own_expansion(self):
        import _runner_tests
        self.assertEqual(rtp.test_list(), _runner_tests.runner_tests(RUNNER))

    def test_the_array_read_is_DELEGATED_not_copied(self):
        """Proved by substitution, not by grepping the source for `TESTS=(`.

        A text probe is the tempting form and it is the wrong one twice over: it
        false-positives on this module's own prose, and it would still pass if the
        delegation were dead code beside a private copy. Swapping the dependency
        out and watching the answer change is the only reading that cannot lie.
        """
        import _runner_tests
        real = _runner_tests.runner_tests
        _runner_tests.runner_tests = lambda *a, **k: ["SENTINEL"]
        try:
            self.assertEqual(rtp.test_list(), ["SENTINEL"])
        finally:
            _runner_tests.runner_tests = real


class ReadsTheOneVerdict(unittest.TestCase):
    """The verdict is SOURCED from tests/lib/verdict.sh, never restated."""

    def test_verdict_shells_out_to_the_reader(self):
        src = pathlib.Path(rtp.__file__).read_text()
        self.assertIn("tests/lib/verdict.sh", src)

    def test_does_not_restate_the_rules(self):
        src = pathlib.Path(rtp.__file__).read_text()
        # The rule bodies, not the outcome NAMES — the runner must name outcomes
        # to tally them, but it must not decide them.
        for probe in ("[VERDICT]", "TIMEOUT at tick", "EXPECT_ERRORS", "SCRIPT ERROR:"):
            self.assertNotIn(probe, src,
                             f"{probe!r} is a verdict.sh rule; reading it here forks the reader")

    def test_hung_comes_back_from_the_real_reader(self):
        log = ROOT / "tests" / "fixtures" / "verdict"
        any_log = next(iter(sorted(log.glob("*"))), None)
        self.assertIsNotNone(any_log, "verdict fixtures are missing")
        self.assertEqual(rtp.verdict(any_log, 124), "HUNG")


class DoesNotCopyWhatTheRunnerOwns(unittest.TestCase):
    """Guards, not declarations: the copies are checked against the original."""

    def test_ci_argument_set_matches_the_runner(self):
        src = RUNNER.read_text()
        # Both indices searched FORWARD from the block start (#417). `src.index`
        # from 0 finds the first `timeout 360` anywhere in the file, and the
        # TESTS array above is 2,000 lines of prose — a comment that merely
        # MENTIONS the wall clock silently emptied this slice and the assertion
        # below then failed on a set(), not on a real drift. Same class of bug as
        # the anchored-regex reading of the array that `_runner_tests` exists to
        # replace: a naive index over a file full of prose reads the prose.
        start = src.index("EXTRA_ARGS=()")
        block = src[start:src.index("TEST_TIMEOUT=360", start)]
        in_runner = set(re.findall(r'\$TEST"\s*=\s*"([A-Za-z0-9_]+)"', block))
        self.assertTrue(in_runner, "could not read the runner's EXTRA_ARGS special cases")
        self.assertEqual(set(rtp.CI_ARG_TESTS), in_runner)

    def test_timeout_matches_the_runner(self):
        src = RUNNER.read_text()
        m = re.search(r'^\s*TEST_TIMEOUT=(\d+)\s*$', src, re.M)
        self.assertIsNotNone(m, "could not read the runner's default per-test timeout")
        self.assertEqual(rtp.TIMEOUT_S, int(m.group(1)))
        self.assertIn('timeout "$TEST_TIMEOUT" "$GODOT" --path . "$SCENE"', src,
                      "the runner no longer wraps the child in its own per-test timeout")

    def test_timeout_raises_match_the_runner(self):
        """The raise table is a SECOND copy, so it gets the same treatment as the
        first. A per-test wall clock that is 1200 s in one arm and 360 s in the
        other scores the same test PASS here and HUNG there — the exact drift
        this class exists to make impossible (#709)."""
        src = RUNNER.read_text()
        in_runner = {name: int(secs) for name, secs in
                     re.findall(r'^\s*([A-Za-z0-9_]+)\)\s*TEST_TIMEOUT=(\d+)\s*;;',
                                src, re.M)}
        self.assertEqual(rtp.TIMEOUT_OVERRIDES, in_runner)
        for name, secs in in_runner.items():
            self.assertGreater(secs, rtp.TIMEOUT_S,
                               f"{name} is in the RAISE table but does not raise anything")

    def test_hung_exit_code_matches_the_runner(self):
        # `timeout` reports 124; verdict.sh keys HUNG off exactly that.
        self.assertEqual(rtp.TIMEOUT_EXIT, 124)


class SummaryIsTheParsedBlock(unittest.TestCase):
    """freeze_test_baseline.py parses `[i/n] Running X...` + `  -> RESULT`."""

    RESULTS = [("A", "PASS"), ("B", "FAIL"), ("C", "NOT_A_TEST"), ("D", "THREW")]

    def test_per_test_lines_are_what_the_register_parses(self):
        out = rtp.format_progress(1, 4, "A", "PASS")
        self.assertIn("[1/4] Running A...", out)
        self.assertIn("\n  -> PASS", out)

    def test_verdicts_parse_back_out_of_the_summary(self):
        import _runner_tests  # noqa: F401  (keeps the tools dir on the path)
        sys.path.insert(0, str(ROOT / "tools"))
        import freeze_test_baseline as fz
        text = "".join(rtp.format_progress(i + 1, 4, s, v) + "\n"
                       for i, (s, v) in enumerate(self.RESULTS))
        tmp = ROOT / "tools" / ".rtp_summary_probe.log"
        tmp.write_text(text)
        try:
            self.assertEqual(fz.verdicts(tmp), dict(self.RESULTS))
        finally:
            tmp.unlink()

    def test_not_a_test_is_out_of_the_denominator(self):
        block = rtp.format_summary(self.RESULTS)
        self.assertIn("PASSED:     1 / 3", block)

    def test_every_outcome_gets_its_own_line(self):
        block = rtp.format_summary(self.RESULTS)
        for name in ("PASSED", "FAILED", "THREW", "TIMEOUT", "HUNG",
                     "CRASHED", "NOT_A_TEST", "NO_VERDICT"):
            self.assertIn(name + ":", block)


class SequentialLaneIsNamedAndReasoned(unittest.TestCase):
    """#453: anything that moves under parallelism runs alone, WITH a reason."""

    def test_lane_entries_carry_a_reason(self):
        for stem, reason in rtp.SEQUENTIAL_LANE.items():
            self.assertTrue(reason and len(reason) > 20,
                            f"{stem} is in the sequential lane without a reason")

    def test_lane_members_are_real_tests(self):
        listed = set(rtp.test_list())
        for stem in rtp.SEQUENTIAL_LANE:
            self.assertIn(stem, listed, f"{stem} is laned but the runner does not list it")

    def test_lane_is_excluded_from_the_parallel_phase(self):
        par, seq = rtp.partition(["A", "B", "C"], lane={"B": "because"})
        self.assertEqual(par, ["A", "C"])
        self.assertEqual(seq, ["B"])

    def test_partition_preserves_the_arrays_order(self):
        par, seq = rtp.partition(["C", "A", "B"], lane={})
        self.assertEqual(par, ["C", "A", "B"])


class LogsDoNotCollideBetweenArms(unittest.TestCase):
    """A parallel arm must not clobber the sequential arm's logs — the diff
    needs both, and a verdict is only comparable to one from the SAME run."""

    def test_log_dir_is_configurable(self):
        p = rtp.log_path("Foo", pathlib.Path("/tmp/somewhere"))
        self.assertEqual(p, pathlib.Path("/tmp/somewhere/Foo.log"))

    def test_default_log_dir_is_the_runners(self):
        self.assertEqual(rtp.DEFAULT_LOG_DIR, ROOT / "tests" / "logs")


class ExitCodesMeanTheSameThingInBothArms(unittest.TestCase):
    """The single most dangerous way these two arms could differ.

    `run_all_tests.sh` wraps every test in `timeout 360` and reads
    `${PIPESTATUS[0]}`, so a segfaulting child arrives at verdict.sh as 139 and
    a hang as 124 — which is exactly what its CRASHED (`exit >= 128`) and HUNG
    (`exit == 124`) rules are written against.

    A Python runner that called `Popen.wait()` would hand the same segfault to
    the same reader as **-11**, `[ -11 -ge 128 ]` is false, and every crash in
    the parallel arm would silently score NO_VERDICT instead of CRASHED. 64 test
    names dump core in every archived run (#471), so that is ~64 rows per run
    scored by a different rule than the sequential arm scores them by — a
    verdict-identity proof invalidated by its own instrument.

    Delegating to `timeout(1)` is what makes them identical, and it also puts
    `timeout: the monitored command dumped core` in the log, which is the string
    `replay.py` reconstructs the exit code from when the run is archived.
    """

    def test_the_child_is_wrapped_in_timeout(self):
        cmd = rtp.command_for("Foo", ROOT)
        self.assertEqual(cmd[:3], ["timeout", str(rtp.TIMEOUT_S), rtp.godot()])

    def test_a_raised_test_is_wrapped_in_its_own_timeout(self):
        # Direction: the table must reach the spawned command, not just exist.
        for name, secs in rtp.TIMEOUT_OVERRIDES.items():
            cmd = rtp.command_for(name, ROOT)
            self.assertEqual(cmd[:3], ["timeout", str(secs), rtp.godot()])

    def test_a_signal_death_arrives_as_128_plus_signo(self):
        code = rtp.run_capture(["bash", "-c", "kill -SEGV $$"], pathlib.Path("/dev/null"))
        self.assertGreaterEqual(code, 128)
        self.assertEqual(code, 139)

    def test_a_crash_scores_CRASHED_through_the_real_reader(self):
        log = ROOT / "tools" / ".rtp_crash_probe.log"
        log.write_text("some engine noise and no marker at all\n")
        try:
            self.assertEqual(rtp.verdict(log, 139), "CRASHED")
        finally:
            log.unlink()

    def test_timeout_wrapping_yields_124_not_a_python_substitute(self):
        code = rtp.run_capture(["timeout", "1", "sleep", "5"], pathlib.Path("/dev/null"))
        self.assertEqual(code, rtp.TIMEOUT_EXIT)


class DoesNotBatch(unittest.TestCase):
    """#430: the gambit runner batches and Vulkan local-device creation fails 54
    of 82 times inside that one process. Parallel means N processes, not fewer."""

    def test_one_process_per_test(self):
        cmd = rtp.command_for("Foo", ROOT)
        scenes = [a for a in cmd if a.startswith("res://tests/")]
        self.assertEqual(scenes, ["res://tests/Foo.tscn"])

    def test_never_headless(self):
        # CLAUDE.md: headful only. The 4.8 fork's engine-fold compositor
        # self-disables otherwise and every folded effect silently vanishes.
        self.assertNotIn("--headless", rtp.command_for("Foo", ROOT))

    def test_ci_tests_get_their_flag(self):
        cmd = rtp.command_for(sorted(rtp.CI_ARG_TESTS)[0], ROOT)
        self.assertIn("--ci", cmd)

    def test_never_headless_even_under_the_timeout_wrapper(self):
        for stem in ("Foo",) + rtp.CI_ARG_TESTS:
            self.assertNotIn("--headless", rtp.command_for(stem, ROOT))



class AdaptivePoolSizingTest(unittest.TestCase):
    """The pool re-sizes as it runs — `additional_fits` and `target_inflight`.

    Sizing once is what made a 711-test run sit at 8 workers for 18 minutes on a
    24-core box: a neighbour held 10 GB at second zero and the run never noticed
    it leave. These are the two functions that let it notice.
    """

    GB = 1024 * 1024          # in the kB units /proc/meminfo reports
    RESERVE = 2 * 1024 * 1024

    def test_additional_fits_can_say_zero_and_worker_count_cannot(self):
        # THE WHOLE DIFFERENCE between the two, and the reason there are two.
        # `worker_count` floors at 1 because a run with no workers is not a run;
        # `additional_fits` is asked while workers already exist, so "no room for
        # another" has to be sayable or the pool can only ever grow.
        tight = self.RESERVE + 100          # 100 kB of headroom: room for nobody
        self.assertEqual(rtp.additional_fits(tight), 0)
        self.assertEqual(rtp.worker_count(tight, cores=24), 1)

    def test_additional_fits_is_headroom_over_the_reserve(self):
        self.assertEqual(rtp.additional_fits(self.RESERVE + 5 * self.GB), 5)
        self.assertEqual(rtp.additional_fits(self.RESERVE), 0)
        # Below the reserve is not negative — the reserve is a floor, not a debt.
        self.assertEqual(rtp.additional_fits(self.RESERVE // 2), 0)

    def test_target_grows_when_a_neighbour_leaves(self):
        # 8 running, box was tight (room for nobody else): stay at 8.
        self.assertEqual(
            rtp.target_inflight(8, avail_kb=self.RESERVE + 100, cores=24), 8)
        # The neighbour exits and frees 10 GB: the same 8 workers may now open up.
        self.assertEqual(
            rtp.target_inflight(8, avail_kb=self.RESERVE + 10 * self.GB, cores=24), 18)

    def test_target_leaves_the_box_some_cores(self):
        # 🔴 200 GB free does not buy every core. The pool grew to 24 of 24 once and a
        # 713-test run went 3 non-PASS -> 14; all twelve new ones passed on re-run, so
        # none was real and each cost a re-run to disprove. The RAM model says how many
        # processes FIT; CORE_HEADROOM says how many should RUN.
        self.assertEqual(
            rtp.target_inflight(4, avail_kb=self.RESERVE + 200 * self.GB, cores=24),
            24 - rtp.CORE_HEADROOM)
        self.assertGreaterEqual(rtp.CORE_HEADROOM, 1,
                                "a headroom of 0 is the regime this constant exists to leave")

    def test_core_ceiling_is_pinned_against_literals(self):
        # `core_ceiling` is now the single definition three call sites share, so it
        # needs an oracle that does NOT call it: every other assertion in this file
        # would move with it. Literals, computed by hand at CORE_HEADROOM = 2.
        self.assertEqual(rtp.CORE_HEADROOM, 2,
                         "the literals below were computed at a headroom of 2")
        for cores, expected in ((24, 22), (8, 6), (3, 1), (2, 1), (1, 1)):
            with self.subTest(cores=cores):
                self.assertEqual(rtp.core_ceiling(cores), expected)

    def test_headroom_never_starves_a_small_box(self):
        # On 1 and 2 cores the headroom would take the pool to zero or below.
        for cores in (1, 2, 3):
            self.assertGreaterEqual(
                rtp.target_inflight(0, avail_kb=self.RESERVE + 200 * self.GB, cores=cores), 1)
            self.assertGreaterEqual(rtp.worker_count(self.RESERVE + 200 * self.GB, cores), 1)

    def test_target_never_starves(self):
        # Nothing running and no headroom at all still yields one worker, or the
        # run cannot make progress and the scheduler spins.
        self.assertEqual(rtp.target_inflight(0, avail_kb=0, cores=24), 1)

    def test_target_does_not_run_away_as_workers_are_added(self):
        # MemAvailable already counts a running worker's pages as taken, so asking
        # repeatedly converges. Simulated: each launch consumes PER_TEST_KB.
        cores, avail = 24, self.RESERVE + 6 * self.GB
        running = 0
        for _ in range(50):
            target = rtp.target_inflight(running, avail_kb=avail, cores=cores)
            if running >= target:
                break
            running += 1
            avail -= rtp.PER_TEST_KB
        self.assertEqual(running, 6, "converged on the headroom it actually had")

if __name__ == "__main__":
    unittest.main()


class EveryRunStampsItsTree(unittest.TestCase):
    """#453 §5.1. A suite run's stdout IS the archive, and not one of the five
    archived runs records the tree it measured — so "were these two runs the same
    code?" is unanswerable about every one of them. That is the provenance error
    map #450 keeps punishing, and it costs one `rev-parse` to end.

    Guarded in BOTH arms, against each runner's own text, for the same reason the
    `-- --ci` set and the 360 s timeout are: two runners feed one register, and a
    stamp that exists in only one of them leaves half the corpus unattributable.

    The DIRTY marker is not a nicety. A run against a modified tree is not a run
    against that SHA, and a stamp that cannot say so is a stamp that lies on
    exactly the runs most likely to be mid-investigation.
    """

    def test_the_parallel_runner_emits_a_code_commit_line(self):
        line = rtp.provenance_line(sha="abc1234", dirty=False, godot="4.8.dev.custom_build")
        self.assertIn("code_commit", line)
        self.assertIn("abc1234", line)

    def test_a_dirty_tree_says_so_in_the_stamp(self):
        clean = rtp.provenance_line(sha="abc1234", dirty=False, godot="g")
        dirty = rtp.provenance_line(sha="abc1234", dirty=True, godot="g")
        self.assertNotIn("DIRTY", clean)
        self.assertIn("WORKING TREE DIRTY at capture", dirty)

    def test_the_dirty_wording_matches_the_frozen_registers(self):
        # `freeze_test_baseline.py` already writes this exact phrase into the TSV's
        # `code_commit` header. Two spellings of one fact is how a corpus stops
        # being greppable.
        freeze = (ROOT / "tools" / "freeze_test_baseline.py").read_text()
        self.assertIn("(WORKING TREE DIRTY at capture)", freeze)
        self.assertIn("(WORKING TREE DIRTY at capture)",
                      rtp.provenance_line(sha="s", dirty=True, godot="g"))

    def test_the_stamp_records_the_engine_too(self):
        # The 4.8 fork vs stock 4.7 is the other axis that makes two runs
        # incomparable — CLAUDE.md's standing warning. Same line, same cost.
        self.assertIn("4.8.dev.custom_build",
                      rtp.provenance_line(sha="s", dirty=False, godot="4.8.dev.custom_build"))

    def test_the_sequential_runner_stamps_too(self):
        text = RUNNER.read_text()
        self.assertIn("rev-parse HEAD", text)
        self.assertIn("code_commit", text)
        self.assertIn("WORKING TREE DIRTY at capture", text)

    def test_the_stamp_cannot_be_read_as_a_verdict(self):
        # §5.2's latent hazard: `freeze_test_baseline.verdicts()` takes the FIRST
        # `^  -> (\w+)$` after a `Running X` header as that test's verdict. A banner
        # line that matched would silently become a verdict. It must not.
        verdict_re = re.compile(r'^  -> (\w+)$')
        for line in rtp.provenance_line(sha="s", dirty=True, godot="g").splitlines():
            self.assertIsNone(verdict_re.match(line), line)


class SequentialArmIsGated(unittest.TestCase):
    """The slow arm refuses to run unless it is asked for by name.

    ADR-0158 measured 61 min sequential against 10.4 parallel and adopted the fast
    one — and then everybody kept running the slow one anyway, because handoffs quote
    `run_all_tests.sh` and its wall clock. One session spent ~150 minutes on three
    sequential passes before noticing. A number in a docstring does not change
    behaviour; a non-zero exit does.

    BEHAVIOURAL, not a grep over the source. A source assertion can match the prose
    beside the rule it is guarding and stay green after the rule is deleted, which
    this repo has already been bitten by. These actually invoke the runner. The cost
    is the pre-flight block (no Godot), which is the point: that block still has to run
    for the gate to be reached.

    🔴 THAT COST SAID "~6 s" AND IT IS **342 s** — measured 2026-09-03, and it had
    already drifted past the subprocess cap, so BOTH arms below were failing with
    `TimeoutExpired` at 300 s while `--preflight-only` itself exited 0. A timeout is not
    a verdict about the gate; it says nothing at all about whether the slow arm is still
    refused, and it aborts the whole pre-flight on its way past. The cap is raised with
    headroom rather than pinned near the measurement, because these two arms are the only
    ones in the tree that pay the block TWICE inside a run that is itself the block.
    ⚠️ The stale number is the finding, not the cap: two arms costing ~680 s
    between them to assert a gate is a real price, and nothing here reduces it.
    """

    @staticmethod
    def _run(*args):
        """Invoke the runner with the nesting flag set.

        Without it this is a fork bomb in slow motion: the runner's pre-flight runs
        THIS module, which runs the runner. FFT_SUITE_NESTED makes the inner level skip
        that one guard and nothing else.
        """
        env = dict(os.environ, FFT_SUITE_NESTED="1")
        # 900, not 300: the block it drives measured 342 s on 2026-09-03 (see the class
        # docstring). Still bounded — the cap is here to catch a HANG, and a hang looks
        # nothing like 342 s.
        return subprocess.run(["bash", str(RUNNER), *args], cwd=ROOT, env=env,
                              capture_output=True, text=True, timeout=900)

    def _skip_if_preflight_aborted(self, out):
        """🔴 A TEST WHOSE SUBJECT WAS NEVER REACHED MUST SKIP, NOT FAIL (#823).

        Both arms below assert on text the runner prints AT THE GATE, and every one of
        the ~50 static guards runs before it and `exit 1`s. So any aborting guard failed
        them — with a message describing a defect in the gate rather than in the guard
        that actually broke. Measured: four misreads in one evening across two sessions
        (`check_context_index`, `check_lattice_ports`, `check_adr_classification` twice),
        each reported as `FAILED (failures=2)` where one failure was a phantom.

        ⚠️ NOT A WEAKENING OF THE ASSERTIONS, and #823 says so in those words. ADR-0158
        exists because everybody ran the slow arm anyway; the gate is real and its wording
        matters. The subject is correct — the defect was reporting on a subject the run
        never reached.

        Keyed on the SENTINEL, not on `returncode`: the no-arguments arm EXPECTS a
        non-zero rc, so the rc cannot tell the two states apart. And a run that reached
        neither the sentinel nor an `ABORT:` line FAILS here rather than skipping — a
        skip that can fire on any unexplained exit is how a silenced arm stays silent."""
        if rtp.PREFLIGHT_PASSED in out.stdout:
            return
        named = rtp.preflight_abort_line(out.stdout)
        self.assertIsNotNone(
            named,
            "the pre-flight neither reached the gate nor printed an `ABORT:` line, so it "
            "died some other way and this arm cannot say anything about the gate:\n"
            + out.stdout[-2000:])
        self.skipTest("a pre-flight guard aborted before the gate was reached — %s" % named)

    def test_no_arguments_refuses_and_names_the_fast_runner(self):
        out = self._run()
        self._skip_if_preflight_aborted(out)
        self.assertNotEqual(out.returncode, 0,
                            "the sequential arm ran with no arguments — the gate is gone")
        self.assertIn("run_tests_parallel.py", out.stdout,
                      "the refusal must name the command the caller actually wanted")
        self.assertNotIn("Rebuilding Godot import cache", out.stdout,
                         "the gate must stop BEFORE any Godot work")

    def test_preflight_only_runs_the_guards_and_stops(self):
        out = self._run("--preflight-only")
        self._skip_if_preflight_aborted(out)
        self.assertEqual(out.returncode, 0, out.stdout[-2000:])
        self.assertIn("every static guard above passed", out.stdout)
        self.assertNotIn("Rebuilding Godot import cache", out.stdout)
    def test_the_parallel_runner_runs_those_guards_itself(self):
        # Otherwise gating the sequential arm would silently retire ~25 static
        # guards — #565's finding (a guard registered nowhere) by another route.
        src = (ROOT / "tools" / "run_tests_parallel.py").read_text()
        self.assertIn("--preflight-only", src)
        self.assertIn("def preflight(", src)


class TheParallelArmRebuildsTheClassCache(unittest.TestCase):
    """The other half of what the sequential arm does above its test loop.

    🔴 THE GUARDS CAME ACROSS ON `--preflight-only` AND THE IMPORT DID NOT, because the
    import sits BELOW that flag's exit. So this runner — the sanctioned one — never
    rebuilt the cache, and a merge that added a `class_name` named by an autoload scored
    6 PASSED of 770 with 694 THREW: one cold cache, 13.8 minutes, reading as a total
    regression (#1094's merge, 2026-09-10).

    ⚠️ THE FIX MAY NOT BE "MOVE IT ABOVE THE EXIT". Two arms of `SequentialArmIsGated`
    assert `assertNotIn("Rebuilding Godot import cache")` on exactly those two paths —
    *"the gate must stop BEFORE any Godot work"* — so that edit trades this defect for
    theirs. The import is test-loop setup, not a guard, and each arm carries its own.

    Behavioural, not a grep: a source assertion here would match this very docstring."""

    def test_the_importer_is_invoked_with_import_on_this_project(self):
        seen = []
        real = rtp.subprocess.run
        rtp.subprocess.run = lambda *a, **k: seen.append(a[0]) or real(["true"])
        try:
            rtp.rebuild_class_cache()
        finally:
            rtp.subprocess.run = real
        self.assertEqual(len(seen), 1, "rebuild_class_cache ran no subprocess")
        self.assertIn("--import", seen[0])
        self.assertIn(str(ROOT), seen[0])

    def test_main_rebuilds_before_it_reaches_the_pool(self):
        """Wired, not merely defined — the whole defect was a call site out of reach.

        `--tests` with an unknown name exits inside `main` AFTER the rebuild and BEFORE
        any worker, so this reaches the call site without launching Godot."""
        called = []
        real = rtp.rebuild_class_cache
        rtp.rebuild_class_cache = lambda: called.append(True)
        try:
            with self.assertRaises(SystemExit):
                rtp.main(["--no-preflight", "--tests", "NoSuchTestNameXYZ"])
        finally:
            rtp.rebuild_class_cache = real
        self.assertEqual(called, [True],
                         "main() reached the test list without rebuilding the cache")


class ThePreflightVerdictIsReadableWithoutRunningIt(unittest.TestCase):
    """`preflight_abort_line()`, graded on CONSTRUCTED stdout.

    🔴 THE SKIP HELPER IS ITSELF AN ARM THAT CAN GO VACUOUS. A helper that matched
    nothing puts the phantom failures back; one that matched everything makes the gate's
    two arms skip forever, which is worse — a silenced arm looks exactly like a passing
    one. Neither state is reachable through the arms it protects, because reaching them
    costs ~680 s and a deliberately broken guard. So the predicate is pure and tested
    here, at no cost, in both directions."""

    def test_a_green_preflight_reads_as_NOT_aborted(self):
        self.assertIsNone(rtp.preflight_abort_line(
            "check_foo: OK\n%s\n--preflight-only: …\n" % rtp.PREFLIGHT_PASSED))

    def test_an_aborting_guard_is_NAMED(self):
        out = ("check_foo: OK\n"
               "ABORT: the lattice register is broken. Fix it.\n")
        self.assertEqual(rtp.preflight_abort_line(out),
                         "ABORT: the lattice register is broken. Fix it.")

    def test_the_SENTINEL_WINS_over_the_word_ABORT_in_a_guards_own_output(self):
        """A guard that PASSES while printing the word — every guard here quotes its own
        failure text in its help — must not make a green pre-flight read as broken."""
        self.assertIsNone(rtp.preflight_abort_line(
            "check_foo: OK — on failure it prints\nABORT: something\n%s\n"
            % rtp.PREFLIGHT_PASSED))

    def test_neither_sentinel_nor_ABORT_is_a_THIRD_state_and_reads_as_None(self):
        """Distinct from `green`: the caller must be able to tell "the pre-flight passed"
        from "the pre-flight vanished". `_skip_if_preflight_aborted` FAILS on this one
        rather than skipping."""
        self.assertIsNone(rtp.preflight_abort_line("bash: run_all_tests.sh: not found\n"))

    def test_the_LAST_abort_wins(self):
        self.assertEqual(
            rtp.preflight_abort_line("ABORT: first\nnoise\nABORT: second\n"),
            "ABORT: second")

    def test_the_sentinel_is_the_STRING_the_runner_actually_prints(self):
        """The two halves of #823 live in two files and a copied literal drifts. This
        reads the shell script."""
        src = (ROOT / "tests" / "run_all_tests.sh").read_text(encoding="utf-8")
        self.assertIn('echo "%s"' % rtp.PREFLIGHT_PASSED, src)


class TheDesktopKeepsItsPagesTest(unittest.TestCase):
    """The pool's SECOND ceiling — what it holds, not what the box has left.

    🔴 THE DEFECT THIS EXISTS FOR. `additional_fits()` reads `MemAvailable`,
    which is free pages plus reclaimable page CACHE and does not count anon
    pages the kernel has already evicted to swap. So the pool can satisfy
    "2 GB is still available" indefinitely *by causing* the compositor's heap
    to be swapped out, and read its own damage as room to grow. Measured
    mid-run on 2026-09-10: MemAvailable held 6–8 GB for a 40 s sample — the
    reserve never binding — while `Hyprland` sat at 172 MB resident against
    240 MB swapped and every terminal was likewise more out than in. The box
    could not be typed on; `/proc/pressure/cpu` read `full avg10=0.00`
    throughout, so it was never the cores.

    A ceiling measured on the POOL'S OWN PROCESSES is the one number nothing
    else on the box can inflate.
    """

    GB = 1024 * 1024          # in the kB units /proc/meminfo reports
    RESERVE = 2 * 1024 * 1024

    def test_the_budget_binds_when_free_ram_says_go(self):
        # 200 GB "available" and 24 cores — the RAM model alone would say 22.
        # The pool is already holding its whole 8 GB budget, so the answer is
        # "no more", and it is the budget that says so.
        self.assertEqual(
            rtp.target_inflight(6, avail_kb=self.RESERVE + 200 * self.GB, cores=24),
            22)
        self.assertEqual(
            rtp.target_inflight(6, avail_kb=self.RESERVE + 200 * self.GB, cores=24,
                                budget_kb=8 * self.GB, used_kb=8 * self.GB),
            6)

    def test_no_budget_is_the_old_model_exactly(self):
        """`budget_kb=None` must not quietly become a live measurement — the RAM
        model has its own tests above and they must still be reading it."""
        for used in (0, 4 * self.GB, 40 * self.GB):
            self.assertEqual(
                rtp.target_inflight(6, avail_kb=self.RESERVE + 200 * self.GB,
                                    cores=24, budget_kb=None, used_kb=used), 22)

    def test_budget_fits_can_say_zero_and_never_goes_negative(self):
        self.assertEqual(rtp.budget_fits(8 * self.GB, 3 * self.GB), 5)
        self.assertEqual(rtp.budget_fits(8 * self.GB, 8 * self.GB), 0)
        # Over budget is not a debt the next slot has to repay.
        self.assertEqual(rtp.budget_fits(8 * self.GB, 40 * self.GB), 0)

    def test_the_budget_never_starves_the_run_to_nothing(self):
        # Same floor as `worker_count()`: a run with no workers is not a run,
        # so an over-budget pool still gets told 1 rather than 0.
        self.assertEqual(
            rtp.target_inflight(0, avail_kb=self.RESERVE + 200 * self.GB, cores=24,
                                budget_kb=8 * self.GB, used_kb=99 * self.GB), 1)

    def test_the_default_budget_leaves_a_small_box_its_floor(self):
        # 12 GB box: 8 GB would be two thirds of it. The floor wins.
        self.assertEqual(rtp.default_budget_kb(12 * self.GB), 4 * self.GB)
        # 30 GB box (the measured one): the constant wins.
        self.assertEqual(rtp.default_budget_kb(30 * self.GB), rtp.SUITE_RSS_BUDGET_KB)
        # And it never goes below one test, however small the box claims to be.
        self.assertEqual(rtp.default_budget_kb(1 * self.GB), rtp.PER_TEST_KB)
        self.assertGreaterEqual(rtp.budget_fits(rtp.default_budget_kb(1 * self.GB), 0), 1)

    def test_the_pool_converges_under_the_budget_instead_of_running_away(self):
        """The runaway, simulated: free RAM stays constant — which is what the
        kernel arranges by evicting somebody else — and only the pool's own RSS
        moves. Without the budget this loop reaches `core_ceiling`; with it, it
        stops at the budget."""
        avail = self.RESERVE + 200 * self.GB
        used, running, launches = 0, 0, 0
        while launches < 100:
            target = rtp.target_inflight(running, avail_kb=avail, cores=24,
                                         budget_kb=8 * self.GB, used_kb=used)
            if running >= target:
                break
            running += 1
            launches += 1
            used += rtp.PER_TEST_KB       # each worker takes its measured peak
        self.assertLess(running, rtp.core_ceiling(24))
        self.assertLessEqual(used, 8 * self.GB)

    def test_memory_high_is_slack_behind_the_cap_not_level_with_it(self):
        """A `MemoryHigh` at the cap would turn every scheduling wobble into
        kernel reclaim inside a live worker. The cap has to bind first."""
        cmd = rtp.scope_cmd(8 * self.GB, ["true"], "unit-under-test")
        high = int(next(a for a in cmd if a.startswith("MemoryHigh=")).split("=")[1])
        self.assertGreater(high, 8 * self.GB * 1024)
        self.assertGreaterEqual(rtp.MEMORY_HIGH_SLACK_KB, rtp.PER_TEST_KB)

    def test_the_scope_is_a_user_scope_and_collects_itself(self):
        # `--user`: a system scope would need root and would not sit beside the
        # graphical slice the desktop guard protects. `--collect`: a scope left
        # by a killed run must not block the next one on a name clash.
        cmd = rtp.scope_cmd(8 * self.GB, ["true"], "unit-under-test")
        for flag in ("--user", "--scope", "--collect", "--unit=unit-under-test"):
            self.assertIn(flag, cmd)
        self.assertEqual(cmd[cmd.index("--") + 1:], ["true"])


class SuiteRssIsMeasuredNotAssumedTest(unittest.TestCase):
    """`proc_rss_table` / `descendant_rss_kb` — the reading the budget is made of."""

    def _fake_proc(self, rows):
        """rows: {pid: (ppid, comm, rss_pages)} written as a /proc tree."""
        import tempfile
        root = pathlib.Path(tempfile.mkdtemp())
        for pid, (ppid, comm, pages) in rows.items():
            d = root / str(pid)
            d.mkdir()
            (d / "stat").write_text("%d (%s) S %d 0 0 0 0 0 0\n" % (pid, comm, ppid))
            (d / "statm").write_text("9999 %d 0 0 0 0 0\n" % pages)
        (root / "self").mkdir()          # a non-numeric entry must be skipped
        return root

    def test_a_comm_with_spaces_and_parens_does_not_move_the_ppid_field(self):
        """`/proc/PID/stat` field indices are only stable after the LAST `)`, and
        Godot is not the only thing on this box with a punctuated `comm`."""
        root = self._fake_proc({7: (3, "we (ird) name", 4)})
        table = rtp.proc_rss_table(str(root))
        page_kb = os.sysconf("SC_PAGE_SIZE") // 1024
        self.assertEqual(table[7], (3, 4 * page_kb))

    def test_the_runners_own_pages_are_not_in_the_budget(self):
        """The budget is about the WORKERS. Counting the interpreter would make
        the same number mean two things depending on whether the caller went
        through `uv run`."""
        # 1 = runner, 2/3 = `timeout` wrappers, 4/5 = godot under them.
        table = {1: (0, 1000), 2: (1, 10), 3: (1, 10), 4: (2, 500), 5: (3, 500)}
        self.assertEqual(rtp.descendant_rss_kb(1, table), 1020)
        # 1020, not 2020: the runner's own 1000 kB is outside the budget.
        self.assertNotEqual(rtp.descendant_rss_kb(1, table), 2020)

    def test_grandchildren_are_counted_because_godot_is_one(self):
        # `run_one` launches `timeout ... godot ...`, so every byte that matters
        # is a GRANDCHILD of the runner. A one-level sum would read ~0.
        table = {1: (0, 0), 2: (1, 1), 3: (2, 900)}
        self.assertEqual(rtp.descendant_rss_kb(1, table), 901)

    def test_a_process_that_exits_mid_read_is_skipped_not_raised(self):
        """During a suite run tests are exiting constantly. A reading that
        raised on the normal case is a reading nobody can take."""
        root = self._fake_proc({7: (1, "alive", 4), 8: (1, "gone", 4)})
        import shutil as _sh
        _sh.rmtree(root / "8")
        table = rtp.proc_rss_table(str(root))
        self.assertIn(7, table)
        self.assertNotIn(8, table)

    def test_a_missing_proc_is_zero_rather_than_a_crashed_run(self):
        self.assertEqual(rtp.proc_rss_table("/nonexistent-proc"), {})
