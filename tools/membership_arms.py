#!/usr/bin/env python3
"""NINE of `check_addon_portability.py`'s ELEVEN arms, over a membership that does not exist yet.

    uv run python tools/membership_arms.py addons/exmateria_catalogue/**/*.gd \\
        --inside=addons/exmateria_catalogue/

    # the membership BEFORE #1025 pass 3 moved it, kept because the numbers in
    # ADR-0262 dec. 2 were taken on it and are only reproducible against it:
    #   ... src/characters/*.gd src/debug/RosterDebugView.gd \\
    #       src/scenarios/AllTemplatesSeeder.gd --inside=src/characters/

WHY THIS EXISTS. `tools/arm7_membership.py` closed ADR-0241 soft spot S1 for ONE arm --
it answers arm 7 and, under `--all`, prints arms 2 / 2b / 6 beside it. Its own docstring
says the rest is out of scope (*"Arm 2 ... and arm 6 ... are not arm 7 and are not in the
default reading"*), and issue #1025 item 5 records the consequence: *"arms 1, 3, 4, 5 are
not measured at all."* Every selection ADR so far has chosen a system on one arm of the
nine. This adds the missing five on the SAME tables and the SAME five shapes, so a pass-2
audit can read the whole nine-arm sentence before a `git mv`.

NINE OF ELEVEN, AND THE TWO IT OMITS ARE NOT AN OMISSION. #1241 added arms 8 and 8b, and
neither is a membership question: arm 8 compares a `plugin.cfg` `deps=` line against arm
5's measured reach, and arm 8b compares that addon's declared `engine=` against its
dependency closure's. Both read a DECLARATION belonging to an addon that already exists,
not a proposed file set -- a membership has no `plugin.cfg` of its own, so there is nothing
here for them to score. What they do say about a `git mv` is said one level up: moving
files INTO an addon can add a sibling reach, and the receiving addon's real `deps=` and
closure engine are then the guard's business on the next run, not this instrument's.

THIS IS AN INSTRUMENT, NOT A GUARD -- no pass/fail, no burn-down -- so it is deliberately
not a `tools/check_*.py` and `check_guard_registry.py` wants no row for it, on
`arm7_membership.py`'s reasoning verbatim.

🔴 IT CANNOT REPLACE THE REAL RUN AND THE NUMBERS CAN ONLY GO UP. The guard walks a real
directory; this walks a proposal. A duck-typed reach carries no type name and is invisible
to all nine (ADR-0131 dec. 6).

🔴 ARM 2 AND ARM 2b DO NOT SHARE AN EXEMPTION, and reading one for the other is the whole
of the autoload question. `check_addon_portability.autoload_route_reaches` (arm 2b) filters
`foreign = {n: t for n, t in names.items() if not t.startswith(own)}` -- an addon reaching
its OWN singleton by node path is free, because it ships the script the `[autoload]` line
points at. `autoload_reaches` (arm 2, the bare `Name.` identifier) takes the WHOLE host
autoload map and has no such filter. So the same dependency is free spelled
`get_node_or_null("/root/X")` and debt spelled `X.foo()`, and this file reports the two
separately for that reason. `AUTOLOADS DECLARED INSIDE` is the row that matters after a
move: the name is still created by the consuming project's `project.godot`, whoever ships
the script.

ARMS 4, 4b AND 5 ARE THE GUARD'S OWN FUNCTIONS, handed a `_FileSet` instead of a
directory, rather than a second implementation of them. That is not tidiness: the first
cut of this file wrote its own push regex and read ZERO on `exmateria_platform`, whose
five pushes are `&"pixel_aspect"` StringName literals. And arm 5 has a rule no shape scan
can reproduce -- it binds a file's `const X = Facade.Y` aliases first and then scores every
bare `X` below them, which is the whole point of ADR-0211 dec. 4's alias route. The shape
scan under-reads the Character Catalogue's arm 5 by 12 lines against 61.

THE INBOUND READING (`--inbound`) IS NOT AN ARM. No arm of the guard looks inward, and the
façade rule (ADR-0211 dec. 1/4, ADR-0212 dec. 1) needs the count. It walks `tests/` and
`tools/` beside `src/`, which the classifier's own walk roots exclude: ADR-0211 dec. 5
rules that *"a test-only host use is a real host use"*, and on the Character Catalogue
membership that distinction is two published names -- `UnitBirthdays` and `UnitNames` read
internal-only in the walk and are named by five test files.
"""
import sys, re, pathlib, collections

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import arm7_membership as A
import check_addon_portability as cap

_INBOUND_ROOTS = ("src", "tests", "tools", "addons")


class _FileSet:
    """An `addon`-shaped object whose `rglob` yields a MEMBERSHIP.

    `check_addon_portability.sibling_class_reaches` uses its `addon` argument for exactly
    two things -- `addon.rglob("*")` and `h != addon` against every `class_name` home --
    so a proposed membership can be handed to the guard's OWN arm 5 rather than to a
    second implementation of it. That reuse is the point: two readings of the same set
    drift (ADR-0147/0148), and this arm has a rule no shape scan can reproduce.
    """

    def __init__(self, paths):
        self._paths = sorted(pathlib.Path(p) for p in paths)

    def rglob(self, _pattern):
        return list(self._paths)


def arms(members, inside_prefixes=()):
    """`{arm: rows}` for all nine arms over `members`.

    A row is `((kind, target, dst, bucket), [(file, lineno), ...])` for the shape-derived
    arms, and a flat list for the two that are not shape-derived (4 and 4b).
    """
    ns = A._load()
    t, strip = ns["_tables"](), ns["strip_noncode"]
    members, mset = sorted(members), set(members)
    shapes = A.all_shapes(members, tuple(inside_prefixes))

    def where(pred):
        return {k: v for k, v in shapes.items() if pred(k)}

    out = {
        # (kind, target, dst_path, bucket) -> lines
        "1": where(lambda k: k[3] in ns["SYSTEMS"]),
        "2": where(lambda k: k[0] == "autoload"),
        "2b": where(lambda k: k[0] == "/root/ reach"),
        "3": where(lambda k: k[0] == "#include"),
        "5": where(lambda k: k[0] == "class_name" and bool(A._ADDON_RE.match(k[2]))),
        "6": where(lambda k: k[0] in ("preload", "const path")
                   and not A._ADDON_RE.match(k[2])),
    }

    # Arm 2's second half: a name the MEMBERSHIP declares is still created by the
    # consuming project's `project.godot`, so it is standalone-parse debt after the
    # move exactly as a foreign one is before it.
    #
    # 🔴 TWO SPELLINGS, AND ARM 2 ONLY SEES ONE. `autoload_reaches` hunts
    # `(?<![.\w])Name\s*\.` and its docstring gives the ground: *"an autoload is reached
    # through its members, and requiring the dot is what keeps a slug string or a prose
    # word out of the count."* A BARE mention with no dot -- `catalog = CharacterCatalog`,
    # `AllTemplatesSeeder.gd:184` -- is the same standalone-parse break (the identifier
    # does not exist in a project without the `[autoload]` line) and no arm of the guard
    # has a word for it: arm 2 needs the dot and arm 2b needs the string. That is #648's
    # finding one spelling further on, so both are reported and they are NOT summed.
    declared = sorted(n for n, p in t["auto"].items() if p in mset)
    own_auto, own_bare = {}, {}
    for name in declared:
        dotted = re.compile(r'(?<![.\w])' + re.escape(name) + r'\s*\.')
        bare = re.compile(r'(?<![.\w])' + re.escape(name) + r'\b(?!\s*\.)')
        hits, bares = [], []
        for rel in members:
            q = pathlib.Path(rel)
            if q.suffix not in ns["SOURCE_SUFFIXES"] or t["auto"][name] == rel:
                continue
            for i, ln in enumerate(strip(q.read_text(errors="ignore")), 1):
                if dotted.search(ln):
                    hits.append((rel, i))
                elif bare.search(ln):
                    bares.append((rel, i))
        own_auto[name], own_bare[name] = hits, bares
    out["2_declared"], out["2_declared_bare"] = own_auto, own_bare

    # Arms 4 / 4b are the GUARD'S OWN functions over a `_FileSet` (see below), not a
    # second implementation. The first cut of this file wrote its own
    # `global_shader_parameter_set\s*\(\s*["\']` and read ZERO on `exmateria_platform`,
    # whose five pushes are spelled `(&"pixel_aspect", v)` -- a StringName literal. The
    # guard's `_PUSH_RE` has always allowed it. Two readings of the same set drift
    # (ADR-0147/0148); this one drifted before it was ever quoted.
    #
    # `own` is what the MEMBERSHIP's own shaders declare, because that is what a proposed
    # addon would ship. Arm 4 is then "binds a name it does not own", both sides.
    fs = _FileSet(members)
    decl = cap.own_global_uniform_declarations(fs)
    out["4"] = cap.shader_global_reaches(fs, {name for _rel, name, _l in decl})
    out["4b"] = decl

    out["7"] = A.arm7(members)
    return out


def arm5_resolved(members):
    """The guard's own arm 5 over `members` — INCLUDING file-local alias use sites.

    🔴 THE SHAPE SCAN IS A FLOOR AND THIS IS WHY. `all_shapes` resolves a token only if
    it is a `class_name`, so `const JobDatabase = ExMateriaAlmanac.JobDatabase` scores ONE
    line and every later bare `JobDatabase` in the same file scores nothing. Arm 5 binds
    the alias first and then scores those use sites against the resolved symbol -- which
    is the whole point of ADR-0211 dec. 4's alias route, *"it keeps 239 use sites
    unchanged"*. A membership that reaches a sibling through aliases reads far cheaper on
    the shape scan than the guard will price it after the move.
    """
    roots, _ = cap.full_roots()
    homes = cap.class_name_homes(roots)
    published = cap.published_members(roots)
    return cap.sibling_class_reaches(_FileSet(members), homes, published)


def inbound(members):
    """`{name: [(file, lineno)]}` for every name the membership DECLARES, named outside it.

    Not an arm -- the façade's subject (ADR-0211 dec. 1/4, ADR-0212 dec. 1). `.gd` only:
    `strip_noncode` is a GDScript stripper and a shader's `//` comment survives it, which
    over-counts `Character` by five rows straight out of `unit.gdshader`'s prose.
    """
    ns = A._load()
    t, strip = ns["_tables"](), ns["strip_noncode"]
    mset = set(members)
    subjects = sorted([cn for cn, p in t["cname"].items() if p in mset]
                      + [n for n, p in t["auto"].items() if p in mset])
    pats = {k: re.compile(r'\b' + re.escape(k) + r'\b') for k in subjects}
    out = {k: [] for k in subjects}
    for root in _INBOUND_ROOTS:
        for q in sorted(pathlib.Path(root).rglob("*.gd")):
            rel = str(q)
            if rel in mset:
                continue
            for i, ln in enumerate(strip(q.read_text(errors="ignore")), 1):
                for k, pat in pats.items():
                    if k in ln and pat.search(ln):
                        out[k].append((rel, i))
    return out


def _dump(title, rows, note=""):
    n = sum(len(v) for v in rows.values())
    print("\n%s: %d line(s)%s" % (title, n, (" -- " + note) if note else ""))
    for (kind, tg, dst, b), v in sorted(rows.items(), key=lambda kv: -len(kv[1])):
        print("    %-12s %-28s -> %-44s [%s] x%d" % (kind, tg[:28], dst[:44], b, len(v)))
        for rel, i in sorted(v):
            print("            %s:%d" % (rel, i))


def main(argv):
    members = sorted({a for a in argv[1:] if not a.startswith("--")})
    inside = tuple(a.split("=", 1)[1] for a in argv if a.startswith("--inside="))
    if not members:
        print(__doc__)
        return 2
    a = arms(members, inside)
    lines = sum(len(pathlib.Path(m).read_text(errors="ignore").splitlines()) for m in members)
    print("membership: %d file(s) / %d line(s)" % (len(members), lines))

    _dump("ARM 1  REACH (dst books to one of the eleven systems)", a["1"])
    _dump("ARM 2  STANDALONE PARSE, FOREIGN autoload named", a["2"])
    for name, hits in sorted(a["2_declared"].items()):
        bares = a["2_declared_bare"][name]
        print("\nARM 2  autoload DECLARED inside the membership: %s" % name)
        print("       %d member line(s) spell it `%s.` -- arm 2's own predicate"
              % (len(hits), name))
        for rel, i in hits:
            print("            %s:%d" % (rel, i))
        print("       %d further member line(s) name it BARE (no dot) -- the same "
              "standalone-parse break, invisible to arms 2 and 2b alike" % len(bares))
        for rel, i in bares:
            print("            %s:%d" % (rel, i))
    if not a["2_declared"]:
        print("\nARM 2  autoloads declared inside the membership: NONE")
    _dump("ARM 2b AUTOLOAD BY NODE PATH (/root/ string)", a["2b"])
    _dump("ARM 3  HOST #include", a["3"])
    n4 = sum(len(lines) for _r, _n, _s, lines in a["4"])
    print("\nARM 4  SHADER GLOBALS bound but not owned: %d line(s)" % n4)
    for rel, name, side, lines in a["4"]:
        print("            %s  %s %s  %s" % (rel, side, name,
                                             ",".join(str(x) for x in lines)))
    print("ARM 4b GLOBAL UNIFORM declared inside the membership: %d" % len(a["4b"]))
    for rel, name, lines in a["4b"]:
        print("            %s  %s  %s" % (rel, name, ",".join(str(x) for x in lines)))
    _dump("ARM 5  SIBLING class_name, shape scan (a FLOOR)", a["5"],
          "free only where the target root is the kernel or the port")
    by_root = collections.Counter()
    for (_k, _tg, dst, _b), v in a["5"].items():
        by_root[dst.split("/")[1]] += len(v)
    print("    by sibling addon root: %s"
          % (", ".join("%s x%d" % kv for kv in sorted(by_root.items())) or "NONE"))

    resolved = arm5_resolved(members)
    n5 = sum(len(lines) for _rel, _n, _h, lines in resolved)
    print("\nARM 5  SIBLING class_name, THE GUARD'S OWN RULE: %d line(s) over %d row(s) "
          "-- alias use sites resolved (ADR-0211 dec. 4)" % (n5, len(resolved)))
    root_of = collections.Counter()
    for rel, name, home, lines in sorted(resolved, key=lambda r: -len(r[3])):
        root = pathlib.Path(home).name
        root_of[root] += len(lines)
        print("    %-46s %-34s -> %-24s x%d" % (rel, name, root, len(lines)))
    print("    by sibling addon root: %s"
          % (", ".join("%s x%d" % kv for kv in sorted(root_of.items())) or "NONE"))
    _dump("ARM 6  RES:// PATH outside every addon root", a["6"])
    n7 = sum(len(h["lines"]) for h in a["7"].values())
    print("\nARM 7  HOST class_name: %d name(s) / %d line(s)" % (len(a["7"]), n7))
    for cn, h in sorted(a["7"].items(), key=lambda kv: -len(kv[1]["lines"])):
        print("    %-28s %3d  %s  [%s]" % (cn, len(h["lines"]), h["path"], h["bucket"]))

    if "--inbound" in argv:
        inb = inbound(members)
        print("\nINBOUND (not an arm) -- the façade's subject")
        print("    %-28s %6s %6s %6s %6s  files" % ("NAME", "src", "tests", "tools", "addons"))
        for k, v in sorted(inb.items(), key=lambda kv: -len(kv[1])):
            c = collections.Counter(r.split("/", 1)[0] for r, _ in v)
            print("    %-28s %6d %6d %6d %6d  %d"
                  % (k, c["src"], c["tests"], c["tools"], c["addons"], len({r for r, _ in v})))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
