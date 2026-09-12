#!/usr/bin/env python3
"""Enforce goal #5 — an extracted addon reaches no SYSTEM, only ports, AND PARSES ALONE.

    python3 tools/check_addon_portability.py
    python3 tools/check_addon_portability.py --root ../exmateria-sound/addons/exmateria_sound --system Audio

Goal #5's literal test is *"a system could ship to another tactics RPG with its
interface intact"*, and this guard mechanizes it along ELEVEN arms: 1, 2, 2b, 3, 4,
4b, 5, 6, 7, 8, 8b below, and the green sentence at the bottom of `main()` is the
one-line version of the same list. It shipped with four and the word has gone stale
THREE times against that list -- twice before it was written down here and once when
this line still read SEVEN over eight labels -- so the word is no longer maintained
by hand: `test_the_spelled_arm_count_equals_the_enumerated_arms` recounts the
headings below and fails on the word. (ELEVEN arms over ELEVEN systems is a
coincidence of two counts that move independently; neither number is read off the
other.)

  1. REACH — nothing under an addon root names a symbol the classifier books to
     one of the eleven systems. A `platform` port (`Tune`) and the `schema`
     kernel are fine and are the point (ADR-0139 dec. 12, ADR-0140 dec. 9).
  2. STANDALONE PARSE — nothing under an addon root names a bare identifier that
     only an AUTOLOAD BLOCK declares. An autoload name is created by a
     *project*, never by the addon, so a file that writes one cannot parse in a
     project that does not autoload it — including the addon's own.
  2b. AUTOLOAD BY NODE PATH — nothing under an addon root hands a HOST autoload's
     name to `get_node`/`get_node_or_null`/`has_node`/`find_child` as a STRING.
     Arm 2's subject in a third spelling, which arm 2 structurally cannot see; free
     for the kernel, the platform port and an addon's own singleton (#648, ADR-0191).
  3. HOST #include PATH — no `#include` under an addon root reaches a file
     outside every addon root. Shipping the addon ships the file; it does not
     ship what the file includes (ADR-0169 dec. 5).
  4. SHADER GLOBALS — nothing under an addon root binds a `[shader_globals]`
     name the addon's own project does not declare, on EITHER side: the shader
     `global uniform` that reads it or the `global_shader_parameter_set` that
     pushes it (ADR-0169 dec. 5, subject widened by ADR-0171 dec. 5).
  4b. GLOBAL UNIFORM OWNER — only a NON-system addon may DECLARE one (ADR-0190).
  5. SIBLING class_name — arm 1 one level down, symbol -> SIBLING ADDON rather than
     symbol -> system, resolved THROUGH a façade alias (ADR-0175 dec. 2, #722).
  6. RES:// PATH — no quoted `res://` literal under an addon root addresses a target
     outside every addon root. The PATH axis of the same sentence, and the arm that
     covers the kernel and the port, which arm 1 skips because they are not systems
     (#658).
  7. HOST class_name — nothing under an addon root names a `class_name` DECLARED
     outside every addon root. Arm 5 one level OUT: arm 5 asks whether the
     declaring root is a sibling ADDON and builds its map from the addon roots
     alone, so a type declared in `src/` is in no map any other arm reads. The
     TYPE axis of arm 6's sentence, and a `class_name` is bound at parse time, so
     a port cannot answer it (ADR-0223).
  8. DECLARED DEPENDENCIES — `plugin.cfg`'s `deps=` names every sibling addon
     this one reaches, and no others. Arm 5 MEASURES the reach; this compares the
     measurement to the DECLARATION, both directions (#1241, #1239).
  8b. CLOSURE ENGINE — the binary `tests/stranger/shared/rig.sh` boots follows the
     dependency CLOSURE, not the subject's own `engine=`, so a `deps=` edit is a
     possible ENGINE change. The pair is printed and the divergences are a named
     register, both directions (#1241, #1099).

WHY ARM 1 EXISTS. ADR-0140 dec. 8 named its own soft spot and declined to close
it: *"nothing in this ADR stops the 40th panel from extending the base class
again. A guard would, and this ADR does not write one."* Extraction #1 then
shipped exactly that — two panels inside a portable addon still `extends
BaseDebugPanel`. This is that guard (ADR-0151).

WHY ARM 2 EXISTS, AND WHY ARM 1 COULD NEVER HAVE CAUGHT IT. Extraction #2 lifted
`spu_audio_debug_panel.gd` into the sound package specifically to satisfy goal #5
(ADR-0153 dec. 4) and it did not parse:

    godot --path exmateria-sound --check-only \
        -s res://addons/exmateria_sound/debug/spu_audio_debug_panel.gd
    Parse Error: Identifier "ExMateriaEffectSfx" not declared in the current scope.  x5

`ExMateriaEffectSfx` is the package's OWN singleton, so arm 1 is right to stay
silent: the reach does not leave the package and books to no system. What breaks
is narrower and arm 1 has no vocabulary for it — the *name* is the host's
`project.godot`, and the package declares no autoloads at all. The same defect
sat on `effect_sfx_engine.gd`'s 13 `ExMateriaAudioEngine` lines, i.e. on the package's
always-on driver, not just a debug view.

WHY THIS GUARD WAS GREEN WHILE BOTH WERE TRUE, WHICH IS THE REAL FINDING. It
scanned `_walk_roots.addon_roots()` — the addon members of
`classify_blueprint.WALK_ROOTS` — and WALK_ROOTS deliberately EXCLUDES
`addons/exmateria_sound` (#326: it is a deployment copy, walking it double-counts).
So on the branch that extracted the Audio system into that package, this guard
printed

    subject: addons/exmateria_render (addon roots in classify_blueprint.WALK_ROOTS)

and exited 0 without ever opening a file the extraction produced. That is the
ADR-0148 pattern the same branch warns about three times: green because it
stopped looking. `_walk_roots.extracted_roots()` exists for exactly this — its
docstring already NAMES this file as one of the five instruments blind at the
extraction boundary — and the subject line above is what made the hole legible.
Both are now subjects.

ARM 2 IS A FLOOR, NOT THE INSTRUMENT. The instrument is
`godot --path <pkg> --check-only -s <file>`, which is truth and costs ~2s per
file (156 files, and it needs a warm class cache). Autoload names are the class
of standalone break this repo has actually shipped twice; a `class_name` a
consumer happens to define would be another. Run the real check before a release.

STRICT WHERE IT IS TESTABLE. An addon that ships with its OWN `project.godot`
(`exmateria-sound/`) can be parsed standalone, so arm 2 is RED there. An addon
that still lives inside the host project (`addons/exmateria_render`) has no
standalone project to parse against, so its reaches are reported as DEBT and do
not fail: `exmateria_render` names `Tune` on 16 lines, which ADR-0139 dec. 12
expressly permits as a platform port and which is nonetheless a standalone-parse
break the next extraction has to answer. Printing it beats both hiding it and
failing a branch that did not create it.

WHY ARMS 3 AND 4 EXIST, AND WHY THEY ARE THE SAME DEFECT IN TWO MORE LANGUAGES.
Arm 2's sentence is *"the name is the host's `project.godot`"*. A shader says that
sentence twice more and neither one is a GDScript identifier, so arms 1 and 2 have
no vocabulary for either (ADR-0169 dec. 4):

  3. HOST #include PATH — a `#include` under an addon root whose target lies
     outside every addon root. ENFORCING, because it is checkable without a
     standalone project: the path either resolves inside an addon root or it does
     not. Green on all three subjects today; the failure it is armed against is
     pass 6 dropping one of nineteen `#include` rewrites, which is a failure mode
     *"a note in a document cannot catch"* (ADR-0169 dec. 5).
  4. SHADER GLOBALS — a `[shader_globals]` name bound from an addon root. The
     engine's answer here is QUIETER than arm 2's, not stricter, and ADR-0238
     corrects ADR-0169 dec. 4 on exactly that: a missing autoload name is a parse
     error in one file, and a missing global uniform is NOTHING outside the editor
     -- `shader_language.cpp` gates the check on `Engine::is_editor_hint()`, so the
     shader compiles, the name reads its type's zero, and the only report is a
     draw-time warning per material. ADR-0169 measured the blast radius as *"the
     direct count is 8 and the compile-failure count is 14 of 16"*, and that reach
     is still right; it is the failure MODE that was wrong. Follows arm 2's
     strictness rule: DEBT for an addon with no `project.godot` of its own, RED for
     a package that has one.

ARM 4 READS BOTH SIDES, AND THE SPECIFICATION ONLY HAD ONE. ADR-0169 dec. 5 scoped
arm 4 to *"any `global uniform` reachable from an addon root"* -- a DECLARATION
scan. ADR-0171 dec. 5 found the hole: `PSXDisplay.gd` declares no `global uniform`
and never will, because it is the CPU half. It **pushes** five of them by name
through `RenderingServer.global_shader_parameter_set`, and it is under an addon
root RIGHT NOW (`addons/exmateria_render/display_port/`), not only after the pass-6
relocation the ADR describes. A declaration-only arm reads that file and reports
nothing.

The two sides are not redundant, and the sharp case proves it. `psx_gamma` is the
extreme: NO addon file declares it anywhere, its `[shader_globals]` entry stays in
the host's `project.godot` (`:882`, value 1.4), and the ONLY evidence inside an addon
root that the name is load-bearing at all is
`addons/exmateria_platform/display_port/PSXDisplay.gd:193` (`_apply_gamma`) pushing
it, bound to the `render.psx_gamma` tunable at `:103-104`. Read declarations alone
and the name is invisible.

    🔴 FOUR NUMBERS IN THIS PARAGRAPH WERE STALE, re-measured 2026-09-11 (#1217).
    It read: *"Of the six `[shader_globals]` entries this addon family binds, only
    `pixel_aspect` and `psx_dither_enabled` are declared by a file that moves with
    the addon; the declarations of the other four stay in consumers that do not
    move. `psx_gamma` is the extreme -- 22 shader files read it ...
    `PSXDisplay.gd:147` pushing it."* Measured: there are **seven** entries, **six**
    are declared inside `addons/exmateria_platform/` (`pixel_aspect`,
    `psx_dither_enabled`, `psx_camera_angle`, `unit_stretch`, `psx_fx_stretch`,
    `psx_cursor_stretch` — the last two via ADR-0220 dec. 2 and #1217 (b)), and
    `psx_gamma` is the ONLY one that is not. Its readers are **three**, all in
    `src/ui3/shaders/` (`formation_box.gdshader:20`, `formation_box_sub.gdshader:20`,
    `formation_orb.gdshader:26`) — and those shaders declare it themselves
    (`formation_box.gdshaderinc:27`, `formation_orb.gdshaderinc:20`), so the name
    never leaves `UI`. The four `tools/probe_shaders/effect_particle_mode*` copies
    used to reach it through the extraction-#7 membership and now carry a local
    `const float psx_gamma = 1.4;` (#1198, #1217 (c)). "22 shader files" was never 22
    of anything this file can point at, and the push site had drifted 46 lines. The
    ARGUMENT is untouched — a declaration-only arm still cannot see a pushed name —
    and it now rests on numbers that were taken rather than remembered, which is the
    whole of ADR-0290 dec. 10.

It is an ENFORCING gate, not a scorecard. `tools/score_goals.py` records what an
extraction achieved and is green while a goal is honestly `open`; this is red the
moment an addon acquires a system reach or a host-autoload name, which is the arm
a scorecard cannot have. The reach scan is `score_goals.outbound_reaches` — one
implementation, not two.

ITS SUBJECT IS THE WALK, AND THAT IS A REAL LIMIT ON THE RULE. `addon_roots()`
is `classify_blueprint.WALK_ROOTS`, which deliberately excludes a system that
extracts into a PUBLISHED PACKAGE — `exmateria-sound/addons/exmateria_sound/` is
outside it and stays outside it (ADR-0153 dec. 1). So for `Audio`, and for every
later system that ships as its own package, **the file does not leave this guard
because it stops inheriting; it leaves because it leaves the walk**, and
ADR-0151's rule would revert to a convention at exactly the moment it starts to
matter.

`_walk_roots.EXTRACTED` closes it: the one declared list of where the source that
left the walk went, read by this guard, by `score_goals.py` and by `residue.py`
rather than invented three times. `--root <path> --system <name>` remains for a
package not yet declared there.

THE COMPANION CHANGE. Retiring `extends BaseDebugPanel` makes a panel invisible
to `check_debug_panel_tunables.py`, whose whole contract keys on that line. The
two cannot land apart or this guard buys four edges and silently costs the other
guard its coverage — the ADR-0148 stale-root defect wearing a marker instead of
a root. That guard's marker was widened in the same commit as this file.
"""
import sys, os, re, pathlib, collections, functools, importlib.util

PROJECT_DIR = pathlib.Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("score_goals", PROJECT_DIR / "tools" / "score_goals.py")
_sg = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_sg)


# --- arm 1's burn-down (ADR-0184 dec. 4) ----------------------------------
# `(addon file, symbol) -> (owner, why)`. A named list, never a pattern: #424
# measured on this codebase that an exclusion expressed as a FILTER manufactures
# its own debt and cannot tell a triaged break from one that merely matches.
# BOTH directions fail — an unlisted reach, and a listed reach that no longer
# happens (or whose file is gone) — so the list cannot rot quietly. The shape is
# `check_par_shaders.BURN_DOWN`, which has carried eleven `UI` shaders the same
# way since ADR-0060.
#
# WHY ARM 1 NEEDS ONE AT ALL, WHICH IS THE FINDING. Extractions #1 and #2 never
# put it to the test: `Render`'s addon had zero outbound system reach, and `Audio`
# left the walk into a package. `Battlefield` is the first system extracted WITH
# outbound debt, and that debt was measured and accepted before the move —
# ADR-0157 dec. 2 enumerates nine lines by file and line number and chooses the
# system anyway, on dec. 3's inbound reading. The move does not create these
# reaches; it makes them VISIBLE, because arm 1 cannot see a `src/` file.
#
# The alternative is that the address cannot land until all four seam builds land
# with it, in one unreviewable commit — which contradicts the pass's own ruling
# that pass 6 is multi-session fan-out. Under a strictly-green arm 1 a SPLIT
# pass 6 is not merely awkward, it is impossible: every ticket but the last has
# arm 1 red by construction. This list is where that split is written down.
# Extraction #7's `Debug.DebugConfig` reach — seeded by #1225, PAID by #1218 on
# 2026-09-12, and recorded here because the number it moved is the one this file
# exists to publish. It was the single largest reach out of any addon root: **61
# lines over 19 files**, 91% of `addons/exmateria_effects`'s whole arm 1, and every
# one a VERBOSITY READ guarding a `print`. ADR-0141 rules the logging sink
# non-counting for the SELECTION question — which is why ADR-0288 dec. 10 predicted
# arm 1 = 3 with these subtracted — and this register is the other question, for
# which the sink counts: an addon that does not parse where `DebugConfig` is absent
# is not installable, whatever the line does when it runs.
#
# `addons/exmateria_effects/install/EffectsDebug.gd` is what paid it — four `debug.*`
# slugs bound through `ExMateriaPlatform.TunePort`, transcribed from
# `addons/exmateria_sprite_rig/install/RigDebug.gd`. The 19 rows that used to stand
# here are DELETED rather than annotated, because the stale arm below is the half of
# this register that scores a list outliving its debt. What the reach cost is now
# only readable in git and in #1218; what it BOUGHT is the 6 below.


ARM1_BURN_DOWN = {
    # IT WAS EMPTY TWICE, AND THE HISTORY IS WHY THE ROWS BELOW ARE NAMED ONE AT A TIME. ADR-0184 dec. 4's six `Battlefield`
    # rows were paid one at a time; #1025 pass 3 put one back
    # (`exmateria_catalogue/templates/CharacterTemplateResolver.gd` ->
    # `ExMateriaSpriteRig`, the palette-row pass-through) and #1071 paid it by
    # deleting the KEY rather than by injecting a port — the row was a render fact
    # the resolver carried and no caller read (ADR-0272). An empty list is not a
    # quiet list: `test_the_green_sentence_is_qualified_EXACTLY_WHEN_arm_1_has_a_row`
    # seeds a reach back into the walk to hold the caveat's other direction, so this
    # file going empty cannot make that arm vacuous.
    #
    # 🔴 IT IS NOT EMPTY ANY MORE, SINCE 2026-09-12. Extraction #7 (#1225) put
    # `addons/exmateria_effects` in the walk and 23 rows arrived with the move: 19
    # `DebugConfig` logging rows plus the four TYPE reaches priced one at a time, each
    # with a DIFFERENT answer — delete it (#1192), invert it elsewhere (#1193), widen it
    # (#1219), keep it (`ExMateriaRender`). #1218 paid the 19 and #1219 the widening, so
    # the list went 0 -> 23 -> 4 -> 3 inside one pass. A pin on this list's size has now
    # been wrong in four directions, which is the shape
    # `test_the_green_sentence_is_qualified_EXACTLY_WHEN_arm_1_has_a_row` records.
    # --- extraction #7's TYPE reaches, each with its own answer. ADR-0288 dec. 8 priced
    # three before the move and all three are still here; a FOURTH — the `Unit` annotation
    # set on `EffectManager.gd`, ADR-0288 dec. 3's — was paid by #1219 the day after the
    # move and took `ARM7_BURN_DOWN` to 0 with it. See that list's note for the argument.
    # \U0001f7e2 PAID AT #1192 (2026-09-12). The row was
    # `subsystem/PaletteSubsystem.gd -> ExMateriaBattlefield`, four lines naming
    # `MapIlluminationDDA` for the Holy/E015 additive map flood. ADR-0208 dec. 5 declined to
    # delete it once — *"a counter is a weak reason"* — and what closed it was not a counter:
    # #1192 asked for the run its own caveat said was missing, and a probe in
    # `build_illumination` fired 2x in its unit test (the positive control) and 0x across
    # eight battle and effect-playback scenes. The owner then ruled the future
    # untextured-terrain scope dead, and ADR-0287 dec. 5 forbids carrying dead code into a
    # published addon. Producer and sink went together — see `TintedSurfaces`' header for
    # why deleting one and keeping the other was not available.
    ("addons/exmateria_effects/camera/CinematicFacingResolver.gd", "ExMateriaBattlefield"):
        ("#1193",
         "INVERTIBLE, AND NOT OURS TO INVERT. `_sample_visible` marches the map lattice to "
         "answer *is this silhouette point visible from the camera?* — a `Battlefield` query "
         "`Effects` is computing by hand. The fix is for `Battlefield` to publish "
         "`is_visible_from(origin, eye)`; ADR-0288 dec. 8 recommends it and scopes it out of "
         "extraction #7."),
    ("addons/exmateria_effects/render/EngineFoldCompositor.gd", "ExMateriaRender"):
        ("ADR-0288 dec. 8 — ARGUED PERMANENT",
         "HONEST AND IT STAYS. `Render` owns the display-space scratch lifecycle (ADR-0074) "
         "and this compositor installs one `FoldSurface`; `Effects` folds THROUGH `Render`, "
         "which is a true sentence about the design rather than a spelling to remove. "
         "Declared debt with no ticket, on purpose — and declared in "
         "`addons/exmateria_effects/plugin.cfg` `deps=` so a rig stages it."),
}


# --- arm 6's burn-down (#658, arm 1's shape) -------------------------------
# `(addon file, res:// target) -> (owner, why)`. Arm 1's rule verbatim, and for arm 1's
# reason: a named list and never a pattern (#424). BOTH directions fail — an unlisted
# reach, and a listed reach that no longer happens.
#
# THREE ROWS, AND THEY ARE NOT ONE KIND, WHICH IS WHY THE LIST IS TRIAGE AND NOT A
# FILTER. #658 asks whether an asset reach is the same defect as a code reach and
# answers "the eleven have to be triaged, not just listed"; eight of its eleven are
# already gone (ADR-0202/ADR-0204 put `exmateria_battlefield` on a host-injected content
# root and the rest were prose), and what is left splits two ways. A pattern like "skip a
# bare scheme root" would excuse rows 2 and 3 AND excuse `res://assets/maps/`, which is a
# real dependency. Naming them is the only way to say they differ.
# --- arm 2's burn-down (#1225, ADR-0308 dec. 1) ---------------------------
# `(addon file, autoload name) -> (owner, why)`. Arms 1/6/7's shape, and EMPTY, which
# is the whole point of adding it.
#
# 🔴 WHY THIS LIST EXISTS AT ALL: ARM 2 USED TO HAVE TWO VERDICTS FOR ONE QUESTION.
# An addon with its own `project.godot` was RED (`STANDALONE PARSE`); an in-walk addon
# with none was a printed `standalone-parse DEBT` block whose heading read *"Not
# enforced (there is no standalone project to parse against yet)"*. That reason was
# TRUE when it was written and had been false for some time: ADR-0238 already struck
# the identical sentence out of arm 4 — *"There ARE standalone projects now -- six
# stranger rigs"* — and there are now EIGHT, one per in-walk addon, every one of them
# declaring an empty `[autoload]` block (ADR-0308 §1). So the set of addons the DEBT
# branch covered and the set with a rig to fail against are the same set, and the
# branch was measuring the absence of a thing that had arrived.
#
# 🔴 AND IT WAS COSTING A REAL MEASUREMENT, NOT JUST TIDINESS. All 26 of the debt
# block's lines were `addons/exmateria_effects`, and they were the addon's LAST
# install blocker: three of its five `known_failures.tsv` rows were exactly three of
# those files. The rig failed them one file at a time, by name, while this arm printed
# them as an unenforced number — two instruments, one defect, and only the slow one
# scoring it. #1225 paid all 26 (two in-addon overlay ports plus
# `ExMateriaPlatform.SfxPort`), which is what makes flipping this free: the corpus-wide
# count is 0, so enforcement changes no verdict TODAY and changes every verdict after.
#
# A row here would say: this addon names a host `[autoload]` identifier, we know, it is
# ticketed, and goal #5's install half is unmet for it on record. BOTH directions fail,
# arms 1/6/7's rule — an unlisted reach, and a listed reach that no longer happens — so
# a list that outlives its debt cannot re-admit the reach under a green guard, which is
# the arm ADR-0308 dec. 5 names as the one a one-armed ratchet misses.
#
# ⚠️ BEFORE ADDING A ROW, CHECK WHICH ADDON SHIPS THE SCRIPT THE AUTOLOAD POINTS AT.
# Arm 2b's remedy note is the rule and it splits on ownership, not on compilability: if
# THIS addon ships the script, the fix is a node-path bind and needs no row here (#1225
# did that for `TintedSurfaces` and `ScreenEffectOverlay`). Only a reach into a script
# the addon does NOT ship needs a port — or a row.
ARM2_BURN_DOWN = {}


ARM6_BURN_DOWN = {
    ("../exmateria-sound/addons/exmateria_sound/runtime/audio_engine.gd",
     "res://assets/music/WAVESET.WD"):
        ("#726",
         "REAL, and the file says the opposite: `audio_engine.gd`'s own docstring reads "
         "*\"nothing in this file names a host symbol, which is what makes it liftable\"* "
         "-- true on the SYMBOL axis and false on the path axis, which is #658's whole "
         "point. The consumer must supply `assets/music/WAVESET.WD` at that exact "
         "address. The shape that pays it is ADR-0202's host-injected content root, which "
         "is a RUNTIME change to an autoload and does not belong in a guard pass."),
    ("../exmateria-sound/addons/exmateria_sound/runtime/asset_paths.gd", "res://"):
        ("#726",
         "NOT a dependency. `ProjectSettings.globalize_path(\"res://\")` asks the engine "
         "where the project root is in order to walk UP out of it looking for "
         "`project-assets/fft-extract/`; it names no file the consumer must supply. On the "
         "list because the alternative is a pattern, and a pattern that excused a bare "
         "scheme root would also excuse `res://assets/maps/`."),
    ("../exmateria-sound/addons/exmateria_sound/runtime/asset_paths.gd", "res://renders"):
        ("#726",
         "NOT a dependency -- an OUTPUT directory default for rendered WAVs, already "
         "overridable by `FFT_SYNTH_OUT_DIR`. It creates the address rather than "
         "requiring it."),
    # --- extraction #7's TEN effect-content literals are PAID, and the register keeps the
    # reading rather than the rows. #1225 seeded ten `res://assets/…` addresses across three
    # files — the per-effect `E###` directory (3 sites, 1 row), the per-callback
    # `callback_data.json`, the four TRAP config tables and the `TRAP1` texture/palette pair.
    # ADR-0202 dec. 5's host-injected content root paid all ten on 2026-09-12:
    # `addons/exmateria_effects/install/EffectsContent.gd`, transcribed from
    # `BattlefieldContent.gd`, and the host declares `exmateria_effects/content_root`.
    #
    # 🔴 TWO PREDICTIONS ABOUT THESE ROWS WERE WRONG, AND BOTH IN THE SAME DIRECTION.
    #   * ADR-0288 dec. 10 predicted **2** rows here, because `membership_arms.py` reports
    #     only the `const path` shape while this guard also reads `preload`/`load`/quoted
    #     literals. The honest number was 10.
    #   * The two rows it did predict — the TRAP texture pair — carried the note *"the pair
    #     is PERMANENT under ADR-0142 rather than targeted at zero"*. That was wrong, and it
    #     was wrong for a reason worth keeping: **ADR-0142 makes the CONTENT un-shippable,
    #     which says nothing about the LITERAL.** This register scores the literal. A
    #     content root removes every literal without moving one byte of ROM-derived content,
    #     so "the dependency is permanent" and "the row is permanent" are different claims
    #     and only the first was true. The same confusion is still live on
    #     `audio_engine.gd`'s `#726` row above, which says the shape that pays it and then
    #     calls it REAL — it is real as a dependency and payable as a row.
}


# --- arm 7's burn-down (ADR-0223 dec. 6, arm 1's shape; owned by #809) -----
# `(addon file, class_name) -> (owner, why)`. Arm 1's rule verbatim and for arm 1's
# reason: a NAMED list, never a pattern (#424 — an exclusion expressed as a filter
# manufactures its own debt and cannot tell a triaged site from one that merely
# matches). BOTH directions fail.
#
# ARM 7 IS ARM 5's RULE ONE LEVEL OUT, exactly as arm 5 is arm 1's rule one level
# down. Arm 5 asks whether a `class_name` is declared by a SIBLING ADDON; it builds
# `homes` from the addon roots alone, so a `class_name` declared in `src/` is not in
# the map and no arm in this file has a word for it. That is the whole hole, and it
# is the reach that goal #5's ✅ was hiding: five lines in `exmateria_sprite_rig`
# name a host-declared type and every arm reported OK.
#
# WHY THE UNIVERSE IS `class_name` AND NOT EVERY REACH SHAPE. The boundary question
# — "does the target resolve outside every addon root" — has SIX shapes and five of
# them are already somebody's. Measured tree-wide 2026-09-02: eight rows leave every
# addon root, and only these five are unreported.
#
#   `autoload`       arm 2  (was `SpriteLayerManager.gd:121,811 Tune` — standalone-parse
#                            DEBT. PAID by #847, which routes both lines through
#                            `ExMateriaPlatform.TunePort`; re-measured over the five
#                            WALK_ROOTS on 2026-09-05, this shape now has NO row that
#                            leaves every addon root. The eight-row total above is as of
#                            its own date and spans the walk PLUS the extracted sound
#                            packages, which this re-reading did not re-scan.)
#   `/root/ reach`   arm 2b (the same name as a node-path STRING, #648)
#   `preload`        arm 6  (`audio_engine.gd:28 res://assets/music/WAVESET.WD`, ARM6_BURN_DOWN)
#   `const path`     arm 6
#   `#include`       arm 3
#   `class_name`     ARM 5 for a sibling addon -- and NOBODY for the host. <-- here
#
# Scoping the arm's UNIVERSE is not #424's filter: that is `_ARM6_REFERRERS`
# subtracting the four shader suffixes because arm 3 owns them, and this file already
# says why — *"scanning shaders here prints one defect twice under two headers."*
# The eighth row is not a row at all: `trace_writer.gd:82` carries `load("res://...")`
# inside a `#` comment, and `outbound_reaches` matches `preload`/`load` against the
# RAW line. Arm 6 strips comments and correctly does not see it.
ARM7_BURN_DOWN = {
    # EMPTY, and that is the arm's target rather than its default. It carried five
    # entries over six lines from 2026-09-02 to 2026-09-04 — four `JsonAsset` and
    # one `AnimationNames`, all inside `exmateria_sprite_rig`, all owned by #809.
    # Both are discharged and neither by the same move: `JsonAsset` went to the PORT
    # (`addons/exmateria_platform/json/`, published as `ExMateriaPlatform.JsonAsset`,
    # ADR-0223 dec. 8 / ADR-0217 dec. 16, `PsxNum` the precedent), while
    # `AnimationNames` moved INTO the rig AND handed its address to the host-injected
    # content root — moving the class alone would have carried
    # `assets/sprites/animation_names.json` under an addon root and landed on arm 6
    # (ADR-0202). A register that empties by a fix rather than by a deletion is the
    # only reading of 0 worth having (ADR-0220's arm-3 note says the same).
    # --- extraction #7 (#1225) held ONE row here for a day and #1219 paid it on
    # 2026-09-12, so this arm is back at its target. The row was
    # `addons/exmateria_effects/cast/EffectManager.gd -> Unit`: three
    # `caster: Unit` / `target: Unit` annotations on the spawn API, `Unit` declared in
    # `src/units/Unit.gd`. Shipping the addon ships `EffectManager.gd` and does not ship
    # the host that mints the name, so the addon did not parse in a stranger project.
    #
    # ADR-0288 dec. 3 ruled the fix `Node3D` because the functions only ever read
    # `.global_position` off the parameter (plus `.name`, a `Node` member, in one verbose
    # branch) — and ADR-0295 dec. 7 ruled it a LOAD-AND-ASSERT item rather than a static
    # edit, because a duck-typed reach is invisible to every scan in this file. The
    # witness is `tests/EffectManagerNode3DAnchorTest.gd`, which spawns through all three
    # entry points with bare `Node3D` anchors and reads the parented instance back. That
    # ordering matters: this arm going to 0 is the CONSEQUENCE, and re-reading the
    # annotation it just wrote is the one thing a static guard cannot use as evidence.
}

# Arm 7's universe. `outbound_reaches` returns six `kind`s and five of them are already
# reported by arms 2, 2b, 3 and 6; see ARM7_BURN_DOWN's note above for the measurement.
_ARM7_KINDS = {"class_name"}


# --- arm 8's exception list (#1241, arm 1's shape) -------------------------
# `(addon, declared dep) -> (owner, why)`. Arm 1's rule verbatim and for arm 1's
# reason: a NAMED list, never a pattern (#424 — an exclusion expressed as a filter
# manufactures its own debt and cannot tell a triaged row from one that merely
# matches). BOTH directions fail — an unlisted declared dep that arm 5 sees no
# reach to, AND a listed row whose dep IS reached after all.
#
# WHY EQUALITY IS THE WRONG RULE, WHICH IS WHY THIS LIST EXISTS AT ALL. Arm 5 sees
# `class_name` reaches and nothing else. A dependency can be real and invisible to
# it — a `res://` path into the sibling's tree, a `[shader_globals]` name the
# sibling's `plugin.gd` provides (ADR-0203 dec. 1), an autoload the sibling's
# `plugin.gd` registers, a `.tscn` that instances the sibling's scene. Every one of
# those has to be STAGED and none of them is a symbol. So the arm cannot read
# "declared but unreached" as a defect; it reads it as a claim that needs a name
# and an owner, and the OTHER direction — a measured reach nobody declared — is the
# unconditional one, because a reach arm 5 can see is a reach the rig must stage or
# the addon does not parse.
#
# 🔴 IT LANDS EMPTY, AND THAT IS THE ARGUMENT FOR BUILDING IT NOW RATHER THAN THE
# ABSENCE OF ONE. Screened over every `deps=` key in the corpus at `772ff743c`,
# declared == measured is 5/5 EXACT: `exmateria_almanac`, `exmateria_battlefield`,
# `exmateria_catalogue`, `exmateria_render` and `exmateria_sprite_rig`. A ratchet
# installed at an exactly-clean baseline carries no burn-down, and this one is only
# clean because #1240 had just paid the single row there was — a dependency
# `exmateria_catalogue` had declared and not reached since #1071, which survived 474
# commits precisely because nothing in `tools/` read the key (ADR-0272, #1239).
ARM8_DEPS_NOT_BY_CLASS_NAME = {
    # It landed EMPTY at #1241 and took its first row at #1286, which is the case the
    # header above describes in the abstract: a dependency that is REAL, must be
    # STAGED, and is invisible to arm 5 because it is a `res://` path rather than a
    # symbol. An empty list is not a quiet one either way —
    # `test_a_clean_dep_left_in_the_list_is_STALE_and_red` seeds a row naming a dep
    # that IS reached, so this list going empty again cannot make the stale arm
    # vacuous.
    ("addons/exmateria_effects", "exmateria_sound"): (
        "#1286",
        "FOUR `preload`s and ZERO `class_name`s, which is exactly the shape this list "
        "exists for. `cast/EffectInstance.gd` preloads three files out of "
        "`res://addons/exmateria_sound/runtime/` and `file_model/EffectData.gd` "
        "preloads `res://addons/exmateria_sound/exmateria_sound.gd` for "
        "`FedsBank.load_from_file` — the blueprint's Format-owner rule, `Effects` "
        "reads `Audio`'s `feds.bin` (ADR-0288 dec. 8 calls that row correct as "
        "written). It was the bare global `ExMateriaSound` until #1241's arm 8 ruled "
        "an undeclared sibling `class_name` unconditional; re-spelling it as a PATH "
        "is what moved it out of arm 5's sight and into this list's. "
        "NOT STALE AND NOT WAIVABLE: `tests/stranger/exmateria_effects/run.sh` stages "
        "the transitive closure of `deps=`, and deleting this dep takes those four "
        "preloads back to unresolvable — the state that was this rig's last two "
        "`known_failures.tsv` rows until #1286 declared the dep and drained them to "
        "ZERO. The direction test is the rig itself."),
}


# --- arm 8b's register (#1241, #1099; arm 1's shape) -----------------------
# `addon -> (subject engine, closure engine, owner, why)`. ONE ROW PER SUBJECT WHOSE
# RIG BOOTS A BINARY ITS OWN `engine=` DOES NOT NAME, and both directions fail — a
# new divergence nobody wrote down, AND a row whose divergence is gone.
#
# WHY A DIVERGENCE IS THE THING WORTH REGISTERING, and not the pair for all seven.
# A row here is not bookkeeping, it is ADR-0194 dec. 7's check going missing:
# `rig.sh`'s fork arm asserts the compositor primitives are ABSENT from stock, which
# turns a `fork` declaration into a checked fact — and it underwrites the CLOSURE's
# requirement, not the subject's. So for a subject that declares `stock` and runs on
# the fork, NOTHING checks the subject's own declaration, and the rig says so itself
# in the banner: *"Goal #5 is UNMET on the declaration axis for $ADDON (#1099)."*
# That is a standing debt with an owner, which is what a named list is for; a
# subject whose closure agrees with it has no debt and needs no row.
#
# AND IT IS THE COUPLING #1241 IS ABOUT, HELD IN BOTH DIRECTIONS. Every way the
# booted binary can move is a movement of this register:
#   * a stock subject GAINS a fork dep (directly or through the closure) -> a new
#     divergence, unlisted, RED.
#   * a stock subject LOSES its last fork dep -> the listed row goes stale, RED.
#     This is #1239's near-miss exactly: dropping `exmateria_sprite_rig` (`fork`)
#     from `exmateria_catalogue` would have flipped that rig to a stock binary, and
#     did not only because #1180 had already added `exmateria_schema` (also `fork`)
#     as a direct dep — unchanged by accident, not by design.
#   * a subject's OWN `engine=` is edited to disagree with its closure -> a new
#     divergence, unlisted, RED.
# A fork subject whose closure is all stock is not a movement: the rig boots the
# fork on the subject's own declaration, and dec. 7's absence arm checks it.
ARM8_CLOSURE_ENGINE = {
    "addons/exmateria_almanac": (
        "stock", "fork", "#1099",
        "REAL, and it is the SECOND addon to acquire it — the first to acquire it by a "
        "MOVE rather than by being born that way. #1159 made `UnitRole` ADR-0118 dec. 1's "
        "eleventh schema row (ADR-0280 dec. 3), so `deps=` gained `exmateria_schema`, "
        "which declares `fork`; the rig has booted the fork since. The declaration is NOT "
        "promoted, for ADR-0194 dec. 7's reason: it is a measured claim about the files in "
        "THIS addon, and no file here names a compositor primitive (the package ships 37 "
        "`.gd` files and zero shaders). `plugin.cfg`'s own `engine=` block carries the "
        "measurement. The cost is that the install pass no longer falsifies a wrong "
        "`stock` here, which is a cost of ADR-0280 dec. 3 rather than a defect in it."),
    "addons/exmateria_catalogue": (
        "stock", "fork", "#1099",
        "REAL, and the FIRST — `tests/stranger/README.md` records the mechanism against "
        "this addon. Its closure reaches `exmateria_schema` (`fork`); booting stock "
        "reported five unexplained throws from `exmateria_schema/compositing_key/`, which "
        "are the dependency's declared fork requirement arriving as if they were the "
        "subject's defect. Promoting this addon's own declaration to `fork` would be the "
        "other error: it would make the `plugin.cfg` say the catalogue needs a primitive "
        "it does not name."),
}

def package_project(addon: pathlib.Path):
    """The `project.godot` that SHIPS WITH this addon, or None if it is the host's.

    Walking up from the addon root: `exmateria-sound/addons/exmateria_sound` finds
    `exmateria-sound/project.godot` (its own), `addons/exmateria_render` finds
    `godot-learning/project.godot` (the host's, i.e. not its own). Only the first
    kind can be parsed standalone, so only the first kind is enforceable.
    """
    for d in addon.resolve().parents:
        q = d / "project.godot"
        if q.is_file():
            return None if d == PROJECT_DIR else q
    return None


def autoload_names(project_godot: pathlib.Path) -> dict:
    """`{name: res-path}` from a project.godot `[autoload]` block.

    The docstring said `[autoload]` block and the loop read the whole FILE, which
    is a different subject. `project.godot` is an ini file, so `^(\w+)="res://…"`
    matches a key in any section, and extraction #4 landed one:
    `[exmateria_sprite_rig] content_root="res://assets/"` (ADR-0202's
    host-injected content root; `[exmateria_battlefield]` has carried the same
    key since extraction #3). Unscoped, arm 2 built a `content_root\s*\.`
    pattern and would have reported any addon writing `content_root.foo` as
    reaching a HOST AUTOLOAD THAT DOES NOT EXIST — a break arm 2 cannot be
    talked out of, against a name Godot never creates. Nothing in the tree
    writes it today, so this was found by reading rather than by a red.
    """
    body = project_godot.read_text(errors="ignore")
    block = body.split("[autoload]", 1)[1].split("\n[", 1)[0] if "[autoload]" in body else ""
    out = {}
    for line in block.splitlines():
        m = re.match(r'^(\w+)="\*?res://(.+)"', line.strip())
        if m:
            out[m.group(1)] = m.group(2)
    return out


def autoload_reaches(addon: pathlib.Path, names: dict):
    """(rel, name, [lines]) for every bare `Name.` an autoload block alone declares.

    `Name.` and not a bare `Name`: an autoload is reached through its members, and
    requiring the dot is what keeps a slug string or a prose word out of the count.
    Comments, docstrings and string literals are blanked first (`strip_noncode`) —
    this repo documents heavily and `## Accessed globally as: ExMateriaAudioEngine` is not a
    reach. `(?<![.\\w])` drops `ExMateriaAudioEngine` in `foo.ExMateriaAudioEngine.bar`.

    The regex is GATED BEHIND A PLAIN SUBSTRING TEST, which is `score_goals.py`'s own
    fix for its own (line x name) loop applied to this one. The gate is a NECESSARY
    CONDITION of the regex it guards, not an approximation of it -- the pattern cannot
    match a line that does not contain the name as a substring -- so the regex still
    decides every row and the gate only decides whether to ask. Ungated, this loop was
    1.89 MILLION `re.search` calls on a whole-tree walk, the guard's largest single cost.
    """
    pats = {n: re.compile(r'(?<![.\w])' + re.escape(n) + r'\s*\.') for n in names}
    out = collections.defaultdict(list)
    for q in sorted(addon.rglob("*")):
        if not (q.is_file() and q.suffix == ".gd"):
            continue
        rel = _sg._rel(q)
        for i, ln in enumerate(_sg.strip_noncode(q.read_text(errors="ignore")), 1):
            for n, pat in pats.items():
                if n in ln and pat.search(ln):
                    out[(rel, n)].append(i)
    return [(rel, n, lines) for (rel, n), lines in sorted(out.items())]



# `get_node`, `get_node_or_null`, `has_node`, `find_child` with a literal name, with
# or without the `/root/` prefix and in either string flavour (`"x"`, `^"x"`, `&"x"`).
# All four verbs and all three spellings, because ADR-0191 recorded that the file
# which motivated this arm used the LONGEST of them —
# `Engine.get_main_loop().root.get_node_or_null("CompositorAutopilot")` — and a rule
# reading only `get_node_or_null("…")` reports zero on its own motivating case.
_NODE_ROUTE_RE = re.compile(
    r'\b(?:get_node|get_node_or_null|has_node|find_child)\s*\(\s*[&^]?"(?:/root/)?([A-Za-z0-9_]+)"')


def autoload_route_reaches(addon: pathlib.Path, names: dict):
    """(rel, name, target, [lines]) for a HOST autoload named as a node-path STRING.

    ARM 2's SUBJECT IN A THIRD SPELLING, AND ARM 2 CANNOT SEE IT. Arm 2 matches a bare
    `Name.` and says so in its own docstring; here the autoload is named as a STRING and
    the call is duck-typed on an untyped `Node`, so the file never writes the identifier
    and arm 2 reports clean. `addons/exmateria_battlefield/cursor/TileCursor.gd` did
    exactly this against the `src/effects/` `CompositorAutopilot` autoload and this guard
    was green over it the whole time — ADR-0191 records it under *"an addon reaches a host
    autoload, and the guard is blind to it"*, and closes with the follow-up this is (#648).

    IT IS A SEPARATE ARM BECAUSE ITS FREE SET IS DIFFERENT, WHICH IS 4b's PRECEDENT. Arm 2
    runs for every subject, the kernel included. This one cannot: reaching a singleton by
    node path is what the platform PORT is MADE of. ADR-0175 dec. 2 re-points 61
    host-autoload reaches into exactly this spelling on purpose, so that an `[autoload]`
    line only the consuming game can write becomes an addon-presence dependency instead —
    `TunePort.gd:77` naming `Tune` is that design working. So `main()` scores this arm on
    arm 5's free set: the kernel and the port are exempt, a SYSTEM is not.

    THE SECOND EXEMPTION IS HERE, AND IT IS A NAME TEST ON PURPOSE. An addon reaching its
    OWN singleton ships the script the autoload points at — `exmateria_sound` naming
    `ExMateriaAudioEngine`, `exmateria_platform` naming `PSXDisplay`, three of the four
    routes on the real tree — and `plugin.gd` can register it (ADR-0203 dec. 1). The
    defect is naming a script the addon does NOT ship. That is decided on the res:// path
    the `[autoload]` line carries and NOT by resolving it on disk, because
    `addons/exmateria_sound` is a per-worktree SYMLINK into the sound package: resolve it
    in a worktree that has not been linked and the addon's own singleton reads foreign.

    NOT "match the 26 names anywhere". `"Campaign"` and `"Focus"` are ordinary words, and
    a bare literal in any string would score prose and slugs. The verb is the discriminator:
    a name handed to one of the four lookup verbs is being resolved as a node.
    """
    own = "addons/%s/" % addon.name
    foreign = {n: t for n, t in names.items() if not t.startswith(own)}
    out = collections.defaultdict(list)
    for q in sorted(addon.rglob("*")):
        if not (q.is_file() and q.suffix == ".gd"):
            continue
        rel = _sg._rel(q)
        # `strip_gdscript_comments`, which is arm 4's stripper and the INVERSE of arm 2's:
        # the name this arm hunts is DELIVERED as a string literal, and `strip_noncode`
        # blanks string literals. Built on arm 2's stripper this arm reads `get_node("")`
        # and reports nothing — the same green-that-blanked-its-own-evidence arm 4 shipped.
        for i, ln in enumerate(strip_gdscript_comments(q.read_text(errors="ignore")), 1):
            for m in _NODE_ROUTE_RE.finditer(ln):
                if m.group(1) in foreign:
                    out[(rel, m.group(1))].append(i)
    return [(rel, n, foreign[n], lines) for (rel, n), lines in sorted(out.items())]


# ADR-0144 dec.: *"source means four extensions"* — `.gdshader`, `.gdshaderinc`,
# `.glsl`, `.glslinc`. `_sg.SHADER_SUFFIXES` IS that list and is imported rather
# than re-spelled here, because spelling three of them is not a smaller version of
# the rule, it is a FALSE ZERO. `pixel_aspect`'s only declaration lives in
# `assets/shaders/pixel_aspect.gdshaderinc`, so a census over `.gdshader`/`.glsl`/
# `.glslinc` reports "pixel_aspect: 0 readers" and both arms below certify an addon
# whose seam is the exact thing they exist to find.
_INCLUDE_RE = re.compile(r'#include\s+"([^"]+)"')
_GLOBAL_UNIFORM_RE = re.compile(r'\bglobal\s+uniform\s+\w+\s+(\w+)')
_PUSH_RE = re.compile(r'global_shader_parameter_(?:set|get)\s*\(\s*&?"(\w+)"')
# An addon root is `res://addons/<name>/` in every project this guard scans — the
# host's and the sound package's alike, which is why one pattern serves both.
_ADDON_RES_RE = re.compile(r'^addons/[^/]+/')


def strip_shader_comments(text: str):
    """Shader source with `//` and `/* */` blanked, LINE COUNT PRESERVED.

    Deliberately NOT `strip_noncode`: that one is GDScript's and blanks `#`, which
    in GDShader is the first character of `#include`. Running the GDScript stripper
    over a shader deletes the very lines arm 3 reads, and reports zero.

    Quoted spans are copied whole rather than scanned — see the inline note; `res://`
    contains `//`, and missing that is not a partial arm but a silent zero.

    Neither arm is optional about this and the tree already holds all three traps:
    `effect_fold_add.gdshader` carries the words *"global uniform"* inside a `//`
    comment explaining that `psx_brightness` is OFF the fold contract, and
    `ot_depth.gdshaderinc:11` and `color_stack.gdshaderinc:16` each spell a
    `#include` inside a `//` block as usage documentation. A raw grep reports three
    findings here and all three are prose. This house has shipped that defect
    before — a guard that stayed green after its guarded line was deleted, because
    the rule's own comment still held the string.
    """
    out, i, n, block = [], 0, len(text), False
    while i < n:
        # A QUOTED SPAN IS COPIED WHOLE, and skipping this deletes arm 3 entirely:
        # `res://` CONTAINS `//`. Seen as a line comment, `#include "res://a.gdshaderinc"`
        # is blanked from the `//` onward, every include in the tree resolves to nothing,
        # and the arm reports a clean zero. `#include` is the only construct in GDShader
        # that takes a string, so one rule covers it.
        if not block and text[i] == '"':
            j = text.find('"', i + 1)
            j = n if j < 0 else j + 1
            out.append(text[i:j])
            i = j
            continue
        if block:
            if text.startswith("*/", i):
                block, i = False, i + 2
                out.append("  ")
                continue
            out.append("\n" if text[i] == "\n" else " ")
            i += 1
        elif text.startswith("/*", i):
            block, i = True, i + 2
            out.append("  ")
        elif text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        else:
            out.append(text[i])
            i += 1
    return "".join(out).splitlines()


def strip_gdscript_comments(text: str):
    """GDScript with `#` comments and triple-quoted blocks blanked, STRING LITERALS KEPT.

    THE INVERSE OF ARM 2'S STRIPPER, AND REUSING ARM 2'S REPORTS ZERO. `strip_noncode`
    blanks string literals — *"a word-match over raw text overcounts wildly"* — and it is
    right to, because arm 2 hunts a bare identifier and `## Accessed globally as:
    ExMateriaAudioEngine` is not a reach. Arm 4's CPU side hunts the opposite thing: the global's
    name is DELIVERED as a string literal, `global_shader_parameter_set(&"psx_gamma", v)`,
    so the one token arm 4 needs is the one token arm 2 must destroy. Built on
    `strip_noncode` this arm ran clean over `PSXDisplay.gd`'s five pushes and printed
    nothing — a green that had already blanked its own evidence.

    Comments still have to go, and that trap is live in the same file: `PSXDisplay.gd:54–55`
    discusses `global_shader_parameter_get` and `global_shader_parameter_set` in a `##` doc
    comment thirty lines above the first real call.

    Scanned rather than regexed because the two rules interact — a `#` inside a string
    literal starts no comment, and a quote inside a comment opens no string.

    THE SCAN IS CHUNKED AND THE RESULT IS MEMOISED, and both are cost, not meaning.
    Three arms strip the same file — 2b's route, 6's path, 4's push — so a whole-tree
    run stripped 310 texts 906 times, exactly 3x each; `_strip_gdscript_cached` keys on
    the TEXT, so the memo cannot go stale the way a path-keyed one could. Inside it,
    ordinary source is copied a RUN at a time (`_NEXT_GD` finds the next quote or `#`)
    instead of one character per loop, and a docstring body is blanked a slice at a
    time. Proven character-identical to the char-by-char original over 3,869 real files
    (38.9 MB of `.gd`/`.tscn`/`.gdshader`/`.py`/`.md`) plus 22 hand-written edge cases —
    unterminated literals, `\\` escapes, unclosed docstrings, `#` inside a string, a
    quote inside a comment, CRLF and non-ASCII — with a deliberately-broken stripper
    as the control that says the comparison can see a difference.
    """
    return list(_strip_gdscript_cached(text))


_NEXT_GD = re.compile(r"[\"'#]")


def _blank_keeping_newlines(chunk: str) -> str:
    """`chunk` with every character but `\n` replaced by a space — the docstring rule."""
    return "\n".join(" " * len(part) for part in chunk.split("\n"))


@functools.lru_cache(maxsize=None)
def _strip_gdscript_cached(text: str) -> tuple:
    out, i, n, doc = [], 0, len(text), None
    while i < n:
        if doc is not None:
            j = text.find(doc, i)
            if j < 0:
                out.append(_blank_keeping_newlines(text[i:]))
                break
            out.append(_blank_keeping_newlines(text[i:j]))
            out.append("   ")
            i, doc = j + 3, None
            continue
        m = _NEXT_GD.search(text, i)
        if m is None:
            out.append(text[i:])
            break
        if m.start() > i:
            out.append(text[i:m.start()])
            i = m.start()
        c = text[i]
        if c == "#":
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif text.startswith(c * 3, i):
            doc = c * 3
            out.append("   ")
            i += 3
        else:
            out.append(c)
            i += 1
            while i < n and text[i] != c and text[i] != "\n":
                step = 2 if (text[i] == "\\" and i + 1 < n) else 1
                out.append(text[i:i + step])
                i += step
            if i < n and text[i] == c:
                out.append(c)
                i += 1
    return tuple("".join(out).splitlines())


def shader_global_names(project_godot) -> set:
    """The `[shader_globals]` names a `project.godot` DECLARES, or empty for None.

    Empty is the right answer for an in-walk addon: it has no project of its own,
    so every name it binds is by definition the host's.
    """
    if project_godot is None:
        return set()
    names, inside = set(), False
    for line in project_godot.read_text(errors="ignore").splitlines():
        s = line.strip()
        if s.startswith("["):
            inside = s == "[shader_globals]"
        elif inside:
            m = re.match(r"^(\w+)\s*=", s)
            if m:
                names.add(m.group(1))
    return names


def include_reaches(addon: pathlib.Path, res_root: pathlib.Path):
    """(rel, line, target, why) for each `#include` under `addon` that is not portable.

    Two ways to fail, and the second is ADR-0146 dec. 8's rule — a seam guard
    checks the file EXISTS rather than just matching a basename, because a
    `#include` naming a path that is not there is a compile error the guard would
    otherwise certify as green.

    RELATIVE INCLUDES ARE RESOLVED, NOT SKIPPED. ADR-0169 dec. 5 writes the arm as
    `#include "res://…"`, and matching only that literal prefix leaves
    `#include "../../assets/shaders/x.gdshaderinc"` — the same escape, spelled the
    other legal way — invisible. Resolving against the including file's directory
    costs one line and closes it. A relative path that climbs out of the project
    entirely cannot be expressed as a res:// path at all, and that is reported as
    the escape it is rather than dropped.
    """
    out = []
    for q in sorted(addon.rglob("*")):
        if not (q.is_file() and q.suffix in _sg.SHADER_SUFFIXES):
            continue
        rel = _sg._rel(q)
        for i, ln in enumerate(strip_shader_comments(q.read_text(errors="ignore")), 1):
            for m in _INCLUDE_RE.finditer(ln):
                raw = m.group(1)
                if raw.startswith("res://"):
                    target, abs_q = raw[len("res://"):], res_root / raw[len("res://"):]
                else:
                    abs_q = q.parent / raw
                    try:
                        target = abs_q.resolve().relative_to(res_root.resolve()).as_posix()
                    except ValueError:
                        out.append((rel, i, raw, "climbs outside the project entirely"))
                        continue
                if not _ADDON_RES_RE.match(target):
                    out.append((rel, i, target, "lies outside every addon root"))
                elif not abs_q.is_file():
                    out.append((rel, i, target, "names a file that does not exist"))
    return out


# Referrer files whose `res://` literals arm 6 reads. `check_res_paths.REFERRER_SUFFIXES`
# MINUS the four shader suffixes, and the subtraction is the point: a
# `#include "res://assets/…"` is ARM 3's exact subject, arm 3 resolves it against the
# shipping project and checks the file exists, and scanning shaders here prints one
# defect twice under two headers.
_ARM6_REFERRERS = {".gd", ".tscn", ".tres", ".cfg"}

# Borrowed in SHAPE from `check_res_paths.LITERAL` — the quote pair, and the optional
# `*` that `project.godot`'s `Autoload="*res://…"` puts between the quote and the scheme
# — and DELIBERATELY WIDER in target. That pattern ends in a source-suffix alternation
# because its question is *"does every source path still resolve"*. This arm's question
# is *"can the addon be installed somewhere else"*, and a `.tga`, a `.json` and a bare
# `res://assets/maps/` directory are exactly as unshippable as a `.gd`: of the eleven
# rows #658 measured, four were `.tga`/`.json` and two were bare directories, so the
# narrow pattern drops six of eleven.
_RES_LITERAL_RE = re.compile(r"""(["'])\*?(res://[^"']*)\1""")


def res_path_reaches(addon: pathlib.Path):
    """(rel, line, target) for a quoted `res://` literal whose target leaves every addon.

    GOAL #5's SENTENCE WAS TRUE ONLY OF TYPE-SHAPED REACHES (#658). A path-shaped one had
    never been in the universe: arm 1 reads symbols the classifier books to a system, arm
    2 reads autoload identifiers, arms 3 and 4 read GDShader. So one line in the kernel —
    `const _SEED = preload("res://src/data/JobDatabase.gd")` — is a hard compile-time
    dependency on a host file and all four arms report OK.

    TWO THINGS ARE OPEN AND THE TICKET'S TABLE NAMES NEITHER, which measuring said rather
    than reasoning. `score_goals.outbound_reaches` has grown `preload` and `const path`
    shapes since #658 was filed, so a `preload` of a Battle-booked file from
    `exmateria_battlefield` IS red today. What is not:

      1. ARM 1 DOES NOT RUN ON THE KERNEL OR THE PORT. `main()` reads
         `if system is None: continue`, correctly — they are not systems — so the two
         addons every other addon depends on may `preload` any host file with no report.
         #658's seed is a kernel file, and that is why it survives.
      2. THE ELEVEN SYSTEMS ARE NOT THE WHOLE HOST. `src/data/JobDatabase.gd` classifies
         `content`, not `Battle`, so even from a SYSTEM addon that exact seed is
         invisible. An addon that cannot find `res://assets/…` is no more installable
         than one that cannot find `src/`.

    So this arm sits BEFORE arm 1's `continue` and asks arm 3's question instead of arm
    1's: the target resolves under an addon root or it does not. No classifier verdict, no
    standalone project — hence ENFORCING, with a NAMED burn-down for what is measured and
    accepted, never a pattern (#424, ADR-0184 dec. 4).

    NOT AN EXISTENCE CHECK. Whether a quoted `res://` literal still resolves is
    `check_res_paths.py`'s whole contract, tree-wide; asking it again here would be two
    instruments answering one question. This one asks only about the ADDRESS.

    THE STRIPPERS ARE THE ARM. All eleven rows #658 lists for `exmateria_battlefield` are
    GONE — ADR-0202/ADR-0204 moved that addon onto a host-injected content root — and
    every surviving `res://assets/` mention in it is a `##` note, a `#` note or a `;` line
    in a `.tres` recording that it moved. An arm without a stripper reports 21 false rows
    on the addon that already paid, and reports them against its own documentation.
    """
    out = []
    for q in sorted(addon.rglob("*")):
        if not (q.is_file() and q.suffix in _ARM6_REFERRERS):
            continue
        rel = _sg._rel(q)
        txt = q.read_text(errors="ignore")
        if q.suffix == ".gd":
            # `strip_gdscript_comments` and NOT `strip_noncode`: the path this arm hunts
            # IS a string literal, and arm 2's stripper blanks string literals. Arm 4's
            # CPU side shipped that defect once already.
            lines = strip_gdscript_comments(txt)
        else:
            # `.tscn`/`.tres`/`.cfg` are INI-shaped: `;` opens a comment and only at the
            # start of a line. `PlayerCamera.tscn` and `tile_cursor_opaque.tres` both
            # carry `;` prose naming `res://assets/…` paths they no longer hold.
            lines = [("" if ln.lstrip().startswith(";") else ln)
                     for ln in txt.splitlines()]
        for i, ln in enumerate(lines, 1):
            for m in _RES_LITERAL_RE.finditer(ln):
                target = m.group(2)
                if not _ADDON_RES_RE.match(target[len("res://"):]):
                    out.append((rel, i, target))
    return out


def shader_global_reaches(addon: pathlib.Path, own: set):
    """(rel, name, side, [lines]) for every shader global an addon binds but does not own.

    BOTH SIDES. The GPU side is the `global uniform` declaration ADR-0169 dec. 5
    specified; the CPU side is `RenderingServer.global_shader_parameter_set/get`,
    which ADR-0171 dec. 5 added because the port that pushes the names declares
    none of them and a declaration-only scan reads it as clean.

    Comments are blanked on both sides with the stripper each language needs, and
    NEITHER of them is arm 2's. `strip_shader_comments` for shader source; for
    GDScript, `strip_gdscript_comments`, which KEEPS string literals precisely
    because the pushed name is one — see its docstring for the false green that
    distinction bought back.
    """
    out = collections.defaultdict(list)
    for q in sorted(addon.rglob("*")):
        if not q.is_file():
            continue
        if q.suffix in _sg.SHADER_SUFFIXES:
            lines, pat, side = strip_shader_comments(q.read_text(errors="ignore")), _GLOBAL_UNIFORM_RE, "declares"
        elif q.suffix == ".gd":
            lines, pat, side = strip_gdscript_comments(q.read_text(errors="ignore")), _PUSH_RE, "pushes"
        else:
            continue
        rel = _sg._rel(q)
        for i, ln in enumerate(lines, 1):
            for m in pat.finditer(ln):
                if m.group(1) not in own:
                    out[(rel, m.group(1), side)].append(i)
    return [(rel, name, side, lines) for (rel, name, side), lines in sorted(out.items())]


def own_global_uniform_declarations(addon: pathlib.Path):
    """(rel, name, [lines]) for every `global uniform` DECLARED under `addon`.

    Arm 4 asks whether a name the addon binds is one the HOST declares, and can
    only report it as debt in-walk because there is no standalone project to fail
    against. (Arm 2 no longer has that branch — #1225 flipped it to `ARM2_BURN_DOWN`
    once the corpus count hit 0, for the reason ADR-0238 gave. Arm 4 keeps it because
    ADR-0238's reason is DIFFERENT and still stands: a missing `global uniform` is not
    a compile error outside the editor, so no rig can fail against it.) This asks a different question that needs no such project: **which
    addon is the declaration IN.** That is a fact about this tree, so it enforces.
    """
    out = collections.defaultdict(list)
    for q in sorted(addon.rglob("*")):
        if not (q.is_file() and q.suffix in _sg.SHADER_SUFFIXES):
            continue
        rel = _sg._rel(q)
        for i, ln in enumerate(strip_shader_comments(q.read_text(errors="ignore")), 1):
            for m in _GLOBAL_UNIFORM_RE.finditer(ln):
                out[(rel, m.group(1))].append(i)
    return [(rel, name, lines) for (rel, name), lines in sorted(out.items())]


def class_name_homes(roots) -> dict:
    """`{class_name: addon_root}` for every `class_name` declared under an addon root.

    A `class_name` is a global name the PROJECT's script-class cache creates by
    scanning the project (`.godot/global_script_class_cache.cfg`). So a file naming
    one parses only where the DECLARING addon is also installed — arm 2's sentence
    with `class_name` in place of autoload. Measured, not argued: an addon naming a
    sibling's `class_name` parses clean with the sibling present and reports
    `Parse Error: Identifier "X" not declared in the current scope` without it,
    both arms run with the class cache warmed (ADR-0175).
    """
    out = {}
    for r in roots:
        for q in sorted(r.rglob("*.gd")):
            m = re.search(r"^class_name\s+([A-Za-z0-9_]+)", q.read_text(errors="ignore"), re.M)
            if m:
                out[m.group(1)] = r
    return out


# A façade's published surface, and the only shape ADR-0212 uses:
# `const <Member> = preload("res://addons/…")` at the top level of the file that
# declares the `class_name`. Deliberately NOT scoped to files named `*_facade` or
# to a hand-kept list of the six — a `const` bound to a `preload` IS the published
# member wherever it sits, so the rule reads a façade and an ordinary class alike
# and nothing has to be taught which is which.
_PUBLISHED_MEMBER_RE = re.compile(r'^const\s+([A-Za-z0-9_]+)\s*:?=\s*preload\(', re.M)

# `const <Local> = <Facade>.<Member>` — the alias line ADR-0211 dec. 4 exists for,
# whose whole purpose is that the use sites below it did NOT move. Anchored and
# whole-line: an alias is a top-level declaration, and matching it mid-expression
# would book `var x = a if F.M else b` as a binding.
_FACADE_ALIAS_RE = re.compile(
    r'^\s*const\s+([A-Za-z0-9_]+)\s*:?=\s*([A-Za-z0-9_]+)\s*\.\s*([A-Za-z0-9_]+)\s*$')


def published_members(roots) -> dict:
    """`{class_name: {member}}` for every `const X = preload(...)` on a declaring file.

    THE FAÇADE MADE THIS REPORT COARSER, WHICH IS #722 AND IS THE OPPOSITE OF WHAT
    ADR-0211 dec. 4 PREDICTED. Dec. 4's *"aliasing makes coupling MORE visible, not
    less"* is true for the HOST, where a coupling was previously a bare type naming
    nothing. It is false for THIS guard, which already resolved a bare type to its
    declaring addon: after ADR-0212, `Fold`, `DepthMode`, `TerrainCell`, `ColorStack`,
    `ColorRecipe` and `CellMarking` are file-local aliases arm 5 cannot see, every
    consumer collapses to one row naming `ExMateriaSchema`, and per-NAME resolution
    becomes per-FOLDER resolution — 21 rows naming a symbol became 20 naming a folder.

    Reading the alias does not merely restore the old row, it lands STRICTLY BETTER.
    The pre-façade `Fold` was the LOCAL spelling; `ExMateriaSchema.Fold` is what the
    addon PUBLISHES, and `exmateria_schema.gd`'s own docstring is the authority on
    which — *"this list IS the supported surface"*, held in both directions by
    `tools/check_addon_globals.py`.
    """
    out = {}
    for r in roots:
        for q in sorted(r.rglob("*.gd")):
            txt = q.read_text(errors="ignore")
            m = re.search(r"^class_name\s+([A-Za-z0-9_]+)", txt, re.M)
            if not m:
                continue
            names = set(_PUBLISHED_MEMBER_RE.findall(txt))
            if names:
                out[m.group(1)] = names
    return out


def sibling_class_reaches(addon: pathlib.Path, homes: dict, members: dict = None):
    """(rel, name, home, [lines]) for every `class_name` a DIFFERENT addon root declares.

    The declaring file is never its own reach: its home IS this root, so it is
    filtered before the scan. Comments and string literals are blanked first, for
    arm 2's reason — this repo documents heavily and `## returns a Fold` is prose.

    `name` RESOLVES THROUGH A FAÇADE (#722). Where the line names a member the façade
    publishes, the row is `ExMateriaSchema.Fold` rather than `ExMateriaSchema`; where a
    file aliases one back to a bare local name, every later use of that local name is
    scored on the resolved symbol too, so the row carries the alias line AND the use
    sites the alias exists to keep spelled the way they were.

    TWO THINGS IT REFUSES TO GUESS, both of them the control half of the rule. A member
    the façade does not publish resolves to the FAÇADE and not to itself — reporting
    `ExMateriaSchema.Internal` would assert a surface the provider does not have. And a
    file-local alias BEATS a sibling's `class_name` of the same spelling, because
    GDScript resolves the local `const` first and because after ADR-0212 the two
    spellings collide by construction: the alias is named after the member precisely so
    the use sites did not move.
    """
    # The default is not a second, unshipped code path: it is the SAME derivation
    # `main()` performs, hoisted there only so the whole walk pays for it once. Nine
    # helper tests call the two-argument form and would otherwise each restate it.
    members = published_members(set(homes.values())) if members is None else members
    foreign = {n: h for n, h in homes.items() if h != addon}
    if not foreign:
        return []
    direct = {n: re.compile(r'(?<![.\w])' + re.escape(n) + r'\b') for n in foreign}
    dotted = {n: re.compile(r'(?<![.\w])' + re.escape(n) + r'\s*\.\s*([A-Za-z0-9_]+)')
              for n in foreign}
    out = collections.defaultdict(set)
    for q in sorted(addon.rglob("*")):
        if not (q.is_file() and q.suffix == ".gd"):
            continue
        rel = _sg._rel(q)
        lines = _sg.strip_noncode(q.read_text(errors="ignore"))

        # Pass A binds the file's aliases before pass B scores a line, because an alias
        # licenses BARE uses ABOVE its own declaration as readily as below it — a
        # `const` is a class member, not a statement, and GDScript resolves the whole
        # class body. A single-pass scan would score every use site written above the
        # alias against the sibling `class_name` it shadows.
        alias = {}
        for ln in lines:
            m = _FACADE_ALIAS_RE.match(ln)
            if m and m.group(2) in foreign and m.group(3) in members.get(m.group(2), ()):
                alias[m.group(1)] = (m.group(2), "%s.%s" % (m.group(2), m.group(3)))
        alias_pats = {a: re.compile(r'(?<![.\w])' + re.escape(a) + r'\b') for a in alias}

        for i, ln in enumerate(lines, 1):
            for n, pat in direct.items():
                # The alias shadows the global. `n in alias` is that rule, and it is
                # what keeps one dependency from being booked as two.
                # `n in ln` is the same necessary-condition gate `autoload_reaches`
                # carries -- the pattern cannot match a line without `n` in it.
                if n in alias or n not in ln or not pat.search(ln):
                    continue
                hit = [m for m in dotted[n].findall(ln) if m in members.get(n, ())]
                for m in (hit or [None]):
                    out[(rel, n if m is None else "%s.%s" % (n, m), n)].add(i)
            for a, pat in alias_pats.items():
                if a in ln and pat.search(ln):
                    out[(rel, alias[a][1], alias[a][0])].add(i)
    return [(rel, name, homes[base], sorted(lines))
            for (rel, name, base), lines in sorted(out.items())]


def _install_register_provides() -> dict:
    """`{setting key: providing plugin.gd}` — ADR-0203 dec. 3, via the install register.

    ONE IMPLEMENTATION, deliberately. `check_addon_install`'s parser is the thing that
    decides this question for the register's arms 2 and 3, and a second copy here would be
    two instruments answering one question — which is the disagreement ADR-0202's
    Consequences already name between these two files, not something to add more of.

    \U0001f534 IT IS `provided_anywhere`, NOT `provided_by_walk`, AND THAT IS THE WHOLE
    DISTINCTION. Once `check_addon_install` took more than one subject, "is this name
    provided" stopped having a single answer: `provided_by_walk(roots)` answers it for one
    install target, and `pixel_aspect` is provided for `exmateria_battlefield` and unprovided
    for `exmateria_sprite_rig` off the same declaration. THIS arm is tree-wide and
    reporting, so the tree-wide union is the one it wants — but it has to ask for it by
    name, because the `except` below would have turned the signature change into a silent
    empty dict and reverted every row to its pre-ADR-0203 wording with nothing going red.

    Imported inside the function and tolerant of failure because this arm is REPORTING: if
    the register is unavailable, every row falls back to the pre-ADR-0203 wording rather
    than taking a portability check down with it."""
    try:
        sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
        from check_addon_install import provided_anywhere
        return provided_anywhere()
    except Exception:
        return {}


def full_roots() -> tuple[list[pathlib.Path], dict]:
    """(roots, gone) for the full walk — every addon this repo claims is portable.

    The walk's own output PLUS the packages that have already LEFT the walk. An
    extraction removes its addon from WALK_ROOTS (#326), so scanning only the
    walk means a guard stops covering a system exactly when that system becomes
    shippable — which is why this guard's rule is a rule and not a convention
    after a system ships as its own package (ADR-0151, corrected).
    """
    roots = list(_sg._walk_roots.addon_roots())
    gone: dict = {}
    for row in _sg._walk_roots.extracted_roots():
        roots.append(row.path)
        gone[row.path] = row.system
    return roots, gone


def walk_addons(roots, named=None, gone=None) -> dict:
    """Every arm's scan over `roots`, with NO burn-down applied.

    The split is not a style choice: the walk's output is a fact about the tree,
    and the burn-downs are claims about the walk. `main()` used to apply the
    three lists inline in its one loop, so a test that wanted to re-score one
    walk against a different list had to walk again — which is how
    `test_check_addon_portability` ended up re-running the ~19.5 s whole-tree
    walk thirteen times on a tree that does not change between its arms
    (docs/PREFLIGHT-TIMING.tsv, 2026-09-07). `report_walk` takes this result
    and the lists, and the two stay separable.
    """
    os.chdir(PROJECT_DIR)
    host_auto = autoload_names(PROJECT_DIR / "project.godot")
    gone = gone or {}

    arm1_raw, scanned, parse_raw = [], [], []
    inc_bad, glob_bad, glob_debt, decl_bad = [], [], [], []
    decl_unprovided = []
    route_bad = []
    path_raw = []
    type_raw = []
    sib_free, sib_debt, sib_bad = [], [], []

    # Arm 5 asks about the root a name is declared IN, not the root it is used in,
    # so every root's verdict has to exist before the first reach is scored.
    #
    # 🔴 TWO MAPS, BECAUSE THEY ARE TWO QUESTIONS (#1059). `system_of[a] is None`
    # used to answer BOTH of them and they diverge: "which of the eleven is this
    # package" is a question about its FILES, and "may everything name it for
    # free" is a question about its TIER. The proxy held while the only non-system
    # addons were the kernel and the port — the two free tiers — and
    # `exmateria_almanac` is where it broke, because the tier value came from a
    # majority vote over `classify()` buckets and `classify()` books a file to the
    # system that CONSUMES it (ADR-0243 dec. 3). A package of tables therefore
    # inherits the names of its readers, and the guard reported the almanac as the
    # Battle system's addon while seven of the eleven reach it.
    #
    # `_walk_roots.declared_tier` reads the answer out of the package's own
    # `plugin.cfg`, beside `engine=` and `deps=`, and RAISES where none is
    # declared. The vote survives for the system NAME alone, which is a fact about
    # files and is what it was always able to see.
    def _tier_of(addon):
        # `--root X --system Y` is the operator DECLARING the tier by hand for a
        # package the walk has never seen; that is what naming one of the eleven
        # means, and it is the only path that reaches a root with no plugin.cfg.
        return "system" if named else _sg._walk_roots.declared_tier(addon)

    tier_of = {a: _tier_of(a) for a in roots}

    def _system_of(addon):
        # A tier that is not `system` HAS no system name, and inventing one is the
        # whole defect: `rules` is not one of the eleven, and neither is the kernel
        # or the port (ADR-0202 dec. 2; ADR-0139 dec. 8 for the kernel half. The
        # `ADR-0139 dec. 9, dec. 12` other comments in this file cite is a
        # mis-attribution inherited from ADR-0202 — ADR-0271 dec. 10).
        if tier_of[addon] != "system":
            return None
        if named:
            return named
        if addon in gone:
            return gone[addon]
        buckets = collections.Counter(
            _sg.classify(_sg._rel(q))
            for q in addon.rglob("*") if q.is_file() and q.suffix in _sg.SOURCE_SUFFIXES)
        return next((b for b, _ in buckets.most_common() if b in _sg.SYSTEMS), None)

    system_of = {a: _system_of(a) for a in roots}
    # The free set, spelled ONCE and read by arms 1, 2b, 4b and 5 below. Every one
    # of them used to spell it `system_of[...] is None`, which is why widening it
    # was a four-site edit nobody could see the shape of.
    free = {a: tier_of[a] in _sg._walk_roots.PORTABLE_TIERS for a in roots}
    homes = class_name_homes(roots)
    # Hoisted for the same reason `homes` is: the published surface is a fact about
    # every root, and re-deriving it inside the per-addon loop would walk all six
    # roots six times to answer one question.
    published = published_members(roots)
    # Arm 4c compares a DECLARATION against a PROVIDE, so the tree-wide provide map has
    # to exist before the first declaration is scored. Hoisted for `homes`' reason: it
    # parses every `plugin.gd` in the tree and the answer does not vary per addon.
    #
    # \U0001f534 ITS FAILURE DIRECTION IS THE LOUD ONE, and arm 4c is only safe to enforce
    # because of that. `_install_register_provides` swallows every exception and returns
    # `{}` — written for the REPORTING arm below, where an empty dict silently reverts
    # each row to its pre-ADR-0203 wording. An enforcing arm reading the same `{}` reds
    # EVERY declaration in the tree, which is a broken import announcing itself rather
    # than a false clean. That asymmetry is the licence; do not add a `if not provides:
    # skip` guard, which would convert it back into the silent direction.
    provides = _install_register_provides()

    # --- #1059 phase 2: arm 5's free set, one level finer than the tier ------
    #
    # `free[a]` frees a PACKAGE and four arms read it. Arm 5 is the only one that
    # holds a MEMBER NAME, and it is also the only one keyed on the reach's TARGET
    # rather than its subject — arms 1, 2b and 4b ask "is this package exempt from
    # being scored", arm 5 asks "may a sibling name this package's symbols". That
    # second question is the one ADR-0115 dec. 7 splits, so the split lands here
    # and nowhere else. Arms 1, 2b and 4b keep reading `free` unchanged, which is
    # what keeps `Arm1HasALiveSubject`'s seeded witness live across this change.
    #
    # RECONCILED IN BOTH DIRECTIONS, LOUDLY, BEFORE THE FIRST ROW IS SCORED.
    # `declared_member_kinds()` cannot see the published list and `published_members()`
    # cannot see the kinds, so on its own either one is happy with a map naming six of
    # thirty-one. A missing entry would otherwise surface as a KeyError deep in the
    # scan or — worse, if anyone ever `.get()`s it — as a member silently scored
    # `table`. #424's rule: a named list, never a filter.
    member_kinds = {}
    for a in roots:
        if tier_of[a] != "rules":
            continue
        facade = next((cn for cn, h in homes.items() if h == a), None)
        declared = _sg._walk_roots.declared_member_kinds(a)
        pub = published.get(facade, set())
        if set(declared) != pub:
            raise ValueError(
                "check_addon_portability: %s's MEMBER_KINDS and its published surface "
                "disagree. Published but undeclared: %s. Declared but unpublished: %s. "
                "Every member a `rules`-tier facade publishes declares exactly one of "
                "%s (#1059 phase 2); the two lists are edited in the same commit."
                % (_sg._rel(a), sorted(pub - set(declared)) or "none",
                   sorted(set(declared) - pub) or "none",
                   _sg._walk_roots.MEMBER_KINDS))
        member_kinds[a] = declared

    def member_free(home, name):
        """May a sibling name `name`, which `home` declares, for free?

        Three answers and they are deliberately not one expression. A FREE TIER is
        free wholesale — every member of the kernel is shared vocabulary and every
        member of the port is the platform seam, so there is nothing to split. A
        SYSTEM is never free; that is what arm 5 exists to print. `rules` is the
        only tier where the package and the member give different answers.

        🔴 THE UNRESOLVED FAÇADE IS NOT FREE, and it is not an oversight.
        `sibling_class_reaches` refuses to guess: a member the façade does not
        publish resolves to the bare `ExMateriaAlmanac` rather than to itself. That
        row names an INTERNAL of this package, which is a strictly worse dependency
        than naming a published table, so it takes the printed branch.
        """
        if free[home]:
            return True
        if tier_of[home] != "rules":
            return False
        member = name.split(".", 1)[1] if "." in name else None
        if member is None:
            return False
        return (member_kinds[home][member]
                in _sg._walk_roots.MEMBER_FREE_KINDS)

    for addon in roots:
        rel = _sg._rel(addon)
        # A package outside the walk has no classifier verdict, so take the SYSTEM
        # THAT WAS DECLARED rather than inferring one — the guess this family of
        # instruments refuses to make is exactly "`exmateria_sound` does not contain
        # the string Audio". The classifier stays the answer for a walk member.
        system = system_of[addon]
        scanned.append(rel)

        # --- arm 2: standalone parse --- runs for EVERY subject, the kernel
        # included: an addon the classifier books to no system must still not name
        # a host autoload, so this sits BEFORE arm 1's `continue`.
        # ONE bucket, not two. The `own is not None` split that used to send in-walk
        # addons to an unenforced `debt` list is gone — see `ARM2_BURN_DOWN`'s header for
        # why the reason it gave expired. `own` is still carried on the row so the report
        # can name which project.godot declares the identifier.
        own = package_project(addon)
        reaches = autoload_reaches(addon, host_auto)
        for r in reaches:
            parse_raw.append((rel, own) + r)

        # --- arm 6: a res:// path that leaves every addon root (#658) --- ENFORCING for
        # EVERY subject, and it sits before arm 1's `continue` deliberately: arm 1 skips
        # the kernel and the port because they are not systems, which leaves the two
        # addons everything else depends on free to name any host file. It is arm 3's
        # question in GDScript rather than arm 1's, so it needs no classifier verdict.
        for row in res_path_reaches(addon):
            path_raw.append(row)   # the burn-down split is report_walk's, not the walk's

        # --- arm 2b: a host autoload named as a node-path STRING (#648) --- ENFORCING
        # for every subject that is one of the eleven, and scored on ARM 5'S FREE SET
        # rather than arm 2's universe: the kernel and the platform PORT are what a
        # portable addon is allowed to name (ADR-0139 dec. 9, dec. 12), and the PORT
        # reaches a host singleton this way BY DESIGN (ADR-0175 dec. 2) — the mechanism
        # that turns a `project.godot [autoload]` dependency into an addon-presence one.
        # NOTE this is WIDER than #648, which asks only to exclude "the addon's own".
        # Measured, the extra width excuses NOTHING: the kernel routes to no host
        # singleton, so the free set carries the port's single `Tune` row and nothing
        # else (`test_the_kernel_and_the_port_are_free_and_the_real_tree_is_green`
        # asserts both halves, so the day that stops being true is a red, not a drift).
        # Enforcing and not debt for arm 3's reason — it needs no standalone project;
        # the name is in the host's autoload block or it is not.
        if not free[addon]:
            for row in autoload_route_reaches(addon, host_auto):
                route_bad.append((rel,) + row)

        # --- arm 3: host #include path (ADR-0169 dec. 5) --- ENFORCING for every
        # subject, because it needs no standalone project: a res:// path either
        # resolves inside an addon root or it does not. `res_root` is the project
        # the addon SHIPS IN — its own when it has one, the host's otherwise —
        # because that is what `res://` means for the shader compiler that will
        # read the line.
        res_root = own.parent if own is not None else PROJECT_DIR
        for row in include_reaches(addon, res_root):
            inc_bad.append(row)

        # --- arm 4: shader globals (ADR-0169 dec. 5; both sides, ADR-0171 dec. 5) ---
        # Arm 2's strictness rule, applied verbatim: an addon with its own
        # project.godot can be compiled standalone, so it is RED; an in-walk addon
        # has no project to fail against, so it is DEBT. Sits before arm 1's
        # `continue` for arm 2's reason — the kernel is not a system, and it must
        # still not bind a name the host alone declares.
        for row in shader_global_reaches(addon, shader_global_names(own)):
            (glob_bad if own is not None else glob_debt).append((rel,) + row)

        # --- arm 4b: only a NON-SYSTEM addon may DECLARE a global uniform ---
        # ENFORCING, unlike arm 4 above, and the difference is what each asks. Arm
        # 4 asks whether the HOST declares a name this addon binds — unanswerable
        # in-walk, because there is no standalone project to fail against, hence
        # DEBT. This asks which addon the DECLARATION SITS IN, which is a fact
        # about this tree and answerable right now.
        #
        # The free set is arm 5's, read from the same declaration and for the same
        # reason (ADR-0202 dec. 2, not the `ADR-0139 dec. 9, dec. 12` pair the
        # neighbouring comments cite — ADR-0271 dec. 10). `free[addon]` is true
        # for the kernel and the platform port, false for every other tier — the eleven
        # systems AND `rules`, which is not a free tier (#1059). A system that
        # declares a `global uniform` is charging its consumer a `[shader_globals]`
        # install step on its own account, which is the thing goal #5 measures.
        #
        # It went green at ADR-0190 and would have caught the defect that motivated
        # it: `Battlefield` declared four names its own `PSXDisplay` port pushed,
        # and one (`visible_angles_cull_mode`) that NOTHING pushed at all.
        if not free[addon]:
            for row in own_global_uniform_declarations(addon):
                decl_bad.append((rel,) + row)

        # --- arm 4c: THE DECLARER PROVIDES (ADR-0220 dec. 1) ---
        # ENFORCING, and it is arm 4b's other half. 4b rules WHO MAY DECLARE a
        # `global uniform` — only the kernel and the port. This rules that whoever does
        # declare one must also ship its `[shader_globals]` entry in its OWN
        # `plugin.gd`'s `const PROVIDED_GLOBALS`. Together they say: only the port
        # declares, and the declarer provides, so only the port provides.
        #
        # 🔴 IT IS `!= this addon`, NOT `is None`, AND THE DIFFERENCE IS THE WHOLE ARM.
        # `pixel_aspect` was provided for years — by `addons/exmateria_battlefield/plugin.gd`,
        # off a declaration in `addons/exmateria_platform/`. A "provided by anything"
        # test reads that green, and it is the Class C layering inversion ADR-0202 dec. 6
        # names: the rig's install target contains the port and NOT the battlefield, so
        # one declaration was arm-3 green for one subject and red for another. Keying on
        # the declaring addon is what makes the verdict follow the declaration.
        #
        # AND IT IS WHY THE RIG'S FAILURE WAS SILENT FOR A WHOLE EXTRACTION.
        # `unit_stretch.gdshaderinc` was created at #744 with no provider anywhere,
        # and the only instrument that could have said so was the install register — which
        # did not score `exmateria_sprite_rig` until #746. This arm answers the question
        # without a subject: a declaration with no provide is a defect the day it lands,
        # in whatever addon later includes it.
        for f, name, lines in own_global_uniform_declarations(addon):
            provider = provides.get("shader_globals/" + name)
            if provider != rel + "/plugin.gd":
                decl_unprovided.append((rel, f, name, lines, provider))

        # --- arm 5: sibling-addon class_name (ADR-0175 dec. 2) ---
        # Arm 1's rule one level down: symbol -> SIBLING ADDON rather than symbol ->
        # system. The kernel and the platform port are FREE and are the point — they
        # are what a portable addon is allowed to name (ADR-0202 dec. 2; the
        # `ADR-0139 dec. 9, dec. 12` pair other comments in this file cite is a
        # mis-attribution — ADR-0271 dec. 10). `member_free()` above is arm 1's own
        # test for exactly that set, read from the target package's declared `tier=`,
        # so `addons/exmateria_platform/` qualifies the day it exists without this
        # file learning its name.
        #
        # A FOURTH TIER, `rules`, IS NOT FREE WHOLESALE AND IS NOT PRINTED WHOLESALE
        # EITHER — that is #1059 phase 2 (ADR-0273). `exmateria_almanac` is shared by
        # seven of the eleven rather than owned by one, so freeing the package would
        # stop this arm printing lines that are still real dependencies; but 17 of the
        # 53 it printed named a `*Database`, which is ADR-0115 dec. 4's content shadow
        # and is expected of every system. So the free question is asked of the MEMBER,
        # against the kind its facade declares (`_walk_roots.MEMBER_FREE_KINDS`), and
        # the 36 lines that survive are the two members declared `state`. Adding
        # `rules` to `PORTABLE_TIERS` remains the rejected alternative and remains
        # priced by a test.
        # Everything else takes arm 2's strictness rule verbatim:
        # RED for a package with its own project.godot, DEBT for one without.
        #
        # THE FREE ROWS ARE PRINTED, and that is the arm's real work. ADR-0175 dec. 2
        # re-points 61 autoload reaches onto a `class_name` port precisely BECAUSE a
        # class_name travels with the addon while an [autoload] line cannot. That trade
        # is only honest if the surviving dependency is counted somewhere: arm 2 goes
        # quiet and nothing else in this file has a word for what replaced it.
        for f, name, home, lines in sibling_class_reaches(addon, homes, published):
            row = (rel, f, name, _sg._rel(home), lines)
            # FREE on either of two grounds, and the second was a false positive
            # this arm shipped with. (1) `member_free` — the target is the kernel or
            # the platform port (the two tiers `_walk_roots.PORTABLE_TIERS` names), or
            # it is a `rules` package and the MEMBER named is declared a `table`. (2) The
            # two addons SHIP IN THE SAME PACKAGE: `exmateria_sound` names `Spu`,
            # declared in `exmateria_spu`, on 51 lines, and both resolve to
            # `exmateria-sound/project.godot`. That is not a portability defect, it
            # is the vendoring the repo-root ADR-0003 dec. 4 relies on — *"D2's
            # vendoring guarantees the SPU addon is present whenever Sound is, so
            # the re-export never dangles."* Co-presence is guaranteed by
            # construction, so the reach cannot dangle.
            #
            # `own is not None` is load-bearing: two addons owned by the HOST share
            # a `None` and do NOT ship together — `exmateria_render` naming a
            # `class_name` of a future `exmateria_battlefield` is exactly the system
            # reach this arm exists to catch, and dropping the guard would excuse it.
            if member_free(home, name) or (own is not None
                                           and package_project(home) == own):
                sib_free.append(row)
            else:
                (sib_bad if own is not None else sib_debt).append(row)

        # --- arm 7: a `class_name` declared OUTSIDE every addon root (ADR-0223) ---
        # ENFORCING for EVERY subject, and it sits before arm 1's `continue` for arm
        # 6's reason: the question is the ADDRESS, so it needs no classifier verdict
        # and no standalone project. Arm 5 is this arm one level in — it asks whether
        # the declaring root is a SIBLING ADDON, and builds `homes` from the addon
        # roots alone, so a type declared in `src/` is in no map it reads.
        #
        # ONE SCAN, TWO ARMS. `outbound_reaches` is the same walk for both; splitting
        # it in two would read every file in the addon twice to ask two questions of
        # the same rows. The `system` argument is unused inside it (five shapes, none
        # of which consults the caller's system), so the kernel and the port pass "".
        reaches = _sg.outbound_reaches(rel, system or "")
        for r in reaches:
            if r.kind not in _ARM7_KINDS or _ADDON_RES_RE.match(r.dst_path):
                continue
            row = (r.rel, r.kind, r.target, r.dst_path, r.lines)
            type_raw.append(row)   # the burn-down split is report_walk's, not the walk's

        # --- arm 1: cross-system reach ---
        if free[addon]:
            continue          # the kernel is not a system; ADR-0139 dec. 9
        # 🔴 THE GATE IS THE TIER, NOT THE NAME, AND SWAPPING THE TWO WOULD HAVE
        # SILENCED THIS ARM OVER A WHOLE ADDON (#1059). `exmateria_almanac` has no
        # system name any more — it is `rules` — so `if system is None: continue`
        # would now skip it, and arm 1 going quiet over a package reads exactly
        # like a package with nothing to report. That is this guard's own founding
        # defect ("WHY THIS GUARD WAS GREEN WHILE BOTH WERE TRUE"). Only the two
        # FREE tiers are outside arm 1's subject; `rules` is inside it, and
        # `cross_system` below filters on the reach's DESTINATION regardless.
        # `cross_system` is arm 1's budget filter, and it is applied HERE rather
        # than inside `outbound_reaches` so arm 7 above can read the rows this one
        # is right to ignore. Arm 1's numbers do not move.
        for r in _sg.cross_system(reaches):
            arm1_raw.append((r.rel, r.kind, r.target, r.dst, r.lines))

    # --- arm 8 + 8b: the DECLARED DEPENDENCIES, and the engine they pick (#1241) ---
    # Scored AFTER the loop, off arm 5's own rows, because that is where the
    # measurement already is: `sib_free`/`sib_debt`/`sib_bad` partition every
    # `class_name` reach into a sibling by whether it is PERMITTED, and arm 8 asks a
    # question about the reach and not about the permission — a free reach into the
    # kernel is still something the rig has to stage. One scan, two arms, for arm 7's
    # reason.
    #
    # ITS SUBJECT IS THE RIG'S, NOT THE WALK'S, and the join is `_walk_roots.RIGS`
    # rather than a second list. `deps=` has exactly one consumer,
    # `tests/stranger/shared/rig.sh`, and `Rig.in_suite` is already the predicate for
    # "this root's rig is the one under `tests/stranger/`". The two EXTRACTED roots
    # are outside it and must be: they ship as one vendored package with their own
    # stock-Godot rigs, declare no `engine=` at all, and `exmateria_sound` naming
    # `exmateria_spu`'s `class_name` is the co-presence arm 5 already frees rather
    # than a staged dependency (repo-root ADR-0003 dec. 4).
    #
    # SKIPPED ENTIRELY UNDER `--root`, on arm 1's rule and for a sharper reason than
    # arm 1 has. `--root` NARROWS the walk to one package, so `homes` holds only that
    # package's `class_name`s and arm 5 measures ZERO sibling reaches by construction
    # — every declared dep would read as unreached. This is a claim about the WALK and
    # only the walk can falsify it.
    dep_rows = []
    if not named:
        measured = collections.defaultdict(lambda: collections.defaultdict(int))
        for row in sib_free + sib_debt + sib_bad:
            measured[row[0]][row[3]] += len(row[4])
        in_suite = {_sg._rel(r.root) for r in _sg._walk_roots.rigs() if r.in_suite}
        for addon in roots:
            rel = _sg._rel(addon)
            if rel not in in_suite:
                continue
            deps = _sg._walk_roots.declared_deps(addon)
            closure = _sg._walk_roots.dep_closure(addon)
            dep_rows.append((
                rel,
                _sg._walk_roots.declared_engine(addon),
                _sg._walk_roots.closure_engine(addon),
                deps,
                closure,
                # Keyed the way arm 5 prints a home, so the two blocks of the report
                # name the same string and a reader can join them by eye.
                {_sg._rel(PROJECT_DIR / "addons" / d): 0 for d in deps}
                | dict(measured.get(rel, {})),
            ))

    return {
        "scanned": scanned, "named": named,
        "arm1_raw": arm1_raw, "parse_raw": parse_raw,
        "inc_bad": inc_bad, "glob_bad": glob_bad, "glob_debt": glob_debt,
        "decl_bad": decl_bad, "decl_unprovided": decl_unprovided,
        "route_bad": route_bad, "path_raw": path_raw,
        "sib_free": sib_free, "sib_debt": sib_debt, "sib_bad": sib_bad,
        "type_raw": type_raw, "dep_rows": dep_rows,
    }


def report_walk(w) -> int:
    """Apply the three burn-downs to a `walk_addons()` result and print the report.

    Reads `ARM1_BURN_DOWN` / `ARM6_BURN_DOWN` / `ARM7_BURN_DOWN` at call time, so
    a test that patches one re-scores the SAME walk against a different list —
    that is what lets `test_check_addon_portability` share one clean-tree walk
    across its green arms and still seed its red ones. The guard itself is
    unchanged in what it walks: a plain run still walks the whole tree, and the
    cache lives in the TEST, where a wrong hit reds the test rather than making
    the guard green.

    `stale` is the arm that keeps a list from rotting: an entry whose reach was
    severed, or whose file no longer exists, fails exactly as an unlisted reach
    does. `--root` NARROWS the subject to one package, so every row naming a
    file outside it looks stale for a reason that is not debt being paid. The
    list is a claim about the WALK, and only the walk can falsify it — the same
    scoping rule arm 1 itself follows. (This is not hypothetical: it turned the
    tool's own `test_clean_package_exits_green` control red the first time it
    ran; the out-of-scope-not-stale rule is arm 7's own test for it.)
    """
    named = w["named"]
    scanned = w["scanned"]

    # --- the SUBJECT arm, and it is every arm's (#1225, ADR-0308 dec. 5 direction 3) ---
    # A ratchet has three ways to rot and the third is that its SUBJECT went empty: the
    # roots moved, `WALK_ROOTS` lost an entry, or an extraction finished and nobody
    # deleted the guard. EVERY arm below is a "nothing found" over `scanned`, so an
    # empty subject makes all of them vacuously green at once and prints a clean bill
    # over nothing. That is the ADR-0148 stale-root defect this file's own header
    # describes, which is why it is checked rather than assumed.
    #
    # Deliberately no count in this message. The first draft read "all fourteen of
    # them", which was invented — `grep -oE "^\s*# --- arm [0-9a-z]+"` reports TWELVE
    # (1, 2, 2b, 3, 4, 4b, 4c, 5, 6, 7, 8, 8b) — and a hardcoded arm count in a guard's
    # own output is a number nothing updates when arm 9 lands.
    if not scanned:
        print("\ncheck_addon_portability: FAIL — the SUBJECT IS EMPTY, so every arm below\n"
              "would pass by having nothing to look at. Either classify_blueprint.WALK_ROOTS\n"
              "and _walk_roots.EXTRACTED name no directory that exists, or a `--root` was\n"
              "given for a path that is not there. This is the one state a green report\n"
              "cannot be told from.")
        return 1
    # Arm 2's, on arms 1/6/7's rule and scoped the same way: `--root` NARROWS the
    # subject, so a row naming a file outside it is OUT OF SCOPE, not stale.
    parse_burn = [r for r in w["parse_raw"] if (r[2], r[3]) in ARM2_BURN_DOWN]
    parse_bad = [r for r in w["parse_raw"] if (r[2], r[3]) not in ARM2_BURN_DOWN]
    parse_stale = ([] if named else
                   sorted(set(ARM2_BURN_DOWN) - {(r[2], r[3]) for r in parse_burn}))
    inc_bad, glob_bad, glob_debt = w["inc_bad"], w["glob_bad"], w["glob_debt"]
    decl_bad, decl_unprovided = w["decl_bad"], w["decl_unprovided"]
    route_bad = w["route_bad"]
    sib_free, sib_debt, sib_bad = w["sib_free"], w["sib_debt"], w["sib_bad"]
    burn = [b for b in w["arm1_raw"] if (b[0], b[2]) in ARM1_BURN_DOWN]
    bad = [b for b in w["arm1_raw"] if (b[0], b[2]) not in ARM1_BURN_DOWN]
    stale = ([] if named else
             sorted(set(ARM1_BURN_DOWN) - {(b[0], b[2]) for b in burn}))
    # Arm 6's, on the same rule and scoped the same way: `--root` NARROWS the subject, so
    # every row naming a file outside it looks stale for a reason that is not debt paid.
    path_burn = [r for r in w["path_raw"] if (r[0], r[2]) in ARM6_BURN_DOWN]
    path_bad = [r for r in w["path_raw"] if (r[0], r[2]) not in ARM6_BURN_DOWN]
    path_stale = ([] if named else
                  sorted(set(ARM6_BURN_DOWN) - {(r[0], r[2]) for r in path_burn}))
    # Arm 7's, on the same rule and scoped the same way, and the scoping is not
    # optional: `--root` NARROWS the subject to one package, so a row naming a file
    # in another package is OUT OF SCOPE, not stale.
    type_burn = [r for r in w["type_raw"] if (r[0], r[2]) in ARM7_BURN_DOWN]
    type_bad = [r for r in w["type_raw"] if (r[0], r[2]) not in ARM7_BURN_DOWN]
    type_stale = ([] if named else
                  sorted(set(ARM7_BURN_DOWN) - {(r[0], r[2]) for r in type_burn}))

    # --- arms 8 and 8b: the `deps=` declaration against the measured reach ----
    # Split here rather than in the walk, on `report_walk`'s own rule: the walk's
    # output is a fact about the tree and the registers are claims about the walk,
    # so a test that patches a register re-scores the SAME walk.
    dep_rows = w["dep_rows"]
    dep_undeclared, dep_unreached, dep_diverged = [], [], []
    for rel, subject_engine, closure_engine, deps, _closure, meas in dep_rows:
        declared = {_sg._rel(PROJECT_DIR / "addons" / d): d for d in deps}
        for home, n in sorted(meas.items()):
            if n and home not in declared:
                dep_undeclared.append((rel, home, n))
        for home, d in sorted(declared.items()):
            if not meas.get(home):
                dep_unreached.append((rel, d))
        if subject_engine != closure_engine:
            dep_diverged.append((rel, subject_engine, closure_engine))
    dep_burn = [r for r in dep_unreached if r in ARM8_DEPS_NOT_BY_CLASS_NAME]
    dep_bad = [r for r in dep_unreached if r not in ARM8_DEPS_NOT_BY_CLASS_NAME]
    dep_stale = ([] if named else
                 sorted(set(ARM8_DEPS_NOT_BY_CLASS_NAME) - set(dep_burn)))
    eng_listed = [r for r in dep_diverged if r[0] in ARM8_CLOSURE_ENGINE]
    eng_bad = [r for r in dep_diverged if r[0] not in ARM8_CLOSURE_ENGINE]
    # A THIRD direction, and it is what makes the register's CONTENT load-bearing
    # rather than just its keys: a row that records `stock -> fork` while the tree
    # now reads `fork -> stock` names the right addon and the wrong fact.
    eng_wrong = [(rel, se, ce) for rel, se, ce in eng_listed
                 if ARM8_CLOSURE_ENGINE[rel][:2] != (se, ce)]
    eng_stale = ([] if named else
                 sorted(set(ARM8_CLOSURE_ENGINE) - {r[0] for r in eng_listed}))

    # Subject before result: an addon outside the walk is not scanned here, and a
    # green that did not look is the defect this whole family exists to catch.
    print("subject: %s%s" % (", ".join(scanned),
          "" if named else
          " (classify_blueprint.WALK_ROOTS plus _walk_roots.EXTRACTED). Any OTHER "
          "package outside the walk is not checked -- declare it in EXTRACTED, or "
          "point at it once with --root <path> --system <name>."))

    if sib_free:
        n = sum(len(r[4]) for r in sib_free)
        print("\ncross-addon class_name — %d line(s) name a `class_name` a SIBLING addon\n"
              "declares. Permitted: the kernel and the platform port are what a portable\n"
              "addon is allowed to name (ADR-0139 dec. 9, dec. 12). Printed because it is\n"
              "still an install-time dependency — the addon does not parse where the\n"
              "declaring addon is absent, and arm 2 cannot see it." % n)
        for rel, f, name, home, lines in sib_free:
            print("  %s:%s  %s -> declared in %s"
                  % (f, ",".join(map(str, lines[:6])) + ("…" if len(lines) > 6 else ""), name, home))

    if sib_debt:
        n = sum(len(r[4]) for r in sib_debt)
        print("\ncross-addon class_name DEBT — %d line(s) in an addon with no project.godot\n"
              "of its own name a `class_name` declared by a SIBLING addon that IS one of the\n"
              "eleven. Not enforced (no standalone project to parse against yet); it is arm\n"
              "1's defect wearing a global name instead of a typed reach." % n)
        for rel, f, name, home, lines in sib_debt:
            print("  %s:%s  %s -> declared in %s"
                  % (f, ",".join(map(str, lines[:6])) + ("…" if len(lines) > 6 else ""), name, home))

    if dep_rows:
        print("\ndeclared dependencies (`deps=`) — %d subject(s) whose stranger rig is\n"
              "tests/stranger/shared/rig.sh, which is the only OTHER reader of this key.\n"
              "The LINE and the CLOSURE are printed apart because they are two facts: the\n"
              "line is what the addon says about itself, the closure is what a consumer has\n"
              "to unzip, and the rig stages the closure. The ENGINE follows the closure too,\n"
              "so a `deps=` edit is a possible ENGINE change — that pair is printed here so\n"
              "a diff can move it rather than a reader having to re-derive it (#1241)."
              % len(dep_rows))
        for rel, subject_engine, closure_engine, deps, closure, meas in dep_rows:
            if subject_engine == closure_engine:
                eng = "engine %s (closure agrees)" % subject_engine
            else:
                owner = ARM8_CLOSURE_ENGINE.get(rel, ("", "", "UNREGISTERED"))[2]
                eng = ("engine %s declared -> closure needs %s  [%s]"
                       % (subject_engine, closure_engine.upper(), owner))
            print("  %s  %s" % (rel, eng))
            print("      deps    %s" % (" ".join(deps) or "none"))
            print("      closure %s" % (" ".join(closure) or "none"))
            print("      arm 5   %s"
                  % (" · ".join("%s %d" % (h, n) for h, n in sorted(meas.items())
                                if n) or "no sibling class_name reach"))

    if dep_burn:
        print("\ndeclared dependencies ARM 5 CANNOT SEE — %d, each NAMED in\n"
              "ARM8_DEPS_NOT_BY_CLASS_NAME with the reach that justifies it. Permitted, not\n"
              "debt: arm 5 measures `class_name` reaches and a dependency can be real and\n"
              "invisible to it — a `res://` path into the sibling's tree, a shader global\n"
              "its plugin.gd provides, a scene it instances. Named one at a time because a\n"
              "PATTERN here would excuse the stale declaration #1239 actually found."
              % len(dep_burn))
        for rel, d in dep_burn:
            owner, why = ARM8_DEPS_NOT_BY_CLASS_NAME[(rel, d)]
            print("  %s  declares %s\n      %s — %s" % (rel, d, owner, why))

    if parse_burn:
        n = sum(len(r[4]) for r in parse_burn)
        print("\nSTANDALONE-PARSE BURN-DOWN — %d line(s) in an addon name a HOST autoload\n"
              "identifier and are NAMED in ARM2_BURN_DOWN with an owner. Not a pass: this is\n"
              "goal #5's INSTALL half unmet, on record, with the ticket that closes it\n"
              "(#1225, ADR-0308 dec. 1).\n" % n)
        for rel, _own, f, name, lines in parse_burn:
            owner, why = ARM2_BURN_DOWN[(f, name)]
            print("  %s:%s  %s   [%s]"
                  % (f, ",".join(map(str, lines[:6])) + ("…" if len(lines) > 6 else ""),
                     name, owner))
            print("      %s" % why)

    if glob_debt:
        n = sum(len(d[4]) for d in glob_debt)
        # ⚠️ "the HOST declares" WAS THE WHOLE STORY AND STOPPED BEING IT AT ADR-0203.
        # This arm's question is "does an addon bind a `[shader_globals]` name it does not
        # ship the declaration for", and the answer used to be the same for all of these:
        # the consumer's `project.godot` was the only place the name could come from, so
        # every row was an uninstallable dependency. ADR-0203 dec. 1 gave the walk a second
        # source — a `plugin.gd` in the walk PROVIDES the name at enable time, with
        # `project.godot`'s own types and defaults — and a report that still called all of
        # them host-only would read as twelve equal debts when eleven of them now install
        # themselves. ADR-0203's Consequences assign this reconciliation to the pass that
        # builds the provide, which is where this annotation comes from.
        #
        # It is still DEBT and not OK, for the reason the header keeps: the provide is an
        # ENABLE-time write, so a project that copies the addons in and never enables the
        # plugin still gets nothing. What changed is that there is now a supported way to
        # get the name.
        #
        # 🔴 `psx_gamma` IS THE ONLY `[host]` ROW LEFT, AND IT IS THE ONLY HONEST ONE.
        # ADR-0203 named two — `psx_gamma` and `unit_stretch` — and the second was a
        # DEFECT rather than a category: it is declared at
        # `exmateria_platform/display_port/unit_stretch.gdshaderinc:24`, so under
        # ADR-0220 dec. 1 its declaring addon owes the provide, and once the port's
        # `plugin.gd` gained it both of its rows re-tagged `[host]` -> `[provided]` with no
        # other movement. Until that happened `exmateria_sprite_rig` could not install: the
        # rig `#include`s that header, and a missing `global uniform` fails the whole
        # shader. `psx_gamma` does not re-tag, because no file under any addon root
        # DECLARES it — the declaration is the host's `project.godot`, and this arm only
        # ever sees `PSXDisplay.gd:193` PUSHING the name. arm 4c cannot score it for the
        # same reason it is still here: a scan that starts at declarations cannot reach a
        # name that has none. ADR-0220 dec. 4 leaves it open deliberately.
        provided = _install_register_provides()
        print("\nshader-global DEBT — %d line(s) in an addon with no project.godot of its own\n"
              "bind a [shader_globals] name it does not ship the declaration for. NOT ENFORCED,\n"
              "and ADR-0238 replaces the reason this heading used to give. There ARE standalone\n"
              "projects now -- six stranger rigs, and tests/stranger/exmateria_platform/ compiles\n"
              "every seam below and passes. The engine is why: `global uniform` validation is\n"
              "gated on `Engine::is_editor_hint()` (shader_language.cpp), so outside the editor a\n"
              "missing name is NOT a compile error and no compile-based check can see it. It is\n"
              "SILENT -- the shader compiles, the name reads its type's zero (a pixel_aspect of 0.0 is\n"
              "a blank screen, ADR-0203 dec. 7) and the engine warns once per material at DRAW\n"
              "time. Quieter than the parse debt above, and worse for it.\n"
              "  [provided] a plugin.gd in the walk installs the name at enable time\n"
              "             (ADR-0203 dec. 1) — the consumer still needs the plugin ENABLED.\n"
              "  [host]     no addon provides it; the consumer must declare it by hand." % n)
        for rel, f, name, side, lines in sorted(
                glob_debt, key=lambda r: ("shader_globals/" + r[2] not in provided, r[1], r[2])):
            tag = "provided" if "shader_globals/" + name in provided else "host"
            print("  [%-8s] %s:%s  %s %s"
                  % (tag, f, ",".join(map(str, lines[:6])) + ("…" if len(lines) > 6 else ""),
                     side, name))

    if burn:
        n = sum(len(b[4]) for b in burn)
        print("\nPORTABILITY BURN-DOWN — %d reach line(s) leave an addon for a SYSTEM and are\n"
              "NAMED in ARM1_BURN_DOWN with an owner. Not a pass: this is goal #5 unmet, on\n"
              "record, with the ticket that closes it (ADR-0184 dec. 4)." % n)
        for f, kind, target, dst, lines in burn:
            owner, why = ARM1_BURN_DOWN[(f, target)]
            print("  %s:%s  %s -> %s.%s\n      %s — %s"
                  % (f, ",".join(map(str, lines)), kind, dst, target, owner, why))

    if path_burn:
        print("\nRES:// PATH BURN-DOWN — %d quoted `res://` literal(s) in an addon address a\n"
              "target outside every addon root and are NAMED in ARM6_BURN_DOWN with an owner.\n"
              "Not a pass: this is goal #5 unmet on the PATH axis, on record, with the ticket\n"
              "that closes it (#658, arm 1's shape)." % len(path_burn))
        for f, line, target in path_burn:
            owner, why = ARM6_BURN_DOWN[(f, target)]
            print("  %s:%d  %s\n      %s — %s" % (f, line, target, owner, why))

    if type_burn:
        n = sum(len(r[4]) for r in type_burn)
        print("\nHOST class_name BURN-DOWN — %d line(s) under an addon root name a\n"
              "`class_name` DECLARED OUTSIDE EVERY ADDON ROOT and are NAMED in\n"
              "ARM7_BURN_DOWN with an owner. Not a pass: this is goal #5 unmet on the TYPE\n"
              "axis, on record, with the ticket that closes it (ADR-0223, arm 1's shape)." % n)
        for f, kind, target, dst_path, lines in type_burn:
            owner, why = ARM7_BURN_DOWN[(f, target)]
            print("  %s:%s  %s -> declared in %s\n      %s — %s"
                  % (f, ",".join(map(str, lines)), target, dst_path, owner, why))

    if type_stale:
        print("\nSTALE ARM7_BURN_DOWN — %d entr(ies) name a `class_name` reach that no\n"
              "longer happens, or a file that is gone. Delete the row; a burn-down that\n"
              "outlives its debt is a list nobody rereads.\n" % len(type_stale))
        for f, target in type_stale:
            owner, _why = ARM7_BURN_DOWN[(f, target)]
            print("  %s  ->  %s   [%s]" % (f, target, owner))

    if parse_stale:
        print("\nSTALE ARM2_BURN_DOWN — %d entr(ies) name an autoload reach that no longer\n"
              "happens (or a file that is gone). Lower the list in the SAME commit that pays\n"
              "the debt: a baseline that outlives its debt re-admits the reach silently, which\n"
              "is the arm ADR-0308 dec. 5 names as the one a one-armed ratchet misses.\n"
              % len(parse_stale))
        for f, name in parse_stale:
            owner, _why = ARM2_BURN_DOWN[(f, name)]
            print("  %s  %s   [%s]" % (f, name, owner))

    if path_stale:
        print("\nSTALE ARM6_BURN_DOWN — %d entr(ies) name a path reach that no longer\n"
              "happens, or a file that is gone. Delete the row; a burn-down that outlives\n"
              "its debt is a list nobody rereads.\n" % len(path_stale))
        for f, target in path_stale:
            owner, _why = ARM6_BURN_DOWN[(f, target)]
            print("  %s  ->  %s   [%s]" % (f, target, owner))

    if stale:
        print("\nSTALE ARM1_BURN_DOWN — %d entr(ies) name a reach that no longer happens,\n"
              "or a file that is gone. Delete the row; a burn-down that outlives its debt\n"
              "is a list nobody rereads.\n" % len(stale))
        for f, target in stale:
            owner, _why = ARM1_BURN_DOWN[(f, target)]
            print("  %s  ->  %s   [%s]" % (f, target, owner))

    if dep_stale:
        print("\nSTALE ARM8_DEPS_NOT_BY_CLASS_NAME — %d entr(ies) name a declared dep that\n"
              "arm 5 DOES measure a `class_name` reach into, or an addon that is no longer a\n"
              "rig subject. Delete the row: it excuses a declaration that now needs no\n"
              "excuse, and an exception nobody rereads is how #1239 survived 474 commits.\n"
              % len(dep_stale))
        for rel, d in dep_stale:
            owner, _why = ARM8_DEPS_NOT_BY_CLASS_NAME[(rel, d)]
            print("  %s  ->  %s   [%s]" % (rel, d, owner))

    if eng_stale:
        print("\nSTALE ARM8_CLOSURE_ENGINE — %d entr(ies) register a subject whose rig\n"
              "binary no longer diverges from its own `engine=`, or an addon that is no\n"
              "longer a rig subject. That is the #1239 direction and it is the loud one: a\n"
              "row leaving this register means the BOOTED BINARY MOVED. Confirm the move was\n"
              "meant, then delete the row.\n" % len(eng_stale))
        for rel in eng_stale:
            se, ce, owner, _why = ARM8_CLOSURE_ENGINE[rel]
            print("  %s  registered %s -> %s   [%s]" % (rel, se, ce, owner))

    if eng_wrong:
        print("\nARM8_CLOSURE_ENGINE ROW DISAGREES WITH THE TREE — %d entr(ies) name the\n"
              "right addon and the wrong pair. The row records which binary the rig boots and\n"
              "off whose declaration; a row that is merely PRESENT would make the register a\n"
              "list of names rather than of facts.\n" % len(eng_wrong))
        for rel, se, ce in eng_wrong:
            rse, rce, owner, _why = ARM8_CLOSURE_ENGINE[rel]
            print("  %s  registered %s -> %s, measured %s -> %s   [%s]"
                  % (rel, rse, rce, se, ce, owner))

    if (not bad and not stale and not parse_bad and not inc_bad and not glob_bad
            and not sib_bad and not decl_bad and not route_bad and not path_bad
            and not path_stale and not decl_unprovided
            and not parse_stale and not type_bad and not type_stale
            and not dep_undeclared and not dep_bad and not dep_stale
            and not eng_bad and not eng_stale and not eng_wrong):
        print("\naddon portability OK — %s reach no system, name no foreign autoload — as a\n"
              "bare identifier OR as a node-path string — include no file outside an addon\n"
              "root, bind no shader global they do not own, PROVIDE every `global\n"
              "uniform` they declare, name no sibling addon's class_name outside the\n"
              "kernel and the port, quote no `res://` path leaving the addon roots,\n"
              "name no `class_name` declared outside every addon root, DECLARE in `deps=` every\n"
              "sibling addon they reach and nothing they do not, and diverge from their\n"
              "dependency closure's engine only where ARM8_CLOSURE_ENGINE says so — beyond the\n"
              "burn-downs above (goal #5)."
              % ", ".join(scanned))
        if burn:
            print("%d reach line(s) are on ARM1_BURN_DOWN above and are NOT part of that "
                  "sentence." % sum(len(b[4]) for b in burn))
        if parse_burn:
            print("%d line(s) are on ARM2_BURN_DOWN above and are NOT part of that "
                  "sentence." % sum(len(r[4]) for r in parse_burn))
        if type_burn:
            print("%d line(s) are on ARM7_BURN_DOWN above and are NOT part of that "
                  "sentence." % sum(len(r[4]) for r in type_burn))
        return 0

    if parse_bad:
        n = sum(len(b[4]) for b in parse_bad)
        print("\nSTANDALONE PARSE: %d line(s) name an identifier only an autoload block declares (goal #5).\n" % n)
        for rel, own, f, name, lines in parse_bad:
            # `own` is None for an IN-WALK addon, which ships in the host project and has
            # no `project.godot` of its own. Its standalone project is its STRANGER RIG,
            # which declares an empty `[autoload]` block on purpose (ADR-0308 §1) — so
            # name that rather than printing `None`, because the rig is where a reader
            # reproduces this row.
            where = (_sg._rel(own) if own is not None
                     else "%s (empty [autoload] on purpose)"
                          % _sg._rel(PROJECT_DIR / "tests" / "stranger"
                                     / pathlib.Path(rel).name / "project.godot"))
            print("  %s:%s  %s -> declared by %s, NOT by %s"
                  % (f, ",".join(map(str, lines)), name,
                     _sg._rel(PROJECT_DIR / "project.godot"), where))
        print("\nReach the singleton by NODE PATH instead — it names no symbol, so the file\n"
              "parses in any project and simply returns null where the consumer did not\n"
              "autoload it:\n"
              "    var loop := Engine.get_main_loop() as SceneTree\n"
              "    var e = loop.root.get_node_or_null(^\"Name\") if loop != null else null\n"
              "Cache it, keep the variable UNTYPED (a `Node` type cannot reach the members),\n"
              "and use get_main_loop() rather than get_node() so it also works off-tree.\n"
              "\n⚠️ THAT REMEDY IS NOT OPEN TO EVERY SUBJECT — see arm 2b below. The node path\n"
              "is free on two grounds and neither is 'it compiles': the autoload points at a\n"
              "script THIS addon ships, or the addon is the kernel or the platform port. A\n"
              "SYSTEM naming a script it does not ship has swapped a parse error for a silent\n"
              "null, which is a worse report of the same dependency. Its answer is a PORT —\n"
              "the signature `addons/exmateria_platform/` publishes, soft-bound at call time\n"
              "(ADR-0175 dec. 2).")

    if path_bad:
        print("\nRES:// PATH: %d quoted `res://` literal(s) under an addon root address a\n"
              "target outside every addon root (goal #5, #658).\n" % len(path_bad))
        for f, line, target in path_bad:
            print("  %s:%d  %s" % (f, line, target))
        print("\nShipping the addon ships the FILE; it does not ship what the file addresses —\n"
              "arm 3's sentence in GDScript. A stranger project has no `src/` and need not have\n"
              "an `assets/` laid out this way, so the literal is the HOST's address and the\n"
              "addon does not carry the host. Move the target under an addon root, or take the\n"
              "root FROM the consumer: `addons/exmateria_battlefield/install/BattlefieldContent.gd`\n"
              "is the shipped precedent — a declared project setting the host points at its own\n"
              "layout, which turns an address the addon asserts into one the consumer supplies\n"
              "(ADR-0202).")

    if route_bad:
        n = sum(len(r[3]) for r in route_bad)
        print("\nAUTOLOAD ROUTE: %d line(s) hand a HOST autoload's name to get_node/\n"
              "get_node_or_null/has_node/find_child as a STRING (goal #5, #648, ADR-0191).\n" % n)
        for rel, f, name, target, lines in route_bad:
            print("  %s:%s  \"%s\" -> %s"
                  % (f, ",".join(map(str, lines)), name, target))
        print("\nArm 2's break with the parse error taken out: the file compiles anywhere and\n"
              "returns null where the consumer did not autoload the name, so the dependency is\n"
              "no smaller and the report of it is. The addon does not ship that script. Reach\n"
              "it through a PORT — the signature `addons/exmateria_platform/` publishes,\n"
              "soft-bound by node path at call time with a defined ABSENT behaviour per verb\n"
              "(ADR-0175 dec. 2) — or invert the reach so the host passes the value in.")

    if bad:
        n = sum(len(b[4]) for b in bad)
        print("\nPORTABILITY: %d reach line(s) leave an addon for a SYSTEM (goal #5, ADR-0151).\n" % n)
        for f, kind, target, dst, lines in bad:
            print("  %s:%s  %s -> %s.%s" % (f, ",".join(map(str, lines)), kind, dst, target))
        print("\nA system's panel ships as a plain Control satisfying "
              "DebugOverlay.register_panel(panel, category) —\nit is duck-typed and the harness names no panel. "
              "A panel that is only TuneField rows is not\nbuilt at all: ADR-0068 dec. 9 renders every registered slug "
              "on the F3 Registry page.")
    if inc_bad:
        print("\nHOST INCLUDE: %d `#include` line(s) under an addon root reach outside every\n"
              "addon root (goal #5, ADR-0169 dec. 5).\n" % len(inc_bad))
        for f, line, target, why in inc_bad:
            print("  %s:%d  #include %s -> %s" % (f, line, target, why))
        print("\nShipping the addon ships the FILE; it does not ship what the file includes.\n"
              "Move the include target under an addon root — `addons/exmateria_schema/` is the\n"
              "precedent and the shape — or inline it. A `res://` path that leaves the addon is\n"
              "the host's address, and the addon does not carry the host.")

    if decl_bad:
        n = sum(len(d[3]) for d in decl_bad)
        print("\nGLOBAL UNIFORM DECLARED BY A SYSTEM — %d line(s). Only the kernel and\n"
              "the platform port may declare one: a `global uniform` name lives in the\n"
              "CONSUMING project's `project.godot [shader_globals]`, so a system that\n"
              "declares one charges every consumer an install step on its own account\n"
              "(ADR-0190). Move the declaration to a seam in `addons/exmateria_platform/`\n"
              "and `#include` it — or, if nothing ever WRITES the name, it is a `const`\n"
              "wearing a uniform's clothes and should be one." % n)
        for rel, f, name, lines in decl_bad:
            print("  %s:%s  declares %s" % (f, ",".join(map(str, lines)), name))

    if decl_unprovided:
        n = sum(len(d[3]) for d in decl_unprovided)
        print("\nDECLARED BUT NOT PROVIDED BY ITS DECLARER — %d line(s). An addon that\n"
              "declares a `global uniform` charges every consumer a `[shader_globals]`\n"
              "entry, and a missing one is SILENT outside the editor -- the shader compiles\n"
              "and the name reads its type's zero (ADR-0238, correcting ADR-0169). That is\n"
              "why the provide matters MORE, not less. ADR-0220 dec. 1: the addon that DECLARES\n"
              "the name PROVIDES it, in its own `plugin.gd`'s `const PROVIDED_GLOBALS`,\n"
              "with `project.godot`'s type and default.\n"
              "  [unprovided]   nothing in the tree installs the name at all.\n"
              "  [wrong addon]  something installs it, but not the declarer — so the name\n"
              "                 is provided for one install target and missing for the\n"
              "                 next, off one declaration (ADR-0202 dec. 6, Class C)." % n)
        for rel, f, name, lines, provider in sorted(decl_unprovided, key=lambda r: (r[1], r[2])):
            tag = "unprovided" if provider is None else "wrong addon"
            where = "nothing provides it" if provider is None else "provided by " + provider
            print("  [%-11s] %s:%s  declares %s — %s"
                  % (tag, f, ",".join(map(str, lines)), name, where))

    if glob_bad:
        n = sum(len(b[4]) for b in glob_bad)
        print("\nSHADER GLOBALS: %d line(s) bind a [shader_globals] name this package does not\n"
              "declare (goal #5, ADR-0169 dec. 5, ADR-0171 dec. 5).\n" % n)
        for rel, f, name, side, lines in glob_bad:
            print("  %s:%s  %s %s" % (f, ",".join(map(str, lines)), side, name))
        print("\nA `global uniform` is arm 2's defect in GDShader and the engine's answer is\n"
              "QUIETER — outside the editor it is not an error at all, just a zero-valued\n"
              "uniform and a draw-time warning (ADR-0238). Declare the name in the\n"
              "package's own project.godot [shader_globals] block, or stop binding it. Note both\n"
              "sides count: a file that only PUSHES the name through\n"
              "RenderingServer.global_shader_parameter_set declares nothing and still cannot\n"
              "ship without it.")

    if type_bad:
        n = sum(len(r[4]) for r in type_bad)
        print("\nHOST class_name: %d line(s) under an addon root name a `class_name`\n"
              "DECLARED OUTSIDE EVERY ADDON ROOT (goal #5, ADR-0223).\n" % n)
        for f, kind, target, dst_path, lines in type_bad:
            print("  %s:%s  %s -> declared in %s"
                  % (f, ",".join(map(str, lines)), target, dst_path))
        print("\nArm 5's sentence with the sibling taken out, and it is the STRICTER half: a\n"
              "`class_name` is a global the PROJECT's script-class cache mints by scanning the\n"
              "project, so a type declared in `src/` exists only where the HOST is. Shipping\n"
              "the addon ships the file; it does not ship the host that declares the name.\n"
              "Move the shared symbol into `addons/exmateria_schema/` — the shipped precedent\n"
              "and the shape — or invert the reach so the host passes the value in. Naming it\n"
              "through a PORT is NOT open here: a port publishes a signature soft-bound at call\n"
              "time (ADR-0175 dec. 2), and a TYPE is bound at parse time.")

    if dep_undeclared:
        n = sum(r[2] for r in dep_undeclared)
        print("\nUNDECLARED DEPENDENCY: %d line(s) name a `class_name` declared by a SIBLING\n"
              "addon that `plugin.cfg`'s `deps=` does not name (goal #5, #1241).\n" % n)
        for rel, home, n in dep_undeclared:
            print("  %s  reaches %s on %d line(s), undeclared" % (rel, home, n))
        print("\nThis direction is unconditional and has no exception list, because the reach\n"
              "arm 5 measured is a reach the rig must STAGE or the addon does not parse: a\n"
              "`class_name` is a global the PROJECT's script-class cache mints by scanning\n"
              "the project. `tests/stranger/shared/rig.sh` stages the declared closure and\n"
              "NOTHING ELSE, deliberately — *\"an undeclared dep staged anyway would let the\n"
              "rig quietly supply something the addon never said it needed\"*. Add the addon\n"
              "to `deps=`, with the measurement inline the way the shipped keys carry theirs,\n"
              "or stop reaching it. ⚠️ Check the census above before you add it: `deps=` also\n"
              "picks the rig's BINARY, so adding a `fork` dep to a `stock` subject moves\n"
              "ARM8_CLOSURE_ENGINE too.")

    if dep_bad:
        print("\nDECLARED DEPENDENCY NOTHING REACHES: %d declared dep(s) that arm 5 measures\n"
              "no `class_name` reach into, and that ARM8_DEPS_NOT_BY_CLASS_NAME does not name\n"
              "(goal #5, #1241, #1239).\n" % len(dep_bad))
        for rel, d in dep_bad:
            print("  %s  declares %s, and reaches no `class_name` it declares" % (rel, d))
        print("\nEither the declaration is STALE — #1239 is exactly this, a dep\n"
              "`exmateria_catalogue` had not reached since #1071 and carried for 474 commits\n"
              "— or the dependency is real and arm 5 cannot see it, which is a `res://` path\n"
              "into the sibling's tree, a `[shader_globals]` name its plugin.gd provides, an\n"
              "autoload it registers, or a scene it instances. Delete the dep, or NAME it in\n"
              "ARM8_DEPS_NOT_BY_CLASS_NAME with an owner and the reach that justifies it.\n"
              "⚠️ Deleting one can change which binary the rig boots — see the census above.")

    if eng_bad:
        print("\nCLOSURE ENGINE NOT REGISTERED: %d subject(s) whose rig boots a binary their\n"
              "own `engine=` does not name, and that ARM8_CLOSURE_ENGINE does not carry\n"
              "(goal #5, #1241, #1099).\n" % len(eng_bad))
        for rel, se, ce in eng_bad:
            print("  %s  declares engine=\"%s\", closure needs \"%s\"" % (rel, se, ce))
        print("\n`tests/stranger/shared/rig.sh` boots the binary that can parse everything it\n"
              "STAGES, which is the CLOSURE — correctly, and for ADR-0194 dec. 7's reason. The\n"
              "cost is that dec. 7's absence arm then underwrites the CLOSURE's fork\n"
              "requirement and NOT this subject's declaration, so nothing checks the\n"
              "subject's own `engine=` any more: goal #5 is unmet on the declaration axis for\n"
              "it (#1099). Do NOT fix this by promoting the subject's `engine=` — that would\n"
              "make the plugin.cfg claim a primitive the addon does not name, which is the\n"
              "other error. Either drop the dependency that pulls the fork in, or register the\n"
              "divergence in ARM8_CLOSURE_ENGINE with an owner and the measurement.")

    if sib_bad:
        n = sum(len(r[4]) for r in sib_bad)
        print("\nCROSS-ADDON class_name: %d line(s) name a `class_name` declared by a SIBLING\n"
              "addon that is one of the eleven (goal #5, ADR-0175 dec. 2).\n" % n)
        for rel, f, name, home, lines in sib_bad:
            print("  %s:%s  %s -> declared in %s" % (f, ",".join(map(str, lines)), name, home))
        print("\nA `class_name` is a global the PROJECT's script-class cache mints by scanning\n"
              "the project, so this is arm 2's break in another spelling: the file parses only\n"
              "where the declaring addon is installed too. The kernel and the platform port are\n"
              "the two an addon may depend on; a SYSTEM is not one of them. Move the shared\n"
              "symbol into `addons/exmateria_schema/` — the shipped precedent and the shape —\n"
              "or invert the reach so the host passes the value in.")

    return 1


def main() -> int:
    """The shipped entry point: parse `--root`/`--system`, walk, report.

    Thin on purpose, so the walk and the report stay separable — see the note on
    the `walk_addons` / `report_walk` split above. `--root` NARROWS the subject
    to one package with a named system; everything else is the full walk.
    """
    if "--root" in sys.argv:
        extra = (PROJECT_DIR / sys.argv[sys.argv.index("--root") + 1].rstrip("/")).resolve()
        if not extra.is_dir():
            print(f"--root {extra} is not a directory")
            return 1
        if "--system" not in sys.argv:
            print("--root needs --system <name>: a package outside the walk has no "
                  "classifier verdict, and guessing it from the directory name is wrong "
                  "for the case that motivates the flag (`exmateria_sound` is `Audio`).")
            return 1
        named = sys.argv[sys.argv.index("--system") + 1]
        if named not in _sg.SYSTEMS:
            print(f"--system {named} is not one of the eleven: {_sg.SYSTEMS}")
            return 1
        return report_walk(walk_addons([extra], named, {}))
    roots, gone = full_roots()
    return report_walk(walk_addons(roots, None, gone))


if __name__ == "__main__":
    sys.exit(main())
