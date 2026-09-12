#!/usr/bin/env python3
"""Guard: every `Vault: [[Note]]` anchor in walked source names a real vault note.

ADR-0111 dec. 7 as amended by #310 and built by ADR-0147 (loop pass 2 of
extraction #1). The anchor is the ONE part of the refactor's instrument that
must exist *before* the code it names is rewritten.

WHY, corrected 2026-08-22 (ADR-0154 dec. 1, extended by ADR-0153 dec. 8). This
docstring used to say "ADR-0112 makes each addon an **analog**, authored fresh".
ADR-0112 does not contain the words, and this file was the FIFTH site asserting
it against that citation and the only one inside an instrument. The reason that
does hold is ADR-0111 dec. 7's own: **a comment travels through any rename, move
or rewrite; an `R:` path citation in the vault does not** — 81 of the vault's 320
cited paths are already dead at trunk, and 70 of the 81 are one package rename
(`smd-player/` -> `exmateria-sound/`). The rule for HOW code leaves is ADR-0110
dec. 1 -- "Systems are lifted out of the host into addons" -- so an anchor on
moved code travels for free and the authoring cost is only on code that was never
anchored. A link that resolves is not a link that supports; that is the failure
this comment now records rather than repeats.

    uv run python tools/check_vault_anchors.py [--list]

WHAT IT ENFORCES — two rules, both about the marker and neither about coverage:

  1. **Every anchor resolves.** `Vault: [[X]]` must name a note that exists at
     `vault/X.md` on `main`. A rotted anchor is worse than no anchor: it reads as
     a live edge and pass 8 cannot tell "we dropped this" from "the note was
     renamed".
  2. **`Vault:` only ever appears in the anchor form.** A bare `Vault: Foo` is a
     typo that a coverage grep silently misses, so it is red here.

It does NOT enforce coverage. Adoption is per-extraction (#310), so a global
threshold would be red for months and deleted within a week — the same argument
ADR-0145 dec. 4 makes for `--delta`. Adoption is REPORTED, never asserted.

THE VAULT IS READ FROM `main`, NEVER FROM THE WORKTREE — `git ls-tree main
vault/`. Since the lines reconciled (ADR-0006) `main` carries the game line too,
so a worktree on `main` holds `vault/` as well; the rule stands anyway, because
the anchor's referent is what `main` has committed, not what a dirty or
mid-branch worktree happens to show. Never write to it.

The walk is `classify_blueprint.WALK_ROOTS` (ADR-0146 dec. 5), not a hard-coded
`src/` — an instrument that hard-codes where things live cannot survive things
moving, and every remaining pass moves things.

AND A SECOND ROOT, WHICH IS NOT A WALK ROOT (ADR-0153 dec. 8). Extraction #2
moves a system OUT of this package, into the canonical `exmateria-sound/`
sibling that dec. 1 keeps outside `WALK_ROOTS` on three grounds. The anchors
written into that tree would otherwise be the only anchors in the repo that
nothing checks — unguarded exactly where the walk cannot see them, which is
where an anchor is worth the most. So `_walk_roots.EXTRACTED` is scanned
too, and BOTH rules apply to it.

What it is NOT: it does not enter `WALK_ROOTS`, it does not feed the baseline,
and `closure.py`, `residue.py`, `asset_census.py`, `touch_matrix.py` and
`check_baseline.py` see no difference. The two trees are counted and printed
SEPARATELY, never summed — adoption is per-extraction, so one number over two
independently-versioned packages is a number nobody can act on. Coverage stays
REPORTED, never asserted, in both.

Verified safe on adoption: the canonical package held no `Vault:` string at all
when this root was added, so the guard could not go red on adoption it had not
been given.
"""
import sys, re, subprocess, io, contextlib, collections, pathlib

_ns = {"__name__": "cbmod"}
with contextlib.redirect_stdout(io.StringIO()):
    try:
        # classify_blueprint ends in sys.exit(); without this the guard prints
        # nothing and exits non-zero, which reads as a failure it never had.
        exec(open("tools/classify_blueprint.py").read(), _ns)
    except SystemExit:
        pass
walk, classify = _ns["walk"], _ns["classify"]
SOURCE_SUFFIXES = _ns["SOURCE_SUFFIXES"]

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import _walk_roots


def extracted_walk():
    """The second root's source files, same suffix rule as the walk.

    Yields `(display_path, package_name, path)`. `classify()` is deliberately not
    called: it answers "which BUCKET of this blueprint" and the answer for a file
    in another package is `None`, which would print as a hole rather than as what
    it is. The package name is the label.
    """
    _root = _walk_roots.PROJECT_DIR.parent
    for e in _walk_roots.extracted_roots():
        for q in sorted(e.path.rglob("*")):
            if q.is_file() and q.suffix in SOURCE_SUFFIXES:
                yield q.relative_to(_root).as_posix(), e.system, q

ANCHOR = re.compile(r'Vault:\s*\[\[([^\]]+)\]\]')
LOOSE = re.compile(r'Vault:(?!\s*\[\[)')


def vault_notes():
    """Note stems on `main`. The vault lives only there (ADR-0111); read-only."""
    out = subprocess.run(["git", "ls-tree", "-r", "--name-only", "main", "vault/"],
                         capture_output=True, text=True, cwd="..")
    if out.returncode != 0:
        print("FAIL: cannot read vault/ from `main`:", out.stderr.strip())
        sys.exit(1)
    return {pathlib.PurePosixPath(p).stem
            for p in out.stdout.split("\n") if p.endswith(".md")}


notes = vault_notes()
walked = collections.defaultdict(list)     # note -> [(file, bucket)]   WALK_ROOTS
extracted = collections.defaultdict(list)  # note -> [(file, system)]  _walk_roots.EXTRACTED
bad_ref, bad_form = [], []


def scan(rel, path, label, into):
    """Both rules, applied to one file. The rules do not know which tree they are
    in — that is the point of a second root; only the REPORTING is separated."""
    for i, line in enumerate(path.read_text(errors="ignore").splitlines(), 1):
        for m in ANCHOR.finditer(line):
            name = m.group(1).strip()
            into[name].append((rel, label))
            if name not in notes:
                bad_ref.append((rel, i, name))
        if LOOSE.search(line):
            bad_form.append((rel, i, line.strip()[:80]))


for f in walk():
    scan(f.as_posix(), f, classify(f.as_posix()), walked)
for rel, pkg, q in extracted_walk():
    scan(rel, q, pkg, extracted)

def report(title, table):
    files = {f for v in table.values() for f, _ in v}
    n = sum(len(v) for v in table.values())
    print(f"{title}: {n} in {len(files)} files, naming {len(table)} distinct notes")
    for b, k in collections.Counter(b for v in table.values() for _, b in v).most_common():
        print(f"    {str(b):22s} {k}")
    if "--list" in sys.argv:
        for name in sorted(table):
            mark = "" if name in notes else "   <-- NO SUCH NOTE"
            print(f"  [[{name}]]{mark}")
            for f, b in sorted(table[name]):
                print(f"      {str(b):22s} {f}")


print(f"vault notes on `main`: {len(notes)}")
# The two trees are NEVER summed. They are independently versioned packages and
# adoption is per-extraction (#310); one total over both is a number that cannot
# be acted on by either.
report("anchors under WALK_ROOTS", walked)
print()
report("anchors under _walk_roots.EXTRACTED (reported, not walked — ADR-0153 dec. 1/8)",
       extracted)

fail = False
if bad_ref:
    fail = True
    print("\nAnchor names a note that does not exist on `main`:")
    for f, i, n in bad_ref:
        print(f"  {f}:{i}  [[{n}]]")
    print("Rename the anchor to the note's current name, or add the note. An anchor\n"
          "that resolves to nothing reads as a live edge and hides a real drop.")
if bad_form:
    fail = True
    print("\n`Vault:` outside the anchor form (expected `Vault: [[Note Name]]`):")
    for f, i, s in bad_form:
        print(f"  {f}:{i}  {s}")

print("\nAdoption is REPORTED, not asserted (#310: it is per-extraction).")
sys.exit(1 if fail else 0)
