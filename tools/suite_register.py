#!/usr/bin/env python3
"""A RE-TAKEABLE per-test register, and a diff between two of them — #454, map #450.

    uv run python tools/suite_register.py take --run-log <log> [--run-log <log>...] \
        [--log-dir tests/logs] [--out <path>]
    uv run python tools/suite_register.py diff <register-a> <register-b>

WHY THIS EXISTS BESIDE `freeze_test_baseline.py`, WHICH IS NOT REPLACED.
`docs/TEST-BASELINE-E2.tsv` is a FROZEN pre-move measurement of extraction #2 and
`check_test_baseline.py` correctly refuses to re-freeze it. That makes it exactly
right as one move's record and unusable as a running health metric: it can only
ever answer one question, about one move. This is the other shape — takeable on
ANY commit, diffable against ANY other. Neither file is touched by this tool.

THE FOUR THINGS IT HAS TO GET RIGHT, EACH OF WHICH THIS MAP HAS ALREADY PAID FOR:

1. IT DOES NOT SCORE. `tests/lib/verdict.sh` is the ONE reader (#451) and this
   transcribes its output out of a runner's stdout. It never re-reads the markers
   in a per-test log to form an opinion — doing so would silently undo rule 7
   (`NOT_A_TEST`) and rule 9 (`THREW`), both of which score a log full of `[PASS]`
   as something other than PASS. The per-test logs supply EVIDENCE only: assertion
   counts, `SCRIPT ERROR` counts, and the failing assertion names.

2. ONE RUN CANNOT REPORT A FLAKE SET. A register taken from a single run knows a
   verdict and nothing about its stability, and a blank stability column reads as
   a clean bill of health. #417 adopted **275** tests that are green exactly ONCE;
   this register prints `UNMEASURED×1` against every one of them and says so in
   the `flakes` header rather than printing `0`. Repeats of the same harness on
   the same tree are how the column becomes `STABLE×n` or `FLAKY(...)`.

3. A DIFF OF TWO SINGLE RUNS REPORTS FLAKES AS MOVERS. `diff_arm_verdicts.py`
   measured this on the archived corpus: four tests are not constant across three
   SAME-TREE runs, so `diff <(a) <(b)` quarantines four innocent tests and proves
   nothing. That tool answers the arm-vs-arm question and this one answers the
   commit-vs-commit question, but the refusal is the same and is deliberately
   spelled the same way — a verdict that was never stable cannot have been moved
   by your commit, and a difference seen once per side is `UNCONFIRMED`, not
   `MOVED`. The remedy the word names is *take more repeats*, not *ignore it*.

4. PROVENANCE IS A PROPERTY OF THE RUN, NOT OF THE MOMENT YOU TAKE THE REGISTER.
   `take` runs no `git rev-parse` and stats no addon: the commit, the engine, the
   harness mode, the addon-sync state and the `.godot/` cache state are all read
   out of the RUNNER'S OWN BANNER, because only the runner was there. Two run logs
   naming different commits are a `ProvenanceError`, never a merge — reading a
   register from one run against a tally from another is the exact error that
   produced this map's original "wrong in both directions" headline (#451).

5. A DEVICE THAT NEVER CAME UP IS EVIDENCE, NEVER A VERDICT. Measured on #547's
   first full register: `GPUArenaTest` on a box with 843 MiB of free VRAM lost the
   test's own `RenderingDevice`, emitted 5,698 `Only local devices can submit and
   sync.` errors — not one compute dispatch reached the GPU — and printed
   `[PASS] Arena combat resolved - Team 1 won`. Every other column on the row read
   clean. `device_lost` counts it, in every repeat's log dir, and `diff` calls a
   difference against such a row `ENVIRONMENT` rather than `MOVED`. This is #526's
   sibling: there the ENGINE never started and the row was a false RED
   (`NO_VERDICT`); here it started, the test's device did not, and the row is a
   false GREEN, which no denominator protects you from.

WHAT IT DOES NOT DECIDE. It measures the wall clock per test and in total; it does
not set a budget. Whether ~100 minutes is affordable, and what the `slow` class in
`tests/skip_tests.tsv` should hold, is a decision, and a decision wants a ticket
rather than a threshold buried in a tool.

REGISTERS ARE ARTIFACTS, NOT TRACKED FILES. `take` writes wherever you point it
and prints to stdout by default. A register committed to the tree is a `tests/logs`
in waiting — checked in, stale within a week, and with nothing saying so.

Pure stdlib. Run from the package root.
"""
import argparse
import collections
import dataclasses
import datetime
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import freeze_test_baseline as ftb   # the parsers, reused rather than restated


class ProvenanceError(RuntimeError):
    """Two run logs that are not the same run of the same tree."""


# --- reading a runner's stdout ------------------------------------------------

RUNNING_RE = re.compile(r'^\[(\d+)/(\d+)\] Running (\S+)\.\.\.')
VERDICT_RE = re.compile(r'^  -> (\w+)$')
SECONDS_RE = re.compile(r'^  seconds ([0-9.]+)$')
EXIT_RE = re.compile(r'^  exit (-?\d+)$')
RULE_RE = re.compile(r'^=+$')
# The banner's own key/value lines. Read ONLY inside the banner block — a suite
# stdout carries hundreds of pre-flight lines and one of them starting with the
# word `godot` would otherwise become the provenance.
FIELD_RE = re.compile(
    r'^\s{2}(code_commit|godot|addon_sync|godot_cache|test_coverage)\s+(.+)$')
BANNER_TITLES = (ftb.SEQUENTIAL_TITLE, ftb.PARALLEL_TITLE)


@dataclasses.dataclass
class Run:
    """One runner stdout, read."""
    path: str
    fields: dict                 # code_commit / godot / addon_sync / godot_cache
    runner: str                  # the harness property, from the banner
    verdicts: dict               # stem -> verdict
    seconds: dict                # stem -> float
    exits: dict                  # stem -> int


def _banner_block(lines):
    """The runner's title block, as a slice, or None.

    Bounded by the format rather than by a line count: the sequential runner
    prints 27 pre-flights before its banner, so a `head` misses it entirely, and
    the first `[n/N] Running` line is the only bound the format guarantees.
    """
    for i, line in enumerate(lines):
        if RUNNING_RE.match(line):
            return None
        if line.strip() in BANNER_TITLES:
            j = i + 1
            while j < len(lines) and not RULE_RE.match(lines[j].strip()):
                if RUNNING_RE.match(lines[j]):
                    break
                j += 1
            return lines[i:j]
    return None


def parse_run(path) -> Run:
    """Transcribe one runner stdout. Scores nothing."""
    path = pathlib.Path(path)
    text = path.read_text(errors="replace")
    lines = text.splitlines()

    fields = {}
    for line in _banner_block(lines) or []:
        m = FIELD_RE.match(line)
        if m:
            fields[m.group(1)] = m.group(2).strip()

    # The harness mode comes from `freeze_test_baseline`, which already reads
    # both banners and already says UNKNOWN for a log that has neither.
    _cmd, prop = ftb.runner_provenance([path])

    verdicts, seconds, exits, scored = {}, {}, {}, None
    for line in lines:
        m = RUNNING_RE.match(line)
        if m:
            scored = m.group(3)
            continue
        m = VERDICT_RE.match(line)
        if m and scored:
            verdicts[scored] = m.group(1)
            continue
        m = SECONDS_RE.match(line)
        if m and scored:
            seconds[scored] = float(m.group(1))
            continue
        m = EXIT_RE.match(line)
        if m and scored:
            exits[scored] = int(m.group(1))
    return Run(str(path), fields, prop, verdicts, seconds, exits)


# --- stability ----------------------------------------------------------------

STABLE_RE = re.compile(r'^STABLE×(\d+)$')
UNMEASURED_RE = re.compile(r'^UNMEASURED×(\d+)$')


def stability(observed):
    """(reported verdict, stability field) for one test's verdicts across repeats.

    ONE OBSERVATION IS `UNMEASURED`, NOT `STABLE`. The distinction is the whole
    point of the column: `STABLE×1` is a claim no single run is entitled to make,
    and it is the claim under which 275 tests were adopted green-once.
    """
    tally = collections.Counter(observed)
    if len(tally) == 1:
        only = next(iter(tally))
        n = tally[only]
        return only, (f"STABLE×{n}" if n > 1 else f"UNMEASURED×{n}")
    # Most-common first, alphabetical on a tie: informative AND deterministic.
    # A register is a diffable artifact, so a cell whose spelling depends on
    # dict insertion order would show up as a change that is not one.
    ranked = sorted(tally.items(), key=lambda kv: (-kv[1], kv[0]))
    return "FLAKY", "FLAKY(" + ",".join(f"{v}×{c}" for v, c in ranked) + ")"


def repeats_of(field: str):
    """How many observations a stability field represents, or None if flaky."""
    for rx in (STABLE_RE, UNMEASURED_RE):
        m = rx.match(field or "")
        if m:
            return int(m.group(1))
    return None


def is_flaky(field: str) -> bool:
    return (field or "").startswith("FLAKY")


# --- the register -------------------------------------------------------------

COLUMNS = ("test", "verdict", "stability", "seconds", "exit", "asserts_pass",
           "asserts_fail", "markers", "script_errors", "failing_assertions",
           "device_lost")

MAX_FAILING = 8


@dataclasses.dataclass
class Row:
    test: str
    verdict: str
    stability: str
    seconds: float = None
    exit_code: int = None
    asserts_pass: int = None
    asserts_fail: int = None
    markers: int = None
    script_errors: int = None
    failing: str = "-"
    device_lost: int = None


@dataclasses.dataclass
class Register:
    header: dict
    rows: list

    def row(self, stem):
        for r in self.rows:
            if r.test == stem:
                return r
        return None

    def render(self) -> str:
        out = [
            "# A RE-TAKEABLE per-test register — #454, map #450.",
            "# GENERATED by tools/suite_register.py take. Never hand-edit.",
            "# NOT a replacement for docs/TEST-BASELINE-E2.tsv, which stays frozen.",
            "#",
            "# The VERDICT column is tests/lib/verdict.sh's output, transcribed from the",
            "# runner's stdout — never re-derived here. The per-test logs supply evidence",
            "# (assertion counts, SCRIPT ERRORs, failing assertion names) and no verdict.",
            "#",
            "# STABILITY is what the repeat count could see. UNMEASURED×1 is not a clean",
            "# bill of health: a single run cannot tell a stable green from a coin flip,",
            "# and `suite_register.py diff` will not call such a row a mover.",
            "#",
            "# DEVICE_LOST is how many of the scanned log dirs show the engine or the",
            "# test's own RenderingDevice failing to come up. A non-zero cell on a PASS",
            "# row is a green taken with the GPU missing — see rule 5.",
        ]
        for k in ("code_commit", "godot", "runner", "taken_on", "repeats",
                  "addon_sync", "godot_cache", "coverage", "wall_clock",
                  "flakes", "environment", "tally", "evidence_from"):
            if k in self.header:
                out.append(f"# {k}\t{self.header[k]}")
        out.append("\t".join(COLUMNS))
        for r in sorted(self.rows, key=lambda r: (r.verdict == "PASS", r.test)):
            out.append("\t".join((
                r.test, r.verdict, r.stability,
                "-" if r.seconds is None else f"{r.seconds:.2f}",
                "-" if r.exit_code is None else str(r.exit_code),
                "-" if r.asserts_pass is None else str(r.asserts_pass),
                "-" if r.asserts_fail is None else str(r.asserts_fail),
                "-" if r.markers is None else str(r.markers),
                "-" if r.script_errors is None else str(r.script_errors),
                r.failing or "-",
                "-" if r.device_lost is None else str(r.device_lost))))
        return "\n".join(out) + "\n"


def _num(cell, cast=int):
    return None if cell == "-" else cast(cell)


def parse_register(src) -> Register:
    """Read back what `render` wrote. The file is the interface `diff` consumes."""
    text = src if isinstance(src, str) and "\n" in src else pathlib.Path(src).read_text()
    header, rows, cols = {}, [], None
    for line in text.splitlines():
        if line.startswith("#"):
            body = line[1:].strip()
            if "\t" in body:
                k, v = body.split("\t", 1)
                header[k.strip()] = v.strip()
            continue
        if not line.strip():
            continue
        cells = line.split("\t")
        if cols is None:
            cols = cells
            continue
        cells += ["-"] * (len(COLUMNS) - len(cells))
        rows.append(Row(cells[0], cells[1], cells[2], _num(cells[3], float),
                        _num(cells[4]), _num(cells[5]), _num(cells[6]),
                        _num(cells[7]), _num(cells[8]), cells[9],
                        _num(cells[10])))
    return Register(header, rows)


# --- evidence, from the per-test logs -----------------------------------------

FAIL_TEXT_RE = re.compile(r'\[FAIL\][ \t]*(.*)')

# RULE 5 — A DEVICE THAT NEVER CAME UP IS EVIDENCE, NEVER A VERDICT.
#
# Measured on #547's register run. `GPUArenaTest` on a box with 843 MiB of free
# VRAM: the engine's display device came up, the TEST's own `RenderingDevice` did
# not, and 5,698 `Only local devices can submit and sync.` errors followed — not
# one compute dispatch reached the GPU. The scene then printed
# `[PASS] Arena combat resolved - Team 1 won` and `tests/lib/verdict.sh` scored it
# PASS, CORRECTLY: a marker is what a verdict is read from, and re-reading the log
# to score would undo rules 7 and 9 (see rule 1 in the module docstring).
#
# So this does not rescore. It counts, in an evidence column, because every other
# column on that row read clean — 0 SCRIPT ERRORs, 1 marker, no failing assertion
# names — and a reader of the artifact had nothing to go on.
#
# ⚠️ THIS IS #526'S SIBLING AND NOT #526. There the engine never started
# (`Unable to create DisplayServer`), the row scored NO_VERDICT, and the error is
# a false RED. Here the engine started, the test's own device did not, and the row
# scores PASS — a false GREEN, which no denominator protects you from. Both shapes
# land in this one column: the question it answers is `did this run happen on a
# working device`, and the end of startup it failed at is a detail.
DEVICE_LOST_RE = re.compile(
    r"^ERROR: (?:Couldn't create Vulkan device"
    r"|Couldn't initialize Vulkan device"
    r"|Unable to create DisplayServer)", re.M)


def device_losses(stem: str, log_dirs) -> int:
    """How many of the scanned log dirs show this test's device failing to come up.

    Scanned across EVERY repeat's log dir, unlike the other evidence columns,
    which are the first run's. The column has to pair with `stability`, which is
    read across all repeats: a device lost in repeat 2 and not repeat 1 is exactly
    the contamination that manufactures a FLAKY row, and a scan of the first dir
    only would miss the case the column exists for.

    None — not 0 — when no repeat left a log for the stem. A `0` there would claim
    a scan that never happened, which is the same error `UNMEASURED×1` exists to
    refuse one column to the left.
    """
    seen = False
    n = 0
    for d in log_dirs:
        f = pathlib.Path(d) / f"{stem}.log"
        if not f.exists():
            continue
        seen = True
        if DEVICE_LOST_RE.search(f.read_text(errors="replace")):
            n += 1
    return n if seen else None


def evidence(stem: str, log_dir: pathlib.Path):
    """(asserts_pass, asserts_fail, markers, script_errors, failing) or Nones.

    READ ONLY FOR A TEST THIS RUN ACTUALLY REACHED — see `take`. `tests/logs/` is
    tracked and nothing marks it stale, so a log left behind by a run four commits
    ago sits there looking exactly like a fresh one.
    """
    p = pathlib.Path(log_dir) / f"{stem}.log"
    if not p.exists():
        return None, None, None, None, "-"
    t = p.read_text(errors="replace")
    ap = af = None
    for m in ftb.COUNT_RE.finditer(t):
        ap = (ap or 0) + int(m.group(1))
        af = (af or 0) + int(m.group(2))
    markers = len(ftb.MARKER_RE.findall(t))
    errs = len(re.findall(r'^[ \t]*SCRIPT ERROR', t, re.M))
    names = []
    for m in FAIL_TEXT_RE.finditer(t):
        s = m.group(1).strip().replace("\t", " ")
        # A test's own AGGREGATE marker is `[FAIL] <StemName>`, and it is the
        # reason the row is red rather than a thing that failed. Listing it puts
        # the row's own `test` cell in its evidence column and pushes a real
        # assertion name off the end of the cap. Measured on the #454
        # demonstration: `CameraUnitsTest` printed three assertion failures and
        # then that fourth line.
        if s and s != stem and s not in names:
            names.append(s)
    extra = len(names) - MAX_FAILING
    failing = " | ".join(names[:MAX_FAILING]) or "-"
    if extra > 0:
        failing += f" | …and {extra} more"
    return ap, af, markers, errs, failing


# --- take ---------------------------------------------------------------------

def take(run_logs, log_dir=None) -> Register:
    """Read N runner stdouts of the SAME harness and tree into one register.

    `log_dir` is one path or a LIST of them, one per repeat. The evidence columns
    are still the FIRST dir's (`tests/logs` holds one generation of logs and the
    repeats overwrite each other, so they can only line up if you gave each repeat
    its own dir); `device_lost` is the exception and is scanned across all of them
    — see `device_losses`.
    """
    if log_dir is None:
        log_dirs = [pathlib.Path("tests/logs")]
    elif isinstance(log_dir, (str, pathlib.PurePath)):
        log_dirs = [pathlib.Path(log_dir)]
    else:
        log_dirs = [pathlib.Path(d) for d in log_dir]
    log_dir = log_dirs[0]
    runs = [parse_run(p) for p in run_logs]

    commits = {r.fields.get("code_commit", "UNKNOWN") for r in runs}
    if len(commits) > 1:
        raise ProvenanceError(
            "these run logs are not the same tree: "
            + ", ".join(f"{pathlib.Path(r.path).name}={r.fields.get('code_commit', 'UNKNOWN')}"
                        for r in runs)
            + ". Repeats are only repeats on one commit; a register merged across "
              "two is the provenance error #451's headline was built on.")

    observed = collections.defaultdict(list)
    for r in runs:
        for stem, v in r.verdicts.items():
            observed[stem].append(v)

    primary = runs[0]
    rows = []
    for stem in sorted(observed):
        verdict, stab = stability(observed[stem])
        secs = [r.seconds[stem] for r in runs if stem in r.seconds]
        ap, af, mk, er, failing = evidence(stem, log_dir)
        rows.append(Row(stem, verdict, stab,
                        round(sum(secs) / len(secs), 2) if secs else None,
                        primary.exits.get(stem), ap, af, mk, er, failing,
                        device_losses(stem, log_dirs)))

    reg = Register(_header(runs, rows, log_dirs), rows)
    return reg


def _header(runs, rows, log_dirs) -> dict:
    log_dir = log_dirs[0]
    primary = runs[0]
    f = primary.fields
    n_run = len(rows)
    produced = sum(1 for r in rows if r.verdict != "NO_VERDICT")
    # The tree half comes from the RUN's banner (`tools/harness_stamp.py`) and is
    # never re-derived here: the array grew by 275 entries in one commit, so a
    # coverage figure taken at read time would sit beside verdicts from before it.
    cov = f.get("test_coverage")
    cover = ((cov or "UNKNOWN scenes on disk — this log has no `test_coverage` "
                    "banner stamp (every archived run predates it)")
             + f" · {n_run} run · {produced} verdicts produced")

    timed = [r.seconds for r in rows if r.seconds is not None]
    if timed:
        ordered = sorted(timed)
        slowest = max(rows, key=lambda r: (r.seconds is not None, r.seconds or 0))
        wall = (f"{round(sum(timed), 1)} s total · mean {round(sum(timed)/len(timed), 1)} s "
                f"· median {round(ordered[len(ordered)//2], 1)} s "
                f"· slowest {slowest.test} {slowest.seconds} s "
                f"· {len(timed)}/{len(rows)} rows timed")
    else:
        wall = ("UNMEASURED — this run did not emit `  seconds` per test. Every "
                "archived run predates that line; a 0 here would read as an "
                "instant test and poison the budget.")

    n_rep = len(runs)
    n_flaky = sum(1 for r in rows if is_flaky(r.stability))
    if n_rep < 2:
        flakes = (f"UNMEASURED — 1 repeat. A single run cannot report a flake set, "
                  f"and `0` here would be a clean bill of health nothing measured. "
                  f"All {len(rows)} rows read UNMEASURED×1.")
    else:
        flakes = (f"{n_flaky} of {len(rows)} rows disagreed across {n_rep} repeats "
                  f"of the same harness on the same tree")

    lost = [r for r in rows if (r.device_lost or 0) > 0]
    named = ", ".join(f"{r.test}({r.verdict}\u00d7{r.device_lost})" for r in lost[:12])
    if len(lost) > 12:
        named += f", \u2026and {len(lost) - 12} more"
    environment = (
        f"{len(lost)} of {len(rows)} rows lost a rendering device in at least one "
        f"of the {len(log_dirs)} log dir(s) scanned"
        + (f" \u2014 {named}. A PASS here is a green taken with the GPU missing and "
           f"is not a statement about the code."
           if lost else
           ". Every scanned log shows the engine and the test's own "
           "RenderingDevice coming up."))

    tally = collections.Counter(r.verdict for r in rows)
    return {
        "code_commit": f.get("code_commit", "UNKNOWN"),
        "godot": f.get("godot", "UNKNOWN"),
        "runner": primary.runner,
        "taken_on": datetime.date.today().isoformat(),
        "repeats": str(n_rep),
        "addon_sync": f.get("addon_sync", "UNKNOWN — the runner did not stamp it"),
        "godot_cache": f.get("godot_cache", "UNKNOWN — the runner did not stamp it"),
        "coverage": cover,
        "wall_clock": wall,
        "flakes": flakes,
        "environment": environment,
        "tally": "  ".join(f"{k} {v}" for k, v in tally.most_common()),
        # ⚠️ ONE RUN'S EVIDENCE BESIDE N RUNS' VERDICT, AND THE HEADER SAYS SO.
        # Verdict and stability are read across every repeat; the assertion
        # counts, SCRIPT ERRORs, failing names and exit code are the FIRST run's,
        # because `tests/logs/` holds one generation of logs and the repeats
        # overwrite each other. Give each repeat its own `--log-dir` and point
        # `--log-dir` at the first if you want them to line up exactly.
        "evidence_from": (f"{log_dir} — the FIRST run log's per-test logs and exit "
                          f"codes. Verdict and stability are read across all "
                          f"{n_rep} repeat(s); the evidence columns are one run's."),
    }


# --- diff ---------------------------------------------------------------------

@dataclasses.dataclass
class Delta:
    test: str
    state: str
    a: str = "-"
    b: str = "-"
    seconds_delta: float = None
    reason: str = ""


def classify(stem, a: Row, b: Row) -> Delta:
    """One test's delta between two registers.

    THE ORDER IS THE SPEC, and it is the same refusal `diff_arm_verdicts.py`
    makes on the arm axis:

      MISSING      scored in one register and not the other. A coverage delta,
                   not a verdict delta — the array changed, or the run did.
      ENVIRONMENT  the two sides do not agree AND at least one of them was taken
                   with a rendering device that never came up. Read BEFORE flakiness
                   because it can be the CAUSE of it: a verdict measured with the
                   GPU missing is not a statement about the commit, so a difference
                   against it cannot be attributed to one. Two agreeing sides are
                   still SAME — both rows may be lies, but that is the register's
                   business and not the diff's, which answers `did this commit move
                   it`. #547; the sibling of #526.
      FLAKY        either side disagreed with ITSELF across its own repeats.
                   Settled BEFORE a move is considered: a verdict that was never
                   stable cannot have been moved by the commit under test. Read
                   first, so two `FLAKY` cells are never mistaken for agreement.
      SAME         same verdict, and neither side flaky.
      MOVED        different, and BOTH sides stable across ≥2 repeats. The finding.
      UNCONFIRMED  different, and at least one side saw it once. The repeat count
                   could not tell a mover from a coin flip. The remedy the word
                   names is more repeats, not silence.
    """
    if a is None or b is None:
        side = "b" if a is not None else "a"
        return Delta(stem, "MISSING", a.verdict if a else "-", b.verdict if b else "-",
                     None, f"absent from register {side}")

    d = None
    if a.seconds is not None and b.seconds is not None:
        d = round(b.seconds - a.seconds, 2)

    env = (a.device_lost or 0) + (b.device_lost or 0)
    disagree = (a.verdict != b.verdict
                or is_flaky(a.stability) or is_flaky(b.stability))
    if env and disagree:
        return Delta(stem, "ENVIRONMENT", a.verdict, b.verdict, d,
                     f"a rendering device never came up \u2014 device_lost "
                     f"a={a.device_lost} b={b.device_lost}. The box, not the commit.")
    if is_flaky(a.stability) or is_flaky(b.stability):
        return Delta(stem, "FLAKY", a.verdict, b.verdict, d,
                     f"unstable within its own repeats — a={a.stability} b={b.stability}")
    if a.verdict == b.verdict:
        return Delta(stem, "SAME", a.verdict, b.verdict, d, "")
    ra, rb = repeats_of(a.stability), repeats_of(b.stability)
    if (ra or 0) >= 2 and (rb or 0) >= 2:
        return Delta(stem, "MOVED", a.verdict, b.verdict, d,
                     f"stable {a.verdict}×{ra} then stable {b.verdict}×{rb}")
    return Delta(stem, "UNCONFIRMED", a.verdict, b.verdict, d,
                 f"differs, but repeats are a={ra} b={rb} — one run per side cannot "
                 f"tell a mover from a coin flip. Re-take with more repeats.")


DIFF_ORDER = ("MOVED", "UNCONFIRMED", "ENVIRONMENT", "FLAKY", "MISSING", "SAME")


def diff(a: Register, b: Register) -> list:
    stems = sorted(set(r.test for r in a.rows) | set(r.test for r in b.rows))
    out = [classify(s, a.row(s), b.row(s)) for s in stems]
    return sorted(out, key=lambda d: (DIFF_ORDER.index(d.state), d.test))


def diff_report(a: Register, b: Register) -> str:
    deltas = diff(a, b)
    tally = collections.Counter(d.state for d in deltas)
    ta = sum(r.seconds for r in a.rows if r.seconds is not None)
    tb = sum(r.seconds for r in b.rows if r.seconds is not None)
    out = [
        f"# suite_register diff — #454, map #450",
        f"# a\t{a.header.get('code_commit', 'UNKNOWN')}\t"
        f"repeats {a.header.get('repeats', '?')}\t{a.header.get('runner', '?')}",
        f"# b\t{b.header.get('code_commit', 'UNKNOWN')}\t"
        f"repeats {b.header.get('repeats', '?')}\t{b.header.get('runner', '?')}",
        f"# tally\t" + "  ".join(f"{k} {tally[k]}" for k in DIFF_ORDER if tally[k]),
        f"# wall_clock\t{round(ta, 1)} s -> {round(tb, 1)} s "
        f"({'+' if tb >= ta else ''}{round(tb - ta, 1)} s)",
        "#",
        "# MOVED is the finding. UNCONFIRMED means the repeat count could not tell a",
        "# mover from a coin flip — re-take with more repeats rather than reading it",
        "# as either. FLAKY was settled before a move was considered.",
        "test\tstate\ta\tb\tseconds_delta\treason",
    ]
    for d in deltas:
        if d.state == "SAME":
            continue
        out.append("\t".join((d.test, d.state, d.a, d.b,
                              "-" if d.seconds_delta is None else f"{d.seconds_delta:+.2f}",
                              d.reason)))
    return "\n".join(out) + "\n"


# --- cli ----------------------------------------------------------------------

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="verb", required=True)

    t = sub.add_parser("take", help="build a register from one or more run logs")
    t.add_argument("--run-log", action="append", required=True, type=pathlib.Path,
                   help="a runner's stdout; repeat for repeats of the SAME tree")
    t.add_argument("--log-dir", action="append", type=pathlib.Path, default=None,
                   help="where the per-test logs are (default: tests/logs). Repeat "
                        "it once per --run-log: the evidence columns come from the "
                        "FIRST, and `device_lost` is scanned across all of them.")
    t.add_argument("--out", type=pathlib.Path, default=None)

    d = sub.add_parser("diff", help="per-test verdict delta between two registers")
    d.add_argument("a", type=pathlib.Path)
    d.add_argument("b", type=pathlib.Path)

    args = ap.parse_args(argv)
    if args.verb == "take":
        missing = [p for p in args.run_log if not p.exists()]
        if missing:
            print(f"no such run log: {missing[0]}", file=sys.stderr)
            return 2
        try:
            reg = take(args.run_log, args.log_dir)
        except ProvenanceError as e:
            print(f"REFUSED: {e}", file=sys.stderr)
            return 2
        text = reg.render()
        if args.out:
            args.out.parent.mkdir(parents=True, exist_ok=True)
            args.out.write_text(text)
            print(f"wrote {args.out} ({len(reg.rows)} rows)", file=sys.stderr)
        else:
            sys.stdout.write(text)
        return 0

    a, b = parse_register(args.a), parse_register(args.b)
    sys.stdout.write(diff_report(a, b))
    return 0


if __name__ == "__main__":
    sys.exit(main())
