#!/usr/bin/env python3
"""Every ADR is classified, exactly once, and INDEX.md / AUDIT.md match the TSVs.

Prologue pass 1's guard. Like classify_blueprint.py it has NO catch-all: a new
ADR that nobody classified is the finding, not a default. It also fails on a
number used twice, because an `ADR-NNNN` citation to a duplicated number cannot
be resolved — which is the one thing pass 1 exists to make explicit.

It also compares the two GENERATED registers against a fresh render. That arm is
split by provenance and it is the whole of #1163 — a measured count moving is not
the author's doing and must not stop the suite; a TSV edit with no regeneration is
and must. `--strict` collapses the split and fails on either, which is what a human
about to commit the registers wants. See `classify_drift` for the rule.

🔴 THIS GUARD DOES NOT WRITE. It renders in memory. Until #1163 it ran each
generator as a subprocess and diffed the file before against the file after, so a
FAILED pre-flight left `AUDIT.md` modified in the working tree — three times a run,
because the pre-flight repeats its guard block. Only `gen_adr_*.py` run as
`__main__` touch `docs/adr/`.

Run from the package root.  Exit 0 = clean, or measured drift reported.
    uv run python tools/check_adr_classification.py [--strict]
"""
import csv, glob, os, sys, collections, pathlib, re

BUCKETS = {"engine", "seam", "content", "method"}
SPANS = {"-", "split", "interface", "platform"}
SYSTEMS = {"Battlefield", "Battle", "Character Catalogue", "Sprite Rig", "Effects", "UI",
           "Audio", "Cutscene", "Campaign", "Render", "Debug", "platform", "host"}

# ---------------------------------------------------------------- the registers
#
# INDEX.md and AUDIT.md are generated and committed, and this is where they used to
# be asserted byte-for-byte. Two things about that were wrong, and #1163 is both.
#
# 🔴 IT WROTE TO THE TREE, AND HARDEST ON THE FAILURE PATH. The old arm ran each
# generator as a SUBPROCESS and compared the file before against the file after —
# so the check WAS the generator. In the clean case it rewrote two files with
# identical bytes; in the stale case it left `AUDIT.md` MODIFIED in the working
# tree and then aborted, handing the author a dirty `git status` they did not
# cause. The suite pre-flight runs its guard block three times, so that happened
# three times a run, and two runs in one worktree could interleave on the same
# path. Nothing about it was read-only. It now renders IN MEMORY and never writes;
# only `gen_adr_*.py` run as `__main__` touch `docs/adr/`.
#
# 🔴 IT COULD NOT TELL THE TWO KINDS OF STALENESS APART. `code`/`test`/`doc`/`tool`/
# `guard` and `cited_by` are MEASURED from a walk of `src`, `assets`, `addons`,
# `tests`, `docs` and `tools`, so **putting the string `ADR-0072` in a comment in a
# shell script makes a committed register stale**. Nothing tells the author, and no
# diff touching only `tools/*.sh` gives them a reason to look — `1d2426dc9` did
# exactly that and stopped the whole 763-scene suite for everybody, twice in one
# day. ADR-0214's Amendment records the same abort from a different cause and names
# it correctly: *staleness it did not cause*.
#
# So the verdict is split by PROVENANCE, which the generators now declare: each
# renders twice, once with the measured cells filled and once with them masked, and
# the two renders are line-aligned by construction because they are the same code
# path. A line of the committed file that differs from the fresh render is
#
#   STRUCTURAL  if it differs in any cell the mask left alone — a TSV edit, a new
#               ADR, a retitled one, a changed decision count. The author made this
#               and forgot the generator. It FAILS, as before.
#   MEASURED    if every cell it differs in is masked. Some unrelated commit moved
#               a count. It is REPORTED, loudly and by row, and does not fail.
#
# `--strict` makes measured drift fatal too, for the one place that wants it: a
# human about to commit the registers.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import gen_adr_index, gen_adr_audit  # noqa: E402

STRICT = "--strict" in sys.argv
drift = []


def classify_drift(name, have, want, mask, tok):
    """Split `have` vs `want` into (structural, measured) findings.

    `want` and `mask` are the same render with the measured cells filled and
    blanked, so line i of one is line i of the other. A differing line is MEASURED
    drift only when every cell it differs in is a masked cell — which puts the
    provenance rule in the generator that knows it, not in a regex here.
    """
    if have is None:
        return [f"MISSING — docs/adr/{name} has never been generated"], []
    H, W, M = have.splitlines(), want.splitlines(), mask.splitlines()
    assert len(W) == len(M), f"{name}: the two renders are not line-aligned"
    gen = f"tools/gen_adr_{'index' if name == 'INDEX.md' else 'audit'}.py"
    if len(H) != len(W):
        return ([f"STALE {name} — it is {len(H)} lines, the generator renders "
                 f"{len(W)}; a row was added or removed. Run `uv run python {gen}`"], [])
    structural, measured, header = [], [], []
    for i, (h, w, m) in enumerate(zip(H, W, M), 1):
        if w.startswith("| ADR |"):
            header = [c.strip() for c in w.split("|")]
        if h == w:
            continue
        if not w.startswith("|"):
            # 🔴 PROSE IS NOT ONE CELL. AUDIT.md's summary paragraph carries two
            # measured numbers in running text, and splitting it on "|" yields a
            # single field that the mask marks wholly measured — so every word of
            # it read as a moved count and an edit to the sentence could not fail.
            # Found by `test_a_changed_prose_line_with_no_mask_is_structural`.
            # A prose line drifts measurably only if BOTH sides still match the
            # literal template the mask makes of it.
            moved = _template_match(h, w, m, tok)
            (measured if moved else structural).append(
                f"{name}:{i} the summary line  {moved}" if moved else
                f"STALE {name}:{i} — `{w.strip()[:100]}`. Run `uv run python {gen}`")
            continue
        hc, wc, mc = h.split("|"), w.split("|"), m.split("|")
        if len(hc) != len(wc) or len(wc) != len(mc) or tok not in m:
            structural.append(f"STALE {name}:{i} — `{w.strip()[:100]}`. Run "
                              f"`uv run python {gen}`")
            continue
        hard = [j for j in range(len(wc)) if hc[j] != wc[j] and tok not in mc[j]]
        if hard:
            cols = ", ".join(header[j] if j < len(header) else f"col {j}" for j in hard)
            structural.append(f"STALE {name}:{i} — {_who(wc)} differs in {cols}, which is "
                              f"NOT a measured column. Run `uv run python {gen}`")
        else:
            moved = " ".join(
                f"{header[j] if j < len(header) else f'col {j}'} "
                f"{hc[j].strip() or '0'}→{wc[j].strip() or '0'}"
                for j in range(len(wc)) if hc[j] != wc[j] and tok in mc[j])
            measured.append(f"{name}:{i} {_who(wc)}  {moved}")
    return structural, measured


def _template_match(have, want, mask, tok):
    """`"102→103"` if `have` differs from `want` only where the mask is, else "".

    The mask line is the literal template: everything outside a `tok` is text the
    generator emits verbatim. A wildcard is `[^|]*` rather than `.*` so this can
    never be asked to swallow a table separator.
    """
    if tok not in mask:
        return ""
    parts = mask.split(tok)
    pat = re.compile("([^|]*)".join(re.escape(s) for s in parts) + r"\Z")
    h, w = pat.match(have), pat.match(want)
    if not h or not w:
        return ""
    moved = [f"{a or '0'}→{b or '0'}" for a, b in zip(h.groups(), w.groups()) if a != b]
    return " ".join(moved) or "(no visible change)"


def drift_report(drift, strict):
    """Route measured drift: advisory by default, fatal under `--strict`.

    Two callers want opposite things from the same finding. The suite pre-flight
    wants to RUN — a moved count is not a reason to stop 763 scenes — so it takes
    the advisory and exits 0. A human about to commit the registers wants the
    opposite, and passes `--strict`. Returning both lists rather than printing
    makes the routing itself testable.
    """
    if not drift:
        return [], []
    head = (f"MEASURED DRIFT — {len(drift)} register cell(s) moved because a file "
            f"outside docs/adr/ gained or lost an `ADR-NNNN` mention. No diff did "
            f"this on purpose, and nothing told its author. Refresh with:\n"
            f"        uv run python tools/gen_adr_index.py && "
            f"uv run python tools/gen_adr_audit.py")
    if strict:
        return [head] + ["  " + d for d in drift], []
    out = [f"check_adr_classification: {head}"] + ["    " + d for d in drift[:12]]
    if len(drift) > 12:
        out.append(f"    … and {len(drift) - 12} more")
    return [], out


def _who(wc):
    """`ADR-0072` out of a rendered row; the summary paragraph has no ADR of its own."""
    m = re.search(r"\[(\d{4})\]", wc[1] if len(wc) > 1 else "")
    return f"ADR-{m.group(1)}" if m else "the summary line"


fail = []
files = sorted(os.path.basename(p) for p in glob.glob("docs/adr/*.md")
               if re.match(r"\d{4}-", os.path.basename(p)))
rows = list(csv.DictReader(open("docs/adr/CLASSIFICATION.tsv"), delimiter="\t"))

classified = {r["file"] for r in rows}
for f in sorted(set(files) - classified):
    fail.append(f"UNCLASSIFIED — no CLASSIFICATION.tsv row: docs/adr/{f}")
for f in sorted(classified - set(files)):
    fail.append(f"STALE — CLASSIFICATION.tsv names a file that does not exist: {f}")
for f, n in collections.Counter(r["file"] for r in rows).items():
    if n > 1:
        fail.append(f"DUPLICATE ROW — {f} classified {n} times")

for r in rows:
    if r["bucket"] not in BUCKETS:
        fail.append(f"{r['file']}: bucket {r['bucket']!r} is not one of {sorted(BUCKETS)}")
    if r["span"] not in SPANS:
        fail.append(f"{r['file']}: span {r['span']!r} is not one of {sorted(SPANS)}")
    if r["system"] not in SYSTEMS:
        fail.append(f"{r['file']}: system {r['system']!r} is not a blueprint system or tier")

# A number used twice makes every ADR-NNNN citation to it unresolvable.
for num, n in sorted(collections.Counter(f[:4] for f in files).items()):
    if n > 1:
        which = ", ".join(f for f in files if f.startswith(num))
        fail.append(f"AMBIGUOUS NUMBER — ADR-{num} names {n} files: {which}")

# Relative links between ADRs must resolve.
for f in files:
    t = (pathlib.Path("docs/adr") / f).read_text(encoding="utf-8")
    for tgt in sorted(set(re.findall(r"\]\((\d{4}-[^)#]*\.md)", t))):
        if tgt not in files:
            fail.append(f"BROKEN LINK — docs/adr/{f} -> {tgt}")

# A link's LABEL and its HREF must name the same ADR. The 2026-08-28 renumber
# repointed nine hrefs to 0196/0200 and left the visible `ADR-0073` / `ADR-0137`
# label in place — the BROKEN LINK arm above forced the href and nothing looked at
# the label, so a reader and `check_adr_anchors.py` both saw the retired number.
# Scanned package-wide, not just under docs/adr: the vocabulary links in too.
import sys as _sys, pathlib as _pathlib
_sys.path.insert(0, str(_pathlib.Path(__file__).resolve().parent))
import _walk_roots  # noqa: E402

LABEL_SCAN = (".md", ".gd", ".py", ".sh")
LABEL = re.compile(r"\[ADR-(\d{4})\]\([^)]*?(\d{4})-[^)]*?\.md")
# `rglob` does not descend a symlinked directory, and `addons/exmateria_{sound,spu}`
# are a real rsync'd directory in one worktree and symlinks in the next — so this
# arm silently stopped scanning 160-odd files depending on the checkout. Same cause
# as the one `gen_adr_audit.scan` documents; same remedy.
for p in sorted(_walk_roots.walk_files(".")):
    if p.suffix not in LABEL_SCAN or ".git" in p.parts:
        continue
    if p.name == "check_adr_classification.py":
        continue                      # spells the mismatch in its own comment
    try:
        t = p.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    for ln, line in enumerate(t.splitlines(), 1):
        for m in LABEL.finditer(line):
            if m.group(1) != m.group(2):
                fail.append(f"LABEL/HREF MISMATCH — {p}:{ln}: label says ADR-{m.group(1)}, "
                            f"the link points at ADR-{m.group(2)}")

# AUDIT.tsv carries the one column that cannot be measured. Its rows must name a
# real ADR exactly once and use the published vocabulary — a free-text verdict is
# how a register stops being countable.
# The register is keyed (adr, dec): `*` is the ADR-level verdict, a number is one
# decision's own conformance. The two vocabularies are deliberately different — an
# ADR is `half-landed`, a single decision never is.
AUDIT_VERDICTS = {"unaudited", "complete", "half-landed", "violated", "closeable", "superseded"}
DEC_STATUS = {"unreviewed", "built", "violated", "stale", "unresolved"}
audit = pathlib.Path("docs/adr/AUDIT.tsv")
if not audit.exists():
    fail.append("MISSING — docs/adr/AUDIT.tsv (the conformance register's verdict column)")
else:
    seen_audit = collections.Counter()
    nums = {r["num"] for r in rows}
    has_star = set()
    for r in csv.DictReader(open(audit), delimiter="\t"):
        key = (r["adr"], r["dec"])
        seen_audit[key] += 1
        if r["adr"] not in nums:
            fail.append(f"AUDIT.tsv names ADR-{r['adr']}, which is not a classified ADR")
        if r["dec"] == "*":
            has_star.add(r["adr"])
            if r["status"] not in AUDIT_VERDICTS:
                fail.append(f"AUDIT.tsv ADR-{r['adr']} (ADR-level): verdict {r['status']!r} "
                            f"is not one of {sorted(AUDIT_VERDICTS)}")
        else:
            if not r["dec"].isdigit():
                fail.append(f"AUDIT.tsv ADR-{r['adr']}: dec {r['dec']!r} is neither '*' nor a number")
            if r["status"] not in DEC_STATUS:
                fail.append(f"AUDIT.tsv ADR-{r['adr']} dec. {r['dec']}: status {r['status']!r} "
                            f"is not one of {sorted(DEC_STATUS)}")
        # An evidence field is a citation, not an essay — prose belongs in audit-notes/.
        if len(r.get("evidence", "")) > 260:
            fail.append(f"AUDIT.tsv ADR-{r['adr']} dec. {r['dec']}: evidence is "
                        f"{len(r['evidence'])} chars; cap is 260 — move prose to "
                        f"docs/adr/audit-notes/{r['adr']}.md")
    for (a, d), c in seen_audit.items():
        if c > 1:
            fail.append(f"AUDIT.tsv DUPLICATE ROW — ADR-{a} dec. {d} appears {c} times")
    # A decision row without its ADR-level row is a register with no verdict.
    for a in sorted({k[0] for k in seen_audit} - has_star):
        fail.append(f"AUDIT.tsv ADR-{a} has decision rows but no `*` ADR-level verdict row")

for _name, _mod in (("INDEX.md", gen_adr_index), ("AUDIT.md", gen_adr_audit)):
    _p = pathlib.Path("docs/adr") / _name
    _have = _p.read_text(encoding="utf-8") if _p.exists() else None
    _s, _m = classify_drift(_name, _have, _mod.render(), _mod.render(measured=False),
                            _mod.MASK)
    fail.extend(_s)
    drift.extend(_m)

# The defects pass 1 FOUND, pinned so a NEW one fails. Shrink this list, never grow it.
# Renumbering and link repair are prose edits, which pass 1 deliberately does not make.
#
# DECIDED 2026-08-21 — the six ambiguous numbers stay pinned; they are NOT renumbered in
# a batch. Each pair is repaired by the first per-system chunk that reaches it, because
# resolving an `ADR-NNNN` citation needs the citing context, which is exactly what that
# chunk has and a batch rename does not.
#
# The tiebreak, because every pair straddles TWO systems and "when its system comes up"
# is ambiguous on its own: THE NUMBER STAYS WITH THE SYSTEM DOING THE WORK, and the other
# member takes the next free number. The chunk being audited is the one whose citations
# are being read, so it keeps the number they were written against.
#
#   0073  Character Catalogue | Effects        0096  Render  | UI   -- RESOLVED
#   0091  UI                  | platform       0097  Effects | UI
#   0095  Effects             | UI             0137  Effects | UI
#
# By ADR-0141's extraction order (Render #1, Audio #2) the first pair reached is 0096:
# Render owns `0096-a-texture-alpha-channel-...`, so Render's chunk renumbers UI's
# aperture ADR.
#
# 0096 RESOLVED 2026-08-26 (#605). Render's extraction ran 2026-08-21 and did not
# discharge it; the debt was found by a cross-worktree number scan, not by the chunk.
# UI's member became `0182-aperture-opens-normal-closes-fast.md` and all 14 of its
# citations were repointed; the 20 STP-side citations kept 0096. The rule above was
# followed, not amended: the number stayed with Render, the system that owns it.
# `cited_by` could then be measured for both rows -- 0096 -> 2, 0182 -> 5 -- which is
# the data the ambiguity had been destroying. Five pairs remain pinned.
#
# `cited_by` reads `ambiguous` for all twelve rows in CLASSIFICATION.tsv and cannot
# supply a citation-count tiebreak — that is the data the ambiguity destroys, and the
# reason the rule is positional rather than measured.
KNOWN = set()
known_hit = {k for k in KNOWN if any(m.startswith(k) for m in fail)}
fail = [m for m in fail if not any(m.startswith(k) for k in KNOWN)]
for k in sorted(KNOWN - known_hit):
    fail.append(f"FIXED, UNPINNED — remove from KNOWN: {k}")

_fatal, _advisory = drift_report(drift, STRICT)
fail.extend(_fatal)
for _line in _advisory:
    print(_line)

if fail:
    print(f"check_adr_classification: {len(fail)} problem(s)")
    for m in fail:
        print("  " + m)
    sys.exit(1)
print(f"check_adr_classification: OK — {len(files)} ADRs, all classified")
