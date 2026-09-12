#!/usr/bin/env python3
"""The declared root set, mechanized.

Prologue pass 3's guard, over `docs/ROOT_SET.tsv`. Like `classify_blueprint.py`
and pass 1's guard it has NO catch-all: a non-test, non-`tools/` scene nobody
declared is the finding, not a default.

It runs ADR-0112 dec. 1's candidacy test as ADR-0143 dec. 2 restates it —
composition, resolved through const-indirected paths, with tests (0112 dec. 4 —
`tests/` AND ADR-0194 dec. 2's `addons/<name>/tests/`, which is not at the top
level) and `tools/` (0135 dec. 2) excluded as referrers — and ADR-0135 dec. 8's
pairing, "a root scene is one nothing instances, and its assembler is the script
nothing calls". Both halves are checked, and both have pinned exceptions.

ADR-0144 dec. 4 narrowed check 4: the classifier is only required to book a root's
script `assembler` where the pairing's SECOND half holds. Two of the eleven roots
are also libraries, and demanding they be booked as wiring was the check asserting
a consequence the decision itself does not reach.

Run from the package root.  Exit 0 = clean.
"""
import csv, importlib.util, pathlib, re, sys, collections

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import _walk_roots            # walk_files: rglob does not follow the
                              # addons/exmateria_sound symlink

ROOT = pathlib.Path(".")
fail = []


def load_classifier():
    spec = importlib.util.spec_from_file_location("cb", "tools/classify_blueprint.py")
    mod = importlib.util.module_from_spec(spec)
    argv, out = sys.argv, sys.stdout
    sys.argv, sys.stdout = ["classify_blueprint.py"], open("/dev/null", "w")
    try:
        spec.loader.exec_module(mod)   # it ends in sys.exit(); the import is for classify()
    except SystemExit:
        pass
    finally:
        sys.stdout.close()
        sys.argv, sys.stdout = argv, out
    return mod.classify


def is_test(p):
    """A test, wherever it lives.

    `tests/` is ADR-0112 dec. 4's; `addons/<name>/tests/` is ADR-0194 dec. 2's —
    an addon-owned test ships INSIDE the addon, so it is not at the top level and
    a `parts[0]` reading does not see it. It is the same instrument defect
    ADR-0194 dec. 9 fixed in the classifier: an exclusion written as "the `tests`
    directory" rather than "a test" stops holding the moment a test moves. Both
    of this file's questions want it, and asking it twice is how the two answers
    drift apart.
    """
    return p.parts[0] == "tests" or (len(p.parts) > 3 and p.parts[0] == "addons"
                                     and p.parts[2] == "tests")


def in_scope(p):
    """Not generated, not a test, not `tools/`.

    Two questions, one answer. As a REFERRER: ADR-0112 dec. 4 and ADR-0135 dec. 2
    exclude tests and tools, so mounting a scene from one does not make it
    composed. As a CENSUS member (check 1): the same files are the ones nobody has
    to declare a root row for. An addon-owned test is excluded on both counts, and
    for the same reason — it is a test, and it is not a root.
    """
    return ".godot" not in p.parts and not is_test(p) and p.parts[0] != "tools"



ALL = list(_walk_roots.walk_files(ROOT))
TSCN = [p for p in ALL if p.suffix == ".tscn"]
GD = [p for p in ALL if p.suffix == ".gd"]


rows = list(csv.DictReader(open("docs/ROOT_SET.tsv"), delimiter="\t"))
declared = {r["scene"]: r for r in rows}

# --- 1. the declaration covers every non-test, non-tools scene, exactly once ---
census = sorted(p.as_posix() for p in TSCN if in_scope(p))
for s in sorted(set(census) - set(declared)):
    fail.append(f"UNDECLARED SCENE — no docs/ROOT_SET.tsv row: {s}")
for s in sorted(set(declared) - set(census)):
    fail.append(f"STALE ROW — docs/ROOT_SET.tsv names a scene that does not exist: {s}")
for s, n in collections.Counter(r["scene"] for r in rows).items():
    if n > 1:
        fail.append(f"DUPLICATE ROW — {s} declared {n} times")

STATUS = {"root", "declined", "component"}
for r in rows:
    if r["status"] not in STATUS:
        fail.append(f"{r['scene']}: status {r['status']!r} is not one of {sorted(STATUS)}")
    want = {"game", "authoring"} if r["status"] == "root" else {"-"}
    if r["set"] not in want:
        fail.append(f"{r['scene']}: set {r['set']!r} is not one of {sorted(want)} for a {r['status']}")
    # `-` declares that the scene's ROOT NODE carries no script, which #744's
    # `addons/exmateria_sprite_rig/UnitRig.tscn` is the first row to need: it is the
    # BASE of an inherited scene, and the script belongs to the inheritor
    # (`assets/scenes/Unit.tscn` attaches `Unit.gd` to the root it inherits). Writing
    # a script here to satisfy the column would name a pairing that does not exist.
    # Checks 3 and 4 never reach it -- both skip any row that is not a `root`.
    if r["script"] == "-":
        if r["status"] == "root":
            fail.append(f"{r['scene']}: a root must name its assembler; `-` is only for a "
                        f"component/declined scene whose root node has no script")
    elif not pathlib.Path(r["script"]).exists():
        fail.append(f"MISSING SCRIPT — {r['scene']} names {r['script']}, which does not exist")

# --- 2. composition sites: who mounts each scene? ---
sites = collections.defaultdict(list)
for p in TSCN:
    if not in_scope(p):
        continue
    for m in re.finditer(r'\[ext_resource[^\]]*path="res://([^"]+\.tscn)"', p.read_text(errors="replace")):
        if p.as_posix() != m.group(1):
            sites[m.group(1)].append(f"{p.as_posix()} [ext_resource]")
for p in GD:
    if not in_scope(p):
        continue
    for i, ln in enumerate(p.read_text(errors="replace").splitlines(), 1):
        if ln.strip().startswith("#"):
            continue
        for m in re.finditer(r'"res://([^"]+\.tscn)"', ln):
            if p.as_posix() != m.group(1):
                sites[m.group(1)].append(f"{p.as_posix()}:{i}")

for r in rows:
    got = sites.get(r["scene"], [])
    if r["status"] == "component" and not got:
        fail.append(f"UNCOMPOSED COMPONENT — {r['scene']} is declared a component but nothing mounts it")
    if r["status"] in ("root", "declined") and got:
        for w in got:
            fail.append(f"MOUNTED — {r['scene']} <- {w}")

# --- 3. ADR-0135 dec. 8: a root's assembler is the script nothing calls ---
def class_name_of(f):
    m = re.search(r'^class_name\s+(\w+)', pathlib.Path(f).read_text(errors="replace"), re.M)
    return m.group(1) if m else None

gd = [p for p in GD if in_scope(p)]
called = {}
for r in rows:
    # A `-` script is already a failure above when the row is a `root`; skipping it
    # here is what keeps this arm from raising on it. A guard that TRACEBACKS instead
    # of reporting takes every arm behind it down with it, which is the failure this
    # repo has already paid for once in the pre-flight.
    if r["status"] != "root" or r["script"] == "-":
        continue
    script, cn = r["script"], class_name_of(r["script"])
    callers = set()
    for p in gd:
        if p.as_posix() == script:
            continue
        for ln in p.read_text(errors="replace").splitlines():
            if ln.strip().startswith("#"):
                continue
            code = re.sub(r'"[^"]*"', '""', ln.split("#")[0])
            if re.search(r'(?:pre)?load\s*\(\s*"res://%s"' % re.escape(script), ln) or \
               (cn and re.search(r'\b%s\b' % cn, code)):
                callers.add(p.as_posix())
                break
    called[script] = callers
    if callers:
        fail.append(f"CALLED — {script} is a root's assembler but {len(callers)} file(s) call it: "
                    + ", ".join(sorted(callers)))

# --- 4. ADR-0134/0135 dec. 8: the classifier books every root's script `assembler`,
# WHERE THE PAIRING HOLDS. ADR-0144 dec. 4 narrows this. Dec. 8 is one sentence with
# two halves — *"a root scene is one nothing instances, and its assembler is the
# script nothing calls"* — and pass 3 found two roots that fail the second half.
# Asserting the consequence anyway demanded that a 3,482-line base class other files
# `extend` be booked as wiring. So the check now runs only where check 3 is clean for
# that root: a script something calls is a LIBRARY, and the pairing, not the booking,
# is what did not hold.
classify = load_classifier()
for r in rows:
    if r["status"] != "root" or r["script"] == "-":
        continue
    if called.get(r["script"]):
        continue
    b = classify(r["script"])
    if b != "assembler":
        fail.append(f"NOT ASSEMBLER — {r['script']} is {r['scene']}'s assembler "
                    f"but classify_blueprint.py books it {b!r}")

# The defects pass 3 FOUND, pinned so a NEW one fails. Shrink this list, never grow it.
# Pass 4 cleared three of the six (ADR-0144 dec. 4): NavigatorMain.gd is now booked
# `assembler` because nothing calls it, and the other two are booked by check 4 no
# longer asking a library to be wiring.
KNOWN = {
    # ADR-0143 dec. 3 — a full-screen overlay, instantiated whole and freed on dismissal,
    # is a navigation transition, not composition. Ratified; the site is not a defect.
    #
    # Pinned WITHOUT the line number, deliberately. `hit` matches by `startswith`, so the
    # trailing colon still names the exact site while surviving any edit ABOVE it. It was
    # pinned at `:321` and the site had already drifted to `:374` before ADR-0180 touched
    # this file — so the guard was reporting the SAME site twice, once as a new defect and
    # once as "FIXED, UNPINNED", and had been red for that reason alone. A pin keyed to a
    # line number reports the editor, not the defect (cf. CLAUDE.md on citing addresses
    # rather than disassembly line numbers).
    "MOUNTED — assets/scenes/Formation.tscn <- src/scenarios/NavigatorMain.gd:",
    # ADR-0181 — the world map's START-menu row mounts the COORDINATOR, for the same reason and
    # in the same shape ADR-0143 dec. 3 already ratified above: instantiated whole, freed on
    # dismissal, a navigation transition rather than composition. The two rows are one decision
    # applied to the two screens the navigator opens; `run_formation_view` still takes the bare
    # `Formation.tscn`, which is why BOTH sites exist rather than one replacing the other.
    # Pinned without the line number, for the reason the comment above gives.
    "MOUNTED — assets/scenes/FormationDetailTransition.tscn <- src/scenarios/NavigatorMain.gd:",
    # ADR-0161/0162 — `run_world_map` mounts the overworld the same way, and awaits the same
    # `dismissed`. Third instance of one ratified shape, not a third decision.
    "MOUNTED — assets/scenes/WorldMap.tscn <- src/scenarios/NavigatorMain.gd:",
    # ADR-0143 dec. 4 — two root assemblers are also libraries. Recorded, not overturned.
    # ADR-0144 dec. 4 keeps both in `UI`: FormationScene.gd is a base class
    # (`extends FormationScene`) publishing SCREEN/PIXELS_PER_UNIT/ROWS/COLS and
    # vitals_view_from_character() to five files, and FormationDetailTransition.gd is a
    # static-factory library `mount_over_map()`d by TWO roots — ADR-0135 dec. 9's own
    # shape, which that decision already resolved AWAY from `assembler`.
    "CALLED — src/ui3/formation/FormationScene.gd",
    "CALLED — src/ui3/formation/FormationDetailTransition.gd",
}
hit = {k for k in KNOWN if any(m.startswith(k) for m in fail)}
fail = [m for m in fail if not any(m.startswith(k) for k in KNOWN)]
for k in sorted(KNOWN - hit):
    fail.append(f"FIXED, UNPINNED — remove from KNOWN: {k}")

if fail:
    print(f"check_root_set: {len(fail)} problem(s)")
    for m in fail:
        print("  " + m)
    sys.exit(1)
n = collections.Counter(r["status"] for r in rows)
print(f"check_root_set: OK — {n['root']} roots ({sum(1 for r in rows if r['set']=='game')} game, "
      f"{sum(1 for r in rows if r['set']=='authoring')} authoring), "
      f"{n['declined']} declined, {n['component']} components; {len(census)} scenes declared")
