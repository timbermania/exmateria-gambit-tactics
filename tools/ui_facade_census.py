#!/usr/bin/env python3
"""ADR-0306's instrument: UI's membership (M5) and its façade, in one command.

THE DEFECT THIS EXISTS FOR. A façade census is a symbol scan, so every way a
language writes a NON-symbol occurrence of an identifier is a way to publish a
name on the strength of a sentence. Three such defects have now done exactly
that (ADR-0306 §4):

  1. `//` comments in shaders      -> published `UI3ClipEngine`   (ADR-0305 §2)
  2. `\"\"\"...\"\"\"` GDScript blocks    -> published `GambitOptions`  (ADR-0306 §4)
  3. `/* ... */` shader blocks     -> gave `FormationScene` an addons namer

Defects 2 and 3 are invisible to a blanker that works ONE LINE AT A TIME: the
offending line contains no quote and no comment marker at all, and its opening
delimiter is ten lines earlier. Both blankers here are therefore STATEFUL across
lines, and `--control` asserts that a real use on the line AFTER a blanked block
still scores -- because "blanked everything" and "found nothing" are the same
output, and a zero from a blind instrument is not an absence.

A fourth distinction, which cost nothing but would have: a `.py`/`.sh` file
naming a class is reading SOURCE AS TEXT, not using the symbol
(`tools/check_focus_anchor.py` names "src/ui3/formation/FormationScene.gd" as a
path string). Those namers are tallied but CANNOT publish.

M5 is NOT the classifier's `UI` bucket -- it is the movable subset of it, and
reading one off the other is how 125 survived two passes (ADR-0306 §1.1). The
filter below IS ADR-0306's derivation table; change one and change the other.

Usage:  python3 tools/ui_facade_census.py [--control] [--members] [--json OUT]
"""
import argparse, contextlib, importlib.util, io, json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# --- ADR-0306 §1.1: the movable subset of the classifier's UI bucket ----------
DROP_PREFIXES = (
    "addons/",            # already inside exmateria_almanac; not ours to move
    "src/debug/",         # ADR-0257 -- a debug panel is not a member
    "src/ui3/testing/",   # ADR-0304 dec. 1 -- stays host-side
    "src/world_map/",     # a separate system, bucketed UI on name
    "src/scenes/",        # OpeningMenu.gd is an assembly
)
# only consumers are src/debug/UI3Owner*.gd -- ADR-0257 reaches the shader too
DROP_EXACT = ("assets/shaders/ui3_owner_color.gdshader",)
# .tscn is not in classify_blueprint's SOURCE_SUFFIXES, but a scene moves with its script
ADD_GLOBS = ("src/ui3/**/*.tscn",)

SYMBOLIC = {".gd", ".tscn", ".gdshader", ".gdshaderinc", ".tres"}
TEXTUAL = {".py", ".sh"}
STR = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'')


def _span(ln, state, open_d, close_d, keep):
    """Blank one multi-line delimiter pair, carrying `state` across lines."""
    while True:
        if state:
            j = ln.find(close_d)
            if j < 0:
                return "", True
            ln, state = ln[j + len(close_d):], False
        else:
            j = ln.find(open_d)
            if j < 0:
                return ln, False
            k = ln.find(close_d, j + len(open_d))
            if k >= 0:
                ln = ln[:j] + keep + ln[k + len(close_d):]
            else:
                return ln[:j], True


def code_lines(text, shader=False):
    """(lineno, line) with comments and string literals blanked. STATEFUL."""
    out, in_tq, in_blk = [], False, False
    for i, ln in enumerate(text.splitlines(), 1):
        ln, in_blk = _span(ln, in_blk, "/*", "*/", " ")      # defect 3
        ln, in_tq = _span(ln, in_tq, '"""', '"""', '""')     # defect 2
        ln = STR.sub('""', ln)
        ln = re.sub(r"//.*$", "", ln) if shader else re.sub(r"#.*$", "", ln)  # defect 1
        out.append((i, ln))
    return out


def members():
    """M5, derived from classify_blueprint's OWN walk() -- never an ad-hoc rglob,
    which yields 299 because it ignores WALK_ROOTS and SOURCE_SUFFIXES."""
    spec = importlib.util.spec_from_file_location("cb", ROOT / "tools/classify_blueprint.py")
    mod = importlib.util.module_from_spec(spec)
    cwd = pathlib.Path.cwd()
    try:
        import os
        os.chdir(ROOT)
        with contextlib.redirect_stdout(io.StringIO()):
            try:
                spec.loader.exec_module(mod)        # it sys.exit(0)s after printing
            except SystemExit:
                pass
        bucket = [p.as_posix() for p in mod.walk() if mod.classify(p.as_posix()) == "UI"]
    finally:
        os.chdir(cwd)
    keep = [f for f in bucket
            if not f.startswith(DROP_PREFIXES) and f not in DROP_EXACT]
    for g in ADD_GLOBS:
        keep += sorted(p.relative_to(ROOT).as_posix() for p in ROOT.glob(g))
    return sorted(set(keep)), len(bucket)


def control():
    """Positive control on the blanker itself (ADR-0306 §4)."""
    probe = ('var a = 1\n"""\n\t`GambitOptions.condition_label` both read either spelling.\n'
             '"""\nvar b = GambitOptions.new()   # GambitOptions in a comment\n')
    got = [ln for _, ln in code_lines(probe)]
    ok = (got[1] == got[2] == got[3] == ""
          and "GambitOptions" in got[4] and got[4].count("GambitOptions") == 1)
    shader = "/*\n  FormationScene lives here in prose\n*/\nuniform float x; // FormationScene\n"
    sg = [ln for _, ln in code_lines(shader, shader=True)]
    ok2 = all("FormationScene" not in ln for ln in sg)
    print(f"control: gd triple-quote blanked AND real use survives .. {'PASS' if ok else 'FAIL'}")
    print(f"control: shader /* */ and // both blanked ............... {'PASS' if ok2 else 'FAIL'}")
    return 0 if (ok and ok2) else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--control", action="store_true")
    ap.add_argument("--members", action="store_true")
    ap.add_argument("--json")
    a = ap.parse_args()
    if a.control:
        return control()

    m5, bucket_n = members()
    if a.members:
        print("\n".join(m5))
        return 0
    mset = {(ROOT / m).resolve() for m in m5}

    names = {}
    for m in m5:
        p = ROOT / m
        if p.suffix != ".gd":
            continue
        mo = re.search(r"^class_name\s+(\w+)", p.read_text(), re.M)
        if mo:
            names[mo.group(1)] = m

    files = [p for p in ROOT.rglob("*")
             if p.is_file() and p.suffix in (SYMBOLIC | TEXTUAL)
             and ".godot" not in p.parts and ".git" not in p.parts
             and p.resolve() not in mset]
    pats = {n: re.compile(r"\b%s\b" % n) for n in names}
    hits = {n: {} for n in names}
    for p in files:
        try:
            txt = p.read_text()
        except Exception:
            continue
        rel = p.relative_to(ROOT).as_posix()
        sym = p.suffix in SYMBOLIC
        cl = code_lines(txt, shader=p.suffix.startswith(".gdshader"))
        for n, pat in pats.items():
            ls = [i for i, ln in cl if pat.search(ln)]
            if ls:
                hits[n][rel] = {"lines": ls, "symbolic": sym}

    pub, testonly, internal = [], [], []
    for n in sorted(names):
        fs = [f for f, v in hits[n].items() if v["symbolic"]]
        if not fs:
            internal.append(n)
        elif all(f.startswith("tests/") for f in fs):
            testonly.append(n)
        else:
            pub.append(n)

    tot = len(pub) + len(testonly) + len(internal)
    print(f"M5 ............................. {len(m5)} files "
          f"(classifier UI bucket = {bucket_n}; ADR-0306 §1.1)")
    print(f"class_name declarations in M5 .. {len(names)}")
    print(f"  published (non-test namer) ... {len(pub)}")
    print(f"  test-only namers ............. {len(testonly)}")
    print(f"  internal ..................... {len(internal)}")
    print(f"  control: {len(pub)}+{len(testonly)}+{len(internal)} = {tot}"
          f"  {'OK' if tot == len(names) else 'MISMATCH'}")
    print(f"\nfaçade if UI owns its tests .... {len(pub)} rows")
    print(f"façade if tests stay in tests/ . {len(pub) + len(testonly)} rows")
    print("\nPUBLISHED:\n  " + "\n  ".join(pub))
    print("\nTEST-ONLY NAMERS:\n  " + "\n  ".join(testonly))
    print("\nINTERNAL:\n  " + "\n  ".join(internal))
    if a.json:
        json.dump({"m5": m5, "published": pub, "test_only": testonly,
                   "internal": internal, "hits": hits}, open(a.json, "w"), indent=1)
    return 0 if tot == len(names) else 1


if __name__ == "__main__":
    sys.exit(main())
