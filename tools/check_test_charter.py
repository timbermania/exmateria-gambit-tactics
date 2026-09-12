#!/usr/bin/env python3
"""Guard: the MECHANICAL half of the test charter — docs/TEST-CHARTER.md.

    uv run python tools/check_test_charter.py            # exit 1 on a violation
    uv run python tools/check_test_charter.py --seed     # rewrite the allowlist
    uv run python tools/check_test_charter.py --stats    # burn-down, no verdict

THE CHARTER HAS FOURTEEN CLAUSES AND THIS FILE ENFORCES FIVE. That is not a gap
being hidden: `docs/TEST-CHARTER.md` marks every clause (G) or (J), and the nine
(J) clauses are judgement calls audited by `.claude/skills/test-audit-loop` one
test at a time. A guard that pretended to check "loads only what it asserts on"
would be a heading that reads as enforced and checks nothing, which is the exact
failure `check_guard_registry.py` was built for.

THE FIVE, and why each one is greppable where its neighbours are not:

  C1  KIND DECLARED  — `# test-kind: <base>[ lane-pinned]`, base one of
      static-guard / logic / render / gpu / stranger-rig / perf. The whole
      demote-to-a-cheaper-kind verdict needs a written starting point; without
      it "is this really a gpu test?" has no prior and every audit re-derives it.
  C4  QUITS ITSELF   — the file calls `.quit()` somewhere. The runner passes NO
      `--quit-after`: a test that does not quit is killed by `timeout(1)` at 360 s
      and scored HUNG. Measured at 77cf2c62e: 777 of 794 files under tests/
      already do this, so the ratchet starts nearly closed.
  C10 CAN FAIL       — `# seeded-break: <what to break to red this test>`. This
      repo has been bitten by unfailable tests repeatedly (#421's guard could not
      fail; an arm that asked the subject for its own flag passed a seeded
      defect). The audit loop seeds a break on every test it touches anyway, so
      this column fills itself in as the burn-down runs.
  C14a NO SLEEPS     — no `create_timer(` under tests/. A duration is a bet about
      how busy the box is. See tests/lib/await_until.gd.
  C14b NO WALL CLOCK — no `Time.get_ticks_*` / `Time.get_unix_time*` /
      `OS.get_ticks_*` unless the declared kind is `perf`. A perf test is
      EXEMPT AND AUTOMATICALLY LANE-PINNED, because a real-time measurement taken
      under N=8 parallel load is not a measurement (SpuClippingMetricsTest read
      2/3 FAIL interleaved and PASS solo, on the same tree).

THE ALLOWLIST MAY ONLY SHRINK. `tests/charter_allowlist.tsv` carries every
violation that already existed when the charter landed. A row whose violation is
GONE is itself reported as an error, so the list cannot rot into a permanent
exemption — the same ratchet `check_adr_shape.py`'s BURN_DOWN uses, for the same
reason. `--seed` rewrites it and is for the initial landing only; running it to
make a red go away is how the ratchet gets defeated.

WHAT COUNTS AS A TEST. The runner's own array, read through
`_runner_tests.runner_tests()` — never a fresh glob. Three tools already read that
array and a fourth reading is how they start to disagree about which scenes exist
(the census that said 740 while the tree held 744). Stems the array names but the
tree does not hold under tests/ are reported as `MISSING`, not skipped silently:
eight tests moved into their addons under ADR-0194 and a guard that quietly
ignored them would go blind exactly when one came home.

Pure stdlib. Run from the package root.
"""
import argparse
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import _runner_tests

ROOT = pathlib.Path(__file__).resolve().parent.parent
TESTS_DIR = ROOT / "tests"
ALLOWLIST = ROOT / "tests" / "charter_allowlist.tsv"

BASE_KINDS = ("static-guard", "logic", "render", "gpu", "stranger-rig", "perf")
MODIFIERS = ("lane-pinned",)

KIND_RE = re.compile(r"^#\s*test-kind:\s*(?P<kinds>[a-z\- ]+?)\s*$", re.M)
SEEDED_RE = re.compile(r"^#\s*seeded-break:\s*(?P<what>\S.*?)\s*$", re.M)
QUIT_RE = re.compile(r"\.quit\s*\(")
TIMER_RE = re.compile(r"create_timer\s*\(")
CLOCK_RE = re.compile(r"\b(?:Time\.get_ticks_\w+|Time\.get_unix_time\w*|OS\.get_ticks_\w+)\b")

# The clause ids this file scores, in report order. Kept as data so --stats and
# the allowlist reader cannot disagree with the checker about the name of a rule.
CLAUSES = ("C1", "C4", "C10", "C14a", "C14b")

CLAUSE_TEXT = {
    "C1": "no `# test-kind:` declaration (or an unknown kind)",
    "C4": "never calls .quit() — the runner has no --quit-after, so this is a 360 s HUNG",
    "C10": "no `# seeded-break:` line — nothing records that this test CAN fail",
    "C14a": "uses create_timer() — sleeps a real duration instead of awaiting a state",
    "C14b": "reads a wall clock (Time/OS ticks) outside a declared `perf` test",
}


def test_paths() -> list[tuple[str, pathlib.Path | None]]:
    """(stem, path-or-None) for every stem the runner's array names."""
    out = []
    for stem in _runner_tests.runner_tests(TESTS_DIR / "run_all_tests.sh"):
        p = TESTS_DIR / (stem + ".gd")
        out.append((stem, p if p.is_file() else None))
    return out


def declared_kind(src: str) -> tuple[str | None, list[str]]:
    """(base_kind, modifiers) from the header, or (None, []) if absent/invalid."""
    m = KIND_RE.search(src)
    if not m:
        return None, []
    tokens = m.group("kinds").split()
    if not tokens or tokens[0] not in BASE_KINDS:
        return None, []
    mods = [t for t in tokens[1:] if t in MODIFIERS]
    if len(mods) != len(tokens) - 1:
        return None, []          # an unknown modifier is a typo, not a kind
    return tokens[0], mods


def violations_for(stem: str, path: pathlib.Path | None) -> list[str]:
    """The clause ids `stem` violates. A MISSING file violates nothing — it is
    reported on its own channel, because 'the array names a file the tree does
    not hold' is a different fact from 'this test breaks a rule'."""
    if path is None:
        return []
    src = path.read_text(encoding="utf-8", errors="replace")
    bad = []
    kind, _mods = declared_kind(src)
    if kind is None:
        bad.append("C1")
    if not QUIT_RE.search(src):
        bad.append("C4")
    if not SEEDED_RE.search(src):
        bad.append("C10")
    if TIMER_RE.search(src):
        bad.append("C14a")
    if CLOCK_RE.search(src) and kind != "perf":
        bad.append("C14b")
    return bad


def read_allowlist() -> set[tuple[str, str]]:
    if not ALLOWLIST.is_file():
        return set()
    rows = set()
    for line in ALLOWLIST.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) >= 2:
            rows.add((parts[0].strip(), parts[1].strip()))
    return rows


def write_allowlist(rows: set[tuple[str, str]]) -> None:
    body = [
        "# tests/charter_allowlist.tsv — the test-charter violations that ALREADY",
        "# existed when docs/TEST-CHARTER.md landed. SHRINK-ONLY.",
        "#",
        "# A row here is a debt with a name on it, not an exemption. Two rules:",
        "#   * A NEW violation not listed here fails the pre-flight. Fix the test.",
        "#   * A row whose violation is GONE also fails, and the fix is to delete",
        "#     the row. That is what stops the list rotting into a permanent",
        "#     carve-out, and it is why there is no --unseed.",
        "#",
        "# `.claude/skills/test-audit-loop` deletes rows as it audits. The row count",
        "# is the burn-down: `uv run python tools/check_test_charter.py --stats`.",
        "#",
        "# test\tclause\twhat the clause says",
    ]
    for stem, clause in sorted(rows):
        body.append(f"{stem}\t{clause}\t{CLAUSE_TEXT[clause]}")
    ALLOWLIST.write_text("\n".join(body) + "\n", encoding="utf-8")


def scan() -> tuple[set[tuple[str, str]], list[str]]:
    """(current violations, stems the array names that the tree does not hold)."""
    live, missing = set(), []
    for stem, path in test_paths():
        if path is None:
            missing.append(stem)
            continue
        for clause in violations_for(stem, path):
            live.add((stem, clause))
    return live, missing


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--seed", action="store_true",
                    help="rewrite the allowlist from the current tree (landing only)")
    ap.add_argument("--stats", action="store_true",
                    help="print the burn-down and exit 0 without a verdict")
    args = ap.parse_args()

    live, missing = scan()

    if args.seed:
        write_allowlist(live)
        print(f"seeded {ALLOWLIST.relative_to(ROOT)} with {len(live)} rows "
              f"across {len({s for s, _ in live})} tests")
        return 0

    allowed = read_allowlist()
    total = len(test_paths())

    if args.stats:
        print(f"check_test_charter — burn-down over {total} tests in the array")
        for clause in CLAUSES:
            n = len([1 for _, c in live if c == clause])
            print(f"  {clause:<5} {n:>4} violating   {CLAUSE_TEXT[clause]}")
        print(f"  {'':<5} {len(live):>4} rows total, {len(allowed)} allowlisted")
        if missing:
            print(f"  {'':<5} {len(missing):>4} stems named by the array, absent under tests/")
        return 0

    new = sorted(live - allowed)
    stale = sorted(allowed - live)

    if new:
        print(f"🔴 {len(new)} NEW test-charter violation(s) — docs/TEST-CHARTER.md\n")
        for stem, clause in new:
            print(f"  {stem}  [{clause}]  {CLAUSE_TEXT[clause]}")
        print("\n  Fix the test. Adding a row to tests/charter_allowlist.tsv is not")
        print("  the fix — that list is seeded once and only ever shrinks.")
    if stale:
        print(f"\n🟡 {len(stale)} allowlist row(s) whose violation is GONE — delete them:\n")
        for stem, clause in stale:
            print(f"  {stem}\t{clause}")
        print("\n  A ratchet that keeps fixed rows stops being a burn-down.")
    if missing:
        print(f"\n⚠️  {len(missing)} stem(s) the array names with no tests/<stem>.gd:")
        print("     " + ", ".join(missing[:8]) + (" …" if len(missing) > 8 else ""))
        print("     (ADR-0194 moved eight tests into their addons; that is expected.)")

    if new or stale:
        return 1
    print(f"✅ check_test_charter: {total} tests, {len(allowed)} known violations "
          f"outstanding, none new.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
