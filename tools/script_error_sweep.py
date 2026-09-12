#!/usr/bin/env python3
"""Which tests threw, what they threw, and whether the throw is stable — #462, map #450.

WHY THIS EXISTS. `tests/lib/verdict.sh` rule 7 scores a green test THREW when the
engine threw under it. That rule answers *whether*; this answers *what*, which is
what you need to fix one. Point it at the merged stdout of a full run (or several)
and it reports, per test: the verdict, the SCRIPT ERROR count, and every distinct
error message with its `at:` provenance and multiplicity.

READ THE RUN LOG, NOT `tests/logs/`. That directory is not cleared between runs, so
a stale per-test log sits there looking exactly like a fresh one. The merged stdout
carries its own `[i/n] Running X...` framing and cannot be stale relative to itself.

WHAT IT FOUND. On all five archived full runs, 13 tests emit SCRIPT ERROR lines and
ALL 13 score PASS — no red test throws at all. The counts are stable to the unit
across runs (`CameraFeelTunablesTest`: 5,322 every time), so these are defects, not
flakes. Two tests VARY by exactly the amount a fixed test stopped throwing, which is
the signal this tool exists to keep visible.

    uv run python tools/script_error_sweep.py <run.log> [<run.log> ...]

The LAST log given is the one profiled; any earlier ones are used only for the
across-runs stability column.
"""
import collections
import re
import sys

START = re.compile(r'^\[(\d+)/(\d+)\] Running (\S+)\.\.\.')
VERDICT = re.compile(r'^  -> (\w+)$')
COUNTS = re.compile(r'===\s*\S+:\s*(\d+)\s+passed,\s*(\d+)\s+failed\s*===')
# Anchored exactly as the verdict reader anchors it, and for the same reason: this
# is the engine's own line-start emission, not a marker a test prints.
SCRIPT_ERROR = re.compile(r'^\s*SCRIPT ERROR:\s*(.*)$')
AT = re.compile(r'^\s*at:\s*(.*)$')


def parse(path):
    """{test_name: {verdict, n_err, errs: Counter[(msg, at)], asserts_pass/fail}}."""
    out, current, buf = {}, None, []

    def flush(name, lines):
        text = "\n".join(lines)
        ap = af = None
        for m in COUNTS.finditer(text):
            ap = (ap or 0) + int(m.group(1))
            af = (af or 0) + int(m.group(2))
        errs = collections.Counter()
        for i, line in enumerate(lines):
            m = SCRIPT_ERROR.match(line)
            if not m:
                continue
            # The `at:` line follows the message, sometimes after a backtrace header.
            at = ""
            for j in range(i + 1, min(i + 4, len(lines))):
                a = AT.match(lines[j])
                if a:
                    at = a.group(1).strip()
                    break
            errs[(m.group(1).strip(), at)] += 1
        out[name] = {"verdict": None, "errs": errs, "n_err": sum(errs.values()),
                     "asserts_pass": ap, "asserts_fail": af}

    for raw in open(path, errors="replace"):
        line = raw.rstrip("\n")
        m = START.match(line)
        if m:
            if current:
                flush(current, buf)
            current, buf = m.group(3), []
            continue
        m = VERDICT.match(line)
        if m and current:
            flush(current, buf)
            out[current]["verdict"] = m.group(1)
            current, buf = None, []
            continue
        if current is not None:
            buf.append(line)
    if current:
        flush(current, buf)
    return out


def main(paths):
    if not paths:
        print(__doc__)
        return 2
    runs = [(p.split("/")[-1], parse(p)) for p in paths]
    label, base = runs[-1]

    throwers = sorted((n for n, r in base.items() if r["n_err"] > 0),
                      key=lambda n: -base[n]["n_err"])
    by_verdict = collections.Counter(base[n]["verdict"] for n in throwers)

    print(f"=== {label}: {len(base)} tests, {len(throwers)} of them threw ===")
    print(f"    throwers by verdict: {dict(by_verdict)}")
    print(f"    total SCRIPT ERROR lines: {sum(base[n]['n_err'] for n in throwers)}\n")

    for name in throwers:
        r = base[name]
        print(f"{name}")
        print(f"    verdict={r['verdict']}  script_errors={r['n_err']}  "
              f"asserts={r['asserts_pass']} passed, {r['asserts_fail']} failed")
        if len(runs) > 1:
            trail = "  ".join(f"{rn.split('/')[-1][:18]}={rr[name]['n_err'] if name in rr else '-'}"
                              for rn, rr in runs)
            counts = [rr[name]["n_err"] for _, rr in runs if name in rr]
            print(f"    across runs: {trail}   [{'STABLE' if len(set(counts)) == 1 else 'VARIES'}]")
        for (msg, at), n in r["errs"].most_common():
            print(f"      x{n:<6}{msg}")
            if at:
                print(f"            at: {at}")
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
