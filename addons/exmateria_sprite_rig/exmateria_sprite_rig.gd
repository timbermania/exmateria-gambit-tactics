class_name ExMateriaSpriteRig
extends RefCounted

## The whole public surface of `addons/exmateria_sprite_rig`, and the only name
## it puts in your project.
##
## Godot has no package scope: a `class_name` is engine-global, so every one an
## addon declares lands in YOUR global scope — and when you declare a colliding
## one, the ADDON's file is what fails to parse, pointing your error at a file
## you did not write.
##
## 🔴 THE POPULATION HAS ARRIVED AND THE BURN-DOWN IS NO LONGER EMPTY (#744,
## 2026-09-01). 33 files moved in, and `check_addon_globals.py`'s burn-down was
## seeded with the **23** global `class_name`s that came with them — not the 24
## #744's own text predicted, because `AnimationOpcodes` was the 24th and #742
## (`d43fd371b`) had already stripped it when it landed the skeleton. It reads
## **20** now: the three resource classes came off in this same pass, because a
## boot proved `resources/map.tres` still loads without them and every one of
## their namers is inside this addon, so no host use site moved. #746 drains the
## 20. Both ratchet arms are enforcing around that number the whole time, so
## landing the files and stripping every name in one commit — which would break
## every host namer at once with no green step between — is not what happened.
##
## Eighteen of the 20 are ALSO published below, which is not a contradiction: the
## burn-down is the `class_name` channel and the constants are the symbol channel,
## and #746 removes each `class_name` while the constant stays. A name that is on
## the burn-down and NOT below is one nothing outside the addon reaches — after
## #746 that set is exactly `AnimationClock` and `PlaybackSet`.
##
## A script constant is a full type — annotation, `is` check, `.new()`:
##
##     var op: int = ExMateriaSpriteRig.AnimationOpcodes.Op.LOAD_FRAME_WAIT
##
## and a consumer may alias one back to a bare local name, which is what keeps
## every existing use site spelled the way it was (ADR-0211 dec. 4):
##
##     const AnimationOpcodes = ExMateriaSpriteRig.AnimationOpcodes
##
## 🔴 AN ALIAS IS A PER-CLASS DECLARATION, NOT A PER-FILE ONE. Where a script
## EXTENDS another that already aliases a name, the child must NOT repeat it —
## GDScript refuses a member that already exists in the parent, and the parse
## error takes the whole child out. None of this addon's six current consumers
## inherits from another, so all six carry their own line; that stops being true
## as the rig's own class hierarchy moves in.
##
## **This list IS the supported surface.** If a script is not named here it is
## internal, whatever its visibility says — and `tools/check_addon_globals.py`
## holds both directions: nothing else in this addon may declare a global, and
## nothing named here may dangle.
##
## 🔴 THE SCENE IS NOT PUBLISHED HERE, AND THAT IS DELIBERATE (ADR-0217 dec. 3).
## `assets/scenes/Unit.tscn` names the rig by `ext_resource` path and is a
## `check_lattice_scene.py` `DECLARED_MOUNTS` row — the shape that collapses 114
## referencing files to one. A `const UnitRig = preload("…/UnitRig.tscn")` here
## would satisfy `_PUBLISHED_CONST`, resolve fine, and give the rig **two
## spellings of one publish**: a symbol channel and a path channel naming the
## same thing, so pass 9 would have two numbers for one question. ADR-0205 dec. 2
## already forbids exactly that merge for the guards.
##
## Nothing here is instantiated. `ExMateriaSpriteRig.new()` gives you an empty
## RefCounted; the class exists to be a namespace, not an object.


# --- the SEQ opcode vocabulary ---------------------------------------------

## The unit-sprite SEQ opcode vocabulary — `Op`, the opcode a sequence step
## carries, and `SideEffect`, what a playback step emits — plus `from_string`,
## the name→`Op` lookup the database uses while parsing.
##
## 🔴 BOTH ENUMS STAY IN THIS ONE FILE (ADR-0217 dec. 6). They share four member
## names at DIFFERENT integer values (`Op.QUEUE_SPRITE_ANIM` = 2,
## `SideEffect.QUEUE_SPRITE_ANIM` = 0), so splitting them across a package
## boundary would manufacture a conflation hazard in the pass that exists to
## retire conflation hazards. `Op` has zero namers outside the rig; `SideEffect`
## crosses on exactly one line once dec. 4 moves `SequenceViewer` in.
## Host use: `src/gpu/CombatLoop.gd` tests `SideEffect.POST_GENERIC_ATTACK`
## before posting a generic attack — that is the host use, and it is the whole of it.
## `addons/exmateria_sprite_rig/sequence/AnimationPlayback.gd` drives the `Op` table
## that maps an opcode to its frame offset, but it is an **in-addon namer** (ADR-0217
## dec. 5): a file inside this very addon, so it is evidence that the name is USED, not
## evidence that a host needs it published. `Op` in fact has zero namers outside the rig
## and rides along because both enums stay in one file (dec. 6, above).
const AnimationOpcodes = preload("res://addons/exmateria_sprite_rig/sequence/AnimationOpcodes.gd")


# --- the content port -------------------------------------------------------

## The rig's ONE content port — seven scalar queries the HOST implements, over
## four different key spaces (ROM item id, weapon type id, job hex string,
## ability id), with the key kind carried in every parameter name (ADR-0217
## dec. 9, ADR-0215 dec. 6).
##
## The rig does not know what a combatant IS: it asks for numbers and owns the
## pixels. Seven call sites used to name four host content stores directly; this
## port is what they name instead, and it holds no reference to any of them —
## the binding is a node-path soft-bind to whatever the consuming project
## registers as `SpriteRigContent` (ADR-0203 dec. 2's *injects the content it
## cannot*, in `TunePort`'s shape).
##
## 🔴 IT HAS A DEFINED ABSENT BEHAVIOUR AND THAT IS THE POINT. With no adapter
## in the project every query answers what an EMPTY content set would — except
## `ability_effect_anim_id`, where `0` is a real answer and absent is `-1`. The
## table is in the port's own docstring.
## Host use: `src/data/SpriteRigContent.gd` is the host adapter that ANSWERS the port
## and `tests/SpriteRigContentPortTest.gd` is the contract test — those two are the host
## use, and they are on the implementing side, which is the whole shape of a port.
##
## The four CALLERS are all **in-addon namers** (ADR-0217 dec. 5) —
## `addons/exmateria_sprite_rig/layers/SpriteLayerManager.gd`, `addons/exmateria_sprite_rig/layers/WeaponAnimationSelector.gd`,
## `addons/exmateria_sprite_rig/layers/AnimationResolutionMap.gd` and `addons/exmateria_sprite_rig/content/SpritePaletteResolver.gd`.
## Labelled rather than removed because for a PORT the direction is inverted on purpose:
## the addon calls and the host implements, so "only this addon names it" is what a
## correct port looks like, not the shrunk-to-one-adapter interface ADR-0215 dec. 4
## warns about. The label is what lets pass 9 count the two cases apart.
const ContentPort = preload("res://addons/exmateria_sprite_rig/content/ContentPort.gd")


# --- the eighteen names host code actually reaches --------------------------
#
# 🔴 THIS LIST IS MEASURED, NOT PREDICTED (#746, 2026-09-02), AND THE
# MEASUREMENT FALSIFIED THE PREDICTION. ADR-0217 dec. 2 and #746's own text
# said NINE published names carrying 18 behaviour members, with the other
# fifteen reached from nowhere outside this addon. A census of every bare-global
# namer in the tree — `#` comments and `"""` docstrings stripped, `Name.gd`
# path strings excluded, `ExMateriaSpriteRig.Name` façade accesses excluded —
# reads **eighteen** names carrying **30** non-enum members plus one enum, over
# 53 host files. #746's acceptance criteria say exactly what to do with that:
# *"If it is more, P1 is falsified at >24 non-enum members reached from outside
# — report the number, do not tune the interface to hit it."* 30 > 24, so P1 is
# FALSIFIED and what stands below is the measured surface, not a tuned one.
#
# THE PREDICTION WAS NOT OFF BY A ROUNDING ERROR, AND WHY IS WORTH KEEPING. It
# was derived from `check_lattice_scene.py` ARM 1, which scores `res://` PATH
# reaches: ten `preload()` lines over three production files and seven tests
# were the whole of what arm 1 could see. The SYMBOL channel — a host naming a
# global `class_name` with no path anywhere — is invisible to it BY DESIGN
# (ADR-0212 dec. 5 says the same about `#include`), and that is where the other
# twelve live. `AnimationStateController.angle_12bit_to_facing` alone is named
# on 18 lines across 13 files and has no path reach to score.
#
# What is NOT here is now a list of TWO. `AnimationClock` and `PlaybackSet` are
# reached from nowhere outside this addon and stay internal `preload`s.
# Publishing them "for symmetry" is how a shallow interface gets ratified —
# ADR-0215 rejects publishing `SpriteLayerManager` as *the* interface for that
# reason, on width of NAME rather than of interface. The three resource classes
# and `SequenceViewer` hold no global name either (#744) and are likewise not
# published.

## The per-unit sprite compositor — three sampled layers on one mesh
## (ADR-0019), the WEP1/EFF1 caches, and the `Layer` enum's driver.
## Host use: `src/scenarios/ScenarioVM.gd`'s `CinematicWalkState` drives a
## cutscene walk through it; `tests/DepthCenterBboxTest.gd`,
## `tests/FormationPlacementTest.gd` and `tests/UnitShaderPanelTuneFieldTest.gd`
## each instantiate one.
const SpriteLayerManager = preload("res://addons/exmateria_sprite_rig/layers/SpriteLayerManager.gd")

## Which WEP1 animation id a weapon plays, keyed by weapon TYPE id.
## Host use: `src/gpu/CombatLoop.gd` resolves the attacker's weapon animation
## before posting a generic attack.
const WeaponAnimationSelector = preload("res://addons/exmateria_sprite_rig/layers/WeaponAnimationSelector.gd")

## The per-unit painter: PlaybackSets, the body/secondary layers, the React
## cascade and `current_anim_id`.
## Host use: `src/units/Unit.gd` owns one as its sole façade onto playback —
## consumers never name it — and `tests/UnitDisplayReactionDefaultTest.gd` holds
## the written-out reaction default against `Battle`'s enum.
const UnitDisplay = preload("res://addons/exmateria_sprite_rig/render/UnitDisplay.gd")

## The distort-move controller — the sub-tile slide a WALKING unit plays.
## Host use: `src/units/Unit.gd` constructs one per unit.
const DistortMovementController = preload("res://addons/exmateria_sprite_rig/state/DistortMovementController.gd")

## The cinematic pose lookup — cardinal index to SEQ pose, on the PSX
## sprite-pose wheel, which is NOT the world wheel (see `ExMateriaSchema.Facing`).
## Host use: `tests/CinematicLowRangeSeqKeyTest.gd` asserts the low-range keys.
const CinematicPoseLUT = preload("res://addons/exmateria_sprite_rig/state/CinematicPoseLUT.gd")

## The crystal-body compositor — the substitute rig a dead unit's crystal wears.
## Host use: `tests/CrystalSpriteCompositorTest.gd` drives it directly. Its
## `EngineFoldCompositor` half is `Render`'s and is reached through that addon.
const CrystalSpriteCompositor = preload("res://addons/exmateria_sprite_rig/crystal/CrystalSpriteCompositor.gd")


# --- the sequence layer -----------------------------------------------------

## The SEQ/SHP animation-set store — `get_set(seq_type, shp_type)` hands back the
## `UnitAnimationSet` for a sprite pair, parsed once and cached.
## Host use: `src/units/Unit.gd` resolves its own set on mount and again on a job
## change; `src/ui3/formation/FormationScene.gd` resolves one per roster row; and
## `tests/FormationAllTemplatesMountTest.gd` walks every template through it.
const AnimationDatabase = preload("res://addons/exmateria_sprite_rig/sequence/AnimationDatabase.gd")

## The parsed SEQ for one sprite pair — the type1/type2 sequence tables a
## `UnitDisplay` plays and an `AnimationFrameCalculator` measures.
## Host use: `src/units/Unit.gd` holds the unit's resolved set as
## `var animation_set: UnitAnimationSet` and hands it to the rig.
const UnitAnimationSet = preload("res://addons/exmateria_sprite_rig/sequence/UnitAnimationSet.gd")

## Frame arithmetic over a SEQ table — `get_frame_at(anim_id, tick, seq)` and
## `get_duration(anim_id, seq)`, both pure.
## Host use: `src/units/Unit.gd` sizes an attack window from `get_duration`;
## `src/ui3/formation/FormationScene.gd` picks the roster pose with `get_frame_at`;
## `tests/UnitThrowBodyDispatchTest.gd` reads the front/back throw slots the same way.
const AnimationFrameCalculator = preload("res://addons/exmateria_sprite_rig/sequence/AnimationFrameCalculator.gd")

## One opcode-walking playback head over a SEQ animation.
## Host use: `src/units/Unit.gd` converts a frame count to seconds with
## `AnimationPlayback.FRAME_DURATION`, the rig's one PSX tick length.
const AnimationPlayback = preload("res://addons/exmateria_sprite_rig/sequence/AnimationPlayback.gd")


# --- the resolution layer ---------------------------------------------------

## Activity → SEQ slot, the ADR-0024 table: `resolve_attack`,
## `resolve_spell_casting`, `resolve_spell_charging`, `resolve_using_item`,
## `resolve_for_activity` and `resolve_idle_low_health`, keyed by sprite type.
## Host use: `src/units/Unit.gd` calls five of the six to pick the BODY/WEP1 slots
## for an action; `tests/CombatVictoryPoseTest.gd` pins the idle/kneel pair and
## `tests/UnitDisplayPaintGoldenTest.gd` the attack pair.
const AnimationResolutionMap = preload("res://addons/exmateria_sprite_rig/layers/AnimationResolutionMap.gd")

## Job/monster palette rows — `job_body_palette_row(job)` and
## `resolve_body_palette_row(slot, sprite_id)`, the colour variant a unit wears.
## THE SIBLING NAMER IS GONE (#1071, ADR-0272). Until then the first citation here
## was `addons/exmateria_catalogue/templates/CharacterTemplateResolver.gd`, a file
## inside another addon, staged as a labelled sibling under ADR-0212 dec. 7 and
## carried as `ARM1_BURN_DOWN`'s last row. It was paid by DELETING the key it
## produced rather than by injecting a port: `resolve()`'s `body_palette_row` was a
## pass-through no consumer read, so the consumers that already hold the `Character`
## now ask this resolver themselves. Every citation below is a host file.
## Host use: `src/units/UnitSpawn.gd` stamps the row at spawn,
## `src/ui3/formation/FormationScene.gd` answers it for the formation body render,
## `src/scenarios/ScenarioPlayerScene.gd` resolves a cutscene slot's row,
## and `src/units/Unit.gd` re-resolves it on a job change;
## `tests/CharacterTemplateResolverTest.gd` (which asserts the resolver does NOT
## answer it) and `tests/CombatBodyPaletteRowTest.gd` assert against it.
const SpritePaletteResolver = preload("res://addons/exmateria_sprite_rig/content/SpritePaletteResolver.gd")


# --- the state layer --------------------------------------------------------

## What a unit is DOING, as far as the rig is concerned — the `Activity` enum
## (IDLE, WALKING, ATTACKING, DYING, …), generated from
## `tools/activity_taxonomy.yaml`.
##
## 🔴 THIS IS AN ENUM AND IT IS THE ADDON'S WIDEST PUBLISH BY USE COUNT: 60
## reaches over 22 host files, every one of them `DisplayActivity.Activity.*`.
## It is NOT a behaviour member and does not count against P1's non-enum floor —
## the same standing `AnimationOpcodes` has. Whether an ACTIVITY is rig
## vocabulary or kernel vocabulary is the question #739/#740 answered for the
## other enums by moving them to `exmateria_schema`; this one did not move, and
## that is recorded rather than settled here (ADR-0217 amendment, #746).
## Host use: `src/gpu/CombatLoop.gd` drives the battle's activity transitions,
## `src/units/Unit.gd` exposes `var activity: DisplayActivity.Activity`, and
## `src/gpu/GPUMovementVisualizer.gd` maps a move timer onto WALKING/JUMPING/LANDING.
const DisplayActivity = preload("res://addons/exmateria_sprite_rig/state/DisplayActivity.gd")

## The facing/pose state machine, and the pure angle conversions that go with it:
## `angle_12bit_to_facing`, `angle_12bit_to_cardinal_bucket`, `get_pose_octant`,
## `pose_octant_to_atlas_cardinal`, `get_camera_variant`, `CAMERA_BASELINE_QUAD`.
## Host use: `src/scenarios/ScenarioVM.gd` picks a cutscene pose and camera variant,
## `src/scenarios/NavigatorMain.gd` converts a deploy facing, `src/units/Unit.gd`
## owns one per unit as `$AnimationStateController`, and
## `tests/GetPoseOctantTest.gd`, `tests/RenderCardinalConverterTest.gd` and
## `tests/UnitOrientationTest.gd` are the fixtures over the conversions.
const AnimationStateController = preload("res://addons/exmateria_sprite_rig/state/AnimationStateController.gd")


# --- the render layer -------------------------------------------------------

## The camera-quadrant watcher — recomputes the PSX camera angle each frame and
## re-poses the sprite when the quadrant flips.
## Host use: `src/units/Unit.gd` holds one as `$CameraRelativeRenderer` and
## `tests/CameraAnglePortTest.gd` builds one to prove it seeds from the port mirror.
const CameraRelativeRenderer = preload("res://addons/exmateria_sprite_rig/render/CameraRelativeRenderer.gd")

## The unit shader/material factory — `shader_for(variant)` and
## `for_variant(variant, base)`, the ADR-0189 opaque/additive/flat trio.
## Host use: `src/scenarios/ScenarioVM.gd` swaps `.shader` mid-fade,
## `src/ui3/formation/FormationScene.gd` mounts the flat variant on the roster
## material, and `tests/UnitMaterialVariantTest.gd` is the variant contract.
const UnitMaterial = preload("res://addons/exmateria_sprite_rig/render/UnitMaterial.gd")


# --- the crystal + editor helpers -------------------------------------------

## The crystal billboard a dead unit leaves behind — an 8-frame forward loop on
## its own Node3D.
## Host use: `src/units/Unit.gd` spawns one on SS=1 and
## `tests/ScenarioInflictStatusTest.gd` asserts the child is one and is freed on reset.
const CrystalSprite3D = preload("res://addons/exmateria_sprite_rig/crystal/CrystalSprite3D.gd")

## Editor-side resource watcher — re-imports the rig's `.tres` tables when they
## change on disk, so an authoring session does not restart.
## Host use: `src/scenes/UnitAnimationViewerScene.gd` constructs one for the
## animation viewer.
const ResourceHotReload = preload("res://addons/exmateria_sprite_rig/resources/ResourceHotReload.gd")

## The hand-authored wiki labels for SEQ slots, keyed by sprite type — the
## viewer's readout and any future atlas-aware tooling. It was
## a file under `src/data/` until #809: `viewer/SequenceViewer.gd` named it
## from inside this addon, which is two of ARM7_BURN_DOWN's six lines and goal #5
## unmet on the TYPE axis. Moving the class alone would NOT have paid it — the
## class carried the host address `assets/sprites/animation_names.json` with it
## have landed on arm 6 on arrival — so the address moved too, onto
## `SpriteRigContentRoot.ANIMATION_NAMES_SUBPATH` (ADR-0202's host-injected
## content root). Host use: `src/debug/UnitAnimationViewerPanel.gd` aliases it
## for the three slot readouts in the F3 overlay.
const AnimationNames = preload("res://addons/exmateria_sprite_rig/sequence/AnimationNames.gd")
