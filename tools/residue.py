#!/usr/bin/env python3
"""Residue attribution — every unclaimed file gets a reason. Run from the package root.

`refactor-loop.md` pass 8: *"Residue attribution — every newly-unclaimed file
gets a reason. Residue is built but unclaimed; a gap is researched but never
built."* `closure.py` produces the unclaimed set; this produces the reason, and
`docs/RESIDUE.tsv` is the register the two feed.

    python3 tools/residue.py [--tsv]        # --tsv rewrites docs/RESIDUE.tsv

WHY IT IS A SEPARATE PROGRAM. The closure answers *"can a declared root reach
this?"* and stops. That question has one answer and six causes, and deleting on
the answer alone is how a file exercised by nine tests gets removed. The causes
are what a human needs, and they are mechanical, so they are derived here rather
than recalled at the moment of deletion.

THE CLASSES, in precedence order — the order of decreasing claim on the file.

    declined   reachable from one of the DECLINED scenes. ADR-0135 dec. 11:
               declined is not deleted. This is not deadness and never was.
    test       named from tests/. Built, unshipped, and exercised — deleting it
               breaks a green suite, which is a different conversation.
    tool       named from tools/, by a tool that CONSUMES it (see below).
    cluster    named only from another unreached file. Unreachable as a GROUP,
               which is the one class where file-at-a-time review misleads: each
               member looks referenced and the whole set is orphaned.
    orphan     no static claim of any kind.

**Prose is never a class.** A `.md` mention is printed in the evidence column
because a human deciding the file's fate wants it, and it decides nothing,
because a document cannot execute a file. That is not fastidiousness — it is the
third false-claim mechanism this program hit, and the worst of them:

    src/ui3/testing/UICompileTest.gd     <- ADR-0112, "dead code is what the
                                            root set cannot reach", naming it
                                            as an EXAMPLE of dead code
    assets/shaders/ui_nearest.gdshader   <- ADR-0144, "a closure candidate"
    src/debug/EffectTimelineView.gd      <- ADR-0145, this program's own ADR,
    src/effects/PSXDitherCurves.gd          which names both orphans

Every one of those documents names the file **in order to say nothing reaches
it**. A `doc` class scored them as claimed, so publishing the register emptied
the register: the two orphans were reclassified by the sentence announcing them.
Prose demoted to evidence, the answer is stable under its own publication — and
`check_residue.py` is what keeps it that way.

TWO MORE WAYS THIS GETS THE ANSWER WRONG, both found while writing it, both fixed:

  * **An instrument is not a consumer.** `tools/classify_blueprint.py` names
    `bitmap_char_3d.gdshader` and `ui_nearest.gdshader` — in its rules table,
    beside a comment reading *"NO reader anywhere — a closure candidate"*.
    `tools/delete_dead_code.py` names six of these files in a `KEEP_FILES` set,
    which is a register of what NOT to delete: a hit there is the recorded
    ABSENCE of a claim. Counting either would have reported `tool` for five
    files nothing consumes. `INSTRUMENTS` below is excluded for that reason —
    ADR-0131 dec. 3's *"the instrument measuring the subject is not the
    subject"*, applied one level down.

  * **A comment is not a reference either.** Three files name
    `EffectTimelineView` and all three do it in a docstring — one of them its own
    sibling, calling it *"thin glue"*. Identifier needles are therefore matched
    against `touch_matrix.strip_noncode`'s output — the same stripper, sliced out
    of that module rather than copied, so the two programs cannot disagree about
    what a reference is (it scored 672 edges against a real 358 before that
    function existed). Path needles are matched against RAW text, because
    `strip_noncode` blanks string literals and a `preload("res://…")` lives in one.

THIS IS STILL A CEILING (closure.py's docstring). A dynamically-built path is
invisible to both programs, so `orphan` means *"no static claim found"*, never
*"provably dead"*. The register records the finding; the deletion is a decision.

AND IT IS A CEILING OVER ONLY ONE TREE, which the output now says on every run.
`closure.SUBJECT` *is* `classify_blueprint.WALK_ROOTS`, so a file outside the
walk can never reach this table — and extraction #2 moves a whole system into a
package ADR-0153 dec. 1 deliberately keeps outside it. Pass 8 is the loop's only
real safety net and it cannot see that destination; goal #3 (*no dead code
ships*) scored `met` for `Audio` on this register's silence about a tree it had
never entered. The two caveat lines are `closure.limit_lines()`, generated from
`WALK_ROOTS` and `_walk_roots.EXTRACTED`, printed here and written into
`docs/RESIDUE.tsv`'s header — an invariant nobody can read is not an instrument,
and a caveat written as prose goes stale the way ADR-0145 dec. 1's number did.
"""
import sys, pathlib, re, io, contextlib, collections

# EVERY MEMBER WAS `.py` UNTIL EXTRACTION #4, AND NOTHING SAID SO. `tools/` also
# holds Godot probes, and `tools/probe_rig_removed.gd` (#745 / ADR-0217 S5) lists
# `res://src/scenes/UnitAnimationViewerScene.gd` in a `HOST_NAMERS` const — it
# names the scene IN ORDER TO CHECK that the scene still resolves with the addon
# gone. That is the docstring's own case, in a suffix the set had never seen: the
# instrument measuring the subject is not the subject. It scored `tool` on a file
# nothing consumes. `declined` outranks `tool` so no CLASS moved, which is
# exactly why it had to be found by reading the diff rather than by a red.
INSTRUMENTS = {"tools/classify_blueprint.py", "tools/touch_matrix.py",
               "tools/closure.py", "tools/residue.py", "tools/asset_census.py",
               "tools/delete_dead_code.py", "tools/probe_rig_removed.gd"}

_argv = sys.argv[:]
sys.argv = ["closure.py"]
_ns = {"__name__": "closuremod", "__file__": "tools/closure.py"}
with contextlib.redirect_stdout(io.StringIO()):
    try:
        exec(open("tools/closure.py").read(), _ns)
    except SystemExit:
        pass
_cb = {"__name__": "cbmod"}
with contextlib.redirect_stdout(io.StringIO()):
    try:
        exec(open("tools/classify_blueprint.py").read(), _cb)
    except SystemExit:
        pass
sys.argv = _argv

# `strip_noncode` is lifted out of touch_matrix.py by source slice rather than
# copied, so the two programs cannot drift apart about what a reference is —
# but WITHOUT exec'ing that module, whose own walk costs 80 seconds and produces
# nothing this program needs.
_tmsrc = open("tools/touch_matrix.py").read()
_fnsrc = re.search(r'^def strip_noncode\(.*?(?=^\S)', _tmsrc, re.S | re.M)
if not _fnsrc:
    sys.exit("tools/touch_matrix.py no longer defines strip_noncode at top level")
_fn = {"re": re}
exec(_fnsrc.group(0), _fn)

unreached = _ns["unreached_src"]
declined_reach = _ns["declined_reach"]
addon_owned_test = _ns["addon_owned_test"]      # ADR-0194 dec. 2, closure.py's
lines_of = _ns["lines_of"]
classify = _cb["classify"]
strip_noncode = _fn["strip_noncode"]

UNREACHED = set(unreached)
GD_LIKE = (".gd",)
SHADER = (".gdshader", ".gdshaderinc", ".glsl", ".glslinc")
SCENE = (".tscn", ".tres", ".material", ".godot")
CODE = GD_LIKE + SHADER + SCENE + (".py",)


def path_view(path, raw):
    """Comments removed, STRING LITERALS KEPT — the view a `res://` path lives in.

    `stripped()` blanks literals, so it cannot be used for a path needle; raw
    text keeps comments, so it must not be. Quote-aware rather than
    `split("#")`, because `print("# hdr")` would otherwise truncate a line and
    LOSE a real claim. THE ONLY ERROR THIS FUNCTION MAY MAKE IS KEEPING A PROSE
    CLAIM, never dropping a real one — so a line holding a triple quote is
    returned verbatim rather than parsed, and an unterminated quote keeps the
    whole line. It is a comment stripper, not a GDScript lexer.
    """
    if path.endswith(SHADER):
        return "\n".join(re.sub(r'(?<!:)//.*$', '', ln) for ln in raw.splitlines())
    if not path.endswith((".gd", ".py")):
        return raw                      # .tscn/.tres/.godot have no `#` comment
    out = []
    for ln in raw.splitlines():
        if '"""' in ln or "'''" in ln:
            out.append(ln)
            continue
        res, q, i, cut = [], None, 0, False
        while i < len(ln):
            ch = ln[i]
            if q:
                if ch == "\\" and i + 1 < len(ln):
                    res.append(ch); res.append(ln[i + 1]); i += 2; continue
                res.append(ch)
                if ch == q:
                    q = None
            elif ch in "\"'":
                q = ch; res.append(ch)
            elif ch == "#":
                cut = True; break
            else:
                res.append(ch)
            i += 1
        out.append(ln if q else ("".join(res) if cut else ln))
    return "\n".join(out)


def stripped(path, raw):
    """Comment-free view. `//` for shaders (the negative lookbehind keeps res://),
    `#` for everything else — strip_noncode's own rule."""
    if path.endswith(SHADER):
        return "\n".join(re.sub(r'(?<!:)//.*$', '', ln) for ln in raw.splitlines())
    return "\n".join(strip_noncode(raw))


# --- who names each unreached file, and from where ---------------------------
corpus = []
for top in ("tests", "tools", "src", "assets", "addons", "docs"):
    for p in pathlib.Path(top).rglob("*"):
        if p.is_file() and p.suffix in CODE + (".md",) and ".godot" not in p.parts:
            corpus.append(p.as_posix())
corpus.append("project.godot")

# One combined stem regex, and a substring pre-filter, because the naive form —
# 34 needles re-scanned over each of ~8,000 corpus files, each of them stripped
# first — runs for 85 seconds and nothing that slow gets run.
stem2files = collections.defaultdict(list)
for f in unreached:
    stem2files[pathlib.Path(f).stem].append(f)
STEM_RE = re.compile(r'\b(' + "|".join(re.escape(s) for s in sorted(stem2files)) + r')\b')
hits = collections.defaultdict(lambda: collections.defaultdict(set))

for c in corpus:
    if c in INSTRUMENTS:
        continue
    if c in UNREACHED:
        origin = "cluster"
    elif c.endswith(".md") or c.startswith("docs/"):
        origin = "doc"          # evidence only — never a class, see the docstring
    elif addon_owned_test(c):
        # ADR-0194 dec. 2: an addon-owned test ships INSIDE the addon, so the
        # top-level directory says `addons` and the claim would land in an
        # EVIDENCE column that is not a CLASS — `klass()` scores only
        # tests/tools/cluster — and a file exercised by nothing but an
        # addon-owned test would read `orphan`, *"no static claim of any kind"*.
        # Same defect as dec. 9's, one level down: what a file IS, not where.
        origin = "tests"
    else:
        origin = c.split("/")[0]
        if origin not in ("tests", "tools", "src", "assets", "addons"):
            origin = "src"
    try:
        raw = pathlib.Path(c).read_text(errors="replace")
    except OSError:
        continue
    # A COMMENT IS NOT A REFERENCE — and until extraction #4 that held for the
    # IDENTIFIER needle only. The docstring's reason for reading paths raw is
    # sound (`strip_noncode` blanks string literals and `preload("res://…")`
    # lives in one) and it over-corrected: raw text also contains comments, so a
    # `## Host use: \`src/scenes/Foo.gd\`` line scored a CLAIM. Three sites
    # register-wide, all three prose — the sprite rig façade's `Host use:` note,
    # `check_move_manifest.py` naming a shader it MOVES, and `WorldMapScene.gd`
    # naming a viewer in a docstring. No class moved on any of them, so nothing
    # was red; the next one need not be so lucky. `path_view` drops comments and
    # KEEPS string literals, which is the view neither existing stripper gives.
    pv = raw if origin == "doc" else path_view(c, raw)   # `doc` is evidence, not a claim
    paths = [f for f in unreached if f != c and f in pv]
    if not paths and not STEM_RE.search(raw):
        continue                       # nothing here names anything unclaimed
    code = raw if origin == "doc" else stripped(c, raw)
    named = set(paths)
    for m in STEM_RE.finditer(code):
        named.update(stem2files[m.group(1)])
    for f in named:
        if f != c:
            hits[f][origin].add(c)

CLASSES = ["declined", "tests", "tools", "cluster", "orphan"]
EVIDENCE = ["tests", "tools", "cluster", "doc", "src", "assets", "addons"]
CLAIMS = [o for o in EVIDENCE if o != "doc"]
LABEL = {"tests": "test", "tools": "tool"}


def klass(f):
    if f in declined_reach:
        return "declined"
    for o in CLASSES[1:-1]:
        if hits[f].get(o):
            return LABEL.get(o, o)
    return "orphan"


def evidence(f, kinds):
    return ",".join(f"{LABEL.get(o, o)}:{len(hits[f][o])}" for o in kinds if hits[f].get(o)) or "-"


# The REGISTER carries claims only. Prose is shown to the reader and kept out of
# the file, so that editing a docstring cannot make the guard red — a register
# that churns on prose is a register somebody switches off.
rows = []
for f in sorted(unreached, key=lambda x: (-lines_of(x), x)):
    rows.append((f, classify(f) or "UNCLASSIFIED", klass(f), lines_of(f),
                 evidence(f, EVIDENCE), evidence(f, CLAIMS)))

# --- what this register is a register OF ---------------------------------------
# `closure.py` owns both halves — its `SUBJECT` *is* `WALK_ROOTS`, and it names
# the extracted packages that are outside it — so the caveat is taken from the
# namespace this program already exec'd rather than re-derived here. Two copies
# of a caveat is how a caveat goes stale on one side only.
limit_lines = _ns["limit_lines"]


by = collections.Counter(r[2] for r in rows)
lab2ord = {LABEL.get(o, o): i for i, o in enumerate(CLASSES)}
for _l in limit_lines():
    print(_l)
print()
print(f"RESIDUE — {len(rows)} unclaimed source files, {sum(r[3] for r in rows):,} lines")
print("  " + "  ".join(f"{k} {by[k]} ({sum(r[3] for r in rows if r[2] == k):,} lines)"
                       for k in sorted(by, key=lambda x: lab2ord[x])))
print()
print(f"{'lines':>6}  {'class':<9}{'bucket':<21}{'file':<52}evidence")
for f, b, k, n, ev, _ in rows:
    print(f"{n:>6}  {k:<9}{b:<21}{f:<52}{ev}")
print("\n  `orphan` means no STATIC claim was found — closure.py's ceiling applies to this")
print("  table too. The register records the finding; the deletion is a decision.")

if "--tsv" in sys.argv:
    out = pathlib.Path("docs/RESIDUE.tsv")
    with out.open("w") as fh:
        # THE REGISTER STATES ITS SUBJECT, not only its result. `closure.py`'s
        # subject IS `WALK_ROOTS`, so this table can never name a file outside it
        # — and an absence it cannot see reads exactly like an absence it checked.
        # That is not hypothetical: `score_goals.py` scored a package outside the
        # walk "no unclaimed files" on this table's silence. A reader who can see
        # the roots on line 1 cannot make that mistake twice.
        for _l in limit_lines("# "):
            fh.write(_l + "\n")
        fh.write("file\tbucket\tclass\tlines\tclaims\n")
        for f, b, k, n, _, claims in rows:
            fh.write(f"{f}\t{b}\t{k}\t{n}\t{claims}\n")
    print(f"\nwrote {out} ({len(rows)} rows)")
