#!/usr/bin/env python3
"""Autoload names one system reaches, and the names it publishes. The fifth reading.

    python3 tools/autoload_reach.py Battlefield

WHY THIS EXISTS, AND WHY IT IS NOT A DUPLICATE OF ANYTHING. An autoload name is a
bare identifier created by `project.godot`, never by the file that uses it. Two
different questions are asked of the same lines and they have different answers:

  * ORDERING (ADR-0141 dec. 2) — which system to extract next. It counts reaches
    into other systems and expressly excludes `platform`, `schema` and `Debug`.
    `touch_matrix.py` DOES see autoload reaches, so dec. 2 is not blind here and
    this tool does not correct it.
  * SHIPPING (goal #5, `check_addon_portability.py` arm 2) — whether the addon
    parses ALONE. Every host-autoload name is a break, excluded-by-dec.-2 or not,
    because the name does not exist in a project that does not autoload it.
    Extraction #2 shipped that defect twice; extraction #1 left 16 lines of `Tune`
    behind and the guard calls them what the next extraction has to answer.

`check_addon_portability.py` answers the shipping question only for a tree that is
ALREADY an addon, and its `--root` takes one directory. A system spread over seven
directories cannot be previewed with it before the move, which is precisely when
the answer is worth having. This is that preview, and the two agree by
construction on any tree they both see: the scan is the same bare-identifier rule.

FALSE POSITIVES ARE POSSIBLE AND BOUNDED. The match is `Name.` outside a comment.
A `class_name` colliding with an autoload name would be counted; run with
`--check-collisions` to list any autoload whose name is also a `class_name` in the
walk, which is the only way that can happen.
"""
import argparse, collections, pathlib, re, sys

USE = "(?<![A-Za-z0-9_.]){}\\s*\\."


def load_classifier():
    src = pathlib.Path("tools/classify_blueprint.py").read_text(encoding="utf-8")
    ns, argv = {"__name__": "cb", "__file__": "tools/classify_blueprint.py"}, sys.argv
    sys.argv = ["classify_blueprint.py"]
    try:
        exec(compile(src[:src.index("print(f\"{'BUCKET")], "classify_blueprint.py", "exec"), ns)
    finally:
        sys.argv = argv
    return ns["classify"], ns["walk"]


def autoloads(classify):
    body = pathlib.Path("project.godot").read_text(encoding="utf-8")
    body = body.split("[autoload]", 1)[1].split("\n[", 1)[0]
    out = {}
    for line in body.strip().splitlines():
        if "=" not in line:
            continue
        name, path = line.split("=", 1)
        rel = path.strip().strip('"').lstrip("*").replace("res://", "")
        out[name.strip()] = (classify(rel) or "?", rel)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("system")
    ap.add_argument("--check-collisions", action="store_true")
    a = ap.parse_args()
    classify, walk = load_classifier()
    al = autoloads(classify)
    files = [p for p in walk() if p.suffix == ".gd"]
    mine = [p for p in files if classify(p.as_posix()) == a.system]
    own = {n for n, (b, _) in al.items() if b == a.system}
    if not mine:
        print(f"no files classify to {a.system!r}", file=sys.stderr)
        return 2

    if a.check_collisions:
        decl = {}
        for p in files:
            m = re.search(r"^class_name\s+([A-Za-z0-9_]+)", p.read_text(errors="ignore"), re.M)
            if m:
                decl[m.group(1)] = p.as_posix()
        clash = {n: decl[n] for n in al if n in decl}
        print("autoload names that are ALSO a class_name:", clash or "(none — the scan is unambiguous)")
        print()

    def scan(paths, names):
        hit = collections.defaultdict(list)
        pats = {n: re.compile(USE.format(n)) for n in names}
        for p in paths:
            rel = p.as_posix()
            for i, line in enumerate(p.read_text(errors="ignore").splitlines(), 1):
                if line.lstrip().startswith("#"):
                    continue
                for n, pat in pats.items():
                    if pat.search(line):
                        hit[n].append(f"{rel}:{i}")
        return hit

    print(f"{a.system}: {len(mine)} .gd files; publishes {len(own)} autoload(s)\n")
    pub = scan([p for p in files if p.as_posix() not in {al[n][1] for n in own}], own)
    print("PUBLISHED — who names this system's autoloads")
    for n in sorted(own):
        v = pub.get(n, [])
        outside = [x for x in v if classify(x.rsplit(":", 1)[0]) != a.system]
        print(f"   {n:24s} {len(v):>3} lines, {len(outside):>3} from OUTSIDE {a.system}")
        for x in outside[:6]:
            print(f"       {x}   [{classify(x.rsplit(':',1)[0])}]")
    print()

    out = scan(mine, [n for n in al if n not in own])
    tot = sum(len(v) for v in out.values())
    nf = len({x.rsplit(':', 1)[0] for v in out.values() for x in v})
    print(f"REACHED — host autoloads named INSIDE {a.system}: {tot} lines in {nf} files")
    print("   (every one is a standalone-parse break; the bucket column is dec. 2's exclusion)")
    for n, v in sorted(out.items(), key=lambda kv: -len(kv[1])):
        b = al[n][0]
        mark = "  <-- counts as outbound debt" if b not in ("platform", "schema", "Debug", "infrastructure", "?") else ""
        print(f"   {n:24s} [{b:12s}] {len(v):>3} lines / {len({x.rsplit(':',1)[0] for x in v}):>2} files{mark}")
    debt = sum(len(v) for n, v in out.items()
               if al[n][0] not in ("platform", "schema", "Debug", "infrastructure", "?"))
    print(f"\n   dec. 2 counts {debt}; goal #5 answers for all {tot}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
