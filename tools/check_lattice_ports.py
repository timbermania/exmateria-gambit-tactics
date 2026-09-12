#!/usr/bin/env python3
"""Guard: the duck-typed-door register — ADR-0164 dec. 4 criterion 2, built by ADR-0192.

    uv run python tools/check_lattice_ports.py [--list] [--emit-burndown]

THE RULE (ADR-0192 dec. 2, amending ADR-0170 dec. 5). A site that reaches the battlefield
lattice is clean **iff the receiver is provably annotated `Lattice`**. Target 0.

It is phrased as an ALLOWLIST and that inversion is the decision. ADR-0170 dec. 5 wrote
arm 1 as *"call sites whose receiver carries no type"*, and that sentence is false on FIVE
of its own fifteen sites — `map_composer: Node` x2, `map: Node3D` x2 and one `:=`
inference all carry a type and are all the defect. A denylist phrased against the ABSENCE
of an annotation needs a permanent special case for `Node`, `Node3D`, `Variant` and
inference, and every special case is a place the guard can be satisfied by writing a
different wrong type (ADR-0164 dec. 4(b)'s hole, one criterion over). "Is this receiver
annotated `Lattice`?" needs no type lattice and no special cases.

WHY THIS GUARD IS BUILT BEFORE THE PORT IT ENFORCES (ADR-0192 dec. 1). The port and
holder 4 together consume this register's entire population. A register written after them
is a scanner that reads zero, which is indistinguishable from a scanner that is broken —
and the only independent evidence that the hard part (receiver-type inference) is right is
that it reproduces a population somebody counted by hand. ADR-0170 dec. 5's **15** and
ADR-0192's **27 = 15 + 12** are that evidence, and they exist only until the port lands.
`PORT_BURN_DOWN` is that hand count, frozen.

BOTH NAME SETS, FROM DAY ONE. `Lattice` does not exist yet, so a scan keyed only on the
port's four future members (`terrain_at` / `world_position_at` / `is_cliff_edge` /
`all_cells`) is green today and proves nothing. It keys on those FOUR **and** the legacy
`get_tile` / `get_all_tiles`, and the legacy half burns down — the same both-directions
shape `check_lattice_doors.py` and `check_addon_portability.py` already use.

THREE SPELLINGS OF THE DOOR, and the third is the one every prior criterion missed:

  CALL      `map.get_tile(x, z)`, and the `has_method("get_tile")` probe form.
  FETCH     `var t: TerrainIndex = map.terrain_index` — the handle is not called for, it
            is READ OFF AN UNTYPED MAP. All twelve `TerrainIndex`-typed call sites got
            their handle here, so a register that scans only CALLS scores the acquisition
            path zero and a pass that re-points 27 calls has changed no structure at all
            (ADR-0192 dec. 3). A fetch is clean IFF its result lands immediately in a
            `Lattice`-annotated variable or field — one untyped step, at the seam, and
            everything after it typed. That is deliberately not a prohibition: six
            assembler scene roots hold the map as `@onready var map: Node3D =
            $ProceduralMap`, a NodePath fetch that infers `Node`, so `map.lattice` is a
            duck-typed read PERMANENTLY and by design, and an arm that failed on it would
            have no green state.
  PRODUCER  `func get_tile(x, z) -> Tile` in a host file — a mock map. It is the other
            end of the same duck-typing: ADR-0170 dec. 3 keeps the seam precisely so
            these can exist, and dec. 6 predicts >=4 of the 7 are DELETED rather than
            ported, which this register reports as stale rows, i.e. as the win.

WHAT THIS GUARD CANNOT SEE, stated because every blind spot on this map has scored zero
and every one has been real:

  - **A receiver typed through a chain it never binds.** `_vm.map_composer.get_tile(...)`
    is reported (a dotted receiver is never "provably `Lattice`"), but the guard does not
    resolve `_vm`'s class and read `map_composer` off it. Cross-file type resolution is
    not attempted anywhere in this repo's guards and is not attempted here.
  - **A name declared with one type and REBOUND to another.** Inference is per FILE and
    per NAME: a receiver is clean only if EVERY declaration of that name in its file is
    annotated `Lattice`. That is conservative in the safe direction (it over-reports,
    never under-reports) and it cannot see `var m: Lattice = ...` followed by `m = <a
    Node>`, which GDScript would reject anyway.
  - **A member INHERITED from a base class.** `GPUArena.gd:117` lands its fetch in
    `terrain_index`, declared `TerrainIndex` on `CombatHost.gd:24` and nowhere in
    `GPUArena` itself, so the row's reason reads *undeclared* rather than
    *`TerrainIndex`*. The VERDICT is right either way — inherited or not, it is not
    `Lattice` — and the reason text says which it could not see. Note the declaration
    itself is not on this register: a host holding `var x: TerrainIndex` is criterion 1's
    published-symbol job, not arm 1's.
  - **Autoloads and static class access.** `SomeSingleton.get_tile(...)` has no
    declaration in the calling file, so it lands on the register as undeclared. Correct
    by ADR-0192 dec. 2's rule and worth knowing: the row's reason will read `undeclared`,
    not `Node`.
  - **A reach through `call("get_tile", ...)` or a `Callable`.** A string-dispatched call
    is invisible to every arm. `has_method("<name>")` IS scanned, because it is the probe
    form that actually appears (`ScenarioUnitAlignmentDebugPanel.gd:132`).
  - **`.tscn` / `.tres`.** A lattice handle is not wired in a scene file anywhere in this
    tree; unlike `check_lattice_doors.py`'s signals, there is nothing to find there.
  - **Roots other than `src/`, `tests/`, `assets/` and `addons/`.** Measured at build
    time: every call and fetch outside those two code roots is INSIDE
    `addons/exmateria_battlefield/`, which owns the store and is exempt.

ARMS. Both ENFORCING, both burn-downs, both directions failing.

  arm 1  `src/` and any non-addon `addons/` or `assets/` file. Rows on `PORT_BURN_DOWN`
         print above the OK line under a heading that says it is not a pass; an UNLISTED
         site fails, and a LISTED row whose site is gone fails as STALE.

  arm 2  `tests/`. ⚠️ ENFORCING, and that is ADR-0192 dec. 7 ruled — see the amendment.
         ADR-0170 dec. 5 made it reporting-only *"because `classify()` returns `None` for
         every test file and a threshold there would be guesswork"*, while naming the risk
         it could not fix: *"arm 1 reaching zero while 20 cases sit in `tests/` reads as
         coverage."* A NAMED BURN-DOWN is not a threshold — it needs no `classify()` at
         all, only a stable identity — so dec. 5's objection does not reach it, and its
         failure mode (a stale row) is exactly the reporting dec. 6 wants when the mock
         producers are deleted rather than ported.

  Both arms print the three-way split (calls / fetches / producers) so ADR-0170 dec. 5's
  hand-measured 13-and-7 stay individually checkable, and arm 1 prints the 15/12 split
  inside its 27 so dec. 5's number survives as a live cross-check.
"""
import pathlib
import re
import sys

PROJECT_DIR = pathlib.Path(__file__).resolve().parent.parent
ADDON_ROOT = "addons/exmateria_battlefield/"
PORT_TYPE = "Lattice"

# Both name sets from day one (ADR-0192 dec. 1). The legacy half burns down.
FUTURE_METHODS = ("terrain_at", "world_position_at", "is_cliff_edge", "all_cells")
LEGACY_METHODS = ("get_tile", "get_all_tiles")
# The unpublished store, by path — it has no `class_name` to name it by
# (ADR-0192 dec. 4), so arm 3 finds each addon file's local alias for it.
STORE_PATH = ADDON_ROOT + "lattice/TerrainIndex.gd"
PORT_METHODS = FUTURE_METHODS + LEGACY_METHODS

# The handle FETCH, same two-name-set shape (ADR-0192 dec. 3).
FUTURE_HANDLES = ("lattice",)
LEGACY_HANDLES = ("terrain_index",)
PORT_HANDLES = FUTURE_HANDLES + LEGACY_HANDLES

SCAN_ROOTS = ("src", "tests", "assets", "addons")
TESTS_ROOT = "tests/"

# --- the burn-down (ADR-0192 dec. 1) --------------------------------------------------
# `(rel, label) -> (owner, why)`. A NAMED LIST, never a pattern — #424 measured on this
# codebase that an exclusion expressed as a FILTER manufactures its own debt and cannot
# tell a triaged site from one that merely matches.
#
# The KEY CARRIES NO LINE NUMBER, deliberately. This population is about to be re-pointed
# wholesale; a key that moved when a line moved would produce a stale row and an unlisted
# row for the same site on every unrelated edit above it. `label` is unique within a file:
# `recv.member()` for a call, `recv.handle` for a fetch, `func member()` for a producer.
# Several SITES therefore collapse onto one ROW — the report prints both counts.
PORT_BURN_DOWN = {
    # ---- arm 1 ----
    #
    # ✅ EMPTY, AND THAT IS THE PASS. Arm 1 shipped at 30 sites over 23 rows — 27 calls
    # (15 untyped-or-wrong + 12 `TerrainIndex`-typed) and 3 handle fetches — and the port
    # consumed every one of them at loop pass 6. Each row was deleted as its site went
    # STALE, which is the direction ADR-0192 dec. 1 built this guard to measure: the
    # register was written FIRST, validated against ADR-0170 dec. 5's hand-counted 15,
    # and then driven to zero by the work. A register written afterwards would read zero
    # whether it worked or not.
    #
    # It stays armed. The scan is unchanged and both name sets are still live, so a new
    # `src/` site reaching the lattice through a receiver that is not provably `Lattice`
    # is UNLISTED and reds the pre-flight — which is the only reason an empty burn-down
    # is worth keeping over a deleted guard.
    # ---- arm 2 ----
    #
    # ✅ EMPTY, AND THAT IS THE PASS. Arm 2 shipped at 32 sites over 25 rows — 12
    # consumer calls, 10 handle fetches over 9 files, and 10 mock-producer declarations
    # in 7 files — and every one closed at loop pass 6.
    #
    # ADR-0170 dec. 6's prediction was that **>=4 of the 7 mock producers get DELETED
    # rather than ported**. Measured: **all 7**. Four returned something that was not a
    # `Tile` (`ScenarioSpriteMoveTest`'s bare `Node3D`, `ScenarioCameraSwoopMonotonicTest`'s
    # ad-hoc `MockTile`, and two `FakeTile extends RefCounted`) and all four lost their
    # tile stand-in class outright — a `TerrainCell` is trivial to fabricate where a
    # `StaticBody3D` is not, which is dec. 6's stated cause. The other three hold real
    # `Tile` nodes because `TileCursor` still hands them out, and they became
    # `extends Lattice` overrides, which is dec. 5's other sanctioned route.
    #
    # 🔴 THAT ROUTE COST THIS GUARD A FIX. The producer scan counted an override inside
    # `extends Lattice` as a mock — it read 10 -> 19 on the pass that repaired all seven,
    # i.e. it scored the sanctioned repair as the defect, which is the hole ADR-0170
    # dec. 5's ⚠️ warns about ("arm 1 must be written so that BOTH routes pass; one
    # phrased against subclassing forbids the cheaper one"), landing on the producer arm
    # instead of arm 1. `_port_subclass_lines` is the repair.
    #
    # It stays armed, for the same reason arm 1 does: an unlisted `tests/` site reds the
    # pre-flight, which is what ADR-0192 dec. 7's ruling is FOR.
}


# 🔴 `strip_noncode` IS LIFTED BY SOURCE SLICE, NOT IMPORTED, and the difference is 73
# SECONDS. `touch_matrix.py` runs its whole cross-system walk at import; exec'ing it to
# reach one pure function cost `check_lattice_doors.py` 73s of its 85s, and the tax
# multiplies because `run_all_tests.sh` pre-flight is re-entered as a subprocess by
# `test_run_tests_parallel` and this guard's own seed tests each call `main()`. Slicing
# rather than copying is `residue.py:105`'s idiom, for its stated reason: the two programs
# cannot drift apart about what a reference is. The `sys.exit` is deliberate — a silent
# fallback to a private copy is how they WOULD drift.
_tmsrc = (PROJECT_DIR / "tools" / "touch_matrix.py").read_text()
_fnsrc = re.search(r'^def strip_noncode\(.*?(?=^\S)', _tmsrc, re.S | re.M)
if not _fnsrc:
    sys.exit("tools/touch_matrix.py no longer defines strip_noncode at top level")
_fn = {"re": re}
exec(_fnsrc.group(0), _fn)
strip_noncode = _fn["strip_noncode"]

# 🔴 THE TWO ARMS OVER ONE FILE NEED OPPOSITE STRIPPERS, and this rewrite is how they get
# both from one pass. `strip_noncode` blanks string literals, which is REQUIRED here:
# `ScenarioUnitAlignmentDebugPanel.gd:133` is a `push_warning` whose text contains
# `ProceduralMap.get_all_tiles()`, and it is the whole difference between the raw grep's
# 28 and ADR-0192's 27. But `has_method("get_tile")` carries its member name INSIDE a
# string literal, so the same blanking erases the probe form that ADR-0170 dec. 5 counts.
# Rewriting the probe to an identifier BEFORE the strip keeps it: a probe inside a real
# string literal loses its inner quotes to the rewrite, so the outer literal is still a
# clean `"[^"]*"` and is blanked as it should be.
_PROBE = re.compile(r'\.has_method\s*\(\s*["\'](\w+)["\']\s*\)')


def _code_lines(text: str):
    """Comment-, docstring- and literal-free lines, line count preserved."""
    return strip_noncode(_PROBE.sub(lambda m: ".has_method__%s()" % m.group(1), text))


# --- receiver-type inference ----------------------------------------------------------
_HEADER_OPEN = re.compile(r"^\s*(?:(?:static\s+)?func|signal)\s+\w+\s*\(")
_VAR_DECL = re.compile(
    r"^\s*(?:@onready\s+|@export\s+)*(?:static\s+)?(?:var|const)\s+(\w+)\s*(:\s*([\w\[\]., ]+?))?\s*(?:=|:=|$)")
_FUNC_HDR = re.compile(r"^\s*(?:static\s+)?func\s+\w+\s*\((.*?)\)\s*(?:->.*)?:")


def _joined_headers(lines):
    """(first_lineno, one-line header) for every `func` / `signal` header, wrapped or not.

    GDScript wraps long signatures across lines and this repo does it constantly —
    `CombatLoop.gd:313` and `:331` both declare a `TerrainIndex` parameter across two
    lines. A per-line declaration scan reads those as NO declaration, which puts a
    correctly-typed receiver on the register as `undeclared`: a guard that is red because
    it stopped looking. `check_lattice_doors.py` paid for this lesson on the door side
    (fourteen wrapped headers in the addon); this is the same fix on the receiver side."""
    out, i, n = [], 0, len(lines)
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


def _split_params(params: str):
    """Top-level commas only — `Array[Tile]` and `Dictionary[int, String]` do not split."""
    out, depth, cur = [], 0, []
    for ch in params:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            out.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    if "".join(cur).strip():
        out.append("".join(cur))
    return out


def declared_types(lines):
    """`name -> set of declared type annotations` for one file.

    `""` means DECLARED BUT UNANNOTATED (`var _map`, `var map := _get_map()`). A name
    absent from the dict is undeclared in this file. Both are "not provably `Lattice`";
    they are distinguished only so the report can say which."""
    types: dict[str, set[str]] = {}
    for ln in lines:
        m = _VAR_DECL.match(ln)
        if m:
            types.setdefault(m.group(1), set()).add((m.group(3) or "").strip())
    for _lineno, hdr in _joined_headers(lines):
        m = _FUNC_HDR.match(hdr)
        if not m:
            continue
        for param in _split_params(m.group(1)):
            p = param.split("=")[0].strip()
            if not p:
                continue
            name, _, ann = p.partition(":")
            name = name.strip()
            if re.fullmatch(r"\w+", name):
                types.setdefault(name, set()).add(ann.strip())
    return types


def name_verdict(name: str, types) -> tuple[bool, str]:
    """`(is_provably_Lattice, noun phrase)` for one NAME (ADR-0192 dec. 2).

    The phrase is a noun so both callers can compose it: arm 1's call scan says
    "receiver `x` is <phrase>" and its fetch scan says "lands in `x`, which is <phrase>"."""
    if "." in name:
        return False, "a chained expression that never binds a typed handle"
    if not re.fullmatch(r"[A-Za-z_]\w*", name):
        return False, "not a name"
    anns = types.get(name)
    if anns is None:
        return False, ("undeclared in this file (inherited, an autoload, or a "
                       "singleton — this guard does not resolve types across files)")
    if anns == {PORT_TYPE}:
        return True, "`%s`" % PORT_TYPE
    shown = ", ".join("unannotated" if a == "" else "`%s`" % a for a in sorted(anns))
    return False, "%s, not `%s`" % (shown, PORT_TYPE)


# --- the three spellings --------------------------------------------------------------
_CALL = re.compile(r"(?<![\w.])([A-Za-z_][\w.]*)\.(%s)\s*\(" % "|".join(PORT_METHODS))
_PROBE_CALL = re.compile(r"(?<![\w.])([A-Za-z_][\w.]*)\.has_method__(%s)\(\)"
                         % "|".join(PORT_METHODS))
_FETCH = re.compile(r"(?<![\w.])([A-Za-z_][\w.]*)\.(%s)\b" % "|".join(PORT_HANDLES))
_PRODUCER = re.compile(r"^\s*(?:static\s+)?func\s+(%s)\s*\(" % "|".join(PORT_METHODS))
# 🔴 AN OVERRIDE INSIDE `extends Lattice` IS NOT A MOCK PRODUCER, and reading it as one
# is the exact hole ADR-0170 dec. 5's ⚠️ warns about on the OTHER arm: "GDScript has no
# interfaces, so a mock must `extends Lattice` and override, or construct a real
# `Lattice` seeded with fabricated `TerrainCell`s. Arm 1 must be written so that BOTH
# routes pass; one phrased against subclassing forbids the cheaper one."
#
# The producer scan was written against the pre-port world, where the only thing a host
# file could do with `func get_tile` was BE a duck-typed map (dec. 5's seven). After the
# port the sanctioned repair is a subclass, and a scan blind to `extends` scores the
# repair as the defect — it went 10 -> 19 on the pass that fixed all seven, which is a
# guard whose green state its own ADR forbids. So a declaration is a producer only when
# it is NOT inside a class that extends the port.
_CLASS_HDR = re.compile(r"^(\s*)class\s+\w+\s+extends\s+(\w+)\s*:")
_FILE_EXTENDS = re.compile(r"^extends\s+(\w+)\s*$")
# What a fetch's result LANDS in, read backwards from the match (ADR-0192 dec. 3).
_LAND_VAR = re.compile(r"^\s*var\s+(\w+)\s*:\s*([\w\[\]]+)\s*=\s*$")
_LAND_VAR_BARE = re.compile(r"^\s*var\s+(\w+)\s*:?=\s*$")
_LAND_NAME = re.compile(r"^\s*(\w+)\s*=\s*$")


class Site:
    __slots__ = ("rel", "kind", "label", "lineno", "clean", "reason", "bucket")

    def __init__(self, rel, kind, label, lineno, clean, reason, bucket):
        self.rel, self.kind, self.label, self.lineno = rel, kind, label, lineno
        self.clean, self.reason, self.bucket = clean, reason, bucket

    @property
    def key(self):
        return (self.rel, self.label)


def _is_write(line: str, end: int) -> bool:
    """`combat_loop.terrain_index = x` STORES the handle; it is not a fetch of one."""
    tail = line[end:].lstrip()
    return tail.startswith("=") and not tail.startswith("==")


_STORE_ALIAS = re.compile(
    r"^\s*const\s+(\w+)\s*:?=\s*preload\(\s*[\"']res://" + re.escape(STORE_PATH) + r"[\"']\s*\)")


def store_aliases(raw_lines) -> set:
    """Local names this file gave the unpublished store via `const X = preload(...)`.

    The store has no `class_name` (ADR-0192 dec. 4), so inside the addon it is named by
    whatever each file called its preload — `TileStore` in `Lattice.gd`,
    `TerrainIndexStore` in `MapComposer.gd`. Arm 3's clean set is exactly these.

    🔴 READS THE RAW TEXT, NOT `_code_lines`. `strip_noncode` blanks string literals, so
    the `preload("res://…")` path — the only thing that identifies the store — is gone
    by the time the call scan sees the file. Every alias came back empty and arm 3
    reported the port's own four call sites as the defect. Same shape as the `has_method`
    probe two functions up: two arms over one file needing opposite strippers."""
    out = set()
    for ln in raw_lines:
        m = _STORE_ALIAS.match(ln)
        if m:
            out.add(m.group(1))
    return out


def sites_in(rel: str, text: str, in_addon: bool = False):
    """Every call / fetch / producer site in one `.gd` file.

    `in_addon` switches the LEGACY half of the verdict (arm 3): outside the addon a
    `get_tile` call is never clean, because the store is unnameable there; inside it,
    it is clean iff the receiver is annotated with this file's preload alias for the
    store, which is the only honest way to reach it."""
    lines = _code_lines(text)
    types = declared_types(lines)
    aliases = store_aliases(text.splitlines()) if in_addon else set()
    out = []

    for i, ln in enumerate(lines, 1):
        for pat, shape in ((_CALL, "call"), (_PROBE_CALL, "probe")):
            for m in pat.finditer(ln):
                recv, member = m.group(1), m.group(2)
                if in_addon and member in LEGACY_METHODS:
                    anns = types.get(recv)
                    clean = anns is not None and anns and anns <= aliases
                    phrase = ("the store" if clean else
                              _addon_phrase(recv, anns))
                    reason = "receiver `%s` is %s" % (recv, phrase)
                else:
                    clean, phrase = name_verdict(recv, types)
                    reason = "receiver `%s` is %s" % (recv, phrase)
                anns = types.get(recv) or set()
                bucket = "TerrainIndex" if anns == {"TerrainIndex"} else "other"
                label = "%s.%s()" % (recv, member)
                if shape == "probe":
                    label = '%s.has_method("%s")' % (recv, member)
                out.append(Site(rel, "call", label, i, clean, reason, bucket))

        for m in _FETCH.finditer(ln):
            if _is_write(ln, m.end()):
                continue
            recv, handle = m.group(1), m.group(2)
            before = ln[:m.start()]
            land = _LAND_VAR.match(before)
            if land:
                clean = land.group(2).strip() == PORT_TYPE
                reason = ("lands in `var %s: %s`" % (land.group(1), land.group(2))
                          if clean else
                          "lands in `var %s: %s`, not `%s`"
                          % (land.group(1), land.group(2), PORT_TYPE))
            elif _LAND_VAR_BARE.match(before):
                nm = _LAND_VAR_BARE.match(before).group(1)
                clean, reason = False, "lands in an unannotated `var %s`" % nm
            elif _LAND_NAME.match(before):
                nm = _LAND_NAME.match(before).group(1)
                clean, phrase = name_verdict(nm, types)
                reason = "lands in `%s`, which is %s" % (nm, phrase)
            else:
                clean, reason = False, "the result lands in no `%s`-annotated slot" % PORT_TYPE
            out.append(Site(rel, "fetch", "%s.%s" % (recv, handle), i, clean, reason,
                            "other"))

    subclass = _port_subclass_lines(lines)
    if in_addon:
        return out          # arm 3 scores calls and fetches only — see `_addon_phrase`
    for lineno, hdr in _joined_headers(lines):
        m = _PRODUCER.match(hdr)
        if m and lineno not in subclass:
            out.append(Site(rel, "producer", "func %s()" % m.group(1), lineno, False,
                            "a host file DECLARES a port member — a mock map "
                            "(ADR-0170 dec. 3's test seam)", "other"))
    return out


def _addon_phrase(recv: str, anns) -> str:
    """Why an ADDON-file legacy call is not clean.

    Arm 3 scores no producers: inside the addon a `func get_tile` declaration is the
    STORE defining itself, and a `func terrain_at` is the PORT defining itself. Both
    are the thing the other arms measure reaches to, not a reach."""
    if anns is None:
        return ("undeclared in this file, so it is not the store (inference is per file; "
                "this guard does not resolve types across files)")
    shown = ", ".join("unannotated" if a == "" else "`%s`" % a for a in sorted(anns))
    return ("%s — not the store. Inside the addon a legacy call is clean only on a "
            "receiver annotated with this file's `preload` alias for it" % shown)


def _port_subclass_lines(lines) -> set:
    """1-based line numbers that sit inside a class extending `Lattice`.

    Covers both spellings: a whole file (`extends Lattice` at column 0) and an inner
    `class X extends Lattice:` block, which ends at the first later line indented no
    further than the class header. Blank lines do not close a block."""
    covered = set()
    if any(_FILE_EXTENDS.match(ln) and _FILE_EXTENDS.match(ln).group(1) == PORT_TYPE
           for ln in lines):
        return set(range(1, len(lines) + 1))
    i, n = 0, len(lines)
    while i < n:
        m = _CLASS_HDR.match(lines[i])
        if not m or m.group(2) != PORT_TYPE:
            i += 1
            continue
        indent = len(m.group(1))
        j = i + 1
        while j < n:
            ln = lines[j]
            if ln.strip() and len(ln) - len(ln.lstrip()) <= indent:
                break
            covered.add(j + 1)
            j += 1
        i = j
    return covered


_CORPUS = None


def corpus(refresh: bool = False):
    """Every non-addon `.gd` file, read ONCE per run — `[(rel, text)]`.

    `refresh` is not optional convenience: the seed tests write a `.gd` into the real tree
    BETWEEN in-process `main()` calls, so a cache that outlived one call would make every
    seed after the first vacuous — a performance fix that silently disarms the arms it
    speeds up. `main()` refreshes on entry."""
    global _CORPUS
    if _CORPUS is not None and not refresh:
        return _CORPUS
    rows = []
    for root in SCAN_ROOTS:
        base = PROJECT_DIR / root
        if not base.is_dir():
            continue
        for q in sorted(base.rglob("*.gd")):
            rel = q.relative_to(PROJECT_DIR).as_posix()
            if rel.startswith(ADDON_ROOT):
                continue
            rows.append((rel, q.read_text(errors="ignore")))
    _CORPUS = rows
    return _CORPUS


_ANALYSIS = {}


def analyse(rel: str, text: str, in_addon: bool = False):
    """`sites_in(rel, text, in_addon)`, or `None` if the C-level reject fired.

    🔴 THE CACHE KEY CARRIES THE TEXT, WHICH IS WHY IT CANNOT GO STALE — and that is the
    whole difference between this and the memo `corpus`'s docstring, one function up,
    forbids. `corpus(refresh=True)` re-reads the tree on every `main()`, so the seed
    tests' file is always FRESH here; what repeats is the ANALYSIS of the 1,389 files the
    seed did not touch. Keying on `(rel, in_addon)` alone would answer for
    `src/_PortSeed.gd` out of the previous seed's body and make every seed after the
    first vacuous. Keying on the text means a changed body is a MISS by construction: no
    invalidation call to forget, no mtime to trust. `==` over the whole corpus costs
    0.002 s (length check, then `memcmp`); the reject sweep and `sites_in` it replaces
    cost 0.118 s of each 0.166 s `main()`, and `main()` runs 25 times in one
    `test_check_lattice_ports` process.

    The reject verdict is cached WITH the sites rather than beside them, because
    "matched nothing" is an analysis result like any other and re-deriving it is the
    larger half of the bill: 8 substring searches over 16.2 MB, 1,389 files, 75 of which
    can match at all.

    ⚠️ Sound only while `sites_in` is a pure function of `(rel, text, in_addon)`. It reads
    the port's name sets and the receiver-type regexes, none of which any caller mutates
    — `_run()` in the seed tests rebinds `PORT_BURN_DOWN`, which is reporting, not
    scanning. Give `sites_in` a dependency on mutable module state and this memo answers
    out of the old one.

    NO NEW TEST GUARDS THIS, because twenty-five already do. Each seed writes a DIFFERENT
    body to the same `src/_PortSeed.gd`, which is exactly the invalidation this key has to
    get right: dropping the `hit[0] == text` half and keying on the path alone was
    measured RED on 12 of the 25. The failure a test could NOT catch is the opposite one
    — a change that makes every lookup MISS is silent, because a memo that never hits is
    slow, not wrong. `tools/rank_preflight.py` is what would show it."""
    key = (rel, in_addon)
    hit = _ANALYSIS.get(key)
    if hit is not None and hit[0] == text:
        return hit[1]
    sites = (sites_in(rel, text, in_addon)
             if any(n in text for n in PORT_METHODS + PORT_HANDLES) else None)
    _ANALYSIS[key] = (text, sites)
    return sites


def scan():
    """`(arm1, arm2, arm3)` — every UNCLEAN site, split by root."""
    arm1, arm2, arm3 = [], [], []
    for rel, text in corpus():
        sites = analyse(rel, text)
        if sites is None:
            continue                       # C-level reject; most files match nothing
        for s in sites:
            if s.clean:
                continue
            (arm2 if rel.startswith(TESTS_ROOT) else arm1).append(s)
    for rel, text in addon_corpus():
        for s in analyse(rel, text, in_addon=True) or ():
            if not s.clean:
                arm3.append(s)
    return arm1, arm2, arm3


_ADDON_CORPUS = None


def addon_corpus(refresh: bool = False):
    """Every `.gd` INSIDE the addon except the store itself — `[(rel, text)]`.

    🔴 ARM 3 EXISTS BECAUSE THE ADDON WAS THE ONE PLACE NOTHING SCANNED, AND IT PAID.
    Arms 1 and 2 exclude `addons/exmateria_battlefield/` on purpose: the addon OWNS the
    store, so `_store.get_tile(x, z)` in `Lattice.gd` is the port doing its job, not a
    duck-typed reach. But `PlayerCamera.gd` reached its map the same way every host file
    did — `procedural_map.get_all_tiles()` behind a `has_method` probe — and when
    ADR-0170 dec. 1 deleted that forwarder off `MapComposer` the probe did not error. It
    started answering "no tiles" FOREVER, which centres the battle camera on the world
    origin. A silent wrong answer, found by grep, in the one region every register was
    blind to.

    The rule is decidable without a `class_name`: a LEGACY call (`get_tile` /
    `get_all_tiles`) is clean iff its receiver is annotated with THIS file's `const X =
    preload(...TerrainIndex.gd)` alias, and a FUTURE call is clean iff its receiver is
    `Lattice` — the same allowlist arm 1 uses, because inside the addon a consumer of the
    port is still a consumer of the port. `TerrainIndex.gd` itself is excluded: it is the
    store, and its own `func get_tile` is the definition, not a reach."""
    global _ADDON_CORPUS
    if _ADDON_CORPUS is not None and not refresh:
        return _ADDON_CORPUS
    rows = []
    base = PROJECT_DIR / ADDON_ROOT
    if base.is_dir():
        for q in sorted(base.rglob("*.gd")):
            rel = q.relative_to(PROJECT_DIR).as_posix()
            if rel == STORE_PATH:
                continue
            text = q.read_text(errors="ignore")
            if any(n in text for n in PORT_METHODS + PORT_HANDLES):
                rows.append((rel, text))
    _ADDON_CORPUS = rows
    return _ADDON_CORPUS


# --- reporting ------------------------------------------------------------------------
def _rows(sites):
    """Sites collapsed onto burn-down keys, in file order."""
    rows = {}
    for s in sites:
        rows.setdefault(s.key, []).append(s)
    return sorted(rows.items(), key=lambda kv: (kv[0][0], kv[1][0].lineno))


def _split(sites):
    """ADR-0170 dec. 5's 13-and-7 and ADR-0192 dec. 2's 15-and-12, kept checkable.

    The producer count is reported as DECLARATIONS **and** FILES because the two
    predictions are about different units: dec. 5 measured 7 (files), and dec. 6 predicts
    ">=4 of the 7 are deleted rather than ported" — also files. Seven files declare ten
    members here, and a single number would silently answer the wrong question."""
    calls = [s for s in sites if s.kind == "call"]
    prods = [s for s in sites if s.kind == "producer"]
    return (len(calls),
            sum(1 for s in calls if s.bucket == "TerrainIndex"),
            len([s for s in sites if s.kind == "fetch"]),
            len(prods), len({s.rel for s in prods}))


def _print_split(name, sites):
    n_call, n_ti, n_fetch, n_prod, n_prod_files = _split(sites)
    print("%s: %d site(s) — %d call(s) (%d untyped-or-wrong + %d `TerrainIndex`-typed), "
          "%d handle fetch(es), %d mock producer declaration(s) in %d file(s)."
          % (name, len(sites), n_call, n_call - n_ti, n_ti, n_fetch, n_prod,
             n_prod_files))


def _report(arm, sites, owner_hint):
    """One arm. Returns `(unlisted, stale)`; prints listed rows above the verdict."""
    rows = _rows(sites)
    listed = {k for k, _ in rows}
    unlisted = [(k, v) for k, v in rows if k not in PORT_BURN_DOWN]
    burned = [(k, v) for k, v in rows if k in PORT_BURN_DOWN]
    stale = sorted(k for k in PORT_BURN_DOWN
                   if k not in listed and PORT_BURN_DOWN[k][2] == arm)

    if burned:
        print("\n%s — %d row(s) / %d site(s) reach the lattice through a receiver that is\n"
              "NOT provably `%s`, each NAMED in PORT_BURN_DOWN with an owner. Not a pass:\n"
              "this is ADR-0164 dec. 4 criterion 2 unmet, on record, target 0."
              % (arm.upper(), len(burned), sum(len(v) for _, v in burned), PORT_TYPE))
        for key, group in burned:
            owner, why, _arm = PORT_BURN_DOWN[key]
            head = group[0]
            at = ", ".join(str(s.lineno) for s in group[:6])
            print("  %s:%s  %s  (%s x%d)\n      %s\n      %s — %s"
                  % (head.rel, at, head.label, head.kind, len(group), head.reason,
                     owner, why))

    if unlisted:
        print("\n%s: %d row(s) / %d site(s) reach the lattice and are NOT ON PORT_BURN_DOWN\n"
              "(ADR-0164 dec. 4 criterion 2, ADR-0192 dec. 2/3).\n"
              % (arm.upper(), len(unlisted), sum(len(v) for _, v in unlisted)))
        for key, group in unlisted:
            head = group[0]
            at = ", ".join(str(s.lineno) for s in group[:6])
            print("  %s:%s  %s  (%s x%d) — %s"
                  % (head.rel, at, head.label, head.kind, len(group), head.reason))
        print("\n%s" % owner_hint)

    if stale:
        print("\nSTALE PORT_BURN_DOWN (%s) — %d row(s) name a site that no longer exists,\n"
              "or one whose receiver is now `%s`. Delete the row; a burn-down that outlives\n"
              "its debt is a list nobody rereads. ⚠️ A row going stale is what SUCCESS looks\n"
              "like here — check the port before you call it a regression.\n"
              % (arm, len(stale), PORT_TYPE))
        for rel, label in stale:
            owner, _why, _arm = PORT_BURN_DOWN[(rel, label)]
            print("  %s  %s   [%s]" % (rel, label, owner))

    return unlisted, stale


def main() -> int:
    corpus(refresh=True)   # see `corpus`: a stale cache disarms the seed tests
    addon_corpus(refresh=True)
    arm1, arm2, arm3 = scan()

    print("subject: every `.gd` under %s except `%s` — %d file(s). Clean IFF the receiver\n"
          "is annotated `%s` (ADR-0192 dec. 2); a handle fetch is clean IFF its result\n"
          "lands in a `%s`-annotated slot (dec. 3). Method names scanned: %s."
          % ("/".join(SCAN_ROOTS), ADDON_ROOT, len(corpus()), PORT_TYPE, PORT_TYPE,
             ", ".join(sorted(PORT_METHODS))))
    _print_split("arm 1 (src/ and non-battlefield addons/assets)", arm1)
    _print_split("arm 2 (tests/)", arm2)
    _print_split("arm 3 (inside the addon)", arm3)

    u1, s1 = _report(
        "arm 1", arm1,
        "Answer with the port: annotate the receiver `%s` and call `terrain_at` /\n"
        "`all_cells` / `world_position_at` / `is_cliff_edge`, or land the handle in\n"
        "`var lattice: %s = map.lattice`. Or add the row with its owner and the ticket\n"
        "that closes it." % (PORT_TYPE, PORT_TYPE))
    u2, s2 = _report(
        "arm 2", arm2,
        "⚠️ arm 2 is ENFORCING (ADR-0192 dec. 7, ruled by amendment 1) — a named list, not\n"
        "a threshold, so `classify()` returning `None` for `tests/` does not reach it. A\n"
        "test reaching the lattice duck-typed is still a host reaching it duck-typed, and\n"
        "arm 1 hitting zero while `tests/` still holds 30 sites is exactly the \"reads as\n"
        "coverage\" failure ADR-0170 dec. 5 named and could not fix.")

    u3, s3 = _report(
        "arm 3", arm3,
        "Inside the addon a LEGACY call is clean only on the store — annotate the\n"
        "receiver with this file's `const X = preload(\".../TerrainIndex.gd\")` alias — and\n"
        "a FUTURE call is clean only on a `%s`. A map handle reached by NodePath infers\n"
        "`Node` here exactly as it does in a host file, and a `has_method` probe over a\n"
        "member that no longer exists answers \"nothing\" rather than failing." % PORT_TYPE)

    if "--list" in sys.argv:
        print("\nPORT_BURN_DOWN rows:")
        for (rel, label), (owner, why, arm) in sorted(PORT_BURN_DOWN.items()):
            print("  [%s] %s  %s   [%s]\n      %s" % (arm, rel, label, owner, why))

    if "--emit-burndown" in sys.argv:
        print("\n# --- generated: paste into PORT_BURN_DOWN ---")
        for arm, sites in (("arm 1", arm1), ("arm 2", arm2), ("arm 3", arm3)):
            for key, group in _rows(sites):
                print('    (%r, %r):\n        ("", %r,\n         %r),'
                      % (key[0], key[1], group[0].reason, arm))

    if u1 or u2 or u3 or s1 or s2 or s3:
        return 1

    total = len(arm1) + len(arm2) + len(arm3)
    if total:
        print("\nDuck-typed-door register: %d site(s) of a target 0, every one on\n"
              "PORT_BURN_DOWN with an owner and no listed row stale. ADR-0192 dec. 1: this\n"
              "guard exists BEFORE the port because the port consumes its whole population,\n"
              "and a register written afterwards reads zero whether it works or not."
              % total)
    else:
        print("\nDUCK-TYPED-DOOR REGISTER CLEAR — every reach into the battlefield lattice\n"
              "goes through a receiver annotated `%s` (ADR-0164 dec. 4 criterion 2)."
              % PORT_TYPE)
    return 0


if __name__ == "__main__":
    sys.exit(main())
