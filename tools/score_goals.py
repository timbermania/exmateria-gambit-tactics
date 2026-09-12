#!/usr/bin/env python3
"""Score the ten goals against one extracted addon, and refuse to guess.

    python3 tools/score_goals.py                 # every addon in the walk
    python3 tools/score_goals.py --addon addons/exmateria_render
    python3 tools/score_goals.py --root ../exmateria-sound/addons/exmateria_sound --system Audio

The ten goals are `godot-learning/CONTEXT.md` -> *Refactor projection -> The ten
goals*. They are cited by number in ten ADRs and in `refactor-loop.md`, and
until this instrument existed **no loop pass checked one of them** -- pass 9
measures lines and reaches (ADR-0131), which are two of goal #4's terms and
none of the other nine. "All goals passed" was unfalsifiable, and an
unfalsifiable charter is the thing this refactor is measured against.

WHAT IT REFUSES TO DO. Five goals admit a mechanical test; five do not. The
instrument never scores an untestable goal from prose -- it reads the recorded
state out of `docs/GOALS.tsv` and checks only that the row cites something that
exists. Anything it can neither test nor find a citation for prints as
`UNSCORED`, which is the finding. Same contract as `classify_blueprint.py`'s
deliberate absence of a catch-all.

THE RATCHET HAS TWO ARMS (ADR-0149 dec. 4). The guard reds when the register
and the mechanical reading DISAGREE, in either direction:

  * a row claims `met` and the test fails      -- the claim is false
  * a row claims `open` and the test passes    -- the register is stale, and
                                                  the moment work lands is
                                                  exactly when it should say so

So a register that honestly reads "five open" is GREEN. Only a lie is red. A
threshold on the open count would make the register worth gaming; agreement
with the code cannot be gamed without changing the code.

`docs/GOALS.tsv` IS HAND-AUTHORED, unlike `docs/RESIDUE.tsv`. Five of the ten
goals have no mechanical test, so a generator could only ever write half the
file and would imply it had written all of it. This reads the register and
argues with it; it never produces it.

WHAT IT WALKS. `_walk_roots.addon_roots()` -- the addons this refactor itself
produced, read from `classify_blueprint.WALK_ROOTS` rather than re-answered
here (ADR-0148). A new extraction is scored the moment its addon enters the
walk; nothing has to remember to add it.

...WITH ONE HOLE, AND `--root` IS THE HANDLE ON IT. A system that extracts into
a PUBLISHED PACKAGE outside `godot-learning/` never enters `WALK_ROOTS` --
`addons/exmateria_sound/` is deliberately excluded (a vendored copy, and walking
it turns `check_no_env_vars.py` red; see `tools/_walk_roots.py`). So the first
system to extract that way is the first one this instrument cannot see, and it
would report nothing rather than report a gap. `--root <path> --system <name>` scores a
directory the walk does not own — for one not yet declared in
`_walk_roots.EXTRACTED`, which is the ONE list of where the source that left the
walk went and which this reads automatically. Both flags are explicit on purpose:
the caller names the package and its system and can be asked why.

**A system with NO rows at all is reported, never failed** — its extraction owes
them at pass 9 and has not got there. The moment it has one row it owes all ten,
which is mechanical and cannot be gamed by writing nine. The system is stated rather than guessed from the
directory name -- `exmateria_sound` does not contain the string "Audio".
"""
import sys, pathlib, re, json, subprocess, collections, io, contextlib, os

PROJECT_DIR = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_DIR / "tools"))
import _walk_roots  # noqa: E402

TSV = pathlib.Path("docs/GOALS.tsv")
COLUMNS = ("extraction", "system", "goal", "scope", "state", "evidence")

def _rel(q: pathlib.Path) -> str:
    """Path relative to PROJECT_DIR when it is under it, else relative to the repo
    root -- a `--root` package legitimately lives outside `godot-learning/`."""
    try:
        return q.relative_to(PROJECT_DIR).as_posix()
    except ValueError:
        return os.path.relpath(q, PROJECT_DIR).replace("\\", "/")


# ---------------------------------------------------------------- classifier
_ns = {"__name__": "cbmod"}
with contextlib.redirect_stdout(io.StringIO()):
    try:
        exec((PROJECT_DIR / "tools" / "classify_blueprint.py").read_text(), _ns)
    except SystemExit:
        pass
classify, SYSTEMS = _ns["classify"], _ns["SYSTEMS"]
SHADER_SUFFIXES, SOURCE_SUFFIXES = _ns["SHADER_SUFFIXES"], _ns["SOURCE_SUFFIXES"]

# `strip_noncode` is touch_matrix's, and it is imported rather than copied on
# purpose: goal #7 is a claim about VOCABULARY, and a docstring that explains
# which PSX compromise a line reproduces is documentation, not vocabulary. Two
# implementations of "which text is code" would drift.
#
# It is used only to decide WHICH LINES are code, never what those lines say --
# because it also blanks string literals, and a `Tune` slug lives in one.
# `Tune.get_value("render.pixel_aspect")` is the single most PUBLIC piece of
# vocabulary this addon has (the slug is what the F3 dashboard prints), and the
# first cut of this instrument scored it zero for exactly that reason: it read 3
# jargon lines where issue #394 had counted `pixel_aspect` x15 by hand. So an
# eligible line is re-read from the RAW text, cut at the first `#` that is not
# inside a quote.
_tm = {}
_tmsrc = (PROJECT_DIR / "tools" / "touch_matrix.py").read_text()
exec(compile(_tmsrc[:_tmsrc.index("\nfiles = cb.walk()")], "touch_matrix.py", "exec"), _tm)
strip_noncode = _tm["strip_noncode"]

# ------------------------------------------------------------------ goal #7
# TWO lexicons, because goal #7 names two different things and one system is
# exempt from exactly one of them (ADR-0150).
#
#   PLATFORM  PlayStation hardware vocabulary.
#   CONTENT   Final Fantasy Tactics vocabulary -- a ROM container, a file
#             format, a place in Ivalice. No system is ever exempt from these:
#             content stays in the host (ADR-0117 dec. 12).
#
# Both lexicons are deliberately SHORT, and every hit prints with its line, so a
# disputed entry is argued over evidence rather than over the lexicon.
#
# A #7 COUNT IS A WORK LIST, NOT A VERDICT (ADR-0150, amended). Every hit sorts
# into one of three, recorded in the register's `evidence` column: **rename**
# (our own concept named after a platform or a container), **membership** (a ROM
# container's name, because the content is in the addon at all -- ADR-0117
# dec. 12, a goal #6 question), or **exempt** (the platform IS the system's
# subject, below). The count is mechanical so it cannot be gamed; the sorting is
# human so it cannot be faked by the lexicon. A rejected alternative was to
# exempt any term "with no better word" -- that marks `pixel_aspect` jargon
# (`pixel_aspect_ratio` is already in the tree) and exempts exactly the ROM
# container names that most deserve flagging.
PLATFORM_JARGON = ("psx", "rgb555", "clut", "tpage", "vram", "libgpu", "gte")
CONTENT_JARGON = ("fft", "waveset", "ivalice", "smd")
JARGON = PLATFORM_JARGON + CONTENT_JARGON

# ADR-0150, on ADR-0117 row 10 and dec. 6: `Render` IS the PlayStation look --
# "Compositor, the depth model, colour modes, shader templating, the fold,
# display aspect" and "about looking like a PlayStation, not about tactics". A
# PSX display fact inside `Render` is its subject matter, not misplaced jargon,
# which is the same strain ADR-0117's Consequences already recorded for goal #8:
# "goal #8 runs backwards inside `Render`, where a PSX compromise is the product
# and a known drop is a regression."
#
# The exemption is a MAP, not a flag, so a second system cannot acquire it
# silently; the count is still reported for an exempt system, never suppressed
# (ADR-0145 dec. 4).
PLATFORM_EXEMPT = {
    "Render": "ADR-0117 row 10 + dec. 6 (via ADR-0150) -- the PSX look is Render's subject",
}


def _cut_comment(raw: str, marker: str) -> str:
    """`raw` up to the first `marker` that is not inside a double-quoted string."""
    inq, i = False, 0
    while i < len(raw):
        c = raw[i]
        if c == '"':
            inq = not inq
        elif not inq and raw.startswith(marker, i):
            return raw[:i]
        i += 1
    return raw


def _blank_block_comments(lines):
    """Shader `/* … */` regions blanked, line count preserved.

    Goal #7 is a claim about VOCABULARY, and ADR-0149 settled the shader case
    when this goal was first mechanised: `RGB555` scores zero for `Render`
    because it appears in `foldsurface_resolve.glsl` only in a comment. That is
    why the GDScript path runs `strip_noncode`, which blanks `#` comments and
    triple-quoted docstrings alike.
    The shader path stripped `//` and nothing else, so the HEADER PARAGRAPH of
    every `.gdshader` in the tree — always a `/* … */` block, by house style —
    read as code. Measured at extraction #4's pass 9: 5 of `Sprite Rig`'s 39
    lines were prose, including two sentences that say the file "renders PSX-era
    sprite animations", and the instrument disagreeing with its own charter is
    the shape ADR-0148 exists to catch (ADR-0228 dec. 5).

    A shader has no string literal to hide a `/*` inside; the one thing that
    looks like a comment and is not is `res://`, and the `//` arm carries the
    same `(?<!:)` guard the caller does.
    """
    out, depth = [], 0
    for ln in lines:
        keep, i = [], 0
        while i < len(ln):
            if depth == 0 and ln.startswith("//", i) and not (i and ln[i - 1] == ":"):
                keep.append(ln[i:])           # a line comment — the `//` arm owns it
                break
            if depth == 0 and ln.startswith("/*", i):
                depth, i = depth + 1, i + 2
                continue
            if depth and ln.startswith("*/", i):
                depth, i = depth - 1, i + 2
                continue
            if depth == 0:
                keep.append(ln[i])
            i += 1
        out.append("".join(keep))
    return out


def jargon_hits(addon: pathlib.Path):
    """(rel, lineno, term, text) for every jargon token in CODE, not in prose."""
    out = []
    for q in sorted(addon.rglob("*")):
        if not (q.is_file() and q.suffix in SOURCE_SUFFIXES):
            continue
        raw = q.read_text(encoding="utf-8", errors="replace").splitlines()
        shader = q.suffix in SHADER_SUFFIXES
        if shader:
            visible = _blank_block_comments(raw)
            eligible = [re.sub(r'(?<!:)//.*$', '', ln) for ln in visible]
        else:
            visible = raw
            eligible = strip_noncode("\n".join(raw))
        for i, (vis, elig) in enumerate(zip(visible, eligible), 1):
            if not elig.strip():
                continue                      # comment- or docstring-only line
            text = _cut_comment(vis, "//" if shader else "#")
            low = text.lower()
            for term in JARGON:
                if term in low:
                    out.append((_rel(q), i, term, text.strip()))
                    break
    return out


# ------------------------------------------------------------------ goal #5
_TABLES = {}


def _tables():
    """(class_name -> file, autoload -> file, file -> bucket) over the whole walk.

    Built once. Reading every walked file to find its `class_name` is cheap; it
    is touch_matrix's O(files x class-names) inner loop that costs 67 seconds,
    and goal #5 only ever scans ONE addon's handful of files against these
    tables. Same five shapes, same classifier, ~700x less work.
    """
    if _TABLES:
        return _TABLES
    cname, sysof = {}, {}
    for q in _ns["walk"]():
        rel = q.as_posix()
        b = classify(rel)
        sysof[rel] = b if isinstance(b, str) else "UNCLASSIFIED"
        if q.suffix == ".gd":
            m = re.search(r'^class_name\s+(\w+)', q.read_text(errors="ignore"), re.M)
            if m:
                cname[m.group(1)] = rel
    auto = {}
    for line in pathlib.Path("project.godot").read_text(errors="ignore").splitlines():
        m = re.match(r'^(\w+)="\*?(res://.+)"', line.strip())
        if m:
            auto[m.group(1)] = m.group(2).replace("res://", "")
    _TABLES.update(cname=cname, auto=auto, sysof=sysof)
    return _TABLES


# `dst` is `classify()`'s BUCKET; `dst_path` is the RESOLVED PATH. They answer two
# different questions, and conflating them was the defect: a bucket is a BUDGET
# oracle ("is the target's system one of the eleven"), and only the path can answer
# the BOUNDARY question ("does this target resolve outside every addon root").
# `record()` computed `dst_path`, keyed the row on the bucket and threw the path
# away, so no reader could ask the boundary question at all and five host reaches
# out of `exmateria_sprite_rig` were invisible to every arm (ADR-0222).
#
# A NamedTuple rather than a bare 6-tuple, and the arity is the point: every
# consumer here unpacks POSITIONALLY, and an un-updated one must fail loudly rather
# than read `dst_path` where it expected `lines`. `score_goals`' own
# `sum(len(h[4]) for h in hits)` is the case that would NOT have raised -- `len()`
# of a path string counts CHARACTERS and returns a plausible number.
Reach = collections.namedtuple("Reach", "rel kind target dst dst_path lines")


def cross_system(reaches):
    """The eleven-systems filter, applied BY THE CONSUMER rather than by `record()`.

    `record()` keeps every reach that LEAVES THE ADDON, including targets that
    classify to `infrastructure` / `content` / `platform` / nothing at all --
    because dropping them inside `record()` is what made them invisible to every
    reader, not only to the ones asking the budget question. The two production
    readings (goal #5 below, and `check_addon_portability` arm 1) ARE budget
    questions and keep this filter verbatim, so their numbers do not move: a
    scanner change that moves a burn-down is indistinguishable from debt being
    paid (ADR-0205 dec. 7).

    \U0001f534 DO NOT WIDEN THIS BY ADDING BUCKETS. Relaxing it to accept every
    bucket yields 30 rows tree-wide of which 25 target `addons/exmateria_platform/`,
    because `classify()` books the port's own files `platform` -- and reaching the
    port is exactly what a portable addon is ALLOWED to do (ADR-0139 dec. 12,
    ADR-0202 dec. 2). `platform` names a TIER and a BUCKET (#575). A reader that
    wants the boundary question filters on `dst_path` against the addon roots; it
    does not relax this one.
    """
    return [r for r in reaches if r.dst and r.dst in SYSTEMS]


# Every identifier-shaped run in a line. A SUPERSET of the whole words in it, which
# is what a gate in front of a `\b`-anchored regex needs to be.
_IDENTS = re.compile(r'[A-Za-z_]\w*')


def outbound_reaches(addon_rel: str, system: str):
    """`Reach(rel, kind, target, dst, dst_path, lines)` for every reach that LEAVES.

    Every reach out of the addon root, UNFILTERED -- `cross_system()` above is the
    eleven-systems filter and both production readings apply it themselves.

    touch_matrix's five shapes, scoped to one addon.

    🔴 THIS DOCSTRING USED TO SAY `Tune` AND THE SHARED KERNEL "DO NOT
    APPEAR" HERE. THEY DO. Measured 2026-09-05 while building ADR-0232, with the
    function itself rather than by reading `record()`: the `Tune` reach out of
    `exmateria_sprite_rig` came back as
    `Reach(kind='autoload', target='Tune', dst='platform',
    dst_path='src/core/Tune.gd')`. This function is UNFILTERED and says so two
    lines up; it is `cross_system()` that drops the row, because `platform` is not
    one of the eleven systems. The distinction is load-bearing and the old wording
    hid it: `src/core/Tune.gd` is a HOST file, so `cross_system()`'s own defence
    -- "reaching the port is exactly what a portable addon is ALLOWED to do"
    (ADR-0139 dec. 12, ADR-0140 dec. 9) -- does not cover this row at all. The
    bucket said port; the address said host (ADR-0223).

    Verified equal to `touch_matrix.py`'s own row for the addon before this
    replaced a read of its cache -- when two registers describe the same set,
    diff them -- a principle ADR-0147/0148 coined and which this comment used to
    attribute to ADR-0146, which does not contain it (`check_adr_quotes.py`).
    The cache read was correct and unusably slow: a guard
    that must re-run a 67-second scan to be trustworthy is a guard nobody runs,
    and a stale cache is the ADR-0148 defect wearing a filename.
    """
    t = _tables()
    out = collections.defaultdict(set)
    inside = addon_rel + "/"

    # \U0001f534 THE TWO NAME LOOPS BELOW ARE THIS SCAN'S WHOLE COST, and the cost was
    # REPETITION rather than work: `re.search(r'\b' + re.escape(n) + ..., ln)` ran once
    # per (line x name) -- 16.8 MILLION calls tree-wide -- and each one re-escaped the
    # name and re-looked-up the pattern in `re`'s internal cache. 95% of the 17-second
    # whole-tree walk was `re._compile` and `re.escape`, not matching.
    #
    # So: compile each pattern ONCE here, and gate it behind a plain substring test.
    # The gate is a NECESSARY CONDITION of the regex it guards, not an approximation of
    # it -- `\b<name>\.` cannot match a line that does not contain `<name>.` as a
    # substring, and `\b<cn>\b` cannot match a line without `<cn>` in it. The regex
    # still decides every row; the gate only decides whether to ask. Verified by
    # diffing all 826 reach rows over all 7 walk roots before and after (identical).
    #
    # THE GATE IS NOW THE LINE'S OWN IDENTIFIERS rather than one substring test per
    # name. With 315 `class_name`s the per-line sweep asked 343 questions of every
    # line to answer at most a couple; `_IDENTS.findall(ln)` asks the line what names
    # it contains ONCE and looks each up. Same necessary-condition argument, one step
    # tighter: `\b<n>\b` and `\b<n>\.` can only match where `<n>` is a whole word,
    # and a whole word in `ln` is always one of `_IDENTS`' matches (which is a
    # SUPERSET -- it also yields the tail of `9Foo`, and an over-yielding gate is
    # harmless because the regex below still decides). Duplicates are free: `record`
    # lands in a set keyed on (kind, rel, target, lineno). Verified the same way the
    # gate above was: all 441 reach rows over all 8 walk roots, before and after,
    # identical -- with dropping one `class_name` that DOES produce rows as the
    # control that says the diff can see a difference (441 -> 393).
    auto_pats = {name: (path, re.compile(r'\b' + re.escape(name) + r'\.'))
                 for name, path in t["auto"].items()}
    cname_pats = {cn: (target, re.compile(r'\b' + re.escape(cn) + r'\b'))
                  for cn, target in t["cname"].items()}

    def record(dst_path, kind, rel, target, lineno):
        # The exclusion is "the target is INSIDE this addon", never "the target's
        # bucket equals this system". Those are the same set only while a system
        # has no host-side residue, and every extraction after `Render` will have
        # some -- a panel whose subject splits, a screen that stays in the host.
        # Keyed on the bucket, an addon reaching back into its own system's
        # leftovers scores zero, which is goal #5 failing while the test passes.
        #
        # The eleven-systems filter USED TO LIVE HERE and does not any more. Keyed
        # on the bucket, a row whose target classifies outside the eleven was not
        # kept as an unscored row -- it was DROPPED, so returning the path as well
        # would have surfaced nothing. Each consumer filters; see `cross_system()`.
        if dst_path.startswith(inside):
            return
        out[(kind, rel, target, t["sysof"].get(dst_path), dst_path)].add(lineno)

    for q in sorted((PROJECT_DIR / addon_rel).rglob("*")):
        if not (q.is_file() and q.suffix in SOURCE_SUFFIXES):
            continue
        rel = _rel(q)
        raw = q.read_text(errors="ignore").splitlines()
        if q.suffix in SHADER_SUFFIXES:
            for i, rawln in enumerate(raw, 1):
                for m in re.finditer(r'#include\s+"res://([^"]+)"',
                                     re.sub(r'(?<!:)//.*$', '', rawln)):
                    record(m.group(1), "#include", rel, m.group(1), i)
            continue
        for i, (rawln, ln) in enumerate(zip(raw, strip_noncode("\n".join(raw))), 1):
            # `res://` is a necessary condition of both patterns below, and
            # `get_node` of the one after the name loops. Same gate as the name
            # loops, asked of a line rather than of a name.
            if "res://" in rawln:
                for m in re.finditer(r'(?:preload|load)\("res://([^"]+)"\)', rawln):
                    record(m.group(1), "preload", rel, m.group(1), i)
                for m in re.finditer(r'^\s*const\s+\w+\s*:?=\s*"res://([^"]+)"', rawln):
                    record(m.group(1), "const path", rel, m.group(1), i)
            for tok in _IDENTS.findall(ln):
                a = auto_pats.get(tok)
                if a is not None and a[1].search(ln):
                    record(a[0], "autoload", rel, tok, i)
                c = cname_pats.get(tok)
                if c is not None and c[0] != rel and c[1].search(ln):
                    record(c[0], "class_name", rel, tok, i)
            if "get_node" in rawln:
                for m in re.finditer(r'get_node(?:_or_null)?\("/root/(\w+)"', rawln):
                    if m.group(1) in t["auto"]:
                        record(t["auto"][m.group(1)], "/root/ reach", rel, m.group(1), i)
    # `dst` is now None for a target outside the eleven, and `None < str` raises,
    # so the sort key spells the None out rather than letting `sorted` reach it.
    return [Reach(rel, kind, target, dst, dst_path, sorted(lines))
            for (kind, rel, target, dst, dst_path), lines
            in sorted(out.items(), key=lambda kv: (kv[0][0], kv[0][1], kv[0][2],
                                                   kv[0][3] or "", kv[0][4]))]


# ------------------------------------------------------------------ goal #3
def residue_rows(addon_rel: str):
    p = pathlib.Path("docs/RESIDUE.tsv")
    if not p.exists():
        return []
    return [ln.split("\t") for ln in p.read_text(encoding="utf-8").strip().splitlines()
            if ln.startswith(addon_rel + "/")]


# ------------------------------------------------------------------- scoring
GOALS = {
    1: ("a greenfield slate", "per-system", "attested"),
    2: ("renaming carries a translation table", "per-system", "mechanical"),
    3: ("remove dead code", "per-system", "mechanical"),
    4: ("catch drift cheaply and continuously", "per-system", "mechanical"),
    5: ("portable systems", "per-system", "mechanical"),
    6: ("assets as a superset", "per-domain", "attested"),
    7: ("no PSX/FFT jargon in engine vocabulary", "per-system", "mechanical"),
    8: ("PSX compromises divorced", "per-system + E1", "attested"),
    9: ("improve the architecture as we go", "per-system", "attested"),
    10: ("eventual support for authoring content", "per-domain", "attested"),
}


def mechanical(goal: int, addon: pathlib.Path, system: str):
    """(verdict, one-line reading) for goals GOALS marks `mechanical`.

    `verdict` is True (`met`), False (`open`), or **None (`unscorable`)** — a test
    whose EVIDENCE does not cover this root. That third value exists because the
    second cut of this instrument scored `Audio` goal #3 `met` on the grounds that
    an out-of-walk package has no rows in `docs/RESIDUE.tsv`. It has no rows
    because the register never looked, which is ADR-0148's defect reappearing in
    the instrument written to catch it. A test that cannot see must say so.
    """
    rel = _rel(addon)
    in_walk = addon in _walk_roots.walk_roots()
    if goal == 2:
        ctx = (PROJECT_DIR / "CONTEXT.md").read_text(encoding="utf-8")
        want = f"translation table (`{system}`)"
        return want in ctx, ("CONTEXT.md carries %s" % want if want in ctx
                             else "CONTEXT.md has no %s" % want)
    if goal == 3:
        # `declined` is NOT deadness (ADR-0154 dec. 2, on ADR-0135 dec. 11 and
        # `residue.py`'s own class list): a declined scene is a candidate root
        # DELIBERATELY not kept, and its deletion is scheduled work owned by the
        # scene, not by whichever addon happens to hold one of its files. Every
        # other residue class is a real unclaimed file and fails.
        if not in_walk:
            return None, ("docs/RESIDUE.tsv is derived over WALK_ROOTS and this root is "
                          "outside it, so an empty result means the register never looked, "
                          "not that nothing is unclaimed")
        rows = residue_rows(rel)
        bad = [r for r in rows if r[2] != "declined"]
        kept = [r for r in rows if r[2] == "declined"]
        note = ("" if not kept else
                "; %d declined (deliberately kept pending its scene's deletion): %s"
                % (len(kept), ", ".join(r[0].rsplit("/", 1)[-1] for r in kept)))
        if bad:
            return False, "; ".join(f"{r[0]} is {r[2]}" for r in bad) + note
        return True, ("no unclaimed file under %s" % rel) + note
    if goal == 4:
        if in_walk:
            return True, "in classify_blueprint.WALK_ROOTS"
        n = len(list((PROJECT_DIR / "tools").glob("check_*.py")))
        if any(addon == row.path for row in _walk_roots.extracted_roots()):
            # Partial, and the split is the point: the instruments that read
            # `_walk_roots.EXTRACTED` follow the system out of the walk; the rest
            # scan WALK_ROOTS and do not.
            return False, ("NOT in WALK_ROOTS. Declared in _walk_roots.EXTRACTED, so "
                           "check_addon_portability.py and this scorecard follow it out "
                           f"-- the other {n - 1} tools/check_*.py scan WALK_ROOTS and "
                           "are green because they no longer look (ADR-0148)")
        return False, ("NOT in WALK_ROOTS and NOT in _walk_roots.EXTRACTED -- nothing "
                       "watches this root at all (ADR-0148)")
    if goal == 5:
        # GOAL #5 IS A CONJUNCTION, and until ADR-0232 this line was half of one.
        #
        # The reach half below is a BUDGET question -- does this addon NAME another
        # system -- and it read 0 for `Sprite Rig` while the addon did not COMPILE
        # in a project that did nothing for it. Both numbers were right about what
        # they measured; nothing joined them. `cross_system()` drops `platform`,
        # and `res://src/core/Tune.gd` is a HOST file wearing the port's bucket, so
        # that filter's own defence -- reaching the port is allowed -- did not
        # cover the row that broke the addon (ADR-0223: a reach has a BUCKET and an
        # ADDRESS, and goal #5 only ever read the bucket).
        #
        # The charter says a system "could ship to another tactics RPG with its
        # interface intact". A reach count cannot answer "could ship"; the stranger
        # rig can, and it had no say here at all -- PR #850's rig printed goal #5
        # UNMET naming two files on the same tree, and the ratchet kept asserting
        # `Sprite Rig 6 met, 4 open` regardless. So the INSTALL half joins the
        # budget half, and neither instrument claims the word alone (the shape
        # ADR-0202 dec. 1 set for `isolated` vs `installable`).
        hits = cross_system(outbound_reaches(rel, system))
        n = sum(len(h.lines) for h in hits)
        who = collections.Counter()
        for h in hits:
            who[f"{h.dst}.{h.target} ({h.kind})"] += len(h.lines)
        reach = ("0 cross-system reach lines leave the addon" if not n else
                 "%d reach lines: %s"
                 % (n, ", ".join(f"{k} x{v}" for k, v in who.most_common())))
        rig = _walk_roots.rig_for(addon)
        if rig is None:
            # ADR-0229 dec. 8, answered rather than filed: a root no rig names has
            # never been ASKED to install anywhere, and `unscorable` is the
            # charter's existing sixth state for exactly this -- a test whose
            # evidence does not cover the root. Reading a 0 here as a clean bill is
            # the ADR-0148 defect (green because it no longer looks) in the one
            # goal that is about leaving.
            return None, (reach + "; but NO STRANGER RIG names this root in "
                          "_walk_roots.RIGS, so nothing has tried to INSTALL the addon "
                          "outside the host -- the reading above is a budget count, not "
                          "an installability verdict (ADR-0229 dec. 8, ADR-0232)")
        where = _rel(rig.run_sh)
        if not rig.in_suite:
            where += " (declared in _walk_roots.RIGS; NOT run by the suite -- stock "
            where += "Godot and a staged publish, so it is a hand-run rig)"
        debt = rig.known_failure_rows()
        if debt:
            names = ", ".join("%s %s" % (p.rsplit("/", 1)[-1], t) for p, t in debt)
            return False, ("%s, BUT the stranger rig declares %d file(s) that do not "
                           "compile in a project that did nothing for the addon: %s. "
                           "Rig: %s" % (reach, len(debt), names, where))
        if n:
            return False, ("%s. The rig's burn-down is empty, so the INSTALL half is "
                           "clean and this row is the budget half alone. Rig: %s"
                           % (reach, where))
        return True, ("%s, and the stranger rig declares no file that fails to compile "
                      "in a project that did nothing for it. Rig: %s" % (reach, where))
    if goal == 7:
        hits = jargon_hits(addon)
        content = [h for h in hits if h[2] in CONTENT_JARGON]
        platform = [h for h in hits if h[2] in PLATFORM_JARGON]
        exempt = system in PLATFORM_EXEMPT
        note = ""
        if platform:
            byfile = collections.Counter(h[0].rsplit("/", 1)[-1] for h in platform)
            note = "; %d platform lines (%s)%s" % (
                len(platform), ", ".join(f"{k} x{v}" for k, v in byfile.most_common(6)),
                " EXEMPT: " + PLATFORM_EXEMPT[system] if exempt else "")
        blocking = content if exempt else hits
        if not blocking:
            return True, "0 content-jargon lines" + note
        byfile = collections.Counter(h[0].rsplit("/", 1)[-1] for h in blocking)
        return False, "%d jargon lines across %d files, top: %s%s" % (
            len(blocking), len(byfile),
            ", ".join(f"{k} x{v}" for k, v in byfile.most_common(6)), note)
    raise AssertionError(f"goal #{goal} has no mechanical test")


def read_tsv():
    if not TSV.exists():
        return []
    rows = [ln.split("\t") for ln in TSV.read_text(encoding="utf-8").strip().splitlines()]
    assert tuple(rows[0]) == COLUMNS, f"docs/GOALS.tsv header is {rows[0]}"
    return rows[1:]


def evidence_exists(ev: str) -> bool:
    """A citation has to point at something. ADR file, CONTEXT.md heading, issue,
    or a path in the tree -- anything else is prose wearing a citation's clothes."""
    ev = ev.strip()
    if not ev or ev == "-":
        return False
    for m in re.finditer(r'ADR-(\d{4})', ev):
        if not list((PROJECT_DIR / "docs/adr").glob(m.group(1) + "-*.md")):
            return False
    for m in re.finditer(r'(?<![\w/])((?:src|tools|docs|addons|assets|tests)/[\w./-]+)', ev):
        if not (PROJECT_DIR / m.group(1)).exists():
            return False
    return bool(re.search(r'ADR-\d{4}|#\d+|(?:src|tools|docs|addons|assets|tests)/', ev))


def main():
    os.chdir(PROJECT_DIR)
    out_of_walk: dict = {}
    only = None
    if "--addon" in sys.argv:
        only = sys.argv[sys.argv.index("--addon") + 1].rstrip("/")

    if "--root" in sys.argv:
        extra = (PROJECT_DIR / sys.argv[sys.argv.index("--root") + 1].rstrip("/")).resolve()
        if not extra.is_dir():
            print(f"--root {extra} is not a directory")
            return 1
        addons = [extra]
    else:
        # THE WALK'S ADDONS *PLUS* THE PACKAGES THAT HAVE LEFT IT. `--root` was this
        # instrument's original handle on the hole below, and a handle is a thing
        # somebody has to remember to pull: with no arguments this scored `Render`
        # alone and reported `GOALS.tsv OK` while extraction #2's ten Audio rows were
        # unratcheted -- the register could say anything about `Audio` and no
        # invocation anyone actually runs would argue. That is this file's own
        # sentence, "it would report nothing rather than report a gap", turned on
        # itself.
        #
        # `_walk_roots.EXTRACTED` is the declaration that closes it, and it did not
        # exist when `--root` was written; its docstring already names this file as
        # one of the five instruments blind at the extraction boundary. It carries the
        # SYSTEM too, so `--system` is not needed here -- the guess this instrument
        # refuses to make ("exmateria_sound does not contain the string Audio") is
        # answered by declaration, not by inference. `--root`/`--system` stay, for a
        # package nobody has declared yet.
        #
        # KEYED BY PACKAGE, NOT BY ROW. `EXTRACTED` is a list of SYSTEMS and
        # nothing stops two of them naming one package -- the addon is the unit
        # that gets walked, so a row-per-append scores that package twice, and a
        # path-keyed dict silently keeps only the LAST system's name. Both blocks
        # then print under one system and the other vanishes from the scorecard
        # entirely. The same shape cost extraction #2 a doubled `--delta`
        # measurement (ADR-0153 dec. 9); there the two readings disagreed by an
        # amount nobody reads, here the wrong half is the NAME, which is the half
        # everybody reads.
        addons = [a for a in _walk_roots.addon_roots()
                  if only is None or _rel(a) == only]
        for row in _walk_roots.extracted_roots():
            if only is None or _rel(row.path) == only:
                if row.path not in out_of_walk:
                    addons.append(row.path)
                out_of_walk.setdefault(row.path, []).append(row.system)
    if not addons:
        print("no addon matched; the walk holds: " +
              ", ".join(_rel(a) for a in _walk_roots.addon_roots()) +
              "; extracted: " +
              ", ".join(_rel(e.path) for e in _walk_roots.extracted_roots()))
        return 1

    # SUBJECT BEFORE RESULT. Every instrument here should say what it looked at,
    # not only what it found — the three failures of 2026-08-22 were all a subject
    # and a question drifting apart, which nothing in a result can show. The one
    # instrument that had never surprised anyone about scope, `classify_blueprint.py`,
    # is the one that already ends by printing its roots.
    print("subject: %s  |  register docs/GOALS.tsv  |  reach + jargon read from each "
          "addon's own files" % ", ".join(_rel(a) for a in addons))
    print("         residue read from docs/RESIDUE.tsv, derived over %s"
          % ", ".join(_rel(r) for r in _walk_roots.walk_roots()))

    rows = read_tsv()
    recorded = {(r[1], int(r[2])): r for r in rows}
    problems, out_rows = [], []

    for addon in addons:
        rel = _rel(addon)
        # A system's name is the classifier's answer for its own files, never a
        # string parsed out of the directory name.
        buckets = collections.Counter(
            classify(_rel(q))
            for q in addon.rglob("*") if q.is_file() and q.suffix in SOURCE_SUFFIXES)
        system = next((b for b, _ in buckets.most_common() if b in SYSTEMS), None)
        # A package outside the walk has no classifier verdict; `_walk_roots.EXTRACTED`
        # declares its system, which is exactly the fact `--system` used to supply.
        if system is None and addon in out_of_walk:
            declared = out_of_walk[addon]
            if len(declared) > 1:
                # REFUSED BY NAME, not split on a share. The ten goals are scored
                # per SYSTEM and every measurement here -- reach lines, jargon
                # lines, residue -- is read from the PACKAGE's files. A package
                # holding two systems cannot say which system's lines it is
                # reporting, and apportioning them by file count is the withdrawn
                # "largest falling system" heuristic wearing a different hat
                # (ADR-0153 dec. 9). Printed rather than skipped: a scorecard
                # that quietly omits a system reads as a system with nothing owed.
                print(f"\n-- {rel}: `_walk_roots.EXTRACTED` declares "
                      f"{len(declared)} systems into this one package "
                      f"({', '.join(sorted(declared))}). The ten goals score a "
                      f"system and every reading here is package-wide, so this "
                      f"scorecard cannot say whose lines these are. Score them "
                      f"with --root <package> --system <name> against a package "
                      f"per system, or split the package.")
                continue
            system = declared[0]
        if system is None and "--root" in sys.argv:
            # An out-of-walk package has no classifier verdict, so the caller states
            # the system. Guessing it from the directory name was the first cut and
            # is wrong for the case that motivates the flag: `exmateria_sound` does
            # not contain the string "Audio".
            if "--system" not in sys.argv:
                print(f"\n-- {rel}: outside classify_blueprint's walk, so it has no bucket. "
                      f"Re-run with --system <name>; the register holds "
                      f"{sorted({r[1] for r in rows if r[1]})}.")
                continue
            system = sys.argv[sys.argv.index("--system") + 1]
            if system not in SYSTEMS:
                print(f"--system {system} is not one of the eleven: {SYSTEMS}")
                return 1
        if system is None:
            # The shared kernel is `schema`, not a system (ADR-0139 dec. 9), and
            # the ten goals are the charter for SYSTEMS. Printed rather than
            # skipped silently: a future addon that lands unclassified would
            # otherwise vanish from the scorecard without anyone noticing.
            print(f"\n-- {rel}: the classifier books no file here to a system "
                  f"({', '.join(sorted(buckets))}); the ten goals score systems, so it is "
                  f"not scored here.")
            continue

        has_any = any(k[0] == system for k in recorded)
        print(f"\n{system}  ({rel})")
        print("-" * 72)
        if not has_any:
            print(" -- no rows in docs/GOALS.tsv yet: the extraction that owns this "
                  "system\n    writes them at pass 9. Reported below, not enforced --")
        for g in sorted(GOALS):
            title, scope, kind = GOALS[g]
            row = recorded.get((system, g))
            state = row[4].strip() if row else "UNSCORED"
            ev = row[5].strip() if row and len(row) > 5 else ""
            if kind == "mechanical":
                ok, reading = mechanical(g, addon, system)
                want = "unscorable" if ok is None else ("met" if ok else "open")
                mark = "OK " if state == want else ("RED" if has_any else "-- ")
                if state != want and has_any:
                    problems.append(
                        f"{system} goal #{g} ({title}): GOALS.tsv says `{state}`, "
                        f"the code says `{want}` -- {reading}")
                print(f" {mark} #{g:<2} {title:<44} {state:<9} {reading}")
            else:
                if state == "UNSCORED":
                    if has_any:
                        problems.append(f"{system} goal #{g} ({title}): no row in docs/GOALS.tsv")
                    print(f" {'RED' if has_any else '-- '} #{g:<2} {title:<44} UNSCORED  no row")
                elif not evidence_exists(ev):
                    problems.append(
                        f"{system} goal #{g} ({title}): state `{state}` cites nothing that "
                        f"exists -- evidence reads {ev!r}")
                    print(f" RED #{g:<2} {title:<44} {state:<9} evidence does not resolve")
                else:
                    print(f" ok  #{g:<2} {title:<44} {state:<9} {ev}")
                    reading = ev
            out_rows.append((row[0] if row else "?", system, str(g), scope,
                             state if state != "UNSCORED" else "open",
                             ev or "-"))

    if problems:
        print(f"\nGOALS.tsv disagrees with the code in {len(problems)} place(s):\n")
        for p in problems:
            print("  *", p)
        return 1
    print("\nGOALS.tsv OK")
    for sysname in sorted({r[1] for r in out_rows}):
        c = collections.Counter(r[4] for r in out_rows if r[1] == sysname)
        print("  %-10s %s%s" % (
            sysname, ", ".join(f"{v} {k}" for k, v in sorted(c.items())),
            "" if any(k[0] == sysname for k in recorded)
            else "   (reported, not enforced — no rows yet)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
