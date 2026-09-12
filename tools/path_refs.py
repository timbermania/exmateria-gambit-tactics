#!/usr/bin/env python3
"""Every `res://` path reference into and out of one system. The fourth reading.

    python3 tools/path_refs.py Battlefield
    python3 tools/path_refs.py Battlefield --no-tests
    python3 tools/path_refs.py Battlefield --tsv > refs.tsv

WHY THIS EXISTS. `touch_matrix.py` reads TYPED SYMBOLS out of `.gd`; a `res://`
string is not one, so the cross-system matrix cannot see a single path reference
in either direction. That is fine while nothing moves and fatal the moment
something does: a `class_name` move is caught by the parser, and a path move is
caught by nothing that runs before the scene loads. ADR-0157 dec. 6 named the
gap and put a number on it (**21**) that no stated definition reproduces — it is
blind to `tests/`, which is where four fifths of the real count lives.

WHAT A "REFERENCE" IS HERE, stated so the number is reproducible. Every
`res://<path>` literal in a file with one of the extensions below, `docs/` and
`tools/` excluded as referrers, `.git/`, `.godot/` and `project-assets/`
excluded entirely. `project.godot` is included: an autoload entry is a path
reference and it breaks exactly like the others. The count is REFERENCES, not
files — a scene naming two of a system's files is two.

THE SYSTEM'S OWN SCENES ARE NOT IN `classify_blueprint.walk()`. It takes `.gd`
and the four shader suffixes and no `.tscn` at all, so a system's scenes are
outside its file census and outside its line count. They are supplied here by
`--scene`, defaulting to the two ADR-0157 names for `Battlefield`, and a scene
supplied that way counts as the system's for both directions.

A `.tscn` referrer is attributed to the bucket of the script its root wears,
which is how a scene edge acquires a system at all. A referrer the classifier
does not book reads `?` — an asset, a material, or `project.godot` — and is
reported rather than dropped.
"""
import argparse, collections, pathlib, re, sys

EXT = (".tscn", ".gd", ".tres", ".gdshader", ".gdshaderinc", ".glsl", ".glslinc",
       ".cfg", ".godot", ".import")
SKIP_DIR = {".git", ".godot", "project-assets"}
SKIP_REFERRER_PREFIX = ("docs/", "tools/")
RES = re.compile(r"res://([A-Za-z0-9_./-]+)")
SCENE_SCRIPT = re.compile(r'type="Script"[^\]]*path="res://([^"]+)"')
# `classify_blueprint.walk()` takes no `.tscn` at all, so a system's own scenes are
# outside its census and have to be supplied by name. That makes this table a
# HARDCODED PATH inside a refactor that moves paths — #561 dec. 3 named it and left
# the edit to pass 6, which is when it came due: both scenes moved into
# `addons/exmateria_battlefield/` at ADR-0184 and this table went with them in the
# same commit. Nothing here fails if it does not; the two scenes simply stop being
# counted, which is the ADR-0148 shape one more time.
DEFAULT_SCENES = {"Battlefield": ("addons/exmateria_battlefield/camera/PlayerCamera.tscn",
                                  "addons/exmateria_battlefield/cursor/TileCursor.tscn")}


def load_classifier():
    """`classify_blueprint` runs its report at import; stop before the first print."""
    src = pathlib.Path("tools/classify_blueprint.py").read_text(encoding="utf-8")
    ns = {"__name__": "cb", "__file__": "tools/classify_blueprint.py"}
    argv = sys.argv
    sys.argv = ["classify_blueprint.py"]
    try:
        exec(compile(src[:src.index("print(f\"{'BUCKET")], "classify_blueprint.py", "exec"), ns)
    finally:
        sys.argv = argv
    return ns["classify"], ns["walk"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("system")
    ap.add_argument("--scene", action="append", default=None,
                    help="a .tscn the classifier cannot see; repeatable")
    ap.add_argument("--no-tests", action="store_true")
    ap.add_argument("--tsv", action="store_true")
    a = ap.parse_args()

    classify, walk = load_classifier()
    owned = {p.as_posix() for p in walk() if classify(p.as_posix()) == a.system}
    scenes = set(a.scene if a.scene is not None else DEFAULT_SCENES.get(a.system, ()))
    if not owned:
        print(f"no files classify to {a.system!r}", file=sys.stderr)
        return 2
    all_owned = owned | scenes

    files = [p for p in pathlib.Path(".").rglob("*")
             if p.is_file() and p.suffix in EXT and not (set(p.parts) & SKIP_DIR)]

    scene_bucket = {}
    for p in files:
        if p.suffix != ".tscn":
            continue
        m = SCENE_SCRIPT.search(p.read_text(encoding="utf-8", errors="replace"))
        scene_bucket[p.as_posix()] = (classify(m.group(1)) or "?") if m else "?"

    def bucket(rel):
        if rel in scenes:
            return a.system
        if rel.endswith(".tscn"):
            return scene_bucket.get(rel, "?")
        return classify(rel) or "?"

    inbound, outbound = [], []
    for p in files:
        rel = p.as_posix()
        if rel.startswith(SKIP_REFERRER_PREFIX):
            continue
        is_test = rel.startswith("tests/")
        if is_test and a.no_tests:
            continue
        for n, line in enumerate(p.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            for m in RES.finditer(line):
                tgt = m.group(1)
                if tgt in all_owned and rel not in all_owned:
                    inbound.append((rel, bucket(rel), tgt, n, is_test))
                if rel in all_owned and tgt not in all_owned:
                    outbound.append((rel, tgt, bucket(tgt), n, is_test))

    if a.tsv:
        w = sys.stdout.write
        w("direction\treferrer\treferrer_bucket\ttarget\ttarget_bucket\tline\tin_tests\n")
        for rel, b, tgt, n, t in sorted(inbound):
            w(f"in\t{rel}\t{b}\t{tgt}\t{a.system}\t{n}\t{int(t)}\n")
        for rel, tgt, b, n, t in sorted(outbound):
            w(f"out\t{rel}\t{a.system}\t{tgt}\t{b}\t{n}\t{int(t)}\n")
        return 0

    prod_in = [r for r in inbound if not r[4]]
    test_in = [r for r in inbound if r[4]]
    print(f"{a.system}: {len(owned)} classified files + {len(scenes)} scene(s) supplied\n")
    print(f"INBOUND  {len(inbound)} references  "
          f"({len(prod_in)} production, {len(test_in)} from "
          f"{len({r[0] for r in test_in})} test files)")
    for tgt, c in collections.Counter(r[2] for r in inbound).most_common():
        p_, t_ = sum(1 for r in prod_in if r[2] == tgt), sum(1 for r in test_in if r[2] == tgt)
        print(f"   {c:>4}  ({p_:>3} prod / {t_:>3} test)  <- {tgt}")
    print("\n   referrer buckets:",
          dict(collections.Counter(r[1] for r in inbound).most_common()))

    print(f"\nOUTBOUND {len(outbound)} references")
    for b, c in collections.Counter(r[2] for r in outbound).most_common():
        print(f"   {c:>4}  -> [{b}]")
    print("\n   ADR-0141 dec. 2 excludes platform, schema and Debug. What is left:")
    left = [r for r in outbound if r[2] not in ("platform", "schema", "Debug", "?", a.system)]
    for rel, tgt, b, n, _ in sorted(left):
        print(f"      {rel}:{n}  ->  {tgt}  [{b}]")
    if not left:
        print("      (none)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
