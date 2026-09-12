#!/usr/bin/env python3
"""Guard: the Tile-door register — ADR-0164 dec. 4 criterion 3, added by ADR-0166 dec. 4.

    uv run python tools/check_lattice_doors.py [--list]

THE RULE. No `Battlefield` member reachable from outside `addons/exmateria_battlefield/`
may have `Tile` in a RETURN or SIGNAL-PAYLOAD position. Target 0. Today: 0 — criterion 3
is MET, closed by ADR-0194. `DOOR_BURN_DOWN` is empty and arm 1 is still enforcing.

WHY THIS REGISTER EXISTS AND THE OTHER TWO CANNOT DO ITS JOB. ADR-0164 dec. 4 scores the
lattice seam by three criteria, and the first two are both satisfied by retyping three
lines:

  1. published-symbol set equality — `Tile` absent from the set of `Battlefield`
     `class_name`s any other system's source NAMES. Catches a type annotation.
  2. the duck-typed-door register — call sites whose receiver carries no type and whose
     method is on the published port. Counts a CALL.

Neither can see a STORED NODE. ADR-0166 measured `MovementComponent.current_logical_tile`
/ `Unit.get_current_tile()` at **56 lines over 24 files with 3 typed**; retyping those
three to `Node3D` satisfies 1 and 2 while every one of the 56 still holds a live `Tile`.

PRODUCER-SIDE, DELIBERATELY, AND THAT IS THE WHOLE DESIGN. It is the only one of the
three criteria that is DECIDABLE: a closed set of ~47 addon files, against a consumer-side
pattern that by construction carries no type name anywhere in 644 host files. It also
makes the held-node shape IMPOSSIBLE rather than merely counted — if no published door
hands out a `Tile`, no host can hold one, so ADR-0166's holders 3, 4 and 6 close without
anyone having to find their 53 invisible sites.

WHAT THIS GUARD CANNOT SEE, stated because every blind spot on this map has scored zero
and every one has been real:

  - **Nothing about a multi-line signature, and that is a correction.** This scan
    JOINS a wrapped header across lines until its parentheses balance, because the
    first draft did not and asserted there were none in the addon — there are
    **fourteen**, including `TileOverlayColor.flat_color` and six in `MapComposer`.
    The draft's own scan-limit arm is what reported them, which is the only reason
    this line is a design note and not a silent hole. The join reports the header's
    FIRST line, so a citation stays stable when the wrap changes.
  - **`Variant` and `Node3D` returns that hand out a `Tile` anyway.** A door that drops
    its type annotation leaves this register exactly as it leaves criterion 1 —
    ADR-0164 dec. 4(b)'s point, one criterion over. Criterion 2 is what covers that, and
    criterion 2 does not exist yet.
  - **A `Tile` reached through a field rather than a member.** `var tiles: Array[Tile]`
    on a public class is readable from outside and is not a return or a payload. Arm 3
    reports the parameter form of the same gap; the field form is not scanned.
  - **`tests/`.** `classify()` returns `None` for every file under `tests/`, so "outside
    the addon" there is not a system reach. Arm 1 counts a test file as an outside
    namer, deliberately — a test holding a `Tile` is still a host holding a `Tile` — and
    prints which of the two it was.
  - **WHICH door a namer reached.** `get_tile` is declared twice (`TerrainIndex` and
    `MapComposer`'s forwarder) and `outside_namers` keys on the member NAME, so both
    rows report the same 17 files. That is deliberate: attributing a duck-typed
    `map.get_tile(x, z)` to one of the two is consumer-side type inference, which is
    criterion 2's job and is exactly what this criterion exists to NOT depend on
    (ADR-0166 dec. 4: producer-side "because that is the only side that is decidable").
    The register's claim per row is the BOOLEAN — this door is named outside — and the
    count is context, not attribution. The report says so.

ARMS.

  arm 1  ENFORCING, burn-down. A door named outside the addon. Rows on
         `DOOR_BURN_DOWN` print above the OK line under a heading that says it is not a
         pass; an UNLISTED door fails, and a LISTED row whose door no longer exists
         fails as STALE. Both directions, same shape as
         `check_addon_portability.ARM1_BURN_DOWN` and `check_par_shaders.BURN_DOWN`.

  arm 2  REPORTING. A public door with `Tile` in the same position that NOTHING outside
         the addon names. Not a failure — ADR-0166 dec. 4 excludes
         `DynamicTerrainBuilder.add_terrain` / `remove_terrain_in_bounds` on exactly
         this ground — but it is one caller away from arm 1, so it prints.

  arm 3  REPORTING, and it is a gap in the rule as ADR-0166 dec. 4 WRITES it. The rule
         says "return or signal-payload position". A PARAMETER is neither, and it is the
         same held-node shape from the other direction: a host that calls
         `SceneTreeManager.add_tiles(tiles: Array[Tile])` must HOLD an `Array[Tile]` to
         call it. Reported rather than enforced because the two instances today are
         internal to the addon, so nothing outside holds one; the day one is named
         outside, arm 3 is arm 1 and the rule needs amending rather than the code.
"""
import pathlib
import re
import sys

PROJECT_DIR = pathlib.Path(__file__).resolve().parent.parent
ADDON_ROOT = "addons/exmateria_battlefield/"

# Where an "outside" namer can live. The addon itself is excluded by prefix below.
OUTSIDE_ROOTS = ("src", "tests", "assets", "addons")
OUTSIDE_SUFFIXES = (".gd", ".tscn", ".tres")

# --- the burn-down (ADR-0166 dec. 4) --------------------------------------
# `(addon file, member) -> (owner, why)`. A NAMED LIST, never a pattern — #424 measured
# on this codebase that an exclusion expressed as a FILTER manufactures its own debt and
# cannot tell a triaged door from one that merely matches.
#
# 🔴 THE BASELINE WAS NINE, NOT THE EIGHT ADR-0166 dec. 4's TABLE NAMED, and the ninth
# was created by pass 6 itself. `TileCursor.cursor_stepped(grid_pos: Vector2i, tile: Tile)`
# was a fourth signal beside `cursor_moved` / `cursor_confirmed` / `cursor_inspected`, and
# #589 connected `src/scenes/BattlefieldWiring.gd:77` to it AFTER dec. 4's table was
# measured. The table was not wrong about what it read; it was a reading taken before the
# edge existed. That is the register catching its own ADR, which is what it is for.
#
# ✅ EMPTY SINCE ADR-0194, AND THE ARM STAYS ARMED. Criterion 3 reads 0 of a target 0:
# nine rows, nine closed. An empty burn-down is not a disabled guard — an UNLISTED door
# still reds arm 1 the moment one is written, and `test_a_LISTED_row_prints_above_the_verdict`
# constructs both a door and a row so the printing property is still exercised at size
# zero. What emptied it:
#
#   pass 6 (ADR-0170 dec. 1, ADR-0192 dec. 4) — 4 rows. `MapComposer.get_tile` /
#     `get_all_tiles` deleted outright (a forwarder, not a second implementation);
#     `TerrainIndex.get_tile` / `get_all_tiles` stopped being NAMED outside the addon when
#     the store lost its `class_name` and the last `tests/` file that hand-built one became
#     a `Lattice` subclass. Both pairs now report under INTERNAL-BUT-PUBLIC.
#   ADR-0194 — 5 rows, the whole `TileCursor` set. The four `cursor_*` payloads narrowed
#     to `(grid_pos: Vector2i)` and `active_tile()` became `_tile_under_cursor()`. Not one
#     host consumer lost information: three `FormationMapHost` handlers and
#     `BattlefieldWiring._play_cursor_cue` bound the node as `_tile` and discarded it, and
#     `GPUArena._on_deployment_confirm` narrowed it straight back to
#     `Vector2i(grid_x, grid_z)` — the cursor's own `grid_pos`, which is what the tile was
#     DERIVED from.
#
# 🔴 ADR-0192's prediction table said 9 -> 4 and that number was WRONG BY ONE; its own
# Consequences said "the FIVE `TileCursor` rows are a separate piece of work", which was
# right. The 4 was a survival from ADR-0166 dec. 4's table of EIGHT. 9 - 4 closed = 5, and
# ADR-0194 closed those five.
DOOR_BURN_DOWN = {}


# 🔴 `strip_noncode` IS LIFTED BY SOURCE SLICE, NOT IMPORTED, and the difference is 73
# SECONDS. `touch_matrix.py` runs its whole cross-system walk at import; exec'ing it to
# reach one pure function cost this guard 73s of its 85s, and the tax multiplied because
# `run_all_tests.sh` pre-flight is re-entered as a subprocess by `test_run_tests_parallel`
# and this guard's own 11 seed tests each call `main()`. A full suite run had to be killed
# before the profile was taken — the two "obvious" optimisations tried first (walk once,
# search whole-text instead of per-line) each moved the total by under a second, because
# neither was where the time was. PROFILE BEFORE OPTIMISING; both of those are kept
# because they are right, not because they helped.
#
# Slicing rather than copying is `residue.py`'s idiom, for its stated reason: the two
# programs cannot drift apart about what a reference is. The `sys.exit` below is
# deliberate — a silent fallback to a private copy is how they WOULD drift.
_tmsrc = (PROJECT_DIR / "tools" / "touch_matrix.py").read_text()
_fnsrc = re.search(r'^def strip_noncode\(.*?(?=^\S)', _tmsrc, re.S | re.M)
if not _fnsrc:
    sys.exit("tools/touch_matrix.py no longer defines strip_noncode at top level")
_fn = {"re": re}
exec(_fnsrc.group(0), _fn)
strip_noncode = _fn["strip_noncode"]

# `-> Tile:` / `-> Array[Tile]:` — never `-> TileCursor`, hence the trailing boundary.
_RET = re.compile(r"^\s*(?:static\s+)?func\s+(\w+)\s*\(.*\)\s*->\s*(Tile|Array\[Tile\])\s*:")
_SIG = re.compile(r"^\s*signal\s+(\w+)\s*\((.*)\)\s*$")
_FUNC = re.compile(r"^\s*(?:static\s+)?func\s+(\w+)\s*\((.*?)\)\s*(?:->.*)?:")
_TILE_PARAM = re.compile(r":\s*(Tile|Array\[Tile\])\s*(?:=|,|$)")
_HEADER_OPEN = re.compile(r"^\s*(?:(?:static\s+)?func|signal)\s+\w+\s*\(")


def _joined_headers(lines):
    """(first_lineno, one-line header) for every `func` / `signal` header, wrapped or not.

    GDScript wraps a long signature across lines; the addon has fourteen. Joining until
    the parentheses balance is what makes the three regexes below sufficient, and the
    lineno reported is the header's FIRST line so a citation survives a re-wrap."""
    out = []
    i, n = 0, len(lines)
    while i < n:
        if not _HEADER_OPEN.match(lines[i]):
            i += 1
            continue
        start, buf, depth = i, [], 0
        while i < n:
            buf.append(lines[i].strip())
            depth += lines[i].count("(") - lines[i].count(")")
            i += 1
            if depth <= 0:
                break
        out.append((start + 1, " ".join(buf)))
    return out


def doors(addon: pathlib.Path):
    """(rel, member, line, kind) for every `Tile` in a return / payload / param slot."""
    out = []
    for q in sorted(addon.rglob("*.gd")):
        rel = q.relative_to(PROJECT_DIR).as_posix()
        for lineno, hdr in _joined_headers(strip_noncode(q.read_text(errors="ignore"))):
            m = _RET.match(hdr)
            if m:
                out.append((rel, m.group(1), lineno, "return"))
                continue
            m = _SIG.match(hdr)
            if m and _TILE_PARAM.search(m.group(2) + ","):
                out.append((rel, m.group(1), lineno, "signal payload"))
                continue
            m = _FUNC.match(hdr)
            if m and _TILE_PARAM.search(m.group(2) + ","):
                out.append((rel, m.group(1), lineno, "parameter"))
    return out


_CORPUS = None


def corpus(refresh: bool = False):
    """Every line outside the addon, read ONCE per run — `[(rel, lineno, text)]`.

    🔴 THE FIRST DRAFT WALKED THE TREE ONCE PER MEMBER, and the cost was not academic.
    `outside_namers` did its own `rglob` over `src/`, `tests/`, `assets/` and `addons/`
    for each of fourteen members — fourteen full walks per run, and eleven runs inside
    `test_check_lattice_doors`, i.e. 154 walks per nested invocation. `run_all_tests.sh`
    pre-flight is itself re-entered as a subprocess by `test_run_tests_parallel`, so the
    tax multiplied again and a full suite run had to be killed. The walk does not depend
    on the member; only the match does.

    `refresh` is not optional convenience: the seed tests write a door and a caller into
    the tree BETWEEN in-process `main()` calls, so a cache that outlived one call would
    make every seed after the first vacuous — a performance fix that silently disarms the
    arms it speeds up. `main()` refreshes on entry.
    """
    global _CORPUS
    if _CORPUS is not None and not refresh:
        return _CORPUS
    rows = []
    for root in OUTSIDE_ROOTS:
        base = PROJECT_DIR / root
        if not base.is_dir():
            continue
        for q in sorted(base.rglob("*")):
            if not (q.is_file() and q.suffix in OUTSIDE_SUFFIXES):
                continue
            rel = q.relative_to(PROJECT_DIR).as_posix()
            if rel.startswith(ADDON_ROOT):
                continue
            rows.append((rel, q.read_text(errors="ignore")))
    _CORPUS = rows
    return _CORPUS


def outside_namers(member: str):
    """Files outside the addon that NAME `member` — a call, a signal use, or a
    `.tscn` connection. Signals are connected in scenes, so `.tscn` is scanned too:
    a register that read only `.gd` would score a scene-wired publish at zero."""
    # 🔴 NO `(?<![.\w])` ON THE SIGNAL PATTERN, and the first draft had one. A signal is
    # ALWAYS reached through its emitter — `tile_cursor.cursor_stepped.connect(...)` — so
    # a lookbehind excluding a preceding `.` excludes exactly the form that exists. It
    # scored `cursor_stepped` and `cursor_inspected` as named by NOBODY and filed both to
    # the reporting arm, i.e. it turned two live doors into "internal". The method
    # pattern below wants the leading `.` for the opposite reason: `get_tile(` unanchored
    # would match the addon's own `func get_tile` in any file that redefined it.
    pats = [re.compile(r"\.%s\s*\(" % re.escape(member)),
            re.compile(r"%s\s*\.\s*(connect|emit|is_connected|disconnect)"
                       % re.escape(member)),
            re.compile(r'signal\s*=\s*"%s"' % re.escape(member)),
            re.compile(r'["\']%s["\']' % re.escape(member))]
    hits = []
    for rel, txt in corpus():
        # Cheap reject: a file that does not contain the bare name cannot match any of
        # the four patterns, and `in` is a C-level substring scan.
        if member not in txt:
            continue
        # 🔴 SEARCH THE WHOLE TEXT, NOT LINE BY LINE. The single-walk fix above did not
        # help because the walk was never the cost: fourteen members x ~1800 files x
        # ~200 lines x four patterns is ~20M Python-level regex calls, and the run stayed
        # at 85s with `user` == `real`. One `p.search(txt)` per (file, pattern) is the
        # same question answered inside the regex engine, and the line number comes from
        # counting newlines before the match rather than from having split them.
        best = None
        for pat in pats:
            m = pat.search(txt)
            if m and (best is None or m.start() < best):
                best = m.start()
        if best is not None:
            hits.append("%s:%d" % (rel, txt.count("\n", 0, best) + 1))
    return hits


def main() -> int:
    addon = PROJECT_DIR / ADDON_ROOT
    if not addon.is_dir():
        print(f"{ADDON_ROOT} does not exist")
        return 1
    corpus(refresh=True)   # see `corpus`: a stale cache disarms the seed tests

    found = doors(addon)
    # Public members only. A leading `_` is not reachable from outside by convention,
    # and ADR-0166 dec. 4 excludes `_get_tile_at` / `_create_tile` on that ground.
    public = [d for d in found if not d[1].startswith("_")]
    print("subject: %s — %d .gd file(s), %d member(s) with `Tile` in a return, "
          "signal-payload or parameter slot, %d of them public."
          % (ADDON_ROOT, len(list(addon.rglob("*.gd"))), len(found), len(public)))

    arm1, arm2, arm3 = [], [], []
    for rel, member, line, kind in public:
        namers = outside_namers(member)
        if kind == "parameter":
            arm3.append((rel, member, line, kind, namers))
        elif namers:
            arm1.append((rel, member, line, kind, namers))
        else:
            arm2.append((rel, member, line, kind, namers))

    listed = {(r, m) for r, m, _, _, _ in arm1}
    unlisted = [row for row in arm1 if (row[0], row[1]) not in DOOR_BURN_DOWN]
    burned = [row for row in arm1 if (row[0], row[1]) in DOOR_BURN_DOWN]
    stale = sorted(set(DOOR_BURN_DOWN) - listed)

    if burned:
        print("\nTILE-DOOR REGISTER — %d public member(s) hand a `Tile` across the addon\n"
              "boundary and are NAMED in DOOR_BURN_DOWN with an owner. Not a pass: this is\n"
              "ADR-0164 dec. 4 criterion 3 unmet, on record, target 0 (ADR-0166 dec. 4)."
              % len(burned))
        for rel, member, line, kind, namers in burned:
            owner, why = DOOR_BURN_DOWN[(rel, member)]
            shown = ", ".join(namers[:4]) + ("…" if len(namers) > 4 else "")
            print("  %s:%d  %s  (%s)\n      the NAME is used in %d file(s): %s\n      %s — %s"
                  % (rel, line, member, kind, len(namers), shown, owner, why))
        print("\n  (`get_tile` and `get_all_tiles` are each declared TWICE — `TerrainIndex`\n"
              "  and `MapComposer`'s forwarder — so both rows report the same namers. Which\n"
              "  of the two a duck-typed `map.get_tile(x, z)` reached is consumer-side type\n"
              "  inference, i.e. criterion 2's job and the thing this criterion exists to\n"
              "  not depend on. The claim per row is the boolean, not the count.)")

    if arm2:
        print("\nINTERNAL-BUT-PUBLIC — %d public member(s) with `Tile` in the same position\n"
              "that NOTHING outside the addon names. Not a failure (ADR-0166 dec. 4 excludes\n"
              "these by name), and one caller away from the register above."
              % len(arm2))
        for rel, member, line, kind, _ in arm2:
            print("  %s:%d  %s  (%s)" % (rel, line, member, kind))

    if arm3:
        print("\nPARAMETER POSITION — %d public member(s) take a `Tile` as an ARGUMENT. The\n"
              "rule as ADR-0166 dec. 4 writes it says \"return or signal-payload position\",\n"
              "so these are outside it; they are the same held-node shape from the other\n"
              "direction, because a caller must HOLD one to make the call. Reported, with\n"
              "whether anything outside the addon names them." % len(arm3))
        for rel, member, line, kind, namers in arm3:
            print("  %s:%d  %s  (%s) — named outside the addon by %d file(s)%s"
                  % (rel, line, member, kind, len(namers),
                     (": " + ", ".join(namers[:3])) if namers else ""))

    if "--list" in sys.argv:
        print("\nDOOR_BURN_DOWN rows:")
        for (rel, member), (owner, why) in sorted(DOOR_BURN_DOWN.items()):
            print("  %s  %s   [%s]\n      %s" % (rel, member, owner, why))

    if unlisted:
        print("\nTILE DOOR: %d public member(s) hand a `Tile` across the addon boundary and\n"
              "are NOT on DOOR_BURN_DOWN (ADR-0164 dec. 4 criterion 3).\n" % len(unlisted))
        for rel, member, line, kind, namers in unlisted:
            print("  %s:%d  %s  (%s) — named by %s"
                  % (rel, line, member, kind, ", ".join(namers[:4])))
        print("\nA published door that hands out a `Tile` lets a host STORE one, and a stored\n"
              "node is invisible to criteria 1 and 2 — that is the whole reason this register\n"
              "is producer-side. Answer with a value (`TerrainCell`) or a key (`Vector2i`),\n"
              "or add the row with its owner and the ticket that closes it.")

    if stale:
        print("\nSTALE DOOR_BURN_DOWN — %d entr(ies) name a door that no longer hands out a\n"
              "`Tile`, or that nothing outside the addon names any more. Delete the row; a\n"
              "burn-down that outlives its debt is a list nobody rereads.\n" % len(stale))
        for rel, member in stale:
            owner, _why = DOOR_BURN_DOWN[(rel, member)]
            print("  %s  %s   [%s]" % (rel, member, owner))

    if unlisted or stale:
        return 1

    if burned:
        print("\nTile-door register: %d of a target 0. Every one is on DOOR_BURN_DOWN with an\n"
              "owner, and no listed row has gone stale. This is goal #5's INBOUND half and no\n"
              "arm of check_addon_portability.py scores it — `score_goals.mechanical(goal=5)`\n"
              "has no inbound term at all (ADR-0164 dec. 4's ⚠️)." % len(burned))
    else:
        print("\nTILE-DOOR REGISTER CLEAR — no `Battlefield` member reachable from outside\n"
              "the addon has `Tile` in a return or signal-payload position (ADR-0164 dec. 4\n"
              "criterion 3, ADR-0166 dec. 4). No host can hold a lattice node, so holders 3,\n"
              "4 and 6 are impossible rather than merely counted.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
