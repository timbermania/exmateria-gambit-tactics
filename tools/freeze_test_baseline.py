#!/usr/bin/env python3
"""Freeze the pre-move test baseline — which tests were ALREADY red (#401).

    uv run python tools/freeze_test_baseline.py --run-log <log> [--tsv] [--out <path>]

`refactor-loop.md` pass 6 moves code. After a move a red test is either *"the
move broke it"* or *"it was red on Friday"*, and by then that distinction is
unrecoverable — nobody re-runs the suite at the parent commit to find out. This
writes it down first. `docs/TEST-BASELINE-E2.tsv` is that record.

WHAT IT READS. `tests/run_all_tests.sh`'s own stdout, captured to a file, because
the runner's verdict rules are the authority on what PASS/FAIL/HUNG/NO_VERDICT
mean and re-deriving them here would be a second opinion nobody asked for. The
per-test `tests/logs/<Test>.log` files supply the two things the summary drops:
the ASSERTION COUNT and the `SCRIPT ERROR` lines.

WHY THE COUNT AND NOT THE VERDICT. A GDScript coroutine error and a stale call
arity each abort a test *silently* — the scene quits, the runner sees no `[FAIL]`
and scores PASS. So a green summary is not evidence the test RAN. Two tests
printing `[PASS]` where one used to print `11 passed` is the shape of that
failure, and it is invisible unless the count is written down. Every row carries
`asserts_pass`/`asserts_fail` where the test prints them, the `[PASS]`/`[FAIL]`
marker count where it does not, and `script_errors` always.

THE TWO SUBSETS. ADR-0153 dec. 2 moves four symbols (`ExMateriaEffectSfx`,
`BusLimiter`, `ExMateriaAudioEngine`, `SpuAudioDebugPanel`) and dec. 1 moves them into
`addons/exmateria_sound/`. The tests that bind either are the subset pass 6 must
diff, so they are marked in the register rather than re-derived per pass — and
they are derived by grep, here, so the marking cannot drift from the tree.

AND THE THIRD STATE IS `not-run`. It is not a formality: 21 of the 39 files that
bind a moving symbol or the addon are not in `run_all_tests.sh`'s list at all.
A test nobody runs cannot be diffed after the move, so `not-run` is the finding
this register exists to surface, not a gap in it.
"""
import sys, re, subprocess, pathlib, collections, datetime
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import _runner_tests

RUNNER = _runner_tests.RUNNER     # one definition of the path, beside the one reader
LOGS = pathlib.Path("tests/logs")
OUT = pathlib.Path("docs/TEST-BASELINE-E2.tsv")

# dec. 2's four moving symbols, and the addon itself. Needles, not a file list:
# the file list is derived from them so it cannot go stale against the tree.
MOVING = _runner_tests.MOVING     # ADR-0153 dec. 2's four moving symbols
ADDON = _runner_tests.ADDON

# A red needs a reason or an explicit `unknown`, so the list cannot quietly
# become an excuse later. Keyed here rather than hand-edited into the TSV, so
# regenerating the register preserves them and an unexplained red still prints
# `unknown`.
RED_REASONS = {
    # Filled by reading each red's log at capture. `unknown` is a legitimate
    # entry and stays visible; what is NOT allowed is a red with no line at all.
    # NONE of these are `Audio` driver failures — every one is recorded so that
    # after the move a red here is attributable to the day it was already red.
    "CursorTunablesTest":
        "pre-existing; shared cause with the two below — `on_update` "
        "(src/core/Tune.gd:542) is invoked with Nil, so `scrubbing <slug> "
        "live-updates` fails on the live-reapply half. ADR-0068 R3 territory, "
        "not Audio",
    "ScenarioWeatherTunablesTest":
        "pre-existing; same `Tune.gd:542` on_update Nil as CursorTunablesTest — "
        "one cause, three tests",
    "ScenarioDialogueBoxTunablesTest":
        "pre-existing; same `Tune.gd:542` on_update Nil as CursorTunablesTest",
    "EffectStudioSoundEditTest":
        "pre-existing. It was the only red in the moving/addon subset while only "
        "the 18 LISTED binders ran; running the other 21 put three more beside it "
        "(FedsInstrumentMeta, FedsNoteAudition, FedsPairEditorAcceptance) plus one "
        "HUNG, which is the finding, not this row. Ran fully — "
        "56 passed, 2 failed. Both reds are Effect Studio inspector re-derivation: "
        "the `_FakeInspector` test stub has no `name_column_width` "
        "(EffectStudioPage.gd:4445) and `FedsPairModel._track_view` indexes past a "
        "PackedInt32Array (:79). No Audio assertion in it fails",
    "EffectStudioFireDragWiringTest":
        "pre-existing; the inspector does not re-derive on a drag — the grab "
        "renders `{}` where a span ref is expected. Effects/studio, not Audio",
    "TweenTriggerProjectorTest":
        "pre-existing; palette tint projects `target_color` where the test wants "
        "`gradient_color`. Effects, not Audio; zero SCRIPT ERRORs",
    "GPUWeaponElementNoStatusTest":
        "pre-existing; `spell path did not register both hits`. Battle/GPU, not "
        "Audio; zero SCRIPT ERRORs",
    "SeekIntegrationTest":
        "pre-existing; `[FAIL] seek dispatches exactly one action: got=0 want=1` "
        "(log :19). WAS recorded `unknown` on the grounds that no per-assertion "
        "line existed — it did, indented two spaces, and only the tool's own "
        "anchored marker regex could not see it. Corrected, and the regex with "
        "it. Cutscene/seek, not Audio; zero SCRIPT ERRORs",
    "GPURangedCombatTest":
        "pre-existing; `[FAIL] ADR-0032: firer never entered "
        "LOGICAL_ACTIVITY_AWAITING_IMPACT`. Battle/GPU, not Audio; zero SCRIPT "
        "ERRORs",
    "GPUPhysicalAbilityTest":
        "pre-existing; the test declares its OWN timeout — `[GPU Physical Ability "
        "Test] TIMEOUT at tick 6007` — which the runner scores TIMEOUT via its "
        "`TIMEOUT at tick` rule, NOT the 360 s wall clock (it quit in under a "
        "minute). Battle/GPU, not Audio; zero SCRIPT ERRORs",
    "GPUStatusNoDamageTest":
        "pre-existing; `1/3 status no-damage tests failed`. Battle/GPU, not "
        "Audio; zero SCRIPT ERRORs",
    "GPUVerticalToleranceTest":
        "pre-existing; `Monk never entered MOVING_TO_CAST (vertical check may not "
        "have fired)`. Battle/GPU, not Audio; zero SCRIPT ERRORs",
    "ScenarioCameraFloorAimCalibTest":
        "pre-existing; 0 passed, 1 failed — a camera calibration datum. One of "
        "three sibling camera-calib reds. Cutscene/camera, not Audio",
    "ScenarioCameraVerticalDatumTest":
        "pre-existing; 0 passed, 1 failed — sibling of the two other camera-calib "
        "reds. Cutscene/camera, not Audio",
    "ScenarioWalkToAnimTest":
        "NOT A FAILURE. The test prints `=== ScenarioWalkToAnimTest: 16 passed, 0 "
        "failed ===` and then `RESULT: PASS`, and emits NO [PASS]/[FAIL] marker, "
        "so the runner's three verdict rules all miss and it scores NO_VERDICT. "
        "A runner/test convention mismatch. Recorded here because after the move "
        "a NO_VERDICT is indistinguishable from a break unless the register says "
        "which it was",
    "ScenarioVarWaitValueTest":
        "pre-existing; 19 passed, 3 failed — scenario VM var-wait. Cutscene, not "
        "Audio; zero SCRIPT ERRORs",
    "GambitScenarioRunnerTest":
        "pre-existing; `GambitScenarioRunner: 7 red verdict(s)` out of 92 markers. "
        "Cutscene/scenario, not Audio; zero SCRIPT ERRORs",
    "DamageNumberTrendTest":
        "pre-existing; `fade digit material not on the additive shader "
        "(feedback_hud_sprite_additive_fold.gdshader)`. Render/compositor-fold, "
        "not Audio; zero SCRIPT ERRORs",
    "DetailScreenLayoutTest":
        "pre-existing; `equipped-item ICONS mounted = 0, want 4 (real ITEM.BIN "
        "cells)`. UI3/Detail, not Audio; zero SCRIPT ERRORs",
    "EquipPickerFrameGroupTest":
        "pre-existing; `picker quad count drifted: observed 52 vs golden 55` "
        "(:166). A golden-multiset drift. UI3/Equip, not Audio; zero SCRIPT "
        "ERRORs. Its markers arrive via push_error as `ERROR: [FAIL] ...`",
    "EquipPickerTunablesTest":
        "pre-existing; `equipicker.rows.icon_x` and `.icon_dy` scrubs `did not "
        "move the screen` (_expect, :226). ADR-0068 tunables territory — a FOURTH "
        "red in that family, and the symptom differs from the `Tune.gd:542` Nil "
        "the other three share, so do not fold it into that one cause. UI3/Equip, "
        "not Audio",
    "FormationEquipDeltaWiringTest":
        "pre-existing; the picker delta is computed against the wrong baseline — "
        "`initial picker delta ... wp = -4, expected 0`, then `Broad Sword over "
        "empty R.Hand: wp = 0, expected 4`, i.e. off by exactly one selection. "
        "UI3/Formation, not Audio; zero SCRIPT ERRORs",
    # --- the 21 UNLISTED binders, run by tools/run_unlisted_audio_binders.sh ---
    # 8 PASS, 3 FAIL, 9 NO_VERDICT, 1 HUNG. The non-verdicts are a RESULT, not a
    # failed run: nine of them are diagnostic/capture rigs that complete and print
    # a prose conclusion without ever emitting a [PASS]/[FAIL] marker, which is
    # the one thing the runner's three verdict rules cannot score.
    #
    # ⚠️ THESE NINE REASONS ARE WHY #463 EXISTS, AND THEY ARE THE SHAPE OF THE
    # PROBLEM, NOT ITS FIX. Every one of them was read and typed by a human, one
    # opens *"not a test —"* and closes *"NO_VERDICT is the right score"*, and
    # nothing forced the tenth rig to get a tenth entry. The reader now scores a
    # scene that declares `[NOT_A_TEST] <why>` as `NOT_A_TEST` — see
    # `tests/lib/verdict.sh`. All nine declare it as of #463, so a fresh run gives
    # them that verdict and this dict merely explains it.
    #
    # The strings below are LEFT AS WRITTEN. `docs/TEST-BASELINE-E2.tsv` is
    # extraction #2's frozen record of a run in which they really did score
    # NO_VERDICT, and rewriting the reasons would misdescribe the measurement the
    # register holds. Map #450 does not touch the frozen register.
    "FedsInstrumentMetaTest":
        "ENVIRONMENTAL, not code — 21 passed, 1 failed, and the one is `E001 feds "
        "bank loads`: `FedsBank: cannot open res://authored_effects/E001.feds.bin` "
        "(feds_bank.gd:37). `authored_effects/` is GITIGNORED (.gitignore:63) and "
        "this worktree holds E019's feds bank but not E001's. The verdict is a "
        "property of the CHECKOUT, not of the tree — see the header caveat",
    "FedsNoteAuditionTest":
        "ENVIRONMENTAL, not code — 46 passed, 1 failed, same single cause as "
        "FedsInstrumentMetaTest: the gitignored `authored_effects/E001.feds.bin` "
        "is absent from this worktree. One cause, two tests",
    "FedsPairEditorAcceptanceTest":
        "pre-existing and REAL — 53 passed, 1 failed: `unwinding fills the "
        "reserved span with ghost copies (×14 loop) — expected true`. Preceded by "
        "`[SKIP] pair 0 rendered no energy bands (transport busy / engine)`, so "
        "read it as possibly engine-timing-sensitive. IN THE SUBSET, and #400 "
        "names this file as prior art — nothing was running it. Zero SCRIPT ERRORs",
    "DeclickDebug":
        "not a test — a ground-truth seam tracer for the spacing=2 retrigger "
        "click. Runs to completion (`[declick-dbg] done`) and prints voice state "
        "rather than asserting. NO_VERDICT is correct",
    "RenderInGameAudio":
        "not a test — a render TOOL that requires `--feds=<path>` and "
        "`--out-dir=<dir>` and correctly refuses without them "
        "(`RenderInGameAudio: missing --feds=<path> or --out-dir=<dir>`, :33). "
        "NO_VERDICT is the right score for a tool invoked with no arguments",
    "RenderTypewriterOffline":
        "not a test — an offline typewriter render tool for by-ear A/B iteration. "
        "Completes (`[tw-offline] done`) and writes WAVs for a human to compare",
    "RenderTypewriterOnline":
        "not a test — the LIVE capture counterpart to RenderTypewriterOffline. "
        "Completes (`wrote online_30hz_3ms.wav | underruns=0 peak=0.966FS`)",
    "SfxLiveStressTest":
        "not a test — a live SFX stress rig. Completes (`[live] done`) printing "
        "engine telemetry (skips=0, q_under=9, active=15) with no assertion",
    "SfxPopDiagTest":
        "not a test — a limiter/pop diagnostic. Completes, printing raw_peak and "
        "limiter gain steps for a human to read",
    "TypewriterClickCapture":
        "not a test — a capture rig for the periodic typewriter click hunt. It "
        "declares itself green IN PROSE (`[tw-capture] PASS: no live underruns`) "
        "without a [PASS] marker, so the runner cannot score it",
    "TypewriterClickTest":
        "HUNG at the 360 s timeout — a standalone A/B rig for the retrigger "
        "de-click with no exit condition; it was still printing engine telemetry "
        "when killed. Named `*Test` but it is a rig, not an assertion",
    "TypewriterCollisionProbe":
        "not a test — a deterministic offline probe for the retrigger-COLLISION "
        "hypothesis. Completes (`[collide] done.`) printing per-sample levels",
    "TypewriterGoldenDiff":
        "not a test — a differential rig. Completes with a prose verdict "
        "(`VERDICT: live mix == golden. The limiter/combine is INNOCENT -> click "
        "is threading/timing`) and no marker",
}


# Both were defined here and re-implemented in run_unlisted_audio_binders.sh; they
# now live in _runner_tests.py so the register and the runner cannot disagree about
# which tests are the subset. Re-exported under their old names — this file's own
# callers are unchanged.
runner_tests = _runner_tests.runner_tests
binders = _runner_tests.binders


def verdicts(run_log: pathlib.Path) -> dict[str, str]:
    """`[i/n] Running X...` followed by `  -> RESULT`, in order."""
    v, cur = {}, None
    for line in run_log.read_text(errors="replace").splitlines():
        m = re.match(r'^\[\d+/\d+\] Running (\S+)\.\.\.', line)
        if m:
            cur = m.group(1)
            continue
        m = re.match(r'^  -> (\w+)$', line)
        if m and cur:
            v[cur] = m.group(1)
            cur = None
    return v


COUNT_RE = re.compile(r'===\s*\S+:\s*(\d+)\s+passed,\s*(\d+)\s+failed\s*===')
# UNANCHORED, because the RUNNER's rule is unanchored (`grep -q "\[FAIL\]"`) and
# the runner is the authority this tool defers to. An anchored `^\[(PASS|FAIL)\]`
# under-read 17 of 413 logs, because a test that emits its markers through
# `push_error` gets them on stderr as `ERROR: [FAIL] X`, and the per-assertion
# markers are indented. `GambitScenarioRunnerTest` read 1 where the truth is 92.
#
# That is not a cosmetic undercount. For a narrative test the marker tally is the
# ONLY count in the row, so an anchored read prints `0` for a test that asserted
# ninety-two times — the register's own evidence column reporting the silence it
# was built to detect. It also MANUFACTURED a finding: `SeekIntegrationTest` was
# recorded `unknown` on the grounds that its log held "a bare [FAIL] with no
# per-assertion line above it", and the line was there all along, indented two
# spaces at :19 (`seek dispatches exactly one action: got=0 want=1`).
MARKER_RE = re.compile(r'\[(?:PASS|FAIL)\]')
# Some tests print a verdict the runner does not recognise. `ScenarioWalkToAnimTest`
# ends `RESULT: PASS` after `16 passed, 0 failed` and emits NO marker at all, so
# the runner scores it NO_VERDICT — a GREEN test filed as a non-verdict. Captured
# so the row can say which it is instead of leaving a reader to guess after the move.
RESULT_RE = re.compile(r'^RESULT:\s*(PASS|FAIL)\s*$', re.M)


def counts(stem: str):
    """(asserts_pass, asserts_fail, markers, script_errors, result_line).

    `asserts_*` come from the `=== Name: N passed, M failed ===` line the counted
    tests print. The narrative tests print only `[PASS] <sentence>`, so for those
    the marker tally is the only count there is and it is reported as such — a
    dash in the assert columns is *"this test does not count itself"*, not zero.
    """
    p = LOGS / f"{stem}.log"
    if not p.exists():
        return None
    t = p.read_text(errors="replace")
    ap = af = None
    for m in COUNT_RE.finditer(t):
        ap = (ap or 0) + int(m.group(1))
        af = (af or 0) + int(m.group(2))
    markers = len(MARKER_RE.findall(t))
    errs = len(re.findall(r'^SCRIPT ERROR', t, re.M))
    rm = RESULT_RE.search(t)
    return ap, af, markers, errs, (rm.group(1) if rm else None)


# --- the runner provenance field ---------------------------------------------
# #453 adopts a second arm, so `bash tests/run_all_tests.sh  sequential, never
# parallel` stopped being a fact about the register and became a hardcoded claim
# that a parallel capture would have inherited unchallenged. Both runners print
# a banner naming themselves and their concurrency, so the field is READ from the
# stdout being frozen. A log with no banner says UNKNOWN: the old line named
# `run_unlisted_audio_binders.sh` for the second log, which was true of the
# 2026-08-22 capture and unfalsifiable for every other one.
PARALLEL_TITLE = "GPU Combat Test Suite — PARALLEL"
SEQUENTIAL_TITLE = "GPU Combat Test Suite"
PARALLEL_RE = re.compile(r"Running \d+ tests, (\d+) workers, (\d+) in the sequential lane")
FIRST_TEST_RE = re.compile(r"^\[\d+/\d+\] Running ")


def _banner(path):
    """The runner's own two-line title block, or None.

    NOT a line-count window: the sequential runner prints 27 pre-flights first,
    so its banner is hundreds of lines in and a `head` would miss it entirely.
    The bound that IS in the format is the first `[1/N] Running` line — the
    banner always precedes it and no test output can. Within that preamble the
    match is anchored across TWO consecutive lines, title then `Running N
    tests`, so a scene echoing one of them cannot restate the provenance.
    """
    prev = None
    with pathlib.Path(path).open(errors="replace") as fh:
        for line in fh:
            if FIRST_TEST_RE.match(line):
                return None
            if prev is not None and line.lstrip().startswith("Running "):
                title = prev.strip()
                if title in (PARALLEL_TITLE, SEQUENTIAL_TITLE):
                    return title, line
            prev = line
    return None


def runner_provenance(run_logs):
    """(command, property) for the `# runner` header, derived per log."""
    cmds, props = [], []
    for lg in run_logs:
        found = _banner(lg)
        m = PARALLEL_RE.search(found[1]) if found else None
        if found and found[0] == PARALLEL_TITLE and m:
            cmds.append(f"uv run python tools/run_tests_parallel.py -N {m.group(1)}")
            props.append(f"parallel N={m.group(1)}, "
                         f"{m.group(2)} in the sequential lane")
        elif found and found[0] == SEQUENTIAL_TITLE:
            cmds.append(f"bash {RUNNER}")
            props.append("sequential")
        else:
            cmds.append("UNKNOWN")
            props.append(f"no runner banner in {pathlib.Path(lg).name}")
    return " + ".join(cmds), "; ".join(props)


def main():
    run_logs = [pathlib.Path(sys.argv[i + 1]) for i, a in enumerate(sys.argv)
                if a == "--run-log" and i + 1 < len(sys.argv)]
    # `--out <path>` writes somewhere OTHER than the frozen pre-move register.
    # Without it this tool can only overwrite `docs/TEST-BASELINE-E2.tsv`, and
    # that file is the PRE-move measurement extraction #2 is scored against —
    # re-running --tsv over it destroys the number the comparison needs, which
    # is exactly what tools/check_test_baseline.py exists to forbid. A post-move
    # capture therefore goes to its own file and is read as a DIFF against the
    # frozen one, never as a replacement for it.
    out_path = next((pathlib.Path(sys.argv[i + 1]) for i, a in enumerate(sys.argv)
                     if a == "--out" and i + 1 < len(sys.argv)), OUT)
    if not run_logs or not all(p.exists() for p in run_logs):
        sys.exit("--run-log <file> is required (stdout of `bash tests/run_all_tests.sh`); "
                 "repeatable, for the unlisted binders run separately")

    suite = runner_tests()
    binds = binders()
    verd = {}
    for lg in run_logs:
        verd.update(verdicts(lg))

    godot = subprocess.run(["godot", "--version"], capture_output=True, text=True).stdout.strip()
    sha = subprocess.run(["git", "rev-parse", "--short", "HEAD"],
                         capture_output=True, text=True).stdout.strip()
    # The register's OWN output is excluded from the dirty check. Writing the file
    # makes the tree dirty by construction, so counting it would stamp
    # `WORKING TREE DIRTY` on every capture and the marker would stop meaning
    # anything — the failure mode ADR-0145 dec. 1 found in a number that moved
    # five times with no code change. Everything else still counts.
    _st = subprocess.run(["git", "status", "--porcelain"],
                         capture_output=True, text=True).stdout.splitlines()
    dirty = "\n".join(l for l in _st if out_path.name not in l).strip()

    # Every test the runner lists, plus every binder it does NOT list.
    rows = []
    for stem in suite:
        rows.append((stem, "yes", verd.get(stem, "NOT-REACHED")))
    # The binders the runner does not list are run SEPARATELY (see the docstring):
    # `not-listed` is what nothing ran, a real verdict is what a separate run gave.
    for stem in sorted(set(binds) - set(suite)):
        rows.append((stem, "no", verd.get(stem, "not-listed")))

    out = []
    for stem, in_suite, v in rows:
        # A per-test log is read ONLY if THIS run produced a verdict for it.
        # `tests/logs/` is not cleared between runs, so a stale log from a
        # previous session sits there looking exactly like a fresh one — reading
        # it would put July's assertion count beside today's verdict, which is
        # the same class of error this whole register exists to prevent.
        c = counts(stem) if v not in ("NOT-REACHED", "not-listed") else None
        ap, af, mk, er, rl = c if c else (None, None, None, None, None)
        b = "+".join(sorted(binds.get(stem, []))) or "-"
        reason = RED_REASONS.get(stem, "unknown") if v not in ("PASS",) else "-"
        # A READING, not a guess, and only where no hand-written reason exists: a
        # log with an unrecognised `RESULT:` line and no marker explains its own
        # non-verdict, and leaving that as `unknown` would hide the one case the
        # runner's verdict rules cannot express.
        if reason == "unknown" and mk == 0 and rl:
            reason = (f"the test prints `RESULT: {rl}` and NO [PASS]/[FAIL] marker, so "
                      f"the runner's rules score it {v} — the test itself reports "
                      f"{'green' if rl == 'PASS' else 'red'}"
                      + (f" ({ap} passed, {af} failed)" if ap is not None else "")
                      + ". A runner/test convention mismatch, not a failure")
        if v == "not-listed":
            reason = "not in tests/run_all_tests.sh's TESTS array — nothing runs it"
        elif v == "NOT-REACHED":
            reason = "the captured run did not reach it (incomplete run)"
        out.append((stem, in_suite, b, v,
                    "-" if ap is None else str(ap),
                    "-" if af is None else str(af),
                    "-" if mk is None else str(mk),
                    "-" if er is None else str(er), reason))
    out.sort(key=lambda r: (r[3] == "PASS", r[0]))

    tally = collections.Counter(r[3] for r in out)
    sub = [r for r in out if r[2] != "-"]
    runner_cmd, runner_prop = runner_provenance(run_logs)
    subtally = collections.Counter(r[3] for r in sub)

    def render(fh):
        w = fh.write
        if out_path == OUT:
            w(f"# The pre-move test baseline for extraction #2 (`Audio`) — #401, ADR-0153.\n")
        else:
            w(f"# A POST-move test capture for extraction #2 (`Audio`) — #401, ADR-0153.\n")
            w(f"# NOT a re-freeze. Read as a DIFF against docs/TEST-BASELINE-E2.tsv, which\n")
            w(f"# stays frozen at the pre-move commit it measures. See check_test_baseline.py.\n")
        w(f"# GENERATED by tools/freeze_test_baseline.py --tsv. Never hand-edit.\n")
        w(f"# code_commit\t{sha}{'  (WORKING TREE DIRTY at capture)' if dirty else ''}\n")
        w(f"# godot\t{godot}\t4.8 compositor fork only; stock 4.7 numbers are not comparable\n")
        w(f"# runner\t{runner_cmd}\t{runner_prop}\n")
        w(f"# taken_on\t{datetime.date.today().isoformat()}\n")
        w(f"# suite_size\t{len(suite)}\ttests in the runner's TESTS array\n")
        # ADR-0194 dec. 10. A NUMBER THAT MOVES ALONE IS A NUMBER NOBODY CAN
        # AUDIT: `suite_size` fell from 692 to 684 because eight tests moved into
        # the addons they guard, not because eight stopped being run. Both counts
        # in the same file, beside each other, so the drop and the rise are one
        # reading. Derived from the tree by `_runner_tests`, never stored — the
        # 410 that went stale in six docstrings on this very branch is what a
        # recorded number does.
        _rigs, _owned = _runner_tests.stranger_rigs(), _runner_tests.addon_owned_tests()
        w(f"# stranger\t{len(_rigs)} rig(s), {len(_owned)} addon-owned test(s)\t"
          f"tests/stranger/*/run.sh — NOT in the array above (ADR-0194 dec. 4: running "
          f"them as res://tests/X.tscn would run them in the project whose absence is "
          f"the claim). suite_size + these = every test this repo has\n")
        w("# tally\t" + "  ".join(f"{k} {v}" for k, v in tally.most_common()) + "\n")
        w(f"# subset\t{len(sub)}\tfiles binding a dec. 2 moving symbol or the addon — "
          + "  ".join(f"{k} {v}" for k, v in subtally.most_common()) + "\n")
        w(f"# binds\tmoving = {' / '.join(MOVING)}\taddon = {' / '.join(ADDON)}\n")
        w("# caveat\tTWO ROWS ARE A PROPERTY OF THIS CHECKOUT, NOT OF THE TREE.\n")
        w("# caveat\tFedsInstrumentMetaTest and FedsNoteAuditionTest each fail ONE assertion\n")
        w("# caveat\tbecause `authored_effects/E001.feds.bin` is absent — that directory is\n")
        w("# caveat\tGITIGNORED (.gitignore:63) and this worktree holds E019's feds bank and\n")
        w("# caveat\tnot E001's. A worktree that has it may score them PASS. So a diff of\n")
        w("# caveat\tthose two rows after the move measures the CHECKOUT unless it is taken\n")
        w("# caveat\ton the same one. Stated rather than silently frozen.\n")
        w("# note\tA GREEN SUMMARY IS NOT A RUN. A coroutine error or a stale call arity\n")
        w("# note\taborts a test silently, so `asserts_pass` and `script_errors` are the\n")
        w("# note\tevidence, not the verdict. `-` in an assert column means the test does\n")
        w("# note\tnot count itself and `markers` is the only count it has — never zero.\n")
        w("test\tin_suite\tbinds\tverdict\tasserts_pass\tasserts_fail\tmarkers\tscript_errors\treason\n")
        for r in out:
            w("\t".join(r) + "\n")

    render(sys.stdout)
    if "--tsv" in sys.argv:
        with out_path.open("w") as fh:
            render(fh)
        print(f"\nwrote {out_path} ({len(out)} rows)", file=sys.stderr)


if __name__ == "__main__":
    main()
