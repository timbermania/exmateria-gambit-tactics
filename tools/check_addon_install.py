#!/usr/bin/env python3
"""Guard: the install register — ADR-0202, goal #5's addon → host direction.

    uv run python tools/check_addon_install.py [--list]

THE RULE (ADR-0202 dec. 2). `addons/exmateria_battlefield/` must load and work in a bare
**Godot 4.8-compositor-fork** project holding `exmateria_schema`, `exmateria_platform` and
itself, and NOTHING else. Every dependency on anything outside those three roots is scored,
and it burns down BY NAME (#424 — an exclusion expressed as a filter manufactures its own
debt and cannot tell a triaged site from one that merely matches).

WHY THIS IS A DIFFERENT REGISTER FROM `check_lattice_publish.py`, AND WHY FOLDING THEM WOULD
BE WRONG. That one measures **host → addon**: does another system name a `Battlefield`
`class_name` it should not (ADR-0164 dec. 4 criterion 1). This one measures **addon → host**.
An addon can satisfy all three of ADR-0164's criteria and still fail to *load* in a bare
project — which is exactly today's state, criterion 2 and 3 clear and the addon reaching 11
asset paths outside its own roots. ADR-0131 dec. 7's named failure is one number answering
two questions; ADR-0202 dec. 1 keeps the two terms apart for the same reason.

WHY THIS GUARD EXISTS AT ALL, GIVEN `check_addon_portability.py` REPORTS **OK**. It does, and
it is green through every site below. Its arms cover systems, autoloads, shader `#include`
resolution, shader globals and sibling `class_name`s. **No arm reads a `res://` path out of a
`.gd` body or a `.tscn` `ext_resource`**, so eleven code sites over eight files are invisible
to it. Two instruments now answer one goal and disagree; ADR-0202's Consequences name the
reconciliation and its owner (the pass that closes Class B) rather than doing it here.

WHY THE REGISTER GOES BEFORE THE MOVES (ADR-0202 dec. 10, applying ADR-0192 dec. 1 through
ADR-0196 dec. 1). Class A's baseline erases itself: once `tile_overlay.tres` lives inside the
addon, a scanner that never learned to read `res://` out of a `.gd` reports the same **0** as
a correct one. `INSTALL_BURN_DOWN` is the frozen population, and each move is GRADED by
watching its rows go STALE.

🔴 THIS ARM NEEDS THE OPPOSITE STRIPPER FROM ITS SIBLINGS, and getting that backwards makes
it read zero. `check_lattice_publish` and `check_lattice_doors` both scan for SYMBOLS and use
`touch_matrix.strip_noncode`, which **blanks string literals**. Every site this register
scores lives *inside* a literal. Slicing `strip_noncode` here would have produced a guard
that reports a clean tree over eleven live edges — the exact failure ADR-0202 dec. 10 exists
to prevent. See `_literals`.

🔴 AND `res://` CONTAINS `//`. A shader stripper that removed `//` comments before finding
the literals would eat every single `#include "res://…"` line, which is how an earlier arm in
this family read 0 of 5. `_literals` walks characters tracking quote state, so a comment
marker inside a literal never fires and a literal's own `//` is never a comment. For the same
reason a `#` inside a GDScript literal cannot truncate the line, which is the defect
`check_lattice_publish._code_lines` had to repair after the fact.

ARMS.

  arm 1  ENFORCING, burn-down, both directions. A `res://` path in an addon file that
         resolves outside the three permitted roots. **11 sites over 8 files** at build time,
         split three ways by ADR-0202 dec. 5 — Class A moves in, Class B loses the literal
         and keeps the dependency, Class C is a layering inversion.

  arm 2  ENFORCING, burn-down. An input action the addon REQUIRES that Godot does not
         provide built-in **and no `plugin.gd` in the walk provides**. **8 distinct actions**
         at build time — NOT the 2 a grep for inline literals finds; see the 🔴 on
         `_ACTION_LITERAL`. All 8 are provided as of ADR-0203; the requirement did not go
         away, the gap did.

  arm 3  ENFORCING, burn-down. A `global uniform` on the addon's compile surface, following
         `#include`s transitively into the permitted siblings, that **no `plugin.gd` in the
         walk provides**. **6** at build time. A missing `global uniform` is a COMPILE error —
         it fails the whole shader, not one file's parse (ADR-0169), which is why this arm is
         stricter than arm 1 despite being smaller.

  🔴 ARMS 2 AND 3 SCORE A GAP, NOT A MENTION — ADR-0203 dec. 3, and they did not always.
  Until it, both asked "does the addon NAME it", which is a question no correct addon can
  ever answer 0 to: the battlefield addon binds `cursor_confirm` because binding
  `cursor_confirm` is what it is FOR. An arm whose only clean state is "the code was
  deleted" stops being read, and dec. 3 re-points it to the question that actually decides
  installability — *does a bare project end up with this name*. The precedent is ADR-0003
  dec. 7 **Arm A**, the same question asked about autoloads, whose guard shape is copied in
  `provided_by_walk` below. It is NOT ADR-0190 arm 4b, which asks whether a global has a
  WRITER — a different question with a different answer, and citing it here would import a
  ruling about host entries into a ruling about installs.

  arm 4  REPORTING, NO TARGET (ADR-0202 dec. 3). Fork-only compositor tokens. The fork IS the
         target platform, so these are conformant; a register that scored its own target
         could never reach 0 and a burn-down that cannot reach 0 stops being read. They print
         because this is the one blocker that produces NO ERROR when violated — under stock
         4.7 the compositor self-disables and every folded prim silently vanishes.

WHAT THIS GUARD CANNOT SEE, stated because every blind spot on this map has scored zero and
every one of them has been real:

  - **A path built at runtime.** `load("res://assets/" + name)` puts only `res://assets/`
    in a literal, which this DOES catch, but `load(base_dir + name)` where `base_dir` came
    from a caller is invisible. Measured at build time: **zero** such sites in the addon.
  - **A triple-quoted docstring body**, skipped as prose along with `#` comments. Measured:
    **zero** of the addon's triple-quoted blocks contain `res://`, so nothing is being hidden
    today — but a path moved into one would leave the register.
  - **A sibling addon's own reaches.** The subject is `exmateria_battlefield`. `_platform`
    and `_schema` are checked only as `#include` targets for arm 3; measured **0** `res://src/`
    or `res://assets/` reaches in either, so the three-addon target holds today.
  - **A soft, null-guarded autoload reach**, which ADR-0202 dec. 7 rules CONFORMANT.
    `TunePort.gd:78`'s `root.get_node_or_null(^"Tune")` serves defaults when the answer is
    null. The consequence is stated rather than scored: in a bare project every tunable
    override is inert and the compiled-in defaults apply. That is a working install.
  - **The cross-addon `class_name` surface** — 23 rows over 9 distinct symbols.
    `check_addon_portability.py` already prints it, ADR-0139 dec. 9/12 permits it, and
    ADR-0202 dec. 2 folds it into the *target* rather than the debt. Duplicating it here
    would score a dependency this ADR has declared legal.
"""
import pathlib
import re
import sys

PROJECT_DIR = pathlib.Path(__file__).resolve().parent.parent

# --- the subjects ---------------------------------------------------------------------
#
# 🔴 THIS TABLE IS THE WIDENING, AND UNTIL IT EXISTED AXIS B HAD EXACTLY ONE READING FOR
# A TREE WITH TWO EXTRACTED ADDONS IN IT. `ADDON_ROOT` was the literal
# `addons/exmateria_battlefield/`, so `check_addon_install` answered ADR-0202's question
# about extraction #3 and about nothing else. Extraction #4's rig was not merely open on
# this axis, it was UNMEASURED — and an unmeasured channel reads exactly like a closed one
# in any summary that lists the guards and finds them all green. `check_lattice_scene.py`
# took the same widening for the same reason (ADR-0205); this is its axis-B twin, and the
# shape is copied deliberately down to `_check_registers()` raising rather than reporting.
#
# `permitted` IS THE INSTALL TARGET AND IT IS DECLARED PER SUBJECT, not derived. Deriving
# it from what the addon happens to reach is the tautology this whole family refuses: an
# addon that reaches a fourth root would simply grow a fourth permitted root and score 0
# forever. The target is a claim about what a person is expected to install, and it is
# written down so that a reach outside it is a finding rather than a definition.
SUBJECTS: dict[str, dict] = {
    "exmateria_battlefield": {
        "why": "ADR-0202 dec. 2 — extraction #3's addon, and the subject this guard was "
               "written for. All four arms read 0 (ADR-0203 closed the last of them).",
        "permitted": ("res://addons/exmateria_battlefield/",
                      "res://addons/exmateria_schema/",
                      "res://addons/exmateria_platform/"),
    },
    "exmateria_effects": {
        "why": "gl-ADR-0295 dec. 2 — extraction #7's addon, SCORED HERE FOR THE FIRST TIME, "
               "and the first subject whose target is not the battlefield's shape. Its "
               "`plugin.cfg` `deps=` names six siblings and the target below is all of "
               "them: MEASURED, not assumed — arm 1 reads 8 against this set, all Class B, "
               "and dropping any of `exmateria_render` (the `FoldSurface` bracket "
               "`EngineFoldCompositor` installs), `exmateria_schema` (`ot_depth.gdshaderinc`, "
               "included by four shaders) or `exmateria_sound` (three `runtime/` preloads in "
               "`cast/EffectInstance.gd`) puts rows back. `exmateria_battlefield` and `exmateria_almanac` are "
               "in the target because arm 5 says the SYMBOLS cross (ADR-0288 dec. 8's ten "
               "debt lines) even though no `res://` path does — a permitted root the subject "
               "never reaches on THIS arm is a root the register cannot grade, so both are "
               "declared with that caveat rather than quietly omitted.\n"
               "  🔴 THE ROWS BELOW ARE EIGHT `res://assets/` LITERALS, ALL CLASS B "
               "(ADR-0202 dec. 5 — the LITERAL is the defect, the dependency is real and "
               "un-shippable). They are the ROM-derived content pack ADR-0142 rules "
               "un-shippable: four TRAP tables, the per-effect `E###` directory, the "
               "per-callback payload and the TRAP texture pair. The shape that pays them is "
               "the host-injected content root `install/BattlefieldContent.gd` already "
               "ships, and it is a RUNTIME change to three loaders rather than anything a "
               "`git mv` commit can do.\n"
               "  Arms 2, 3 and 4 read 0 / 0 / (not scored): the addon requires no input "
               "action, declares no `global uniform` (#1217 moved `psx_fx_stretch` to the "
               "port and left `psx_gamma` the host's, so arm 4b of the portability guard "
               "reads 0 too), and arm 4 declines to score the fork by its own rule.",
        "permitted": ("res://addons/exmateria_effects/",
                      "res://addons/exmateria_schema/",
                      "res://addons/exmateria_platform/",
                      "res://addons/exmateria_render/",
                      "res://addons/exmateria_battlefield/",
                      "res://addons/exmateria_almanac/",
                      # Another PACKAGE, vendored under this one's `addons/` and ruled by
                      # its own guards (ADR-0212 dec. 11). In the target because three
                      # `runtime/` preloads resolve there, which is the one thing this arm
                      # can see about it.
                      "res://addons/exmateria_sound/"),
    },
    "exmateria_sprite_rig": {
        "why": "ADR-0217 — extraction #4's addon, SCORED HERE FOR THE FIRST TIME. Its "
               "target is the same shape as the battlefield's — fork + kernel + port + "
               "itself — and the shape is not an assumption: measured against the four "
               "candidate targets, arm 1 reads 7 sites against the rig alone, 4 with the "
               "kernel added and 0 with the port added, and adding `exmateria_render` on "
               "top changes nothing. So the port is the last root the rig actually needs "
               "and `exmateria_render` is deliberately NOT in the target — a permitted "
               "root the subject never reaches is a root the register cannot grade.\n"
               "  ALL FOUR ARMS READ 0, AND ARM 3 GOT THERE BY A FIX RATHER THAN BY "
               "SILENCE. The rig's `unit.gdshader` and `unit_additive.gdshader` "
               "`#include` two of the port's `.gdshaderinc` files, which is legal — the "
               "port IS in the target — and what they pull onto the compile surface is "
               "two `global uniform`s (`pixel_aspect`, `unit_stretch`). On this "
               "register's first reading of this subject NOTHING in the target provided "
               "them and arm 3 read 2. ADR-0220 dec. 1/2 moved the provide to the addon "
               "that DECLARES each name — `exmateria_platform`, which is in every "
               "subject's target — and both rows closed. The two Class E rows are gone "
               "from `_SPRITE_RIG_ROWS`, which is what a discharged burn-down looks like.",
        "permitted": ("res://addons/exmateria_sprite_rig/",
                      "res://addons/exmateria_schema/",
                      "res://addons/exmateria_platform/"),
    },
}


def addon_dir(addon: str) -> str:
    """`addons/x/` — the walk root for a subject."""
    return "addons/" + addon + "/"


def permitted(addon: str) -> tuple:
    return SUBJECTS[addon]["permitted"]

# Every file type the addon actually has that can carry a path or a declaration.
# `.uid` files are Godot's import bookkeeping and carry a `uid://`, never a `res://`.
SCANNED_SUFFIXES = (".gd", ".tscn", ".tres", ".gdshader", ".gdshaderinc", ".cfg")

# ADR-0202 dec. 3. Fork-only; REPORTED, never scored.
FORK_TOKENS = ("compositor_fold", "compositor_layer", "render_layer")


# --- the burn-down (ADR-0202 dec. 10) -------------------------------------------------
# `(rel, kind, target) -> (klass, owner, why)`. A NAMED LIST, never a pattern.
#
# THE KEY CARRIES NO LINE NUMBER, on `PORT_BURN_DOWN`'s and `PUBLISH_BURN_DOWN`'s stated
# reason: a key that moved when a line moved would produce a stale row AND an unlisted row
# for the same site on every unrelated edit above it. Several SITES collapse onto one ROW;
# the report prints both counts and every line number.
#
# 🔴 THIS IS THE HAND COUNT, AND IT IS THE ONLY EVIDENCE THE SCANNER IS RIGHT. Each site was
# re-read individually before its row was written. Two of the three numbers ADR-0202 inherited
# were wrong and are corrected here rather than carried: the globals are **6** and not the
# portability guard's whole-walk 12 (six of those lines are `PSXDisplay.gd` *pushes*, GDScript
# sets that cannot fail a compile), and the actions are **8** and not 2.
#
# It read **49 sites over 29 rows** on `71f410cfc` and reads **48 over 28** after the Class A
# move: minus three rows, plus two.
_BATTLEFIELD_ROWS = {
    # ==== arm 1, Class A — ✅ CLOSED, 3 rows, by ADR-0202 dec. 5. ======================
    # `tile_cursor_opaque.tres` -> `cursor/`, `tile_overlay.tres` -> `overlay/`,
    # `tile_knife.json` -> `cursor/`. All three rows went STALE the moment the move landed:
    # this guard returned 1 on the move commit until they were deleted, which is dec. 10's
    # whole design. The move was GRADED by the register, not asserted by the mover — and the
    # grading is the only reason we know the scanner is satisfied rather than blind, because
    # Class A reading 0 is what BOTH look like.
    #
    # 🔴 THE MOVE DID NOT SUBTRACT THREE. It subtracted three and ADDED TWO: the register
    # scans `.tres` inside the addon, and `tile_cursor_opaque.tres` carries its own two
    # `RANGETILE` `ext_resource`s. Those did not appear — they were always there, one
    # indirection away, invisible while the file sat outside the addon root. Arm 1 went
    # 11 -> 10, not 11 -> 8, and the two new sites are booked below as Class B beside the
    # `Tile.gd` rows that name the same two textures. A fix booked into the bucket it drains
    # is how a delta lies; classify the new file before trusting one.
    #
    # 🔴 THE SEVERITY CHANGED EVEN WHERE THE COUNT DID NOT. `TileCursor.gd:150` was the one
    # PARSE-TIME site in the register — a `preload` of a file a bare project does not have,
    # which stops the addon LOADING. It now preloads a file the addon ships, so the addon
    # parses; what is left is two textures that fail to load at runtime. The register counts
    # sites, so it cannot show this. It is the reason the move was worth making.

    # ==== arm 1, Class B — ✅ CLOSED, 9 rows, by ADR-0202 dec. 5 + ADR-0203 dec. 1. ====
    # ROM-derived, un-shippable: the map tree, the doodad tree and the `RANGETILE` trio.
    # "Move it in" was never available, so dec. 5 removed the LITERAL and kept the
    # dependency as a contract — `install/BattlefieldContent.gd` resolves every subpath
    # against a host-declared `exmateria_battlefield/content_root`, and the in-repo game
    # declares it in `project.godot`. All nine rows went STALE together and were deleted.
    #
    # 🔴 THE DEFAULT IS EMPTY AND THAT IS THE LOAD-BEARING PART. A default of
    # `res://assets/` would have left the literal inside an addon file, so arm 1 would
    # still score it and the nine rows would NOT have reached 0 — the fix booked into the
    # bucket it drains, which is how a delta lies in this family. Empty also buys dec. 5's
    # actual goal: a bare project gets one push_error naming the setting instead of a
    # silent empty load.
    #
    # 🔴 TWO OF THE NINE WERE NOT REACHABLE BY A SETTING AT ALL. `tile_cursor_opaque.tres`
    # carried the `RANGETILE` pair as `[ext_resource]` links, and an `ext_resource`
    # resolves at LOAD time, before any code runs. No search root can reach one. The
    # material had to stop referencing them and take them at runtime
    # (`TileCursor._bind_range_textures`), which is also what cleared the stranger rig's
    # two `known_failures.tsv` rows — one debt wearing two addresses, the `.tres` and
    # `TileCursor.gd:150`'s `preload` of it as a pure cascade.

    # ==== arm 1, Class C — ✅ CLOSED, 1 row, by ADR-0202 dec. 6 + ADR-0204. ============
    # `camera/PlayerCamera.tscn:5` declared `res://assets/scenes/CombatUI.tscn` and `:38`
    # instanced it at `FocusPoint/Camera` — the addon's camera scene OWNING the host's
    # entire combat UI. A LAYERING INVERSION, not a path problem: re-pathing the row green
    # would have made the tree worse, which is why dec. 6 named a mount point instead.
    #
    # ADR-0204's mount point is a host-owned INHERITED SCENE, `assets/scenes/
    # CombatCamera.tscn`, based on the addon's scene and carrying the `CombatUI` instance
    # at the same node and the same index. All 107 consumers swapped ONE `ext_resource`
    # line and every node path stayed byte-identical. dec. 2 rejects the obvious `UIMount`
    # spelling: a named child of `Camera` lengthens 17 live paths to publish one node while
    # ~90 test scenes already override `Camera` itself under `[editable path=...]`.
    #
    # 🔴 THE COUNT THAT WAS BEING USED WAS THE WRONG COUNT, and the register is one of the
    # instruments that said so. This arm scored the ADDON's two lines — the sites that NAME
    # the path — while **104 of the 107** consumers inherit the node silently and mention
    # `CombatUI` nowhere. Deleting two lines would have emptied `combat_ui` in 76 test
    # scenes, and 65 of those never dereference it, so most would have stayed GREEN. The
    # oracle for the move is `tests/CombatCameraMountTest.gd`, which COUNTS resolutions.
    #
    # 🔴 AND CLASS C CLOSES ON THE ADDON SIDE ONLY (ADR-0204 dec. 3). The host still
    # depends on the addon's interior structure in 107 scenes. That dependency runs
    # host -> addon, which is ADR-0164 dec. 4 criterion 1's axis, still open at 21/12 by
    # design. ADR-0202 dec. 1 forbids reporting either axis as the other.

    # ==== arm 2, Class D — ✅ CLOSED, 12 rows, by ADR-0203 dec. 1 + dec. 3. ============
    # The 8 input actions the addon binds, 12 rows because `PAN_ACTIONS` and
    # `CURSOR_ACTIONS` name the same four in two files and either file could be fixed
    # alone. `addons/exmateria_battlefield/plugin.gd` now PROVIDES all eight at enable
    # time — name, deadzone and the host's exact key/pad bindings — so the requirement
    # still stands and the GAP is gone, which is the only thing dec. 3's predicate scores.
    # All twelve rows went stale together and were deleted.
    #
    # 🔴 SIX OF THE EIGHT WERE INVISIBLE TO A GREP FOR `is_action_pressed("literal")`,
    # which is where the inherited count of 2 came from. They travel as `StringName`
    # constants (`CURSOR_ACTIONS`, `PAN_ACTIONS`, `CURSOR_CONFIRM_ACTION`,
    # `CURSOR_INSPECT_ACTION`) and reach `is_action_pressed` through a loop variable. That
    # is why `_ACTION_LITERAL` scans for `&"…"` as well as for the call site.
    #
    # 🔴 THE DEFAULTS ARE PART OF THE FIX, NOT DECORATION. `cursor_confirm` binds Enter and
    # NOT Space, because on the battlefield Space starts the battle — riding `ui_accept`
    # would make starting a battle also a confirm (ADR-0137, and `TileCursor`'s own
    # docstring). A provide that supplied the eight NAMES with empty event lists would
    # green this arm and ship an addon nobody can drive.

    # ==== arm 3, Class E — ✅ CLOSED, 5 rows, by ADR-0203 dec. 1 + dec. 3. ============
    # The 5 `global uniform`s on the addon's compile surface, now provided by
    # `plugin.gd` with the host's types and defaults. A missing `global uniform` fails the
    # WHOLE shader, not one file's parse (ADR-0169), which is why this arm was stricter
    # than arm 1 despite being smaller.
    #
    # 🔴 THE ADR-0190 MOVE DID NOT DRAIN THE BUCKET IT WAS BOOKED INTO, and this row block
    # is the record of it. `scan_globals` follows `#include` into the port and keys each
    # row to the DECLARING file, so relocating three declarations from
    # `exmateria_battlefield/` to `exmateria_platform/` re-keyed the rows and left them
    # scored: 6 -> 5, and the one that closed was the one with no writer
    # (`visible_angles_cull_mode`). The five that remained were all the same shape
    # `pixel_aspect` always had — declared in the port, reached through an include — and no
    # further move could have touched them, because the port ships beside the addon and
    # neither can supply a HOST setting the other one needs. Providing them is what
    # closed it. ADR-0190 dec. 4's "goal #5's shader half is met *as an install step*"
    # is now literally true: this is the install step.
    #
    # ⚠️ AMENDED BY ADR-0220 dec. 2 -- the clause "neither can supply a HOST setting
    # the other one needs" is FALSE, and the five entries have moved to the port. Both
    # addons run `set_setting` against the same `ProjectSettings`, so either one CAN
    # supply the setting; what the sentence was really observing is that at the time only
    # the battlefield had a `plugin.gd` doing it. The five names are all DECLARED in the
    # port, and a provide sitting in a different addon from the declaration is exactly
    # what left the sprite rig uninstallable -- see `_SPRITE_RIG_ROWS`. This block stays
    # because the ADR-0190 accounting it records (6 -> 5, and WHY the five survived a
    # move) is still the true history of the bucket.
    #
    # 🔴 A DEFAULT OF 0 WOULD HAVE BEEN WORSE THAN THE GAP for one of the five.
    # `PSXDisplay`'s reader turns an absent name into `0.0`, and a `pixel_aspect` of 0
    # collapses every vertex's x — a blank screen with no error. That is ADR-0203 dec. 7,
    # fixed in the same commit as this arm: the reader now pushes an error instead of
    # serving a degenerate value. `BattlefieldProvidesTest` asserts the five VALUES, not
    # just the five names, for the same reason.
}

# extraction #4's rows. EMPTY, and deliberately still here.
#
# \U0001f534 IT HELD TWO CLASS E ROWS FOR ONE SESSION AND BOTH CLOSED, WHICH IS THE ONLY
# OUTCOME A BURN-DOWN IS FOR. On this register's first reading of `exmateria_sprite_rig`
# arm 3 read 2: `render/unit.gdshader:47,52` and `render/unit_additive.gdshader:40,45`
# `#include` two of the port's `.gdshaderinc` files -- both permitted -- and those files
# declare `pixel_aspect` and `unit_stretch`, which nothing in `permitted()` provided.
# `pixel_aspect` was provided only by `addons/exmateria_battlefield/plugin.gd`, an addon that
# is NOT in this subject's target and must not be (the Class C layering inversion of
# ADR-0202 dec. 6, arriving by the shader-global door instead of the path door);
# `unit_stretch` was provided by no `plugin.gd` in the tree at all, only by the
# host's own `project.godot:857`.
#
# \U0001f534 THE FIX WAS NOT "ADD TWO ENTRIES SOMEWHERE IN THE TARGET" -- that would have
# closed these two rows and left the next one to be discovered the same way, an
# extraction later. ADR-0220 dec. 1 rules that the addon which DECLARES a `global
# uniform` PROVIDES it. Composed with ADR-0190 / arm 4b ("only the kernel and the port
# may declare one"), that yields "only the port provides", and the port is in EVERY
# subject's target -- so one provide closes the name for every consumer, present and
# future, instead of re-opening the row once per addon. `exmateria_platform/plugin.gd`
# gained all six; `exmateria_battlefield/plugin.gd` shed the five it had been carrying
# for names it does not declare (ADR-0220 dec. 2), and its own arm 3 stayed 0 through
# that -- which is the load-bearing half of the reading, because it is what proves
# `provided_by_walk` finds the port INSIDE the battlefield's target rather than the
# battlefield having been green off its own array all along.
#
# ⚠️ EMPTY IS NOT THE SAME AS ABSENT. `_check_registers()` requires a key here for
# every `SUBJECTS` key; deleting the name would raise. And the arm that scores this
# subject is unchanged and still enforcing -- a new unprovided global reddens it
# tomorrow.
_SPRITE_RIG_ROWS: dict = {}


_EFFECTS_ROWS: dict = {
    # \U0001f7e2 EMPTY SINCE 2026-09-12, AND IT WENT 8 -> 0 BY THE SHAPE ITS OWN ROWS
    # NAMED. #1225 seeded eight Class B rows — the per-effect `E###` directory, the
    # per-callback `callback_data.json`, the four TRAP config tables, and the `TRAP1`
    # texture/palette pair — every one a `res://assets/…` literal in addon code addressing
    # ROM-derived content ADR-0142 rules un-shippable. Each row said the fix in the same
    # sentence: ADR-0202 dec. 5's host-injected content root, the way
    # `install/BattlefieldContent.gd` and `install/CatalogueContent.gd` already ship it.
    # `addons/exmateria_effects/install/EffectsContent.gd` is that file, transcribed from
    # the battlefield one, and `godot-learning/project.godot` declares
    # `exmateria_effects/content_root`.
    #
    # \U0001f534 "UN-SHIPPABLE CONTENT" AND "PERMANENT ROW" ARE DIFFERENT CLAIMS, AND THESE
    # ROWS RAN THEM TOGETHER. Every one carried *"ROM-derived and un-shippable under
    # ADR-0142, so the LITERAL is the defect and the dependency is real"* — the first half
    # true, the second half a non-sequitur that `check_addon_portability.py`'s twin rows
    # spelled out as *"the pair is PERMANENT under ADR-0142 rather than targeted at zero"*.
    # ADR-0142 makes the CONTENT un-shippable. This register scores the LITERAL. A content
    # root removes every literal without moving one ROM-derived byte, so the dependency
    # survives as a documented install step and the row reaches 0. Kept as the note this
    # list opens with, because the same conflation is still live on `exmateria_sound`'s
    # `audio_engine.gd` row in the sibling register.
    #
    # \u26a0\ufe0f EMPTY IS NOT THE SAME AS ABSENT — `_check_registers()` requires a key
    # here for every `SUBJECTS` key, and the arm that scores this subject is unchanged and
    # still enforcing: a new `res://assets/` literal in an addon file reds it tomorrow.
}

# \U0001f534 KEYED BY ADDON, and every `SUBJECTS` key must appear — `_check_registers()`
# raises otherwise, on `check_lattice_scene._check_registers`'s stated reason: a subject
# missing from the register is graded with `.get(addon, {})` semantics, every site
# UNLISTED, which is LOUD; but a register naming a subject that `SUBJECTS` does not scan
# reads as owing nothing, SILENTLY. The silent direction is the one that has to raise.
INSTALL_BURN_DOWN: dict[str, dict] = {
    "exmateria_battlefield": _BATTLEFIELD_ROWS,
    "exmateria_sprite_rig": _SPRITE_RIG_ROWS,
    "exmateria_effects": _EFFECTS_ROWS,
}


def _check_registers() -> None:
    """Every subject has a row in the register, and the register names no other subject."""
    missing = sorted(set(SUBJECTS) - set(INSTALL_BURN_DOWN))
    extra = sorted(set(INSTALL_BURN_DOWN) - set(SUBJECTS))
    if missing:
        raise SystemExit("INSTALL_BURN_DOWN has no row for %s — a graded subject with no "
                         "register entry. Add the row (empty is a measurement)." % missing)
    if extra:
        raise SystemExit("INSTALL_BURN_DOWN names %s, which SUBJECTS does not grade — a "
                         "register nobody scans reads as owing nothing, silently." % extra)

CLASS_LABEL = {
    "A": "Class A — addon-owned, tracked. The fix is a MOVE (dec. 5)",
    "B": "Class B — ROM-derived, un-shippable. The LITERAL is the defect (dec. 5)",
    "C": "Class C — a layering inversion, not a path (dec. 6)",
    "D": "input actions (dec. 9)",
    "E": "shader globals — a COMPILE failure, not a parse one (dec. 8)",
}


# 🔴 A CHARACTER WALK, NOT A REGEX, AND NOT `strip_noncode`. See the two 🔴s in the module
# docstring: every site this register scores lives INSIDE a string literal, which
# `strip_noncode` blanks; and `res://` contains `//`, which a shader comment stripper would
# eat. Tracking quote state is what makes both safe at once — a comment marker inside a
# literal never fires, and a literal's own `//` or `#` is never a comment.
def _literals(text: str, line_comment=None, block: bool = False):
    """`[(lineno, body)]` for every double-quoted literal, comments removed.

    `line_comment` is `"#"` for GDScript, `"//"` for shaders, `None` for `.tscn`/`.tres`
    (Godot's scene format has no comment syntax). `block` enables `/* … */`.

    GDScript `\"\"\"…\"\"\"` blocks are skipped as PROSE rather than collected. They are real
    string expressions to the parser, but nothing `load()`s one; measured at build time,
    zero of the addon's triple-quoted blocks contain a `res://`. Stated in the docstring's
    blind-spot list because a path moved into one would leave the register."""
    out = []
    i, n, lineno = 0, len(text), 1
    while i < n:
        c = text[i]
        if c == "\n":
            lineno += 1
            i += 1
            continue
        if block and c == "/" and text[i + 1:i + 2] == "*":
            end = text.find("*/", i + 2)
            end = n if end < 0 else end + 2
            lineno += text.count("\n", i, end)
            i = end
            continue
        if line_comment and text.startswith(line_comment, i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if text.startswith('"""', i):
            end = text.find('"""', i + 3)
            end = n if end < 0 else end + 3
            lineno += text.count("\n", i, end)
            i = end
            continue
        if c == '"':
            start_line, j, buf = lineno, i + 1, []
            while j < n and text[j] != '"':
                if text[j] == "\\":
                    buf.append(text[j:j + 2])
                    j += 2
                    continue
                if text[j] == "\n":       # an unterminated literal is not a literal
                    break
                buf.append(text[j])
                j += 1
            if j < n and text[j] == '"':
                out.append((start_line, "".join(buf)))
                i = j + 1
                continue
            i += 1
            continue
        i += 1
    return out


_COMMENT_STYLE = {
    ".gd": ("#", False),
    ".gdshader": ("//", True),
    ".gdshaderinc": ("//", True),
    ".tscn": (None, False),
    ".tres": (None, False),
    ".cfg": (None, False),
}

_RES_PATH = re.compile(r"res://[^\"'\s]*")
# 🔴 `[ \t]*` AND NOT `\s*`. `\s` matches a NEWLINE, so with `re.M` the match could begin
# on the blank line ABOVE the declaration and report a line number one too small —
# `psx_dither.gdshaderinc` read 6 for a declaration on 7 in this guard's first run.
# A silently-off-by-one line number is the kind of thing a reader checks once, finds
# wrong, and then stops trusting the whole register over.
_GLOBAL_UNIFORM = re.compile(r"^[ \t]*global[ \t]+uniform[ \t]+\w+[ \t]+(\w+)", re.M)
_INCLUDE = re.compile(r'#include\s+"(res://[^"]+)"')

# 🔴 SIX OF THE EIGHT ACTIONS NEVER APPEAR INSIDE AN `is_action_*` CALL. Scanning call sites
# is what produced the inherited count of 2. The addon's action names travel as `StringName`
# constants — `const CURSOR_ACTIONS: Array[StringName] = [&"camera_up", …]` — and reach
# `is_action_pressed` through a loop variable, so the only place every name is visible is the
# `&"…"` literal itself. Both spellings are scanned and the union is the population.
_ACTION_LITERAL = re.compile(r'&"([a-zA-Z_][a-zA-Z_0-9]*)"')
_ACTION_CALL = re.compile(r'is_action(?:_just)?_(?:pressed|released)\(\s*"([^"]+)"')

# \U0001f534 A `StringName` IS NOT AN INPUT ACTION, AND THE WIDENING IS WHAT PROVED IT.
# `_ACTION_LITERAL` matches EVERY `&"…"`, which was harmless for as long as this guard had
# one subject: every `&"…"` in `exmateria_battlefield` really is an action name. The sprite
# rig has exactly one, `ContentPort.gd:98`'s `n.has_method(&"job_is_monster")` — a METHOD
# name handed to reflection on a duck-typed port node. Scored raw, it reported the rig as
# REQUIRING an input action called `job_is_monster` that no plugin.gd provides, which is a
# confident false RED on an arm whose true reading is 0. An arm that invents debt gets
# ignored exactly as fast as one that hides it (#424).
#
# The narrowing is by SYNTACTIC POSITION, not by name: a literal sitting in the argument
# list of a reflection call is naming a member of some object, and no input action is ever
# spelled that way. It is not a filter over action NAMES — no name is exempted, and
# `is_action_pressed(&"job_is_monster")` would still score — so it cannot manufacture the
# quiet exemption a name list would. Verified against `exmateria_battlefield`: still 8
# required actions over 12 rows, unchanged, because none of its literals sits in one of
# these calls.
_REFLECTION_CALL = re.compile(
    r'\b(?:has_method|has_signal|has_meta|get_meta|set_meta|remove_meta|call|call_deferred'
    r'|callv|rpc|rpc_id|emit_signal|connect|disconnect|is_connected|bind|unbind'
    r'|Callable|get_indexed|set_indexed|get_node_and_resource)\s*\('
)


def _reflection_spans(line: str) -> list[tuple[int, int]]:
    """`[(start, end)]` of each reflection call's argument list, parens balanced.

    Balanced rather than "to the end of the line" so that a real action literal sitting
    AFTER a reflection call on the same line still scores — `if n.has_method(&"x") and
    Input.is_action_pressed(&"camera_up"):` must keep `camera_up`."""
    spans = []
    for m in _REFLECTION_CALL.finditer(line):
        depth, i = 0, m.end() - 1
        while i < len(line):
            if line[i] == "(":
                depth += 1
            elif line[i] == ")":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        spans.append((m.end(), i))
    return spans

# Godot ships the `ui_*` family in every project, bare or not. Everything else in an input
# map is a project declaration by definition, which is what makes this test independent of
# the host's `project.godot` — a guard that asked "is it declared over there?" would go blind
# the day the host stopped declaring it.
_BUILTIN_ACTION_PREFIX = "ui_"


# --- what the WALK PROVIDES (ADR-0203 dec. 3) -----------------------------------------
#
# THE CONTRACT IS A CONST NAME, and it is deliberately narrow. A `plugin.gd` under any of
# the three permitted roots provides `input/<x>` by naming `<x>` first in a top-level entry
# of `const PROVIDED_ACTIONS`, and `shader_globals/<x>` the same way in
# `const PROVIDED_GLOBALS`. The alternative to a literal parse is executing GDScript from
# Python, which this repo has no way to do from a pre-commit hook.
#
# The shape is lifted from `exmateria-sound/tools/check_globals.py:plugin_autoloads()`,
# which answers repo-root ADR-0003 dec. 7 Arm A's version of this question about autoloads.
#
# 🔴 THE BLIND DIRECTION OF THIS PARSER IS THE LOUD ONE, which is the only reason being
# this literal is safe. If it read nothing, every one of the seventeen requirement rows
# would go unmatched and print as UNLISTED with rc=1 — it cannot manufacture a false clean.
# The failure it CANNOT catch is the opposite one: thirteen strings typed into an array no
# code path reaches would green this arm, and the register cannot tell a reached const from
# a decorative one. That is why ADR-0203 dec. 4 forbids this change from shipping alone and
# `addons/exmateria_battlefield/tests/BattlefieldProvidesTest.gd` ships with it — it CALLS
# `provide_into()` against an inspectable surface and asserts all thirteen names land with
# the right type and default. This file is the burn-down; that test is the oracle.
_PROVIDER_CONSTS = (("PROVIDED_ACTIONS", "input/"), ("PROVIDED_GLOBALS", "shader_globals/"))


def _const_entry_names(text: str, const_name: str):
    """First string of each TOP-LEVEL entry of `const <const_name> ... = [ ... ]`.

    🔴 DEPTH-AWARE, BECAUSE THE ENTRIES NEST. `["camera_up", 0.5, [["key", KEY_W]]]` would
    hand a flat `\\["(\\w+)"` regex `"key"` alongside `"camera_up"`, and the register would
    then believe the walk provides an action called `key`. Quote state is tracked for the
    same reason `_literals` tracks it: a bracket or a `#` inside a literal must not move the
    depth or start a comment."""
    m = re.search(r"^const\s+%s\b[^=\n]*=\s*\[" % re.escape(const_name), text, re.M)
    if m is None:
        return []
    i, n = m.end() - 1, len(text)
    depth, names, have_name = 0, [], False
    while i < n:
        ch = text[i]
        if ch == '"':
            j, buf = i + 1, []
            while j < n and text[j] != '"':
                if text[j] == "\\":
                    j += 1
                if j < n:
                    buf.append(text[j])
                j += 1
            if depth == 2 and not have_name:
                names.append("".join(buf))
                have_name = True
            i = j + 1
        elif ch == "#":
            while i < n and text[i] != "\n":
                i += 1
        elif ch == "[":
            depth += 1
            if depth == 2:          # only ever reached from 1: `]` never increments
                have_name = False
            i += 1
        elif ch == "]":
            depth -= 1
            i += 1
            if depth == 0:
                break
        else:
            i += 1
    return names


def provided_by_walk(roots):
    """`{setting key: the plugin.gd that provides it}` across a subject's permitted roots.

    \U0001f534 THE ANSWER IS PER SUBJECT, not per tree, and that is the whole point of taking
    `roots`. It caught a real one: `pixel_aspect` used to be provided ONLY by
    `addons/exmateria_battlefield/plugin.gd`, so it read PROVIDED for the battlefield
    subject and UNPROVIDED for the sprite rig, whose target does not contain that addon.
    A tree-wide `provided` set would have said "provided" for both and reported an
    install that does not exist.

    ⚠️ THAT EXAMPLE IS HISTORY NOW AND THE DISTINCTION IS NOT. ADR-0220 dec. 2 moved
    all six shader globals to the port, which is in every subject's target, so the shader
    half currently answers the same for both subjects -- the divergence closed because it
    was a DEFECT, not because the two questions merged. The `input/` half still diverges
    live: `addons/exmateria_battlefield/plugin.gd` provides eight actions and is absent
    from the rig's target, so the moment the rig requires one this function says
    unprovided and `provided_anywhere()` says provided. Do not collapse them."""
    out = {}
    for root in roots:
        rel = root[len("res://"):] + "plugin.gd"
        q = PROJECT_DIR / rel
        if not q.is_file():
            continue
        text = q.read_text(errors="ignore")
        for const_name, prefix in _PROVIDER_CONSTS:
            for name in _const_entry_names(text, const_name):
                out.setdefault(prefix + name, rel)
    return out


def provided_anywhere() -> dict:
    """`{setting key: the plugin.gd that provides it}` across EVERY addon in the tree.

    \U0001f534 A DIFFERENT QUESTION FROM `provided_by_walk`, and the two must not be confused.
    That one asks "does THIS SUBJECT'S install target provide the name" and is the one the
    arms score; this one asks "does anything in the tree provide it at all", which is what
    a tree-wide arm wants. `check_addon_portability._install_register_provides` is the
    only caller, and since ADR-0220 dec. 3 it feeds an ENFORCING arm (4c: the addon that
    declares a `global uniform` must be the addon that provides it), not a reporting one
    only. The answers differ, and the difference is a finding rather than an
    inconsistency -- `pixel_aspect` read provided HERE and unprovided for
    `exmateria_sprite_rig` for as long as the provide sat in the wrong addon.

    It exists as a named function because the alternative was letting the portability arm
    keep calling `provided_by_walk()` with no argument. That call sits inside a bare
    `except Exception: return {}`, so widening the signature would have emptied it SILENTLY
    and every row there would have quietly reverted to its pre-ADR-0203 wording with
    nothing going red."""
    out = {}
    for q in sorted((PROJECT_DIR / "addons").glob("*/plugin.gd")):
        rel = q.relative_to(PROJECT_DIR).as_posix()
        text = q.read_text(errors="ignore")
        for const_name, prefix in _PROVIDER_CONSTS:
            for name in _const_entry_names(text, const_name):
                out.setdefault(prefix + name, rel)
    return out


def addon_files(addon: str):
    """`[(rel, suffix, text)]` for every scannable file under the subject's root."""
    rows = []
    base = PROJECT_DIR / addon_dir(addon)
    if not base.is_dir():
        return rows
    for q in sorted(base.rglob("*")):
        if not q.is_file() or q.suffix not in SCANNED_SUFFIXES:
            continue
        rows.append((q.relative_to(PROJECT_DIR).as_posix(), q.suffix,
                     q.read_text(errors="ignore")))
    return rows


def scan_assets(files, roots):
    """`[(rel, target, lineno)]` — a `res://` path outside the subject's permitted roots."""
    out = []
    for rel, suffix, text in files:
        line_comment, block = _COMMENT_STYLE.get(suffix, (None, False))
        for lineno, body in _literals(text, line_comment, block):
            for m in _RES_PATH.finditer(body):
                path = m.group(0)
                if path.startswith(roots):
                    continue
                out.append((rel, path, lineno))
    return out


def scan_actions(files):
    """`[(rel, action, lineno)]` — an action name Godot does not provide built-in."""
    out = []
    for rel, suffix, text in files:
        if suffix != ".gd":
            continue
        for i, ln in enumerate(text.splitlines(), 1):
            if ln.lstrip().startswith("#"):
                continue
            spans = _reflection_spans(ln)
            for pat in (_ACTION_LITERAL, _ACTION_CALL):
                for m in pat.finditer(ln):
                    name = m.group(1)
                    if name.startswith(_BUILTIN_ACTION_PREFIX):
                        continue
                    if any(a <= m.start() < b for a, b in spans):
                        continue          # a member name, not an action — see the 🔴 above
                    out.append((rel, name, i))
    return out


def scan_globals(files, roots):
    """`[(rel, name, lineno)]` — every `global uniform` on the addon's compile surface.

    Follows `#include` transitively into the permitted siblings, because a global reaches
    the compile surface through an include exactly as surely as through a declaration —
    `pixel_aspect` and `psx_dither_enabled` are both only ever declared in the port. Rows are
    keyed to the DECLARING file, which is the file a fix would edit -- and since ADR-0220
    dec. 1 that file's addon is also the one that owes the provide, so the key names the
    `plugin.gd` to edit as well."""
    seen, queue = set(), []
    for rel, suffix, text in files:
        if suffix in (".gdshader", ".gdshaderinc"):
            queue.append((rel, text))
    out, visited = [], set()
    while queue:
        rel, text = queue.pop()
        if rel in visited:
            continue
        visited.add(rel)
        for m in _GLOBAL_UNIFORM.finditer(text):
            key = (rel, m.group(1))
            if key in seen:
                continue
            seen.add(key)
            out.append((rel, m.group(1), text[:m.start()].count("\n") + 1))
        for m in _INCLUDE.finditer(text):
            target = m.group(1)
            if not target.startswith(roots):
                continue          # scored by arm 1 instead; not a compile surface we own
            q = PROJECT_DIR / target[len("res://"):]
            if q.is_file():
                queue.append((q.relative_to(PROJECT_DIR).as_posix(),
                              q.read_text(errors="ignore")))
    return sorted(out)


def scan_fork(files):
    """`[(rel, token)]` — fork-only compositor tokens. REPORTED, never scored (dec. 3)."""
    out = []
    for rel, _suffix, text in files:
        hits = sorted({t for t in FORK_TOKENS if t in text})
        if hits:
            out.append((rel, ", ".join(hits)))
    return sorted(out)


def _rows(sites):
    """Sites collapsed onto burn-down keys, in file order."""
    rows = {}
    for rel, target, lineno in sites:
        rows.setdefault((rel, target), []).append(lineno)
    return sorted(rows.items(), key=lambda kv: (kv[0][0], kv[0][1]))


def report(addon: str) -> int:
    roots = permitted(addon)
    burn_down = INSTALL_BURN_DOWN[addon]
    files = addon_files(addon)
    assets = scan_assets(files, roots)
    fork = scan_fork(files)

    # ADR-0203 dec. 3. The scanners report what the addon REQUIRES; the gap is what is
    # required and unprovided. Both halves are printed, because "8 required, 8 provided"
    # and "0 required" are the same 0 on this arm and only one of them is an addon that
    # still works.
    provided = provided_by_walk(roots)
    actions_required = scan_actions(files)
    globals_required = scan_globals(files, roots)
    actions = [s for s in actions_required if "input/" + s[1] not in provided]
    globals_ = [s for s in globals_required if "shader_globals/" + s[1] not in provided]

    print("=" * 78)
    print("SUBJECT %s — %s" % (addon, SUBJECTS[addon]["why"]))
    print("subject: `%s` — %d scannable file(s). ADR-0202 dec. 2's install target is a bare\n"
          "Godot 4.8-COMPOSITOR-FORK project holding exactly these root(s) and nothing\n"
          "else: %s. Anything outside them is scored.\n"
          "This is the addon → host direction; ADR-0164 dec. 4's criteria measure the other\n"
          "one and neither may be reported as the other (dec. 1)."
          % (addon_dir(addon), len(files), ", ".join("`%s`" % r for r in roots)))

    found = {}
    for kind, sites in (("asset", assets), ("action", actions), ("global", globals_)):
        for (rel, target), linenos in _rows(sites):
            found[(rel, kind, target)] = linenos

    print("\narm 1 (`res://` outside the three roots) — ENFORCING: %d row(s) / %d site(s)."
          % (len(_rows(assets)), len(assets)))
    print("arm 2 (input actions Godot does not ship AND no plugin.gd in the walk provides)\n"
          "    — ENFORCING: %d row(s) / %d site(s). The addon REQUIRES %d action(s) over %d\n"
          "    row(s); the walk provides %d of them (ADR-0203 dec. 3)."
          % (len(_rows(actions)), len(actions),
             len({s[1] for s in actions_required}), len(_rows(actions_required)),
             len({s[1] for s in actions_required if "input/" + s[1] in provided})))
    print("arm 3 (`global uniform` on the compile surface that no plugin.gd in the walk\n"
          "    provides) — ENFORCING: %d row(s). The addon REQUIRES %d; the walk provides\n"
          "    %d. A missing one is a COMPILE error, not one file's parse error (ADR-0169)."
          % (len(_rows(globals_)), len(_rows(globals_required)),
             len({s[1] for s in globals_required if "shader_globals/" + s[1] in provided})))
    print("    provided by: %s"
          % (", ".join("`%s` (%d)" % (rel, sum(1 for v in provided.values() if v == rel))
                       for rel in sorted(set(provided.values()))) or "nothing in the walk"))
    print("arm 4 (fork-only compositor tokens) — REPORTING, NO TARGET (dec. 3): %d file(s)."
          % len(fork))

    unlisted = sorted(k for k in found if k not in burn_down)
    burned = sorted(k for k in found if k in burn_down)
    stale = sorted(k for k in burn_down if k not in found)

    if burned:
        print("\nINSTALL REGISTER — %d row(s) / %d site(s) depend on something a bare\n"
              "fork+kernel+port project does not have, and are NAMED in INSTALL_BURN_DOWN\n"
              "with a class and an owner. Not a pass: this is ADR-0202's goal unmet, on\n"
              "record, target 0."
              % (len(burned), sum(len(found[k]) for k in burned)))
        for klass in ("A", "B", "C", "D", "E"):
            rows = [k for k in burned if burn_down[k][0] == klass]
            if not rows:
                continue
            print("\n  ── %s — %d row(s)" % (CLASS_LABEL[klass], len(rows)))
            for key in rows:
                rel, _kind, target = key
                _k, owner, why = burn_down[key]
                at = ", ".join(str(n) for n in sorted(found[key])[:8])
                print("    %s:%s  `%s` x%d\n        %s — %s"
                      % (rel, at, target, len(found[key]), owner, why))

    if fork:
        print("\nFORK-ONLY — %d file(s), REPORTED, no target (ADR-0202 dec. 3). The 4.8\n"
              "compositor fork IS the install target, so these are conformant. They print\n"
              "because this is the one blocker that produces NO ERROR when violated: under\n"
              "stock 4.7 the compositor self-disables and every folded prim silently\n"
              "vanishes, and `Fold.add` off-fork throws (ADR-0186 Amdt 4 §3)." % len(fork))
        for rel, tokens in fork:
            print("  %s  [%s]" % (rel, tokens))

    if "--list" in sys.argv:
        print("\n%s INSTALL_BURN_DOWN rows:" % addon)
        for key, (klass, owner, why) in sorted(burn_down.items()):
            rel, kind, target = key
            print("  [%s] %s  %s `%s`   [%s]\n      %s"
                  % (klass, rel, kind, target, owner, why))

    if unlisted:
        print("\nINSTALL: %d row(s) / %d site(s) depend on something outside the three\n"
              "permitted roots and are NOT on INSTALL_BURN_DOWN (ADR-0202).\n"
              % (len(unlisted), sum(len(found[k]) for k in unlisted)))
        for key in unlisted:
            rel, kind, target = key
            at = ", ".join(str(n) for n in sorted(found[key])[:8])
            print("  %s:%s  %s `%s` x%d" % (rel, at, kind, target, len(found[key])))
        print("\nAnswer by giving the addon what it needs — move the asset in (Class A), take\n"
              "the literal out and keep the contract (Class B), hand the host the mount\n"
              "point (Class C), or PROVIDE the name from a plugin.gd in the walk (Classes D\n"
              "and E, ADR-0203 dec. 1) — or add the row with its class, its owner and, under\n"
              "ADR-0196 dec. 5, the PASS that closes it.")

    if stale:
        print("\nSTALE INSTALL_BURN_DOWN — %d row(s) name a dependency that is no longer\n"
              "there. Delete the row; a burn-down that outlives its debt is a list nobody\n"
              "rereads. ⚠️ A row going stale is what SUCCESS looks like here — check the\n"
              "move before you call it a regression.\n" % len(stale))
        for key in stale:
            rel, kind, target = key
            klass, owner, _why = burn_down[key]
            print("  [%s] %s  %s `%s`   [%s]" % (klass, rel, kind, target, owner))

    if unlisted or stale:
        return 1, len(burned)

    if burned:
        per = {}
        for k in burned:
            per[burn_down[k][0]] = per.get(burn_down[k][0], 0) + 1
        print("\nInstall register: %d site(s) over %d row(s), of a target 0 — %s. Every one is\n"
              "on INSTALL_BURN_DOWN with a class, an owner and a pass, and no listed row has\n"
              "gone stale. ADR-0202 dec. 10: this guard exists BEFORE the moves, because after\n"
              "a move a scanner blind to the old spelling is indistinguishable from a correct\n"
              "one."
              % (sum(len(found[k]) for k in burned), len(burned),
                 ", ".join("%s %d" % (k, per[k]) for k in sorted(per))))
    else:
        print("\n✅ %s INSTALL REGISTER CLEAR — the addon depends on nothing outside a bare\n"
              "fork+kernel+port project (ADR-0202). Axis B is 0 for this subject." % addon)
    return 0, len(burned)


def main() -> int:
    _check_registers()
    print("check_addon_install.py — ADR-0202, the INSTALL channel (axis B)")
    print("  subject: %d addon(s) — %s" % (len(SUBJECTS), ", ".join(sorted(SUBJECTS))))
    print("\n🔴 THIS IS AXIS B (addon → host), NOT criterion 4. Axis A\n"
          "   (`check_lattice_scene`, ADR-0205) is a different question and a different\n"
          "   number. Never report either as the other — ADR-0202 dec. 1.\n")

    results = {addon: report(addon) for addon in sorted(SUBJECTS)}
    print("\n" + "=" * 78)
    print("check_addon_install: axis B per addon — %s"
          % ", ".join("%s %d%s" % (a, n, " (BURN-DOWN BROKEN)" if rc else "")
                      for a, (rc, n) in sorted(results.items())))
    print("   That number is the install debt and its target is 0 (ADR-0202 dec. 10). A\n"
          "   non-zero reading with no `BURN-DOWN BROKEN` beside it means every row is\n"
          "   NAMED — the register doing its job, NOT the addon being installable.")
    print("   ⚠️ THAT IS AXIS B ALONE — say axis A's criterion 4 too\n"
          "   (`check_lattice_scene`), never one as the other (ADR-0202 dec. 1).")
    return 1 if any(rc for rc, _ in results.values()) else 0


if __name__ == "__main__":
    sys.exit(main())
