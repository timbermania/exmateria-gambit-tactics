#!/usr/bin/env python3
"""Guard: the published-symbol register — ADR-0164 dec. 4 criterion 1, built by ADR-0196.

    uv run python tools/check_lattice_publish.py [--list]

THE RULE (ADR-0196 dec. 4, amending ADR-0164 dec. 4 criterion 1 in place). No FORBIDDEN
`Battlefield` `class_name` may be named as a TYPE by another system's source. Target 0.
The six are `Tile`, `TerrainIndex`, `MapComposer`, `TileCursor`, `CursorController` and
`PlayerCamera`, and they burn down by NAME (#424 — an exclusion expressed as a filter
manufactures its own debt and cannot tell a triaged site from one that merely matches).

WHY THE CRITERION HAD TO BE AMENDED BEFORE IT COULD BE BUILT. As ADR-0164 wrote it,
criterion 1 demanded that the set of `Battlefield` `class_name`s named outside the addon
**equal** the declared published set, "difference computed both ways". That is
unpassable and always was: of the addon's 30 `class_name`s, **20 are named as a type by
nothing in `src/`** (13 by nothing in `src/` OR `tests/`) — `Doodad`, `SceneTreeManager`,
`VisualGeometryIndex`, `MapLightingConfig` and the rest — whose only defect is that no
host happens to want them yet. Worse, set equality makes DELETING a host call site red
the guard. So dec. 4 splits the criterion:

  ENFORCED   no forbidden name is named as a type outside the addon. Arm 1, burn-down.
  REPORTED   the declared published set should be a SUPERSET of the named set. Printed
             both ways, scoring nothing. See `DECLARED_PUBLISHED`.

WHY THIS GUARD IS BUILT BEFORE THE ENUM MOVES (ADR-0196 dec. 1, applying ADR-0192
dec. 1's ruling to the third criterion). Criterion 1's baseline is MORE erasable than
criterion 2's was: after `Tile.HighlightType` becomes `CellMarking.Kind`, all ten of
`Tile`'s host lines are gone, so a scanner that merely fails to RECOGNISE
`Tile.HighlightType` is indistinguishable from a correct one. `PUBLISH_BURN_DOWN` is the
frozen population, and the enum move is graded by watching `Tile`'s two rows go STALE.

A TYPE REFERENCE, AND WHY A NODE PATH IS NOT ONE (ADR-0196 dec. 2). `$PlayerCamera`,
`get_node_or_null("PlayerCamera")` and a `.tscn` instancing `PlayerCamera.tscn` are
couplings to a SCENE TREE, not to a compiled symbol. Criterion 1 exists so the addon's
COMPILED surface is narrow — a symbol you cannot name as a type cannot be compiled
against — and folding scene coupling in would make one number answer two questions,
which is ADR-0131 dec. 7's own named failure. The consequence is stated rather than
hidden: this register reads **0** for `PlayerCamera` and `MapComposer` while host files
name them BY PATH. 🔴 ADR-0205 corrects what that population is: it was called the
INSTALL term here and in ADR-0196 dec. 8, and the direction is wrong — a HOST file naming
`res://addons/exmateria_battlefield/…` is host → addon, which is THIS axis, not axis B.
It is now criterion 4 and `check_lattice_scene.py` scores it. This register still does
not, deliberately: different subject, different instrument, different file types.

🔴 THE EXCLUSION IS ON THE OCCURRENCE, NEVER ON THE LINE, and getting that backwards is
the defect ADR-0196's own hand count had. Its reading (a) put `TileCursor` at **9**; the
tree holds **12**. The three it missed are `EffectViewerScene.gd:27`,
`FireCastReproScene.gd:45` and `GPUArena.gd:41` — each an
`@onready var tile_cursor: TileCursor = $TileCursor` (or the `get_node_or_null(...)`
spelling), a real type ANNOTATION sharing its line with a node path. Dropping the line
drops a compiled-symbol reference, which is the whole subject of the criterion.
`test_an_annotation_SHARING_its_line_with_a_node_path_still_counts_once` pins it.

WHAT THIS GUARD CANNOT SEE, stated because every blind spot on this map has scored zero
and every one has been real:

  - **`.tscn` and `.tres`.** Deliberate, per dec. 2. Scored since ADR-0205 by
    `check_lattice_scene.py` as criterion 4 — 138 sites over 132 files. Run both.
  - **A reach through `load()` / `preload()` by path.** `preload("res://addons/…/Tile.gd")`
    names the file, not the `class_name`, and `strip_noncode` blanks the literal before
    the scan sees it. The reach is real and this criterion does not score it; the doors
    and ports registers cover the call and hand-out shapes.
  - **A symbol reached through inheritance.** A host `extends` an addon class and uses an
    inherited member unqualified; nothing in the host file names the symbol.
  - **The addon's own files.** By construction — `class_name` self-reference inside
    `addons/exmateria_battlefield/` is not a cross-system reach.
  - **A single-quoted node path.** `strip_noncode` blanks `"…"` but not `'…'`, so
    `get_node_or_null('PlayerCamera')` would score. Measured at build time: **zero**
    single-quoted occurrences of any of the six anywhere outside the addon. The
    lookbehind excludes a leading `'` for the same reason it excludes `"`, which covers
    the one-line case.

  ✅ **One entry left this list by being fixed instead.** A `#` inside a string literal
  truncated the line and dropped the code after it — one live site, `TileCursor` reading
  12 instead of 13. Auditing this list is what found it; see `_code_lines`. The lesson is
  the list's own: a blind spot written down and not measured is a blind spot that stays.

ARMS.

  arm 1  ENFORCING, burn-down, both directions. `src/`, `tools/` and any
         non-battlefield `addons/` or `assets/` file. Rows on `PUBLISH_BURN_DOWN` print above the OK
         line under a heading that says it is not a pass; an UNLISTED namer fails, and a
         LISTED row whose file no longer names the symbol as a type fails as STALE.

  arm 2  REPORTING, no target (ADR-0196 dec. 3, on ADR-0170 dec. 5's precedent).
         `classify()` returns `None` for every file under `tests/`, so a threshold there
         is guesswork. But arm 1 reaching zero while three cursor fixtures hold 24 lines
         of `Array[Tile]` / `Tile.new()` reads as COVERAGE, so the sites print without a
         target.

  arm 3  ENFORCING, burn-down, both directions, keyed on the NAME. An addon
         `class_name` named as a TYPE from anywhere outside the addon while
         `DECLARED_PUBLISHED` does not name it. ADR-0208 dec. 2's second half — a
         criterion-4 path row may be paid by naming a PUBLISHED name and never by
         re-spelling an unpublished one — which was ruled with no instrument until
         #713. Scans the WHOLE corpus including `tests/`, unlike arms 1 and 2, because
         criterion 4 has rows in `tests/` and a payment made there must be scored
         there. See `UNDECLARED_BURN_DOWN`.

  the declared-set report  REPORTING, dec. 4's second half. Never changes the rc.
"""
import pathlib
import re
import sys

PROJECT_DIR = pathlib.Path(__file__).resolve().parent.parent
_REL_FROM = len(PROJECT_DIR.as_posix()) + 1     # see `corpus`
ADDON_ROOT = "addons/exmateria_battlefield/"

# ADR-0164 dec. 4 criterion 1's six, verbatim.
# 🔴 FOUR OF THE SIX NO LONGER HAVE A `class_name` AT ALL, AND THEY STAY ON THIS LIST.
# `TerrainIndex` lost its `class_name` to ADR-0192 dec. 4; `TileCursor` and
# `CursorController` lost theirs to ADR-0206. A name that does not exist cannot be
# matched, so those entries score 0 by construction — which is exactly why they remain:
# re-adding `class_name TileCursor` would make every host reach nameable again, and this
# list is what turns that back into a red instead of a silent regression. Removing an
# entry because it now reads 0 would retire the guard on the day it started working.
FORBIDDEN = ("Tile", "TerrainIndex", "MapComposer", "TileCursor", "CursorController",
             "PlayerCamera")

# 🔴 `tools/` IS IN, AND NEITHER SIBLING REGISTER SCANS IT. `check_lattice_doors.py`
# and `check_lattice_ports.py` both stop at `src` / `tests` / `assets` / `addons`, each
# on a measurement of ITS OWN subject (a door's namers, a port's receivers). This
# criterion's subject is different — any file that can name a `class_name` — and
# `tools/` holds **94 `.gd` files**, the capture and debug scenes, which are host code
# by every test that matters. Measured at build time: **0** type references to the six
# there today. That is why it costs nothing to include and exactly why it is included —
# an empty root left unscanned is a place the register can be satisfied by writing the
# reach somewhere it does not look.
SCAN_ROOTS = ("src", "tests", "assets", "addons", "tools")
TESTS_ROOT = "tests/"

# --- the declared published set (ADR-0196 dec. 4) -------------------------------------
# A LITERAL HERE, BESIDE THE BURN-DOWN — the `DOOR_BURN_DOWN` / `ARM1_BURN_DOWN`
# precedent — and deliberately NOT parsed out of the addon README.
#
# 🔴 A SOURCE ASSERTION THAT MATCHES ITS OWN PROSE STAYS GREEN THROUGH THE DELETION OF
# THE LINE IT GUARDS. The README's statement of this set is "30 `class_name`s and two
# scenes", a line whose own ⚠️ admits it "read 28 and was already stale by one before
# loop pass 6 measured it at 29". A guard that read that sentence would inherit its
# staleness and call it agreement.
#
# ELEVEN, not thirty. The README counts what the addon DECLARES; this is what it means to
# PUBLISH — the port, its configuration, and the overlay/pathfinding/generation surface a
# host is invited to name. `test_every_declared_name_is_a_real_addon_class_name` and
# `test_every_declared_name_states_a_host_use` keep the literal honest in the two
# directions a literal can rot silently: a name the addon no longer declares, and a name
# nobody can say why we declared.
#
# 🔴 THIS COUNT WAS ITSELF STALE. It read NINE beside a ten-name tuple until ADR-0208 —
# the same defect the ⚠️ above catches the README in, one screen lower and unnoticed,
# which is why dec. 6 makes the per-entry comment a STRUCTURAL requirement rather than
# a habit. A number in prose beside a list is a second copy of the list.
DECLARED_PUBLISHED = (
    # 🔴 EVERY ENTRY CARRIES ITS HOST USE, and `test_every_declared_name_states_a_host_use`
    # requires the comment STRUCTURALLY (ADR-0208 dec. 6). This list is what makes a published
    # name a legitimate payment for a criterion-4 path row (dec. 2), which makes ADDING to it
    # the same hole one level up — a row could be drained by declaring its target. The gate is
    # that a name joins only in a pass that STATES the host use it serves, and never in the
    # commit that closes the row. An entry whose comment says nothing is a name nobody reread.
    #
    # 🔴 THIS LIST WAS ELEVEN NAMES AND IT IS NOW ONE — ADR-0211 dec. 2. The addon declares
    # exactly one `class_name`; the other twenty-nine were DELETED, and the fourteen the host
    # actually reaches are re-published as constants on the façade. The eleven that used to
    # sit here (`Lattice`, `CursorRig`, `TileHighlights`, `TileOverlayConfig`, `SkirtConfig`,
    # `MapGridOverlay`, `MapIlluminationDDA`, `EventPathfinder`, `MapConstants`,
    # `TileCursorCompositor`, `PaletteTextureGenerator`) are all still reachable and every
    # host spelling of them is unchanged — a host-side `const Lattice = ExMateriaBattlefield
    # .Lattice` keeps the annotation, the `is`, and the `.new()`. What changed is the CHANNEL,
    # so keeping them here would be rot: `addon_class_names()` no longer returns any of them,
    # and this list would name eleven symbols that do not exist.
    #
    # 🔴 THE SUCCESSOR INSTRUMENT IS `check_addon_globals.py` arm 2, not this list. It reads
    # every `const X = preload(...)` on the façade and fails if the file is missing or sits
    # outside `addons/` — the same question ("what does the addon publish, and is it real?")
    # asked on the channel the answer now lives on. Run both; neither reports the other.
    #
    # ⚠️ NOT AN ADR-0208 dec. 6 VIOLATION, stated because the shape looks like one. Dec. 6
    # forbids a name joining in the commit that CLOSES the criterion-4 row it drains. This
    # commit closes no criterion-4 row: `check_lattice_scene` reads 0 before and after, and
    # the three arm-3 rows below went stale because their `class_name`s stopped existing,
    # which is the opposite direction from being declared out of debt.
    #
    # Host use: `src/gpu/CombatHost.gd` holds `const Lattice = ExMateriaBattlefield.Lattice`
    # at the combat seam — the terrain query surface the GPU pipeline compiles against, 50
    # references over 22 `src/` files (ADR-0210 dec. 1), all of them now routed through this
    # one name. `src/debug/CursorDebugPanel.gd` reaches the cursor port the same way.
    "ExMateriaBattlefield",
)

# --- arm 3's burn-down: NAMED BUT NOT DECLARED (ADR-0208 dec. 2, built by #713) -------
# `class_name -> (owner, why)`. A NAMED LIST, never a filter (#424 — an exclusion
# expressed as a filter manufactures its own debt and cannot tell a triaged site from
# one that merely matches).
#
# WHY THIS ARM EXISTS. ADR-0208 dec. 2 rules that a criterion-4 path row is paid by
# deleting the dependency, by host-owned indirection, or by naming a name the addon
# PUBLISHES — never by re-spelling an unpublished one. NOTHING ENFORCED THE SECOND HALF.
# Arm 1 scores the six `FORBIDDEN` names and only three of those six are still
# `class_name`s, so **27 of the addon's 30 scored under no enforcing arm anywhere**, 16
# of them named by nothing at all. Each of those 16 was a criterion-4 row payable
# tomorrow by writing the bare name with all five registers staying green — the exact
# move dec. 2 forbids, and not hypothetical: ADR-0208 records two host sites
# (`src/debug/ScenarioUnitAlignmentDebugPanel.gd`, `tests/MapPaletteFieldObjectTest.gd`)
# that arrived that way before the rule existed.
#
# 🔴 THE KEY IS THE NAME, NOT THE SITE, which is the one place this list differs in
# shape from `PUBLISH_BURN_DOWN` below. Arm 1's subject is a COUNT of couplings, so its
# key is `(file, symbol)`. Arm 3's subject is REACHABILITY — whether a host may compile
# against a symbol the addon never invited it to name — and one namer is the whole
# defect. A per-site key would manufacture a row every time a second test touched an
# already-reachable name, and close rows by re-numbering lines. Every site still PRINTS.
#
# 🔴 ADR-0196 dec. 4 DOES NOT BLOCK THIS, and reading it as if it did is why the arm was
# missing for three passes. Dec. 4 made the declared-set report REPORTING because "a
# declared-but-unnamed name is NOT a defect, and enforcing that direction would make
# deleting a host call site red this guard, which is backwards" — that is the OPPOSITE
# direction. Named-but-undeclared carries no such inversion: deleting a host call site
# DRAINS an arm-3 row instead of creating one.
#
# 🔴 A ROW ALSO CLOSES BY THE NAME BEING DECLARED, which is the same hole one level up.
# It is gated one level up and deliberately not re-litigated here: ADR-0208 dec. 6 makes
# the per-entry host-use comment on `DECLARED_PUBLISHED` structural and forbids a name
# joining in the commit that closes the row it drains. A second copy of that rule, in a
# place nobody would look for it, is how the two would drift.
#
# ✅ ALL FIVE ROWS ARE UNDER `tests/`, MEASURED — arm 1 reads 0 and `src/`, `tools/`,
# `assets/` and the sibling `addons/` name none of the five. That is stated rather than
# assumed because it is the reason arm 3 scans the WHOLE corpus and not `src/`: a
# criterion-4 path row in `tests/` (`tests/CursorTunablesTest.gd`,
# `tests/TileCursorIntegrationTest.gd` and four more today) would otherwise be payable
# by re-spelling it as a bare name in the same file, and arm 3 would not look.
UNDECLARED_BURN_DOWN = {
    # ✅ EMPTY, AND EMPTIED BY A CHANNEL CHANGE RATHER THAN BY THE MOVES IT WAITED ON.
    # ADR-0211 dec. 2 deleted twenty-nine of the addon's thirty `class_name`s, so the
    # three rows that stood here — `Tile` (#560), `MapTextureAnimator` (#716) and
    # `DynamicGeometryBuilder` (#560) — name symbols that no longer exist. A host cannot
    # compile against a global the engine never registered, so the reachability this arm
    # scores is structurally zero for every internal, not merely unobserved.
    #
    # 🔴 THE UNDERLYING PROBLEM IS NOT PAID, only made inexpressible here. All three rows
    # were one defect (ADR-0210 dec. 5): the addon exposes typed members whose types it
    # does not publish, and no host-side rewrite reaches them — `MapComposer
    # .dynamic_geo_builder` is TYPED, so a duck-typed stand-in throws on assignment, and
    # the fixtures that build a fake lattice out of `Tile` cannot fake it. Under the
    # façade those three types ARE published (`ExMateriaBattlefield.Tile`,
    # `.MapTextureAnimator`, `.DynamicGeometryBuilder` — ADR-0211 dec. 2 names them as
    # the three arm-3 rows this branch paid), so the host reaches them legitimately and
    # the interface question #716 asks is answered by publication rather than by a move.
    # That is a real close, and it is the only one of the three mechanisms ADR-0208 dec. 2
    # allows that was ever available to these rows.
    #
    # 🔴 EMPTY IS A MEASUREMENT, NOT A FINISHED JOB. The arm STAYS. Its subject —
    # a host naming an addon `class_name` the addon never declared — becomes live again
    # the moment anyone re-adds a `class_name` inside the addon, and this arm is the one
    # that scores whether a HOST then names it. `check_addon_globals.py` arm 1 fails on
    # the re-add itself; the two are different questions and the overlap is deliberate.
}


# --- arm 1's burn-down (ADR-0196 dec. 1) ---------------------------------------------
# `(rel, symbol) -> (owner, why)`. A NAMED LIST, never a pattern.
#
# THE KEY CARRIES NO LINE NUMBER, deliberately, for `PORT_BURN_DOWN`'s stated reason: a
# key that moved when a line moved would produce a stale row AND an unlisted row for the
# same site on every unrelated edit above it. Several SITES collapse onto one ROW; the
# report prints both counts and every line number.
#
# 🔴 THIS IS THE HAND COUNT, CORRECTED, AND IT IS THE ONLY EVIDENCE THE SCANNER IS
# RIGHT. It reads **31 sites over 14 rows** on `ee261694d`. ADR-0196's reading (a)
# predicted 27 — `Tile` 10, `TileCursor` 9, `CursorController` 8 — and `Tile` and
# `CursorController` reproduce exactly, site for site. `TileCursor` is **12**: the hand
# count dropped three `@onready var tile_cursor: TileCursor = $TileCursor` lines because
# the annotation shares its line with a node path, and a FOURTH — `CursorDebugPanel.gd:85`
# — was dropped by this scanner's own first draft, which is what `_code_lines` repairs.
# `TileCursor` is **13**. Each of the four was re-read individually before this number was
# written down. See the 🔴 in the module docstring.
#
# ✅ IT READS **21 OVER 12** TODAY. `Tile`'s ten sites closed in the second commit of the
# same pass (ADR-0196 dec. 6). What is left is `TileCursor` 12 and `CursorController` 8,
# deferred by dec. 8 to a NAMED pass — the one that closes criterion 1 — because both are
# construction seams and not re-spellings. Under dec. 5 a deferral that names an owner but
# no pass is a decision nobody ever has to make; ADR-0193 dec. 2 named one and two passes
# cited it and moved on.
PUBLISH_BURN_DOWN = {

}


# 🔴 `strip_noncode` IS LIFTED BY SOURCE SLICE, NOT IMPORTED, and the difference is 73
# SECONDS. `touch_matrix.py` runs its whole cross-system walk at import; exec'ing it to
# reach one pure function cost `check_lattice_doors.py` 73s of its 85s, and the tax
# multiplies because `tests/run_all_tests.sh` pre-flight is re-entered as a subprocess by
# `test_run_tests_parallel` and this guard's own seed tests each call `main()`. Slicing
# rather than copying is `residue.py`'s idiom, for its stated reason: the two programs
# cannot drift apart about what a reference is. The `sys.exit` is deliberate — a silent
# fallback to a private copy is how they WOULD drift.
_tmsrc = (PROJECT_DIR / "tools" / "touch_matrix.py").read_text()
_fnsrc = re.search(r'^def strip_noncode\(.*?(?=^\S)', _tmsrc, re.S | re.M)
if not _fnsrc:
    sys.exit("tools/touch_matrix.py no longer defines strip_noncode at top level")
_fn = {"re": re}
exec(_fnsrc.group(0), _fn)
strip_noncode = _fn["strip_noncode"]

# 🔴 A `#` INSIDE A STRING LITERAL TRUNCATES THE LINE, AND THE CODE AFTER IT IS LOST.
# `strip_noncode` strips comments BEFORE it blanks literals, so `re.sub(r'#.*$', '', s)`
# fires on a `#` that is not a comment at all. `src/debug/CursorDebugPanel.gd:85` is the
# live instance:
#
#     print("# outline blend mode (cursor.blend_mode): %s" % TileCursor.SEMI_MODE_LABELS[bm])
#
# — a real static read of `TileCursor`, dropped because the format string starts with `#`.
# The register read `TileCursor` at 12 with this hole and reads **13** without it. Found by
# auditing this module's own "what this guard cannot see" list rather than by a failing
# test, which is the only reason it is not still in the count.
#
# Rewriting the hazard BEFORE the strip is `check_lattice_ports._PROBE`'s idiom, for its
# stated reason: two arms over one file can need opposite strippers, and the fix belongs to
# the arm that needs it. Fixing `touch_matrix.strip_noncode` itself would move every number
# `residue.py`, `touch_matrix.py` and both sibling registers report — a repo-wide
# re-measurement, and not this pass's to make. The sentinel is a character no GDScript
# source contains; `strip_noncode` blanks the whole literal a moment later regardless, so a
# `#` that really was inside a string still contributes nothing.
_HASH_IN_LITERAL = re.compile(r'"[^"\n]*"')


def _code_lines(text: str):
    """Comment-, docstring- and literal-free lines, line count preserved.

    Identical to `strip_noncode` except that a `#` inside a double-quoted literal can no
    longer eat the code after the closing quote. See the 🔴 above.

    🔴 STRIPPING CANNOT INVENT A NAME, and that is the whole licence for the
    `any(n in text ...)` C-level reject in `named_types` and `named_sites`. Every
    transform on the way here returns a PREFIX of its line (the comment cut, the opening
    docstring cut), a SUFFIX of it (the closing docstring cut), the empty line, or a
    same-length substitution (`#` to the sentinel). The literal blank KEEPS BOTH QUOTES
    — it rewrites a quoted run to an empty quoted run rather than deleting it — so
    `Ti"x"le` becomes `Ti""le` and never `Tile`, which is the one way a deletion could
    have joined two halves of a name that was not there. The only characters stripping
    introduces are the quote and the sentinel, and a `class_name` is word characters. So
    a name absent from the RAW text is absent from every stripped line, and a file the
    reject drops could not have scored.

    Checked, not merely argued: over the whole 1,492-file corpus and all seven names
    (the six FORBIDDEN plus the addon's one `class_name`), the number of files where a
    stripped line names something the raw text does not is 0. A reject becomes a blind
    spot the day that stops holding, and this list's own lesson is that an unmeasured
    blind spot stays."""
    return strip_noncode(
        _HASH_IN_LITERAL.sub(lambda m: m.group(0).replace("#", "\x01"), text))


def _type_ref(name: str):
    """`name` used as a TYPE — not `$name`, not `%name`, not `x.name`, not `"name"`.

    The lookbehind is the whole of ADR-0196 dec. 2, and it excludes an OCCURRENCE. A
    `@onready var c: TileCursor = $TileCursor` therefore scores exactly once: the
    annotation counts, the node path does not. `\\b` on the right is what keeps
    `TileCursor`, `TileCursorBob` and `TileHighlights` from all reading as `Tile`."""
    return re.compile(r"(?<![\w.$" + chr(37) + "\"'])" + re.escape(name) + r"\b")


_PATTERNS = {n: _type_ref(n) for n in FORBIDDEN}
_CLASS_NAME = re.compile(r"^class_name\s+(\w+)")

_CORPUS = None


def corpus(refresh: bool = False):
    """Every non-addon `.gd` file, read ONCE per run — `[(rel, text)]`.

    `refresh` is not optional convenience: the seed tests write a `.gd` into the real
    tree BETWEEN in-process `main()` calls, so a cache that outlived one call would make
    every seed after the first vacuous — a performance fix that silently disarms the
    arms it speeds up. `main()` refreshes on entry."""
    global _CORPUS
    if _CORPUS is not None and not refresh:
        return _CORPUS
    rows = []
    for root in SCAN_ROOTS:
        base = PROJECT_DIR / root
        if not base.is_dir():
            continue
        for q in sorted(base.rglob("*.gd")):
            # A SLICE, NOT `relative_to` — #999's measurement, on this corpus: 1,547
            # `relative_to(...).as_posix()` calls cost 7.3 ms, the slice 0.1 ms. Every
            # `q` here came out of `PROJECT_DIR / root`, so the prefix is not a guess.
            rel = q.as_posix()[_REL_FROM:]
            if rel.startswith(ADDON_ROOT):
                continue
            rows.append((rel, q.read_text(errors="ignore")))
    _CORPUS = rows
    return _CORPUS


# Cites a FILE, not a class or a method. A `.gd` suffix is the whole boundary and it is
# deliberate — `MapIlluminationDDA`'s entry says
# `src/effects/PaletteSubsystem.build_illumination()`, which is path-SHAPED prose naming a
# method, not a file that exists. Widening this to any `src/…` token would red on that
# comment for being written in the house style. STATED BLIND SPOT: a class-or-method
# citation rots unscored; only a file citation is checked.
_CITED_HOST_FILE = re.compile(r"(?:src|tools|tests|addons|assets)/[\w/\.\-]+\.gd")


def declared_citations(text: str = None) -> dict:
    """`{declared name: [host file cited in its comment]}` — ADR-0210 dec. 1.

    ADR-0208 dec. 6 made the per-entry host-use comment structural, and
    `test_every_declared_name_states_a_host_use` mechanized the only half its docstring
    thought mechanizable: PRESENCE. That arm cannot tell a true host use from a token
    one, and `Lattice`'s entry proved it — the comment named one debug panel while 22
    `src/` files and 50 references compiled against the name. The arm was green through
    an entry understating its subject by a factor of twenty.

    The half that IS checkable is the CITATION. A comment that names a host `.gd` file
    makes a claim about the tree, and a claim about the tree is exactly what goes stale
    when the file moves or the last call site is deleted. Two arms in
    `test_check_lattice_publish.py` read this: the cited file must EXIST, and it must
    NAME the symbol.

    Takes `text` so the seeds can construct an entry instead of reading a shipped one —
    the lesson this file's own header states, one list over.
    """
    src = (pathlib.Path(__file__).read_text() if text is None else text)
    block = src.split("DECLARED_PUBLISHED = (")[1].split("\n)")[0]
    out, comment = {}, []
    for line in block.splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            comment.append(stripped)
        elif stripped.startswith('"'):
            out[stripped.strip('",')] = sorted(
                set(_CITED_HOST_FILE.findall(" ".join(comment))))
            comment = []
        elif stripped:
            comment = []
    return out


def addon_class_names() -> set:
    """Every `class_name` the addon declares — the universe the declared set draws from."""
    out = set()
    base = PROJECT_DIR / ADDON_ROOT
    if not base.is_dir():
        return out
    for q in sorted(base.rglob("*.gd")):
        for ln in q.read_text(errors="ignore").splitlines():
            m = _CLASS_NAME.match(ln.strip())
            if m:
                out.add(m.group(1))
    return out


def named_types(text: str, names):
    """`[(symbol, lineno)]` for every TYPE reference to `names` in one file's text."""
    out = []
    if not any(n in text for n in names):
        return out                     # C-level reject; most files match nothing
    for i, ln in enumerate(_code_lines(text), 1):
        for name in names:
            if name not in ln:
                continue
            pat = _PATTERNS.get(name) or _type_ref(name)
            for _m in pat.finditer(ln):
                out.append((name, i))
    return out


def scan():
    """`(arm1, arm2)` — `[(rel, symbol, lineno)]` for the six, split by root."""
    arm1, arm2 = [], []
    for rel, text in corpus():
        for symbol, lineno in named_types(text, FORBIDDEN):
            (arm2 if rel.startswith(TESTS_ROOT) else arm1).append((rel, symbol, lineno))
    return arm1, arm2


def named_sites(rel_prefix: str = "") -> dict:
    """`class_name -> [(rel, lineno)]`, one entry per OCCURRENCE, for every addon
    `class_name` named as a type outside the addon.

    Dec. 4's REPORTED half needs the whole addon surface, not just the forbidden six.
    Arm 3 needs the SITES as well as the count — a name it reds has to be findable —
    and a second walk computing the same predicate is how two answers to one question
    drift apart, so `named_set` is derived from this rather than written beside it."""
    names = addon_class_names()
    pats = {n: _type_ref(n) for n in names}
    sites = {}
    for rel, text in corpus():
        if rel_prefix and not rel.startswith(rel_prefix):
            continue
        if rel_prefix == "src/" and rel.startswith(TESTS_ROOT):
            continue
        if not any(n in text for n in names):
            continue                   # C-level reject — see `_code_lines`
        for i, ln in enumerate(_code_lines(text), 1):
            for n in names:
                if n in ln:
                    k = len(pats[n].findall(ln))
                    if k:
                        sites.setdefault(n, []).extend([(rel, i)] * k)
    return sites


def named_set(rel_prefix: str = "") -> dict:
    """`class_name -> site count`. Derived from `named_sites`; see its docstring."""
    return {n: len(v) for n, v in named_sites(rel_prefix).items()}


def _rows(sites):
    """Sites collapsed onto burn-down keys, in file order."""
    rows = {}
    for rel, symbol, lineno in sites:
        rows.setdefault((rel, symbol), []).append(lineno)
    return sorted(rows.items(), key=lambda kv: (kv[0][0], kv[0][1]))


def _sites_of(pairs):
    """`['rel:1, 2, 3', ...]` — arm 3's sites, grouped by file, at most eight lines each.

    Arm 3 keys on the NAME, so the row itself carries no location; without this the
    report would name a defect nobody could find. The cap matches arm 1's."""
    per = {}
    for rel, lineno in pairs:
        per.setdefault(rel, []).append(lineno)
    return ["%s:%s" % (rel, ", ".join(str(n) for n in sorted(lns)[:8]))
            for rel, lns in sorted(per.items())]


def _by_symbol(sites) -> str:
    per = {}
    for _rel, symbol, _ln in sites:
        per[symbol] = per.get(symbol, 0) + 1
    return ", ".join("%s %d" % (n, per.get(n, 0)) for n in FORBIDDEN)


def main() -> int:
    corpus(refresh=True)   # see `corpus`: a stale cache disarms the seed tests
    arm1, arm2 = scan()

    print("subject: every `.gd` under %s except `%s` — %d file(s). A forbidden name is\n"
          "scored when it appears as a TYPE (ADR-0196 dec. 2): a node path (`$Name`,\n"
          "`%%Name`, `get_node_or_null(\"Name\")`) is a scene-tree coupling, not a compiled\n"
          "symbol, and the exclusion is on the OCCURRENCE, never on the line."
          % ("/".join(SCAN_ROOTS), ADDON_ROOT, len(corpus())))

    rows = _rows(arm1)
    print("\narm 1 (src/, tools/ and non-battlefield addons/assets) — ENFORCING: %d row(s) / "
          "%d site(s).\n    %s" % (len(rows), len(arm1), _by_symbol(arm1)))
    print("arm 2 (tests/) — REPORTING, no target: %d site(s).\n    %s"
          % (len(arm2), _by_symbol(arm2)))

    listed = {k for k, _ in rows}
    unlisted = [(k, v) for k, v in rows if k not in PUBLISH_BURN_DOWN]
    burned = [(k, v) for k, v in rows if k in PUBLISH_BURN_DOWN]
    stale = sorted(k for k in PUBLISH_BURN_DOWN if k not in listed)

    if burned:
        print("\nPUBLISHED-SYMBOL REGISTER — %d row(s) / %d site(s) name a forbidden\n"
              "`Battlefield` `class_name` as a TYPE and are NAMED in PUBLISH_BURN_DOWN\n"
              "with an owner. Not a pass: this is ADR-0164 dec. 4 criterion 1 unmet, on\n"
              "record, target 0 (ADR-0196 dec. 4)."
              % (len(burned), sum(len(v) for _, v in burned)))
        for (rel, symbol), linenos in burned:
            owner, why = PUBLISH_BURN_DOWN[(rel, symbol)]
            at = ", ".join(str(n) for n in sorted(linenos)[:8])
            print("  %s:%s  `%s` x%d\n      %s — %s"
                  % (rel, at, symbol, len(linenos), owner, why))

    if arm2:
        print("\nARM 2 (tests/) — %d site(s), REPORTED, no target. ADR-0196 dec. 3: a\n"
              "threshold here would be guesswork because `classify()` returns `None` for\n"
              "every test file — but arm 1 at zero while the cursor fixtures hold dozens\n"
              "of `Array[Tile]` / `Tile.new()` lines reads as coverage, so they print."
              % len(arm2))
        for (rel, symbol), linenos in _rows(arm2):
            at = ", ".join(str(n) for n in sorted(linenos)[:8])
            print("  %s:%s  `%s` x%d" % (rel, at, symbol, len(linenos)))

    # --- dec. 4's REPORTED half. Scores nothing, and must not. -------------------------
    declared = set(DECLARED_PUBLISHED)
    all_names = addon_class_names()
    any_sites = named_sites()          # arm 3 needs the sites; the report needs the count
    # DERIVED FROM THE SAME WALK, not a second one — `named_sites`'s own docstring
    # argument ("a second walk computing the same predicate is how two answers to one
    # question drift apart"), applied to the caller that was still making one. Identical
    # by construction: `named_sites("src/")` differs from this filter only by a
    # `rel.startswith(TESTS_ROOT)` clause that is dead for a `src/` prefix.
    src_named = {n: k for n, k in
                 ((n, sum(1 for rel, _ln in v if rel.startswith("src/")))
                  for n, v in any_sites.items()) if k}
    any_named = {n: len(v) for n, v in any_sites.items()}
    undeclared = sorted(n for n in any_named if n not in declared)
    unnamed_src = sorted(n for n in declared if not src_named.get(n))
    unnamed_any = sorted(n for n in all_names if not any_named.get(n))
    print("\nDECLARED PUBLISHED SET — %d name(s) declared, %d of the addon's %d\n"
          "`class_name`s named as a type outside it. REPORTED ONLY (ADR-0196 dec. 4): a\n"
          "declared-but-unnamed name is NOT a defect, and enforcing that direction would\n"
          "make deleting a host call site red this guard, which is backwards."
          % (len(declared), len(any_named), len(all_names)))
    print("  named but NOT declared (%d): %s"
          % (len(undeclared), ", ".join(undeclared) or "—"))
    print("  declared but named by nothing in `src/` (%d): %s"
          % (len(unnamed_src), ", ".join(unnamed_src) or "—"))
    print("  `class_name`s named by nothing outside the addon at all (%d): %s"
          % (len(unnamed_any), ", ".join(unnamed_any) or "—"))
    print("  ⚠️ THE PATH SPELLING IS NOT SCORED HERE (dec. 2's 🔴). `PlayerCamera` and\n"
          "  `MapComposer` read 0 above while host files name them by PATH. That is\n"
          "  criterion 4 and `check_lattice_scene.py` scores it — ADR-0205, which also\n"
          "  corrects this line: the population is axis A (host -> addon), NOT the\n"
          "  install term it was called here and in ADR-0196 dec. 8.")

    # --- arm 3, ENFORCING (ADR-0208 dec. 2, #713). Same predicate, scored. ------------
    und_unlisted = [n for n in undeclared if n not in UNDECLARED_BURN_DOWN]
    und_burned = [n for n in undeclared if n in UNDECLARED_BURN_DOWN]
    und_stale = sorted(n for n in UNDECLARED_BURN_DOWN if n not in undeclared)

    if und_burned:
        print("\nUNDECLARED-NAME REGISTER — %d name(s) / %d site(s) are an addon\n"
              "`class_name` named as a TYPE from outside it while `DECLARED_PUBLISHED`\n"
              "does not name them, and are NAMED in UNDECLARED_BURN_DOWN with an owner.\n"
              "Not a pass: this is ADR-0208 dec. 2's second half unmet, on record,\n"
              "target 0."
              % (len(und_burned), sum(len(any_sites[n]) for n in und_burned)))
        for n in sorted(und_burned):
            owner, why = UNDECLARED_BURN_DOWN[n]
            files = sorted({rel for rel, _ln in any_sites[n]})
            print("  `%s` x%d over %d file(s)\n      %s — %s\n      %s"
                  % (n, len(any_sites[n]), len(files), owner, why,
                     "\n      ".join(_sites_of(any_sites[n]))))

    if "--list" in sys.argv:
        print("\nPUBLISH_BURN_DOWN rows:")
        for (rel, symbol), (owner, why) in sorted(PUBLISH_BURN_DOWN.items()):
            print("  %s  `%s`   [%s]\n      %s" % (rel, symbol, owner, why))

    if und_unlisted:
        print("\nUNDECLARED NAME: %d name(s) / %d site(s) are an addon `class_name` named\n"
              "as a TYPE from outside the addon while `DECLARED_PUBLISHED` does not name\n"
              "them, and are NOT on UNDECLARED_BURN_DOWN (ADR-0208 dec. 2, #713).\n"
              % (len(und_unlisted), sum(len(any_sites[n]) for n in und_unlisted)))
        for n in sorted(und_unlisted):
            print("  `%s` x%d\n      %s"
                  % (n, len(any_sites[n]), "\n      ".join(_sites_of(any_sites[n]))))
        print("\nAnswer by deleting the reach, by routing it through a mount or a value\n"
              "both sides can name, or by DECLARING the name — and a declaration is an\n"
              "ADR-0208 dec. 6 move: it states the host use it serves, above the entry,\n"
              "and never in the commit that closes the criterion-4 row it drains. Adding\n"
              "the row here instead requires an owner and, under ADR-0196 dec. 5, the\n"
              "pass that closes it.")

    if und_stale:
        print("\nSTALE UNDECLARED_BURN_DOWN — %d row(s) name a `class_name` that is no\n"
              "longer both named from outside and undeclared. Delete the row. ⚠️ A row\n"
              "going stale is what SUCCESS looks like here — the name was published with\n"
              "a stated host use, the last host namer went away, or the addon stopped\n"
              "declaring it. Check which before calling it a regression.\n" % len(und_stale))
        for n in und_stale:
            owner, why = UNDECLARED_BURN_DOWN[n]
            print("  `%s`   [%s]  %s" % (n, owner, why))

    if unlisted:
        print("\nPUBLISHED SYMBOL: %d row(s) / %d site(s) name a forbidden `Battlefield`\n"
              "`class_name` as a TYPE and are NOT on PUBLISH_BURN_DOWN (ADR-0164 dec. 4\n"
              "criterion 1, ADR-0196 dec. 4).\n"
              % (len(unlisted), sum(len(v) for _, v in unlisted)))
        for (rel, symbol), linenos in unlisted:
            at = ", ".join(str(n) for n in sorted(linenos)[:8])
            print("  %s:%s  `%s` x%d" % (rel, at, symbol, len(linenos)))
        print("\nAnswer by moving the value the host actually wants to a place both sides\n"
              "can name — the schema, per ADR-0196 dec. 6 — or add the row with its owner\n"
              "and, under dec. 5, the PASS that closes it. A re-spelling count is never\n"
              "grounds to defer.")

    if stale:
        print("\nSTALE PUBLISH_BURN_DOWN — %d row(s) name a (file, symbol) pair that no\n"
              "longer names the symbol as a type. Delete the row; a burn-down that\n"
              "outlives its debt is a list nobody rereads. ⚠️ A row going stale is what\n"
              "SUCCESS looks like here — check the move before you call it a regression.\n"
              % len(stale))
        for rel, symbol in stale:
            owner, _why = PUBLISH_BURN_DOWN[(rel, symbol)]
            print("  %s  `%s`   [%s]" % (rel, symbol, owner))

    if unlisted or stale or und_unlisted or und_stale:
        return 1

    if burned:
        print("\nPublished-symbol register: %d site(s) over %d row(s), of a target 0. Every\n"
              "one is on PUBLISH_BURN_DOWN with an owner and a pass, and no listed row has\n"
              "gone stale. ADR-0196 dec. 1: this guard exists BEFORE the enum moves, because\n"
              "after the move a scanner blind to the old spelling is indistinguishable from\n"
              "a correct one." % (sum(len(v) for _, v in burned), len(burned)))
    else:
        # ⚠️ THE FIRST LINE IS QUOTED VERBATIM BY ADR-0206's Consequences. Arm 3 arrived
        # after that sentence was written, so the wording is qualified rather than
        # replaced — a renamed verdict would strand the citation silently, which is the
        # failure `test_every_declared_name_states_a_host_use` exists to make loud one
        # level up.
        print("\nPUBLISHED-SYMBOL REGISTER CLEAR — no forbidden `Battlefield` `class_name`\n"
              "is named as a type by another system's source (ADR-0164 dec. 4 criterion 1,\n"
              "as amended by ADR-0196 dec. 4). ⚠️ THAT IS ARM 1 ALONE. Arm 3 has its own\n"
              "verdict below and answers a different question — arm 1 counts couplings to\n"
              "the six, arm 3 counts the names a host MAY couple to (#713).")

    if und_burned:
        print("\nArm 3: %d name(s) over %d site(s) are reachable-but-unpublished, of a\n"
              "target 0. Every one is on UNDECLARED_BURN_DOWN with an owner, and no\n"
              "listed row has gone stale. ADR-0208 dec. 2's second half is on record\n"
              "rather than unenforced (#713)."
              % (len(und_burned), sum(len(any_sites[n]) for n in und_burned)))
    else:
        print("\nARM 3 CLEAR — every addon `class_name` named as a type from outside the\n"
              "addon is one `DECLARED_PUBLISHED` names (ADR-0208 dec. 2).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
