#!/usr/bin/env python3
"""System x system TOUCH matrix — who reaches across a blueprint boundary, and how.

Companion to classify_blueprint.py, whose rules it reuses as ground truth for
"which system does this file belong to". Answers the blueprint's own prescribed
method: *"For each thing a system owns, list who touches it and in which
direction the dependency runs."*  Run from the package root.

    python3 tools/touch_matrix.py [--edges]

WHAT IT COUNTS — five shapes, none of which is an interface:
    class_name    a direct compile-time type reference
    autoload      an ambient global (project.godot)
    preload       a direct file dependency (`res://` at any walked source file)
    /root/ reach  get_node("/root/X") — ambient node lookup
    #include      one shader pulling in another system's shader source

An injected port would show up as NONE of these, which is the finding: there
are no ports in src/.

**The unit is the LINE, not the file-edge** (ADR-0131 dec. 5). A file reaching
`Battle` on fifty lines used to count once; it now counts fifty. `--edges`
prints the old per-(file, target, kind) unit alongside, because the published
series before prologue pass 4 is in those units and the two are not comparable.

**`#include` is a fifth shape, added with the shader walk** (ADR-0144 dec. 1,
amending ADR-0131 dec. 5's "four shapes are unchanged"). Without it the 12,627
shader lines the walk newly sees would contribute zero crossings — a blind spot
manufactured by the very pass that closed the last one.

TWO LIMITS, both load-bearing — this is a FLOOR, not a census:

  * It OVERCOUNTED badly before comments were stripped. This repo documents
    heavily (CLAUDE.md keeps docstrings deliberately), and a word-match over
    raw text scored 672 edges where the real figure is 358 — 47% of the first
    count was prose. `strip_noncode` is why; do not remove it.

  * It UNDERCOUNTS duck-typed reaches, which carry no type name. The worked
    example is PaletteSubsystem holding a `WeakRef` to a caster/target Unit and
    calling `get_instance_id()` — a real coupling to `Battle` that this scan
    cannot see. A clean column here is not proof of a clean boundary.
"""
import sys, pathlib, re, collections, json, io, contextlib

_src = open("tools/classify_blueprint.py").read()
_ns = {"__name__": "cbmod"}
with contextlib.redirect_stdout(io.StringIO()):
    try:
        exec(_src, _ns)
    except SystemExit:
        pass


class cb:
    pass


cb.classify = _ns["classify"]
cb.SYSTEMS = _ns["SYSTEMS"]
cb.walk = _ns["walk"]
cb.SHADER_SUFFIXES = _ns["SHADER_SUFFIXES"]


def strip_noncode(txt,
                  # 🔴 COMPILED ON THE `def` LINE, NOT AT MODULE LEVEL. Five modules lift
                  # this function by SOURCE SLICE (`^def strip_noncode\(` … `(?=^\S)`) and
                  # exec it in a namespace holding only `re` — check_lattice_publish,
                  # check_lattice_ports, check_lattice_doors, residue, and
                  # test_check_addon_install. A module-level constant would not travel with
                  # the slice and every slicer would NameError on the first call. A default
                  # argument is evaluated once when the def is executed, so each slicer pays
                  # two `re.compile`s per exec instead of two `re._compile` cache lookups per
                  # LINE: measured 1,268,120 of them in one `check_lattice_publish` run, 79%
                  # of its 1.44 s. Same patterns, no flags — the output is byte-identical,
                  # which is asserted in test_touch_matrix.StripNoncodeIsCompiledOnce.
                  _comment=re.compile(r'#.*$'),
                  _literal=re.compile(r'"[^"]*"')):
    """Blank out ## / # comments, \"\"\"docstrings\"\"\" and string literals, KEEPING the
    line count — this repo documents heavily, so a word-match over raw text
    overcounts wildly, and the unit is now the line so positions must not shift."""
    out = []
    indoc = False
    for ln in txt.splitlines():
        s = ln
        if '"""' in s:
            n = s.count('"""')
            if not indoc:
                s = s.split('"""')[0]
                if n == 1:
                    indoc = True
            else:
                if n >= 1:
                    indoc = False
                    s = s.split('"""')[-1]
                else:
                    s = ""
        elif indoc:
            s = ""
        s = _comment.sub('', s)
        s = _literal.sub('""', s)
        out.append(s)
    return out


files = cb.walk()
sysof = {}
for f in files:
    rel = f.as_posix()
    b = cb.classify(rel)
    sysof[rel] = b if isinstance(b, str) else "UNCLASSIFIED"

gd = [f for f in files if f.suffix == ".gd"]
cname2file = {}
for f in gd:
    m = re.search(r'^class_name\s+(\w+)', f.read_text(errors="ignore"), re.M)
    if m:
        cname2file[m.group(1)] = f.as_posix()

autoloads = {}
for line in pathlib.Path("project.godot").read_text(errors="ignore").splitlines():
    m = re.match(r'^(\w+)="\*?(res://.+)"', line.strip())
    if m:
        autoloads[m.group(1)] = m.group(2).replace("res://", "")

# 🔴 SHAPES 2 AND 3 ARE THIS SCAN'S WHOLE COST, and the cost is REPETITION not
# work. Inline `re.search(r'\b' + re.escape(n) + ..., ln)` runs once per (line x name)
# and re-escapes the name and re-looks-up the pattern on EVERY one of those calls --
# millions of them tree-wide, and `re._compile` + `re.escape` dominated the profile.
# So compile each pattern ONCE, and gate it behind a plain substring test.
#
# The gate is a NECESSARY CONDITION of the regex it guards, not an approximation:
# `\b<name>\.` cannot match a line that lacks `<name>.` as a substring, and
# `\b<cn>\b` cannot match a line without `<cn>` in it. The regex still decides every
# row; the gate only decides whether to ask. `score_goals.outbound_reaches` carries the
# same fix for the same reason -- verified there by diffing all 826 reach rows, and
# here by diffing `.touch_cache.json` before and after (identical).
_auto_pats = [(name, path, name + ".", re.compile(r'\b' + re.escape(name) + r'\.'))
              for name, path in autoloads.items()]
_cname_pats = [(cn, t, re.compile(r'\b' + re.escape(cn) + r'\b'))
               for cn, t in cname2file.items()]

# (src_sys, dst_sys) -> {(kind, file, target): {line numbers}}
touches = collections.defaultdict(lambda: collections.defaultdict(set))


def record(s, dst_path, kind, rel, target, lineno):
    d = sysof.get(dst_path)
    if d and d != s:
        touches[(s, d)][(kind, rel, target)].add(lineno)


for f in files:
    rel = f.as_posix()
    s = sysof[rel]
    raw = f.read_text(errors="ignore").splitlines()
    code = strip_noncode("\n".join(raw))
    is_shader = f.suffix in cb.SHADER_SUFFIXES
    for i, (rawln, ln) in enumerate(zip(raw, code), 1):
        if is_shader:
            # shader comments are `//`, not `#` — strip_noncode's rules would eat
            # the `#include` itself, so the line is re-stripped here. The negative
            # lookbehind matters: a bare `//.*` strips `res://...` to nothing and
            # silently zeroes this whole shape.
            for m in re.finditer(r'#include\s+"res://([^"]+)"', re.sub(r'(?<!:)//.*$', '', rawln)):
                record(s, m.group(1), "#include", rel, m.group(1), i)
            continue
        # 1. preload/load of another walked source file
        for m in re.finditer(r'(?:preload|load)\("res://([^"]+)"\)', rawln):
            record(s, m.group(1), "preload", rel, m.group(1), i)
        # 1b. the SAME dependency, bound to a name first (ADR-0148 dec. 2).
        # `const X := "res://…"` then `load(X)` elsewhere is one dependency in two
        # statements, and shape 1 saw neither: the const line has no `load(` on it,
        # and strip_noncode blanks every string literal, so `ln` has already lost the
        # path by the time any other shape looks. ADR-0147 dec. 8 named ONE instance
        # and inferred a large hole; measured, there are 196 such declarations and
        # exactly 2 are cross-bucket, because 77 stay inside their own system and 117
        # name a `.tscn`, which the source walk does not carry. `closure.py` has
        # always seen these — it scans for `res://` literals rather than call syntax —
        # so this is ADR-0146's "when two registers describe the same set, diff them"
        # arriving one pass later, and the registers now agree.
        for m in re.finditer(r'^\s*const\s+\w+\s*:?=\s*"res://([^"]+)"', rawln):
            record(s, m.group(1), "const path", rel, m.group(1), i)
        # 2. autoload usage
        for name, path, lit, pat in _auto_pats:
            if lit in ln and pat.search(ln):
                record(s, path, "autoload", rel, name, i)
        # 3. class_name reference
        for cn, t, pat in _cname_pats:
            if t == rel:
                continue
            if cn in ln and pat.search(ln):
                record(s, t, "class_name", rel, cn, i)
        # 4. /root/ node reach
        for m in re.finditer(r'get_node(?:_or_null)?\("/root/(\w+)"', rawln):
            p = autoloads.get(m.group(1))
            if p:
                record(s, p, "/root/ reach", rel, m.group(1), i)

json.dump({f"{a}||{b}": [[k[0], k[1], k[2], sorted(v)] for k, v in d.items()]
           for (a, b), d in touches.items()},
          open("tools/.touch_cache.json", "w"))

SYS = cb.SYSTEMS


def cell(a, b, unit):
    d = touches.get((a, b), {})
    return sum(len(v) for v in d.values()) if unit == "lines" else len(d)


def matrix(unit):
    print(f"MATRIX — rows touch columns ({unit})")
    print("%-22s" % "", " ".join("%-5s" % x[:5] for x in SYS))
    for a in SYS:
        print("%-22s" % a, " ".join("%-5s" % (cell(a, b, unit) or ".") for b in SYS))
    tot = sum(cell(a, b, unit) for a in SYS for b in SYS)
    print(f"\ntotal cross-SYSTEM {unit}:", tot)
    return tot


lines_total = matrix("lines")
if "--edges" in sys.argv:
    print()
    matrix("edges")
by_kind = collections.Counter()
for (a, b), d in touches.items():
    if a in SYS and b in SYS:
        for k, v in d.items():
            by_kind[k[0]] += len(v)
print("by shape:", ", ".join(f"{k} {v}" for k, v in by_kind.most_common()))
print("This is a FLOOR (ADR-0131 dec. 6): duck-typed reaches carry no type name and are invisible.")
