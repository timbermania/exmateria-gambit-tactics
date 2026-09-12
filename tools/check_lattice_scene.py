#!/usr/bin/env python3
"""Guard: the resource-path register — ADR-0164 dec. 4 criterion 4, built by ADR-0205.

    uv run python tools/check_lattice_scene.py [--list]

THE RULE (ADR-0205 dec. 2). For each SUBJECT addon, no file outside `addons/<subject>/`
may name an `res://addons/<subject>/…` path, except at a DECLARED MOUNT. Target 0
undeclared reaches. Sites burn down BY NAME (#424 — an exclusion expressed as a filter
manufactures its own debt and cannot tell a triaged site from one that merely matches).

🔴 THE SUBJECT IS A MAPPING, NOT ONE STRING (ADR-0217 dec. 4). It was
`ADDON = "addons/exmateria_battlefield/"` until #737, so criterion 4 was a
Battlefield-only register — closed at 0 on ADR-0209 and therefore silent while the next
extraction's scene publish went ungraded entirely. `SUBJECTS` now names every graded
addon with the reason it is graded, and every derived value follows it: the `res://`
prefix, the corpus exclusion, the symlink probe, the header and the verdict. Each subject
gets its own section, its own two arms and its own verdict, and the process rc is the OR
— because one addon at 0 and another carrying debt are two readings, not an average.

Each subject's corpus excludes ITS OWN addon and no other, so a SIBLING addon naming a
path into this one is still a site. That is deliberate: it is a real reach, and hiding
every addon from every scan would put it in a hole instead of on a burn-down. It is also
why the subjects report different `file(s) scanned` counts for the same tree.

🔴 WHY THIS IS AXIS A AND NOT THE INSTALL TERM. `check_lattice_publish` and ADR-0196
dec. 8 both called this population "the install term" and both were wrong about the
DIRECTION. A HOST file naming `res://addons/exmateria_battlefield/assembly/MapComposer.gd`
is the host reaching INTO the addon: same direction as `var c: MapComposer`, same failure
mode, same criterion — only a different spelling. Axis B (ADR-0202,
`check_addon_install`) asks what breaks when you remove the HOST, and nothing here does:
delete the whole host tree and every row below stays behind, in the host. Axis B reads
**0 / 0** and this register does not touch it. Report both numbers, never either as the
other (ADR-0202 dec. 1).

The confusion had a cause worth keeping: "the addon does not parse where the declaring
addon is absent" is a true sentence about a HOST file with the ADDON removed, and it
sounds like an install claim because *install* is the word attached to absence.

WHY THIS IS A SEPARATE REGISTER AND NOT PART OF CRITERION 1 (ADR-0205 dec. 2).
Criterion 1's subject is the COMPILED SYMBOL surface and its instrument is a `class_name`
scan of `.gd`. This one's subject is the RESOURCE PATH surface across `.tscn`, `.tres`,
`.gd` and `.gdshader`. Merging them is ADR-0131 dec. 7's own named failure — one number
answering two questions. They run side by side; both must be run.

WHY THE REGISTER WAS BUILT BEFORE THE COLLAPSE (ADR-0205 dec. 7, applying ADR-0192
dec. 1 and ADR-0196 dec. 1 a third time). 115 of the opening 138 rows — 83% — were
`MapComposer.gd`. After a move, a scanner blind to the old spelling is indistinguishable
from a correct one, so `SCENE_BURN_DOWN` froze the population first and the collapse was
graded by watching those 115 rows go STALE. ✅ THEY DID, ALL 115, in ADR-0207's first
commit, which touched no line of this file. That is the only evidence that separates
"the reach is gone" from "the scanner stopped seeing it", and it exists because the
register went first.

WHY `tests/` ENFORCES HERE, unlike criterion 1's arm 2 (ADR-0205 dec. 6). ADR-0196 dec. 3
made `tests/` a reporting arm because `classify()` returns `None` for every test file, so
a threshold would be guesswork. THAT REASON DOES NOT TRANSFER. A path is not a bucket:
`res://addons/exmateria_battlefield/…` identifies the addon with no classifier involved,
and "does this file name that path" has the same answer in `tests/` as in `src/`. It
matters: `src/` holds **2** of the 139 sites and `tests/` holds **122**, so a
reporting-only `tests/` arm would leave 88% unscored and this guard would read as nearly
closed on the day it was built.

ARMS.

  arm 1  ENFORCING, burn-down, both directions. Every path reach outside the addon that
         is not a DECLARED MOUNT. A row prints above the OK line under a heading that
         says it is not a pass; an UNLISTED site fails, and a LISTED row whose site is
         gone goes STALE and fails. Both arms are direction-tested — a ratchet has two
         arms, and the grade is on the REPORTED LINE, never on `rc`.

  arm 2  REPORTED, scores nothing. `DECLARED_MOUNTS` both ways, plus the namer count per
         declared target. A mount declared for a target nothing names shows up as dead;
         a declared target with many namers shows how much of its fan-out is still debt.
         Enforcing this direction would make DELETING a mount red the guard, which is
         backwards — the same argument ADR-0196 dec. 4 makes for the declared-published
         set.

  arm 3  REPORTED, scores nothing toward criterion 4 — and STILL ENFORCED (ADR-0222
         dec. 1). `SCENE_ORACLES`: host tests that name an addon path in order to MEASURE
         the seam. Three machine conditions gate every row and each can red it later —
         under `tests/`, still REACHING host territory by a `res://` path or a host
         `class_name` (so ADR-0194 cannot take it into the addon — Amendment 2, #871),
         and still live. See the register's own comment for why the split exists.

🔴 CRITERION 4 IS ARM 1's NUMBER ALONE, AND ARMS 2 AND 3 ARE PRINTED BESIDE IT, NEVER
ADDED (ADR-0222 dec. 3 and dec. 6). The rig read **7** before this split, **1 (+6
oracle)** after it, and **0 (+6 oracle, 2 mount)** once its last production row was declared
a mount — and NO LINE OF THE TREE MOVED FOR ANY OF THE THREE. Every one of those drops is a
fact about the SCANNER, which is exactly what ADR-0205 dec. 7 says a register must never let
a reader mistake for a fact about the tree. The summary line carries all three terms so the
7 is recoverable from the sentence a reader quotes. \u26a0\ufe0f THE 0 IS AN EXEMPTION, NOT A
DRAIN: `assets/materials/unit.tres` still names `render/unit.gdshader` and always will,
because a shader-less `ShaderMaterial` drops all 39 of its authored `shader_parameter/`
values at parse time — measured, see the mount's own note. WHY THE SPLIT: six of the seven could not be paid by any move — both oracle tests
reach `src/`, so ADR-0194 cannot take either into the addon — and this family already rules
that a register which cannot reach its own target is a defect in the REGISTER, not debt in
the tree. `check_addon_install`'s arm 4 declines to score the fork in those words: *a
register that scored its own target could never reach 0 and a burn-down that cannot reach 0
stops being read.*

WHAT THIS GUARD CANNOT SEE, stated because every blind spot on this map has scored zero
and every one has been real:

  - **A path assembled at runtime.** `"res://addons/" + name + "/foo.gd"` names nothing
    this regex matches. Measured at build time: **zero** constructed battlefield paths
    outside the addon. One file holds a bare `res://addons/` literal —
    `tests/ShaderCompileTest.gd:68`, `path.begins_with("res://addons/")` — which READS an
    already-resolved path rather than building one, so it is correctly not a site.
  - **A reach by UID.** A `.tscn` `ext_resource` may carry `uid="uid://…"` alongside
    `path=`, and 🔴 GODOT PREFERS THE UID — BUT ONLY WHILE IT RESOLVES. A file that
    dropped its `path=` attribute would keep working and score 0 here. Both halves of
    that model were measured on the 4.8 fork by #736, because the earlier note stated
    only the first half and a mover written to it breaks the two files extraction #4 is
    about:

      * **A live `uid=` wins, silently.** `assets/materials/unit.tres`'s `type1_tex`
        row, `uid=` left on `01.tga` and `path=` repointed at `WEP1.tga`, loads
        `res://assets/sprites/textures/01.tga` with **no warning**. So editing only
        `path=` IS the no-op the earlier note claimed.
      * **A dead `uid=` falls back to `path=`, loudly.** `ext_resource, invalid UID:
        … - using text path instead` (`resource_format_text.cpp:501`). So editing only
        `uid=` is **not** a no-op — it either retargets the line or downgrades it to the
        path. Two rows shipped in exactly that state (ADR-0217 dec. 18); #736 fixed both.

    And most of the corpus has no uid to prefer. Measured at build time: **1091 of 1091**
    `[ext_resource]` lines in `corpus()` carry `path=`, and only **149** carry a `uid=`
    at all — so for 942 of them `path=` is the ONLY resolver and a path-only fix is
    complete. A fix on one of the 149 must still swap `uid=` AND `path=`.

    Dead-UID scan of the corpus, #736 (S6 of ADR-0217 asked for it and nobody had
    looked): **2 dead, both fixed, 0 remaining**, and **0** rows whose `uid=` resolves
    to a target other than its own `path=`. Same numbers over the whole tree with
    symlinked directories followed — 1108 lines, 151 with `uid=`, 0 dead — so the
    reading does not depend on which worktree it is taken in.
  - **A `class_name` type reference.** By construction — that is criterion 1, and
    `check_lattice_publish` scores it. Neither register subsumes the other.
  - **`.godot/`.** The import cache is generated, is gitignored, and mirrors real
    references; scanning it double-counts. Pruned by directory AND re-checked on the
    relative path, because `lstrip("./")` strips CHARACTERS and silently readmitted 32
    cache hits during this register's own measurement.
  - **A SYMLINKED DIRECTORY.** `Path.rglob` does not recurse into one
    (`recurse_symlinks=False`, Python 3.13), so `addons/exmateria_sound/`,
    `addons/exmateria_spu/`, `assets/maps/` and ~20 more trees are outside the walk.
    Following them was REJECTED: `assets/maps` is absent from a bare worktree, so the
    enforced count would read SMALLER there and the same commit would score two numbers.
    Instead `symlink_probe()` checks each symlinked tree for the prefix and REPORTS the
    count, scoring nothing — so this cannot go non-empty silently. Measured at build
    time: **0 files** across every symlinked tree. Found by
    `test_a_sibling_addon_is_PROBED_not_walked`, which was written asserting the
    opposite.

  🔴 A SITE IS A (file, target) PAIR, NOT A LINE. `GPUArena.tscn` names `MapComposer.gd`
  once; `EffectViewer.tscn` names `TileCursor.tscn` once. Where a file names the same
  target on several lines the row holds every line number and the site counts once —
  because the fix is one edit per (file, target), and counting lines would make a
  formatting change move the number.
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# \U0001f534 ADR-0217 dec. 4. THIS WAS `ADDON = "addons/exmateria_battlefield/"`, ONE STRING,
# and criterion 4 was therefore a Battlefield-only register — empty and closed
# (ADR-0209) while the next extraction's scene publish went unscored entirely. One
# subject per addon this register grades, each with the reason it is graded. Every
# derived value follows it: the `res://` prefix, the corpus exclusion, the symlink
# probe's exclusion, the printed header and the verdict.
#
# A SUBJECT WHOSE FOLDER DOES NOT EXIST YET IS THE POINT, NOT A DEFECT. ADR-0205
# dec. 7's account of the last extraction is that 83% of the opening rows were one
# file, and the only evidence separating "the reach is gone" from "the scanner
# stopped seeing it" was watching 115 frozen rows go STALE. So the row is seeded
# BEFORE the move (ADR-0192 dec. 1, a fourth time) and its DEAD -> live transition
# is the witness. Arm 2 is reported-only, so a dead mount scores nothing.
# 🔴 CRITERION 4's TARGET IS NOT 0 FOR EVERY SUBJECT, AND PRETENDING IT IS MAKES THE
# NUMBER UNREADABLE (#1249, 2026-09-12). This family already rules — in
# `check_addon_install`'s arm 4, quoted in this file's own header — that *a register that
# scored its own target could never reach 0 and a burn-down that cannot reach 0 stops being
# read*, and that **a register which cannot reach its own target is a defect in the REGISTER,
# not debt in the tree.** `exmateria_effects` is the first subject where that bites.
#
# MEASURED, not estimated: of its 52 rows, **17 target a `.gdshader` or a `.gdshaderinc`**.
# #1249's two routes are (1) publish the name on the facade and (2) move the test into the
# addon under ADR-0194. NEITHER can route a shader path: no GDScript constant routes an
# `#include` (ADR-0212 dec. 5), and a `tools/` probe is not a test, so ADR-0194 does not move
# it. Those 17 are unpayable by any named route and 0 is unreachable while they exist.
#
# So the floor is DECLARED and it is CHECKED IN BOTH DIRECTIONS. A count below the floor
# means a route was found that this note says does not exist — the floor is then wrong and
# must be lowered deliberately, with the argument. A new undeclared row is still arm 1's,
# unchanged. The floor is a claim about the SHAPE of the residue, not permission to stop.
#
# ⚠️ THE OTHER 35 ROWS ARE NOT EXCUSED BY THIS. They target `.gd` files and route 1
# WOULD pay them — at the price of ~15 permanent public names on the facade, which is
# exactly the trade gl-ADR-0295 dec. 1 weighed and DECLINED. #1249 records that decision;
# this floor records why the remainder cannot be zero even if it were reversed.
CRITERION4_FLOOR: dict[str, int] = {
    "exmateria_battlefield": 0,
    "exmateria_effects": 17,
    "exmateria_sprite_rig": 0,
}


SUBJECTS: dict[str, str] = {
    "exmateria_battlefield":
        "ADR-0205 — the extraction #3 addon. Criterion 4 reads 0 and closed on "
        "ADR-0209; the three rows below are its declared mounts.",
    "exmateria_effects":
        "gl-ADR-0295 dec. 1 — extraction #7. THE MOVE LANDED (#1225) and this subject "
        "opens NON-ZERO BY DECISION, which no previous subject has done. The façade "
        "publishes the 21 names production reaches; the fifteen members reached only from "
        "`tests/` and `tools/` are deliberately unpublished, so they are bound by "
        "`res://addons/exmateria_effects/…` path instead — and this register is where that "
        "trade is DECLARED rather than hidden. Extraction #4 took the opposite reading of "
        "the same trade; ADR-0295 dec. 1 rules that what is not defensible is arriving at "
        "pass 9 with the number unexplained.\n"
        "  \U0001f534 SO READ THE THREE TERMS, NEVER THE FIRST ALONE. Criterion 4 is arm 1's "
        "production number; the oracle and mount counts print beside it (ADR-0222 dec. 3). "
        "The four `project.godot` `[autoload]` rows are DECLARED MOUNTS — an `[autoload]` "
        "line can only be written by the consuming project and stays the host's whoever "
        "ships the script (ADR-0262 dec. 6) — and ADR-0288 dec. 7 takes them 4 -> 2 at "
        "#1223/#1224.",
    "exmateria_sprite_rig":
        "ADR-0217 dec. 4 — extraction #4. THE MOVE LANDED (#744) and the mount is "
        "live. P9 predicted this subject would read exactly 1 site, that site being "
        "the mount; it opened at 1 declared mount + 11 on the burn-down, so P9 IS "
        "FALSIFIED and the rows below are the report ADR-0217's own criterion asks "
        "for rather than an absorption. The dead one-shot's four rows are DRAINED, "
        "taking it 11 -> 7. "
        "(The count moved twice inside #744 and both moves are the same lesson: the "
        "class_name strip converted three BARE-IDENTIFIER reaches in that dead file "
        "into three scored `preload()` paths, 8 -> 11. A path-based guard cannot see "
        "an identifier and can see a preload, so retiring a global GROWS this "
        "register — that is a real cost of the win, booked here rather than netted "
        "off against it.)\n"
        "  \U0001f7e2 THE SEVEN WERE TWO POPULATIONS AND THE TARGET-0 READING SUMMED "
        "THEM; ADR-0222 dec. 1 SPLIT IT. Criterion 4 is the PRODUCTION channel and reads "
        "0 — but 0 BY EXEMPTION, NOT BY A DRAIN, and the difference is the whole point of "
        "ADR-0205 dec. 7. The one production row was `assets/materials/unit.tres` naming "
        "the rig's shader; ADR-0222 P1 predicted it would drain, the shape settled on "
        "2026-09-02 was to inject the shader from `UnitAssets.base_material()` the "
        "way `for_variant` already injects the base, and the measurement refused it: "
        "`ShaderMaterial::_set` is guarded by `shader.is_valid()`, so a shader-less "
        "`.tres` loses all 39 of its authored `shader_parameter/` values AT PARSE TIME "
        "(39 of 39 null before the injection and after it), and a `ResourceSaver` round "
        "trip writes back 0 of 39 silently. It is a DECLARED MOUNT now (ADR-0222 "
        "Amendment 1) — the file still names the addon and always will. The other "
        "six are ORACLES on arm 3, reported and scoring nothing: two host tests that "
        "name a path in order to MEASURE the seam. Their permanence is MEASURED now "
        "rather than asserted — both name host paths (`ScenarioDeadUnitFadeTest` "
        "preloads `res://src/scenarios/ScenarioVM.gd`; `UnitMaterialVariantTest` names "
        "`ScenarioVM.gd`, `FormationScene.gd` and `res://assets/materials/unit.tres`), "
        "so ADR-0194 cannot take either into the addon, and arm 3 re-checks that every "
        "run so the argument EXPIRES instead of standing on a reviewer's word. "
        "\u26a0\ufe0f 7 -> 1 -> 0 IS THE REGISTER MOVING TWICE, NOT THE TREE MOVING ONCE "
        "(ADR-0205 dec. 7) — the summary prints `0 (+6 oracle, 2 mount)` so both the 7 "
        "and the exemption stay recoverable from the line a reader quotes.",
}

SCAN_EXTS = {".tscn", ".tres", ".gd", ".gdshader", ".cfg", ".godot"}
SKIP_DIRS = {".godot", ".git", ".import", "node_modules"}

_EXT_RESOURCE = re.compile(r'\[ext_resource\s+type="([A-Za-z0-9_]+)"')

# A `res://` path into HOST territory — not into any addon, and not into `tests/`. Arm 3's
# condition 2 uses it and nothing else does. See `oracle_blockers()` for why `tests/` is out.
_HOST_PATH = re.compile(r"res://(?!addons/)(?!tests/)[A-Za-z0-9_\-./]+")

# \U0001f534 THE SECOND SPELLING OF THE SAME REACH (ADR-0222 Amendment 2, #871). A host
# dependency is not always a `res://` literal: a bare `ClassName` resolves through Godot's
# global class registry and reaches the file that declares it, with no path anywhere in the
# caller. `_HOST_PATH` cannot see that, and the blind spot scored NON-ZERO —
# `tests/MapDitherSnapTest.gd` names two battlefield shader paths in order to measure the
# seam and reaches host territory ONLY through `MapRenderDebugPanel`, so condition 2 read
# "this test could move into the addon" about a test that instantiates a host debug panel.
# This module's own header makes exactly this argument about axis A: *same direction, same
# failure mode, same criterion — only a different spelling.*
_CLASS_NAME_DECL = re.compile(r"^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)", re.M)
# GDScript comments only. `_HOST_PATH` scans RAW text and keeps doing so — changing it would
# move rows this amendment is not about — but a class name is a bare word and prose names
# classes constantly, so the class half is scanned with comments stripped. That is the
# CONSERVATIVE direction for a VETO: a narrower blocker set admits fewer rows, never more.
_GD_COMMENT = re.compile(r"#.*$", re.M)

# Filled by `host_classes()` on first use and RESET at the top of `main()`. The reset is
# not hygiene: `test_check_lattice_scene.py` seeds files into the REAL tree and calls
# `main()` several times in one process, so a registry cached across seeds would make a
# seeded host class invisible to the very arm that seeds it.
_HOST_CLASSES: dict[str, str] | None = None


def addon_dir(addon: str) -> str:
    """`addons/x/` — one spelling of the exclusion, used by the corpus and the probe."""
    return "addons/" + addon + "/"


def prefix(addon: str) -> str:
    """`res://addons/x/` — the string a host file has to hold to be a site."""
    return "res://" + addon_dir(addon)


def path_re(addon: str) -> re.Pattern:
    return re.compile(re.escape(prefix(addon)) + r"([A-Za-z0-9_\-./]+)")

# --- arm 2: the declared mounts. REPORTED, scores nothing. -----------------------------
# A host-owned indirection file that is PERMITTED to name an addon path. This is the only
# escape hatch from arm 1 and it is a reviewed literal, not a filter.
# \U0001f534 KEYED BY ADDON, and every `SUBJECTS` key must appear — `_check_registers()`
# raises otherwise. A subject added here and not to `SCENE_BURN_DOWN` (or the other way)
# would score the new addon as owing nothing, SILENTLY, which is the failure
# `check_addon_globals`'s own test has an arm for.
DECLARED_MOUNTS: dict[str, dict[tuple[str, str], tuple[str, str]]] = {
 "exmateria_effects": {
    # The four `[autoload]` scripts, and they are mounts for a reason no move can change:
    # `project.godot` is the CONSUMING project's file. ADR-0288 dec. 7 takes the four to
    # 🔴 ONE OF THESE ROWS WENT AT #1224, NOT TWO. The prediction was that merging the
    # two tint overlays would stale two mounts; it staled ONE. #1223 RETARGETED the
    # `UnitTintOverlay` row (the host still writes that `[autoload]` line, it just names
    # `TintedSurfaces` now) and #1224 DELETED the `MapTintOverlay` one, because the script
    # it named is gone. A rename is not a stale; only a deletion is. The second predicted
    # removal was `EffectMultiMeshPool`'s, on the argument that a node-path reach needs no
    # entry — measured false at #1224, see `addons/exmateria_effects/plugin.gd`'s header.
    # Arm 2 is reported-only, so a mount going dead scores nothing and reds nothing.
    ("project.godot", "overlay/ScreenEffectOverlay.gd"):
        ("ADR-0262 dec. 6",
         "the full-screen tint overlay — one of the addon's four `[autoload]` scripts. An `[autoload]` line can only "
         "be written by the CONSUMING project's `project.godot`, so the entry stays the "
         "host's whoever ships the script, and `addons/exmateria_effects/plugin.gd` "
         "registers the same name for a consumer that does not declare it. Declared as a "
         "mount rather than as debt because there is no edit to the addon that removes a "
         "host's own project setting."),
    ("project.godot", "overlay/TintedSurfaces.gd"):
        ("ADR-0262 dec. 6",
         "the tinted-surface registry, called `UnitTintOverlay` until #1223 renamed it "
         "(ADR-0288 dec. 7 / ADR-0290 dec. 7; #1224 merges the map's in as the erased-key "
         "case and takes these four `[autoload]` lines to two) — one of the addon's four "
         "`[autoload]` scripts. \u26a0\ufe0f A RENAME RETARGETS THIS ROW, it does not stale it: the "
         "host still writes the line and the reach is the same reach, so deleting the row "
         "would drop a live mount from the register. An `[autoload]` line can only "
         "be written by the CONSUMING project's `project.godot`, so the entry stays the "
         "host's whoever ships the script, and `addons/exmateria_effects/plugin.gd` "
         "registers the same name for a consumer that does not declare it. Declared as a "
         "mount rather than as debt because there is no edit to the addon that removes a "
         "host's own project setting."),
    ("project.godot", "render/EffectMultiMeshPool.gd"):
        ("ADR-0262 dec. 6",
         "the shared transparent-prim pool, also reached by NODE PATH from two members — one of the addon's four `[autoload]` scripts. An `[autoload]` line can only "
         "be written by the CONSUMING project's `project.godot`, so the entry stays the "
         "host's whoever ships the script, and `addons/exmateria_effects/plugin.gd` "
         "registers the same name for a consumer that does not declare it. Declared as a "
         "mount rather than as debt because there is no edit to the addon that removes a "
         "host's own project setting."),
 },
 "exmateria_battlefield": {
    ("assets/scenes/CombatCamera.tscn", "camera/PlayerCamera.tscn"):
        ("ADR-0204 dec. 1",
         "the inherited-scene mount. A host scene based on the addon's camera, carrying "
         "the host's CombatUI, so every node path stays byte-identical. Collapsed 107 "
         "direct consumers to 1."),
    ("assets/scenes/ProceduralMap.tscn", "assembly/MapComposer.gd"):
        ("ADR-0207 dec. 1",
         "the host's map-composer mount. A scene whose ROOT is the composer node — same "
         "name, type, place and defaults — instanced by the 109 host scenes that each "
         "used to declare it themselves. Collapsed 115 direct consumers to 1. NOT an "
         "inherited scene: nothing adds a child and the composer node has no internal "
         "structure, so ADR-0204's inheritance half buys nothing here (ADR-0207 dec. 2)."),
    ("assets/scenes/CombatCursor.tscn", "cursor/TileCursor.tscn"):
        ("ADR-0207 dec. 5",
         "the host's tile-cursor mount. An INHERITED scene, ADR-0204's form and not "
         "dec. 2's: the base has a `HighlightMesh` child the script drives, so a wrapper "
         "would flatten it or bury it a level deeper and move every `TileCursor/...` "
         "path. Collapsed 7 direct namers to 1 — three host scenes by `ext_resource`, "
         "three tests by `preload` and one by a `load()`ed string. Adds nothing today, "
         "deliberately: the seam is host-owned before a host has something to hang on "
         "it. ADR-0206 dec. 2 left `$TileCursor` authored in the scene, which is why "
         "publishing `CursorRig` closed criterion 1 without touching any of these. "
         "NAMED `CombatCursor`, not `TileCursor`: the moved file's original host path "
         "is a move-manifest row, and a mount re-created AT that path reds "
         "`check_move_manifest.py` arm 1 as `BOTH src and dst exist (copied, not "
         "moved)`. Measured, not predicted. `CombatCamera.tscn` dodged the same "
         "collision by accident of naming; this one is deliberate."),
 },
 "exmateria_sprite_rig": {
    ("assets/scenes/Unit.tscn", "UnitRig.tscn"):
        ("ADR-0217 dec. 3",
         "the rig's scene mount, SEEDED BEFORE THE MOVE and DEAD until #744 lands it. "
         "`Unit.tscn` is already doing ADR-0204's thing without saying so: 114 files "
         "reference it (5 production, 109 `tests/`), and after the move it is the only "
         "file in the tree naming an addon path — 114 consumers collapsed to 1, and the "
         "109 tests never learn the addon exists. The façade deliberately does NOT also "
         "publish the scene: `const UnitRig = preload(...)` would resolve fine and give "
         "the rig two spellings of one publish, so pass 9 would have two numbers for one "
         "question (ADR-0205 dec. 2 forbids exactly that merge for the guards). "
         "\u26a0\ufe0f THE TARGET STRING IS #744's TO SETTLE — the addon's internal layout "
         "is not decided yet, and this row names the rig scene ADR-0217 dec. 3 describes. "
         "Until that commit the row reads DEAD!, scores nothing, and its flip to `live` "
         "is the evidence the mount landed rather than evidence the scanner changed "
         "(ADR-0205 dec. 7). P9 predicts this addon's criterion 4 seeds at exactly 1 "
         "site and that the one row is THIS mount, never a burn-down row."),
    ("assets/materials/unit.tres", "render/unit.gdshader"):
        ("ADR-0222 Amdt 1",
         "the host's authored base material, and the LAST production row — declared a "
         "mount on 2026-09-03 because the drain ADR-0222 P1 predicted was MEASURED "
         "and is not available. 🔴 THE MEASUREMENT, not an argument: "
         "`ShaderMaterial::_set` accepts a `shader_parameter/x` assignment ONLY while "
         "`shader.is_valid()`, so a `.tres` that does not name a shader loses every "
         "parameter AT PARSE TIME. `tools/probe_unitres_shader_drain.gd` authored the "
         "shader-less copy and read it back: 39 of 39 parameters null BEFORE the "
         "injection, still 39 of 39 null after setting `mat.shader` — the values are "
         "gone before any code of ours can inject anything. Its half (b) is worse: "
         "`_get_property_list` enumerates the CURRENT shader's uniforms, so the "
         "shader-less material listed 0 `shader_parameter` properties and a "
         "`ResourceSaver.save()` round trip wrote back 0 of 39, SILENTLY. So the "
         "`ext_resource` is not one address among the file's forty lines; it is the only "
         "thing that makes the other thirty-nine loadable. This row is an EXEMPTION and "
         "the shape fits: `UnitAssets.BASE_MATERIAL` already collapsed four independent "
         "`load()` sites to one const (#741), the file is the single host-owned "
         "indirection every consumer goes through, and it is the only PRODUCTION namer "
         "of the target. ⚠️ CRITERION 4 GOING 1 -> 0 HERE IS THIS ROW MOVING, NOT "
         "THE TREE (ADR-0205 dec. 7) — which is why the summary line now prints the mount "
         "count beside the oracle count."),
 },
}

# --- arm 1: the burn-down. ENFORCING, target 0. ----------------------------------------
# \U0001f7e2 EMPTY, AND THAT IS THE TARGET REACHED — criterion 4 is 0 (ADR-0209, ADR-0207
# dec. 5 + dec. 6). The last three rows were `CURSOR_IMPL` x2 and `CURSOR_SHADER`, and each
# was paid by a DIFFERENT route from ADR-0208 dec. 2's menu rather than by one rule:
# `TileCursorBobTest` moved into the addon (ADR-0194), `CursorPanelTuneFieldTest` deleted
# its reach outright once ADR-0208 dec. 1 showed it was a class LOAD the subject already
# forces, and the CLUT preview shader went back to the host, which is where the manifest
# says it came from. `CURSOR_SHADER`'s own \u26a0\ufe0f said to price the viewer move before
# assuming it was as cheap as the tests' — priced, and it was not.
#
# \U0001f534 KEEP THIS DICT AND ITS BOTH-ARM TESTS. Empty is a MEASUREMENT, not a finished
# job: arm 1 is what makes a NEW unnamed reach red rather than silently join a filter, and
# `test_check_lattice_scene`'s ratchet arms seed their own rows, so they still say the same
# thing over an empty list. Deleting the register because it reads 0 is how the number
# starts climbing again with nothing to report it.
# \U0001f534 KEYED BY ADDON, same as `DECLARED_MOUNTS`, and every `SUBJECTS` key must
# appear. `exmateria_sprite_rig` was written here as "opens EMPTY and stays empty through
# #744: P9 predicts its one site is the declared mount above, so a row appearing here
# would falsify P9 rather than record debt, and arm 1 is what makes that visible instead
# of silent."
#
# \U0001f534 IT DID. #744 LANDED AND P9 IS FALSIFIED — 1 declared mount and NINE rows
# (2026-09-01). It read EIGHT when the move landed; the ninth arrived three commits later
# and is #744's OWN, which is the more useful half of the finding — see the third bullet.
# The mechanism worked exactly as designed: arm 1 named all of them instead of
# a filter swallowing them, and the sentence above is why they are recorded here rather
# than absorbed. The move itself paid 14 of the opening 22 sites — the mount collapsed
# `Unit.tscn`'s four to one, the exerciser scene moved INTO the addon with its two, six
# `preload()` lines went to the façade's symbol channel, and one test stopped spelling a
# path it could ask a symbol for. What is left divides three ways and only ONE of the
# three is drainable:
#
#   \u2022 SIX rows are ARGUED PERMANENT, not deferred. They are the two host tests that
#     are the INDEPENDENT ORACLES for the unit shader variants, and ADR-0189 dec. 8
#     already granted `ScenarioDeadUnitFadeTest` exactly this on exactly this argument:
#     routing the yardstick through the module makes the guard compare the module to
#     itself. ADR-0194's addon-owned-test shape cannot take either of them — neither is an
#     addon test. `ScenarioDeadUnitFadeTest` drives `src/scenarios/ScenarioVM.gd` and
#     `UnitMaterialVariantTest` reads `assets/materials/unit.tres`, so both would drag a
#     host file into a stranger rig that is supposed to have no host.
#   \u2022 ONE row is a HOST RESOURCE and a `.tres` cannot take an injection. ADR-0202's
#     Class B answer — a `ProjectSettings` key with an empty default and a `push_error` —
#     needs a file that can RUN. `unit.tres` is data; its `ext_resource` line is resolved
#     by the loader before any code of ours exists. Payable only by deleting the authored
#     base material, which is `UnitAssets.BASE_MATERIAL` and four call sites' single
#     source (#741).
#     \U0001f534 SETTLED 2026-09-03, AND NOT THE WAY THIS BULLET GUESSED. A third way
#     was chosen on 2026-09-02 and is ADR-0222's answer to its own dec. 4 — keep the
#     file, drop its `shader =` line, and have `UnitAssets` inject the shader after
#     `load()`. Measured
#     (`tools/probe_unitres_shader_drain.gd`) and it does not work, for a reason no
#     reading of this bullet predicted: the parameters do not survive to the injection.
#     `ShaderMaterial::_set` is guarded by `shader.is_valid()`, so a shader-less `.tres`
#     drops all 39 `shader_parameter/` lines AT PARSE TIME — 39 of 39 read back null
#     before the injection and 39 of 39 after it. The `ext_resource` is what makes the
#     rest of the file mean anything. The row is a DECLARED MOUNT now, above.
#   \u2022 FOUR rows are ONE DEAD ONE-SHOT, and they are the only drainable ones. It began
#     as one row. Stripping the three resource classes' global `class_name`s later in the
#     same pass — a boot proved `map.tres` still loads without them — turned that file's
#     three BARE IDENTIFIERS into three `preload()` PATHS, because it constructs all three
#     and has to keep parsing. A guard that scores PATHS cannot see a bare global, so the
#     strip moved three reaches from an UNSCORED channel into a SCORED one and this
#     register grew as a direct consequence of a name being retired. Worth naming rather
#     than netting off: the two channels are not interchangeable, and a pass that reported
#     only its wins would have booked this as 23 -> 20 with no cost line anywhere. All four
#     drain together the day the one-shot is deleted. See their notes.
#
# The honest reading of P9 is that it was written against the SCRIPT surface, where the
# façade answers everything, and did not price the two surfaces a symbol cannot reach: a
# `.tres` `ext_resource` and a test that must name a file as TEXT.
SCENE_BURN_DOWN: dict[str, dict[tuple[str, str], tuple[str, str]]] = {
    "exmateria_battlefield": {},
    "exmateria_effects": {
        # 🔴 SIXTY ROWS ON DAY ONE, AND THE NUMBER IS THE DECISION RATHER THAN A SLIP
        # (gl-ADR-0295 dec. 1) — SIXTY-ONE since #1218, whose row says why it is declared
        # here instead of published. The façade publishes the 21 names PRODUCTION reaches; the
        # fifteen members reached only from this repo's own `tests/` and `tools/` are
        # deliberately unpublished, so each of those reaches is a `res://` path and this is
        # where they are declared. Criterion 4 for this subject therefore OPENS at 60 and
        # the two routes that drain it are named per row: publish the name (the trade
        # dec. 1 declined), or move the test into the addon under ADR-0194 (which is why
        # `classify_blueprint.py` already carries an `addons/exmateria_effects/tests/`
        # rule with no directory behind it). Owner **#1249**.
        #
        # 🔴 NOT `SCENE_ORACLES`, AND THAT IS THE LOAD-BEARING PART. The oracle channel
        # scores nothing toward criterion 4 and its admission is gated on the row
        # MEASURING the seam; a unit test of `ParticlePhysics` does not measure a seam, it
        # tests an internal. Putting sixty rows there would be this register's own named
        # failure — *a reported channel is where debt goes to hide unless admission is
        # checked* — so they sit in the enforcing channel with a ticket.
        #
        # ⚠️ TWENTY-ONE OF THE SIXTY CANNOT BE DRAINED BY EITHER ROUTE: a shader is
        # addressed as a FILE, and no GDScript constant can route an `#include`
        # (ADR-0212 dec. 5). `tools/probe_stp_shaders.gd` alone binds seven.
    ("tests/ChildSpawnSuppressionTest.gd", "subsystem/ParticleSubsystem.gd"):
        ("#1249, 2026-09-12",
         "the particle channel runtime — an addon INTERNAL [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/ColourRibbonResolveParityTest.gd", "particles/Particle.gd"):
        ("#1249, 2026-09-12",
         "the particle record — an addon INTERNAL the façade does not publish [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/ColourRibbonResolveParityTest.gd", "render/EffectParticleRenderer.gd"):
        ("#1249, 2026-09-12",
         "the particle renderer — an addon INTERNAL [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/EffectAnimationDisplayLengthTest.gd", "particles/ParticleAnimator.gd"):
        ("#1249, 2026-09-12",
         "the frameset animator — an addon INTERNAL [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/EffectParticleRendererColorCurveRefreshTest.gd", "particles/Particle.gd"):
        ("#1249, 2026-09-12",
         "the particle record — an addon INTERNAL the façade does not publish [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/EffectParticleRendererColorCurveRefreshTest.gd", "render/EffectParticleRenderer.gd"):
        ("#1249, 2026-09-12",
         "the particle renderer — an addon INTERNAL [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/CurveGeneratorsTest.gd", "particles/ParticlePhysics.gd"):
        ("#1249, 2026-09-12",
         "the PSX particle integrator — an addon INTERNAL [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/DebugLoggingFlagsTunableTest.gd", "install/EffectsDebug.gd"):
        ("#1249, 2026-09-12",
         "the addon's own debug seam — an addon INTERNAL [preload()]. THE SIXTY-FIRST ROW, "
         "and the first one #1225's move did not seed: #1218 built "
         "`install/EffectsDebug.gd` to take 61 `DebugConfig` reads out of this addon, and "
         "the guard for its four slug literals has to read `slugs()` from the host side. "
         "Declared here rather than paid by publishing the name, because route 1 is a "
         "change to the SUPPORTED SURFACE and gl-ADR-0295 dec. 1 owns that trade for this "
         "addon — #1218 is not entitled to take it in passing. route 1 (publish) or "
         "route 2 (ADR-0194, move the test in)."),
    ("tests/EffectCurveOwnershipTest.gd", "particles/ParticlePhysics.gd"):
        ("#1249, 2026-09-12",
         "the PSX particle integrator — an addon INTERNAL [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/EffectInstanceReplaySoundTest.gd", "cast/EffectTimeline.gd"):
        ("#1249, 2026-09-12",
         "the timeline stepper — an addon INTERNAL [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/EffectInstanceReplaySoundTest.gd", "subsystem/SoundSubsystem.gd"):
        ("#1249, 2026-09-12",
         "the sound channel runtime — an addon INTERNAL [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/EffectRngDeterminismTest.gd", "cast/EffectTimeline.gd"):
        ("#1249, 2026-09-12",
         "the timeline stepper — an addon INTERNAL [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/EffectRngDeterminismTest.gd", "particles/ParticlePhysics.gd"):
        ("#1249, 2026-09-12",
         "the PSX particle integrator — an addon INTERNAL [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/EffectRngDeterminismTest.gd", "subsystem/CameraSubsystem.gd"):
        ("#1249, 2026-09-12",
         "the camera channel runtime — an addon INTERNAL [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/EffectRngDeterminismTest.gd", "subsystem/ParticleSubsystem.gd"):
        ("#1249, 2026-09-12",
         "the particle channel runtime — an addon INTERNAL [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/EffectSoundEditReachesPlaybackTest.gd", "cast/EffectTimeline.gd"):
        ("#1249, 2026-09-12",
         "the timeline stepper — an addon INTERNAL [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/EffectSoundEditReachesPlaybackTest.gd", "subsystem/SoundSubsystem.gd"):
        ("#1249, 2026-09-12",
         "the sound channel runtime — an addon INTERNAL [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/EffectStudioColorCurveLiveEditTest.gd", "particles/Particle.gd"):
        ("#1249, 2026-09-12",
         "the particle record — an addon INTERNAL the façade does not publish [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/EffectStudioColourKeyframeAcceptanceTest.gd", "particles/Particle.gd"):
        ("#1249, 2026-09-12",
         "the particle record — an addon INTERNAL the façade does not publish [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/EffectStudioColourRibbonAcceptanceTest.gd", "particles/Particle.gd"):
        ("#1249, 2026-09-12",
         "the particle record — an addon INTERNAL the façade does not publish [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/EffectStudioEffectFlagsAcceptanceTest.gd", "cast/EffectTimeline.gd"):
        ("#1249, 2026-09-12",
         "the timeline stepper — an addon INTERNAL [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/EffectStudioTimeScaleAcceptanceTest.gd", "cast/EffectTimeline.gd"):
        ("#1249, 2026-09-12",
         "the timeline stepper — an addon INTERNAL [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/EmitterFieldRelevanceSimGuardTest.gd", "particles/ActiveEmitter.gd"):
        ("#1249, 2026-09-12",
         "a live emitter — an addon INTERNAL [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/EmitterFieldRelevanceSimGuardTest.gd", "particles/Particle.gd"):
        ("#1249, 2026-09-12",
         "the particle record — an addon INTERNAL the façade does not publish [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/EmitterFieldRelevanceSimGuardTest.gd", "particles/ParticlePhysics.gd"):
        ("#1249, 2026-09-12",
         "the PSX particle integrator — an addon INTERNAL [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/EmitterFieldRelevanceSimGuardTest.gd", "particles/ParticlePool.gd"):
        ("#1249, 2026-09-12",
         "the particle pool — an addon INTERNAL [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/EmitterFieldRelevanceSimGuardTest.gd", "render/EffectParticleRenderer.gd"):
        ("#1249, 2026-09-12",
         "the particle renderer — an addon INTERNAL [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/EmitterFieldRelevanceSimGuardTest.gd", "subsystem/ParticleSubsystem.gd"):
        ("#1249, 2026-09-12",
         "the particle channel runtime — an addon INTERNAL [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/EmitterLifeWindowTest.gd", "particles/ParticlePhysics.gd"):
        ("#1249, 2026-09-12",
         "the PSX particle integrator — an addon INTERNAL [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/ScreenSubsystemTest.gd", "overlay/ScreenEffectOverlay.gd"):
        ("#1249, 2026-09-12",
         "an overlay AUTOLOAD script, bound by path because the test drives it directly rather than through the singleton [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tests/UnitTintOverlayTest.gd", "overlay/TintedSurfaces.gd"):
        ("#1249, 2026-09-12",
         "an overlay AUTOLOAD script, bound by path for the reason above; ADR-0288 dec. 7 merges it at #1223/#1224 [preload()]. route 1 (publish) or route 2 (ADR-0194, move the test in)."),
    ("tools/probe_cursor_palette_engine_fold.gd", "render/EngineFoldCompositor.gd"):
        ("#1249, 2026-09-12",
         "PUBLISHED as `ExMateriaEffects.EngineFoldCompositor`, and this row is a STRING not a type — the probe names the path to instance it by `load()` [string]. route 1 (publish) — a `tools/` probe cannot move into the addon."),
    ("tools/probe_cursor_palette_engine_fold.gd", "render/OTDepthPrimOrder.gd"):
        ("#1249, 2026-09-12",
         "the OT-depth prim ordering — an addon INTERNAL [preload()]. route 1 (publish) — a `tools/` probe cannot move into the addon."),
    ("tools/probe_demi_bucket_spread.gd", "render/OTDepthPrimOrder.gd"):
        ("#1249, 2026-09-12",
         "the OT-depth prim ordering — an addon INTERNAL [preload()]. route 1 (publish) — a `tools/` probe cannot move into the addon."),
    ("tools/probe_demi_engine_fold.gd", "render/effect_fold_add.gdshader"):
        ("#1249, 2026-09-12",
         "a fold carrier SHADER: a shader is a file, and no GDScript constant can be an `#include` [preload()]. neither route reaches it: a shader is addressed as a FILE."),
    ("tools/probe_demi_engine_fold.gd", "render/effect_fold_mix.gdshader"):
        ("#1249, 2026-09-12",
         "a fold carrier SHADER — see above [preload()]. neither route reaches it: a shader is addressed as a FILE."),
    ("tools/probe_demi_engine_fold.gd", "render/effect_fold_sub.gdshader"):
        ("#1249, 2026-09-12",
         "a fold carrier SHADER — see above [preload()]. neither route reaches it: a shader is addressed as a FILE."),
    ("tools/probe_occlusion_engine_fold.gd", "callbacks/effect_callback_fold.gdshader"):
        ("#1249, 2026-09-12",
         "the callback fold SHADER — see above [preload()]. neither route reaches it: a shader is addressed as a FILE."),
    ("tools/probe_shaders/effect_particle_linear_add.gdshader", "render/effect_particle_stp.gdshaderinc"):
        ("#1249, 2026-09-12",
         "the STP include, reached by `#include` from a probe shader — the one channel no façade can route (ADR-0212 dec. 5) [string]. neither route reaches it: a shader is addressed as a FILE."),
    ("tools/probe_shaders/effect_particle_linear_sub.gdshader", "render/effect_particle_stp.gdshaderinc"):
        ("#1249, 2026-09-12",
         "the STP include, reached by `#include` from a probe shader — the one channel no façade can route (ADR-0212 dec. 5) [string]. neither route reaches it: a shader is addressed as a FILE."),
    ("tools/probe_shaders/effect_particle_mode0.gdshader", "render/effect_particle_stp.gdshaderinc"):
        ("#1249, 2026-09-12",
         "the STP include, reached by `#include` from a probe shader — the one channel no façade can route (ADR-0212 dec. 5) [string]. neither route reaches it: a shader is addressed as a FILE."),
    ("tools/probe_shaders/effect_particle_mode1.gdshader", "render/effect_particle_stp.gdshaderinc"):
        ("#1249, 2026-09-12",
         "the STP include, reached by `#include` from a probe shader — the one channel no façade can route (ADR-0212 dec. 5) [string]. neither route reaches it: a shader is addressed as a FILE."),
    ("tools/probe_shaders/effect_particle_mode2.gdshader", "render/effect_particle_stp.gdshaderinc"):
        ("#1249, 2026-09-12",
         "the STP include, reached by `#include` from a probe shader — the one channel no façade can route (ADR-0212 dec. 5) [string]. neither route reaches it: a shader is addressed as a FILE."),
    ("tools/probe_shaders/effect_particle_mode3.gdshader", "render/effect_particle_stp.gdshaderinc"):
        ("#1249, 2026-09-12",
         "the STP include, reached by `#include` from a probe shader — the one channel no façade can route (ADR-0212 dec. 5) [string]. neither route reaches it: a shader is addressed as a FILE."),
    ("tools/probe_stp_shaders.gd", "render/effect_fold_add.gdshader"):
        ("#1249, 2026-09-12",
         "a fold carrier SHADER: a shader is a file, and no GDScript constant can be an `#include` [preload()]. neither route reaches it: a shader is addressed as a FILE."),
    ("tools/probe_stp_shaders.gd", "render/effect_fold_mix.gdshader"):
        ("#1249, 2026-09-12",
         "a fold carrier SHADER — see above [preload()]. neither route reaches it: a shader is addressed as a FILE."),
    ("tools/probe_stp_shaders.gd", "render/effect_fold_sub.gdshader"):
        ("#1249, 2026-09-12",
         "a fold carrier SHADER — see above [preload()]. neither route reaches it: a shader is addressed as a FILE."),
    ("tools/probe_stp_shaders.gd", "render/effect_native_add.gdshader"):
        ("#1249, 2026-09-12",
         "a native-blend carrier SHADER — see above [preload()]. neither route reaches it: a shader is addressed as a FILE."),
    ("tools/probe_stp_shaders.gd", "render/effect_native_mix.gdshader"):
        ("#1249, 2026-09-12",
         "a native-blend carrier SHADER — see above [preload()]. neither route reaches it: a shader is addressed as a FILE."),
    ("tools/probe_stp_shaders.gd", "render/effect_native_sub.gdshader"):
        ("#1249, 2026-09-12",
         "a native-blend carrier SHADER — see above [preload()]. neither route reaches it: a shader is addressed as a FILE."),
    ("tools/probe_stp_shaders.gd", "render/effect_particle_opaque.gdshader"):
        ("#1249, 2026-09-12",
         "the opaque particle SHADER — see above [preload()]. neither route reaches it: a shader is addressed as a FILE."),
    ("tools/proto_single_held_particle.gd", "particles/Particle.gd"):
        ("#1249, 2026-09-12",
         "the particle record — an addon INTERNAL the façade does not publish [preload()]. route 1 (publish) — a `tools/` probe cannot move into the addon."),
    },
    "exmateria_sprite_rig": {
        # \U0001f7e2 EMPTY — AND THE LAST ROW LEFT AS AN EXEMPTION, NOT AS A PAYMENT.
        # `assets/materials/unit.tres` -> `render/unit.gdshader` was the one production
        # row. ADR-0222 P1 predicted it would DRAIN, by injecting the shader from
        # `UnitAssets.base_material()`; the measurement says it cannot, because
        # `ShaderMaterial::_set` drops every `shader_parameter/x` while `shader` is null
        # and a shader-less `.tres` therefore loads with all 39 authored parameters gone.
        # It is a `DECLARED_MOUNTS` row now (ADR-0222 dec. 4), which is arm 2 —
        # REPORTED, scoring nothing — and the mount's own note carries the numbers.
        # \U0001f534 SO CRITERION 4 READING 0 HERE IS THE REGISTER MOVING, NOT THE TREE.
        # Exactly ADR-0205 dec. 7's hazard, and the reason `report()` now returns the
        # mount count and the summary line prints it: `0 (+6 oracle, 2 mount)` is
        # recoverable, `0` alone is not.
        # \U0001f7e2 THE SIX ORACLE ROWS MOVED TO `SCENE_ORACLES` (ADR-0222 dec. 1). They
        # are not paid and they are not gone: they are in a channel that scores nothing,
        # because they cannot be paid and a target-0 register holding rows that cannot
        # reach 0 stops being read. The move is the SCANNER changing, not the tree —
        # ADR-0205 dec. 7 — so criterion 4 reading 7 -> 1 here is not a win, and the
        # summary line prints the oracle count beside it so the 7 is still recoverable.
        # DRAINED — the four `tools/migrate_state_animations_to_tres.gd` rows are gone
        # because the file is. Verified dead before deleting rather than trusting its own
        # docstring, which was half wrong: its INPUT
        # (`assets/abilities/state_animations.json`) was deleted at 553ef2cd8 and nothing
        # in the tree referenced the one-shot, but its OUTPUT is not gone at all —
        # `addons/exmateria_sprite_rig/resources/map.tres` is 21 KB, live, loaded by
        # `layers/AnimationResolutionMap.gd` and hot-reloaded by
        # `resources/ResourceHotReload.gd`. That is what a SUCCEEDED one-shot looks like:
        # the corpus it emitted is owned by the addon now and the generator can never run
        # again, because the JSON it reads does not exist. Dead for the reason the file
        # gave, but not by the evidence it gave — the missing directory it cited was
        # `assets/animation_resolution/`, its pre-#744 output path, drained in the same
        # commit from `asset_census.FORMAT_OWNER` and `check_tool_paths.CENSUS_ALLOWED_EMPTY`.
        # Criterion 4: 11 -> 7.
    },
}


# --- arm 3: the ORACLES. REPORTED, scores nothing. -------------------------------------
# \U0001f534 THIS CHANNEL EXISTS BECAUSE ARM 1 COULD NOT REACH ITS OWN TARGET (ADR-0222).
# `check_addon_install`'s arm 4 already declines to score the fork in exactly these words —
# `a register that scored its own target could never reach 0 and a burn-down that cannot
# reach 0 stops being read` — and criterion 4 was in that state for the sprite rig: 7 rows,
# SIX of them host tests that name a rig path in order to MEASURE the seam. ADR-0189 dec. 8
# granted one of them by hand on the ground that routing the yardstick through the module
# makes the guard compare the module to itself. A contract test has to name both parties.
#
# So the number splits on ADR-0205 dec. 3's own ENFORCED/REPORTED shape, one channel per
# question:
#
#   SCENE_BURN_DOWN   PRODUCTION reaches. ENFORCING, target 0. This is criterion 4.
#   SCENE_ORACLES     TEST reaches that exist to measure the seam. REPORTED, scores
#                     nothing toward criterion 4 — and still ENFORCED for hygiene.
#
# \U0001f534 A REPORTED CHANNEL IS WHERE DEBT GOES TO HIDE UNLESS ADMISSION IS CHECKED, so
# admission is not the reviewer's word alone. Three MACHINE conditions gate every row and
# each of them can red it later — the point is that the argument EXPIRES rather than being
# asserted once (`test_a_row_whose_ARGUMENT_EXPIRES_is_RED`):
#
#   1. THE FILE IS UNDER `tests/`. An oracle is a test. This is what stops the one
#      PRODUCTION row being drained by moving it here: `assets/materials/unit.tres` is not
#      a test and the guard says so by name rather than by a reviewer noticing.
#   2. THE FILE REACHES HOST TERRITORY, by EITHER of the two spellings a reach has —
#      a `res://…` outside `addons/` and outside `tests/`, or a bare `ClassName` that a
#      HOST file declares. That is the MEASURED form of "ADR-0194 cannot take this test
#      into the addon": a stranger rig has no host, so a test that reaches host territory
#      cannot move, and the row is permanent for a reason the guard re-checks every run.
#      The day a row's file stops reaching one, its rows red and the test has to move into
#      the addon or the row has to be re-argued.
#      \U0001f534 THE SECOND SPELLING WAS ADDED BY AMENDMENT 2 (#871) AFTER THE FIRST
#      SCORED A FALSE GREEN. `tests/MapDitherSnapTest.gd` names two battlefield shader
#      paths in order to measure the seam and holds NO host `res://` literal at all — its
#      only host dependency is `MapRenderDebugPanel`, instantiated by class name. So the
#      predicate said "this test could move into the addon" about a test that cannot, and
#      the two rows the tree was already red on could not be admitted to the channel they
#      belong to. A blind spot in a VETO is not a safe direction: it refuses true rows.
#   3. THE SITE IS LIVE. A row whose reach is gone goes STALE and reds, same as arm 1 —
#      an oracle that quietly stops naming the seam is an oracle that stopped measuring.
#
# \u26a0\ufe0f CONDITION 2 IS NECESSARY, NOT SUFFICIENT, and saying so is the point. Almost
# every `tests/*.gd` file in the tree reaches host territory by one of the two spellings, so
# the predicate does not by itself pick the oracles out — it is a VETO, not an election. The election is the reviewed literal below,
# with a dated owner and a reason, exactly as `SCENE_BURN_DOWN`'s rows are. What the veto
# buys is that no row can sit here on an argument that has stopped being true, which is the
# failure mode a reported channel actually has.
#
# \U0001f534 THE THREE REGISTERS ARE DISJOINT and `_check_registers()` raises on an overlap.
# A key in two of them would be counted in two channels or, worse, in neither — and the
# whole reason to split a number is that the two halves stay addable.
SCENE_ORACLES: dict[str, dict[tuple[str, str], tuple[str, str]]] = {
    # 🟢 EFFECTS' CHANNEL OPENED AT #1219, ON ONE ROW, AND THE GATE IT PASSES IS THE
    # ONE THE SIXTY-ONE IN `SCENE_BURN_DOWN` DO NOT. gl-ADR-0295 dec. 1 ruled that this
    # addon's test-only reaches are DECLARED rather than published, and #1249 owns that
    # population by the two routes its rows name: publish the name, or move the test into
    # the addon under ADR-0194. This row can be paid by NEITHER, and not as a matter of
    # judgement — `oracle_blockers()` reads `Unit (src/units/Unit.gd)` off the file,
    # because the test's premise arm asserts `(caster is Unit) or (target is Unit) ==
    # false`. Naming `Unit` is not incidental to it: the whole claim is that the spawn API
    # works on something that is NOT a `Unit`, so the host class has to be named to say so,
    # and a test that names a host `class_name` cannot go into an addon. Booking it in the
    # enforcing channel would create a row neither route can reach — and this family's own
    # rule is that *a burn-down that cannot reach 0 stops being read*.
    #
    # ⚠️ THE CONTRAST IS DELIBERATE AND IT IS THE CHECKABLE PART. #1218's row the day
    # before — `tests/DebugLoggingFlagsTunableTest.gd -> install/EffectsDebug.gd` — is in
    # `SCENE_BURN_DOWN`, not here, because it names NO host `class_name` and no host
    # `res://` path: it reaches `DebugConfig` and `Tune` as AUTOLOADS, which
    # `oracle_blockers()` explicitly cannot see and explicitly does not count. So that row
    # COULD be paid by route 2 and this one cannot. Two rows, two channels, one predicate
    # deciding — rather than two readings of one situation.
    #
    # 🔴 AND IT EXPIRES IF THE PREMISE ARM GOES. Delete the `is Unit` assertion and
    # `oracle_blockers()` returns `[]`, condition 2 fails, and this row reds under
    # `ARGUMENT EXPIRED` — which is correct: without that arm the test no longer
    # distinguishes a `Node3D` from a `Unit` and has stopped measuring the seam it is
    # admitted for.
    "exmateria_effects": {
        ("tests/EffectManagerNode3DAnchorTest.gd", "cast/EffectManager.gd"):
            ("#1219, 2026-09-12 — ARGUED PERMANENT",
             "the addon's spawn API, named so the test can call it with a bare `Node3D` "
             "and read the parented instance back. ADR-0288 dec. 3 widened three "
             "`caster: Unit` / `target: Unit` annotations to `Node3D` and gl-ADR-0295 "
             "dec. 7 rules that VERIFIED BY LOADING AND ASSERTING, not by scanning — "
             "ADR-0288 S2 says a duck-typed reach is invisible to every static instrument "
             "here, so re-reading the annotation the change just wrote is not evidence. "
             "This is the seam measurement: does the addon's published spawn path require "
             "a host type? Cannot move into the addon under ADR-0194 — it names `Unit`, a "
             "host `class_name`, and must, because that is what it asserts the anchors are "
             "not."),
    },
    # \U0001f7e2 BATTLEFIELD'S CHANNEL OPENED HERE (#871, ADR-0222 Amendment 2). It was `{}`
    # for two days while the guard was RED on trunk over these two rows, which aborted the
    # pre-flight — and therefore the whole suite — on every branch cut from `main`. The
    # rows could not be admitted on the day they appeared: `oracle_blockers()` read `[]`
    # for this file, so condition 2 said the test could move into the addon, and the row
    # would have red on arrival under `ARGUMENT EXPIRED`. The predicate was wrong, not the
    # judgement — see Amendment 2 and `oracle_blockers()`.
    "exmateria_battlefield": {
        ("tests/MapDitherSnapTest.gd", "texturing/indexed_color.gdshader"):
            ("#871, 2026-09-05 — ARGUED PERMANENT",
             "the map terrain shader, read as TEXT: the arms scan its source for the "
             "`psx_dither_and_quantize(` call, count it, and compare the call's OFFSET "
             "against the `map_light_debug` branch's. `ShaderCompileTest` already proves "
             "the file parses; what it cannot see is whether the snap is called, WHERE, "
             "or with what — so the assertion IS the scan and the scan needs the address. "
             "Cannot move into the addon under ADR-0194: the test instantiates "
             "`MapRenderDebugPanel`, a host debug panel, and a stranger rig has no host."),
        ("tests/MapDitherSnapTest.gd", "camera/screen_background.gdshader"):
            ("#871, 2026-09-05 — ARGUED PERMANENT",
             "the second of the two battlefield surfaces on the same 256-wide PSX screen. "
             "Arm 5 asserts the two call sites pass the SAME native width, so both paths "
             "have to be named before the agreement can be taken — deriving the second "
             "from the first is what would make it pass by construction, the same "
             "argument `UnitMaterialVariantTest`'s three variant rows carry. Blocked from "
             "moving by the same host panel as the row above."),
        ("tests/ShadowFoldOrderTest.gd", "overlay/TileOverlayCompositor.gd"):
            ("#1075, 2026-09-09 — ARGUED PERMANENT",
             "the compositor is an addon INTERNAL and the facade deliberately does not "
             "publish it, so there is no seam to route through — and what the test needs "
             "off it are the two constants the TILE DECAL actually stamps (its depth mode "
             "and its fold rank), which are half the ordering claim. The alternative is "
             "restating them as literals in the test, which is exactly how a guard goes "
             "green against a value nobody kept: the arms assert that the shadow's key "
             "sorts STRICTLY ABOVE the tile's, so both keys must come from the code that "
             "produces them or the comparison passes by construction. Cannot move into "
             "the addon under ADR-0194: every arm reads `UnitShadow`, a host class, and "
             "a stranger rig has no host — which is condition 2's bare-identifier "
             "spelling, the one Amendment 2 added."),
    },
    "exmateria_sprite_rig": {
        ("tests/ScenarioDeadUnitFadeTest.gd", "render/unit.gdshader"):
            ("#744, 2026-09-01 — ARGUED PERMANENT",
             "ADR-0189 dec. 8 named this test by hand as ALLOWED to spell a unit shader "
             "path, on the ground that it is the independent oracle for the additive "
             "swap and routing it through the module would make it compare the module "
             "to itself. The move changed the path, not the argument."),
        ("tests/ScenarioDeadUnitFadeTest.gd", "render/unit_additive.gdshader"):
            ("#744, 2026-09-01 — ARGUED PERMANENT",
             "the additive half of the pair above; the test asserts the swap FROM one TO "
             "the other, so it has to name both."),
        ("tests/UnitMaterialVariantTest.gd", "render/unit.gdshader"):
            ("#744, 2026-09-01 — ARGUED PERMANENT",
             "one of the three variant shaders this test compares. Its own docstring "
             "states the case: the test is inside Sprite Rig's own guard, so naming them "
             "is the module's business, not a consumer reaching around the seam. Cannot "
             "move into the addon under ADR-0194 — it reads `assets/materials/unit.tres` "
             "as TEXT for its carried-contract arm, and a stranger rig has no host."),
        ("tests/UnitMaterialVariantTest.gd", "render/unit_additive.gdshader"):
            ("#744, 2026-09-01 — ARGUED PERMANENT",
             "the second of the three variants. Arms 1 and 2 diff the three shaders "
             "against each other, so all three paths have to be named before the diff "
             "can be taken; naming two and deriving the third is what would make the "
             "comparison pass by construction."),
        ("tests/UnitMaterialVariantTest.gd", "render/unit_flat.gdshader"):
            ("#744, 2026-09-01 — ARGUED PERMANENT",
             "the third of the three variants, and the one that makes the set a set: "
             "`unit_flat` is the ortho roster shader, so its uniform block differs from "
             "the two battle variants by design (`FLAT_ONLY_UNIFORMS` vs "
             "`BATTLE_ONLY_UNIFORMS`) and the test needs the third path to say which "
             "differences are the intended ones."),
        ("tests/UnitMaterialVariantTest.gd", "layers/SpriteLayerManager.gd"):
            ("#744, 2026-09-01 — ARGUED PERMANENT",
             "read as TEXT, not loaded: the arm enumerates the `shader_parameter/` keys "
             "the driver pushes per frame by scanning its source, because "
             "`_write_layer_params` CONCATENATES a prefix onto a suffix and none of the "
             "24 names appears as a literal. The façade const gives the class, and the "
             "class does not give you its source text — `resource_path` would, which is "
             "how `UnitDisplayReactionDefaultTest` paid its own row, but here the "
             "SCANNING is the assertion and asking the subject for its own address is a "
             "step toward the tautology the file's docstring already refuses."),
    },
}


def host_classes(listing: list[Path] | None = None) -> dict[str, str]:
    """`class_name` -> the HOST file that declares it, for the whole tree, walked once.

    HOST is `_HOST_PATH`'s exclusion in the other spelling: outside `addons/` and outside
    `tests/`. A class declared inside an addon is not a blocker — a test naming one moves
    into the addon with it — and a class declared under `tests/` is another test.

    \U0001f534 CACHED FOR THE PROCESS. `report()` calls `oracle_blockers()` once per row per
    subject, and re-deriving this per call would walk the tree ~16 times for a guard whose
    whole cost is the walk (`entries()` makes the same argument).

    ⚠️ THE CACHE DID NOT COVER THE WALK ITSELF. `main()` nulls `_HOST_CLASSES` on
    entry, so the first `oracle_blockers()` of every run called `entries()` again — a
    SECOND full tree walk per invocation, beside the one `main()` had already taken and
    handed to `corpus()` and `symlink_counts()`. `main()` now primes this with that same
    listing, which is also the guarantee `entries()` argues for: every consumer in one run
    reads THE SAME TREE. The no-argument form still walks, because `oracle_blockers()`
    reaches this with no listing to give and a caller may reach it with no `main()`."""
    global _HOST_CLASSES
    if _HOST_CLASSES is None:
        found: dict[str, str] = {}
        for p in (entries() if listing is None else listing):
            if p.suffix != ".gd" or not p.is_file():
                continue
            rel = p.relative_to(ROOT).as_posix()
            if rel.startswith("addons/") or rel.startswith("tests/"):
                continue
            if any(part in SKIP_DIRS for part in rel.split("/")[:-1]):   # see corpus()
                continue
            try:
                text = p.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            for m in _CLASS_NAME_DECL.finditer(text):
                found.setdefault(m.group(1), rel)
        _HOST_CLASSES = found
    return _HOST_CLASSES


def oracle_blockers(rel: str) -> list[str]:
    """The HOST territory `rel` reaches — the measured reason ADR-0194 cannot take it into
    an addon. Empty means the row's permanence argument no longer holds.

    TWO SPELLINGS OF ONE REACH, and the second was added by ADR-0222 Amendment 2 (#871)
    after the first scored a false green on a real oracle:

      * a `res://` path into host territory — `res://src/scenarios/ScenarioVM.gd`;
      * a bare `ClassName` that a HOST file declares — `MapRenderDebugPanel`, which
        resolves through Godot's global class registry with no path in the caller at all.

    Reported as `Name (declaring/file.gd)` so a reader can see WHICH file the row is
    pinned to without re-deriving the registry.

    `res://tests/…` is deliberately NOT a blocker. A test naming its own `.tscn` (every
    file here does, in its `## Run:` line) is self-reference, not a host dependency, and
    counting it would make condition 2 true of every test file in the tree. A `class_name`
    declared under `tests/` is out for the same reason.

    \u26a0\ufe0f WHAT THIS STILL CANNOT SEE, stated because the last unstated blind spot on
    this predicate is what #871 cost: a host class named inside a STRING literal counts
    (the scan strips comments, not strings), and a host dependency reached only through an
    AUTOLOAD singleton is invisible here — an autoload is not a `class_name` and this repo
    has already measured that a closure walk cannot see one."""
    try:
        text = (ROOT / rel).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    out = {m.group(0) for m in _HOST_PATH.finditer(text)}
    code = _GD_COMMENT.sub("", text) if rel.endswith(".gd") else text
    words = set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", code))
    self_declared = {m.group(1) for m in _CLASS_NAME_DECL.finditer(text)}
    for name, decl in host_classes().items():
        if name in words and name not in self_declared and decl != rel:
            out.add("%s (%s)" % (name, decl))
    return sorted(out)


def _check_registers() -> None:
    """Every subject has a row in BOTH registers, and neither register names a subject
    that is not graded.

    \U0001f534 THIS IS THE WIDENING'S OWN FAILURE MODE, not decoration. A subject added to
    `SUBJECTS` and forgotten in `SCENE_BURN_DOWN` would be graded with `.get(addon, {})`
    semantics — every site UNLISTED, which is loud — but a subject added to the registers
    and forgotten in `SUBJECTS` is scanned by nobody and reads as owing nothing, SILENTLY.
    That is the same shape `check_addon_globals`'s test has an arm for, so it raises here
    rather than reporting."""
    for name, reg in (("DECLARED_MOUNTS", DECLARED_MOUNTS),
                      ("SCENE_BURN_DOWN", SCENE_BURN_DOWN),
                      ("SCENE_ORACLES", SCENE_ORACLES)):
        missing = sorted(set(SUBJECTS) - set(reg))
        extra = sorted(set(reg) - set(SUBJECTS))
        if missing:
            raise SystemExit(f"{name} has no row for {missing} — a graded subject with no "
                             "register entry. Add the row (empty is a measurement).")
        if extra:
            raise SystemExit(f"{name} names {extra}, which SUBJECTS does not grade — a "
                             "register nobody scans reads as owing nothing, silently.")
    # \U0001f534 AND THE TWO CHANNELS ARE DISJOINT (ADR-0222 dec. 1). Splitting one number
    # into two is only honest while the halves stay addable: a key in both registers is
    # counted twice, so a reader recovering the pre-split total from `n (+m oracle)` would
    # get a number that was never true of the tree.
    #
    # \u26a0\ufe0f SCOPED TO THE TWO BURN-DOWNS, and NOT to `DECLARED_MOUNTS`. A mount is an
    # EXEMPTION, not a third channel — `report()` subtracts it before either register is
    # consulted, so a mount that also carries a row is redundant rather than double-counted
    # and nothing a reader adds up moves. Widening this to the mounts was tried and reverted
    # the same hour: it raises on `all_live_sites_declared()`, the constructed
    # empty-register state the suite uses to keep an arm alive after a burn-down empties.
    # A register check that forbids a legitimate constructed state is testing the test.
    for addon in SUBJECTS:
        both = sorted(set(SCENE_BURN_DOWN[addon]) & set(SCENE_ORACLES[addon]))
        if both:
            raise SystemExit(f"{addon}: {both} is in BOTH SCENE_BURN_DOWN and "
                             "SCENE_ORACLES — a site in two channels is counted twice, "
                             "and `n (+m oracle)` stops being addable. Pick one.")


def entries() -> list[Path]:
    """ONE `rglob` for the whole invocation. Every subject filters the same list.

    Not an optimisation for its own sake: the walk is the guard's whole cost, and a
    per-subject walk makes it linear in the number of addons — the widening would have
    doubled a pre-flight guard's wall clock for a report nobody reads twice. It is also
    the only way two subjects are guaranteed to be reading THE SAME TREE, which matters
    while the seeds in `test_check_lattice_scene.py` write into the real one.

    PRUNED AT THE WALK, not after it. `rglob("*")` descends `.godot/` and hands back
    15,639 paths that every one of the three consumers (`host_classes`, `corpus`,
    `symlink_counts`) then drops again on the same `SKIP_DIRS` test — 69% of the listing
    existed only to be filtered, three times, by three separate loops that each `stat()`
    it first. Pruning `dirnames` in place means the walk never enters those directories,
    so the cost disappears from the walk AND from every downstream pass.

    \U0001f534 THE RESULT IS UNCHANGED, and that is the only reason this is allowed. What
    is dropped is exactly the set of paths lying UNDER a `SKIP_DIRS` directory, which is
    exactly what all three consumers already excluded — so the same rows are scored, in
    the same order. `test_entries_is_the_pruned_rglob` pins that equality against a live
    `rglob` rather than trusting this comment; a guard that stopped LOOKING and a guard
    that found nothing read identically, and this file exists to tell them apart.

    Note the prune is on DIRECTORY names only. A *file* named `.godot` is kept — that is
    `SCAN_EXTS`'s `.godot` suffix, i.e. `project.godot`, which is a real subject and lives
    at the tree root, not inside the `.godot/` cache directory."""
    out: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(ROOT, followlinks=False):
        here = Path(dirpath)
        kept = []
        for name in dirnames:
            if name in SKIP_DIRS:
                continue
            kept.append(name)
            out.append(here / name)
        dirnames[:] = kept                    # prune IN PLACE — os.walk reads it back
        out.extend(here / name for name in filenames)
    # `Path.__lt__` compares the parts tuple, and sorting 7,150 Paths through it costs
    # more than the walk. Same order, ~10x cheaper.
    return sorted(out, key=lambda p: p.parts)


def corpus(addon: str, listing: list[Path] | None = None) -> list[Path]:
    """Every scannable file outside THIS addon. `.godot/` is pruned twice — see the
    docstring's blind-spot list; a `lstrip` bug readmitted 32 cache hits once already.

    Excluding only the subject, never every subject: a sibling addon naming a path into
    this one is a real reach and belongs on the burn-down or in `DECLARED_MOUNTS`, not
    inside a hole. While the rig's folder does not exist the two subjects read the same
    corpus, which is why Battlefield's numbers are unchanged by the widening."""
    out = []
    skip = addon_dir(addon)
    for p in (entries() if listing is None else listing):
        # SUFFIX BEFORE `is_file()`: same conjunction, but `suffix` is a string test and
        # `is_file()` is a `stat()`. Most of the listing is not a `SCAN_EXTS` file, so
        # asking the cheap question first drops ~13k syscalls per run.
        if p.suffix not in SCAN_EXTS or not p.is_file():
            continue
        rel = p.relative_to(ROOT).as_posix()
        if rel.startswith(skip):
            continue
        # The SECOND `relative_to(ROOT)` here rebuilt the tuple this line already holds:
        # for a relative path `as_posix()` IS `"/".join(parts)`, so splitting `rel` back
        # is the identical sequence at string cost. `relative_to` was 37% of the guard's
        # cumulative profile and this loop ran it twice over every one of 7,246 entries.
        if any(part in SKIP_DIRS for part in rel.split("/")[:-1]):
            continue
        if rel.startswith(".godot/"):
            continue
        out.append(p)
    return out


def symlink_counts(listing: list[Path] | None = None) -> dict[str, dict[str, int]]:
    """rel -> {addon: files naming that addon's prefix}. ONE read pass per symlinked
    tree, scored for every subject at once — see `entries()`."""
    out: dict[str, dict[str, int]] = {}
    pres = {a: prefix(a) for a in SUBJECTS}
    for p in (entries() if listing is None else listing):
        if not p.is_symlink() or not p.is_dir():
            continue
        rel = p.relative_to(ROOT).as_posix()
        if any(d in rel.split("/") for d in SKIP_DIRS):
            continue
        if any(rel.startswith(addon_dir(a)) for a in SUBJECTS):
            continue
        n = {a: 0 for a in SUBJECTS}
        # 🔴 `os.walk`, NOT `rglob("*")`, and the reason is 95 ms per call. This
        # enumerates 24,734 paths across 416 symlinked roots to read the 168 that are
        # `SCAN_EXTS` files, and under `rglob` every one of those 24,734 was a `Path`
        # constructed only to be thrown away — `_parse_path`/`with_segments`/`is_file()`
        # dominated the whole guard's profile. `os.walk` hands back strings and already
        # knows a name is not a directory, so the same 168 files are read for 16 ms.
        # SAME ANSWER, and that is the only reason this is allowed: `followlinks=False`
        # matches `rglob`'s `recurse_symlinks=False` (a symlinked directory is listed and
        # not descended, both ways); `splitext(name)[1]` is `Path.suffix` including for a
        # dotfile like `.gd`, where BOTH yield `""` and neither matches; and a broken
        # symlink lands in `filenames` here and fails `is_file()` there, so the `OSError`
        # below drops it exactly where `rglob` never yielded it.
        for dirpath, _dirnames, filenames in os.walk(p.resolve(), followlinks=False):
            for name in filenames:
                if os.path.splitext(name)[1] not in SCAN_EXTS:
                    continue
                try:
                    with open(os.path.join(dirpath, name), encoding="utf-8",
                              errors="replace") as fh:
                        text = fh.read()
                except OSError:
                    continue
                for a, pre in pres.items():
                    if pre in text:
                        n[a] += 1
        out[rel] = n
    return out


def symlink_probe(addon: str, counts: dict[str, dict[str, int]] | None = None
                  ) -> list[tuple[str, int]]:
    """REPORTED, scores nothing. `corpus()` cannot walk a symlinked directory and must
    not — see the docstring's blind-spot list. This says how many files inside one name
    the prefix, so the gap cannot go non-empty without saying so. Worktree-dependent by
    construction: a bare worktree has fewer of these links, which is exactly why the
    number is reported and never enforced."""
    if counts is None:
        counts = symlink_counts()
    return sorted((rel, n[addon]) for rel, n in counts.items())


def _shape(line: str) -> str:
    m = _EXT_RESOURCE.search(line)
    if m:
        return "ext_resource:" + m.group(1)
    if "preload(" in line:
        return "preload()"
    if "load(" in line:
        return "load()"
    return "string"


def scan(addon: str, files: list[Path] | None = None) -> dict[tuple[str, str], dict]:
    """(rel, target) -> {"lines": [n, ...], "shapes": {shape, ...}}. A site is a PAIR."""
    pre, rx = prefix(addon), path_re(addon)
    sites: dict[tuple[str, str], dict] = {}
    for p in (corpus(addon) if files is None else files):
        rel = p.relative_to(ROOT).as_posix()
        try:
            text = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if pre not in text:
            continue
        for n, line in enumerate(text.splitlines(), 1):
            for m in rx.finditer(line):
                key = (rel, m.group(1))
                e = sites.setdefault(key, {"lines": [], "shapes": set()})
                if n not in e["lines"]:
                    e["lines"].append(n)
                e["shapes"].add(_shape(line))
    return sites


def report(addon: str, listing: list[Path] | None = None,
           counts: dict[str, dict[str, int]] | None = None) -> int:
    """One subject's two arms, its probe and its verdict. Returns its rc.

    Every number below is derived from `addon` — there is no module-level subject left
    to leak one addon's reading into another's line."""
    mounts = DECLARED_MOUNTS[addon]
    burn_down = SCENE_BURN_DOWN[addon]
    oracles = SCENE_ORACLES[addon]
    files_scanned = corpus(addon, listing)
    sites = scan(addon, files_scanned)
    files = sorted({k[0] for k in sites})
    declared = {k: v for k, v in sites.items() if k in mounts}
    # \U0001f534 THREE CHANNELS, NOT TWO (ADR-0222 dec. 1). `scored` is the PRODUCTION
    # population and it alone is criterion 4; an oracle site is lifted out here and
    # reported by arm 3. Lifting by MEMBERSHIP of the reviewed literal, never by a
    # predicate over the path: a filter manufactures its own debt and cannot tell a
    # triaged site from one that merely matches (#424), which is the same reason arm 1
    # burns down by name.
    unscored = {k: v for k, v in sites.items() if k not in mounts and k in oracles}
    scored = {k: v for k, v in sites.items() if k not in mounts and k not in oracles}

    print("\n" + "=" * 78)
    print("SUBJECT %s — %s" % (addon, SUBJECTS[addon]))
    print("subject: every `%s` file under %s except `%s` — %d file(s) scanned. A site is\n"
          "a (file, target) PAIR naming `%s\u2026`, not a line (ADR-0205)."
          % ("`/`".join(sorted(e.lstrip(".") for e in SCAN_EXTS)),
             ROOT.name, addon_dir(addon), len(files_scanned), prefix(addon)))

    unlisted = sorted(k for k in scored if k not in burn_down)
    burned = sorted(k for k in scored if k in burn_down)
    stale = sorted(k for k in burn_down if k not in scored)

    by_shape: dict[str, int] = {}
    by_dir: dict[str, int] = {}
    for (rel, _), e in scored.items():
        for sh in e["shapes"]:
            by_shape[sh] = by_shape.get(sh, 0) + 1
        by_dir[rel.split("/")[0]] = by_dir.get(rel.split("/")[0], 0) + 1
    print("\narm 1 — PRODUCTION, ENFORCING, target 0: %d site(s) over %d file(s), %d "
          "declared.\n    THIS NUMBER IS CRITERION 4. %d oracle site(s) are reported by "
          "arm 3 and\n    score nothing (ADR-0222 dec. 1); the two are never summed and "
          "never\n    reported as each other."
          % (len(scored), len(files), len(declared), len(unscored)))
    print("    by shape:     " + ", ".join("%s %d" % (sh, n) for sh, n in
                                           sorted(by_shape.items(), key=lambda x: -x[1])))
    print("    by directory: " + ", ".join("%s %d" % (d, n) for d, n in
                                           sorted(by_dir.items(), key=lambda x: -x[1])))

    if burned:
        owners: dict[str, int] = {}
        for k in burned:
            owners[burn_down[k][0]] = owners.get(burn_down[k][0], 0) + 1
        print("\nRESOURCE-PATH REGISTER — %d site(s) name an addon path and are NAMED in\n"
              "SCENE_BURN_DOWN with an owner. Not a pass: this is ADR-0164 dec. 4\n"
              "criterion 4 unmet, on record, target 0 (ADR-0205 dec. 3)." % len(burned))
        for owner, n in sorted(owners.items(), key=lambda x: -x[1]):
            print("  %4d  %s" % (n, owner))
        if "--list" not in sys.argv:
            print("  (--list for the rows)")

    print("\narm 2 — DECLARED MOUNTS, REPORTED, scores nothing (ADR-0205 dec. 3). "
          "Enforcing\n    this direction would make DELETING a mount red the guard, "
          "which is backwards.")
    for (rel, target), (owner, why) in sorted(mounts.items()):
        live = (rel, target) in sites
        others = sorted(r for (r, t) in scored if t == target)
        print("  %s %s → %s\n      %s — %s" % ("live " if live else "DEAD!", rel, target, owner, why))
        if not live:
            print("      ⚠️ declared but the file does not name that path. Dead mount.")
        print("      %d undeclared namer(s) of the same target still on the burn-down%s"
              % (len(others), (": " + ", ".join(others[:6])) if others else ""))

    print("\narm 3 — ORACLES, REPORTED, scores nothing toward criterion 4 (ADR-0222\n"
          "    dec. 1). A host test that names an addon path in order to MEASURE the\n"
          "    seam. Routing the yardstick through the module would make the guard\n"
          "    compare the module to itself (ADR-0189 dec. 8). %d site(s) over %d file(s)."
          % (len(unscored), len({r for r, _ in unscored})))
    for rel, target in sorted(unscored):
        owner, why = oracles[(rel, target)]
        blockers = oracle_blockers(rel)
        print("  keep  %s → %s\n      %s — %s" % (rel, target, owner, why))
        print("      ADR-0194 cannot take it: reaches %d host name(s)%s"
              % (len(blockers), (" — " + ", ".join(blockers[:3])) if blockers else ""))

    probe = symlink_probe(addon, counts)
    hot = [(r, n) for r, n in probe if n]
    print("\n    symlink probe — REPORTED, scores nothing. %d symlinked tree(s) are\n"
          "    outside the walk (`rglob` does not recurse a symlink, and following one\n"
          "    would make a bare worktree score a different number for the same commit).\n"
          "    Files naming the prefix inside them: %d."
          % (len(probe), sum(n for _, n in probe)))
    for rel, n in hot:
        print("      ⚠️ %s — %d file(s) name the prefix and are NOT on the burn-down." % (rel, n))

    rc = 0
    if unlisted:
        rc = 1
        print("\n❌ %s arm 1 — %d UNLISTED site(s). A new path reach into the addon was\n"
              "   added and named nowhere. Fix it, or add the row with an owner and a pass."
              % (addon, len(unlisted)))
        for rel, target in unlisted:
            e = sites[(rel, target)]
            print("  %s:%s  →  %s  [%s]"
                  % (rel, ",".join(str(n) for n in e["lines"][:8]), target,
                     "/".join(sorted(e["shapes"]))))
    if stale:
        rc = 1
        print("\n❌ %s arm 1 — %d STALE row(s). The debt is PAID; the row is the leftover.\n"
              "   DELETE the row. Never restore the reach." % (addon, len(stale)))
        for rel, target in stale:
            print("  %s  →  %s\n      was: %s" % (rel, target, burn_down[(rel, target)][0]))

    # \U0001f534 ARM 3 SCORES NOTHING AND IS STILL ENFORCED. "Reported" names what the row
    # contributes to criterion 4, not whether the guard checks it — a channel that scores
    # nothing AND checks nothing is a filter with extra words, and #424 is the rule
    # against exactly that. Each block below is one of the three admission conditions,
    # re-checked every run so the argument EXPIRES instead of being asserted once.
    # \u26a0\ufe0f STALE IS KEYED ON `sites`, NOT ON `unscored`, and the difference is a real
    # state the suite reaches: `unscored` excludes DECLARED MOUNTS, so an oracle row whose
    # site is also a mount would read as stale while the reach is still right there in the
    # file. Stale means the FILE STOPPED NAMING THE PATH. A row that is also a mount is
    # redundant, which is a different (and harmless) thing.
    # Conditions 1 and 2 run over EVERY row for the same reason — they ask about the row's
    # FILE, not about what the row scores, so exempting a mounted row would let the one
    # shape this channel must refuse in through the one door that skips the check.
    o_stale = sorted(k for k in oracles if k not in sites)
    if o_stale:
        rc = 1
        print("\n❌ %s arm 3 — %d STALE oracle row(s). The test no longer names that path,\n"
              "   so it is no longer measuring the seam. DELETE the row — and check the\n"
              "   oracle still asserts what it was kept for." % (addon, len(o_stale)))
        for rel, target in o_stale:
            print("  %s  →  %s\n      was: %s" % (rel, target, oracles[(rel, target)][0]))
    o_prod = sorted(k for k in oracles if not k[0].startswith("tests/"))
    if o_prod:
        rc = 1
        print("\n❌ %s arm 3 — %d oracle row(s) NOT under `tests/`. An oracle is a test.\n"
              "   A production reach parked here is criterion 4 draining itself by\n"
              "   reclassification, which is the one thing this split must not buy."
              % (addon, len(o_prod)))
        for rel, target in o_prod:
            print("  %s  →  %s" % (rel, target))
    o_free = sorted(k for k in oracles if not oracle_blockers(k[0]))
    if o_free:
        rc = 1
        print("\n❌ %s arm 3 — %d oracle row(s) whose ARGUMENT EXPIRED. The file names no\n"
              "   host path and no host `class_name` any more, so ADR-0194 CAN take it\n"
              "   into the addon now and the reason it was called permanent is gone.\n"
              "   Move the test, or re-argue the row against what is true today."
              % (addon, len(o_free)))
        for rel, target in o_free:
            print("  %s  →  %s\n      was: %s" % (rel, target, oracles[(rel, target)][0]))

    if "--list" in sys.argv:
        print("\n%s SCENE_BURN_DOWN rows:" % addon)
        for rel, target in burned:
            e = sites[(rel, target)]
            print("  %s:%s  →  %s  [%s]  %s"
                  % (rel, ",".join(str(n) for n in e["lines"][:8]), target,
                     "/".join(sorted(e["shapes"])), burn_down[(rel, target)][0]))

    # \U0001f534 A DECLARED MOUNT IS AN EXEMPTION AND THE VERDICT HAS TO SAY SO. `declared`
    # never entered `scored`, so "criterion 4 is 0" is the claim `every production file
    # naming this addon is a reviewed indirection`, which is a smaller claim than the one
    # the sentence used to make. Printed rather than implied — see `report()`'s return.
    mounted = ("" if not declared else
               "\n   \u26a0\ufe0f %d site(s) are DECLARED MOUNTS (arm 2), subtracted before this\n"
               "   count. Reviewed indirections, not absent reaches." % len(declared))
    if rc == 0:
        # \U0001f534 THE VERDICT HAS TO DISTINGUISH THE TWO WAYS OF BEING GREEN, PER ADDON.
        # rc 0 with rows on the list means "every debt is NAMED", which is not the same
        # claim as "there is no debt"; printing one sentence for both is how a burn-down
        # gets read as a pass while it still holds sixteen rows. Widening the register did
        # not collapse the two sentences into one tree-wide verdict, for the same reason:
        # one addon at 0 and another carrying debt are two readings, not an average.
        if burned:
            print("\n✅ %s resource-path register OK — %d production site(s), all named,\n"
                  "   no stale rows. NOT a pass on criterion 4 while any row remains:\n"
                  "   target is 0. (%d oracle site(s) beside it, scoring nothing.)%s"
                  % (addon, len(burned), len(unscored), mounted))
        elif unscored:
            # \U0001f534 THE THIRD SENTENCE, AND IT IS NOT THE SECOND ONE. Criterion 4 at 0
            # over a non-empty oracle channel is a real pass — no PRODUCTION file reaches
            # in — but it is not the same claim as "no file in the tree names an addon
            # path", and printing dec.-4's sentence here would make the split read as a
            # bigger win than it is. ADR-0222 dec. 3: the oracle count is never silent.
            print("\n✅ %s CRITERION 4 IS 0 — no PRODUCTION file names a path into the\n"
                  "   addon. %d oracle site(s) remain and are REPORTED, not paid: they are\n"
                  "   host tests that name the seam in order to measure it, each still\n"
                  "   blocked from moving by a host reach the guard re-checks (arm 3).%s"
                  % (addon, len(unscored), mounted))
        else:
            print("\n✅ %s CRITERION 4 IS 0 — no host file names a path into the addon, and\n"
                  "   the burn-down is EMPTY rather than merely all-named. Every declared\n"
                  "   mount above is still checked, and a new unnamed reach still reds arm 1.%s"
                  % (addon, mounted))
    # 🔴 THE CALLER NEEDS THE COUNT, NOT JUST `rc` — and giving it only `rc` is how
    # the summary line below spent #745 printing `exmateria_sprite_rig 0` over a register
    # holding ELEVEN rows. `rc` answers "is any row unlisted or stale", which is the
    # HYGIENE question; criterion 4 is the SIZE question and target 0 (ADR-0205 dec. 3).
    # A fully-named register is rc 0 at any size, so rendering rc as the criterion prints
    # a pass for every state except a broken burn-down. That is the same two-ways-of-being-
    # green collapse the block above exists to refuse, leaking one function outward.
    #
    # \U0001f534 AND THE MOUNT COUNT FOR THE SAME REASON, ONE PASS LATER. `declared` is
    # subtracted before either channel is consulted, so criterion 4 can reach 0 because a
    # row was EXEMPTED rather than because a reach was removed — which is what happened to
    # the rig on 2026-09-03 (ADR-0222 dec. 4). Battlefield has read 0 over THREE
    # mounts since ADR-0207 and the summary never said so; that was tolerable while no
    # number turned on it and stopped being tolerable the moment one did.
    return rc, len(burned), len(unscored), len(declared)


def main() -> int:
    global _HOST_CLASSES
    _HOST_CLASSES = None                      # see the constant's own comment
    _check_registers()
    print("check_lattice_scene.py — ADR-0164 dec. 4 criterion 4, the RESOURCE-PATH channel")
    print("  subject: %d addon(s) — %s" % (len(SUBJECTS), ", ".join(sorted(SUBJECTS))))
    print("\n🔴 THIS IS AXIS A (host → addon), NOT the install term. Axis B\n"
          "   (`check_addon_install`, ADR-0202) is a different question and a different\n"
          "   number. Never report either as the other — ADR-0202 dec. 1.")

    listing = entries()
    host_classes(listing)                     # prime with THIS run's listing, not a new walk
    counts = symlink_counts(listing)
    results = {addon: report(addon, listing, counts) for addon in sorted(SUBJECTS)}
    print("\n" + "=" * 78)
    print("check_lattice_scene: criterion 4 per addon — %s"
          % ", ".join("%s %d (+%d oracle, %d mount)%s"
                      % (a, n, o, m, " (BURN-DOWN BROKEN)" if rc else "")
                      for a, (rc, n, o, m) in sorted(results.items())))
    print("   The FIRST number IS criterion 4 — the PRODUCTION channel — and its target is\n"
          "   0 (ADR-0205 dec. 3, split by ADR-0222 dec. 1) EXCEPT where `CRITERION4_FLOOR`\n"
          "   declares otherwise. A non-zero reading with no `BURN-DOWN BROKEN` beside it\n"
          "   means every row is NAMED — the register doing its job, NOT the criterion met.")
    floor_fail = False
    for a, (_rc, n, _o, _m) in sorted(results.items()):
        f = CRITERION4_FLOOR.get(a, 0)
        if f:
            print("   %s: floor %d of the %d are UNPAYABLE BY EITHER ROUTE — they target a "
                  "shader\n      or an `#include`, which no GDScript name can route "
                  "(#1249). 0 is unreachable\n      while they exist; %d is the number a "
                  "route could still move." % (a, f, n, n - f))
        if n < f:
            floor_fail = True
            print("\n\u274c %s criterion 4 reads %d, BELOW its declared floor of %d. A route "
                  "was found\n   that `CRITERION4_FLOOR`'s note says does not exist — lower "
                  "the floor WITH the\n   argument, or the note is now false." % (a, n, f))
    # \U0001f534 THE `+n oracle` TERM IS NOT DECORATION AND IT IS NOT ADDABLE-AWAY.
    # ADR-0205 dec. 7: after a change, a scanner blind to the old spelling is
    # indistinguishable from a correct one. The rig's criterion 4 went 7 -> 1 on the day
    # this split landed and NOT ONE LINE OF THE TREE MOVED, so the drop is evidence about
    # the SCANNER. Printing the oracle count next to it is what keeps the 7 recoverable
    # from the line a reader quotes, which is the only thing that stops the split being a
    # way to buy a number.
    print("   \u26a0\ufe0f `+n oracle` is arm 3 — host tests that name the seam to MEASURE it\n"
          "   (ADR-0222). It scores nothing and is NEVER added to the first number. A\n"
          "   criterion 4 that FELL when this channel appeared fell because the register\n"
          "   split, not because the tree moved (ADR-0205 dec. 7).")
    # \U0001f534 THE `n mount` TERM IS THE SAME MEDICINE AS `+n oracle`, ONE PASS LATER.
    # A mount is subtracted before either channel is consulted, so the FIRST number can
    # fall to 0 because a row was EXEMPTED. The rig's did, on 2026-09-03: its last
    # production row could not be drained (ADR-0222 dec. 4) and became its second
    # mount, and without this term the line a reader quotes would be indistinguishable
    # from the reach having been removed.
    print("   \u26a0\ufe0f `n mount` is arm 2 — host-owned indirections DECLARED as permitted\n"
          "   to name an addon path, subtracted before either channel. A criterion 4 of 0\n"
          "   over a live mount says every production namer is a reviewed seam, NOT that\n"
          "   nothing names the addon. Battlefield has read 0 over three mounts since\n"
          "   ADR-0207; the rig's second mount is its last production row (ADR-0222\n"
          "   Amendment 1), so the term is load-bearing now rather than decorative.")
    print("   ⚠️ THAT IS AXIS A's criterion 4 ALONE — say axis B's number too\n"
          "   (`check_addon_install`), never one as the other (ADR-0202 dec. 1).")
    # `floor_fail` is ORed in rather than printed only: a clause that reports and cannot
    # change the verdict discriminates nothing, which is the shape this repo keeps finding
    # in its own guards.
    return 1 if (floor_fail or any(rc for rc, _, _, _ in results.values())) else 0


if __name__ == "__main__":
    raise SystemExit(main())
