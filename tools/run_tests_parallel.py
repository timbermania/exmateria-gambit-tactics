#!/usr/bin/env python3
"""Run `tests/run_all_tests.sh`'s test list in N processes instead of one — #453.

    uv run python tools/run_tests_parallel.py                 # N from free RAM
    uv run python tools/run_tests_parallel.py -N 8 --log-dir /tmp/par-1
    uv run python tools/run_tests_parallel.py --jsonl /tmp/par-1.jsonl

WHAT THIS IS FOR, AND WHAT IT IS NOT. The suite takes ~44 minutes and about half
of that is Godot booting, once per test, 412 times. No amount of making an
individual test quicker touches that. But a fast unreliable suite is worse than a
slow reliable one, because the entire point of map #450 is an instrument you can
believe — so this runner is only adoptable once its verdicts are PROVEN identical
to the sequential runner's, and everything that is not identical is named in
`SEQUENTIAL_LANE` below with the reason it is there.

`docs/TEST-BASELINE-E2.tsv`'s header records `sequential, never parallel` as a
property of the instrument, not a preference. This file does not change that
frozen register; it is a second arm to diff against it.

THREE THINGS THIS RUNNER DOES NOT OWN, AND DELIBERATELY CANNOT DRIFT FROM:

  - THE TEST LIST. `_runner_tests.runner_tests()` slices the `TESTS=(` array out
    of the runner and asks BASH to expand it. That module's docstring records why
    a regex reading returns 437 names instead of 410. One reading, already built.
  - THE VERDICT. `tests/lib/verdict.sh` is SOURCED per test, in a subshell, the
    same nine rules `run_all_tests.sh` scores with. Restating them in Python would
    put two rules in one register with nothing saying which row came from which —
    the exact failure that file exists to prevent.
  - THE `-- --ci` SET AND THE TIMEOUT. Those two live in the runner's loop body
    and there is no way to source them, so they are copied here — and
    `test_run_tests_parallel.py` reads them back out of `run_all_tests.sh` and
    compares. A guard, not a comment.

WHY NOT BATCH CHEAP TESTS INTO SHARED PROCESSES. It is the obvious answer to a
~3.5 s startup floor and this codebase has already run the experiment: the gambit
runner batches, and Vulkan local-device creation fails 54 of 82 times inside that
one process, emitting 43,492 device errors under a green suite (#430). Process
isolation is buying real protection. Parallel here means N processes, never fewer.

WHY N IS DERIVED FROM RAM. Measured on this box while the sequential arm ran: 24
cores, per-test peak RSS ~1.02 GB, per-test VRAM ~0.3 GB against ~29 GB free. The
CPU is not the constraint and neither is the GPU. A runner that picked `nproc`
would pick 24, need ~24 GB, and swap. See `worker_count()`.

Pure stdlib. Run from the package root.
"""
import argparse
import concurrent.futures
import json
import os
import pathlib
import shutil
import subprocess
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import _runner_tests
import harness_stamp
import machine_state_sentinel

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_LOG_DIR = ROOT / "tests" / "logs"
VERDICT_SH = "tests/lib/verdict.sh"

# --- copied from run_all_tests.sh's loop body, and guarded against it ---------
# Interactive diagnostic scenes need `--ci` to run their checks and quit.
CI_ARG_TESTS = ("UnitOrientationTest",)
# 6 min per test. Bumped from 180 s when #53's cinematic orchestrator started
# doubling the 4v4 arena's resolution time.
TIMEOUT_S = 360
# A per-test RAISE, for a test whose honest run does not fit the default. Not an
# escape hatch for a hang: every entry carries the MEASURED solo wall clock that
# justifies it, and a test that stops making progress still dies — later.
# Mirrored in `run_all_tests.sh`'s `case "$TEST"` table, and
# `tools/test_run_tests_parallel.py` reads BOTH and asserts they are equal.
#
#   GambitScenarioRunnerTest — 82 GPU scenarios in ONE process. Measured 678 s
#   solo (11m18s, [PASS], 82 scenarios green) on 2026-08-29. At 360 s it reached
#   56 of 82 and was scored HUNG (#709); it is not hung, it does not fit.
TIMEOUT_OVERRIDES = {"GambitScenarioRunnerTest": 1200}
# What `timeout(1)` reports when it kills the process, and the code verdict.sh
# keys HUNG off.
TIMEOUT_EXIT = 124

# --- the RAM model -----------------------------------------------------------
# Peak RSS of one test process, measured across the 2026-08-23 sequential arm
# (78 one-second samples, peak 1.02 GB, mean 0.64 GB). The PEAK is the number
# that matters: N processes can all be at their peak at once, and the mean would
# oversubscribe by 60%.
PER_TEST_KB = 1024 * 1024
# Left for the rest of the box. This machine is shared — during the measurement
# it also held two Godot editors from a sibling worktree and seven agent
# processes, and 8 GB of swap was already in use. A runner that spends every last
# free page makes the whole box slower, including its own workers.
RESERVE_KB = 2 * 1024 * 1024
# Cores left free. The RAM model says how many processes FIT; this says how many
# should RUN, and they are not the same question — a test can have all the memory
# it needs and still lose a deferred relayout to a box with nothing left to
# schedule it on.
#
# 🔴 MEASURED, not guessed. The pool grew to 24 of 24 on 2026-08-27 and a 713-test
# run went from 3 non-PASS to FOURTEEN. Every one of the twelve new ones passed on
# a re-run — ten at N=4 and the last two serially — so none was a real failure and
# all twelve cost a full re-run to disprove. `SEQUENTIAL_LANE` already carried the
# same finding for one test at N=8 ("20/20 PASS idle, 5 FAIL in 30 starts under an
# N=8 mixed load"), which should have been the warning.
#
# 2 is a floor on the headroom, not a claim that 22 is safe. The flake surface is
# CPU/GPU contention and this constant only bounds the CPU half; if a run still
# shows EffectStudio or GPU tests failing and passing on re-run, lower the ceiling
# with `-N` and say so, rather than treating the re-run as the answer.
CORE_HEADROOM = 2

# --- the desktop's share, and why RESERVE_KB does not buy it -----------------
# 🔴 `MemAvailable` CANNOT SEE THE HARM THIS POOL DOES, so RESERVE_KB above is
# not the reserve it reads as. MemAvailable is free pages plus reclaimable page
# CACHE. It does not count anon pages the kernel has already evicted to swap —
# so "2 GB is still available" stays true *because* the compositor's heap is
# being written to the swapfile to keep it true, and `additional_fits()` reads
# that 2 GB as room for another worker and takes it. The reserve is respected on
# every single sample and protects nothing.
#
# 🔴 MEASURED mid-run, 2026-09-10, on this box: 24 cores, 30 GB, ~22 workers in
# flight. A 40 s sample of /proc/meminfo held MemAvailable at 6–8 GB the whole
# time — RESERVE_KB never once binding — while, at that same instant:
#
#     Hyprland    VmRSS 172 MB    VmSwap 240 MB
#     waybar      VmRSS  23 MB    VmSwap  87 MB
#     fcitx5      VmRSS  26 MB    VmSwap   9 MB
#     alacritty   VmRSS  30–54 MB VmSwap 29–153 MB   (six of them)
#
# The compositor and every terminal were MORE swapped out than resident. A
# keystroke then has to major-fault that heap back from a 930 GB swapfile before
# the key-UP is processed, while the client's own Wayland key-repeat timer keeps
# firing — which is the `gggggggggggg` this box types during a suite run.
#
# ⚠️ CPU IS NOT THE CAUSE and lowering CORE_HEADROOM will not fix the typing.
# Across the same sample `/proc/pressure/cpu` read `full avg10=0.00` throughout
# (`some` peaked at 2.18%) and `/proc/pressure/io` `full avg10=0.20` at worst —
# nothing was ever fully stalled on a runqueue or on disk. The stall is memory.
#
# So the pool needs a second ceiling: one on what IT HOLDS, measured on its own
# processes, which is a number nothing can inflate by evicting somebody else.
# 8 GB is a WALL-CLOCK TRADE, not a discovered constant: at the ~530 MB mean RSS
# measured across 23 live workers it lands the pool near 15 in flight instead of
# the 22 `core_ceiling()` allows, and leaves 22 of the box's 30 GB to the desktop
# and the sibling agent sessions. Raise it with `--mem-budget-gb` or
# `FFT_SUITE_MEM_GB` when nobody is typing; `0` restores the old behaviour.
SUITE_RSS_BUDGET_KB = 8 * 1024 * 1024
# ...but never take that much of a SMALL box. The budget is capped so this much
# is always left outside it, and it never drops below one test.
BOX_FLOOR_KB = 8 * 1024 * 1024
# The scope's `MemoryHigh` is a BACKSTOP behind the pool cap, never the throttle.
# Set at the same number the cap uses, every scheduling wobble would become
# kernel reclaim inside a live worker; one test's peak of slack means the cap
# binds first and the kernel only steps in when the cap's arithmetic was wrong.
MEMORY_HIGH_SLACK_KB = PER_TEST_KB
# Set in the re-exec'd child, so a runner that wrapped itself does not do it again.
SCOPE_ENV = "FFT_SUITE_IN_SCOPE"


def core_ceiling(cores: int = None) -> int:
    """The most workers this box may run: `cores - CORE_HEADROOM`, floored at 1.

    ONE definition, because three call sites wrote this expression by hand and the
    banner's copy could disagree with the pool's without anything failing — a print
    that lies about the ceiling reads exactly like a pool that ignores it.
    """
    if cores is None:
        cores = os.cpu_count() or 1
    return max(1, cores - CORE_HEADROOM)


def worker_count(avail_kb: int = None, cores: int = None) -> int:
    """How many test processes fit, from FREE RAM — never from core count.

    `avail_kb` is MemAvailable, not MemFree: the page cache is reclaimable and
    counting it as taken would pick 1 on a box with 11 GB genuinely free.

    This is the STARTING size. The pool re-sizes itself as it runs — see
    `additional_fits()` and the scheduler in `main()`.
    """
    if avail_kb is None:
        avail_kb = _mem_available_kb()
    if cores is None:
        cores = os.cpu_count() or 1
    fits = (avail_kb - RESERVE_KB) // PER_TEST_KB
    return max(1, min(int(fits), core_ceiling(cores)))


def additional_fits(avail_kb: int = None) -> int:
    """How many MORE test processes fit right now. 0 is a valid answer.

    The difference from `worker_count()` is the floor: that one never returns
    less than 1, because a run with no workers is not a run. This one is asked
    *while workers already exist*, so "no room for another" has to be sayable.

    Reads the same MemAvailable, which already counts the running workers'
    pages as taken — so a pool sized by repeatedly asking this question
    converges instead of running away.
    """
    if avail_kb is None:
        avail_kb = _mem_available_kb()
    return max(0, int((avail_kb - RESERVE_KB) // PER_TEST_KB))


def target_inflight(running: int, avail_kb: int = None, cores: int = None,
                    budget_kb: int = None, used_kb: int = None) -> int:
    """How many tests SHOULD be in flight: what is running, plus what still fits,
    capped at cores and by the pool's own RSS budget, and never below 1.

    TWO CEILINGS, ASKING TWO DIFFERENT QUESTIONS. `additional_fits()` asks what
    the BOX has left and is the one that yields to a neighbour; `budget_fits()`
    asks what THIS POOL is already holding and is the one the box cannot lie
    about — see `SUITE_RSS_BUDGET_KB` for the measurement that says why the
    first is not enough on its own. `budget_kb=None` means no budget ceiling,
    which is what a caller reasoning about the RAM model alone wants.

    🔴 WHY THIS IS RE-ASKED RATHER THAN DECIDED ONCE. `worker_count()` reads a
    single instant, and this box is shared: a sibling worktree's Godot editor, a
    Blender, another agent's suite. Sizing once means a run that starts while a
    neighbour holds 10 GB stays throttled for its whole length even after that
    neighbour exits — measured on 2026-08-27, a 711-test run pinned at 8 workers
    for 18 minutes on a 24-core box because of who happened to be resident at
    second zero. Asking every time a slot frees costs one `/proc/meminfo` read
    per completed test and lets the run open up to the full 24 the moment the
    memory is actually there.

    It shrinks the same way. If a neighbour ARRIVES mid-run, `additional_fits()`
    goes to 0 and the pool stops launching until it does not — which is the
    "unless an issue comes up" half, and the reason this is safe to make the
    default rather than a flag.
    """
    if cores is None:
        cores = os.cpu_count() or 1
    target = min(core_ceiling(cores), running + additional_fits(avail_kb))
    if budget_kb:
        if used_kb is None:
            used_kb = suite_rss_kb()
        target = min(target, running + budget_fits(budget_kb, used_kb))
    return max(1, target)


def scope_cmd(budget_kb: int, argv: list[str], unit: str) -> list[str]:
    """The `systemd-run` line that re-launches this runner in its own cgroup.

    `MemoryHigh` throttles — it makes the KERNEL reclaim from these processes
    when they exceed the budget — and it never kills, so a budget that is wrong
    costs wall clock and not a verdict. `--collect` so a scope left behind by a
    killed run does not block the next one on a name clash."""
    return ["systemd-run", "--user", "--scope", "--quiet", "--collect",
            "--unit=" + unit,
            "-p", "MemoryHigh=%d" % ((budget_kb + MEMORY_HIGH_SLACK_KB) * 1024),
            "--", *argv]


def reexec_in_scope(budget_kb: int) -> None:
    """Re-launch this process inside a transient systemd user scope. Returns —
    having changed nothing — when that is not possible.

    WHY A CGROUP AS WELL AS THE POOL CAP. The cap is this runner's own
    arithmetic over `PER_TEST_KB`, and arithmetic can be wrong: a test whose
    peak is three times the mean, a Godot that leaks, a `-N` a caller forced
    past the model. `MemoryHigh` decides WHO PAYS when it is wrong. Without it
    the kernel reclaims from whatever is cheapest on the box, which is how the
    compositor ended up more swapped out than resident; with it the suite
    reclaims from the suite.

    ⚠️ The scope lands under `app.slice`, a SIBLING of `app-graphical.slice`
    where the terminals and the sibling agent sessions live — which is what
    makes `tools/desktop_input_guard.sh`'s `MemoryLow` on those slices able to
    name the suite as the preferred reclaim victim. A runner that stayed in the
    tmux scope would be inside the thing being protected.

    Best-effort by design. No systemd user session — a container, a CI box, a
    plain ssh login — means no scope and the pool cap alone, which is still the
    ceiling that does the work.
    """
    if os.environ.get(SCOPE_ENV) or not shutil.which("systemd-run"):
        return
    # ⚠️ ONLY WHEN THIS FILE IS THE ENTRY POINT. `main()` is also driven directly
    # by `tools/test_run_tests_parallel.py`, where `sys.argv[0]` is the test
    # harness — re-execing there relaunches unittest inside a scope and the test
    # dies on a path that never existed.
    if pathlib.Path(sys.argv[0] or "").name != pathlib.Path(__file__).name:
        return
    unit = "fft-suite-%d" % os.getpid()
    # Probed before it is exec'd into: a `systemd-run` that cannot start (no
    # user bus, cgroup delegation off) must degrade to an unscoped run, and an
    # `execvpe` into it would instead end the run with a message about systemd.
    probe = subprocess.run(scope_cmd(budget_kb, ["true"], unit + "-probe"),
                           capture_output=True)
    if probe.returncode != 0:
        print("  (no systemd user scope — running unscoped, pool cap only: %s)"
              % probe.stderr.decode(errors="replace").strip().splitlines()[:1],
              flush=True)
        return
    env = dict(os.environ)
    env[SCOPE_ENV] = "1"
    os.execvpe("systemd-run",
               scope_cmd(budget_kb, [sys.executable, *sys.argv], unit), env)


def _meminfo_kb(key: str) -> int:
    want = key + ":"
    for line in pathlib.Path("/proc/meminfo").read_text().splitlines():
        if line.startswith(want):
            return int(line.split()[1])
    raise RuntimeError("no %s in /proc/meminfo" % key)


def _mem_available_kb() -> int:
    return _meminfo_kb("MemAvailable")


def default_budget_kb(total_kb: int = None) -> int:
    """The pool's own RSS ceiling — `SUITE_RSS_BUDGET_KB`, shrunk so a smaller
    box still keeps `BOX_FLOOR_KB` outside it, and never below one test.

    A budget under one test would mean a run with no workers, which is the same
    thing `worker_count()`'s floor exists to refuse."""
    if total_kb is None:
        total_kb = _meminfo_kb("MemTotal")
    return max(PER_TEST_KB, min(SUITE_RSS_BUDGET_KB, total_kb - BOX_FLOOR_KB))


def proc_rss_table(proc: str = "/proc") -> dict:
    """`{pid: (ppid, rss_kb)}` for every process this user can read, in one pass.

    A process that exits between the directory scan and the read is SKIPPED, not
    an error: during a suite run tests are exiting constantly, and a measurement
    that raised on the normal case would be a measurement nobody could take."""
    table: dict[int, tuple[int, int]] = {}
    page_kb = os.sysconf("SC_PAGE_SIZE") // 1024
    try:
        entries = list(os.scandir(proc))
    except OSError:
        return table
    for entry in entries:
        if not entry.name.isdigit():
            continue
        try:
            # `comm` may hold spaces AND parens, so ppid is found from the LAST
            # `)` — the field index is only stable after it.
            stat = pathlib.Path(proc, entry.name, "stat").read_bytes()
            ppid = int(stat[stat.rindex(b")") + 2:].split()[1])
            rss = int(pathlib.Path(proc, entry.name, "statm").read_text().split()[1])
        except (OSError, ValueError, IndexError):
            continue
        table[int(entry.name)] = (ppid, rss * page_kb)
    return table


def descendant_rss_kb(root_pid: int, table: dict) -> int:
    """Summed RSS of `root_pid`'s DESCENDANTS — the workers, not the runner.

    The runner's own interpreter is not what the budget is about, and counting
    it would make the same budget mean two different things depending on whether
    the caller went through `uv run`."""
    kids: dict[int, list[int]] = {}
    for pid, (ppid, _) in table.items():
        kids.setdefault(ppid, []).append(pid)
    total, stack = 0, list(kids.get(root_pid, ()))
    seen = set()
    while stack:
        pid = stack.pop()
        if pid in seen:          # a reparented pid cannot make this loop
            continue
        seen.add(pid)
        total += table[pid][1]
        stack.extend(kids.get(pid, ()))
    return total


def suite_rss_kb(root_pid: int = None) -> int:
    """What the pool is holding RIGHT NOW, read off its own processes."""
    return descendant_rss_kb(os.getpid() if root_pid is None else root_pid,
                             proc_rss_table())


def budget_fits(budget_kb: int, used_kb: int) -> int:
    """How many more workers the BUDGET allows. 0 is a valid answer, for the
    same reason it is in `additional_fits()`."""
    return max(0, int((budget_kb - used_kb) // PER_TEST_KB))


# --- the sequential lane -----------------------------------------------------
# Tests that must NOT run beside anything else, each with the reason it is here.
# FILLED BY THE DIFF, never by hand. #453's whole point is that a lane entry is a
# MEASUREMENT — "this test's verdict moved between the sequential and parallel
# arms, N times out of M" — and not a guess about which tests look timing-
# sensitive. Guessing would both miss real movers and quarantine innocents, and
# either one silently shrinks what the register measures.
#
# ⚠️ A LANE ENTRY IS THE SECOND CHOICE (ADR-0158 dec. 3). The arms named exactly
# one mover and it was ROOT-CAUSED first: `_scroll_selected_into_view` returned
# "already visible" on every invocation the feature ever had, so the test's
# assertion was vacuous and its rare red was the only time the absence was
# observable. Laning it then would have preserved a green and kept a dead
# feature dead. It is here now because the fix made the assertion REAL and the
# real assertion is contention-sensitive — a different fact, separately measured.
SEQUENTIAL_LANE: dict[str, str] = {
    "EffectStudioDeselectScrollAcceptanceTest":
        "FLAKY_PARALLEL at c546fbbb4: 20/20 PASS idle, 5 FAIL in 30 starts under "
        "an N=8 mixed load (`the into-view nudge actually ran (runs=0)`, "
        "`window_bottom=0.0` — the deferred relayout has not landed when the "
        "assertion reads it). Stable sequentially, so the lane restores it. #527",
}


def test_list() -> list[str]:
    """The runner's own array, in its own order."""
    return _runner_tests.runner_tests(ROOT / "tests" / "run_all_tests.sh")


def partition(stems, lane=None):
    """(parallel, sequential), each in the array's order."""
    lane = SEQUENTIAL_LANE if lane is None else lane
    return ([s for s in stems if s not in lane],
            [s for s in stems if s in lane])


def log_path(stem: str, log_dir: pathlib.Path) -> pathlib.Path:
    return pathlib.Path(log_dir) / (stem + ".log")


def godot() -> str:
    return os.environ.get("GODOT", "godot")


def godot_version(binary: str = None) -> str:
    v = subprocess.run([binary or godot(), "--version"],
                       capture_output=True, text=True).stdout.strip().splitlines()
    return v[-1] if v else "UNKNOWN"


def head_sha(project_dir: pathlib.Path = ROOT) -> tuple[str, bool]:
    """(sha, dirty) for the tree about to be measured. UNKNOWN outside a repo —
    a stamp that guesses is worse than one that admits it doesn't know."""
    def git(*a):
        return subprocess.run(["git", "-C", str(project_dir), *a],
                              capture_output=True, text=True)
    r = git("rev-parse", "HEAD")
    if r.returncode != 0:
        return "UNKNOWN", False
    return r.stdout.strip(), git("diff", "--quiet", "HEAD").returncode != 0


def provenance_line(sha: str, dirty: bool, godot: str) -> str:
    """The two facts that make two runs comparable, printed into the artifact.

    #453 §5.1. This runner's stdout is what gets archived, and NOT ONE of the five
    archived suite runs records the tree it measured — so every "is this the same
    code?" question about the corpus is unanswerable, which is exactly the
    provenance error map #450 keeps punishing. One `rev-parse` ends it.

    The DIRTY marker carries as much weight as the SHA: a run against a modified
    tree is not a run against that commit, and the runs most likely to be dirty are
    the mid-investigation ones whose attribution matters most. Same wording as
    `freeze_test_baseline.py`'s `code_commit` header, so one grep finds both.

    The engine goes on the same line because it is the other axis that makes two
    runs incomparable: the 4.8 compositor fork renders folded effects and stock 4.7
    silently does not (CLAUDE.md), so a number from each is two different suites.

    Indented two spaces like the rest of the banner, but never as `  -> WORD` —
    that shape is what `freeze_test_baseline.verdicts()` reads as a test's verdict
    (§5.2), and a banner line that could be mistaken for one is a stamp that
    corrupts the thing it was added to make trustworthy.
    """
    mark = "  (WORKING TREE DIRTY at capture)" if dirty else ""
    return f"  code_commit {sha}{mark}\n  godot {godot}"


def timeout_for(stem: str) -> int:
    """This test's wall clock: the default, unless it is named in the raise table."""
    return TIMEOUT_OVERRIDES.get(stem, TIMEOUT_S)


def command_for(stem: str, project_dir: pathlib.Path = ROOT) -> list[str]:
    """One process, one scene, headful, wrapped in `timeout` — and the wrapper
    is not a convenience.

    `run_all_tests.sh` runs `timeout 360 "$GODOT" ... | tee "$LOG"` and scores
    `${PIPESTATUS[0]}`, so verdict.sh sees a segfaulting child as 139 and a hang
    as 124. Those are the literal numbers its CRASHED (`>= 128`) and HUNG
    (`== 124`) rules test. Python's own `Popen.wait()` reports a signal death as
    NEGATIVE (-11 for SIGSEGV): `[ -11 -ge 128 ]` is false, so every crash in
    this arm would score NO_VERDICT while the same crash in the sequential arm
    scores CRASHED. 64 test names dump core in every archived run (#471) — that
    is ~64 rows per run scored by a different rule than the arm they are being
    compared against, which would invalidate the identity proof from inside the
    instrument built to make it.

    Handing the job back to `timeout(1)` makes the two arms agree by
    construction, and it also leaves `timeout: the monitored command dumped
    core` in the log — the string `replay.py` reconstructs an archived run's
    exit code from.

    No `--headless`: the 4.8 fork's engine-fold compositor self-disables under
    it and every folded effect prim silently vanishes, so a render test would
    pass against a degraded frame.
    """
    cmd = ["timeout", str(timeout_for(stem)), godot(),
           "--path", str(project_dir), f"res://tests/{stem}.tscn"]
    if stem in CI_ARG_TESTS:
        cmd += ["--", "--ci"]
    return cmd


def run_capture(cmd: list[str], log: pathlib.Path) -> int:
    """Run cmd with stdout+stderr to `log`; return the shell's exit status.

    The negative-to-128+signo fold is belt and braces: `timeout` already
    normalises its child, but this function is also what the tests drive
    directly, and a runner that only agrees with the shell most of the time is
    not the thing #453 needs.
    """
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("wb") as fh:
        code = subprocess.Popen(cmd, cwd=str(ROOT), stdout=fh,
                                stderr=subprocess.STDOUT).wait()
    return code if code >= 0 else 128 - code


def verdict(log: pathlib.Path, exit_code: int) -> str:
    """The ONE reader, sourced. Not a Python restatement of its nine rules."""
    out = subprocess.run(
        ["bash", "-c", f'source "$1"; test_verdict "$2" "$3"',
         "_", str(ROOT / VERDICT_SH), str(log), str(exit_code)],
        capture_output=True, text=True, cwd=str(ROOT))
    return out.stdout.strip() or "NO_VERDICT"


def run_one(stem: str, log_dir: pathlib.Path) -> dict:
    """Launch, capture to the log the reader will read, score, time it."""
    log = log_path(stem, log_dir)
    start = time.monotonic()
    code = run_capture(command_for(stem), log)
    wall = time.monotonic() - start
    return {"test": stem, "verdict": verdict(log, code),
            "exit": code, "seconds": round(wall, 2)}


def format_progress(num: int, total: int, stem: str, result: str,
                    seconds: float = None, exit_code: int = None) -> str:
    """The lines `freeze_test_baseline.verdicts()` pairs up, plus the two
    `tools/suite_register.py` prices a run with. Byte-compatible with
    `run_all_tests.sh` on purpose — the register parses stdout, so a parallel arm
    that printed its own shape could not feed it.

    `  seconds` and `  exit` are SEPARATE lines and never decorations on
    `  -> RESULT`: that shape is what the verdict parser reads, and every
    archived run and every `replay.py` reconstruction depends on it unchanged.
    They are also optional here, because an arm that did not measure must print
    nothing rather than a zero — `suite_register` renders a missing wall clock as
    `-`, and a `0.00` would read as an instant test and poison the budget."""
    out = f"[{num}/{total}] Running {stem}...\n  -> {result}\n"
    if seconds is not None:
        out += f"  seconds {seconds:.2f}\n"
    if exit_code is not None:
        out += f"  exit {exit_code}\n"
    return out


OUTCOMES = ("PASS", "FAIL", "THREW", "TIMEOUT", "HUNG",
            "CRASHED", "NOT_A_TEST", "NO_VERDICT")
_LABEL = {"PASS": "PASSED", "FAIL": "FAILED"}


def format_summary(results) -> str:
    """The eight-outcome block. NOT_A_TEST comes out of the DENOMINATOR — a rig
    in the numerator would inflate a coverage figure with something that never
    asserted."""
    tally = {o: 0 for o in OUTCOMES}
    lines = []
    for stem, v in results:
        tally[v] = tally.get(v, 0) + 1
        lines.append(f"  [{v}] {stem}")
    total = len(results)
    out = ["=" * 38, "  RESULTS SUMMARY", "=" * 38, *lines, ""]
    out.append(f"  PASSED:     {tally['PASS']} / {total - tally['NOT_A_TEST']}")
    for o in OUTCOMES[1:]:
        out.append(f"  {(_LABEL.get(o, o) + ':'):<11} {tally[o]}")
    out.append("=" * 38)
    return "\n".join(out)


# The sentinel `tests/run_all_tests.sh` prints immediately before the gate, which every
# guard's `exit 1` is upstream of. Its PRESENCE is the only positive evidence a caller has
# that the guards ran and passed; `rc == 0` is not, because a caller reading stdout may be
# looking at a run that aborted. Spelled once, here, and imported by the gate's own tests.
PREFLIGHT_PASSED = "PRE-FLIGHT COMPLETE: every static guard above passed."


def preflight_abort_line(stdout: str) -> str | None:
    """The LAST `ABORT:` line in `stdout`, or None if the pre-flight reached the gate.

    The last one and not the first: `run_all_tests.sh` aborts on the first failing guard,
    so at most one is ever printed by a real run — but a guard's own OUTPUT may quote the
    word, and the abort that actually stopped the script is the final one either way.

    Returns None whenever the sentinel is present, so a guard that prints `ABORT:` in
    prose while still passing cannot make a green pre-flight read as a broken one."""
    if PREFLIGHT_PASSED in stdout:
        return None
    hits = [ln.strip() for ln in stdout.splitlines() if ln.lstrip().startswith("ABORT:")]
    return hits[-1] if hits else None


def preflight() -> bool:
    """Run the ~25 static guards that live in `tests/run_all_tests.sh`, and nothing else.

    THIS RUNNER DOES NOT OWN THEM EITHER. It owns a test list and a worker pool; the
    guards are a long block of `uv run python tools/check_*.py` calls in the sequential
    runner, growing whenever somebody adds a rule. Copying them here would be a second
    place to add one — and a guard that only exists in the arm nobody runs is #565's
    finding (`check_vault_anchors.py`, registered nowhere, for months). So: shell out to
    the one definition, via the flag that runs the guards and stops before any Godot.

    Seconds, not minutes — no Godot is launched.
    """
    print("pre-flight (tests/run_all_tests.sh --preflight-only) …", flush=True)
    # \U0001f534 STREAMED AND CAPTURED, not just streamed (#823). The pre-flight is a wall
    # of ~50 guards and the one that aborted printed its own `ABORT:` line several hundred
    # lines up; this message used to say only that "a pre-flight guard failed", which
    # leaves the reader to scroll for the name of the guard they are being told about.
    # Capturing the tail is the cheapest way to say WHICH, and it costs nothing a reader
    # loses: every line still prints as it arrives.
    proc = subprocess.Popen(["bash", str(ROOT / "tests" / "run_all_tests.sh"),
                             "--preflight-only"], cwd=ROOT,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    lines: list[str] = []
    for line in proc.stdout:
        sys.stdout.write(line)
        lines.append(line)
    sys.stdout.flush()
    rc = proc.wait()
    if rc != 0:
        named = preflight_abort_line("".join(lines))
        print("ABORT: a pre-flight guard failed. Fix it before reading any verdict.",
              file=sys.stderr)
        print("       %s" % (named or "no `ABORT:` line was printed — the pre-flight died "
                             "some other way; read the tail above."), file=sys.stderr)
        return False
    return True


def rebuild_class_cache() -> None:
    """Rebuild Godot's global class cache before the workers start.

    🔴 A `class_name` the cache has not seen is a PARSE ERROR in every script that
    names it, and when one of those scripts is an autoload it is a parse error in
    EVERY test. MEASURED on the merge of #1094, which added `DebugPanelIds` (named by
    `DebugOverlay`, an autoload): 6 PASSED of 770, 694 THREW, 13.8 minutes of the suite
    saying `Identifier "DebugPanelIds" not declared` — one cold cache reading as a
    catastrophic regression. `godot --path . --import` and the same tree is green.

    The sequential arm has always done this, immediately above its test loop. This
    runner shelled out to `--preflight-only` and inherited the guards but NOT that
    line, because the line sits BELOW the `--preflight-only` exit. So the sanctioned
    way to run the suite was the one arm that never rebuilt the cache.

    ⚠️ IT DOES NOT BELONG IN THE PRE-FLIGHT, and two arms of
    `test_run_tests_parallel.SequentialArmIsGated` say so by name: `--preflight-only`
    and the no-argument gate both assert `assertNotIn("Rebuilding Godot import
    cache")` — *"the gate must stop BEFORE any Godot work"*. Moving it up there passes
    the cache to this runner and breaks that contract in the same edit. It is not a
    guard; it is test-loop setup, which is why it lives beside each arm's test loop.

    Best-effort: a failure here is not a verdict about the tree, and the parse errors
    it would have prevented still surface per test."""
    print("rebuilding Godot import cache (so new/edited class_name scripts load) …",
          flush=True)
    subprocess.run(["timeout", "300", godot(), "--path", str(ROOT), "--import"],
                   cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("-N", "--workers", type=int, default=None,
                    help="cap parallel workers (default: derived from free RAM, and it GROWS toward core count as RAM frees)")
    ap.add_argument("--log-dir", type=pathlib.Path, default=DEFAULT_LOG_DIR,
                    help="where per-test logs go (default: tests/logs)")
    ap.add_argument("--jsonl", type=pathlib.Path, default=None,
                    help="append one record per test: verdict, exit, seconds")
    ap.add_argument("--tests", default=None,
                    help="comma-separated subset, for a smoke run")
    ap.add_argument("--no-preflight", action="store_true",
                    help="skip the sequential runner's static pre-flight guards")
    ap.add_argument("--mem-budget-gb", type=float, default=None,
                    help="ceiling on the POOL's own RSS, in GB. 0 disables it and "
                         "restores the pre-#1099 MemAvailable-only model. Default "
                         "from $FFT_SUITE_MEM_GB, else `default_budget_kb()`")
    ap.add_argument("--no-scope", action="store_true",
                    help="do not re-exec into a systemd user scope; keep the pool "
                         "cap but drop the kernel's MemoryHigh backstop")
    args = ap.parse_args(argv)

    # --- the memory budget, resolved once ------------------------------------
    # Flag beats environment beats the measured default, and an explicit 0 at
    # either level is a REAL answer ("no budget"), not a missing one — which is
    # why this is not a chain of `or`.
    if args.mem_budget_gb is not None:
        budget_kb = int(args.mem_budget_gb * 1024 * 1024)
    elif os.environ.get("FFT_SUITE_MEM_GB"):
        budget_kb = int(float(os.environ["FFT_SUITE_MEM_GB"]) * 1024 * 1024)
    else:
        budget_kb = default_budget_kb()

    # BEFORE the pre-flight, not after: the guards and the import-cache rebuild
    # are part of what the run costs the box, and a scope that only wrapped the
    # test loop would leave `godot --import` outside it.
    if budget_kb and not args.no_scope:
        reexec_in_scope(budget_kb)          # does not return, when it works

    if not args.no_preflight and not preflight():
        return 1
    rebuild_class_cache()

    # --- machine-state sentinel, open bracket (ADR-0281 / #1149) -------------
    # NOT a pre-flight guard, and it could not be one: a pre-flight asks about the TREE
    # and this asks what the RUN did, so it has to bracket the test loop. It opens after
    # the cache rebuild for the same reason `rebuild_class_cache` is not in the
    # pre-flight — everything from here down is test-loop setup, not a guard.
    args.log_dir.mkdir(parents=True, exist_ok=True)
    machine_state = args.log_dir / "machine_state.json"
    machine_state_sentinel.main(["--snapshot", str(machine_state)])

    stems = test_list()
    if args.tests:
        want = [t.strip() for t in args.tests.split(",") if t.strip()]
        unknown = [t for t in want if t not in stems]
        if unknown:
            sys.exit("not in the runner's array: " + ", ".join(unknown))
        stems = [s for s in stems if s in want]

    cores = os.cpu_count() or 1
    n = args.workers or worker_count()
    if budget_kb and not args.workers:
        # The opening size obeys the budget too. It is ~0-used at this point, so
        # this only bites when the budget is smaller than what free RAM allows —
        # which is exactly the case the budget exists for.
        n = max(1, min(n, budget_fits(budget_kb, suite_rss_kb())))
    if args.workers:
        cores = args.workers          # an explicit -N is a ceiling, not a start
    par, seq = partition(stems)
    total = len(stems)

    sha, dirty = head_sha()
    print("=" * 38)
    print("  GPU Combat Test Suite — PARALLEL")
    print(f"  Running {total} tests, {n} workers to start"
          + (f" (grows to {core_ceiling(cores)} of {cores} cores as RAM frees)"
             if not args.workers else "")
          + f", {len(seq)} in the sequential lane")
    print(provenance_line(sha, dirty, godot_version()))
    # The same two harness stamps the sequential runner prints, from the same
    # owner — see `tools/harness_stamp.py`. Two arms printing two different
    # provenance shapes is the drift `format_progress` exists to prevent, one
    # level up.
    print(harness_stamp.banner_lines())
    print("=" * 38, flush=True)
    # OUTSIDE the banner block on purpose: `freeze_test_baseline._banner()` reads
    # the title and the `Running N tests` line, and a new line between them would
    # move the register's provenance parse.
    print("  memory: pool capped at %s"
          % ("%.1f GB RSS (raise with --mem-budget-gb / $FFT_SUITE_MEM_GB)"
             % (budget_kb / 1024 / 1024) if budget_kb else "free RAM only (budget off)")
          + (", scope MemoryHigh=%.1f GB"
             % ((budget_kb + MEMORY_HIGH_SLACK_KB) / 1024 / 1024)
             if budget_kb and os.environ.get(SCOPE_ENV) else ", unscoped"),
          flush=True)

    started = time.monotonic()
    records: list[dict] = []
    done = 0

    def emit(rec):
        nonlocal done
        done += 1
        records.append(rec)
        print(format_progress(done, total, rec["test"], rec["verdict"],
                              rec.get("seconds"), rec.get("exit")), flush=True)

    # The pool is sized at `cores` and GATED by `target_inflight`, which is
    # re-asked every time a test finishes. `n` above is only the opening size and
    # the number the banner reports; `peak_n` is what actually ran, and the
    # summary prints both so a slow run is attributable to the box rather than a
    # mystery. Submitting all futures up front would defeat this — a
    # ThreadPoolExecutor starts as many as its max_workers allows immediately —
    # so work is handed over one slot at a time.
    pending = list(par)
    peak_n = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=cores) as pool:
        running: dict = {}
        while pending or running:
            target = target_inflight(len(running), cores=cores,
                                     budget_kb=budget_kb)
            while pending and len(running) < target:
                stem = pending.pop(0)
                running[pool.submit(run_one, stem, args.log_dir)] = stem
            peak_n = max(peak_n, len(running))
            finished, _ = concurrent.futures.wait(
                running, return_when=concurrent.futures.FIRST_COMPLETED)
            for fut in finished:
                running.pop(fut)
                emit(fut.result())

    # The lane runs alone, AFTER the pool has drained — a test that is here
    # because it cannot tolerate contention gains nothing from running beside
    # the tail of the parallel phase.
    for stem in seq:
        emit(run_one(stem, args.log_dir))

    # --- the stranger phase (ADR-0194 dec. 10) ------------------------------
    # THE OTHER ARM HAS TO RUN THEM TOO. dec. 10 words the phase as
    # `run_all_tests.sh`'s, and this is the arm anyone actually uses for a
    # landing run — 10 minutes against 61. A rig that only the slow arm invokes
    # is a rig nobody invokes, and "green because it stopped looking" is the
    # failure the phase exists to prevent, not a property of one runner.
    #
    # SEQUENTIAL, AND AFTER THE POOL: each rig stages a project and boots Godot
    # two or three times, which is exactly the contention the sequential lane
    # exists for.
    #
    # NOT IN `records`, and that is deliberate. `records` is what `--jsonl` and
    # `tools/suite_register.py` read, one row per TEST, keyed by a stem that
    # names a `tests/<stem>.tscn`. A rig is not one of those and must not arrive
    # in that register wearing one's clothes. It joins the SUMMARY, which is a
    # human-facing tally, and the exit code.
    rig_results = []
    if not args.tests:
        rigs = _runner_tests.stranger_rigs(ROOT / "tests" / "stranger")
        if rigs:
            print("=" * 38, flush=True)
            print(f"  STRANGER RIGS — {len(rigs)}, sequential, after the pool")
            print("  Each builds its own throwaway project and installs ONE addon.")
            print("=" * 38, flush=True)
            for i, rig in enumerate(rigs, 1):
                addon = rig.parent.name
                log = args.log_dir / f"stranger_{addon}.log"
                t0 = time.monotonic()
                code = run_capture(["bash", str(rig)], log)
                # The rig's own three exit codes. 2 is COULD NOT RUN and is
                # loudly not a pass; NO_VERDICT is this suite's word for the
                # same claim, and scoring it FAIL would report a portability
                # defect where what happened is a missing engine.
                v = {0: "PASS", 1: "FAIL"}.get(code, "NO_VERDICT")
                rig_results.append((f"stranger:{addon}", v))
                print(f"  [rig {i}/{len(rigs)}] {addon}  {v}  "
                      f"({time.monotonic() - t0:.0f}s, exit {code}, {log})", flush=True)

    wall = time.monotonic() - started
    by_stem = {r["test"]: r["verdict"] for r in records}
    print(format_summary([(s, by_stem[s]) for s in stems] + rig_results))
    print(f"  wall clock: {wall / 60:.1f} min at N={n}"
          + (f" (peak {peak_n} of {cores} cores)" if peak_n != n else ""))
    print(f"  cpu-seconds in tests: {sum(r['seconds'] for r in records) / 60:.1f} min")

    if args.jsonl:
        args.jsonl.parent.mkdir(parents=True, exist_ok=True)
        with args.jsonl.open("w") as fh:
            for r in sorted(records, key=lambda r: r["test"]):
                fh.write(json.dumps(r) + "\n")

    red = sum(1 for r in records if r["verdict"] not in ("PASS", "NOT_A_TEST"))
    red += sum(1 for _, v in rig_results if v != "PASS")

    # --- machine-state sentinel, close bracket (ADR-0281 / #1149) -----------
    # 🔴 IT SCORES THE RUN RED, and it is the one red that is not about any single test:
    # a run that rewrote `config/tune_overrides.json` mid-flight poisoned every test that
    # booted after the write, so the per-test verdicts above describe the poison and not
    # the tree. #1149 measured nine of them, and they were read as a regression in the
    # branch under test. A green tally printed beside a changed machine file is the
    # reading this line exists to make impossible.
    if machine_state_sentinel.main(["--compare", str(machine_state)]):
        print("  🔴 MACHINE STATE CHANGED — the verdicts above are not about this tree.",
              flush=True)
        red += 1

    return 1 if red else 0


if __name__ == "__main__":
    sys.exit(main())
