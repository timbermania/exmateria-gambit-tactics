#!/usr/bin/env python3
"""Guard: every extraction's move manifest, and the vault edges that ride on it.

Written at loop **pass 5** by #565, satisfied at pass 6, checked at pass 7 —
ADR-0168. Two registers per extraction, five arms, and every arm is here because
some *other* instrument is structurally unable to report the thing it checks.

    uv run python tools/check_move_manifest.py [--list] [--only N]

ONE SUBJECT BECAME A REGISTER AT EXTRACTION #7 (gl-ADR-0295 dec. 8, #1216). This
file used to hardcode `EXTRACTION-3-MOVE-MANIFEST.tsv` and
`addons/exmateria_battlefield/`, and the measured consequence is that
**extractions #4, #5 and #6 wrote no manifest at all** — the obligation in the
paragraph above is generic, the enforcement was not, and three extractions
passed through the hole. `SUBJECTS` below is the register; adding an extraction
is two TSVs and one row. The three lapsed manifests are deliberately NOT
back-filled: a register filled in by someone who did not measure the move is
worse than an absent one (ADR-0290 dec. 10, gl-ADR-0295 *Considered
alternatives*), and #1199 is where that debt lives.

WHY A MANIFEST AT ALL. #561 dec. 2 collapsed the ~27 hand-audited `Battlefield`
rules in `classify_blueprint.py` into one location assertion,
`("addons/exmateria_battlefield/", "Battlefield")`. After that the census
**restates where files were put** rather than measuring what `Battlefield` is: a
file wrongly moved in is booked `Battlefield`, its cross-system reaches stop
being counted by `touch_matrix.py`, it passes goal #5 arm 1 *as the addon's own
file*, and its lines read as growth against `--delta 8360`. A wrong move reads as
a win on two instruments. The manifest is the only register that can say "the
right files moved", and the only checkable form of that claim is **set
equality** — so that is what arms 2 and 3 assert. Every extraction inherits that
property the moment its addon prefix lands in `WALK_ROOTS`, which is why the
subject list is a register and not a special case for #3.

WHY THE VAULT EDGES ARE A SEPARATE REGISTER. `check_vault_anchors.py` enforces
that every anchor *present* resolves to a note on `main`. It has no opinion about
an anchor that stops being present. Seeded at `cd9d6c88f`, all three of these
left it at **exit 0**:

    - delete both `## Vault:` lines from `src/map/MapStateSelector.gd`
    - delete the sole `[[Walk To Opcode]]` anchor, taking that note to ZERO edges
    - delete `src/scenarios/EventPathfinder.gd` outright

The count in its report drops (`Battlefield 31 -> 29`) and nothing asserts on the
count. That is exactly the case `docs/agents/refactor-loop.md` says cannot be
recovered after the fact — pass 8 cannot tell *"we dropped this"* from *"we
reimplemented it without a marker"* — so arm 4 pins the **note**, not the file.

    Keying on the note is the whole trick. The file path changes BY DESIGN in
    this pass; an `R:` citation or a path-keyed register would go red on every
    correct move and teach everyone to ignore it. The note name is the one
    coordinate the move does not touch.

AND THE COST PROFILE IS PER-EXTRACTION. `refactor-loop.md`'s marker paragraph is
amended by ADR-0154 dec. 1: ADR-0112 does not say "analog, authored fresh", and
under ADR-0110 dec. 1's **lift** a moving file keeps its comment for free. This
system has already demonstrated it — pass 4 (#551) split `CursorBob.gd` and
`[[Start Action Menu]]` rode into `src/ui3/GloveCursorBob.gd` with zero authoring
and the guard green throughout. Extraction #3 measured at `cd9d6c88f` has **0
authoring debt**: the R:-seed scan over all 230 notes finds 15 notes / 31 pairs
into the 44-file census and every one is already anchored, 0 gaps and 0 extras.

    ⚠️ EXTRACTION #7 IS THE OPPOSITE READING OF THE SAME MEASUREMENT, and it is
    half the reason this register exists. `Effects` read **2** anchors against
    **48** notes citing a `src/effects/` path — 138 authored in #1215, to 140
    over 54 files — because nothing ever asserted coverage (#310, deliberately:
    a global floor would be red for months). Two anchors and forty look
    identical in a green pre-flight, so "0 authoring debt" is a per-extraction
    FINDING and never an inherited default. Budget for survival where the
    measurement says 0, and for authoring where it does not.

WHAT EACH ARM CANNOT SEE, stated because pass 4's lesson was that every blind
spot on this map scored zero and every one was real:

  - arm 1 knows three dispositions and each asserts a DIFFERENT pair of facts:
    `move` (exactly one of src/dst present), `new` (src empty, dst present) and
    `returned` (src present, dst absent). A row exempt from checking would be a
    hole; each of these is falsifiable in both directions instead.
  - arm 1 is per-row, so it cannot see a row that should not exist at all;
    that is arm 2's job, and arm 2 only runs while the host copy is still there.
  - arm 2 cannot assume the manifest is the whole bucket, and at extraction #7 it
    is NOT. `Effects` books **191** files; the membership is **67**. ADR-0286
    dec. 4's finding is that *"classification and membership are different
    questions — a file can belong to a system and still not move in that
    system's extraction"*, and it keeps `src/effects/studio/` (116 files), the
    six studio debug panels, `EffectScoreModel.gd` and `PSXDitherCurves.gd` in
    the host on their own schedule. Measured: arm 2 against the bare census
    reports **124 failures**, one per correctly-staying file. So the residue is a
    DECLARED register — `stays` — and not an exemption: a `system` file that is
    neither on the manifest nor matched by a `stays` pattern reds (arm 2), and a
    `stays` pattern that matches nothing reds too (arm 2b), so the declaration
    cannot rot into a blanket. Extraction #3's `stays` is empty, which is the
    same claim as before about the same tree.
  - arm 3 compares against `SOURCE_SUFFIXES`, which is `.gd` plus four shader
    suffixes and **no `.tscn`** — so scene rows are matched by hand against the
    addon tree, not by the walk. This is #561 dec. 4's hole and it does not close
    by itself.
  - arm 3 is set equality against ONE addon root, so a row whose dst lands in a
    DIFFERENT addon is outside it by construction. Extraction #7 has three — the
    PSX trio goes home to `addons/exmateria_platform/` as `PsxMagnitude`,
    `PsxChirality` and `CameraCalibration` (gl-ADR-0295 dec. 3/4, #1220) — and
    they are counted and printed rather than silently dropped, because a row
    quietly excluded from the only set-equality arm is exactly how a wrong move
    gets to read as a win. Arm 1 still holds them in both directions.
  - arm 4 proves a note still has SOME anchor. It cannot prove the anchor is on
    code that still does the thing the note describes. Nothing can; that is
    pass 8's qualitative read and it is supposed to be qualitative.
  - none of them see `.uid` sidecars, `.import` files, or `project.godot` — the
    three edits #561 dec. 3 lists are pass 6's and are checked by `path_refs.py`
    and `check_root_set.py`, not here.
  - arm 3 does not see an addon's own `tests/`. A manifest is the record of ONE
    move — extraction #3 pass 6's 46 files — and an addon-owned test
    (ADR-0194 dec. 2) arrives later, from `tests/`, by a different act with its own
    register (`docs/TEST-BASELINE-E2.tsv`'s `# moved` rows). Booking it here would
    say pass 6 moved a file it did not. This is the same "a test is not production
    source" exclusion ADR-0194 dec. 9 made in the classifier, the fourth instrument
    to need it, and the first one a probe seeded in a DIFFERENT addon could not
    find — each subject is scoped to its own addon alone.

THE ARMS ARE PURE FUNCTIONS of (rows, filesystem predicate). `main()` wires them
to the real tree; `tools/test_check_move_manifest.py` wires them to a fake one,
which is the only way to score the AFTER-the-move half of a move that has not
happened yet, and the only way to direction-test a register whose red state is
"somebody moved a file wrongly" — not a thing to do to a shared worktree.
"""
import csv, io, contextlib, os, pathlib, re, sys

PROJECT_DIR = pathlib.Path(__file__).resolve().parent.parent
ANCHOR = re.compile(r"Vault:\s*\[\[([^\]]+)\]\]")

# The register. One row per extraction that has moved a system into an addon.
#   `system`      — what `classify_blueprint.classify()` books the addon's files as.
#   `scaffolding` — addon-root files that are plugin plumbing (#561 dec. 5), not
#                   manifest rows. `plugin.cfg` is not a `SOURCE_SUFFIXES` suffix
#                   and never reaches arm 3; `plugin.gd` and the folder-named
#                   façade (ADR-0212 dec. 1) are.
#   `stays`       — `system`-classified host files this extraction does NOT claim
#                   (ADR-0286 dec. 4: classification and membership are different
#                   questions). A path ending in `/` is a directory prefix; every
#                   other entry is one exact path. Both arms of arm 2 read it.
#   `census_sources` — which `source` values name a row whose src the classifier can
#                   SEE, so arm 2's reverse half ("the manifest names a src the
#                   classifier no longer books as `system`") applies to it. It is a
#                   declaration and not a suffix rule because extraction #3's two
#                   `scene` rows are `.tscn`, which is not in `SOURCE_SUFFIXES` and
#                   therefore can never be in the census — #561 dec. 4's hole. A
#                   suffix rule would red on them; naming the sources cannot.
SUBJECTS = {
    3: {
        "manifest": "docs/EXTRACTION-3-MOVE-MANIFEST.tsv",
        "edges": "docs/EXTRACTION-3-VAULT-EDGES.tsv",
        "addon_root": "addons/exmateria_battlefield/",
        "system": "Battlefield",
        "scaffolding": {"plugin.gd"},
        "census_sources": {"census"},
        # Extraction #3 moved the whole census. An empty list is a CLAIM — arm 2b
        # has nothing to check and arm 2 is the full-bucket assertion it was
        # written as, unchanged.
        "stays": [],
    },
    7: {
        "manifest": "docs/EXTRACTION-7-MOVE-MANIFEST.tsv",
        "edges": "docs/EXTRACTION-7-VAULT-EDGES.tsv",
        "addon_root": "addons/exmateria_effects/",
        "system": "Effects",
        "scaffolding": {"plugin.gd", "exmateria_effects.gd"},
        # All 67 rows are `.gd`/shader and all 67 ARE booked `Effects` today, so
        # unlike #3's `scene` rows the reverse half of arm 2 is live for every one.
        "census_sources": {"membership_arms"},
        # ADR-0286 dec. 4, stated as a register. The directory is a directory
        # because the ADR names one; the rest are named one by one so a NEW
        # studio panel reds here instead of inheriting the exemption.
        "stays": [
            "src/effects/studio/",                 # 116 files, extractable later
            "src/debug/ColorTimelineModel.gd",     # the six studio panels —
            "src/debug/EffectTimelineModel.gd",    # ADR-0286 dec. 3's root set
            "src/debug/EffectTimelineView.gd",
            "src/debug/EffectViewerPanel.gd",
            "src/debug/FireCastReproPanel.gd",
            "src/debug/TrapViewerPanel.gd",
            # `src/effects/EffectScoreModel.gd` used to need its own entry here —
            # a studio file misfiled into the runtime's directory. #1217 (a) moved
            # it to its studio address, so the directory entry above now covers it
            # and the explicit line had to GO in the same commit or arm 2b reds.
            # That coupling firing on its first use is the register working.
            "src/effects/PSXDitherCurves.gd",      # excluded by the membership command
        ],
    },
}


def load_classifier():
    """`classify_blueprint` reports at import and ends in sys.exit(); catch both."""
    ns = {"__name__": "cbmod"}
    src = (PROJECT_DIR / "tools" / "classify_blueprint.py").read_text(encoding="utf-8")
    cwd = os.getcwd()
    try:
        os.chdir(PROJECT_DIR)
        with contextlib.redirect_stdout(io.StringIO()):
            try:
                exec(compile(src, "classify_blueprint.py", "exec"), ns)
            except SystemExit:
                pass
    finally:
        os.chdir(cwd)
    return ns


def rows(path):
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


# ---------------------------------------------------------------------------
# The four arms, as pure functions. `exists` is a predicate over path strings so
# a test can hand them a tree that does not exist on disk; `main()` passes the
# real one. Each returns its report line(s) and a list of failures.
# ---------------------------------------------------------------------------

def arm1(man, exists):
    """Every row is in exactly one of its two places, per its disposition."""
    at_src, at_dst, both, neither, fresh, back, gone = [], [], [], [], [], [], []
    fail = []
    for r in man:
        # 🔴 A ROW CAN BE RULED BACK, AND THAT IS NOT A DROP. The census moved
        # `assets/shaders/cursor_clut_preview.gdshader` in by DIRECTORY (source `census`,
        # ADR-0184's bulk pass), not by a per-file ruling. ADR-0209 measured that no addon
        # file uses it and its one consumer is a HOST viewer that also needs two host TGAs
        # and a host JSON, so the file went back where it came from. Two arms had an
        # opinion about that and both were wrong for it:
        #
        #   - arm 1 would book it `at_src`, which is correct in itself, EXCEPT that a
        #     non-empty `at_src` is what gates arm 2 — and arm 2's premise (see its own
        #     comment) is "while the host copy is still there", i.e. DURING the extraction.
        #     Measured: reversing one row woke arm 2 in a world it was not written for and
        #     it reported 44 failures, one for every completed move.
        #   - arm 3 is set equality against the addon tree, so a dst that correctly no
        #     longer exists reds as `on the manifest but not in the addon`.
        #
        # `returned` asserts the MIRROR of a move — src PRESENT, dst ABSENT — so the row
        # stays falsifiable in both directions rather than being deleted. Deleting it would
        # erase the only record that the file was ever moved, which is the one thing this
        # manifest exists to hold (see WHY A MANIFEST AT ALL, above).
        disp = (r.get("disposition") or "").strip()
        if disp == "returned":
            back.append(r)
            if not (r["src"] or "").strip():
                fail.append("arm 1  a `returned` row names no src, so there is nowhere to "
                            "return to: %s" % r["dst"])
            elif not exists(r["src"]):
                fail.append("arm 1  `returned` row's src does not exist: %s" % r["src"])
            if (r["dst"] or "").strip() and exists(r["dst"]):
                fail.append("arm 1  `returned` row's dst still exists, so it did not "
                            "return: %s" % r["dst"])
            continue
        # 🔴 A ROW CAN BE MERGED AWAY, AND THAT IS NOT A DROP EITHER — the FOURTH
        # disposition (#1224). `src/effects/MapTintOverlay.gd` moved into the addon at
        # #1225 and was then absorbed by `overlay/TintedSurfaces.gd` as its reserved
        # `SURFACE_MAP` token, so BOTH its addresses are now empty. Arm 1 reads that pair
        # as `NEITHER src nor dst exists (dropped)` — which is the correct reading of an
        # undeclared disappearance and the wrong one here.
        #
        # Deleting the row instead is what this file's own `returned` note forbids in so
        # many words: *"Deleting it would erase the only record that the file was ever
        # moved, which is the one thing this manifest exists to hold."* That sentence was
        # written about a row going back to the host; it is just as true of one folded into
        # a sibling. So `merged` asserts the pair BOTH ABSENT — still falsifiable in both
        # directions, because restoring either file reds it — and pins `lines` to 0, since
        # a file that does not exist has none. WHERE it went is prose, and it lives where a
        # reader looks: this register's header, `plugin.gd`'s, and the extraction's
        # translation table.
        if disp == "merged":
            gone.append(r)
            if exists(r["dst"]):
                fail.append("arm 1  `merged` row's dst still exists, so it did not "
                            "merge: %s" % r["dst"])
            if (r["src"] or "").strip() and exists(r["src"]):
                fail.append("arm 1  `merged` row's src came back, so the move it records "
                            "was undone: %s" % r["src"])
            if (r.get("lines") or "").strip() != "0":
                fail.append("arm 1  `merged` row must read `lines` 0 — the file is gone: "
                            "%s" % r["dst"])
            # And it anchors NOTHING, for the same reason: the `anchors` column is
            # re-derived from the file, and there is no file. That is also what keeps this
            # register and `*-VAULT-EDGES.tsv` agreeing — the edges register is PRESENT
            # tense (arm 4 asserts a live anchor), so a merged row has no edge row either.
            if (r.get("anchors") or "").strip():
                fail.append("arm 1  `merged` row names anchors but has no file to carry "
                            "them: %s" % r["dst"])
            continue
        # 🔴 A `new` ROW HAS NO SRC AND THAT IS NOT A DROP. Arm 3 is set equality
        # against the addon tree, so a file WRITTEN in the addon (rather than moved
        # into it) still has to be on the manifest or arm 3 reds — and before this
        # branch existed the only way to satisfy arm 3 was to name a host path that
        # never existed, i.e. to record a move that never happened. `Lattice.gd` is
        # the first: ADR-0192 dec. 4 writes the port fresh, and its "original" is the
        # store it wraps, not a file that moved. `disposition == "new"` asserts the
        # opposite pair of facts from a move — src EMPTY, dst PRESENT — so a new row
        # is still falsifiable in both directions rather than merely exempt.
        if disp == "new":
            fresh.append(r)
            if (r["src"] or "").strip():
                fail.append("arm 1  a `new` row names a src, so it is a move: %s" % r["src"])
            if not exists(r["dst"]):
                fail.append("arm 1  `new` row's dst does not exist: %s" % r["dst"])
            continue
        s, d = exists(r["src"]), exists(r["dst"])
        (both if s and d else neither if not (s or d) else at_src if s else at_dst).append(r)
    for r in both:
        fail.append(f"arm 1  BOTH src and dst exist (copied, not moved): {r['src']}")
    for r in neither:
        fail.append(f"arm 1  NEITHER src nor dst exists (dropped): {r['src']}")
    report = (f"manifest: {len(man)} rows — {len(at_src)} still in the host, "
              f"{len(at_dst)} moved, {len(fresh)} written in the addon, "
              f"{len(back)} returned to the host, {len(gone)} merged away")
    return report, fail, {"at_src": at_src, "at_dst": at_dst, "returned": back,
                          "merged": gone}


def stayed(path, stays):
    """True when `stays` declares this `system` file as not-this-extraction's."""
    return any(path.startswith(s) if s.endswith("/") else path == s for s in stays)


def arm2(man, census, system, stays, census_sources=("census",), at_src=None):
    """Every `system` file is on the manifest or declared a stay, and vice versa.

    Two arms in one pass. Arm 2 is the escape check: a file the classifier books
    as `system` that nothing accounts for. Arm 2b is the rot check on the
    declaration itself — a `stays` entry matching no census file is a widened
    exemption nobody would notice, and it is the only way this register degrades.

    🔴 THE REVERSE HALF IS SCOPED TO THE ROWS THAT HAVE NOT MOVED. It asks "the
    manifest names a src the classifier no longer books as `system`" — which is
    true of EVERY correctly-moved row, because the src is gone. Extraction #3
    never noticed: its rows moved in one commit, so arm 2 ran with all of them
    still in the host and then stopped running at all. Extraction #7 moves the PSX
    trio at #1220 and the other 64 at #1225, and measured at that in-between
    state this half reported **3 failures, one per correct move**. `at_src` is
    arm 1's own bucket of rows still in the host; passing it is what makes the
    question answerable during a staged extraction rather than only at its ends.
    """
    fail = []
    listed = {r["src"] for r in man} | {r["dst"] for r in man}
    for extra in sorted(census - listed):
        if stayed(extra, stays):
            continue
        fail.append(f"arm 2  classifier books `{system}` but no manifest row names it "
                    f"and no `stays` entry declares it: {extra}")
    unmoved = man if at_src is None else at_src
    # 🔴 A ROW WITH NO SRC CANNOT NAME A CENSUS ROW, so it is not an answer to this
    # half's question. `disposition == "new"` is the shape (#1218's `EffectsDebug.gd`
    # is extraction #7's first): its src is EMPTY by assertion, and without this filter
    # the empty string falls straight through `- census` and reds as *"the manifest
    # names a census row the classifier no longer books"* — naming nothing. `main()`
    # never saw it because it passes arm 1's `at_src` bucket, which a `new` row is not
    # in; the bare `at_src=None` form the tests use did, which is exactly the
    # difference the `at_src` parameter exists to record.
    # A `merged` row's src is gone too (#1224) — the classifier cannot book a file that
    # does not exist, so the row is not an answer to this half either. Same reason as the
    # srcless filter beside it.
    missing = ({r["src"] for r in unmoved
                if r["source"] in census_sources and (r["src"] or "").strip()
                and (r.get("disposition") or "").strip() != "merged"}
               - census - {r["dst"] for r in man})
    for m in sorted(missing):
        fail.append(f"arm 2  manifest names a census row the classifier no longer "
                    f"books `{system}`: {m}")
    held = {s: sum(1 for p in census if stayed(p, [s])) for s in stays}
    for s, n in sorted(held.items()):
        if n == 0:
            fail.append(f"arm 2b `stays` declares `{s}` but the classifier books no "
                        f"`{system}` file there — a stale entry is a silent exemption")
    report = (f"arm 2   census {len(census)} files — {len(census) - sum(held.values())} "
              f"on the manifest, {sum(held.values())} declared a stay over "
              f"{len(stays)} entr{'y' if len(stays) == 1 else 'ies'}")
    if stays:
        report += "\n        " + ", ".join(f"{s} {n}" for s, n in
                                           sorted(held.items(), key=lambda kv: -kv[1])[:3])
    return report, fail


def arm3(man, root, got, returned, scaffolding):
    """Set equality: the addon's source files are exactly the manifest's dsts.

    Restricted to dsts UNDER `root`. A row landing in another addon is reported,
    never dropped silently — see the blind-spot list in the module docstring.
    """
    fail = []
    # `returned` AND `merged` dsts are both asserted ABSENT by arm 1, so neither can
    # be wanted in the addon (#1224 added the second kind).
    back = {id(r) for r in returned}
    want, elsewhere = set(), []
    for r in man:
        if id(r) in back:       # arm 1 asserts a `returned` dst is ABSENT
            continue
        if r["dst"].startswith(root):
            want.add(r["dst"])
        else:
            elsewhere.append(r["dst"])
    got = {p for p in got if p.rsplit("/", 1)[-1] not in scaffolding}
    for extra in sorted(got - want):
        fail.append(f"arm 3  in the addon but not on the manifest: {extra}")
    for miss in sorted(want - got):
        fail.append(f"arm 3  on the manifest but not in the addon: {miss}")
    report = f"arm 3   addon holds {len(got)} source files, manifest wants {len(want)}"
    if elsewhere:
        report += (f"\n        + {len(elsewhere)} row(s) land in ANOTHER addon, outside "
                   f"this arm (arm 1 still holds them): "
                   + ", ".join(sorted(elsewhere)[:3])
                   + (" …" if len(elsewhere) > 3 else ""))
    return report, fail


def arm4(edges, exists, read):
    """No registered vault note loses its LAST anchor."""
    live, notes, fail = {}, sorted({r["note"] for r in edges}), []
    for r in edges:
        here = r["dst"] if exists(r["dst"]) else r["src"]
        if not exists(here):
            continue
        if r["note"] in ANCHOR.findall(read(here)):
            live.setdefault(r["note"], []).append(here)
    for n in notes:
        if n not in live:
            fail.append(f"arm 4  vault note [[{n}]] has ZERO surviving anchors — "
                        f"registered at {[r['src'] for r in edges if r['note'] == n]}")
    report = (f"arm 4   {len(live)} of {len(notes)} registered vault notes still anchored "
              f"({sum(len(v) for v in live.values())} of {len(edges)} edges live)")
    return report, fail, live, notes


def check(n, subj, walk, classify, source_suffixes, listing=False):
    """One subject, four arms, against the real tree. Returns its failures."""
    man = rows(PROJECT_DIR / subj["manifest"])
    edges = rows(PROJECT_DIR / subj["edges"])
    exists = lambda p: bool((p or "").strip()) and pathlib.Path(p).exists()
    read = lambda p: pathlib.Path(p).read_text(errors="replace")
    fail = []

    print(f"--- extraction #{n} -> {subj['addon_root']} (`{subj['system']}`)")
    rep, f, buckets = arm1(man, exists)
    print(rep); fail += f

    # Only meaningful while the host copy is still there: once the addon prefix
    # rule lands, `classify()` books the addon's own files as the system and this
    # arm would be comparing the manifest against itself (#561 dec. 2).
    if buckets["at_src"]:
        census = {p.as_posix() for p in walk() if classify(p.as_posix()) == subj["system"]}
        rep, f = arm2(man, census, subj["system"], subj["stays"],
                      subj["census_sources"], buckets["at_src"])
        print(rep); fail += f
    else:
        print("arm 2   SKIPPED — nothing left in the host, so the classifier would be "
              "compared against itself (#561 dec. 2)")

    root = pathlib.Path(subj["addon_root"])
    if root.is_dir():
        got = {q.as_posix() for q in root.rglob("*")
               if q.is_file() and (q.suffix in source_suffixes or q.suffix == ".tscn")
               and "tests" not in q.parts[2:3]}
        rep, f = arm3(man, subj["addon_root"], got,
                      buckets["returned"] + buckets["merged"], subj["scaffolding"])
        print(rep); fail += f
    else:
        print(f"arm 3   SKIPPED — {subj['addon_root']} does not exist yet (pass 6 creates it)")

    rep, f, live, notes = arm4(edges, exists, read)
    print(rep); fail += f

    if listing:
        print()
        for nm in notes:
            print(f"  [[{nm}]]")
            for p in live.get(nm, []):
                print(f"      {p}")
            if nm not in live:
                print("      (none)")
    print()
    return fail


def main(argv=None):
    argv = sys.argv if argv is None else argv
    os.chdir(PROJECT_DIR)
    ns = load_classifier()
    walk, classify = ns["walk"], ns["classify"]
    SOURCE_SUFFIXES = ns["SOURCE_SUFFIXES"]

    only = int(argv[argv.index("--only") + 1]) if "--only" in argv else None
    fail, ran = [], 0
    for n in sorted(SUBJECTS):
        if only is not None and n != only:
            continue
        ran += 1
        fail += check(n, SUBJECTS[n], walk, classify, SOURCE_SUFFIXES,
                      listing="--list" in argv)

    if fail:
        for f in fail:
            print(f"[FAIL] {f}")
        print(f"\n{len(fail)} failure(s).")
        return 1
    print(f"[PASS] {ran} extraction(s): move manifests and vault edges intact.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
