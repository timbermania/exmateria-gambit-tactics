#!/usr/bin/env python3
"""Arm 7's predicate over a membership that does not exist yet.

    uv run python tools/arm7_membership.py src/data/*.gd src/units/UnitProgression.gd
    uv run python tools/arm7_membership.py --all src/data/*.gd      # all five shapes
    uv run python tools/arm7_membership.py --exclude-panels src/units/*.gd

WHY THIS EXISTS. `check_addon_portability.py` arm 7 asks the boundary question --
*does this `class_name` resolve outside every addon root* -- and it is the instrument
that decides an extraction (ADR-0241 dec. 8). But it reads `score_goals.outbound_reaches`,
which **walks a real addon directory**, so it cannot be pointed at a proposed
membership. Every selection ADR that needed the number applied the predicate BY HAND;
ADR-0241 soft spot S1 named that as its own weakest point and ADR-0243 dec. 11 closes
it with this file.

THIS IS AN INSTRUMENT, NOT A GUARD. It has no pass/fail and no burn-down, so it is
deliberately not a `tools/check_*.py` and `check_guard_registry.py` does not want a row
for it. What it reports is an input to an ADR, and the guard on the real folder after
the move is still the witness.

WHAT IT COUNTS, and it is arm 7's predicate verbatim (`check_addon_portability.py`
lines 1120-1123): kind is `class_name`; `strip_noncode` is applied so docstrings do not
score; the target's declaring file is matched against `^addons/[^/]+/`; and a name
declared INSIDE the membership is internal and does not count. The unit is the LINE
(ADR-0131 dec. 5).

🔴 IT CANNOT REPLACE THE REAL RUN AND THE NUMBER CAN ONLY GO UP. Arm 2 (host autoloads)
and arm 6 (`res://` paths) are not arm 7 and are not in the default reading -- `--all`
prints them beside it, which is how ADR-0243 found that the tier's true boundary is one
arm-7 line PLUS one arm-6 shader path plus twelve asset payloads that travel with it.
A duck-typed reach carries no type name and is invisible to every one of these
(ADR-0131 dec. 6).

CALIBRATED THREE WAYS BEFORE IT WAS BELIEVED, because a fresh instrument agreeing with
nothing is a fresh instrument's opinion:

  1. Against the REAL guard, row for row INCLUDING LINE NUMBERS, on every addon in the
     package. The three extracted addons all read arm-7 ZERO, so that comparison alone
     is vacuous -- 0 == 0 is not a liveness witness. Re-taken with the addon-root filter
     OFF, where the sets are non-empty: `exmateria_battlefield` 2 names / 35 lines,
     `exmateria_sprite_rig` 2 / 19, `exmateria_render` 1 / 1, all equal.
  2. Against ADR-0241 dec. 2's four published memberships: A 4/45, B 9/85, C 8/79,
     D 13/119. All four reproduce exactly.
  3. Against ADR-0241 dec. 7's six-system table (746 lines) and dec. 8's
     by-declaring-directory table (`src/data/` 326, `src/debug/` 202, `src/scenarios/`
     82, `src/units/` 67). Every row reproduces exactly.

`tools/test_arm7_membership.py` holds calibrations 1 and 2 so a change here has to
answer to the guard it claims to mirror.

`--exclude-panels` DROPS every `BaseDebugPanel` subclass from the membership before the
predicate runs (ADR-0257 dec. 1). A panel is host debug-window UI (ADR-0035), it is
instantiated by the host's scene-boot entry points rather than by the system it
inspects, and no shipped addon contains one -- so counting it as a member books the
panel's reach into its subject's portability debt. That is not a filter on the answer;
it is a correction to the QUESTION, and without it `classify()`'s book-by-consumer rule
(ADR-0243 dec. 3) makes a system's debt a function of who debugs it. The flag reports
what it dropped, by name: a silent exclusion reads exactly like a clean membership.
"""
import sys, os, re, io, pathlib, collections, contextlib

_ADDON_RE = re.compile(r'^addons/[^/]+/')
_WORD = re.compile(r'\w+')
_EXTENDS = re.compile(r'^extends\s+(.+?)\s*(?:#.*)?$', re.M)
_PANEL_ROOT = "src/debug/BaseDebugPanel.gd"
_ns = None


def _load():
    """`score_goals.py`'s own tables, via the `exec`-and-catch-`SystemExit` idiom
    `touch_matrix.py` lines 43-61 established. Reusing them rather than
    re-implementing is the point: a second reading of the same set is what
    ADR-0147/0148 warn about."""
    global _ns
    if _ns is None:
        ns = {"__name__": "sgmod", "__file__": "tools/score_goals.py"}
        with contextlib.redirect_stdout(io.StringIO()):
            try:
                exec(pathlib.Path("tools/score_goals.py").read_text(), ns)
            except SystemExit:
                pass
        _ns = ns
    return _ns


def panel_subclasses(root=_PANEL_ROOT):
    """Every path whose `extends` chain reaches `root`, transitively.

    Resolves both spellings -- `extends BaseDebugPanel` (a `class_name`, via
    `_tables()["cname"]`) and `extends "res://..."` -- because the corpus uses both.
    The walk is bounded by the file count, and a cycle cannot arise: GDScript rejects
    one at parse time. `root` itself is INCLUDED, since the base class is as much host
    debug-window UI as its children.
    """
    ns = _load()
    t = ns["_tables"]()
    parent = {}
    for rel in t["sysof"]:
        q = pathlib.Path(rel)
        if q.suffix != ".gd":
            continue
        m = _EXTENDS.search(q.read_text(errors="ignore"))
        if not m:
            continue
        par = m.group(1).strip().strip('"').strip("'")
        if par.startswith("res://"):
            parent[rel] = par[len("res://"):]
        elif par in t["cname"]:
            parent[rel] = t["cname"][par]
    out = set()
    for rel in parent:
        seen, cur = set(), rel
        while cur in parent and cur not in seen:
            seen.add(cur)
            cur = parent[cur]
            if cur == root:
                out.add(rel)
                break
    if pathlib.Path(root).exists():
        out.add(root)
    return out


def arm7(members):
    """{class_name: {"path", "bucket", "lines": [(file, lineno)]}} leaving `members`.

    The tokenised inner loop is not an approximation: a `\\w+` run is exactly the span
    `\\b<name>\\b` can match, so it is the same predicate. The `re.search` form is
    O(names x lines) and `src/data/AbilityDatabase.gd` alone is 19,411 lines.
    """
    ns = _load()
    t, strip = ns["_tables"](), ns["strip_noncode"]
    members = set(members)
    hits = collections.defaultdict(lambda: {"path": None, "bucket": None, "lines": []})
    for rel in sorted(members):
        q = pathlib.Path(rel)
        if q.suffix not in ns["SOURCE_SUFFIXES"] or q.suffix in ns["SHADER_SUFFIXES"]:
            continue
        for i, ln in enumerate(strip(q.read_text(errors="ignore")), 1):
            for cn in set(_WORD.findall(ln)):
                target = t["cname"].get(cn)
                if target is None or target == rel or target in members:
                    continue                       # unknown, self, or internal
                if _ADDON_RE.match(target):
                    continue                       # already inside an addon root
                h = hits[cn]
                h["path"], h["bucket"] = target, t["sysof"].get(target)
                h["lines"].append((rel, i))
    return dict(hits)


def all_shapes(members, inside_prefixes=()):
    """Every outbound edge in touch_matrix's five shapes, for the arms arm 7 cannot see.

    `inside_prefixes` mirrors `outbound_reaches`' `inside` check -- a target under a
    directory the membership takes with it is not outbound. Without it a data asset a
    member preloads reads as an escape, which is exactly the twelve `assets/*.json`
    rows ADR-0243 dec. 8 rules travel with the databases.
    """
    ns = _load()
    t, strip = ns["_tables"](), ns["strip_noncode"]
    members, inside = set(members), tuple(inside_prefixes)
    out = collections.defaultdict(list)

    def rec(dst, kind, rel, target, i):
        if dst in members or (inside and dst.startswith(inside)):
            return
        out[(kind, target, dst, t["sysof"].get(dst, "?"))].append((rel, i))

    for rel in sorted(members):
        q = pathlib.Path(rel)
        if q.suffix not in ns["SOURCE_SUFFIXES"]:
            continue
        raw = q.read_text(errors="ignore").splitlines()
        if q.suffix in ns["SHADER_SUFFIXES"]:
            for i, rawln in enumerate(raw, 1):
                for m in re.finditer(r'#include\s+"res://([^"]+)"',
                                     re.sub(r'(?<!:)//.*$', '', rawln)):
                    rec(m.group(1), "#include", rel, m.group(1), i)
            continue
        for i, (rawln, ln) in enumerate(zip(raw, strip("\n".join(raw))), 1):
            for m in re.finditer(r'(?:preload|load)\("res://([^"]+)"\)', rawln):
                rec(m.group(1), "preload", rel, m.group(1), i)
            for m in re.finditer(r'^\s*const\s+\w+\s*:?=\s*"res://([^"]+)"', rawln):
                rec(m.group(1), "const path", rel, m.group(1), i)
            for name in set(re.findall(r'\b(\w+)\.', ln)):
                if name in t["auto"]:
                    rec(t["auto"][name], "autoload", rel, name, i)
            for cn in set(_WORD.findall(ln)):
                if cn in t["cname"] and t["cname"][cn] != rel:
                    rec(t["cname"][cn], "class_name", rel, cn, i)
            for m in re.finditer(r'get_node(?:_or_null)?\("/root/(\w+)"', rawln):
                if m.group(1) in t["auto"]:
                    rec(t["auto"][m.group(1)], "/root/ reach", rel, m.group(1), i)
    return dict(out)


def main(argv):
    show_all = "--all" in argv
    drop_panels = "--exclude-panels" in argv
    inside = [a.split("=", 1)[1] for a in argv if a.startswith("--inside=")]
    members = sorted({a for a in argv[1:] if not a.startswith("--")})
    if not members:
        print(__doc__)
        return 2
    ns = _load()
    if drop_panels:
        dropped = sorted(set(members) & panel_subclasses())
        members = [m for m in members if m not in set(dropped)]
        print("--exclude-panels dropped %d BaseDebugPanel subclass(es):" % len(dropped))
        for d in dropped:
            print("    %s" % d)
        if not members:
            print("membership is EMPTY after the exclusion -- nothing to measure.")
            return 0
    hits = arm7(members)
    n = sum(len(h["lines"]) for h in hits.values())
    print("membership: %d file(s)" % len(members))
    print("ARM 7: %d name(s) / %d line(s) declared outside every addon root" % (len(hits), n))
    for cn, h in sorted(hits.items(), key=lambda kv: -len(kv[1]["lines"])):
        print("    %-28s %3d  %s  [%s]" % (cn, len(h["lines"]), h["path"], h["bucket"]))
        for rel, i in h["lines"]:
            print("            %s:%d" % (rel, i))
    if show_all:
        esc = {k: v for k, v in all_shapes(members, inside).items()
               if not _ADDON_RE.match(k[2])}
        print("\nALL FIVE SHAPES, targets outside every addon root: %d line(s)"
              % sum(len(v) for v in esc.values()))
        for (kind, target, dst, b), v in sorted(esc.items(), key=lambda kv: -len(kv[1])):
            print("    %-12s %-30s -> %-46s [%s] x%d" % (kind, target[:30], dst[:46], b, len(v)))
    # autoload veto (ADR-0139 dec. 4b) -- a member that is an autoload cannot be kernel
    auto = sorted(k for k, p in ns["_tables"]()["auto"].items() if p in set(members))
    print("\nautoloads inside the membership: %s" % (", ".join(auto) if auto else "NONE"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
