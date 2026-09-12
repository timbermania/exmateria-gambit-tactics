#!/usr/bin/env python3
"""The blueprint walk, guarded.

Prologue pass 4's guard over `tools/classify_blueprint.py`. The classifier has
no catch-all by design, but nothing re-ran it, and three of its own stated rules
lived only as comments. This checks all four:

  1. the walk places every file — zero UNCLASSIFIED, which is the classifier's
     own exit condition (ADR-0131 dec. 4);
  2. every exact-path rule names a file that exists, and none is DEAD — shadowed
     by an earlier rule that already matches it;
  3. ADR-0140 dec. 1's rule, which was a comment: *"Keep every entry here
     matching an actual file, or the shadow returns."* It returned anyway, at a
     smaller scale — "Map" preceded "Ui", so the UI3 owner-map tool was booked
     `Battlefield`. Every DEBUG_HOST / DEBUG_OWNER / DEBUG_EXACT entry must match
     a real `src/debug/` stem, and no DEBUG_OWNER fragment may be wholly
     shadowed by an earlier one;
  4. the ADR-0144 population — `src/data/` AND `addons/exmateria_almanac/`,
     which is where thirty-one of its files went at extraction #5 — has no
     catch-all, and its `content` rows are re-derived from source, not trusted:
     CONTEXT.md's *Hand-authored data asset* shape (a static cache + a lazy
     `_ensure_loaded` + one `JsonAsset.load_dict` of a `.json` under `assets/`
     or under the addon) is detected directly;
  5. every addon walk root books `tests/` to an EXCLUDED `tests` bucket
     (ADR-0194 dec. 9). Check 2 cannot judge those four rules — they are
     deliberately ahead of the tree, since the alternative is that the first
     test move corrupts the frozen register — so this arm replaces it, and
     asks the question check 2 never asked: does the rule FIRE.

Run from the package root.  Exit 0 = clean.
"""
import importlib.util, io, contextlib, pathlib, re, sys

fail = []


def load_classifier():
    spec = importlib.util.spec_from_file_location("cb", "tools/classify_blueprint.py")
    mod = importlib.util.module_from_spec(spec)
    argv = sys.argv
    sys.argv = ["classify_blueprint.py"]
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            spec.loader.exec_module(mod)   # it ends in sys.exit(); the import is for the tables
    except SystemExit as e:
        if e.code:
            fail.append("UNCLASSIFIED — classify_blueprint.py exits non-zero; "
                        "run `uv run python tools/classify_blueprint.py --list-unclassified`")
    finally:
        sys.argv = argv
    return mod


cb = load_classifier()
walked = {p.as_posix() for p in cb.walk()}

# --- 2. exact-path rules: present, and not shadowed ---------------------------
for i, (pat, bucket) in enumerate(cb.RULES):
    if pat.endswith("/"):
        # ADR-0194 dec. 9's rules are PROVISIONED — they must exist before the
        # directory does, because the alternative is that the first test move
        # books 1,796 lines of test code as production source and corrupts the
        # frozen register in the same commit. "Nothing under it is walked" is
        # their correct state on the day they land, so this arm cannot judge
        # them; check 5 below judges them instead, and judges the thing that
        # can actually go wrong here (a tests rule ordered after its addon's
        # own prefix rule, which is a directory-over-directory shadow this
        # loop does not look for).
        if bucket == "tests" and pat.endswith("/tests/"):
            continue
        if not any(r.startswith(pat) for r in walked):
            fail.append(f"DEAD DIRECTORY RULE — nothing under {pat!r} is walked")
        continue
    if pat not in walked:
        fail.append(f"STALE RULE — {pat!r} -> {bucket!r} names a file the walk does not see")
        continue
    for j, (earlier, ebucket) in enumerate(cb.RULES[:i]):
        if earlier.endswith("/") and pat.startswith(earlier):
            fail.append(f"SHADOWED RULE — {pat!r} -> {bucket!r} is dead; "
                        f"rule #{j} {earlier!r} -> {ebucket!r} already claims it")
            break
        if earlier == pat:
            fail.append(f"DUPLICATE RULE — {pat!r} appears at #{j} -> {ebucket!r} and #{i} -> {bucket!r}")
            break

# --- 3. the src/debug/ tables ------------------------------------------------
stems = sorted(p.stem for p in pathlib.Path("src/debug").rglob("*.gd"))
for h in cb.DEBUG_HOST:
    if not any(h in s for s in stems):
        fail.append(f"DEAD DEBUG_HOST — {h!r} matches no src/debug/ file (ADR-0140 dec. 1)")
for s in cb.DEBUG_EXACT:
    if s not in stems:
        fail.append(f"DEAD DEBUG_EXACT — {s!r} is not a src/debug/ stem")
seen_by = {}
for idx, (frag, owner) in enumerate(cb.DEBUG_OWNER):
    hits = [s for s in stems if frag in s and s not in cb.DEBUG_EXACT]
    if not hits:
        fail.append(f"DEAD DEBUG_OWNER — {frag!r} -> {owner!r} matches no src/debug/ file "
                    f"(ADR-0140 dec. 1)")
        continue
    reachable = [s for s in hits
                 if not any(h in s for h in cb.DEBUG_HOST)
                 and next(f for f, _ in cb.DEBUG_OWNER if f in s) == frag]
    if not reachable:
        stealers = sorted({next(f for f, _ in cb.DEBUG_OWNER if f in s) for s in hits
                           if not any(h in s for h in cb.DEBUG_HOST)})
        fail.append(f"SHADOWED DEBUG_OWNER — {frag!r} -> {owner!r} never fires; every file it "
                    f"matches is taken first by {stealers or ['DEBUG_HOST']}")

# --- 4. the ADR-0144 population: no catch-all, `content` re-derived from source
#
# 🔴 THE POPULATION MOVED AND THE WALK MOVED WITH IT (ADR-0251 dec. 7). This
# check was written against `src/data/`, where all twelve stores lived. #945
# moved thirty-one of those files into `addons/exmateria_almanac/`; a walk still
# scoped to `src/data/` would have found ONE file left (`SpriteRigContent.gd`,
# ADR-0243 dec. 5), reported OK, and stopped asserting the two-way rule over the
# eleven stores it exists for — green, on a surface nobody was watching.
#
# The two roots are ONE population and are named as one, so the next move has to
# come here rather than silently shrink the subject.
ADR_0144_ROOTS = ("src/data", "addons/exmateria_almanac")
EXACT = {pat for pat, _ in cb.RULES if not pat.endswith("/")}
for pat, _ in cb.RULES:
    for root in ADR_0144_ROOTS:
        if pat == root + "/":
            fail.append(f"CATCH-ALL RETURNED — ('{root}/', ...) books whatever the exact rules "
                        "miss; ADR-0144 dec. 2 removed it and ADR-0251 dec. 7 declined to "
                        "restore it one directory over")


def adr_0144_files():
    """Every `.gd` under either root, EXCLUDING the addon's own scaffolding.

    `plugin.gd` and the façade are `infrastructure` by rule and are neither
    tables nor rules over one — the membership ADR-0243 dec. 4 counted is 32
    files and these two are not in it.
    """
    out = sorted(pathlib.Path("src/data").glob("*.gd"))
    root = pathlib.Path("addons/exmateria_almanac")
    out += sorted(q for q in root.rglob("*.gd")
                  if q.name not in ("plugin.gd", "exmateria_almanac.gd"))
    return out


for p in adr_0144_files():
    if p.as_posix() not in EXACT:
        fail.append(f"UNRULED — {p.as_posix()} has no exact rule (ADR-0144 dec. 2)")

# Declared exemptions from check 4's two-way `content` <-> store rule, KEYED BY
# DIRECTION. One set skipping BOTH arms is a blanket exemption wearing an
# exception's name: a file listed to excuse the direction it violates stops
# asserting the direction it does not, silently and for good. Worked case —
# `SpriteRigContent.gd` is exempted below because it is booked `content` without
# the store shape; give it that shape later and re-book it, and STORE NOT CONTENT
# is the arm that should fire. Under a single set it would not have.
SHAPE_BUT_NOT_CONTENT = {
    # has the shape but is not a store: it implements EVTCHR_CLUT_RESOLUTION.md's
    # two-axis body-row rule OVER a baked manifest. Behaviour, so it keeps its system.
    "addons/exmateria_sprite_rig/content/SpritePaletteResolver.gd",
}

CONTENT_BUT_NOT_SHAPE = {
    # #743 / ADR-0217 dec. 9: the host side of the rig's content port -- seven
    # forwards onto four stores, no cache, no `_ensure_loaded`, no `load_dict`,
    # because it is a TRANSLATION and not a table. `content` is not a judgement
    # call here: ADR-0156 rules that new code with no original is `content`, and
    # booking it `Sprite Rig` instead would land the severance in the bucket it
    # drains and read P3c as 7 rather than 0 (ADR-0167's own fix first read as
    # GROWTH for exactly that reason).
    "src/data/SpriteRigContent.gd",
}


def is_store(path):
    """CONTEXT.md -> Hand-authored data asset: the `JobDatabase` shape.

    🔴 THE PAYLOAD PATH IS PART OF THE SHAPE, AND THE PAYLOADS MOVED TOO
    (ADR-0251 dec. 2). All thirteen `assets/**.json` files the twelve stores
    load travelled into the addon with them — a table left behind in the host is
    an outbound edge into the game, which is what ADR-0146 dec. 1 ruled. A regex
    still spelling only `res://assets/` would return False for every one of
    them, and the two-way rule below would then fire ELEVEN false CONTENT NOT A
    STORE failures while asserting nothing.
    """
    txt = path.read_text(errors="replace")
    return ("JsonAsset." in txt
            and "_ensure_loaded" in txt
            and re.search(r'res://(?:assets|addons/exmateria_almanac)/[^"]+\.json',
                          txt) is not None)


for p in adr_0144_files():
    rel = p.as_posix()
    booked = cb.classify(rel)
    if is_store(p) and booked != "content" and rel not in SHAPE_BUT_NOT_CONTENT:
        fail.append(f"STORE NOT CONTENT — {rel} has the JobDatabase shape "
                    f"(JsonAsset.load_dict + lazy _ensure_loaded) but is booked {booked!r}")
    if booked == "content" and not is_store(p) and rel not in CONTENT_BUT_NOT_SHAPE:
        fail.append(f"CONTENT NOT A STORE — {rel} is booked 'content' but has no "
                    f"JsonAsset.load_dict/_ensure_loaded pair; state the reason or reclassify")

# --- 5. ADR-0194 dec. 9: every addon walk root books its tests/ to `tests` ----
# The claim is three things and each fails differently:
#   * a rule EXISTS for every addon walk root — add extraction #4's addon to
#     WALK_ROOTS and forget this, and its tests book to the system;
#   * the rule FIRES — it is ahead of that addon's own prefix rule, which is a
#     directory-over-directory shadow check 2 does not look for;
#   * the bucket is SUBTRACTED — booking without excluding is the +1,796-line
#     reading dec. 9 exists to stop, and `tests` must be an OTHER row so it is
#     printed before it is subtracted (ADR-0131 dec. 4).
ADDON_ROOTS = [r for r in cb.WALK_ROOTS if r.startswith("addons/")]
for root in ADDON_ROOTS:
    probe = f"{root}/tests/Probe.gd"
    booked = cb.classify(probe)
    if booked != "tests":
        fail.append(f"TESTS RULE MISSING OR SHADOWED — {probe} books {booked!r}, not 'tests'. "
                    f"An addon-owned test is inside a walk root; a rule ('{root}/tests/', 'tests') "
                    f"must exist AHEAD of ('{root}/', ...) (ADR-0194 dec. 9)")
if "tests" not in cb.EXCLUDED:
    fail.append("TESTS NOT EXCLUDED — `tests` is booked but not in EXCLUDED, so moved tests "
                "add to the baseline as production source (ADR-0194 dec. 9)")
if "tests" not in cb.OTHER:
    fail.append("TESTS NOT REPORTED — `tests` is in EXCLUDED but not in OTHER, so it is "
                "subtracted without ever being printed (ADR-0131 dec. 4)")

if fail:
    print(f"check_blueprint_walk: {len(fail)} problem(s)")
    for m in fail:
        print("  " + m)
    sys.exit(1)
sh = sum(1 for r in walked if pathlib.Path(r).suffix in cb.SHADER_SUFFIXES)
print(f"check_blueprint_walk: OK — {len(walked)} source files walked ({sh} shaders), "
      f"0 unclassified; {len(EXACT)} exact rules all live; "
      f"{len(cb.DEBUG_HOST)}+{len(cb.DEBUG_OWNER)}+{len(cb.DEBUG_EXACT)} src/debug/ entries all fire; "
      f"{len(ADDON_ROOTS)} addon roots book tests/ to an excluded `tests` bucket")
