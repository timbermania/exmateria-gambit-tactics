#!/usr/bin/env python3
"""The closure from the declared root sets — ADR-0112 dec. 1, mechanized.

*"Dead code is what the root set cannot reach."* `check_root_set.py` walks
candidacy and the assembler pairing; it is this walk's INPUT, not this walk.
Run from the package root.

    python3 tools/closure.py [--list] [--assets] [--holes]

SEEDS — the `root` rows of `docs/ROOT_SET.tsv` (11 scenes + their scripts) plus
every autoload in `project.godot`, which Godot instantiates before any scene and
which therefore cannot be reached *from* a root.

EDGES — seven, all static:
    .tscn  [ext_resource path="res://…"]        scripts, scenes, shaders, resources
    .tres  [ext_resource path="res://…"]
    .gd    preload("res://…") / load("res://…")
    .gd    any "res://…" string on a non-comment line   <- the const-indirection case
    .gd    extends "res://…"  /  extends ClassName  /  a bare ClassName reference
    shader #include "res://…"
    *      a res:// literal holding `%` or ending in `/` reaches that SUBTREE

THE APPROXIMATION IS ONE-SIDED, AND IT IS A CEILING ON DEADNESS, NOT A FLOOR.
Every edge above is static. A path the code builds at runtime — `"res://assets/
effects/E%03d/" % id` — is caught only by the subtree rule, and a path assembled
from two variables is not caught at all. So **UNREACHED is a candidate list, not
a verdict**: everything genuinely dead is in it, together with anything reached
only dynamically. `--holes` prints the dynamic-load sites inside reached code,
which is the exact list of places the walk could be wrong.

The `.gd` register alone holds 487 `preload("literal")`, 48 `load("literal")`
and 144 non-literal `load()` at trunk. ADR-0135's 371/30/128 reproduces exactly
at `a5ccb9fa2` by this method.
"""
import csv, collections, pathlib, re, sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import _walk_roots            # walk_files: rglob does not follow the
                              # addons/exmateria_sound symlink

ROOT = pathlib.Path(".")
SRC_SUFFIXES = (".gd", ".gdshader", ".gdshaderinc", ".glsl", ".glslinc")
TEXT_SUFFIXES = SRC_SUFFIXES + (".tscn", ".tres", ".material", ".godot")


def tracked(p):
    return ".godot" not in p.parts


# --- the universe ------------------------------------------------------------
all_files = [p for p in _walk_roots.walk_files(ROOT) if tracked(p)]
universe = sorted(p.as_posix() for p in all_files
                  if p.parts[0] in ("src", "assets", "addons", "tools", "tests"))
existing = set(universe)
cname2file = {}
for p in all_files:
    if p.suffix != ".gd":
        continue
    m = re.search(r'^class_name\s+(\w+)', p.read_text(errors="replace"), re.M)
    if m:
        cname2file[m.group(1)] = p.as_posix()

# SCOPED TO THE `[autoload]` BLOCK, and that is not tidiness. `project.godot` is
# an ini file and `^(\w+)="res://…"` matches a key in ANY section. Extraction #4
# added `[exmateria_sprite_rig] content_root="res://assets/"` (ADR-0202's
# host-injected content root; `[exmateria_battlefield]` has carried the same key
# since extraction #3), and the unscoped read seeded a phantom autoload named
# `content_root` pointing at `assets/`. It cost nothing here only by luck —
# `close_over` drops a seed that is not a file, so the walk printed
# `SEED MISSING — assets/` on every run and reached the same set. The luck does
# not generalise: a settings key naming a real file would have seeded it as an
# autoload, and everything it reaches would have left the residue register as
# `claimed` with no way to notice. `autoload_reach.py` already scopes this way.
_pg = pathlib.Path("project.godot").read_text(errors="ignore")
_autoload_block = _pg.split("[autoload]", 1)[1].split("\n[", 1)[0] if "[autoload]" in _pg else ""
autoloads = {}
for line in _autoload_block.splitlines():
    m = re.match(r'^(\w+)="\*?res://(.+)"', line.strip())
    if m:
        autoloads[m.group(1)] = m.group(2)

RES = re.compile(r'"res://([^"]+)"')
IDENT = re.compile(r'\b[A-Za-z_]\w*\b')
CNAMES = set(cname2file)
# sets, not lists: the walk runs twice (roots, then declined roots)
holes, dangling, patterned = set(), set(), collections.Counter()
HOLE = re.compile(r'(?:ResourceLoader\.)?\bload\s*\(\s*(?!")')
FMT = re.compile(r'%[-+ #0]*\d*(?:\.\d+)?[a-zA-Z]|\{[^}]*\}')


def pattern_hits(lit):
    """A path the code BUILDS: `res://assets/effects/E%03d/frames.json`.

    Each `%…`/`{…}` placeholder stands for one path SEGMENT, so it expands to
    `[^/]+` — not to the whole subtree. Widening it to the containing directory
    was the first version of this rule and it reached every one of the 23,827
    files from a single literal, reporting 0.0% of assets unread.
    """
    out, last = [], 0
    for m in FMT.finditer(lit):
        out.append(re.escape(lit[last:m.start()])); out.append("[^/]+"); last = m.end()
    out.append(re.escape(lit[last:]))
    rx = re.compile("^" + "".join(out) + ("" if lit.endswith("/") else "$"))
    return [u for u in universe if rx.match(u)]


def out_edges(rel):
    """Everything `rel` statically names, deduped."""
    return sorted(set(_out_edges(rel)))


def _out_edges(rel):
    p = pathlib.Path(rel)
    if p.suffix not in TEXT_SUFFIXES:
        return
    txt = p.read_text(errors="replace")
    shader = p.suffix in (".gdshader", ".gdshaderinc", ".glsl", ".glslinc")
    skip = FACADE_SKIP_LINES.get(rel, ())
    for i, ln in enumerate(txt.splitlines(), 1):
        if i in skip:
            continue                    # a re-export is not a use — see FACADE_EXPORTS
        if shader:
            ln = re.sub(r'(?<!:)//.*$', '', ln)
        elif ln.lstrip().startswith("#"):
            continue
        for m in RES.finditer(ln):
            t = m.group(1)
            if t in existing:
                yield t
                continue
            if FMT.search(t) or t.endswith("/"):
                hits = pattern_hits(t)
                patterned[t] = len(hits)
                yield from hits
                continue
            dangling.add(f"{rel}:{i}  {t}")
        if p.suffix == ".gd":
            code = re.sub(r'"[^"]*"', '""', ln.split("#")[0])
            if HOLE.search(code):
                holes.add(f"{rel}:{i}")
            # tokenise once and intersect, rather than running ~600 regexes per line
            for tok in set(IDENT.findall(code)) & CNAMES:
                f = cname2file[tok]
                if f != rel:
                    yield f
            # `ExMateriaSpriteRig.UnitDisplay` — the consumer half of a façade
            # re-export. The line above already yields the FAÇADE (its
            # `class_name` is a CNAME); this yields the MEMBER, which is the
            # edge ADR-0211 dec. 4's shape moved off the publisher.
            if MEMBER is not None:
                for _fac, _mem in MEMBER.findall(code):
                    t = CNAME2EXPORTS[_fac].get(_mem)
                    if t and t != rel:
                        yield t


# --- addon façades: a re-export is not a use --------------------------------
# ADR-0211 dec. 4 gives each addon ONE global name and publishes its whole
# surface as `const <Name> = preload("res://addons/<a>/…")` on that one file.
# Read as an ordinary edge, that table makes every member of every addon
# reachable from any root that touches the façade — and `src/scenarios/
# NavigatorMain.gd` (a root) names `ExMateriaSpriteRig`, so at extraction #4
# nineteen sprite-rig files (2,656 lines) stopped being answerable by this walk.
# The register did not go red. It went QUIET, which is worse: `docs/RESIDUE.tsv`
# lost `ResourceHotReload.gd` — whose only namer outside the addon is a DECLINED
# scene — and reported one fewer unclaimed file as though something had been
# claimed. Pass 8 is the only real safety net (`refactor-loop.md`), and a façade
# per system means this blindness scales with the refactor rather than with the
# addon.
#
# So a façade's `const X = preload(...)` line is a RE-EXPORT and yields nothing,
# and `<Facade>.X` written anywhere yields an edge to X instead. The claim moves
# from the publisher to the consumer, which is where it always was: nothing
# about `ExMateriaSpriteRig` USES `ResourceHotReload`. A member reached by a
# plain `preload("res://addons/…")` from a sibling inside the addon is untouched
# — that IS a use, and it is how `CinematicPoseLUT` stays reached.
#
# The façade is `addons/<name>/<name>.gd` with a `class_name`: the shape
# ADR-0211 dec. 4 mandates, not a heuristic over any file with a const table.
FACADE_EXPORTS = {}          # facade rel -> {const name: target rel}
FACADE_SKIP_LINES = {}       # facade rel -> {line numbers that are re-exports}
CNAME2EXPORTS = {}           # class_name -> {const name: target rel}
_EXPORT = re.compile(r'^const\s+(\w+)\s*=\s*preload\("res://([^"]+)"\)')
for _cfg in sorted(ROOT.glob("addons/*/plugin.cfg")):
    _fac = _cfg.parent / f"{_cfg.parent.name}.gd"
    if not _fac.is_file():
        continue
    _rel = _fac.as_posix()
    _txt = _fac.read_text(errors="replace")
    _m = re.search(r'^class_name\s+(\w+)', _txt, re.M)
    if not _m:
        continue
    _exp, _skip = {}, set()
    for _i, _ln in enumerate(_txt.splitlines(), 1):
        _e = _EXPORT.match(_ln)
        if _e and _e.group(2) in existing:
            _exp[_e.group(1)] = _e.group(2)
            _skip.add(_i)
    if _exp:
        FACADE_EXPORTS[_rel] = _exp
        FACADE_SKIP_LINES[_rel] = _skip
        CNAME2EXPORTS[_m.group(1)] = _exp
MEMBER = re.compile(r'(?<![.\w])(' + "|".join(sorted(map(re.escape, CNAME2EXPORTS)))
                    + r')\s*\.\s*(\w+)') if CNAME2EXPORTS else None


# --- seeds -------------------------------------------------------------------
rows = list(csv.DictReader(open("docs/ROOT_SET.tsv"), delimiter="\t"))
seeds, why = [], {}
for r in rows:
    if r["status"] != "root":
        continue
    for s in (r["scene"], r["script"]):
        seeds.append(s)
        why.setdefault(s, f"root {r['set']}")
for name, path in autoloads.items():
    seeds.append(path)
    why.setdefault(path, f"autoload {name}")
# An addon's plugin.cfg `script=` is a declaration in exactly the sense
# project.godot's [autoload] block is: a manifest naming an entry point that
# nothing in src/ ever preloads, and that the ENGINE loads. It is not reachable
# from a game root and never will be, so leaving it out reports scaffolding as
# residue — which is what happened in prologue pass 6 (ADR-0146 dec. 7), where
# `residue.py` then attributed it to seven files that merely contain the English
# word "plugin".
for cfg in sorted(ROOT.glob("addons/*/plugin.cfg")):
    m = re.search(r'^script\s*=\s*"([^"]+)"', cfg.read_text(errors="replace"), re.M)
    if m:
        entry = (cfg.parent / m.group(1)).as_posix()
        seeds.append(entry)
        why.setdefault(entry, f"plugin entry {cfg.parent.name}")
for s in seeds:
    if s not in existing:
        print(f"closure: SEED MISSING — {s}", file=sys.stderr)

# --- walk --------------------------------------------------------------------
def close_over(start):
    got, queue = set(), [s for s in start if s in existing]
    while queue:
        cur = queue.pop()
        if cur in got:
            continue
        got.add(cur)
        for t in out_edges(cur):
            if t not in got:
                queue.append(t)
    return got


reached = close_over(seeds)

# ADR-0135 dec. 11: declined is not deleted. Their closure is walked separately so
# that "reachable only from a scene we declined" reads as its own answer, which is
# what pass 5's deletion decision needs, rather than as deadness.
declined_seeds = [x for r in rows if r["status"] == "declined" for x in (r["scene"], r["script"])]
declined_reach = close_over(declined_seeds) - reached

# --- report ------------------------------------------------------------------
# classify_blueprint is the ground truth for both the subject's ROOTS and each
# unreached file's bucket, so it is loaded before either is needed. It ends in
# sys.exit(); importing it raises SystemExit.
sys.path.insert(0, "tools")
import io, contextlib, importlib.util
_spec = importlib.util.spec_from_file_location("cb", "tools/classify_blueprint.py")
cb = importlib.util.module_from_spec(_spec)
_a = sys.argv[:]
sys.argv = ["classify_blueprint.py"]
with contextlib.redirect_stdout(io.StringIO()):
    try:
        _spec.loader.exec_module(cb)
    except SystemExit:
        pass
sys.argv = _a

# The same roots the source instrument walks (ADR-0146 dec. 5): the kernel left
# src/ and assets/ in prologue pass 6, and a subject that does not follow it
# would report six reached files as absent rather than as reached.
SUBJECT = tuple(f"{d}/" for d in cb.WALK_ROOTS)
SUBJECT_LABEL = " + ".join(f"{d}/" for d in cb.WALK_ROOTS)


def addon_owned_test(u: str) -> bool:
    """`addons/<name>/tests/…` — ADR-0194 dec. 2's home for a test that ships.

    The host's `tests/` has never been in this subject: it is not a walk root.
    An addon-owned test is INSIDE one, and nothing reaches a test from a declared
    root — that is what a test is — so a subject that contained them would hand
    `residue.py` every one of them as `orphan`, *"no static claim of any kind"*,
    in the register a human reads before deleting a file. Written as "a test"
    rather than "the `tests/` directory", which is the reading that stops holding
    the moment a test moves (ADR-0194 dec. 9, the same defect in the classifier).
    """
    parts = u.split("/")
    return len(parts) > 3 and parts[0] == "addons" and parts[2] == "tests"


# Source files only: the register reports source, so a count that included the
# `.tscn` beside each `.gd` would state a limit twice the size of the one that
# exists.
ADDON_TESTS = [u for u in universe if addon_owned_test(u)
               and pathlib.Path(u).suffix in SRC_SUFFIXES]

# --- and what the SUBJECT is not ---------------------------------------------
# `SUBJECT` *is* `WALK_ROOTS`, so a file outside the walk can never enter the
# unreached set — and an absence this program cannot see reads exactly like an
# absence it checked. That is not hypothetical: goal #3 (*no dead code ships*)
# scored `met` for `Audio` on `docs/RESIDUE.tsv`'s silence about a package this
# subject had never contained. ADR-0153 dec. 1 keeps that package out of the walk
# on three grounds that all still hold, so the honest move is to STATE the limit
# rather than widen the walk out of it.
#
# Generated from the two lists, never written as prose: ADR-0145 dec. 1 found a
# number in a document that moved five times with no code change, and a caveat
# rots the same way. `residue.py` prints these lines too and writes them into
# `docs/RESIDUE.tsv`'s header — it takes the function from here rather than
# owning a second copy, so the register and the closure cannot disagree about
# what they could not see.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import _walk_roots as _wr


def limit_lines(prefix: str = "") -> list[str]:
    # `e.system` and not the package directory name: the caveat's reader wants to
    # know which SYSTEM is invisible here, and `exmateria_sound` does not say
    # `Audio`. That field arrived with ADR-0155's table and is the reason this
    # borrows that table rather than keeping a second one (#411 / #405).
    _root = _wr.PROJECT_DIR.parent
    outside = [f"{e.system} ({e.path.relative_to(_root).as_posix()})"
               for e in _wr.extracted_roots()]
    lines = [f"{prefix}derived over: {', '.join(cb.WALK_ROOTS)}"
            "  — a file outside these roots CANNOT appear here; its absence is "
            "not evidence (ADR-0149, amended)",
            f"{prefix}NOT the subject, and therefore invisible here: "
            f"{'; '.join(outside) or '(none)'}"
            "  — an extracted package the walk REPORTS rather than enters "
            "(ADR-0153 dec. 1). `no rows` about it is not `no residue` in it."]
    # The third limit is CONDITIONAL, and that is what arms it: it says nothing
    # while `addons/*/tests/` is empty, and states itself in the same commit that
    # first puts a test there. A carve-out inside a listed root is exactly the
    # absence this file warns reads like an absence it checked, and a note asking
    # a future session to remember is how that gets forgotten.
    if ADDON_TESTS:
        n = len(ADDON_TESTS)
        lines.append(f"{prefix}addon-owned tests are INSIDE these roots and are "
                     f"deliberately not the subject: {n} file{'s' if n != 1 else ''} under "
                     "`addons/<name>/tests/` (ADR-0194 dec. 2). Nothing reaches a test "
                     "from a declared root, so a subject containing them would report "
                     "every one as `orphan`.")
    return lines

subject = [u for u in universe if u.startswith(SUBJECT) and not addon_owned_test(u)]
src = [u for u in subject if pathlib.Path(u).suffix in SRC_SUFFIXES]
unreached_src = sorted(set(src) - reached)


def lines_of(f):
    return len(pathlib.Path(f).read_text(errors="replace").splitlines())


print(f"CLOSURE from {len(seeds)} seeds ({sum(1 for r in rows if r['status']=='root')} root "
      f"scenes + their scripts, {len(autoloads)} autoloads)")
print(f"  reached anything        {len(reached & set(subject)):>6} of {len(subject)} files under {SUBJECT_LABEL}")
print(f"  reached source          {len(set(src) & reached):>6} of {len(src)} hand-written .gd + shader files")
print(f"  UNREACHED source        {len(unreached_src):>6} files, {sum(lines_of(f) for f in unreached_src):,} lines")

if unreached_src:
    by = collections.Counter()
    byn = collections.Counter()
    for f in unreached_src:
        b = cb.classify(f) or "UNCLASSIFIED"
        by[b] += lines_of(f)
        byn[b] += 1
    print("\n  UNREACHED by bucket (a CANDIDATE list — see the module docstring):")
    for b, n in by.most_common():
        print(f"    {b:<22}{byn[b]:>4} files{n:>8} lines")
    only_declined = [f for f in unreached_src if f in declined_reach]
    print(f"\n  of those, {len(only_declined)} files ({sum(lines_of(f) for f in only_declined):,} lines) "
          f"ARE reachable from one of the {sum(1 for r in rows if r['status']=='declined')} DECLINED "
          f"scenes — declined is not deleted (ADR-0135 dec. 11), so that is a separate\n"
          f"  question from deadness. The remaining {len(unreached_src) - len(only_declined)} files "
          f"({sum(lines_of(f) for f in unreached_src if f not in declined_reach):,} lines) "
          f"no declared scene reaches at all.")
    if "--list" in sys.argv:
        print()
        for f in sorted(unreached_src, key=lines_of, reverse=True):
            tag = "declined-only" if f in declined_reach else "UNREACHED"
            print(f"    {lines_of(f):>6}  {f}  [{cb.classify(f) or 'UNCLASSIFIED'}]  {tag}")

if "--assets" in sys.argv:
    assets = [u for u in subject if pathlib.Path(u).suffix not in SRC_SUFFIXES
              and not u.endswith((".import", ".uid"))]
    un = sorted(set(assets) - reached)
    b_all = sum(pathlib.Path(a).stat().st_size for a in assets)
    b_un = sum(pathlib.Path(a).stat().st_size for a in un)
    print(f"\n  asset files             {len(assets) - len(un):>6} reached of {len(assets)}")
    print(f"  asset bytes             {b_all - b_un:>13,} reached of {b_all:,}  "
          f"({b_un:,} unreached = {b_un / b_all * 100:.1f}%)")

n_pre = sum(len(re.findall(r'preload\("res://', pathlib.Path(f).read_text(errors="replace")))
            for f in src if f.endswith(".gd"))
n_lit = sum(len(re.findall(r'(?<!pre)load\("res://', pathlib.Path(f).read_text(errors="replace")))
            for f in src if f.endswith(".gd"))
print(f"\n  KNOWN HOLES — {len(holes)} non-literal load() sites in walked code, against "
      f"{n_pre} preload(\"literal\") and {n_lit} load(\"literal\").")
print("  UNREACHED is a CEILING on deadness: it contains everything dead, plus anything")
print("  reached only through a path this walk cannot see. Confirm before deleting.")
for _l in limit_lines("  "):
    print(_l)
if patterned:
    print(f"  {len(patterned)} BUILT paths (a `%`/`{{}}` placeholder per path segment) reached "
          f"{sum(patterned.values())} files.")
if dangling:
    print(f"  {len(dangling)} DANGLING res:// literals name nothing on disk.")
if "--holes" in sys.argv:
    print("\n  non-literal load() sites:")
    for h in sorted(holes):
        print("    " + h)
    print("\n  built paths:")
    for k, v in patterned.most_common():
        print(f"    {v:>6}  {k}")
    print("\n  dangling res:// literals:")
    for d in sorted(dangling):
        print("    " + d)
