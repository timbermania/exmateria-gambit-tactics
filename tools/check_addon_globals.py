#!/usr/bin/env python3
"""ADR-0212 — every addon here puts ONE global name in a consumer's project, and
that name is the folder-named façade.

Godot has no package scope. A `class_name` is an engine-global registration, so
every one an addon declares lands in a consumer's global scope — and when the
consumer declares a colliding one, it is the ADDON's file that fails to parse,
pointing the error at a file they did not write.

ADR-0211 ruled that for `exmateria_battlefield` alone, which declared **30**.
ADR-0212 dec. 1 states the invariant the three finished addons already satisfy —
**one global `class_name`, spelled `ExMateriaX`, in `addons/exmateria_x/
exmateria_x.gd`** — and dec. 3 applies it to the three ADR-0211 dec. 8 left out:
`exmateria_platform` (3 then, **7** since #1220 brought the PSX trio home),
`exmateria_schema` (6) and `exmateria_render` (1).

🔴 A COUNT OF ONE WAS NEVER THE INVARIANT. `exmateria_render` already declares
exactly one global. It is `FoldSurface`, and it collides in a consumer's project
as readily as any of battlefield's thirty. What makes the finished addons safe is
that their surviving name is brand-prefixed and named after its folder, so this
guard asserts the folder-named form (`arm_rot`) and not merely the count.

Three arms, lifted in shape from `exmateria-sound/tools/check_globals.py` (the
repo-root `docs/adr/0003-an-installed-addon-owns-five-global-names.md` guard).
LIFTED, not imported: `check_addon_install.py` set that precedent, and a
cross-package import would couple two packages' tool trees to make one guard.
The ancestor iterates a `FACADES` dict; this file was narrowed to one hardcoded
addon on the way down and ADR-0212 dec. 6 restores the dict, which is why the
widening is a restoration rather than an invention.

  CREEP  nothing new becomes global. The `class_name` set under each addon root
         is exactly that addon's façade, plus whatever its `BURN_DOWN` names.

  ROT    nothing a façade publishes has gone missing. Every `const X =
         preload(...)` on a façade resolves to a file that exists, inside an
         addon. A ratchet with only the creep arm reports green while the
         surface it protects decays — and the motivating defect for the root
         ADR was exactly that: an 18-key façade was settled with one of its
         keys ALREADY deleted.

  CITE   nothing a façade publishes has gone unread. Every published constant
         states a host use, and a citation naming a `.gd` file must still
         resolve and still name the symbol (ADR-0208 dec. 6 + ADR-0210 dec. 1).
         A cited file that is not the host says which relationship it is: a
         SIBLING ADDON (ADR-0212 dec. 7) or this addon's OWN root (ADR-0217
         dec. 5, mechanizing ADR-0215 dec. 4). The second label is not a
         prohibition — its COUNT is reported per addon, and above zero it says
         the published surface shrank to what one in-addon adapter wanted.

🔴 SCOPE, STATED SO IT IS NOT READ WIDER. This scores the `class_name` channel
of the four `godot-learning` addons.
  - The autoload and host-global channels are `check_addon_install.py`'s (axis
    B, ADR-0202 dec. 1). Never report one as the other.
  - The `.tscn`/`res://` PATH channel is `check_lattice_scene.py`'s criterion 4
    (axis A, ADR-0205 — a path reach is the SAME axis as a type reach). This
    arm is blind to it BY DESIGN: `MapComposer` will read clean here while
    remaining the addon's most-reached file by path through its declared mount.
    "Holds no global name" is NOT "nothing depends on it" (ADR-0211 dec. 3).
  - The shader `#include` channel is OUT OF SCOPE and said out loud rather than
    left silent (ADR-0212 dec. 5). Roughly forty `#include "res://addons/…"`
    lines reach into `exmateria_platform` and `exmateria_schema`. A
    `.gdshaderinc` declares no `class_name`, so it carries none of the collision
    hazard this file is about, and no GDScript constant can route a preprocessor
    include. The direction that matters — an `#include` OUT of an addon — is
    already scored by `check_addon_portability.py` arm 3 (ADR-0169 dec. 5).
  - `exmateria_sound` and `exmateria_spu` live in another package and stay ruled
    by the repo-root `docs/adr/0003-an-installed-addon-owns-five-global-names.md`
    and by that package's own `tools/check_globals.py` (ADR-0212 dec. 11). Two
    instruments on one population across a package boundary is what that
    decision refuses.

Run from the package root.  Exit 0 = clean.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
PKG = HERE.parent.parent                     # godot-learning/
ADDONS = PKG / "addons"

# Every addon root under this package, and the ONE global name it may declare.
# The façade file is named after its folder, and that is asserted rather than
# assumed (ADR-0212 dec. 1) — a façade a stranger cannot find is a façade nobody
# maintains, and `ExMateriaFoldSurface` would be branded and still not a
# namespace.
FACADES = {
    "exmateria_battlefield": "ExMateriaBattlefield",
    "exmateria_platform": "ExMateriaPlatform",
    "exmateria_render": "ExMateriaRender",
    "exmateria_schema": "ExMateriaSchema",
    "exmateria_sprite_rig": "ExMateriaSpriteRig",
    "exmateria_almanac": "ExMateriaAlmanac",
    "exmateria_catalogue": "ExMateriaCatalogue",
    "exmateria_effects": "ExMateriaEffects",
}

# One spelling of "a published constant", shared by the rot arm and the citation arm —
# two regexes that must agree is a way for two arms to disagree about the same list.
_PUBLISHED_CONST = re.compile(
    r'^const\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::=|=)\s*preload\(\s*"([^"]+)"\s*\)',
    re.M)

# --- the burn-down ---------------------------------------------------------
#
# Per addon, the `class_name`s that still violate ADR-0212 dec. 1. A NAMED LIST,
# never a filter (#424 — an exclusion expressed as a filter manufactures its own
# debt and cannot tell a triaged name from one that merely matches).
#
# 🔴 EVERY LIST HERE MAY ONLY SHRINK, AND BOTH DIRECTIONS ARE SCORED. A name on
# one of these lists that no longer declares a `class_name` is a FAILURE, not a
# pass — the entry is deleted in the same commit as the `class_name` it names.
# Without that second arm a list rots into a permanent exemption, which is a
# ratchet with one arm reporting green over a surface nobody is watching.
#
# 🔴 THE THREE NEW LISTS ARE SEEDED IN THE SAME COMMIT THAT WIDENS `FACADES`
# (ADR-0212 dec. 6). `run_tests_parallel.py:377` runs preflight as
# `run_all_tests.sh --preflight-only` and `run_all_tests.sh:303` calls this
# guard, so a widened dict with unseeded burn-downs reds preflight the moment it
# lands — and an early-aborting preflight hides every guard behind it.
BURN_DOWN: dict[str, set[str]] = {
    # Seeded at 30 on 2026-08-30 (every `class_name` the addon declared; the
    # façade is a NEW file, so none of them survived) and drained to 0 in the
    # same pass by ADR-0211 dec. 2's migration. EMPTY IS A MEASUREMENT, NOT A
    # FINISHED JOB — the entry and both arms STAY.
    "exmateria_battlefield": set(),
    # Seeded at 3 on 2026-08-30 for #719 (ADR-0212 dec. 3) and drained to 0 in
    # the same pass. `DisplayPort` IS THE NAME OF A HARDWARE STANDARD, which is
    # the clearest single reason the invariant is the folder-named façade and not
    # a count. Complete symbol close: zero host `.gd` files preload a `res://`
    # path into this addon. EMPTY IS A MEASUREMENT, NOT A FINISHED JOB.
    "exmateria_platform": set(),
    # Seeded at 1 on 2026-08-30 for #718 (ADR-0212 dec. 1) and drained to 0 in
    # the same pass. The one name was `FoldSurface` — unbranded, not a namespace,
    # and it collided like any other, which is why a count of one was never the
    # invariant. EMPTY IS A MEASUREMENT, NOT A FINISHED JOB.
    "exmateria_render": set(),
    # Seeded at 6 on 2026-08-30 for #720 (ADR-0212 dec. 3) and drained to 0 in
    # the same pass. By collision risk these were the WORST of the ten: `Fold`,
    # `ColorStack`, `DepthMode`, `CellMarking`, `ColorRecipe` and `TerrainCell`
    # are all generic English, and `Fold` in particular is a word any project
    # doing compositing, layout or card games has its own reason to want.
    # EMPTY IS A MEASUREMENT, NOT A FINISHED JOB.
    "exmateria_schema": set(),
    # Seeded EMPTY on 2026-09-01 for #742 (ADR-0217 dec. 2) while the addon was a
    # SKELETON, seeded at 23 the same day when #744 moved 33 files in, drained to
    # 20 in that same pass, and DRAINED TO 0 ON 2026-09-02 BY #746. Every number
    # in that sentence was counted from the tree; #744's title and ADR-0217 both
    # said 24, and 24 was never right — `AnimationOpcodes` was the 24th and #742
    # (`d43fd371b`) had already stripped it when it landed the skeleton.
    #
    # EMPTY IS A MEASUREMENT, NOT A FINISHED JOB — the entry and both arms STAY,
    # which is the standing note on the four entries above and now means something
    # sharper here: this list held 23 names for one day, so the creep arm is the
    # only thing between the addon and a 24th.
    #
    # 🔴 WHAT #746 COST, BECAUSE THE PRICE WAS NOT WHAT ADR-0217 dec. 2 PREDICTED.
    # The prediction was nine published names carrying 18 behaviour members, the
    # other fifteen reached from nowhere outside the addon. Measured: EIGHTEEN
    # published names carrying THIRTY non-enum members plus one enum, over 53 host
    # files. #746's own acceptance criteria priced that outcome — "If it is more,
    # P1 is falsified at >24 non-enum members reached from outside — report the
    # number, do not tune the interface to hit it" — so P1 IS FALSIFIED and the
    # façade is the measured surface. `AnimationClock` and `PlaybackSet` are the
    # only two of the 20 with zero outside reach.
    #
    # The prediction came from `check_lattice_scene.py` ARM 1, which scores `res://`
    # PATH reaches. This file's whole subject — a host naming a global `class_name`
    # with no path anywhere — is invisible to arm 1, and that is where the twelve
    # unforeseen names lived. Two instruments, two channels, and the gap between
    # them is exactly the size of the miss. Do not read either one as the other
    # (SCOPE, above).
    "exmateria_sprite_rig": set(),
    # Extraction #5 (#945, ADR-0251). Seeded EMPTY on 2026-09-06, in the SAME
    # commit that created the directory — which is the first time that has been
    # possible, and it is not a virtue of this pass. `exmateria_sprite_rig` above
    # was seeded empty as a skeleton, went to 23 when #744 moved the files in, and
    # drained the next day; the three before it were seeded at 30 / 3 / 6 and
    # drained in place. Here the move and the shed are ONE commit because the
    # population was known before the folder existed (ADR-0243 dec. 4 measured it
    # on trunk with `tools/arm7_membership.py`), so there was never a tree state
    # with the files inside and the `class_name`s still on them.
    #
    # 🔴 THIRTY-TWO IS THE LARGEST SHED THIS REPO HAS DONE, and by collision risk
    # the worst set: `Gambit` (a chess term), `ItemDatabase`, `StatusRegistry`,
    # `TargetSelector`, `UnitRole`, `AbilityType`, `StatCalculator` — generic
    # English every tactics project has its own reason to want. ADR-0243 dec. 4
    # counted thirty-one; thirty-one is the count of names PUBLISHED on the façade
    # and the two agree only by coincidence (ADR-0251 dec. 6). `BaseStatsDatabase`
    # is the thirty-second: shed, and NOT published, because nothing outside the
    # addon names it.
    #
    # EMPTY IS A MEASUREMENT, NOT A FINISHED JOB — the entry and both arms STAY.
    "exmateria_almanac": set(),
    # Extraction #6 (#1025 pass 3, ADR-0262 dec. 11). Seeded EMPTY on 2026-09-08,
    # in the SAME commit that created the directory — the second pass able to do
    # that, for `exmateria_almanac`'s reason directly above: ADR-0262 dec. 2
    # measured the population on trunk with `tools/membership_arms.py` before the
    # folder existed, so there was never a tree state with the files inside and
    # the `class_name`s still on them.
    #
    # TEN NAMES SHED, TEN PUBLISHED — and the two counts agreeing is the thing to
    # distrust, because they nearly did not. `CharacterCatalog` is this project's
    # `[autoload]`, and 63 of its 65 host use sites reach it as a singleton, not
    # as a type; on a symbol census it publishes nothing (ADR-0262 dec. 7 counted
    # NINE for exactly that reason). The other TWO sites are
    # `tests/CharacterCatalogOwnedTest.gd:13` and `tests/StoryMutationScriptTest.gd:32`,
    # which `preload` the script by PATH and `.new()` a fresh catalogue on purpose.
    # A symbol census cannot see a path, so the tenth name was found by re-reading
    # the preloads, not by counting identifiers. Unpublished it would have left two
    # `res://addons/exmateria_catalogue/...` literals in host test code.
    #
    # By collision risk the set is mid-range but not benign: `Character`,
    # `UnitNames`, `ResidueManifest` and `SlugBinding` are generic English, and
    # `Character` in particular is a word any project with people in it wants.
    # `Character` was `CharacterClass` in `src/` and was renamed on the way in
    # (19 sites) — the old spelling was a workaround for exactly the collision
    # ADR-0212 dec. 1 abolishes, so the shed is what made the honest name safe.
    #
    # EMPTY IS A MEASUREMENT, NOT A FINISHED JOB — the entry and both arms STAY.
    "exmateria_catalogue": set(),
    # Extraction #7 (#1225, gl-ADR-0295 dec. 1). Seeded EMPTY on 2026-09-12, in the
    # SAME commit that created the directory — the third pass able to do that, for
    # `exmateria_almanac`'s reason: ADR-0286 dec. 2 measured the population on trunk
    # with `tools/membership_arms.py` before the folder existed, so there was never a
    # tree state with the files inside and the `class_name`s still on them.
    #
    # 🔴 FORTY-TWO SHED, TWENTY-ONE PUBLISHED — AND `45` IS THE NUMBER EVERY PLAN
    # DOCUMENT CARRIES. Both are right about different trees: the membership declared
    # 45 when ADR-0295 counted it, and #1220 took `PsxUnits`, `CameraCalib` and
    # `PSXCameraConvert` to `exmateria_platform` three commits before this one. 45 − 3
    # = 42, counted from the tree on the move commit. The larger shed remains
    # `exmateria_almanac`'s 32→0 by a different measure — this one is the largest in
    # NAMES and the second largest in files.
    #
    # By collision risk this is the worst set yet: `Particle`, `EffectData`,
    # `ScreenData`, `CameraData`, `TimelineData`, `TrapEffect`, `CallbackManager`,
    # `CallbackRegistry`, `Subsystem` — generic English that any project with a
    # particle system, a timeline or a camera has its own reason to want, and
    # `Particle` in particular is a word Godot itself nearly uses.
    #
    # 🔴 TWENTY-ONE PUBLISHED IS NOT THE SAME COUNT AS THE OUTSIDE REACH, BY DESIGN.
    # Fifteen further members are reached ONLY from `tests/` and `tools/` and are
    # deliberately unpublished (gl-ADR-0295 dec. 1); they are bound by `res://` path,
    # which is `check_lattice_scene.py` criterion 4's axis, and declared there. So
    # criterion 4 is non-zero for this addon at the move — read that number there, not
    # here (SCOPE, above). Extraction #4 took the opposite reading of the same trade.
    #
    # EMPTY IS A MEASUREMENT, NOT A FINISHED JOB — the entry and both arms STAY.
    "exmateria_effects": set(),
}

fails: list[str] = []


def fail(msg: str) -> None:
    fails.append(msg)
    print("FAIL: " + msg)


def ok(msg: str) -> None:
    print("ok:   " + msg)


def gd_files(root: Path) -> list[Path]:
    return sorted(p for p in root.rglob("*.gd") if not p.is_symlink())


def res_to_path(res: str) -> Path:
    """`res://x` -> the file under this package. One spelling, used twice."""
    return PKG / res.replace("res://", "")


def facade_file(addon: str) -> Path:
    """`addons/x/x.gd` — one spelling of dec. 1's location rule, used by every arm."""
    return ADDONS / addon / f"{addon}.gd"


# `class_name Foo extends Node` is ONE line and registers the same global as the
# bare form — the root guard's older pattern anchored on end-of-line and scored
# that spelling clean, so the set it compared was smaller than the real one.
CLASS_NAME = re.compile(
    r"^class_name\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:$|#|extends\s)"
)


def declared_class_names(root: Path) -> dict[str, str]:
    found: dict[str, str] = {}
    for f in gd_files(root):
        for line in f.read_text(errors="replace").splitlines():
            m = CLASS_NAME.match(line)
            if m:
                found[m.group(1)] = str(f.relative_to(PKG))
    return found


# --------------------------------------------------------------------------
# CREEP — the class_name set is the façade plus the burn-down, and no more
# --------------------------------------------------------------------------
def arm_creep(addon: str, facade: str, found: dict[str, str]) -> None:
    root = ADDONS / addon
    burn_down = BURN_DOWN.get(addon, set())
    if not root.is_dir():
        fail(f"{addon}: no such addon folder at {root}")
        return
    if not gd_files(root):
        fail(f"{addon}: holds no .gd files — this arm would pass vacuously")
        return

    extra = sorted(set(found) - {facade} - burn_down)
    if extra:
        fail(
            f"{addon}: {len(extra)} global `class_name`(s) beside the façade and "
            "outside the burn-down — "
            + ", ".join(f"{n} ({found[n]})" for n in extra)
            + ". Every one lands in a consumer's global scope, and if they declare "
            "a colliding name it is THIS addon's file that fails to parse. Publish "
            "it on the façade and `preload` it internally (ADR-0212 dec. 1)."
        )
    else:
        ok(
            f"{addon}: no `class_name` outside the façade and the burn-down "
            f"({len(found)} declared, {len(burn_down)} still owed)"
        )

    # The ratchet's SECOND arm. An entry that no longer violates is a failure,
    # so the list cannot rot into a permanent exemption.
    stale = sorted(burn_down - set(found))
    if stale:
        fail(
            f"{addon}: {len(stale)} BURN_DOWN entr(ies) name no `class_name` any "
            "more — " + ", ".join(stale) + ". The entry is deleted in the SAME "
            "commit as the `class_name` it names; a list that outlives its "
            "population is an exemption nobody reread."
        )
    else:
        ok(f"{addon}: every BURN_DOWN entry still names a live `class_name`")


# --------------------------------------------------------------------------
# ROT — every façade constant resolves
# --------------------------------------------------------------------------
def arm_rot(addon: str, facade: str, found: dict[str, str]) -> None:
    f = facade_file(addon)
    burn_down = BURN_DOWN.get(addon, set())

    if facade not in found:
        # Before the migration lands there is no façade to rot. Stated rather
        # than silently skipped, and it stops being tolerated the moment the
        # burn-down empties — at which point a missing façade means the whole
        # public surface is gone.
        if burn_down:
            ok(
                f"{addon}: façade `{facade}` not declared yet — ADR-0212 dec. 1 is "
                f"not built ({len(burn_down)} name(s) owed). THIS ARM IS INERT and "
                "says so; it becomes a hard failure when the burn-down empties."
            )
        else:
            fail(
                f"{addon}: no file declares `class_name {facade}` and the burn-down "
                "is empty. The façade is the addon's whole public surface; without "
                "it nothing downstream can name anything."
            )
        return

    if Path(found[facade]).name != f"{addon}.gd":
        fail(
            f"{addon}: `class_name {facade}` is in {found[facade]}, not "
            f"addons/{addon}/{addon}.gd — the façade lives in the file named after "
            "its addon so a stranger can find it."
        )
    if not f.is_file():
        fail(f"{addon}: no façade file at addons/{addon}/{addon}.gd")
        return

    consts = _PUBLISHED_CONST.findall(f.read_text(errors="replace"))
    if not consts:
        fail(
            f"{addon}: the façade publishes nothing. A façade with no constants is "
            "not a public surface, and this arm would have nothing to check."
        )
        return

    # 🔴 The `ok` below is GUARDED. It used to be unconditional, so a tree with a
    # dangling constant printed both the FAIL and "N façade constant(s) all resolve"
    # — the verdict was still red, but the log said the opposite of the defect two
    # lines under it. Found by seeding #743's published `ContentPort` at a path that
    # does not exist.
    rotted = 0
    for name, path in consts:
        if not path.startswith("res://addons/"):
            rotted += 1
            fail(
                f"{addon}: `{facade}.{name}` points outside addons/ ({path}) — a "
                "published path a consumer does not install is a dangling one"
            )
            continue
        if not res_to_path(path).is_file():
            rotted += 1
            fail(
                f"{addon}: `{facade}.{name}` preloads {path}, which does not exist. "
                "This is the rot arm: the name is still published and the file "
                "behind it is gone."
            )
    if not rotted:
        ok(f"{addon}: {len(consts)} façade constant(s) all resolve")


_CITED_HOST_FILE = re.compile(r"(?:src|tools|tests|addons|assets)/[\w/\.\-]+\.gd")

# ADR-0212 dec. 7. A citation MAY name a sibling addon PROVIDED IT SAYS SO, and
# these are the words that say it — the way ADR-0211 dec. 5 made a test-only
# entry carry `test-only namer`. Matched case-insensitively so the house
# `**SIBLING NAMER**` emphasis reads the same as plain prose.
_SIBLING_NAMER = "sibling namer"

# ADR-0217 dec. 5, mechanizing ADR-0215 dec. 4. A citation MAY name a `.gd` inside
# the addon's OWN root — an in-addon viewer or adapter is a real consumer — but it
# is NOT the same evidence as a host use, so it carries its own words. Same
# case-insensitive match as the sibling label, for the same reason.
_INADDON_NAMER = "in-addon namer"

_ADDON_CITE = re.compile(r"^addons/([^/]+)/")


def facade_citations(addon: str, text: str | None = None) -> dict:
    """`{published name: ([host files cited], stated a host use?, comment blob)}` —
    ADR-0210 dec. 1, on the channel ADR-0211 moved those comments to.

    🔴 WHY THIS EXISTS AT ALL. Before the façade, eleven of these names sat on
    `check_lattice_publish.DECLARED_PUBLISHED`, where ADR-0208 dec. 6 made the per-entry
    host-use comment STRUCTURAL and ADR-0210 dec. 1 ratcheted the citation inside it: the
    cited file must exist, and it must still name the symbol. ADR-0211 collapsed that list
    to one name and the fourteen per-name comments moved HERE — where, for one commit,
    nothing read them. That is a silent loss of an enforced invariant, which is the exact
    failure this repo keeps re-finding: the population moved and the instrument did not.

    Takes `text` so the seeds can construct a façade instead of reading the shipped one.
    """
    src = (facade_file(addon).read_text(errors="replace") if text is None else text)
    out, comment = {}, []
    for line in src.splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            comment.append(stripped)
        else:
            m = _PUBLISHED_CONST.match(stripped)
            if m:
                blob = " ".join(comment)
                out[m.group(1)] = (sorted(set(_CITED_HOST_FILE.findall(blob))),
                                   bool(comment),
                                   blob)
            comment = []
    return out


def arm_citations(addon: str, facade: str) -> None:
    """ADR-0208 dec. 6 + ADR-0210 dec. 1, applied to each façade's published constants.

    Four claims, in the order they rot:

      - PRESENCE. A constant with no comment above it is a name nobody reread. Dec. 6
        makes the host-use sentence structural; this is the only half of it a machine
        can read, and it was mechanized one list over before it was mechanized here.
      - ROT ONE. A comment that names a host `.gd` makes a claim about the tree, and a
        claim about the tree goes stale when the file MOVES.
      - ROT TWO. The file is still there and no longer names the symbol.
      - SIBLING (ADR-0212 dec. 7). A citation naming a `.gd` inside ANOTHER addon is a
        valid host use — `exmateria_schema`'s heaviest consumers live inside
        `exmateria_battlefield`, so a `src/`-only rule would leave `Fold`'s most
        load-bearing use uncitable — but the entry must SAY that is what it is, or a
        reader cannot tell an addon consumer from a host one at a glance. The
        relationship is already declared in `plugin.cfg` `deps=` and already staged by
        `tests/stranger/shared/rig.sh`, so the citation records something checked
        rather than something assumed.
      - IN-ADDON (ADR-0217 dec. 5, mechanizing ADR-0215 dec. 4). A citation naming a
        `.gd` inside the addon's OWN root must say so too, and until this arm existed
        it passed SILENTLY — which is the one shape dec. 4's test is about. Dec. 4
        asks *"if it needs a member `Unit.gd` does not, that member is published; if
        it needs a private, the interface is wrong"*, and a member published solely
        because the addon's own viewer wants it is the interface having shrunk to what
        one adapter wanted. That is not a failure by itself — an addon is allowed an
        in-addon consumer — so the arm asks for the WORDS and then REPORTS THE COUNT.
        🔴 THE NUMBER IS THE POINT, NOT THE FAILURE: a viewer-only count above
        zero is what pass 9 reads, and a count that is never printed is a count nobody
        reads the day it moves.

    🔴 AN ENTRY THAT CITES NOTHING IS NOT SCORED BY THE ROT ARMS, and that blind spot is
    stated rather than hidden — it is inherited verbatim from `check_lattice_publish`.
    Prose that names a class or a method (`TileHighlights` names three host controllers;
    `TileCursorCompositor` says ⚠️ NO HOST NAMER TODAY and means it) is house style, and
    scoring it would red a correct comment. Presence still covers those.

    🔴 THIS DOES MAKE DELETING THE LAST HOST CALL SITE RED THE ARM. Same direction
    ADR-0210 dec. 1 already ruled acceptable: the name stays published and the remedy is
    to re-read the comment, not to restore the call."""
    if not facade_file(addon).is_file():
        return                                   # arm_rot already said so, once
    cites = facade_citations(addon)
    if not cites:
        return                                   # arm_rot already said so, once

    silent = [n for n, (_f, has, _b) in cites.items() if not has]
    if silent:
        fail(f"{addon}: {len(silent)} façade constant(s) state no host use — "
             f"{', '.join(sorted(silent))}. ADR-0208 dec. 6: a name joins the published "
             "surface in a pass that says what host use it serves.")

    moved, quiet, unlabelled, bare_in_addon = [], [], [], []
    labelled_in_addon = 0
    for name, (files, _has, blob) in sorted(cites.items()):
        low = blob.lower()
        says_sibling = _SIBLING_NAMER in low
        says_in_addon = _INADDON_NAMER in low
        for rel in files:
            q = PKG / rel
            m = _ADDON_CITE.match(rel)
            if m and m.group(1) != addon and not says_sibling:
                unlabelled.append((name, rel))
            elif m and m.group(1) == addon:
                # ONE `_ADDON_CITE` match, two relationships. Reading either label
                # for either would make the count meaningless: a sibling citation
                # would book itself as an in-addon one and dec. 7 would never fire.
                if says_in_addon:
                    labelled_in_addon += 1
                else:
                    bare_in_addon.append((name, rel))
            if not q.is_file():
                moved.append((name, rel))
            elif name not in q.read_text(errors="ignore"):
                quiet.append((name, rel))
    for name, rel in moved:
        fail(f"{addon}: `{facade}.{name}` cites {rel}, which has MOVED or been deleted "
             "(ADR-0210 dec. 1)")
    for name, rel in quiet:
        fail(f"{addon}: `{facade}.{name}` cites {rel}, which no longer names it — "
             "re-read the comment (ADR-0210 dec. 1)")
    for name, rel in unlabelled:
        fail(f"{addon}: `{facade}.{name}` cites {rel} — a SIBLING ADDON, which is a "
             "valid host use, but the entry must say so with the words "
             f"'{_SIBLING_NAMER}' (ADR-0212 dec. 7). A reader cannot otherwise tell an "
             "addon consumer from a host one, and the two are staged differently.")
    for name, rel in bare_in_addon:
        fail(f"{addon}: `{facade}.{name}` cites {rel} — a file INSIDE THIS ADDON, "
             "which is NOT the same evidence as a host use: a name published only "
             "because this addon's own viewer or adapter wants it is the interface "
             "having shrunk to what one adapter wanted (ADR-0215 dec. 4). It may still "
             f"be right, so say so with the words '{_INADDON_NAMER}' (ADR-0217 dec. 5) "
             "— the label is what turns it into a count pass 9 can read instead of a "
             "citation that reads like a host use and is not one.")
    # REPORTED, scores nothing — the shape `check_lattice_scene.symlink_probe` uses,
    # and printed on the FAILING path too, because a number that only appears when
    # everything else is green is missing on the one day it moved.
    print(f"      {addon}: {labelled_in_addon} labelled IN-ADDON citation(s) — "
          "REPORTED, scores nothing (ADR-0217 dec. 5). Above zero means the published "
          "surface carries names only this addon's own consumer asked for.")
    if not (silent or moved or quiet or unlabelled or bare_in_addon):
        n = sum(len(f) for f, _has, _b in cites.values())
        ok(f"{addon}: {len(cites)} published name(s) state a host use; {n} citation(s) "
           "resolve and still name their symbol")


def main() -> int:
    # Cleared per call, not per process. `fails` is module state, and the seed
    # tests call `main()` repeatedly — without this the second seed inherits the
    # first one's failures and every arm after it "fires" for free.
    fails.clear()
    owed = {a: len(BURN_DOWN.get(a, set())) for a in FACADES}
    print("check_addon_globals.py — ADR-0212: each addon owns ONE global name, "
          "and it is the folder-named façade")
    print(f"  subject: {len(FACADES)} addon(s) under addons/ — the `class_name` "
          "channel only")
    for addon, facade in sorted(FACADES.items()):
        print(f"    {addon:<24} façade {facade:<22} burn-down "
              f"{owed[addon]} name(s) owed, target 0")
    print("  🔴 NOT axis B (check_addon_install), NOT the path channel")
    print("     (check_lattice_scene criterion 4), NOT the shader #include")
    print("     channel (ADR-0212 dec. 5). Say the other numbers too.")
    print()

    for addon, facade in sorted(FACADES.items()):
        root = ADDONS / addon
        found = declared_class_names(root) if root.is_dir() else {}
        arm_creep(addon, facade, found)
        arm_rot(addon, facade, found)
        arm_citations(addon, facade)
        print()

    if fails:
        print(f"check_addon_globals: {len(fails)} failure(s)")
        return 1
    total_owed = sum(owed.values())
    if total_owed:
        still = ", ".join(f"{a} {owed[a]}" for a in sorted(owed) if owed[a])
        print(
            f"check_addon_globals: NOT A PASS — {total_owed} `class_name`(s) "
            f"still global ({still}), target 0. Every one is NAMED above with an "
            "owner; the creep, rot and citation arms are enforcing around them "
            "(ADR-0212 dec. 6)."
        )
        return 0
    print(f"check_addon_globals: the global surface is {len(FACADES)} name(s), "
          "one per addon — "
          + ", ".join(f"`{FACADES[a]}`" for a in sorted(FACADES)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
