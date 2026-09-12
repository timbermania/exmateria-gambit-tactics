class_name ScenarioVM
extends Node

## Emitted when the MAIN context (`_contexts[0]`) reaches its Event End
## (`{DB}`/`{E3}`) — the scenario chunk finished. The runtime navigator yields on
## this to advance the story walk (live-boot #1, decision #179): a scenario group's
## terminal member reaching Event End is what "group finished" means. Child block
## coroutines terminating do NOT fire it. Payload is `current_scenario_id`.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const UnitMaterial = ExMateriaSpriteRig.UnitMaterial
const SpriteLayerManager = ExMateriaSpriteRig.SpriteLayerManager
const AnimationStateController = ExMateriaSpriteRig.AnimationStateController
const DisplayActivity = ExMateriaSpriteRig.DisplayActivity

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const EventPathfinder = ExMateriaBattlefield.EventPathfinder
const RomTerrain = ExMateriaBattlefield.RomTerrain
const Lattice = ExMateriaBattlefield.Lattice

## ADR-0212 dec. 1 — one alias line per file keeps the use sites spelled as they were.
const TerrainCell = ExMateriaSchema.TerrainCell
## And the same for `addons/exmateria_platform`, which shed `DisplayPort` — the
## name of a hardware standard — under ADR-0212 dec. 1.
const PsxNum = ExMateriaPlatform.PsxNum

## And the same for `addons/exmateria_schema`, whose six generic-English globals
## collapsed onto one façade in the same pass (ADR-0212 dec. 1).
const ColorRecipe = ExMateriaSchema.ColorRecipe
const ColorStack = ExMateriaSchema.ColorStack

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const SpriteLayer = ExMateriaSchema.SpriteLayer.Kind
const ClockOwner = ExMateriaSchema.ClockOwner.Kind
const UnitMaterialVariant = ExMateriaSchema.UnitMaterialVariant.Kind

signal group_finished(last_scenario_id: int)

## Thin event-script VM for replaying FFT scenarios in Godot.
##
## Tracer-bullet scope (handoff `/tmp/handoff_tracer_bullet_scenario_1.md`):
## walk the JSON-decoded scenario chunk, dispatch opcodes by string name,
## halt at the first unhandled opcode. Tick clock at fixed 60 Hz mirrors
## PSX cadence; `Wait T=N` blocks N ticks; `Wait For Instruction` is a
## stub-skip for now.
##
## Pre-bake input via `tools/disasm_event.py --json` — no GDScript port of
## the disassembler needed.

const _TICK_HZ := 60.0
## Seconds per VM tick — the fixed step motion/camera/anim advance by inside
## `_advance_tick_visuals` (ADR-0065). One console vblank; NOT host render-delta.
const _TICK_DT := 1.0 / _TICK_HZ
# FFT {28} Walk To drives the unit's *movement* walk animation, which the ROM
# selects as anim_id 15 (0x0F) → SEQ sequence 28 (front) / 29 (back) via the
# `(anim_id-1)*2 + front/back` rule (matches Godot's `_arm_anim_id_clock`).
# Verified live on PSX (pcsx-agent): Ovelia's idx-201 Walk To holds
# unit+0x1DC (SEQ key) = 29 the whole walk, SHP frame (+0x1E0) ping-ponging
# 14-18 — byte-exact to `type3_seq.json["29"]`. This is the "slow"-cadence walk
# (waits 8,8,8,4), NOT the combat-resolver's seq 8/9 ("fast", waits 2,4,6,4)
# that `anim_state=WALKING` used to pick. See
# research/working_documents/scenario_1_captures/HANDOFF_walk_to_animation.md.
const FFT_WALK_ANIM_ID := 15

## When true, unhandled opcodes log + advance instead of halting the VM, and
## boxed dialogs auto-advance after a dwell instead of blocking on input.
## `Display Message` / `Change Dialog` keep their real handlers — Dialog=0x09
## (overlay, e.g. the chapel prayer) and the boxed `0x1X/0x9X` variants render
## normally; the advance gate (`Wait For Instruction Task=1`) auto-advances so
## the whole camera choreography can be watched without blocking on input.
## Used by the VM debug panel's "Play-through" toggle.
var play_through_skip_unknown: bool = false:
	set(value):
		var was := play_through_skip_unknown
		play_through_skip_unknown = value
		# Flipping the toggle ON after a halt must resume the VM: an unhandled
		# opcode halts by setting `_running = false`, so without re-arming here
		# the "Play-through" checkbox does nothing once the VM has already
		# stopped (it only helped if enabled BEFORE the first halt). Re-arm only
		# on a genuine OFF->ON edge so the internal fast-play save/restore
		# (`_begin_fast_play` / `_finish_fast_play`) doesn't fight `paused`.
		if value and not was:
			_running = true

## In play-through mode, cap Wait + Camera lerp durations so absurd Time
## values from later in scenario 1 (29914+ ticks = 8 minutes each) don't
## stall the orientation watch. 60 ticks @ 60 Hz = 1 s max per opcode.
var play_through_max_ticks: int = 60

## Map of unit_id (int) -> Unit node. Populated by the scene before start().
var units_by_id: Dictionary = {}

## Extra units whose idle body clock rides the ONE 60 Hz VM tick (ADR-0065) but which are
## addressable by NOTHING else — not `resolve_unit_set`, not team broadcasts, not the {43}
## dead-unit fade, not reset/teardown, not the frame-0 visibility gate. `_advance_scenario_anim`
## `advance_frame()`s each of these every tick, in lockstep with `units_by_id`, so a unit can
## march-in-place at the true event cadence WITHOUT becoming an event-addressable unit. The
## navigator registers its deployed owned generics here at the pre-battle pause (no scn-12
## opcode names them); it owns the list's lifecycle (populate + clear) — the VM only pumps it.
var idle_only_units: Array = []

## Command-mode Pause survey freeze (ADR-0083, narrowed from the old `battle_frozen`). Halts the
## SCENARIO-owned body pump (both `units_by_id` and `idle_only_units`) so a paused battlefield is a
## true freeze-frame including ambient scenario NPCs — COMBAT-owned bodies are already frozen by
## `CombatLoop.combat_active = false`. This is now ONLY the Pause freeze-frame: the VM/CombatLoop
## double-pump is handled structurally by per-unit `clock_owner` (the VM pump skips COMBAT-owned
## always), NOT by this flag. DISTINCT from `paused` (which gates camera + motion but lets a scenario
## PARK breathe). Owned by `NavigatorMain` (set on Live→Paused, cleared on Paused→Live / Deployment);
## defaults false so cutscene playback is untouched.
var survey_frozen: bool = false

## PlayerCamera reference (for Camera + Reveal handlers).
var player_camera: Node = null

## The scenario-camera director — owns the cinematic-camera state + apply
## (Camera / Camera Fusion opcodes, calibration knobs, lerp, fusion-chain
## spline). Created in `_ready`; the interpreter delegates to it.
var camera_director: ScenarioCameraDirector = null

## The dialogue box pool — owns boxed-dialog RENDERING (slots, placement,
## persist bit, message-token index, anchor gizmos). The advance GATE stays
## VM scheduler state (Option A); the VM's gate logic calls down into this.
var box_pool: ScenarioDialogueBoxPool = null

## The injected world facade the apply layer mutates (ADR-0058). Wraps this VM's
## live scene refs; [ScenarioApply] `apply_X(intent, _world)` calls its verbs so an
## apply is testable against a [FakeScenarioWorld]. Grown family-by-family as
## behavioral opcodes migrate off the inline `_op_*` bodies. Created in `_ready`.
var _world: ScenarioWorld = null

## MapComposer ref (for Warp Unit -> place_on_tile).
##
## ⚠️ STAYS UNTYPED, AND THAT IS ADR-0170 dec. 3's NAMED REMAINING DEBT. The lattice
## port covers 10 of the ~24 members this VM reaches through this handle; what
## survives is a field-effects + animation seam (`play_texture_animation`,
## `commit_field_tint`, `set_field_color_stack`, `change_map`, `rebuild_map`,
## `is_animation_active`) with five reflection guards of its own. Pulling that in
## would re-open what `Battlefield` publishes, which ADR-0170 dec. 1 settled; leaving
## it unnamed is how it stays invisible for another three passes. Terrain queries go
## through `_lattice()` below and are typed.
var map_composer: Node = null


## The map's lattice, or null before the map builds one.
##
## The ONE untyped step ADR-0192 dec. 3 permits at the seam: `map_composer` is
## `$ProceduralMap`, which infers `Node`, and criterion 1 forbids publishing
## `MapComposer`, so this handle can never carry a type. Everything downstream of
## this line is `Lattice`-typed, which is what makes the register's arm 1 decidable.
func _lattice() -> Lattice:
	if map_composer == null or not ("lattice" in map_composer):
		return null
	var lat: Lattice = map_composer.lattice
	return lat

## Host callback that instantiates a runtime "ghost" actor for {47} Add Ghost Unit
## (ADD_GHOST_UNIT_OPCODE_47.md §6). A ghost has no ENTD roster record, so unlike
## normal units it is NOT pre-spawned by `ScenarioPlayerScene._spawn_units` — it must
## be created on the fly. The host (ScenarioPlayerScene) registers this after `_ready`;
## null in VM-only tests (the apply seam uses a [FakeScenarioWorld] instead). Signature:
## `fn(control_id:int, sprite_set:int, psx_x:int, psx_y:int, elevation:int,
## facing_12bit:int, visible:bool) -> Node` — returns the spawned Unit (already added
## to `units_by_id[control_id]`), or null on failure.
var ghost_spawn_fn: Callable = Callable()

## Map depth in tiles (PSX `size_z`), set by the host scene from the loaded
## map's `terrain.json`. In-chunk unit depth rows arrive PRE-FLIPPED from the
## parser now (ADR-0057 — the scenario chunk is Godot-native, extract_event
## bakes the ADR-0052 mirror), so this no longer flips unit placement; it is
## kept because ScenarioCameraDirector still mirrors the continuous camera-body
## depth against it (PsxNum.flip_depth_continuous).
var map_size_z: int = 0

## Map width in tiles (PSX `size_x`), set by the host scene. Used by {3C} Weather
## to size the rain scatter box to the map footprint. 0 = unset (Weather falls
## back to its own default footprint).
var map_size_x: int = 0

## {3C} Weather — the live rain particle system (lazily created on the first
## Weather opcode, parented into the scene so the game camera transforms it).
var _weather: ScenarioWeather = null

## {76} Dark Screen — the pre-battle "Conditions for Winning" diamond-mosaic
## overlay (lazily created on the first Dark Screen opcode). A foreground
## fullscreen quad+shader; ticked outside the halt gate. The kind-54 ({E5})
## barrier holds while it settles. Torn down by {77} Remove Dark Screen.
var _dark_screen: ScenarioDarkScreen = null

## {3E} Color Screen — the full-screen colour ramp that fades the whole frame from
## a start RGB to an end RGB over Time frames with a PSX ABR blend (Mode). Lazily
## created on the first Color Screen opcode; a foreground fullscreen quad+shader
## ticked outside the halt gate. The kind-0x0C ({E5} Task=12) barrier holds while
## the ramp is in flight; releases when it lands on `end`.
## RE: research/working_documents/COLOR_SCREEN_OPCODE_3E.md.
var _color_screen: ScenarioColorScreen = null

## {7D} Show Graphic — the fullscreen event graphic (chapter title card, ending
## still, GAME OVER, or a WLDBK world background) that fades in, holds, then fades
## out (lazily created on the first Show Graphic opcode). A foreground fullscreen
## quad+shader ticked outside the halt gate; the kind-61 ({E5} Task=61=0x3D)
## barrier holds while it's still on screen. Self-clears once fully faded out.
var _show_graphic: ScenarioShowGraphic = null

## {78} Display Conditions — the battle-intro victory-condition banner + `READY!`,
## and the whole outro pipeline (the victory text, BONUS MONEY + the gil reel, and
## the three screens that find nothing to draw). Lazily created on the first {78}.
## A screen-space prim list ticked outside the halt gate; the kind-56 ({E5}
## Task=56=0x38) barrier holds while a screen is still on its own clock.
var _results_screen: ScenarioResultsScreen = null

## {91} Show Map Title — the pre-battle location-name strip (e.g. "Military
## Academy's Auditorium") that reveals with a L->R wipe, holds, then ERASES with
## a second L->R wipe (lazily created on the first Show Map Title opcode). Ticked
## outside the halt gate like {7D}; the {91} handler BLOCKS the main VM context on
## this until it erases (the PSX built-in FUN_8014c9d0 wait, NOT a following {E5}).
## show_map_title_op91_decode.md.
var _map_title: ScenarioMapTitle = null

## The current battle map_id, set by the host scene from the scenario group
## (ScenarioGroupDatabase). Used to resolve the context-selected MAPTITLE slot
## for {91} (the runtime index derivation is an ATTACK.OUT GAP-3.1); -1 = unknown.
var current_map_id: int = -1

## The scenario id of the chunk currently loaded/playing, set by the host scene
## when it loads a member (mirrors `current_map_id`). Carried as the payload of
## [signal group_finished] so the navigator knows which member just ended. -1 =
## unset (standalone boots that never set it still fire the signal with -1).
var current_scenario_id: int = -1

## {22} Switch Track — the scenario's two music slots (ATTACK.OUT
## `music_file_one_id` / `music_file_two_id`), set by the host scene. The wiki
## ("toggle between the first and second song assigned in ATTACK.OUT") + the
## decompiler agree: `{22}` ignores its track byte's *value* and instead
## alternates a toggle, selecting slot = toggle+1 (1 → song one, 2 → song two).
## music one plays at scenario load (toggle 0), so the FIRST `{22}` flips to
## song two. A slot id of 0 = unloaded → that switch is a no-op (per-slot arm
## gate, decomp `0x801438f8 beq sVar1,0`). See
## research/working_documents/HANDOFF_switch_track_opcode.md.
var music_slot_one_id: int = 0
var music_slot_two_id: int = 0
var _track_toggle: int = 0

# The in-chunk unit depth-row flip (`Warp Unit` / `Walk To` event-Y) used to live
# here as a runtime consume-boundary mirror. It moved HOME to the parser
# (extract_event._flip_placement_rows, ADR-0057): the chunk now arrives
# Godot-native, so the placement opcodes consume Event-Y raw. The map mesh, ENTD
# spawns, terrain, and now the scenario chunk are all pre-flipped at parse time —
# no Placement stays flipped at runtime. (The raw byte-faithful chunk lives in the
# .raw.json sidecar as RE-diff data; live PSX RAM is the real diff oracle.)

## Fade overlay (CanvasLayer/ColorRect) for Reveal.
var fade_rect: ColorRect = null

## DialogueOverlay (CanvasLayer) for `0x10 Display Message` (Dialog=0x09
## overlay mode — the chapel prayer at PC=42). Boxed dialog variants
## (Dialog=0x11/0x12/0x91/0x92) are out of scope here; see Phase 5 of
## `research/working_documents/scenario_1_captures/display_message_overlay_decode.md`.
## Optional: when null, the overlay handler degrades to skip-with-log
## behavior so VM-only unit tests don't need a CanvasLayer.
var dialogue_overlay: Node = null


## Auto-advance boxed dialogs after a fixed dwell instead of blocking on the
## Cross/confirm key. Forced on in `play_through_skip_unknown` / chapel-trace
## so automated runs don't deadlock; the live ScenarioPlayer leaves it false
## so the player drives the pace (Decision 4 in the boxed-dialog doc).
var dialog_auto_advance: bool = false
## Dwell (in 60 Hz ticks) before an auto-advance fires once the box is shown.
var dialog_auto_advance_ticks: int = 45

# Boxed-dialog advance gate. `_pending_dialog_gate` is armed by a boxed Display
# Message / Change-Dialog-swap and consumed by the next `Wait For Instruction
# Task=1` (the ROM's advance gate). While `_dialog_gate_active`, the FOREGROUND
# box (slot `box_pool._foreground_slot`) is awaiting advance and its owning context is
# parked (the box keeps typing via its own clock) until the player presses
# advance, or the auto-advance dwell expires. Exactly one foreground box awaits
# at a time (PSX: exactly one kind-1 slot), so a single gate models it.
var _pending_dialog_gate: bool = false
var _dialog_gate_active: bool = false
var _dialog_dwell_ticks: int = 0
# The context that raised the active dialog gate. Only THIS context is held
# while a box waits to advance — parallel block coroutines keep draining so a
# unit's staged entry (Sprite Move → Walk To) finishes while the box is shown,
# instead of freezing mid-walk and dispatching its Walk To *after* a later
# cinematic Unit Anim (the chapel "Ramza kneels then slides into his seat" bug).
var _dialog_gate_ctx = null  # ScriptContext or null

## The active EVTFACE row-block selected by the last {0x50} Portrait Row opcode
## (-1 = no {50} seen this scene => dialogue boxes use the in-battle unit-SPR
## portrait path). {10}/{51}'s Portrait byte supplies the COLUMN into this row.
## PORTRAIT_ROW_OPCODE_50_EVTFACE.md §2.1/§5.1.
var _portrait_row: int = -1

## FFT's game-variable store — the SAME array the world map reads (ADR-0179). Backs the
## `0xB0`–`0xBE` writers (`Add`/`Zero`/…) and the `0x7E Wait Value` reader.
##
## [b]One array, not one per subsystem.[/b] The ROM keeps it at `0x8005771C`, in SCUS BSS
## *below* `0x80067000`, so it survives the `BATTLE.BIN` overlay load — that placement is
## what lets a scenario's own `Zero(110); Add(110, k)` advance the world map's story
## counter. `research/wiki_articles/event_instruction_b0_be_variable_math.md` §1 puts the
## event variable file's base at `*0x80165F9C` = `0x8005771C`; `WORLD_MAP_SCREEN.md` §27.4
## puts the map's store at `*(0x80153280)` = the same word. They are one thing.
##
## An unowned VM (unit tests, a bare construct) makes its own and behaves exactly as before.
## The navigator injects `Campaign`'s via [method set_variable_store], and then a scenario's
## writes are campaign state. [WorldMapVariables] also models the BIT and NIBBLE regions the
## old per-VM Dictionary did not — scenario 14 writes var 445, 963–965 and 1008, all of
## which were being silently dropped.
##
## [b]Not cleared on (re)start.[/b] The ROM never clears it, and `Zero(v); Add(v, k)` IS the
## reset — the idiom exists because the event compiler has no SET opcode. Clearing broke the
## cross-member idiom (var 41 is zeroed in a SIBLING member) and would corrupt genuine
## accumulators (var 101 is Deep Dungeon depth). Measured: 85 of 1,411 reads/RMWs across the
## 250 decoded chunks are not preceded by a `Zero` of the same id, on four ids, and three of
## the four argue FOR persistence. var 87, the prayer-scene frame counter, is re-zeroed by
## its own `Zero(87)` at pc 319 before every use.
var vars_store: WorldMapVariables = WorldMapVariables.new()

var _insts: Array = []

## Cooperative-coroutine model (PSX 16-slot scheduler, FUN_8014ca80) — each
## live "thread" of execution is a ScriptContext. `_contexts[0]` is the main
## scenario VM (slot 1 on PSX); `Block Start` (`0x2A`) appends a child context
## whose PC starts at the byte after the opcode, while the main context skips
## past the matching Block End — per BLOCK_EXECUTION_INVESTIGATION.md the
## dynamic capture (vsync=409 chapel) confirms blocks enter the SAME tick the
## main thread fires Block Start, with no barrier at Block End. `_current_ctx`
## mirrors PSX's `DAT_80174038` slot index — set before each handler dispatch
## so handlers that arm a wait write to the CALLING context's wait_ticks.
var _contexts: Array = []
var _current_ctx: ScriptContext = null

var _running: bool = false
var _tick_accumulator: float = 0.0

## Monotonic VM tick counter — increments once per processed `_tick_once` (when
## the round-robin actually runs). The clock for `wait_until` watchdog deadlines.
var _vm_tick: int = 0

## Watchdog budget (60 Hz ticks) for a `wait_until` predicate barrier. PSX has no
## watchdog — it trusts the activity consumer to clear the flag — but Godot must
## force-release a never-clearing predicate so a stuck activity (e.g. a unit that
## despawned mid-rotate) can't deadlock the whole VM. 600 ticks = 10 s, far above
## any real rotation/walk/slide (worst case is tens of ticks).
const _WAIT_UNTIL_WATCHDOG_TICKS := 600

## A much larger watchdog for the prayer-overlay typewriter hold — the
## `Wait For Instruction Task=1` (chunk PC 50) that blocks the script on the
## self-timed overlay typewriter finishing. The chapel prayer alone runs
## ~10-12 s (47 glyphs @ ~10 vsync/glyph + a {Delay 3C} ~2 s pause), so the
## default 10 s ceiling would force-release mid-prayer. 1800 ticks = 30 s —
## above any plausible single overlay message, still a deadlock backstop.
const _OVERLAY_TYPEWRITER_WATCHDOG_TICKS := 1800

## Watchdog for the {91} Show Map Title block. The effect runs ~591 frames at
## Speed 1 (reveal 240 + hold 110 + erase 241); the wait carries a progress probe
## (the effect's frame counter) so a normal run never trips it. 900 ticks = 15 s
## is a pure deadlock backstop above the effect's length.
const _MAP_TITLE_WATCHDOG_TICKS := 900

var _reveal_remaining_ticks: int = 0
var _reveal_duration_ticks: int = 0

## {1A} Map Darkness — the prayer-scene "oxide" screen tint, modelled as PSX RAM state
## ONLY (no render surface). Faithful to the applier FUN_80090840 (research/working_
## documents/scenario_1_captures/map_darkness_oxide_decode.md): a per-channel "current"
## byte color integrates toward a target over Time*8 frames. Scenario 1 uses Blend==4
## only (target = baseline + signed(R,G,B)).
##
## The subtractive overlay this once drove (a CanvasLayer ColorRect, BLEND_MODE_SUB) was
## a PROVEN phantom and has been REMOVED (2026-07-11): PSX savestates (scn4 lightning
## pan) hold the accumulator delta (+30) in RAM while the *applied* gradient (0x800a1b18)
## and the map CLUT stay byte-identical, and live pokes in three scenes (scn4, scn6, scn1
## prayer) move ~0 px / +0.05 luma when the oxide is swept. The real map darken is the
## {33} CLUT palette-content fade, not this quad. The accumulator below is still ramped
## because it mirrors the faithful PSX RAM state and gates the darkscreen ({E5} Task=54)
## liveness poll via `_oxide_remaining_ticks`; only the never-visible render was dropped.
## The deeper "why does FUN_80090840 render invisibly in battle" question (once tracked
## as Q2) is a PSX-side RE thread — chased in PCSX/Ghidra, not by re-drawing Godot's
## known-wrong subtract. See MAP_FLASH_SCENARIO4_PERSISTENT_DARK.md §4 (fix option a).
##
## Rest darkness color (byte R,G,B), live-captured at the prayer scene — the baseline
## the accumulator ramps from/to.
const _OXIDE_BASELINE := Vector3(20, 4, 0)
var _oxide_current_byte: Vector3 = _OXIDE_BASELINE
var _oxide_start_byte: Vector3 = _OXIDE_BASELINE
var _oxide_target_byte: Vector3 = _OXIDE_BASELINE
var _oxide_remaining_ticks: int = 0
var _oxide_duration_ticks: int = 0


## {33} Color Field — the Orbonne prayer whole-scene palette-content fade. The
## broadcast sibling of {32} Color Unit: the SAME (scale,bias) affine (see
## ScenarioColorTint) applied to the WHOLE field (every unit sprite's CLUT + the
## map palette) rather than one unit, so it carries Color(mode)/RGB/Time but no
## Units/Multi target (PSX FUN_800933c4 takes the slot >= 0x10 broadcast path).
## Modelled faithfully in palette space — the affine is pushed to each unit's
## `unit_tint_scale`/`unit_tint_bias` shader uniform (composed with any active
## per-unit {32} tint) and to the map via `MapComposer.set_field_tint`
## (indexed_color.gdshader rewrites the sampled palette entry). This mirrors the
## PSX CLUT rewrite per-surface before compositing, NOT a screen-space filter.
## A single `_field_tint` holds the in-flight ramp; it ticks in _tick_once
## outside the VM halt gate (like the oxide/Color-Unit ramps) so a fade set right
## before the prayer dialog wall still completes, and the untint naturally
## follows the text because {33}'s untint op dispatches only after the Display
## Message advances. Not modelling the PSX per-view CLUT split
## (prayer_screen_tint_quad_decode.md §8.5) is deliberate — that split is a
## VRAM-layout artifact, not separate visible colors.
## {6B} BG Sound / {6A} Edit BG Sound — live background-ambient sounds keyed by
## env sound id → ScenarioBgSound. Each holds the audio handle + its linear
## volume ramp; ticked in _tick_once outside the VM halt gate (like the
## reveal/oxide/tint ramps) so a fade set right before a dialog/unhandled-opcode
## wall still converges. Playback + tracked/overlay bookkeeping live in SfxRouter;
## the PSX task is kind 0x35 (registered in the {E5} liveness registry). See
## research/working_documents/BGSOUND_OPCODE_6B_INVESTIGATION.md.
var _bg_sounds: Dictionary = {}

## SfxCatalog (no class_name — path-preloaded) for the env-bank loop flag.
const _SfxCatalog := preload("res://src/audio/SfxCatalog.gd")

var _field_tint: ScenarioColorTint = null
## Shared, never-mutated identity affine — the "own tint" for units that have no
## {32} tint when re-pushing the {33} field broadcast (_apply_field_tint_to_all).
var _identity_tint: ScenarioColorTint = ScenarioColorTint.new()

## {43} Call Function 4 — the battle->scenario-6 dead-unit fade (RE:
## research/working_documents/SCENARIO6_DEAD_UNIT_FADE.md, ROM FUN_80147cf0). A
## per-uid fade phase for each on-field non-persisting-side unit the sweep picked:
##   1 = pass 1 in flight (mode-4 Δ=(-31,-31,0) — kill R,G, keep B),
##   2 = pass 2 in flight (mode-4 Δ=(-31,-31,-31) — collapse to black).
## Advanced in `_advance_dead_unit_fades` (ticked outside the halt gate, right
## after the {32} tint ramps): when a pass's ramp lands, the next pass arms; when
## pass 2 lands, the unit is removed from the field (hidden). Mirrors the ROM's
## 3-state `+0x13e` removal machine (FUN_800870ac). Keyed on the resolved uid.
var _dead_unit_fades: Dictionary = {}   # uid -> phase (1|2)

## Ramp `Time` bytes for the two fade passes (byte-exact ROM args, §5.4): pass 1
## `unit_graphic_palette_revert(...,2,...)` Time=2 (fast 8-frame ramp); pass 2
## per-frame updater fires Time=4. Not calibration knobs — fixed ROM values.
const _DEAD_FADE_PASS1_TIME := 2
const _DEAD_FADE_PASS2_TIME := 4
## The event VM halts 120 frames after the sweep (`event_fiber_yield_n(0x78)`, §3)
## before the staging warps + Ovelia's "Let go of me!" box run. 0x78 = 120.
const _DEAD_FADE_HOLD_TICKS := 120

## {2E} Background — the full-screen gradient quad ramp model (the storm sky +
## lightning flashes). Ticked in _tick_once; pushed to the ScreenBackground quad
## via _apply_screen_background. Null until the first {2E} arms it.
var _background: ScenarioBackground = null

## Field-object / 3D-object textured-animation state, keyed by object ID.
## Mirrors the PSX per-object descriptor model decoded in
## `research/working_documents/scenario_1_captures/use_field_object_decode.md`:
## `{55} Use Field Object` latches a one-shot "play textured-animation #ID on
## the map mesh" request (consumer FUN_80143418 → FUN_800f0be0 cmd 0x83), and
## `{57} Wait Field Object` barriers on the single active slot (PSX flag
## 0x80166070) until the animation finishes. `{54}/{56}` are the 3D-object pair
## (cmd 0x80/0x81, flag 0x8016606e); they don't appear in the chapel scene but
## are registered so the next scenario doesn't halt.
##
## Stage 1 (here): the real map texture-animation isn't rendered yet, so each
## record models a duration in 60 Hz ticks and the {57}/{56} barriers resolve
## when every record drains. PSX ran the chapel field anim ~50 frames
## (descriptor cap 0x7e = 126); 50 keeps the {57} barrier plausibly timed.
## Stage 2 replaces `ticks_left` with `MapComposer.is_animation_active(id)`
## once the Mesh-Resource texture-animation section is parsed.
var _field_objects: Dictionary = {}   # id -> { "ticks_left": int, "arg2": int }
var _threed_objects: Dictionary = {}  # id -> { "ticks_left": int, "state": int }
const _FIELD_OBJ_DEFAULT_TICKS := 50  # modeled fallback when the map can't render

# Stage 2: when the map actually renders the field-object animation, {57} Wait
# Field Object barriers on MapComposer.is_animation_active() instead of the
# modeled tick drain. -1 = no real animation in flight (use the fallback).
var _field_anim_rendered_id: int = -1

## Tracks the EVTCHR slot currently mapped into each cinematic RAM block,
## set by the event-script `0x58 Load EVTCHR` opcode handler. Keys are the
## Block parameter as authored in the chunk; values are the Slot parameter
## (an EVTCHR-segment selector — exact slot→segment indirection still TBD,
## see followup #1 in `research/working_documents/scenario_1_captures/
## cinematic_seq_source_decode.md`). Cinematic Unit Anim (anim_id 0x1F4+)
## consumers read this to choose which `cinematic_seq.json` entry to play.
var _evtchr_block_to_slot: Dictionary = {}

## The block id of the most-recent `Load EVTCHR`. This is the cinematic EVTCHR
## FALLBACK, not the active context: PSX keeps TWO pages resident at once and the
## anim band picks between them, so `_resolve_cinematic_block` reads this only
## when the band's own block was never loaded. It used to be the page for every
## unit — that is the root-28 wrong-sprite bug (three units painted from one
## atlas), and the "the anim band does NOT encode a block" claim that justified it
## is false; see `EVTCHR_CHARACTER_ATTRIBUTION.md` § "The band selects the PAGE".
## Defaults to `2` so the Orbonne chapel — which issues its real `Load EVTCHR` in
## the un-extracted "Setup" scenario 1, leaving `_evtchr_block_to_slot` empty here
## — keeps its historical block-2 → seg-0 behaviour. Scenario 6 sets this to 0 via
## `Load EVTCHR {Block:0, Slot:1}`.
## See `research/working_documents/SCENARIO6_CARRY_POSE_EVTCHR_RENDER.md`.
var _active_evtchr_block: int = 2

## Cinematic render tunables (issue #124). Palette is driven by each unit's
## `body_palette_row` uniform (V14, 2026-06-27 — set at spawn from the ENTD
## slot's `palette` byte, same field combat uses per ADR-0022); no per-VM
## resolver. `cinematic_segment_override` forces a specific segment id when
## ≥ 0; -1 means defer to the resolver (which itself currently hardcodes 0).
## `cinematic_frame_override` forces a specific frame byte (0xD2..0xF9)
## instead of the first LoadFrameWait pulled from the bytecode; -1 means
## use the bytecode-derived frame. Both are exposed to the F3 debug panel
## for live experimentation.
# The two overrides are `scenario.*` Tune tunables (ADR-0068). Each DEFAULT is a static var
# (materializable, R1 — not a const, not a bind_update-forwarded property) + a HINT const; bound
# in register_tunables() so ScenarioCinematicDebugPanel reads both back as a pure view. -1 = auto.
const CINEMATIC_SEGMENT_OVERRIDE_SLUG := "scenario.cinematic_segment_override"
static var CINEMATIC_SEGMENT_OVERRIDE_DEFAULT := -1
const CINEMATIC_SEGMENT_OVERRIDE_HINT := {"min": -1, "max": 136, "step": 1}
const CINEMATIC_FRAME_OVERRIDE_SLUG := "scenario.cinematic_frame_override"
static var CINEMATIC_FRAME_OVERRIDE_DEFAULT := -1
const CINEMATIC_FRAME_OVERRIDE_HINT := {"min": -1, "max": 249, "step": 1}
var cinematic_segment_override: int = CINEMATIC_SEGMENT_OVERRIDE_DEFAULT
var cinematic_frame_override: int = CINEMATIC_FRAME_OVERRIDE_DEFAULT

# Replay state for the "Re-apply cinematic" debug button — fires the most
# recent cinematic Unit Anim with the current tunables.
var _last_cinematic_unit_uid: int = -1
var _last_cinematic_block: int = -1
var _last_cinematic_local_idx: int = -1
var _last_cinematic_anim_id: int = -1

## Event movement pathfinder (port of ROM FUN_8017813c), used by {28} Walk To and
## any future event opcode that moves an actor across the map. Stateless — reused.
var _event_pathfinder := EventPathfinder.new()
## One warning per VM for a map with no `terrain.json` — see `_plan_walk_route`.
## A cutscene issues thirty `{28}`s and thirty identical warnings is a log nobody
## reads.
var _warned_lattice_terrain: bool = false

## The home of everything one unit's cutscene owns — a [ScenarioActor] per resolved
## uid (ADR-0064). Five formerly-loose per-unit dicts — `_unit_tints`, `motions`,
## `_cinematic_walkers`, `cinematic_unit_atlas_y_offset` (uid-keyed) and
## `_unit_move_home` (iid-keyed) — collapse into this single registry, each a field
## on the actor:
##   * `tint` ([ScenarioColorTint]) — {0x32} Color Unit palette ramp; ticked in
##     `_tick_once` outside the halt gate, pushed to the unit shader.
##   * `motion` ([ScenarioMotion]) — Sprite Move ({3B}/{6E}) + Walk To ({28}),
##     one straight-line lerp holding no node ref (ADR-0055); advanced per host
##     frame in `_advance_motions`, awaited via `motion_done(uid)`.
##   * `walker` (`CinematicWalkState`) — in-flight cinematic EVTCHR anim.
##   * `atlas_y` — signed px offset (PSX `unit+0x7a`) for cinematic frame render.
##   * `home` — Sprite-Move base anchor (PSX `+0x40`, the `+0x60` offset datum),
##     captured on first move, iid-guarded so a rebound node re-captures.
## `actor(uid)`/`peek_actor(uid)`/`forget`/`reset_all` are its whole
## lifecycle. Single-keyed on the resolved uid (matching `units_by_id`); node
## identity lives on each actor's `owner_iid` guard, never as a second key.
var actors: Dictionary = {}

## Uids whose {11} pending-anim latch was CONSUMED (painted) this accumulator
## tick — the transient half of the §8g consume-before-advance ordering. Cleared
## at the TOP of each `_advance_frame` accumulator iteration, repopulated by
## `_consume_pending_body_anims`. A marked uid is skipped for that one tick by
## BOTH `_advance_scenario_anim` (so a freshly painted SEQ pose holds frame 0
## instead of advancing to 1 — the PSX consumer paints, it does not advance) and
## `_tick_cinematic_walkers` (so a walker spawned by the consume this tick isn't
## double-advanced by that same tick's dispatch phase). Set-like: `{uid: true}`.
var _painted_this_tick: Dictionary = {}

# uid -> true for units that {44} Draw Unit revealed during THIS tick's dispatch.
# Drained by `_paint_revealed_unit_anims` at the end of the tick, before the frame
# is drawn; cleared every tick.
var _revealed_this_tick: Dictionary = {}

## Chapel-cinematic opcode trace. When `DebugConfig.chapel_trace_enabled`,
## `start()` opens a JSONL writer that appends one row per dispatched opcode
## with the post-state of every spawned unit (visibility, facing
## cardinal + 12-bit, type1 anim_id/frame, last painted frame, cinematic
## walker state). Pair with `research/lua_scripts/probe_chapel_opcodes.lua`
## on the PCSX side to diff PSX vs Godot opcode-by-opcode. Default output
## path: research/working_documents/chapel_opcode_trace/godot_run.jsonl.
var _chapel_trace_file: FileAccess = null
var _chapel_trace_rows: int = 0


# Debug-panel surface — read-only externally; flipped by the panel's pause/step
# buttons. `paused` halts opcode dispatch (camera lerp + reveal still tick so
# in-flight transitions complete). Stepping is driven by `step(n)`, which arms
# the same high-speed fast-play as a rewind — it advances the main context `n`
# opcodes through the REAL pipeline (motion plays out, fast) and re-pauses,
# instead of snapping each opcode to its endpoint. Step 1 / Step 10 / Step 100
# buttons just call `step()` with different counts.
#
# ⚠ `paused` ALSO stops the 60 Hz tick, and unit animation clocks are
# tick-driven — so pausing FREEZES every unit mid-animation. Do NOT set
# `paused = true` to "hold a beat" for capture/inspection expecting animation to
# keep playing: you'll grab a mid-pose frame (a unit caught mid-fall, etc.) and
# misread it. To hold a beat with animation LIVE, leave `paused = false` and rely
# on the dialogue gate (`dialog_auto_advance = false` + an open box) — exactly
# what the debug panel's double-click-PC rewind does. See
# `tools/capture_scenario_beat.gd` for the blessed capture pattern. The setter
# warns (once) when an external caller pauses, to catch this trap; internal
# step/rewind writes use the `_paused` backing field to stay silent.
var _paused: bool = false
var _paused_warned: bool = false
var paused: bool:
	get:
		return _paused
	set(value):
		if value and not _paused and not _paused_warned:
			_paused_warned = true
			push_warning(
				"[ScenarioVM] paused=true is a FREEZE-FRAME: it halts opcode "
				+ "dispatch, cinematic walkers, in-flight Sprite-Move/Walk slides, "
				+ "and the camera lerp (per-unit body anim clocks still advance via "
				+ "`_advance_scenario_anim`, ungated). Use it to hold a clean "
				+ "pre-execution beat at `get_pc()`. "
				+ "To hold a beat with slides/camera STILL playing, don't pause — hold "
				+ "via the dialogue gate (dialog_auto_advance=false + open box), like "
				+ "the debug panel's double-click-PC. See tools/capture_scenario_beat.gd.")
		_paused = value

## Debug event-toggle set (F3 Scenario VM panel). Keys are PC indices into `_insts`
## the user has switched OFF; a disabled PC is skipped in `_drain_context` exactly
## like a clean no-op — PC advances, no handler fires — so a scenario can be A/B'd
## with any event removed. Applies to whichever context reaches the PC. Pushed in
## by the panel (via `rebind` → `_push_panel_values_into_vm`), so a rewind replay
## honours the same disabled set. Empty = every event runs. The [ScenarioPathApplier]
## holds this aside for intermediate members so target-member PCs don't bleed across.
var disabled_pcs: Dictionary = {}

# High-speed rewind playback ("scrub to PC"). Instead of snapping every opcode
# to its endpoint, `set_rewind_target` resets to scene start and replays the
# script through the NORMAL `_process` pipeline with `delta` scaled up by
# `rewind_speed`, halting the main context exactly at `_ff_target_pc` and then
# pausing. The trajectory is identical to a real playthrough — every per-tick
# and per-frame transition still fires, in order — just fast. Armed by
# `set_rewind_target`; driven + finalized in `_process` / `_finish_rewind`.
var rewind_speed: float = 30.0
var _ff_active: bool = false
var _ff_target_pc: int = 0
var _ff_prior_skip: bool = false
var _ff_frames_left: int = 0
## Set when a `step` RESUMES from a park (see `step`): the parked frame already
## advanced the render clock on the tick the main context became dispatchable, so
## the first resumed tick dispatches WITHOUT charging a fresh visual advance —
## reusing that frame the way a continuous fast-play folds a whole non-blocking run
## (plus the barrier release before it) onto one tick. Consumed on the first tick.
var _ff_skip_first_visual: bool = false
## Safety cap (real host frames) so an unexpected deadlock during a rewind
## replay can't spin forever — finalize + pause if we blow past it.
const _REWIND_MAX_FRAMES := 1800
## Per-frame cap on the scaled replay delta (seconds). Bounds the work a single
## host frame can do (≤30 VM ticks @ 60 Hz) so a post-reload frame-time spike
## can't run thousands of ticks at once, and keeps the scrub visibly smooth.
const _REWIND_MAX_FRAME_DELTA := 0.5

# Public getters for the debug panel. PC/wait_ticks report the MAIN context's
# state — the debug panel's step/rewind buttons and trace tooling all reason
# about the main scenario thread, not the parallel block coroutines.
func get_pc() -> int: return _contexts[0].pc if not _contexts.is_empty() else 0
func get_instructions() -> Array: return _insts
func is_running() -> bool: return _running


## Is the `{76}` dim fully established and no longer sweeping — i.e. is the frame a settled
## black plate with nothing but `{78}`'s banner on it?
##
## THIS IS A COVER QUESTION, and the one host that asks it is the navigator. The battle intro
## holds a fully dark screen for seconds while the victory-condition banner is up, and that is
## the only stretch of the story→battle handoff in which an expensive, frame-blocking build
## costs the player nothing to look at: a hitch anywhere else in the window lands on ten
## idle-breathing sprites and reads as a hold-and-snap
## (`NavigatorMain._prewarm_battle_under_the_dark`).
##
## Deliberately NOT `progress() >= 1.0` alone. `progress()` reports 1.0 from the frame the
## grow-in completes, but the RETRACT reports a falling 1.0→0.0 through that same accessor, so
## its first frame still reads 1.0 while the plate is already lifting. `is_sweeping()` is what
## separates "settled black" from "on its way somewhere".
func screen_is_fully_dark() -> bool:
	if _dark_screen == null or not is_instance_valid(_dark_screen):
		return false
	return not _dark_screen.is_sweeping() and _dark_screen.progress() >= 1.0
## True while a high-speed fast-play (rewind / step) is in flight. Used by the
## [ScenarioPathApplier] to await an intermediate member's fast-forward to end.
func is_fast_playing() -> bool: return _ff_active
## Has the MAIN script context run its `Event End`? That — not the PC reaching the last
## byte of the chunk — is what "the scenario finished" means here: `_op_event_end` kills
## the context and emits `group_finished`, which is exactly what the normal-speed walk
## yields on. The two usually coincide, and in one of the 72 battle openers they do not:
## scn 47 ends `{E3} Event End 2` at pc 131 followed by a `{DB} Event End` at 132 that is
## therefore never dispatched, so a fast-play watching only the PC sat on 132 for its full
## stall budget after the scenario had, in fact, finished (ADR-0264's opener sweep).
func is_main_context_finished() -> bool:
	return _contexts.is_empty() or not _contexts[0].alive
## Abort an in-flight fast-play immediately (pausing at the current PC), restoring
## the pre-run halt policy. Used by [ScenarioPathApplier] when an intermediate
## member stalls on the combat barrier that a path deliberately never fights.
func cancel_fast_play() -> void:
	if _ff_active:
		_finish_fast_play()
func get_wait_ticks() -> int: return _contexts[0].wait_ticks if not _contexts.is_empty() else 0
# Snapshot the live contexts (for debug panels). Returns a list of {label, pc,
# wait_ticks, alive} — does NOT expose the live objects (avoid mutation).
func get_contexts_snapshot() -> Array:
	var out: Array = []
	for ctx in _contexts:
		out.append({
			"label": ctx.label, "pc": ctx.pc,
			"wait_ticks": ctx.wait_ticks, "alive": ctx.alive,
		})
	return out

# --- Camera-opcode conversion (verified against ROM live RAM 2026-06-23) ---
#
# Position: opcode (X, Z, Y) is FFT cinematic screen-space convention
# (X=lateral, Y=depth, Z=vertical). ROM stores work_position_int_xyz =
# (opcode_X/4, opcode_Z/4, opcode_Y/4) — i.e., the opcode encodes "PSX
# world units × 4" and the handler does a ×4 down-shift on each axis,
# plus an axis remap (opcode Y → world Z; opcode Z → world Y).
#
# To get Godot tile units (1 unit = 1 tile, FFT 28 PSX units per tile)
# with Godot Y-up (FFT Y-down), the full conversion is:
#   godot_x =  opcode_X / 4 / 28 =  opcode_X / 112
#   godot_y = -opcode_Z / 4 / 28 = -opcode_Z / 112   (Y-down → Y-up)
#   godot_z =  opcode_Y / 4 / 28 =  opcode_Y / 112
#
# Zoom: ROM's sprite_scale=4096 means 1.0x. `ExMateriaPlatform.CameraCalibration`
# handles the scale → ortho-size conversion; the calibration knob below controls
# what "1.0x ortho size" means in Godot Display space. (It said `PSXCameraConvert`
# until #1220 — which was the right address only because that file DELEGATED here.
# It now holds the sign axis and nothing else, and the mapping lives where its
# `GODOT_CAMERA_SIZE` calibration does.)

const SCENARIO_POSITION_DIVISOR := 112.0

## Sprite Move ({3B}/{6E}) delta divisor: opcode position-units per Godot tile.
## The Camera opcode encodes "PSX world units × 4" (divisor 112 = 28×4), but
## the unit Sprite Move encodes raw PSX world units, so 28 opcode units = one
## tile. Anchored on baked scenario_1 {3B}: unit 0x13 `+X=0x1C` (28) ≈ 1 tile,
## unit 0x17 `+X=0xFFE4` (-28) ≈ 1 tile the other way. Exposed as a tunable
## (like the camera knobs) for visual calibration against the PSX walk refs.
var sprite_move_position_divisor: float = SCENARIO_POSITION_DIVISOR / 4.0


## Dispatch table built in _ready (Callables need self bound, so deferred from const).
## Keyed by opcode BYTE (the [EventInstruction] enum member's value), populated
## via `_bind` / `_skip`. ADR-0059.
var _handlers: Dictionary = {}

## Byte -> reason string for opcodes registered via `_skip` (intentionally
## unhandled). "Bound-or-skipped" == byte key present in `_handlers`; this holds
## the WHY for the skipped ones (the coverage check + traces read it).
var _skip_reasons: Dictionary = {}


func _init() -> void:
	# The apply-layer world facade (ADR-0058). Constructed here — not in `_ready` —
	# so it exists whenever the VM does, including tests that call handlers on a
	# `ScenarioVM.new()` that was never added to the tree. It reads the VM's
	# collaborators live (the host wires `units_by_id` / `map_composer` later), so it
	# only needs the VM ref now.
	_world = ScenarioWorld.new(self)


func _ready() -> void:
	camera_director = ScenarioCameraDirector.new(self)
	box_pool = ScenarioDialogueBoxPool.new(self)
	# Initialize the main context up-front so tests / debug paths that call
	# handlers directly (without going through `start()`) still have a valid
	# `_current_ctx` to write into.
	if _contexts.is_empty():
		var main_ctx := ScriptContext.new()
		main_ctx.label = "main"
		_contexts = [main_ctx]
		_current_ctx = main_ctx
	_bind_cinematic_tunables()
	box_pool.bind_tunables(self)  # dialbox.* placement knobs owned by the pool (ADR-0068)
	# Event-instruction handlers, keyed by opcode BYTE via _bind / _skip
	# (the EventInstruction enum member value IS the opcode byte). ADR-0059.
	_bind(EventInstruction.NO_OP, Callable(self, "_op_noop"))
	_bind(EventInstruction.LOAD_EVTCHR, Callable(self, "_op_load_evtchr"))
	_bind(EventInstruction.SAVE_EVTCHR, Callable(self, "_op_skip"))
	_bind(EventInstruction.WAIT_FOR_INSTRUCTION, Callable(self, "_op_wait_for_instruction"))
	_bind(EventInstruction.COLOR_UNIT, Callable(self, "_op_color_unit"))
	_bind(EventInstruction.COLOR_FIELD, Callable(self, "_op_color_field"))
	_bind(EventInstruction.RESET_PALETTE, Callable(self, "_op_reset_palette"))
	_bind(EventInstruction.MIRROR_SPRITE, Callable(self, "_op_mirror_sprite"))   # 0x68
	_bind(EventInstruction.BACKGROUND, Callable(self, "_op_background"))
	_bind(EventInstruction.CAMERA_FUSION_START, Callable(camera_director, "_op_camera_fusion_start"))
	_bind(EventInstruction.CAMERA_FUSION_END, Callable(camera_director, "_op_camera_fusion_end"))
	# Add Unit Start / End (0x49 / 0x4A) are pure brackets in the ROM — no
	# params, no observable side effect beyond batching. Add Unit (0x45)
	# dispatches to BATTLE.BIN `FUN_BATTLE.BIN__8008d05c` ("Post add/
	# transform Graphic UPDATE by Battle ID" per the Ghidra wiki comment):
	# fetches the unit's stats via `BATTLE_get_battle_stats_from_battle_id`
	# and commits the SHP/SEQ — it does NOT toggle sprite visibility. The
	# actual on-screen reveal is `Draw Unit` (0x44), which the same unit
	# always receives later inside a Block (color → off-screen sprite-move
	# → Draw Unit → fade in → walk to final tile).
	_bind(EventInstruction.ADD_UNIT_START, Callable(self, "_op_skip"))
	_bind(EventInstruction.ADD_UNIT, Callable(self, "_op_add_unit"))
	_bind(EventInstruction.ADD_UNIT_END, Callable(self, "_op_skip"))
	_bind(EventInstruction.DRAW_UNIT, Callable(self, "_op_draw_unit"))
	_bind(EventInstruction.ERASE_UNIT, Callable(self, "_op_erase_unit"))
	# {47} Add Ghost Unit — spawn a sprite-only actor with NO ENTD roster record
	# (BATTLE.BIN FUN_8008cf78 → the same unit-sprite VRAM-upload queue {45} Add Unit
	# uses; the only difference is the ghost carries no unit struct). Because a ghost
	# is not pre-spawned by `_spawn_units`, this handler actually creates the actor at
	# runtime (via the host `ghost_spawn_fn`), registered under control-id xID+0x64.
	# Full RE + decode: research/working_documents/ADD_GHOST_UNIT_OPCODE_47.md.
	_bind(EventInstruction.ADD_GHOST_UNIT, Callable(self, "_op_add_ghost_unit"))   # 0x47
	# {3D} Remove Unit — tears a unit fully off the field AND out of memory
	# (roster slot + registry + sprite slot), instantly. NOT the same as {46}
	# Erase Unit (hide-only) nor {44} Blue Remove Unit (animated + War Trophy).
	# Live-validated at both scenario-1 sites (0x83 PC 382, 0x13 PC 401). See
	# research/working_documents/scenario_1_captures/remove_unit_decode.md.
	_bind(EventInstruction.REMOVE_UNIT, Callable(self, "_op_remove_unit"))   # 0x3D
	# {92} Inflict Status — spawns a cooperative apply task on PSX (handler
	# 0x80145EE0 → body FUN_80148E88). We reproduce ONLY the stock `Status == 0`
	# branch = revive-if-dead(1 HP) + force a clean Standing (Critical-if-low-HP)
	# pose + block later event HP-restore; it is NOT a status bit and NOT body
	# removal. Covers 139/141 {92}-using scenarios (incl. scenario 6). Any other
	# Status FAILS LOUD (push_error + halt) — see issue #154 and
	# research/working_documents/scenario_1_captures/inflict_status_op92_decode.md.
	_bind(EventInstruction.INFLICT_STATUS, Callable(self, "_op_inflict_status"))   # 0x92
	# {43} Call Function — UNIMPLEMENTED. Dispatches a table of engine subroutines
	# (custom MIPS per `Function` index) we do not emulate. Unlike the `_op_skip`
	# stubs this is a genuine fidelity hole, so the handler SCREAMS on every call
	# (push_error, not once) — but it does NOT halt: the VM keeps running so the
	# scene still renders. Appears in ~530 scenario chunks (scn6 uses Function 4/5;
	# chapel uses 104). Needs Ghidra RE of the dispatch + function table — issue
	# #155. Was the scenario-6 Delita-render blocker (halted at pc=7,
	# long before his Draw at pc=88).
	_bind(EventInstruction.CALL_FUNCTION, Callable(self, "_op_call_function"))   # 0x43
	# {3C} Weather — map-wide rain particle latch. Two operand bytes pack into
	# one PSX global (Strength | Unknown<<8); Unknown!=0 runs weather, =0
	# cancels. Strength 2/3/4 = increasing storm power (velocity triple), not
	# density. World-space particle system (ScenarioWeather) parented into the
	# scene so the game camera transforms it + the depth buffer occludes it for
	# free. Snow is a per-map flag, out of scope. Live RE:
	# research/working_documents/WEATHER_OPCODE_3C_INVESTIGATION.md.
	_bind(EventInstruction.WEATHER, Callable(self, "_op_weather"))      # 0x3C
	# {76}/{77}/{78} Dark Screen family — the pre-battle "Conditions for
	# Winning" overlay (was the scenario-4 PC-130 halt). {76} starts an
	# expanding diamond-mosaic foreground overlay + raises the kind-54 ({E5})
	# barrier while it settles; {78} paints the win-conditions text over the
	# dim field; {77} retracts it. Full live-hardware RE (GAP-M CLOSED):
	# research/working_documents/DARKSCREEN_OPCODE_76_INVESTIGATION.md.
	_bind(EventInstruction.DARK_SCREEN, Callable(self, "_op_dark_screen"))         # 0x76
	_bind(EventInstruction.REMOVE_DARK_SCREEN, Callable(self, "_op_remove_dark_screen"))  # 0x77
	# {3E} Color Screen — full-screen ABR-blended colour ramp (fade to black/white).
	# research/working_documents/COLOR_SCREEN_OPCODE_3E.md.
	_bind(EventInstruction.COLOR_SCREEN, Callable(self, "_op_color_screen"))       # 0x3E
	_bind(EventInstruction.DISPLAY_CONDITIONS, Callable(self, "_op_display_conditions"))  # 0x78
	# {7D} Show Graphic: fades a fullscreen graphic (chapter card / ending /
	# GAME OVER / WLDBK background) in, holds, fades out; raises the kind-61
	# ({E5} Task=61) barrier while it's on screen. show_graphic_op7d_decode.md.
	_bind(EventInstruction.SHOW_GRAPHIC, Callable(self, "_op_show_graphic"))        # 0x7D
	# {91} Show Map Title: reveals a location-name strip (L->R wipe), holds, then
	# erases it (L->R wipe). BLOCKS the VM until it erases (handler-armed wait; the
	# PSX built-in FUN_8014c9d0, not a following {E5}). Ticked outside the halt
	# gate. show_map_title_op91_decode.md.
	_bind(EventInstruction.SHOW_MAP_TITLE, Callable(self, "_op_show_map_title"))    # 0x91
	_bind(EventInstruction.MAP_DARKNESS, Callable(self, "_op_map_darkness"))
	_bind(EventInstruction.WARP_UNIT, Callable(self, "_op_warp_unit"))
	_bind(EventInstruction.CAMERA, Callable(camera_director, "_op_camera"))
	# {1F} Focus / {38} Focus Speed — camera-focus-on-unit(s). Focus is a PSX
	# bytecode patcher: it rewrites the position operands of the FOLLOWING {19}
	# Camera opcode with the target unit(s)' midpoint (Focus Speed → that
	# Camera's Time). The linear Godot VM mirrors this by stashing a pending
	# focus on the director; `_op_camera` consumes it. Was the #1 early halt
	# (12 battle-intro scenarios die at PC 5-9). Live-validated RE:
	# research/working_documents/FOCUS_OPCODE_1F_INVESTIGATION.md.
	_bind(EventInstruction.FOCUS, Callable(camera_director, "_op_focus"))        # 0x1F
	_bind(EventInstruction.FOCUS_SPEED, Callable(camera_director, "_op_focus_speed"))  # 0x38
	# {73} Camera Move (relative) / {63} Camera Speed Curve — the {1F}-Focus-style
	# pre-patchers for the scenario-6 PC 386 orbit. {73} rewrites the FOLLOWING {19}
	# Camera's 7 pose operands to live_pose+delta (fixes the Zoom=0 → wide-shot
	# teleport, structurally); {63} arms the per-op ease curve. Live-validated,
	# byte-exact RE: CAMERA_ROTATION_OPCODES_63_73_19_INVESTIGATION.md §4.4/§4.7.
	_bind(EventInstruction.CAMERA_MOVE_RELATIVE, Callable(camera_director, "_op_camera_move_relative"))  # 0x73
	_bind(EventInstruction.CAMERA_SPEED_CURVE, Callable(camera_director, "_op_camera_speed_curve"))      # 0x63
	_bind(EventInstruction.UNIT_ANIM, Callable(self, "_op_unit_anim"))
	# {80} March — the cinematic→combat idle transition (starts each unit into its
	# combat idle, the walk-in-place "breathing" idle, not the scenario standing-still
	# idle). Battle-opener cinematics end on a March (e.g. Gariland scn 10); without a
	# handler the VM stalled here and the walk hung before deployment.
	_bind(EventInstruction.MARCH, Callable(self, "_op_march"))
	_bind(EventInstruction.ROTATE_UNIT, Callable(self, "_op_rotate_unit"))
	# {53} Face Unit — affected unit(s) rotate to LOOK AT the faced unit's
	# tile. Computes a look-at target_12bit then reuses the same
	# `scenario_rotate` stepper / pending-rotate queue as {2D} Rotate Unit.
	# Decode: research/working_documents/scenario_1_captures/face_unit_decode.md.
	_bind(EventInstruction.FACE_UNIT, Callable(self, "_op_face_unit"))
	# {2C} Face Unit 2 — the SAME ROM handler as {53} Face Unit
	# (evt0x53_face_unit @ 0x80148084), dispatched with a1=0 (`_clear a1`)
	# instead of a1=1. The a1=0 branch ALSO rotates the FACED unit 180° back
	# to look at the affected unit — so the two units FACE EACH OTHER (mutual).
	# Was the #1 remaining ScenarioVM halt (173 of 500 chunks). Live-decoded
	# static (scenario dispatch @ 0x80144dec) — see face_unit_decode.md §11.
	_bind(EventInstruction.FACE_UNIT_2, Callable(self, "_op_face_unit_2"))
	# {8C} Unit Anim Rotate (ROM 0x80147fac) — combined INSTANT set-facing
	# (absolute Direction nibble, no interpolation) + set-animation for one
	# unit. Mirrors {11} Unit Anim's animation path + {2D}'s absolute facing.
	_bind(EventInstruction.UNIT_ANIM_ROTATE, Callable(self, "_op_unit_anim_rotate"))
	# {69} Face Tile — the FaceUnit family sibling that targets a map TILE (X,Y)
	# instead of a faced unit. Same look-at + {2D} rotate stepper as {53} Face
	# Unit; only the target position differs (tile centre vs unit). Multi=1
	# (team set) is static-only, warn-skipped as in {53}. Scenario-6 onlookers
	# 2/23/52 turn to face the exit tile (0,13) to watch the ride-off. See
	# research/working_documents/FACE_TILE_UNIT_SHADOW_WAIT_ADD_UNIT.md §2.
	_bind(EventInstruction.FACE_TILE, Callable(self, "_op_face_tile"))
	# {4E} Unit Shadow — enable/disable a unit's ground drop-shadow. ROM toggles
	# the unit-struct show-flag unit+0x298 (shadow renderer @ 0x8007D5D0 gates on
	# it); anim opcodes 0xE0/0xE1 do the same. Operand Disable 0=on/1=off. Wired
	# to the existing per-unit UnitShadow (Unit.gd $ShadowMesh). Scenario-6:
	# 225/226 kill Ovelia/Delita shadows when they are lifted; 384 kills the
	# chocobo's as it rides off. See that same doc §3.
	_bind(EventInstruction.UNIT_SHADOW, Callable(self, "_op_unit_shadow"))
	_bind(EventInstruction.REVEAL, Callable(self, "_op_reveal"))
	_bind(EventInstruction.WAIT, Callable(self, "_op_wait"))
	_bind(EventInstruction.DISPLAY_MESSAGE, Callable(self, "_op_display_message"))
	_bind(EventInstruction.CHANGE_DIALOG, Callable(self, "_op_change_dialog"))
	# {50} Portrait Row: latch which EVTFACE row-block is resident (the following
	# {10}/{51} Portrait byte picks the column). PORTRAIT_ROW_OPCODE_50_EVTFACE.md.
	_bind(EventInstruction.PORTRAIT_ROW, Callable(self, "_op_portrait_row"))
	# Block Start / Block End: per wiki entry {2A}/{2B} + the live PSX decode
	# in BLOCK_EXECUTION_INVESTIGATION.md, Block Start spawns a parallel
	# cooperative coroutine for the block's body while the main thread
	# resumes past Block End. `_op_block_start` appends a child
	# ScriptContext that gets round-robined in `_tick_once` alongside the
	# main context. Block End in a parallel context terminates the
	# coroutine; in the main context it should never fire (the spawn
	# advanced main past it) and falls through to the noop handler.
	_bind(EventInstruction.BLOCK_START, Callable(self, "_op_block_start"))
	_bind(EventInstruction.BLOCK_END, Callable(self, "_op_block_end"))
	# The three script terminators are enum-keyed handlers (ADR-0059): they end
	# the current context (alive=false) so the drain loop exits, replacing the
	# former name-string special-case that preceded the dispatch lookup.
	_bind(EventInstruction.EVENT_END, Callable(self, "_op_event_end"))
	_bind(EventInstruction.EVENT_END_2, Callable(self, "_op_event_end"))
	# Inside-block opcodes. {3B} Sprite Move / {6E} Sprite Move Beta /
	# {6F} Wait Sprite Move are now implemented (per-unit straight-line
	# position lerp + barrier — see SPRITE_MOVE_INVESTIGATION.md, ROM
	# handler FUN_80149C48). The rest are still skip-stubs so they're
	# harmless if the Block Start jump misses (mismatched bracket) or if
	# they appear outside blocks. Wiki entries: {28} WalkTo, {29} WaitWalk,
	# {79} WalkToAnim. Plus chapel-chunk extras: Event Speed, Wait Add
	# Unit End.
	_bind(EventInstruction.SPRITE_MOVE, Callable(self, "_op_sprite_move"))
	_bind(EventInstruction.SPRITE_MOVE_BETA, Callable(self, "_op_sprite_move_beta"))
	_bind(EventInstruction.WAIT_SPRITE_MOVE, Callable(self, "_op_wait_sprite_move"))
	_bind(EventInstruction.WALK_TO, Callable(self, "_op_walk_to"))
	_bind(EventInstruction.WAIT_WALK, Callable(self, "_op_wait_walk"))
	# {64} Wait Rotate Unit / {65} Wait Rotate All — predicate barriers on the
	# unit `scenario_rotate` stepper (ROM FUN_801498fc @ 0x801498fc, polls the
	# +4 active flag). See HANDOFF_wait_rotate_unit.md.
	_bind(EventInstruction.WAIT_ROTATE_UNIT, Callable(self, "_op_wait_rotate_unit"))
	_bind(EventInstruction.WAIT_ROTATE_ALL, Callable(self, "_op_wait_rotate_all"))
	# {79} Walk To Anim only selects which anim plays during the in-flight
	# Walk To (Unit + Animation); `_op_walk_to` already drives the WALKING
	# activity, so the position outcome doesn't depend on it. Left a skip
	# until per-anim cinematic walk selection is wired.
	_bind(EventInstruction.WALK_TO_ANIM, Callable(self, "_op_skip"))
	# {48} Wait Add Unit — on PSX this BARRIERS the script until the pending
	# add/ghost unit finishes loading (async CDROM-DMA sprite upload:
	# evtchr_unit_add_queue @ 0x80049C1C, pending flag DAT_8016604e; drained by
	# evtchr_unit_queue_drain @ 0x80088E04). In Godot the {45}/{47} spawn is
	# SYNCHRONOUS — ScenarioPlayerScene._spawn_ghost_actor add_child()s the unit
	# and Unit._ready() runs in-stack, so by the time {48} executes the unit is
	# already registered + instantiated → the barrier is already satisfied. Skip,
	# exactly as its sibling {4B} Wait Add Unit End already does. See doc §4.
	_bind(EventInstruction.WAIT_ADD_UNIT, Callable(self, "_op_skip"))
	_bind(EventInstruction.WAIT_ADD_UNIT_END, Callable(self, "_op_skip"))
	_bind(EventInstruction.EVENT_SPEED, Callable(self, "_op_skip"))
	# {21} Sound Effect: single u16 operand = system-bank sound id. No
	# volume/pan/gain — those are baked into the SED bank entry. Wiki:
	# `research/wiki_articles/event_instructions_sound.md`. PSX dispatcher
	# `BATTLE_block_start_event_instruction @ 0x8013e8e8`. Chapel PC 92 fires
	# sound id 72 / 0x48 ("Locked Door"). Handler is fire-and-forget; the
	# VM keeps walking past it (no barrier opcode).
	_bind(EventInstruction.SOUND_EFFECT, Callable(self, "_op_sound_effect"))
	# {60} Fade Sound: fades the currently-playing MUSIC to silence (target is
	# always 0 — not parameterizable) over `(Time << (Shift+2)) & 0x3FFC`
	# music-sequencer ticks (= Time*4 for Shift 0). Time=0 cuts instantly; no
	# music → no-op; SFX {21} / BGSound {6B} untouched. Fire-and-forget (no
	# Wait opcode). PSX handler 0x801453f4 → flush 0x8014398c → SUB_80043be8 →
	# Calc_Mus_VolChange. Full RE:
	# research/working_documents/FADESOUND_OPCODE_60_INVESTIGATION.md.
	_bind(EventInstruction.FADE_SOUND, Callable(self, "_op_fade_sound"))
	# {22} Switch Track: toggle between the scenario's two ATTACK.OUT songs
	# (music_file_one/two), ramping master volume to the (transformed) Volume
	# over Time*4 sequencer ticks. The track byte (param "1") is a set-gate
	# only — its value never selects the song (decomp ticker `0x80143894`
	# sign-tests it; only the toggle picks slot=toggle+1). PSX handler
	# 0x801453c4 → flush 0x80143894 → FUN_80043a90 (stop+select+Reset_Mus) →
	# Calc_Mus_VolChange. RE: HANDOFF_switch_track_opcode.md.
	_bind(EventInstruction.SWITCH_TRACK, Callable(self, "_op_switch_track"))
	# {6B} BG Sound / {6A} Edit BG Sound — env-bank ambient (SOUND/ENV.SED,
	# handle 0x10000|Sound) with a linear StartVol→Volume ramp over Time
	# frames. {6B} plays (looping ambients loop; one-shots don't), tracked
	# (Stacking=0) vs overlay (≠0); {6A} re-ramps an already-playing bg sound
	# with NO re-trigger. NOT "Background" (0x2E gradient backdrop, handled by
	# _op_background above). Live-validated PSX decode + ramp:
	# research/working_documents/BGSOUND_OPCODE_6B_INVESTIGATION.md. Scenario 4
	# PC 5 = Rain (Sound 1, 0→24 over 255f) — was the halt blocker there.
	_bind(EventInstruction.BG_SOUND, Callable(self, "_op_bg_sound"))       # 0x6B
	_bind(EventInstruction.EDIT_BG_SOUND, Callable(self, "_op_edit_bg_sound"))  # 0x6A
	# {7C} End Sound — stop the currently-playing event SFX/BGM. PSX SUB_800440cc
	# zeroes the active-sound handle DAT_8004599c and runs an 8-voice teardown
	# (FUN_80012860); the scenario tail fires it before the battle hand-off. The
	# counterpart to {6B} BG Sound / {21} Sound Effect. Live-validated decode:
	# research/working_documents/SCENARIO6_UNKNOWN_OPCODES_6D_71_7C_82_INVESTIGATION.md §4.
	_bind(EventInstruction.END_SOUND, Callable(self, "_op_end_sound"))     # 0x7C
	# {54}/{55}/{56}/{57} Use/Wait 3D/Field Object — map textured-animation
	# objects. {55} Use Field Object (chapel PC 231, ID=1) plays a one-shot
	# textured animation on the map mesh; {57} Wait Field Object barriers on
	# its completion. {54}/{56} are the 3D-object pair. Full live-validated
	# PSX decode: research/working_documents/scenario_1_captures/
	# use_field_object_decode.md (Stage 1 unhalt; Stage 2 = real render).
	_bind(EventInstruction.USE_FIELD_OBJECT, Callable(self, "_op_use_field_object"))   # 0x55
	_bind(EventInstruction.WAIT_FIELD_OBJECT, Callable(self, "_op_wait_field_object"))  # 0x57
	_bind(EventInstruction.USE_3D_OBJECT, Callable(self, "_op_use_3d_object"))      # 0x54
	_bind(EventInstruction.WAIT_3D_OBJECT, Callable(self, "_op_wait_3d_object"))     # 0x56
	# Event variable system (Wait Value path). Writers `Zero` (0xBE) /
	# `Add` (0xB0) and reader `Wait Value` (0x7E) — the prayer-scene
	# frame-counter sync (var 87). Full RE:
	# research/wiki_articles/event_instruction_a0_d5_variable_readers.md
	# (readers) + event_instruction_b0_be_variable_math.md (writers).
	_bind(EventInstruction.ZERO, Callable(self, "_op_var_zero"))          # 0xBE
	_bind(EventInstruction.WAIT_VALUE, Callable(self, "_op_wait_value"))        # 0x7E
	# The `0xB0`-`0xBD` arithmetic family is ONE ROM handler (`FUN_8014a018`), so it
	# is one handler here: the op comes from the opcode's high nibble-pair and the
	# operand mode from its low bit (even = immediate, odd = variable id). Binding
	# the whole family rather than only the two opcodes a scenario happens to reach
	# is the point — `Returning to Igros` (scn 27) halted the walk on `0xB1 Add
	# Variable` alone, and every unbound sibling is the same halt waiting for a
	# different scenario. Writers doc §0/§2.
	for _math_op in _VAR_MATH_OPCODES:
		_bind(_math_op, Callable(self, "_op_var_math"))
	# `0xA0`-`0xA5` comparisons: a two-register ALU over the FIXED scratch pair
	# var[0] / var[1] whose boolean lands back in var[0] (readers doc §2). They read
	# no operand bytes at all, which is why the compiler stages both operands with
	# the writers above first.
	for _cmp_op in _VAR_COMPARE_OPS:
		_bind(_cmp_op, Callable(self, "_op_var_compare"))
	# `0xD0`/`0xD1`/`0xD3` jumps + their `0xD2`/`0xD4`/`0xD5` label anchors (readers
	# doc §3). The jumps carry a LABEL ID, never a byte distance — `0xD0` is the
	# other half of the comparison above (it jumps exactly when var[0] == 0, i.e.
	# when the compare was FALSE).
	_bind(EventInstruction.JUMP_FORWARD_IF_ZERO, Callable(self, "_op_jump_forward_if_zero"))  # 0xD0
	_bind(EventInstruction.JUMP_FORWARD, Callable(self, "_op_jump_forward"))                  # 0xD1
	_bind(EventInstruction.JUMP_BACK, Callable(self, "_op_jump_back"))                        # 0xD3
	_bind(EventInstruction.FORWARD_TARGET, Callable(self, "_op_label_anchor"))                # 0xD2
	_bind(EventInstruction.FORWARD_IF_ZERO_TARGET, Callable(self, "_op_label_anchor"))        # 0xD4
	_bind(EventInstruction.BACK_TARGET, Callable(self, "_op_label_anchor"))                   # 0xD5
	# The 48 unnamed ("Unknown") catalog opcodes auto-skip: each is bound to
	# _op_skip so byte-keyed dispatch clean-skips it (print + return, pc already
	# advanced) instead of halting on a null handler — preserving the prior single
	# "Unknown" -> _op_skip_unknown clean-skip. ADR-0059 / issue #145.
	for _unknown_op in EventInstructionSet.unknown_opcodes():
		_skip(_unknown_op, "unnamed opcode")
	# {0x66} Commit Palette — MODELED (the scenario-3/4/5/6 map-hue fix). Named in
	# the catalog so the generator emits COMMIT_PALETTE (naming goes through the
	# vendored XML, not a hand-patched enum); the unnamed-sweep above no longer
	# touches it, so this explicit bind is the sole handler. See _op_commit_palette.
	_bind(EventInstruction.COMMIT_PALETTE, Callable(self, "_op_commit_palette"))
	# Verified opcodes Godot declines to model (ADR-0059 downstream policy): keep
	# them off the halt path via _skip so the coverage invariant holds.
	# {7F} EVTCHR Palette — an EVTCHR palette timing-wait (PSX evt0x7f waits on
	# FUN_8013b590(Block) >= Palette). We don't model EVTCHR palette timing, so
	# skipping is faithful-enough (the wait is a no-op without EVTCHR loaded).
	# Its `Block` param is the palette-upload counter being waited on — NOT the
	# addressed unit's EVTCHR page. Binding it as a per-unit page override was
	# considered for the root-28 fix and REFUTED by the 500-chunk replay: it
	# disagrees with the band in 6 of 115 bindings and is wrong in all 6. The
	# reasoning is on `_resolve_cinematic_block`; don't re-derive it.
	_skip(EventInstruction.EVTCHR_PALETTE, "EVTCHR palette timing-wait; not modeled in Godot")
	# Scenario-6 opcodes RE'd 2026-07-10 (SCENARIO6_UNKNOWN_OPCODES_6D_71_7C_82_
	# INVESTIGATION.md). Named + documented but intentionally NO-OP in Godot: each
	# PSX effect is an artifact of the PSX 2D sprite-list renderer / manual per-unit
	# update loop that Godot's 3D depth sort + VM-driven cinematic units subsume.
	# PSX: {6D}/{6C} set/clear bit 0x04000000 @ unit node+0x80 = hold the unit under
	# event control (suppresses part of the per-frame combat update FUN_80082468).
	# Godot: cinematic units are already VM-driven (is_cinematic_unit) → no auto-update to suppress.
	_skip(EventInstruction.SET_UNIT_EVENT_HOLD, "hold unit under event control; cinematic units already VM-driven (is_cinematic_unit)")   # 0x6D
	_skip(EventInstruction.CLEAR_UNIT_EVENT_HOLD, "release event-control hold; cinematic units already VM-driven (is_cinematic_unit)")     # 0x6C
	# PSX: {71} raises the unit's sprite to the head of the draw-order list
	# (unit_sprite_list_head 0x80098A54) before a Sprite Move so it layers on top.
	# Godot: sprites depth-sort by real 3D position (ADR-0009 CUSTOM0) → no draw-list to reorder.
	_skip(EventInstruction.RAISE_UNIT_DRAW_PRIORITY, "PSX 2D draw-order bump; Godot 3D depth sort (ADR-0009) already orders sprites")       # 0x71
	# {1B} Map Light — NOT IMPLEMENTED, and the skip is the decision (ADR-0264).
	# The catalog carries it `verified: false` with three unnamed 2-byte params ahead of
	# Red/Green/Blue/Time, it is un-RE'd, and across all 72 battle-group openers it appears
	# TWICE — both in group 291's opener (scn 292). Inferring a light from those names is
	# exactly what was done for its neighbour {1A} Map Darkness, which turned out to change
	# zero rendered pixels and had to be removed (ADR-0051); the overexposed-map bug it gets
	# confused with was ADR-0056, a map-data EXPORT defect, not a missing instruction. So it
	# is skipped rather than guessed at — and skipped rather than left unbound, because an
	# unbound opcode HALTS the VM, and a halt mid-opener is a battle that never settles.
	_skip(EventInstruction.MAP_LIGHT, "un-RE'd map lighting (verified:false); ADR-0264 declines to infer one")  # 0x1B
	# PSX: {82} is a sub-token of the {49}..{4A} AddUnit block (control-point/midpoint
	# geometry setup via FUN_8013e81c), never a standalone dispatched opcode.
	# Godot: add-unit + ScenarioPathMotion already cover path/geometry init.
	_skip(EventInstruction.ADD_UNIT_PATH_SETUP, "AddUnit-block control-point setup; covered by add-unit + ScenarioPathMotion")             # 0x82
	# Cooperative-task kind→liveness registry (the {E5} Wait For Instruction
	# barrier model). Registered once here; see `_register_task_kinds`.
	_register_task_kinds()

	# Soft coverage reminder (ADR-0059): a `verified:true` opcode that is neither
	# bound nor _skip'd would halt mid-scene. Warn (do NOT refuse to boot) so a dev
	# running headful sees the gap during RE iteration. Healthy build → silent.
	for _unbound in unbound_verified_opcodes():
		push_warning("[ScenarioVM] verified opcode 0x%02X (%s) is neither bound nor skipped — will halt if reached" %
			[_unbound, EventInstructionSet.name_of(_unbound)])


func load_chunk_json(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[ScenarioVM] cannot open %s" % path)
		return false
	var raw := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if parsed == null or not parsed.has("instructions"):
		push_error("[ScenarioVM] bad JSON in %s" % path)
		return false
	_insts = parsed["instructions"]
	if box_pool == null:
		box_pool = ScenarioDialogueBoxPool.new(self)
	box_pool._index_message_tokens()
	print("[ScenarioVM] loaded %d instructions from %s" % [_insts.size(), path])
	return true




## `fresh` (default true) does a full scene reset — the standalone boot / replay /
## rewind path. Pass `fresh=false` when ADVANCING to the next member of a scenario
## group ([ScenarioPathApplier]): the persistent scene overlays (weather, ambient
## BG sound, dark screen, background gradient) then CARRY OVER instead of being torn
## down, matching the ROM — those live in map-state that scenario-init does NOT reset
## (weather = var 0x23), unlike the per-scenario execution state below (contexts,
## dialog gates, unit cutscene state, {22} track toggle, event vars) which resets on
## every member exactly as `0x80144034` zeroes them at each scenario init.
## `preserve_combat_poses` (only true on the woven victory-beat handoff) carries the
## combat-committed pose across `reset_all` so KO'd units stay DOWN and survivors
## keep their end-of-combat pose instead of snapping to idle (see `reset_all` /
## `Unit.reset_scenario_cutscene_state`). Default off: fresh boots and ordinary
## member advances reset to the idle baseline as before.
func start(fresh: bool = true, preserve_combat_poses: bool = false) -> void:
	var main_ctx := ScriptContext.new()
	main_ctx.label = "main"
	_contexts = [main_ctx]
	_current_ctx = main_ctx
	_running = true
	# Clear any leftover fast-play / debug-park HALT. `start()` is the ADR-0064 single
	# reset path, so no `_paused` may leak across a (re)start. This is load-bearing on
	# the navigator SEEK path: `run_combat` settles the world by fast-forwarding the
	# opener on this same `_vm`, and `_finish_fast_play()` leaves `_paused = true`; the
	# victory beat then `start()`s scn6 on it — without this clear, scn6 dispatched
	# under `paused` (`_tick_once` `if paused: return`) and froze at pc 0, never reaching
	# the {43} dead-unit fade (ScenarioStartClearsPauseTest; diagnosing-bugs 2026-07-18).
	_paused = false
	_pending_dialog_gate = false
	_dialog_gate_active = false
	_dialog_gate_ctx = null
	_dialog_dwell_ticks = 0
	box_pool._close_all_boxes()
	box_pool._box_speaker = null
	# Per-unit cutscene state (tint/motion/walker/atlas/home) AND the three Unit
	# fields (facing/rotate/anim) rebuild from scratch on a (re)start / rewind
	# replay — the one reset path (ADR-0064) so nothing leaks across a live-VM
	# restart. Replaces the old home-only clear that leaked all the rest.
	reset_all(units_by_id, preserve_combat_poses)
	# ADR-0065: scenario units advance their anim clock off the VM tick, not host
	# render-delta. Flip every registered unit to `tick_based` on scenario entry;
	# `Unit._process`'s delta pump then no-ops and `_advance_scenario_anim` drives
	# the frame index once per `_tick_once`. Scenario-scoped: units are spawned
	# fresh per scenario and freed on exit, so the flip does not leak into combat
	# or free-roam (which keep delta-mode smoothness). Ghost units spawned mid-run
	# flip on first sight in `_advance_scenario_anim`.
	for uid in units_by_id.keys():
		var u = units_by_id[uid]
		if u != null and is_instance_valid(u) and ("clock_owner" in u):
			u.clock_owner = ClockOwner.SCENARIO
	# Persistent scene overlays (weather / ambient BG sound / dark screen /
	# background gradient) tear down ONLY on a fresh boot / replay / rewind. On a
	# group member advance (`fresh=false`) they carry over — the ROM keeps them in
	# map-state that scenario-init does not clear, so wiping them here dropped the
	# rain when the scenario player walked 4→6 within a group.
	if fresh:
		# {6B} BG Sounds: stop any live ambient voices and drop their ramps so a
		# (re)start / rewind replay re-triggers them from PC 0 rather than layering a
		# second copy on top of the still-playing first.
		for sid in _bg_sounds:
			_world.stop_bg_sound((_bg_sounds[sid] as ScenarioBgSound).handle)
		_bg_sounds.clear()
		# {3C} Weather: cancel any live rain so a (re)start / rewind replay re-arms it
		# from PC 0 rather than leaving the previous run's particles falling.
		if _weather != null:
			_weather.set_weather(false, 0)
		# {76} Dark Screen: free the overlay so a (re)start / rewind replay re-runs
		# {76} from scratch rather than leaving a settled mosaic dimming the frame.
		if _dark_screen != null:
			_dark_screen.queue_free()
			_dark_screen = null
		# {78} Display Conditions: free the screen so a (re)start / rewind replays
		# the banner / results pipeline from its first frame.
		if _results_screen != null:
			_results_screen.queue_free()
			_results_screen = null
		# {3E} Color Screen: free the overlay so a (re)start / rewind replays the
		# fade from scratch rather than inheriting a settled full-screen tint.
		if _color_screen != null:
			_color_screen.queue_free()
			_color_screen = null
		# {2E} Background: drop the gradient ramp model so a (re)start replays the
		# storm-sky/flash sequence from scratch rather than inheriting a mid-ramp
		# state. The quad is re-established by the scene default + the first {2E}.
		_background = null
	# {1F}/{38} Focus: drop any pending focus (a Focus with no consuming Camera
	# before restart) so a replay re-derives it from PC 0.
	if camera_director != null:
		camera_director.clear_pending_focus()
	# {22} Switch Track toggle resets to 0 (PSX `0x80144034` zeroes fd8 at
	# scenario init); song one is the load-time track, so the first {22} → song
	# two. Reset here so a rewind/replay re-derives the same alternation.
	_track_toggle = 0
	# {50} Portrait Row EVTFACE latch resets to "no row" on every (re)start so a
	# rewind/replay/group-member advance re-derives it from the member's own {50}
	# (per-scenario execution state, like the track toggle). Without this the last
	# scene's row leaks and a later mode-0x10 box paints a stale event portrait.
	_portrait_row = -1
	# The variable store is NOT cleared here — see `vars_store`. It is campaign state
	# shared with the world map, and the scripts reset their own counters with
	# `Zero(v); Add(v, k)`. Clearing it is what kept the story counter from ever advancing.
	# Chapel-trace mode: enable play-through-skip so a single unhandled opcode
	# (Change Dialog, etc.) doesn't truncate the trace before the
	# section of interest. The trace records `handled=false` for those rows so
	# the report can flag opcodes the engine couldn't act on.
	if DebugConfig.chapel_trace_enabled and not play_through_skip_unknown:
		play_through_skip_unknown = true
		print("[ScenarioVM] chapel-trace: forcing play_through_skip_unknown=true")
	_open_chapel_trace()
	print("[ScenarioVM] start (pc=0)")


## Rewind to `target_pc` by replaying the script from scene start at high speed,
## then halt paused so the user can step the target opcode normally. Backs the
## F3 debug panel's click-to-rewind: the panel reloads the scene (resetting the
## world), the scene boots ScenarioVM via `start()`, then calls this.
##
## This does NOT snap opcodes to their endpoints. It arms a high-speed replay:
## `_process` drives the normal per-frame + per-tick pipeline (camera lerps,
## sprite moves, walks, Wait counters, cinematic walkers) with `delta` scaled by
## `rewind_speed`, so the world evolves along the SAME trajectory a real-time
## playthrough would take — just fast — and the main context is halted exactly
## at `target_pc`. This is the difference the user asked for: "go to scene start,
## crank the speed, let it play," not "collapse every timed action to zero."
##
## `play_through_skip_unknown` is forced on for the duration so an unhandled
## opcode (or an 8-minute Wait) before the target can't strand the replay; it's
## restored in `_finish_fast_play`. Block contexts spawned during the replay run
## and complete normally (real coroutines), so they're left in their true state
## rather than dropped.
##
## `target_pc <= 0` sits paused at PC=0 without replaying. `target_pc` past
## end-of-chunk clamps to the last instruction.
func set_rewind_target(target_pc: int) -> void:
	if _insts.is_empty():
		push_warning("[ScenarioVM] set_rewind_target before load_chunk_json; ignoring")
		return
	target_pc = clampi(target_pc, 0, _insts.size())

	# Reset the VM to scene start: a fresh main context at PC=0, no residual
	# dialog/advance gates or Sprite-Move home anchors from the pre-rewind run.
	var main_ctx := ScriptContext.new()
	main_ctx.label = "main"
	_contexts = [main_ctx]
	_current_ctx = main_ctx
	_pending_dialog_gate = false
	_dialog_gate_active = false
	_dialog_gate_ctx = null
	_dialog_dwell_ticks = 0
	box_pool._close_all_boxes()
	box_pool._box_speaker = null
	# Same unified per-unit reset as start() (ADR-0064): registry + the three Unit
	# fields, so a rewind replay re-derives everything from PC 0 with no leak.
	reset_all(units_by_id)
	# The variable store is NOT cleared here either (matches `start()`); the replay
	# re-derives var 87 from the chunk's own `Zero(87)`.

	if target_pc <= 0:
		# Nothing to replay — sit paused at the very start.
		_ff_active = false
		_running = false
		_paused = true  # internal (rewind halt) — silent, see paused setter
		print("[ScenarioVM] rewind → pc=0 (paused at scene start)")
		return

	_begin_fast_play(target_pc, "rewind")


## Step the main context forward `n` opcodes the SAME way a rewind plays — a
## high-speed run through the real pipeline, not a snap-to-endpoint. Backs the
## F3 debug panel's Step / Step 10 / Step 100 buttons. Unlike `set_rewind_target`
## it does NOT reset to scene start: it continues from wherever the VM is paused,
## advancing exactly `n` main-context opcodes (motion from each plays out, fast),
## then re-pauses. Safe to call while running (it just re-targets and pauses on
## arrival) or at end-of-chunk (no-op).
func step(n: int = 1) -> void:
	if _insts.is_empty():
		return
	var main_ctx: ScriptContext = _contexts[0] if not _contexts.is_empty() else null
	if main_ctx == null or main_ctx.pc >= _insts.size():
		return
	var target: int = clampi(main_ctx.pc + maxi(1, n), 0, _insts.size())
	# Resuming from a park (halted, `_paused`): the parked frame already advanced the
	# render clock on the tick the main context became dispatchable, so the first
	# resumed dispatch reuses it rather than charging a fresh visual tick — that's
	# what makes "park N + step" land on the SAME beat as "select N+1". A step issued
	# while the VM is genuinely running has no such pre-spent frame, so don't skip.
	_begin_fast_play(target, "step", _paused)


# Arm a high-speed fast-play: `_process` drives the normal per-frame + per-tick
# pipeline with `delta` scaled by `rewind_speed` until the main context reaches
# `target_pc`, then `_finish_fast_play` restores the halt policy and pauses.
# Shared by `set_rewind_target` (which resets first) and `step` (which doesn't).
# Forces `play_through_skip_unknown` on so an unhandled opcode / 8-minute Wait
# before the target can't strand the run; restored on finish.
func _begin_fast_play(target_pc: int, kind: String, skip_first_visual: bool = false) -> void:
	# Preserve the ORIGINAL halt policy across a re-target (e.g. a Step clicked
	# while a prior fast-play is still settling) so `_finish_fast_play` restores
	# the user's real choice, not the forced-on value.
	if not _ff_active:
		_ff_prior_skip = play_through_skip_unknown
	play_through_skip_unknown = true
	# Only a step RESUMING from a park reuses the parked frame (see `step` /
	# `_advance_frame`). A re-target while already fast-playing (`_ff_active`) is
	# mid-stream — its visual bookkeeping is live, so never inject a skip there.
	_ff_skip_first_visual = skip_first_visual and not _ff_active
	_ff_target_pc = target_pc
	_ff_frames_left = _REWIND_MAX_FRAMES
	_ff_active = true
	_running = true
	_paused = false  # internal (fast-play run) — silent, see paused setter
	var from_pc: int = _contexts[0].pc if not _contexts.is_empty() else 0
	print("[ScenarioVM] %s → high-speed play pc=%d→%d (of %d) at %.0fx" %
		[kind, from_pc, target_pc, _insts.size(), maxf(1.0, rewind_speed)])


# Finalize a high-speed fast-play (rewind or step): restore the pre-run halt
# policy and pause at the current PC so the user can step the next opcode.
func _finish_fast_play() -> void:
	_ff_active = false
	play_through_skip_unknown = _ff_prior_skip
	# Drop the unspent tick budget of the batch we broke out of mid-way. A fast-play
	# host frame adds ~`rewind_speed` ticks to the accumulator but the mid-batch park
	# break (see `_advance_frame`) consumes only a few; without this reset the ~29
	# leftover ticks would dump into the anim clock on the first post-park frame,
	# lurching the parked pose forward. The park is a deliberate halt — start the
	# quantizer clean.
	_tick_accumulator = 0.0
	_paused = true  # internal (step/rewind halt) — silent, see paused setter
	var pc: int = _contexts[0].pc if not _contexts.is_empty() else 0
	if pc >= _ff_target_pc:
		print("[ScenarioVM] fast-play done; paused at pc=%d" % pc)
	else:
		push_warning("[ScenarioVM] fast-play hit safety cap at pc=%d (target=%d); paused" %
			[pc, _ff_target_pc])



## True while the main context is stalled on a barrier armed by an already-passed
## opcode — a timed `Wait` (`wait_ticks`) or a motion/rotate/predicate wait
## (`wait_until`). A fast-play must not park while this holds, else it freezes an
## awaited slide that PSX would have finished before fetching the target opcode.
func _main_ctx_blocked() -> bool:
	if _contexts.is_empty():
		return false
	var m: ScriptContext = _contexts[0]
	return m.wait_ticks > 0 or m.wait_until.is_valid()


## Boxed-dialog advance: while a box gate is active and we are NOT auto-advancing, the
## Cross/confirm key drives it — first press completes the typewriter, a second press releases
## the gate.
##
## [b]An EVENT, not a per-frame edge query.[/b] This stood in `_process` as
## `Input.is_action_just_pressed`, the last POLL on `check_focus_anchor.py`'s list and the one
## thing Focus structurally cannot gate: the switch stops Godot CALLING a non-holder, it cannot
## stop one ASKING. An edge query is the awkward kind to convert — there is no held state to
## track, so it does not become a tracked vector the way the pad reads did. It becomes the
## thing it was always emulating, which is the press itself.
##
## The gate is still tested here rather than at the bottom of the callback, and for the reason
## it was tested in `_process`: outside an active, non-auto-advancing gate this press does not
## mean "advance" and is none of this node's business.
##
## [b]Not consumed.[/b] The poll never took the event off anyone, and `set_input_as_handled()`
## here would be a new behaviour smuggled in under a refactor — a confirm that other listeners
## see today would silently stop arriving. If it should be exclusive, that is its own decision.
func _unhandled_input(event: InputEvent) -> void:
	if not _dialog_gate_active or dialog_auto_advance:
		return
	if _advance_action_pressed(event):
		_advance_dialog()


func _process(delta: float) -> void:
	if _ff_active:
		# High-speed fast-play (rewind or step): drive the normal pipeline with a
		# scaled delta so every per-tick / per-frame transition still fires in
		# order, then pause the instant the main context reaches the target PC.
		# The scaled delta is capped (`_REWIND_MAX_FRAME_DELTA`) so one host frame
		# can't run an unbounded number of ticks after a frame-time spike.
		_ff_frames_left -= 1
		var ff_delta := minf(delta * maxf(1.0, rewind_speed), _REWIND_MAX_FRAME_DELTA)
		_advance_frame(ff_delta)
		# `_advance_frame`'s accumulator loop already broke out the instant this same
		# predicate went true mid-batch (see `_ff_should_park`), so the render clock
		# is pinned at exactly the target tick; here we just finalize the halt.
		if _ff_should_park():
			_finish_fast_play()
		return

	_advance_frame(delta)


# Advance every time-driven system one host frame: camera chain spline, camera
# lerp, sprite moves, walks, and the 60 Hz VM tick clock. Factored out of
# `_process` so a high-speed fast-play (rewind or step) can drive the SAME
# pipeline with a scaled delta — that's what makes both a faithful fast
# playthrough rather than a snap-to-endpoint.
func _advance_frame(delta: float) -> void:
	# Keep an open dialogue box glued to its speaker + picking up live debug-panel
	# tuning. Placement used to run once at show_dialog time, so tuning an open box
	# did nothing; re-run it here each frame while the box is up.
	box_pool._reposition_open_box()

	# ADR-0065: motion, camera, and the unit anim clock NO LONGER advance here on
	# host render-delta. They advance one fixed 1/60 step per VM tick — in lockstep
	# with dispatch — via `_advance_tick_visuals` inside the accumulator loop, so
	# the rendered sprite (position + pose) stays locked to the event clock and a
	# scenario beat is a function of tick-count-since-resync, host-rate-independent
	# (the scn6 carry beat-match drift; see the ADR + living doc). This function is
	# now purely the host→tick quantizer.
	_tick_accumulator += delta * _TICK_HZ
	while _tick_accumulator >= 1.0:
		_tick_accumulator -= 1.0
		# Clear the per-tick paint mark FIRST so it stays live through this tick's
		# whole visuals phase AND the following `_tick_once` (where
		# `_tick_cinematic_walkers` reads it, §8f).
		_painted_this_tick.clear()
		# {11} pending-pose latch consume — the Godot mirror of the PSX per-frame
		# consumer `FUN_80085C0C`. PSX paints the pose on the FIRST FRAME THAT ELAPSES
		# after the latch, and a frame elapses only when the main thread YIELDS inside a
		# blocking wait. So the consume is gated on a wait-frame genuinely being spent
		# this tick — the main context is blocked (a `Wait` / `Wait Sprite Move` /
		# predicate barrier is spinning) coming INTO this tick — NOT on every tick.
		# Without the gate the latch painted (a) while genuinely PARKED — the paused
		# accumulator kept ticking the consume, so a park drifted the pose forward one
		# host frame after halting — and (b) on a step OVER a non-blocking opcode (e.g. a
		# `{3B}` Sprite-Move arm), where PSX elapses NO frame, so in the F3 stepper the
		# pose leaked onto the wrong opcode boundary by up to the count of non-blocking
		# opcodes between the `{11}` and the next wait (live PSX single-pass sweep
		# pc210→225: paint lands on the next {F1}/{6F}, latch can persist across 3+
		# non-blocking opcodes; SCENARIO_WAIT_SEMANTICS.md §8k). Free-run is unaffected:
		# `_drain_context` collapses a whole non-blocking run into ONE tick, so the tick
		# AFTER a `{11}` is always a blocked wait-frame tick → the paint still lands on
		# the wait's first frame. Both fast-play paths ("select N+1" and "park N + step")
		# use this same gate, so the stepping-consistency invariant is preserved.
		if _main_ctx_blocked():
			_consume_pending_body_anims()
		if _ff_active and _ff_skip_first_visual:
			# First tick of a `step` resumed from a park: the parked frame already
			# advanced the render clock on the tick the main context became
			# dispatchable, so reuse it — dispatch WITHOUT a fresh visual advance.
			# Without this, each step charges one visual tick PER opcode while a
			# continuous fast-play (select) drains a whole non-blocking run on ONE
			# tick, so N steps drift N ticks ahead of selecting the run's end
			# (the stepping-consistency off-by-one; ScenarioSteppingConsistencyTest).
			# NOTE the latch consume above sits OUTSIDE this skip on purpose (§8h): it
			# is an event-clock paint, not a render-clock advance, so a step-resumed
			# tick still evaluates it — but it only fires when a wait-frame is actually
			# being spent (`_main_ctx_blocked()`), which is never the case on a park's
			# pre-exec first tick, matching PSX (§8k).
			_ff_skip_first_visual = false
		else:
			_advance_tick_visuals()
		_tick_once()
		# End of the dispatch tick: a unit that {44} revealed THIS tick must not be
		# drawn wearing the pose a sibling {11} on the same tick already superseded
		# (the scenario-29 pc76 one-frame flash). Runs after `_tick_once` so it sees
		# every opcode the tick drained, and on `_ff_skip_first_visual` ticks too.
		_paint_revealed_unit_anims()
		# Fast-play (rewind/step) parks the INSTANT the main context reaches its
		# target and is un-blocked — mid-batch, not at end-of-batch. One fast-play
		# host frame quantizes to a whole BATCH of ticks (`rewind_speed`≈30); without
		# this break the loop keeps pumping the rest of the batch into the anim /
		# motion / camera clocks AFTER the PC is already pinned at target, over-running
		# the park by the batch remainder. That over-run is why "park N then step" (two
		# batches) landed the render clock a full batch ahead of "select N+1" (one
		# batch) — the stepping-consistency divergence (ScenarioSteppingConsistencyTest).
		# Breaking here pins the render state at exactly the tick the target is reached,
		# so both paths converge on the same beat. `_process` re-checks the same
		# predicate and calls `_finish_fast_play` (which drops the unspent batch budget).
		if _ff_active and _ff_should_park():
			break


## True once a fast-play (rewind/step) has reached its halt point: the main
## context has REACHED the target PC and is un-blocked (no pending timed `Wait`,
## no motion/rotate barrier), or it terminated, or the safety frame budget ran
## out. Un-blocked matters: a `Wait`/`Wait Sprite Move` bumps pc BEFORE arming its
## barrier, so pc reaches the target while the awaited slide is still in flight;
## parking then would freeze a move PSX completes BEFORE "PC N read", leaving the
## beat one move behind (HANDOFF_scn6_pace_alignment §3.2). Holding until un-blocked
## drains the barrier so the parked beat is the true pre-execution state at
## `get_pc()==N`. Shared by the `_advance_frame` accumulator loop (mid-batch break)
## and `_process` (finalize) so both agree on exactly when the run stops.
func _ff_should_park() -> bool:
	if _contexts.is_empty():
		return true
	if _ff_frames_left <= 0:
		return true
	return _contexts[0].pc >= _ff_target_pc and not _main_ctx_blocked()


## Advance the render clock one VM tick (ADR-0065): unit anim, camera, and motion
## each step a fixed 1/60 in lockstep with dispatch. Driven from the
## `_advance_frame` accumulator loop alongside `_tick_once`, which stays PURE
## DISPATCH — tests (and debug tooling) drive `_tick_once` directly to step
## dispatch WITHOUT moving the camera/slides (ScenarioWaitForInstructionTest sets
## camera state by hand and asserts a barrier holds). Order mirrors the old
## `_advance_frame`: visuals advance, then dispatch reads the fresh state.
##
## The anim advance is NOT pause-gated — per-unit body clocks kept animating
## during a park before this change (they ran in `Unit._process`, which the
## `paused` freeze never touched), so a parked beat still breathes. Camera +
## motion ARE pause-gated so a debug park is a true freeze-frame: an in-flight
## slide must not interpolate past the parked PC (the "slow-mo after park" bug,
## HANDOFF_scn6_pace_alignment §3.1). Both run during a halt (`_running` false) —
## matching the old placement outside the tick loop — and during a fast-play
## (rewind/step clears `paused`, so both advance to the target beat).
func _advance_tick_visuals() -> void:
	_advance_scenario_anim()
	if not paused:
		camera_director.tick(_TICK_DT)
		if not actors.is_empty():
			_advance_motions(_TICK_DT)


## Advance every time-driven visual ramp one VM tick: the reveal/oxide fades,
## weather, dark-screen mosaic, show-graphic fade, unit/field colour tints, the
## background gradient, BG-sound volume ramps, and the overlay typewriter.
##
## These run OUTSIDE the `_running`/dispatch halt gate (that's why they're
## factored out here and called before `_tick_once`'s `if not _running` return):
## a fade armed right before an unhandled-opcode or wait wall must still finish
## so the scene settles. But they are ALL frozen together by a debug `paused`
## park — `_tick_once` calls this behind a single `if not paused` gate. That one
## gate is THE freeze for a beat-compare park; do NOT re-add per-effect
## `not paused` checks (the old bandaid pattern — camera/motion/walkers each grew
## their own gate while the fades kept ticking, so a park was never a true
## freeze). New time-driven effects belong here and inherit the freeze for free.
func _tick_time_driven_effects() -> void:
	# Fade ticker runs independently of VM halt — Reveal sets up a fade that
	# must complete even after the VM stops on an unhandled opcode.
	if _reveal_remaining_ticks > 0:
		_reveal_remaining_ticks -= 1
		var done_frac := 1.0 - (float(_reveal_remaining_ticks) / float(_reveal_duration_ticks))
		_apply_fade_alpha(1.0 - done_frac)

	# {3C} Weather rain particles — advance one game frame. Ticks outside the VM
	# halt gate (like the fades) so rain keeps falling while dispatch pauses on a
	# dialog or unhandled opcode. No-op while inactive.
	if _weather != null:
		_weather.tick()

	# {76} Dark Screen mosaic — advance the overlay's grow-in / retract one frame.
	# Ticks outside the halt gate so the mosaic settles while the VM parks on the
	# {E5} Wait For Instruction(0x36) that immediately follows the {76} dispatch.
	if _dark_screen != null:
		_dark_screen.tick()

	# {3E} Color Screen — advance the full-screen colour ramp one frame. Ticks
	# outside the halt gate so the fade completes while the VM parks on the {E5}
	# Wait For Instruction(Task=12) that immediately follows the {3E} dispatch.
	if _color_screen != null:
		_color_screen.tick()

	# {7D} Show Graphic — advance the fullscreen graphic's fade one frame. Ticks
	# outside the halt gate so the fade-in/hold/fade-out completes while the VM
	# parks on the {E5} Wait For Instruction(Task=61) that follows every {7D}.
	if _show_graphic != null:
		_show_graphic.tick()

	# {78} Display Conditions — advance the banner / results screen one vsync. Like
	# {76}, it ticks outside the halt gate so the screen plays in full while the VM
	# parks on the {E5} Wait For Instruction(Task=56) that follows every {78}.
	if _results_screen != null:
		_results_screen.tick()
	# {91} Show Map Title — advance the location-name strip's reveal/hold/erase
	# one frame. LOAD-BEARING: the {91} handler parks the main context on this
	# effect, so this tick must run every non-paused frame (outside the halt gate)
	# for the L->R reveal + erase to complete and RELEASE that wait. Do not gate it
	# behind the dispatch/halt state or the block would deadlock until the watchdog.
	if _map_title != null:
		_map_title.tick()

	# {1A} Map Darkness oxide fade — like Reveal, ticks independently of the VM
	# halt/dispatch gate so the darken/untint completes even while opcode dispatch
	# pauses on a dialog or unhandled opcode.
	if _oxide_remaining_ticks > 0:
		_oxide_remaining_ticks -= 1
		var ox_frac := 1.0 - (float(_oxide_remaining_ticks) / float(_oxide_duration_ticks))
		_oxide_current_byte = _oxide_start_byte.lerp(_oxide_target_byte, ox_frac)
		if _oxide_remaining_ticks == 0:
			_oxide_current_byte = _oxide_target_byte

	# {32} Color Unit palette-tint ramps — tick each in-flight tint and re-push
	# it to the unit shader. Like the reveal/oxide fades above, this runs outside
	# the VM halt gate so a tint set right before a dialog/unhandled-opcode wall
	# still finishes its ramp.
	for uid in actors:
		var tint: ScenarioColorTint = (actors[uid] as ScenarioActor).tint
		if tint != null and tint.tick():
			_apply_unit_tint(uid, tint)

	# {43} Call Function 4 dead-unit fade — sequence pass 1 -> pass 2 -> remove for
	# each swept corpse now that this frame's tint ramps (above) have advanced.
	# Outside the halt gate like the tint ramps: the fade plays through the VM's
	# own 120-frame yield that `_begin_dead_unit_fade` armed.
	_advance_dead_unit_fades()

	# {33} Color Field whole-scene fade — advance the single global tint ramp and
	# re-push it to every unit (composed with each unit's own tint) + the map
	# palette. Same halt-gate exemption as the oxide/Color-Unit fades above: the
	# prayer untint set right before a Display Message wall must still converge.
	if _field_tint != null and _field_tint.tick():
		_apply_field_tint_to_all()

	# {2E} Background gradient ramp — advance the storm-sky/lightning-flash quad and
	# re-push its corners. Same halt-gate exemption as the fades above: the flash
	# ramp (armed by a {2E} then immediately walled by a {F1} Wait) must keep
	# converging frame-for-frame with the paired {33} map-hue ramp.
	if _background != null and _background.tick():
		_apply_screen_background()

	# {6B}/{6A} BG Sound volume ramps — advance each live ambient's linear fade and
	# push the new volume to its SPU voices. Outside the halt gate (like the fades
	# above): the PSX ramp is a cooperative task that keeps stepping every frame
	# regardless of what the main interpreter is waiting on, so the rain fade-in at
	# scenario-4 PC 5 completes even while the VM sits on a later opcode.
	if not _bg_sounds.is_empty():
		for sid in _bg_sounds:
			var bg: ScenarioBgSound = _bg_sounds[sid]
			if bg.tick():
				_world.set_bg_sound_volume(bg.handle, bg.vol)

	# Overlay typewriter reveal — pumped from the VM's 60 Hz logical tick (one
	# _tick_once ↔ one console VBlank), NOT the host render rate, so the prayer
	# types out refresh-independently. Ticked alongside the fades above (outside
	# the _running/paused gates) so the reveal keeps advancing even while opcode
	# dispatch is halted on a wait/unhandled opcode — matching PSX, where the
	# typewriter runs off the frame-sync interrupt independent of event dispatch.
	if dialogue_overlay != null and dialogue_overlay.has_method("is_active") \
			and dialogue_overlay.is_active():
		dialogue_overlay.advance_frames(1)


## Force EVERY in-flight time-driven screen/colour effect to its settled end-state in
## one shot — the "all pre-battle scenario effects are resolved before the battle
## starts" guarantee. Its complement: `_tick_time_driven_effects` advances these ramps
## ONE frame at a time OUTSIDE the dispatch halt gate, so on the 1× linear walk they
## always tick to completion before combat. But a direct combat SEEK fast-forwards the
## group's opener at 30× and parks the instant the opcode stream hits end-of-script —
## a ramp armed by one of the LAST opcodes (a {33} Color Field sepia wash, {1A} Map
## Darkness, {2E} Background, the {Reveal} fade, {76}/{3E}/{7D}/{91} overlays, a
## {6B} BG-sound fade) has no following Wait to tick against, so the stream ends with
## it mid-flight and the wash lingers into combat. Each effect snaps to its COMMITTED
## TARGET (never neutral — combat inherits the committed palette, see
## WITHIN_GROUP_MEMBER_TRANSITION.md); every snap mirrors ticking the effect to its
## final frame, and is a no-op when nothing is ramping — so this is safe to call
## unconditionally right before combat. Called by NavigatorMain.run_combat.
func settle_screen_effects() -> void:
	# Clear any leftover fast-play/park halt so the VM's persistent time-driven overlays
	# (weather rain above all, plus any still-ramping BG-sound fade) keep advancing THROUGH
	# the battle. Combat runs on this same live world (decision #180) via a bare CombatLoop
	# and NEVER calls `start()`, so — unlike the reused victory beat, whose `start()` clears
	# the pause (ScenarioStartClearsPauseTest) — a seek's opener fast-forward would otherwise
	# leave `_paused = true` here (`_finish_fast_play`), and `_tick_once`'s `if not paused`
	# gate would freeze the rain the instant combat began. Combat is live gameplay, not a
	# debug freeze-frame; un-pause so the overlays stay alive. Silent internal write.
	_paused = false
	# {Reveal} fade → fully revealed (alpha 0 = the settled end-state).
	if _reveal_remaining_ticks > 0:
		_reveal_remaining_ticks = 0
		_apply_fade_alpha(0.0)
	# {1A} Map Darkness oxide → its target byte (also frees the darkscreen liveness poll).
	if _oxide_remaining_ticks > 0:
		_oxide_remaining_ticks = 0
		_oxide_current_byte = _oxide_target_byte
	# {76} Dark Screen mosaic → established / retracted terminal.
	if _dark_screen != null:
		_dark_screen.settle()
	# {3E} Color Screen full-screen ramp → end colour.
	if _color_screen != null:
		_color_screen.settle()
	# {7D} Show Graphic → faded away.
	if _show_graphic != null:
		_show_graphic.settle()
	# {78} Display Conditions → the screen finished and cleared.
	if _results_screen != null:
		_results_screen.settle()
	# {91} Show Map Title → erased.
	if _map_title != null:
		_map_title.settle()
	# {32} Color Unit per-unit tint ramps → committed target.
	for uid in actors:
		var tint: ScenarioColorTint = (actors[uid] as ScenarioActor).tint
		if tint != null and tint.is_ramping():
			tint.resolve()
			_apply_unit_tint(uid, tint)
	# {33} Color Field whole-scene tint ramp → committed target (the sepia/hue wash).
	if _field_tint != null and _field_tint.is_ramping():
		_field_tint.resolve()
		_apply_field_tint_to_all()
	# {2E} Background gradient ramp → target corners.
	if _background != null and _background.settle():
		_apply_screen_background()
	# {6B}/{6A} BG-sound volume ramps → target volume.
	if _world != null:
		for sid in _bg_sounds:
			var bg: ScenarioBgSound = _bg_sounds[sid]
			if bg.settle():
				_world.set_bg_sound_volume(bg.handle, bg.vol)


func _tick_once() -> void:
	# Time-driven visual ramps (fades, weather, mosaic, graphic, oxide, unit/field
	# tints, background, BG-sound, overlay typewriter) advance OUTSIDE the dispatch
	# halt gate so they finish even when the VM stops on an unhandled opcode or
	# sits on a wait — but a debug `paused` park FREEZES them all here, in ONE
	# place, so a parked frame is a true PSX-comparable freeze-frame (no reveal
	# fade creeping forward while the user beat-compares). See
	# `_tick_time_driven_effects`. A fast-play clears `paused`, so effects still
	# advance to the target beat and then freeze once it parks.
	if not paused:
		_tick_time_driven_effects()

	# Halted-on-unhandled-opcode + active fast-play (rewind/step) → revive the
	# dispatcher so the run advances past the halt instead of doing nothing. The
	# unhandled opcode itself is treated as step-overable inside the dispatch loop
	# below (play-through skip is forced on during a fast-play). Without this
	# revival, the only way past a Display Message wall is the Skip Halt button.
	var main_ctx: ScriptContext = _contexts[0] if not _contexts.is_empty() else null
	if not _running and _ff_active and main_ctx != null and main_ctx.pc < _insts.size():
		_running = true

	if not _running:
		return

	# Cinematic walkers tick independently of the wait gate so units keep
	# animating during camera-lerp wait holds. Frozen by `paused` so the F3
	# debug panel can scrub frames without time advancing; a fast-play (rewind /
	# step) clears `paused`, so walker ticks resume alongside opcode dispatch.
	if not paused:
		_tick_cinematic_walkers()
		_tick_unit_rotations()
		_tick_field_objects()

	# Boxed-dialog advance gate — holds ONLY the context that raised it (the
	# script thread sitting on `Wait For Instruction`), NOT the whole VM. PSX
	# *input* is global (you can't advance two boxes at once), but a Display
	# Message is just an overlay: parallel block coroutines keep running, so a
	# unit's staged entry (Sprite Move → Walk To) finishes WHILE the box is on
	# screen. Freezing every context here was the chapel "Ramza kneels for a
	# split second then slides into his seat" bug — his entry block (block@115)
	# was frozen mid-walk by main's dialogs, then dispatched its Walk To *after*
	# the PC 155 kneel, exiting cinematic mode and sliding him. The box keeps
	# typing via its own clock; `_advance_dialog` (input) or the auto-advance
	# dwell releases the owning context. (`_dialog_gate_ctx` is skipped in the
	# round-robin below.)
	if _dialog_gate_active:
		_tick_dialog_gate()

	# Pause gate (debug-panel toggle). A fast-play (rewind / step) clears `paused`
	# while it runs, so this only halts dispatch when the user has genuinely
	# paused. Camera lerp + reveal fade keep running independently (above).
	if paused:
		return

	# A back-jump loop with no Wait in it would spin `_drain_context` forever with
	# nothing on screen changing and nothing in the log — the one failure mode the
	# jump family adds that the rest of the dispatch table cannot. The budget is
	# per TICK, so an ordinary loop that waits each pass is unaffected. See
	# `_jump_to_label`.
	_back_jumps_this_tick = 0

	# Round-robin every live context. Each context drains opcodes until it
	# either hits a wait, terminates, or runs out of instructions.
	# Iterate over a snapshot of the array — `_op_block_start` may append new
	# contexts mid-tick, and PSX semantics say the freshly-spawned block also
	# starts running in the SAME vsync (verified live in
	# BLOCK_EXECUTION_INVESTIGATION.md, vsync=409). So after the main pass we
	# keep draining until no new contexts appear.
	_vm_tick += 1

	# Drive var 87 — the prayer-scene frame counter that `Wait Value` polls. The
	# ROM has a background event coroutine doing a resolver-mediated Add(87,+1)
	# each frame (the prayer animation); the exact producer isn't isolable from
	# static disasm (readers doc §1 "Still open"), so we model it here: +1 per VM
	# tick, BEFORE the round-robin drain so a barrier armed this tick polls the
	# updated value. `Zero(87)` (pc 319) resets it; the two `Wait Value(87,28)` /
	# `(87,30)` barriers in the prayer block then release 28 / 30 ticks later.
	# Generalise to other counter vars only if a future scenario needs it.
	vars_store.set_var(87, _var_get(87) + 1)

	var visited: Dictionary = {}
	while true:
		var made_progress := false
		for ctx in _contexts:
			if visited.has(ctx):
				continue
			visited[ctx] = true
			made_progress = true
			if not ctx.alive:
				continue
			# Dialog gate holds ONLY its owning context; siblings keep draining
			# so unit-entry coroutines finish while a box is shown (see above).
			if _dialog_gate_active and ctx == _dialog_gate_ctx:
				continue
			if ctx.wait_ticks > 0:
				ctx.wait_ticks -= 1
				if ctx.wait_ticks > 0:
					continue
				# Wait just expired THIS tick — fall through and dispatch the next
				# opcode now, not next tick. PSX `Wait N` resumes on frame N, not N+1:
				# scn6 ground truth (tools/record_carry_timeline.gd vs the PSX anim-id
				# poll) shows Wait T=6 spans exactly 6 vsyncs between anim onsets, while
				# blocking the tick it hits zero made Godot span 7 — a +1-frame-per-Wait
				# error that accumulated to ~+8% pace drift over the carry cinematic.
				# [scn6 pace-align 2026-07-07]
			if ctx.wait_until.is_valid() and _hold_wait_until(ctx):
				continue
			if ctx.pc >= _insts.size():
				ctx.alive = false
				continue
			_drain_context(ctx)
			# Bail out of the whole tick early if dispatch flipped a VM-level
			# halt (unhandled opcode without skip-policy, pause budget exhausted)
			# — the next tick picks up where we left off. The dialog gate does
			# NOT bail the tick: it only parks its owner (skipped above), letting
			# sibling coroutines run on in this same tick.
			if not _running:
				break
			if paused:
				break
		if not made_progress:
			break
		if not _running:
			break
		if paused:
			break

	# Reap dead contexts at end of tick so the next tick's snapshot is clean —
	# EXCEPT the main context, which is never reaped.
	#
	# `_contexts[0] is the main thread` is a load-bearing IDENTITY, relied on by 13
	# call sites: `_op_block_end` ("am I a coroutine? then terminate"), `_op_event_end`
	# (`was_main` gates the `group_finished` emit the navigator walks on),
	# `_child_blocks_drained` (excludes main from the drain quorum), the fast-play
	# targeting, and every `get_pc()`-style readout. Compacting the array BREAKS that
	# identity the moment main dies while a block is still live: index 0 silently
	# becomes a surviving block, and then
	#   - Block End no longer terminates that block — it runs on past the end of its
	#     body into whatever bytecode follows, re-dispatching main's tail;
	#   - a block's Event End reports itself as main and emits `group_finished`,
	#     advancing the scenario walk from a sub-fiber;
	#   - `_child_blocks_drained` excludes the wrong context from its own quorum.
	# A dead main costs one `if not ctx.alive: continue` per tick in the round-robin.
	# Found via ScenarioVarWaitValueTest, whose fixture outlives its main thread: the
	# block re-dispatched the main-thread marker opcode and never printed its own
	# "done @pc (Block End)".
	var live: Array = []
	for i in _contexts.size():
		var ctx: ScriptContext = _contexts[i]
		if i == 0 or ctx.alive:
			live.append(ctx)
	_contexts = live


## Register an event-instruction handler keyed by opcode byte. `instruction` is
## an [EventInstruction] enum member (whose underlying int IS the byte); a typo
## at a call site is a GDScript parse error. ADR-0059.
func _bind(instruction: int, handler: Callable) -> void:
	_handlers[instruction] = handler


## Register an opcode as intentionally unhandled: it dispatches to `_op_skip`
## (print + return; pc is already advanced at the dispatch site) and records the
## reason. Keeps the byte key present so it clean-skips instead of hitting the
## null-handler halt path — and so the coverage check counts it as covered.
func _skip(instruction: int, reason: String) -> void:
	_handlers[instruction] = Callable(self, "_op_skip")
	_skip_reasons[instruction] = reason


## `verified:true` catalog opcodes that are neither bound nor skipped in the
## registrar — they would HALT the VM if reached. The coverage test asserts this
## is empty and the boot `push_warning` reminds softly. ADR-0059.
func unbound_verified_opcodes() -> Array:
	var out: Array = []
	var descriptors: Dictionary = EventInstructionSet.all()
	for op in descriptors:
		if descriptors[op].get("verified", false) and not _handlers.has(op):
			out.append(op)
	out.sort()
	return out


# Drain a single context's opcode stream until it hits a wait, terminates, or
# the VM-level gates (running / dialog / pause) demand a yield.
func _drain_context(ctx: ScriptContext) -> void:
	while _running and ctx.alive and ctx.wait_ticks == 0 \
			and not ctx.wait_until.is_valid() \
			and not (_dialog_gate_active and ctx == _dialog_gate_ctx) \
			and ctx.pc < _insts.size() \
			and not (_ff_active and ctx.label == "main" and ctx.pc >= _ff_target_pc):
		var inst = _insts[ctx.pc]
		var name := str(inst.get("name", "Unknown"))
		# Debug event-toggle: a PC the user switched OFF in the F3 panel skips like a
		# clean no-op (advance PC, no dispatch) so the scenario can be A/B'd with any
		# event removed. Checked before the handler lookup so disabling an unhandled
		# opcode also clean-skips it. Re-checks the while guard on `continue`, so a
		# skip that lands on the fast-play target PC still halts the rewind there.
		if not disabled_pcs.is_empty() and disabled_pcs.has(ctx.pc):
			print("[ScenarioVM] event DISABLED — skip '%s' @pc=%d (ctx=%s)" % [name, ctx.pc, ctx.label])
			ctx.pc += 1
			continue
		# The three terminators ({DB} Event End / {E3} Event End 2 / {2B} Block End)
		# are now enum-keyed handlers (_op_event_end / _op_block_end) that set
		# `ctx.alive = false`; the drain loop exits on that guard next check. The
		# handler path's pc += 1 is harmless on a now-dead context (it never reads
		# _insts[pc] again). ADR-0059.
		var handler = _handlers.get(int(inst.get("opcode", -1)), null)
		if handler == null:
			# A fast-play (rewind / step) forces `play_through_skip_unknown` on,
			# so this branch makes Step a smooth step-over of unhandled opcodes
			# rather than a button that silently stalls at every Display Message.
			if play_through_skip_unknown:
				print("[ScenarioVM] skip unhandled '%s' @0x%X (pc=%d, ctx=%s)" %
					[name, int(inst.get("offset", 0)), ctx.pc, ctx.label])
				ctx.pc += 1
				_emit_chapel_trace_row(ctx.pc - 1, inst, false)
				continue
			push_warning("[ScenarioVM] stopping at unhandled opcode '%s' at offset 0x%X (pc=%d, ctx=%s)" %
				[name, int(inst.get("offset", 0)), ctx.pc, ctx.label])
			_running = false
			return
		ctx.pc += 1
		_current_ctx = ctx
		handler.call(inst)
		# Chapel-trace burn-through: drain in-flight rotation steppers to
		# target BEFORE emitting the trace row, so the snapshot reflects the
		# end-of-rotate state PSX would render after the cinematic Wait
		# that normally follows a Rotate Unit. Without this drain, the
		# burn-through (which zeroes `wait_ticks`) skips every per-tick
		# step and every rotate appears to no-op in the trace.
		if DebugConfig.chapel_trace_enabled:
			_drain_unit_rotations_to_target()
			# Same burn-through for {28} Walk To + {3B}/{6E} Sprite Move: the trace
			# zeroes the {29}/{6F} wait barriers, so without snapping the in-flight
			# motions the row would sample units still sliding / at the entry column.
			_drain_motions_to_target()
			# Same burn-through for {11}/{8C} Unit Anim: the anim now LATCHES at
			# dispatch and paints on the next elapsed tick (the pending-anim latch,
			# §8i). The trace zeroes the following Wait, so without draining the
			# latch here the row would snapshot the STALE pose. Paint it so the trace
			# reflects the end-state PSX renders after the Wait — matching the
			# rotation/motion drains above.
			_consume_pending_body_anims()
		_emit_chapel_trace_row(ctx.pc - 1, inst, true)
		# Chapel-trace burn-through: when the trace is on we want the per-opcode
		# table without paying real-time for every Wait/camera-lerp. The post-state
		# snapshot is already in the JSONL above; cancel any wait the handler
		# armed so the next opcode dispatches next host frame.
		if DebugConfig.chapel_trace_enabled and ctx.wait_ticks > 0:
			ctx.wait_ticks = 0
		# Same burn-through for a `wait_until` predicate barrier — the trace's
		# rotation/walk drain above already satisfied it, so release immediately.
		if DebugConfig.chapel_trace_enabled and ctx.wait_until.is_valid():
			ctx.wait_until = Callable()
		# A fast-play (rewind / step) stops the main context exactly at
		# `_ff_target_pc` via the loop guard above — no per-opcode snap. In-flight
		# motion from each dispatched opcode plays out through `_advance_frame`
		# (fast) instead of being collapsed to its endpoint.
		if ctx.wait_ticks > 0:
			# Wait opcode just armed — yield to next tick.
			return
		if ctx.wait_until.is_valid():
			# Predicate barrier just armed — yield; the tick gate re-polls it.
			return


## Evaluate a context's `wait_until` predicate barrier for this tick. Returns
## true if the context must keep holding (predicate not yet satisfied), false
## once released — either because the predicate returned true or the watchdog
## deadline passed. Clears `wait_until` on release. Mirrors the PSX yield+poll
## loop (e.g. {64}'s FUN_801498fc spinning on the +4 active flag each frame).
func _hold_wait_until(ctx: ScriptContext) -> bool:
	if ctx.wait_until.call():
		ctx.wait_until = Callable()
		ctx.wait_until_progress = Callable()
		return false
	# Progress-aware watchdog: an advancing barrier (probe value changing) is not a
	# deadlock, so keep pushing its deadline forward. Only a probe that STALLS for a
	# full watchdog window force-releases.
	if ctx.wait_until_progress.is_valid():
		var p: int = int(ctx.wait_until_progress.call())
		if p != ctx.wait_until_last_progress:
			ctx.wait_until_last_progress = p
			ctx.wait_until_deadline_tick = _vm_tick + ctx.wait_until_watchdog_ticks
	if _vm_tick > ctx.wait_until_deadline_tick:
		push_warning("[ScenarioVM] wait_until watchdog fired (pc=%d, ctx=%s) — force-releasing after %d ticks" %
			[ctx.pc, ctx.label, ctx.wait_until_watchdog_ticks])
		ctx.wait_until = Callable()
		ctx.wait_until_progress = Callable()
		return false
	return true


## Arm a predicate barrier on `ctx`: hold the context (re-polling `pred` each
## tick) until it returns true or the watchdog deadline passes. See
## `_hold_wait_until`. Deadline is anchored to the current `_vm_tick`. The
## `watchdog_ticks` budget defaults to the 10 s rotation/walk ceiling; pass a
## larger value for legitimately long holds (e.g. the prayer overlay's ~10 s
## typewriter, which would otherwise trip the default watchdog).
func _arm_wait_until(ctx: ScriptContext, pred: Callable,
		watchdog_ticks: int = _WAIT_UNTIL_WATCHDOG_TICKS,
		progress: Callable = Callable()) -> void:
	ctx.wait_until = pred
	ctx.wait_until_watchdog_ticks = watchdog_ticks
	ctx.wait_until_deadline_tick = _vm_tick + watchdog_ticks
	ctx.wait_until_progress = progress
	ctx.wait_until_last_progress = int(progress.call()) if progress.is_valid() else 0


# --- Helpers -----------------------------------------------------------------

## Point this VM at a shared game-variable store (ADR-0179). The navigator hands it
## `Campaign`'s, so a scenario's `Zero(110); Add(110, k)` advances the world map's story
## counter — which is how the ROM does it, and the only way the campaign loop closes.
## Never null: passing null is a no-op, so a mis-wire degrades to the private store rather
## than crashing mid-scene.
func set_variable_store(store: WorldMapVariables) -> void:
	if store == null:
		push_warning("[ScenarioVM] set_variable_store(null) ignored — keeping the private store")
		return
	vars_store = store


## Read a game variable. Unread ids read 0.
func _var_get(id: int) -> int:
	return vars_store.get_var(id)


# --- Single-unit resolution ---------------------------------------------------
#
# `Units`/`Multi` are NOT a split u16 unit id — they are the multi-unit broadcast
# SELECTOR (EVENT_UNIT_SET_RESOLUTION.md). `Multi != 0` rows (scenario 1 has 8:
# 0x012E, 0x013A, 0x0125, 0x0136, 0x012C, …) are TEAM-SET broadcasts, resolved by
# `ScenarioWorld.resolve_unit_set` — NOT by this function. This resolves the SINGLE
# unit `Units` names when `Multi == 0` (and the id-typed operands of Face Unit /
# Remove / etc.), including the ≥0x80 special-id and Focus/Ghost paths.

# Resolve a unit by its id, falling back to the low byte when only the u8 key is
# present (ENTD-spawned units are u8-keyed; a u16-typed operand may carry a high
# byte). Returns -1 if no match — callers should `push_warning` with their context.
func _resolve_unit_key(chunk_unit_id: int) -> int:
	if units_by_id.has(chunk_unit_id):
		return chunk_unit_id
	var lo := chunk_unit_id & 0xFF
	if lo != chunk_unit_id and units_by_id.has(lo):
		return lo
	return -1


# Resolve the rotate-target 12-bit angle from the Facing byte's mode-dispatch
# table — pure decode, lives in ScenarioDecode. `current_12bit`/`camera_yaw_12bit`
# are the apply-time reads the handler supplies (see ScenarioDecode for the mode
# table). Mode 0x14 (face-target) falls back to "no change" here.
func _resolve_rotate_target_12bit(facing_byte: int,
		current_12bit: int, camera_yaw_12bit: int) -> int:
	return ScenarioDecode.resolve_rotate_target_12bit(
		facing_byte, current_12bit, camera_yaw_12bit)


func _s16(v: int) -> int:
	return PsxNum.s16(v)


# --- Handlers ----------------------------------------------------------------

func _op_noop(_inst: Dictionary) -> void:
	pass


func _op_skip(inst: Dictionary) -> void:
	print("[ScenarioVM] skip %s @0x%X params=%s" %
		[inst.get("name"), int(inst.get("offset", 0)), inst.get("params", [])])


## {DB} Event End / {E3} Event End 2 — the script terminators. Both end the chunk
## from the data's perspective (PSX: {DB} is a per-unit palette-restore pass that
## falls off into the interpreter's default fiber-stop; {E3} drains pending FX +
## child blocks then hard-terminates). End the CURRENT context with NO
## unhandled-opcode warning; the drain loop exits on `alive = false`. The pc has
## already advanced past the terminator, which is harmless on a dead context.
## Live-validated RE: FOCUS_OPCODE_1F_INVESTIGATION.md §5/§6/§8.
func _op_event_end(inst: Dictionary) -> void:
	print("[ScenarioVM] %s: event script complete @pc=%d (%s)" %
		[_current_ctx.label, _current_ctx.pc - 1, inst.get("name", "Event End")])
	var was_main: bool = not _contexts.is_empty() and _current_ctx == _contexts[0]
	_current_ctx.alive = false
	# The MAIN context finishing is the scenario chunk finishing — the navigator
	# yields on this to advance the walk (decision #179). A child block coroutine's
	# Event End is just a sub-fiber terminating, not the group ending.
	if was_main:
		group_finished.emit(current_scenario_id)


## {2B} Block End — in a parallel (block) context it terminates the coroutine
## (PSX FUN_8014c958). The main context shouldn't normally hit Block End
## (`_op_block_start` advances main past it); if it ever does, this is a no-op
## (the block spawn already carried main forward). Was the name-string terminator
## special-case before ADR-0059 folded it here.
func _op_block_end(_inst: Dictionary) -> void:
	if _current_ctx != _contexts[0]:
		print("[ScenarioVM] %s done @pc=%d (Block End)" % [_current_ctx.label, _current_ctx.pc - 1])
		_current_ctx.alive = false


func _op_sound_effect(inst: Dictionary) -> void:
	ScenarioApply.sound_effect(ScenarioDecode.sound_effect(EventInstructionSet.args(inst)), _world)


## {60} Fade Sound — fade the active music to silence. See the dispatch-table
## comment + FADESOUND_OPCODE_60_INVESTIGATION.md. Mirrors the PSX flush math:
## the handler latches `Time << (16+Shift)`, the flush extracts ramp ticks as
## `(word >> 14) & 0x3FFC` = `(Time << (Shift+2)) & 0x3FFC`.
func _op_fade_sound(inst: Dictionary) -> void:
	ScenarioApply.fade_sound(ScenarioDecode.fade_sound(EventInstructionSet.args(inst)), _world)


## {22} Switch Track — toggle between the scenario's two ATTACK.OUT songs.
## See the dispatch-table comment + HANDOFF_switch_track_opcode.md. Decompiler
## ticker (`battle_decompilation.c:50595`):
##   if (-1 < fc8) {                      # track byte: enabled gate (value unused)
##       stop_current();
##       fd8 ^= 1;                         # flip toggle
##       arm = (fd8 == 0) ? fd4 : fd6;     # per-slot arm flag
##       if (arm != 0)                     # unloaded slot → no-op
##           switch(fd8 + 1, transform(Volume), Time << 2);
##   }
## Volume curve is FFT `FUN_8012db90`: 0→0, ≥96→127, else Volume*127/96 (the
## decompiler is authoritative over the wiki's naive-linear description). ticks
## = Time*4 sequencer ticks, same unit as {60}.
func _op_switch_track(inst: Dictionary) -> void:
	var intent := ScenarioDecode.switch_track(EventInstructionSet.args(inst))
	# Flip the toggle and select the OTHER slot's song (slot = toggle+1). The
	# toggle is VM-side scheduler state (ADR-0058); decode owns only the volume
	# curve + tick math.
	_track_toggle ^= 1
	var song_id := music_slot_two_id if _track_toggle == 1 else music_slot_one_id
	# Per-slot arm gate: an unloaded slot (id 0) makes the switch a no-op,
	# matching the PSX `if (arm != 0)` guard. Leaves the toggle flipped so the
	# next {22} still alternates (the PSX flips fd8 before the gate too).
	if song_id == 0:
		return
	_world.switch_music_track(song_id, intent.target_vol, intent.ticks)


## {6B}/{6A} operands are read POSITIONALLY through the reader, not by name: the
## two opcodes share one byte layout — [Sound, StartVol, Volume, Stacking, Time] —
## despite the catalog naming op[1] "Echo" (it's the ramp StartVol, doc §4) and
## giving {6A} TWO operands both named "Unknown". The name-keyed `_params_dict`
## collapsed {6A}'s dup "Unknown", losing an operand; EventInstructionArgs.nth
## reads by position, so the collapse can't happen (ADR-0059 Phase 2).


## {6B} BG Sound — play an env-bank ambient (handle 0x10000|Sound on PSX) and run
## a linear volume ramp StartVol→Volume over Time frames (fire-and-forget; the
## ramp ticks in `_tick_once`). Stacking=0 = the tracked/replaceable background
## channel; ≠0 = an overlay voice. Re-triggering the same Sound stops the prior
## instance first. See the dispatch-table comment + the {6B} investigation doc.
func _op_bg_sound(inst: Dictionary) -> void:
	var intent := ScenarioDecode.bg_sound(EventInstructionSet.args(inst))
	# A re-triggered Sound replaces its prior ScenarioBgSound (play_bg_sound stops
	# the old voices first), so drop any stale ramp for this id. The ramp registry
	# is VM-side scheduler state (ADR-0058); the SPU access goes through _world.
	_bg_sounds.erase(intent.sound_id)
	var handle: int = _world.play_bg_sound(intent.sound_id, intent.stacking)
	print("[ScenarioVM] BG Sound id=0x%02X '%s' start=%d vol=%d stack=%d time=%d handle=%d" %
		[intent.sound_id, _SfxCatalog.name_for("env", intent.sound_id),
		intent.start_vol, intent.target_vol, intent.stacking, intent.time, handle])
	if handle == 0:
		return  # backend miss (no SPU / bad id) — nothing to ramp
	var bg := ScenarioBgSound.new()
	bg.sound_id = intent.sound_id
	bg.stacking = intent.stacking
	bg.loop = _SfxCatalog.is_loop("env", intent.sound_id)
	bg.handle = handle
	bg.start_ramp(intent.start_vol, intent.target_vol, intent.time)
	_bg_sounds[intent.sound_id] = bg
	# Push the initial volume this frame (mirrors the PSX pre-ramp set-volume).
	_world.set_bg_sound_volume(handle, bg.vol)


## {6A} Edit BG Sound — re-ramp an ALREADY-PLAYING bg sound's volume
## (StartVol→Volume over Time), with NO re-trigger. If the sound isn't currently
## playing there's nothing to edit → no-op (matches the PSX ramp worker running
## against a handle whose voices are silent).
func _op_edit_bg_sound(inst: Dictionary) -> void:
	var intent := ScenarioDecode.bg_sound(EventInstructionSet.args(inst))
	var bg: ScenarioBgSound = _bg_sounds.get(intent.sound_id)
	if bg == null:
		return
	# start_vol/target_vol/time are op[1]/op[2]/op[4] (the SECOND {6A} "Unknown"
	# the old name-keyed read collapsed away). Stacking (op[3]) isn't re-applied.
	print("[ScenarioVM] Edit BG Sound id=0x%02X start=%d vol=%d time=%d handle=%d" %
		[intent.sound_id, intent.start_vol, intent.target_vol, intent.time, bg.handle])
	bg.start_ramp(intent.start_vol, intent.target_vol, intent.time)
	_world.notify_bg_sound_changed("edit", intent.sound_id, bg.stacking, bg.handle)
	_world.set_bg_sound_volume(bg.handle, bg.vol)


## {7C} End Sound — stop the currently-playing event SFX/BGM (PSX SUB_800440cc:
## clear the active-sound handle DAT_8004599c + 8-voice teardown FUN_80012860).
## Placed at the scenario tail before the battle hand-off. See the dispatch-table
## comment + SCENARIO6_UNKNOWN_OPCODES_6D_71_7C_82_INVESTIGATION.md §4.
func _op_end_sound(_inst: Dictionary) -> void:
	# Drop every live {6B} bg ramp so it stops ticking against a torn-down voice.
	# The ramp registry is VM-side scheduler state (ADR-0058); the SPU teardown
	# itself goes through _world → SfxRouter.stop_all_event_sound().
	_bg_sounds.clear()
	ScenarioApply.end_sound(_world)


## Event-script `0x2A Block Start` handler.
##
## Wiki entry: "A block is a portion of the event played in a separate
## process. When the game finds a block, it will start executing it and will
## also resume the event whatever there is after the block at the same time."
##
## PSX implementation (BLOCK_EXECUTION_INVESTIGATION.md, verified live
## vsync=409 on the chapel chunk): `Block Start` allocates a free slot from
## PSX's 16-slot cooperative-coroutine table, plants the post-`0x2A` bytecode
## pointer in the new slot, registers the generic block-body interpreter
## (FUN_8013e904) as its entry, and the calling thread (main, or another
## block) scans forward to the matching `Block End` and continues past it.
##
## Godot mirror: append a new ScriptContext starting at the byte after this
## opcode, then scan forward (with a depth counter for nested Block Start /
## End brackets) and advance the CALLING context's PC past the matching Block
## End. The spawned context will start draining its bytecode on the next
## iteration of `_tick_once`'s round-robin loop — same vsync as the spawn,
## matching PSX's "main thread doesn't yield between back-to-back Block
## Starts" behavior.
##
## Note: `_current_ctx.pc` was already advanced past the Block Start opcode
## by the dispatcher, so the spawned context's starting PC == `_current_ctx.pc`
## at this moment — i.e., the first opcode INSIDE the block body.
func _op_block_start(inst: Dictionary) -> void:
	var calling_ctx := _current_ctx
	var body_pc := calling_ctx.pc
	var depth := 1
	var scan_pc := calling_ctx.pc
	while scan_pc < _insts.size():
		var name := str(_insts[scan_pc].get("name", ""))
		if name == "Block Start":
			depth += 1
		elif name == "Block End":
			depth -= 1
			if depth == 0:
				calling_ctx.pc = scan_pc + 1
				var child := ScriptContext.new()
				child.pc = body_pc
				child.label = "block@%d" % body_pc
				_contexts.append(child)
				print("[ScenarioVM] Block Start @0x%X (caller=%s) — spawned %s; caller resumes at pc=%d (Block End was pc=%d)" %
					[int(inst.get("offset", 0)), calling_ctx.label, child.label,
					 calling_ctx.pc, scan_pc])
				return
		scan_pc += 1
	# Unmatched Block Start — log + leave caller's PC alone so the VM keeps
	# executing the block's contents serially in the caller. That's wrong but
	# visible, and better than a silent infinite skip.
	push_warning("[ScenarioVM] Block Start @0x%X (caller=%s) — no matching Block End found; falling through serially" %
		[int(inst.get("offset", 0)), calling_ctx.label])


## Event-script `0x58 Load EVTCHR` handler.
##
## BATTLE.BIN's handler (at `0x80145414`) just queues the Slot halfword to
## `DAT_80165FCA`; an async worker (per-frame at `0x80143930`) reads it and
## triggers a CDROM-DMA of the selected EVTCHR segment into the cinematic
## block's RAM region (0x800A77D8 for Block 1 / 0x800AED3C for Block 2).
##
## Godot side just records the mapping — actual cinematic anim playback
## (`anim_id 0x1F4..0x297` lookup against `cinematic_seq.json`) is consumed
## by a future `_op_unit_anim` extension. The Slot → EVTCHR-segment
## indirection has not been fully traced yet (followup #1 in
## `cinematic_seq_source_decode.md`); for now we store the raw Slot value
## and let the consumer resolve it.
func _op_load_evtchr(inst: Dictionary) -> void:
	var a := EventInstructionSet.args(inst)
	ScenarioApply.load_evtchr(a.raw("Block"), a.raw("Slot"), _world)


## Event-script `0x97 Reset Palette` handler.
##
## PSX semantics:
##   - Opcode 0x97, 2 operand bytes (Unit halfword, little-endian) =
##     3 bytes per instruction. `event_opcode_operand_size_table[0x97]
##     = 2`, verified live.
##   - Handler is `FUN_8013e6c4` — synchronous, no `FUN_8014ca80`
##     yield. It reads exactly ONE halfword via `event_bytecode_reader_c`
##     (no `param+2` byte, matching the size table), resolves the unit via
##     `unit_id_validate_resolve` (0x7d0 = not deployed → no-op), and calls
##     `FUN_8008cd24` → `FUN_80081d54(sprite_obj, 0, 1)`, a palette/CLUT
##     rebuild keyed off the object's +5/+7 sprite-set fields (not itself
##     fully RE'd — out of scope for #68).
##   - Dispatch: guard `bne s4,v0 @0x80144878` (main) / `bne v1,v0
##     @0x8013eb04` (block); case bodies 0x80144880 / 0x8013eb0c.
##
## CORRECTION (2026-09-02, MIRROR_SPRITE_OPCODE_68.md §2.3): this docblock
## previously named `FUN_8013e65c` and described a "mode byte at param+2"
## writing `unit[+0x13F]`. That is `{68} Mirror Sprite`'s handler, not this
## one — the earlier pass read each `bne`'s DELAY-SLOT constant as its own
## operand, which shifts every case attribution by one. `FUN_8013e65c` reads
## 3 operand bytes (= size table `[0x68] = 3`) and `unit[+0x13F]` is the
## sprite flip_xor_mask, nothing to do with palettes. See `_op_mirror_sprite`.
##
## Godot mirror clears the unit's {32} tint state. The palette rebuild itself
## is implicit here (our tint model has no separate CLUT to restore).
func _op_reset_palette(inst: Dictionary) -> void:
	ScenarioApply.reset_palette(EventInstructionSet.args(inst).raw("Unit") & 0xFFFF, _world)


## Event-script `0x68 Mirror Sprite` handler.
##
## PSX semantics (`research/working_documents/MIRROR_SPRITE_OPCODE_68.md`):
##   - Opcode 0x68, 3 operand bytes {u16 Unit; u8 Mirror} = 4 bytes per
##     instruction (`event_opcode_operand_size_table[0x68] = 3`; all 62 corpus
##     sites decode as 4-byte raws).
##   - Handler `evt0x68_mirror_sprite_handler` @0x8013E65C. Resolves ONE unit
##     via `unit_id_validate_resolve` (0x7d0 = not deployed -> silent no-op) —
##     the single-unit resolver, NOT {2D}/{11}'s multi-selector, so Mirror
##     Sprite never broadcasts to a team set.
##   - `Mirror == 1` -> `unit[+0x13F] = 0x02`; anything else -> `0x00`. An
##     absolute latch, not a self-toggle: 16 corpus chunks set then clear the
##     same unit, and scenario 154 latches unit 130 on/off/on/off.
##   - THE COMPOSITION RULE: `unit[+0x13F]` is not the final flip. The render
##     dispatch computes `flip = render_flags(+0x12) ^ flip_xor_mask(+0x13F)`
##     (`xor` @0x80086764, and again @0x8007F374 for the translucent pass), and
##     `render_flags` is recomputed from the (camera yaw + unit facing) octant
##     every frame. So {68} XORs with the natural facing flip; it does not
##     override it. 0x02 is exactly render_flags' flip_horizontal bit.
##
## Godot mirror: `SpriteLayerManager` holds `_base_reversion` (the per-paint
## camera variant) and `mirror_xor` (this latch) apart and recomposes on either
## write, so the mirror survives `CinematicWalkState._apply_cinematic_reversion`
## recomputing the base flip on every EVTCHR frame.
func _op_mirror_sprite(inst: Dictionary) -> void:
	var a := EventInstructionSet.args(inst)
	ScenarioApply.mirror_sprite(a.raw("Unit") & 0xFFFF, a.raw("Mirror"), _world)


## Event-script Color Unit ({0x32}) — per-unit palette tint. The Orbonne door
## exit fires this per actor (Exit A: `Color=1,Time=0` snap-to-half then
## `Color=8,Time=2` ramp back to base; Exit B: single `Color=1,Time=2` darken).
## It is a TINT, not a hide — the sprite vanishes later via Erase Unit ({0x46}).
## Faithful decode + live capture: research/working_documents/
## UNIT_FADE_COLOR_UNIT_OPCODE.md. The tint math lives in ScenarioColorTint;
## here we just resolve the target unit, apply the op, and push to its shader.
func _op_color_unit(inst: Dictionary) -> void:
	ScenarioApply.color_unit(ScenarioDecode.color_unit(EventInstructionSet.args(inst)), _world)


## Push a unit's current tint (scale,bias affine) to its sprite shader. The
## unit shader applies `ALBEDO = ALBEDO * unit_tint_scale + unit_tint_bias`
## on the sampled palette colour (see addons/exmateria_sprite_rig/render/unit.gdshader). The per-unit
## {32} tint is COMPOSED with any active {33} Color Field broadcast so the two
## don't clobber each other's shader uniform — see `_compose_with_field`.
func _apply_unit_tint(uid: int, tint: ScenarioColorTint) -> void:
	if not units_by_id.has(uid):
		return
	var unit = units_by_id[uid]
	if unit == null or not is_instance_valid(unit):
		return
	# `get()` (not `.material`) so a non-visual node (e.g. a dispatch-test stub with
	# no `material` property) yields null and bails, rather than throwing.
	var mat = unit.get("material")
	if mat == null:
		return
	var eff := _effective_unit_tint(tint)
	# ADR-0067: fold the effective {32}∘{33} spec through the unified color stack
	# (unit.gdshader's color_apply). ScenarioColorTint still computes the spec
	# (timeline/DDA); _push_unit_color_stack translates it to color_layer_* uniforms.
	_push_unit_color_stack(mat, eff)


## Translate a unit's effective {32}∘{33} spec into the ≤2-layer color stack the
## unified shader folds, and push its color_layer_* uniforms (ADR-0067): the affine
## below (fully applied), then the luma at progress = the cross-fade weight — the
## mapping proven byte-exact against the PSX tint math by ColorStack.fold's parity
## oracle. No per-consumer quantize (luma quantizes internally; affine stays float).
func _push_unit_color_stack(mat, eff: Dictionary) -> void:
	var stack := ColorStack.new()
	stack.push_fixed_layer(ColorRecipe.affine(eff["scale"], eff["bias"]), 1.0)
	if int(eff["luma_div"]) > 0:
		var luma := ColorRecipe.luma(eff["luma_div"], eff["luma_delta5"], not eff["from_current"])
		stack.push_fixed_layer(luma, eff["luma_mix"])
	stack.apply(mat, 0)


## Compose a per-unit affine (scale,bias) with the active {33} Color Field
## broadcast affine, applied AFTER the unit tint (field ∘ unit): a base colour
## goes base → unit → field, i.e.
##   result = (base*unit_s + unit_b)*field_s + field_b
##          = base*(unit_s*field_s) + (unit_b*field_s + field_b).
## With no field active this returns the unit affine unchanged, and with an
## identity unit tint it returns the field affine — so a unit under only one of
## the two gets exactly that one. Returns [scale: Vector3, bias: Vector3].
func _compose_with_field(unit_scale: Vector3, unit_bias: Vector3) -> Array:
	if _field_tint == null:
		return [unit_scale, unit_bias]
	var fs := _field_tint.scale
	var fb := _field_tint.bias
	return [unit_scale * fs, unit_bias * fs + fb]


## Resolve the effective shader spec for a unit under its own {32} tint composed
## with the active {33} field. Returns a dict {scale, bias, luma_div, luma_delta5,
## from_current}. LUMA remaps every entry to a luminance scalar and cannot be an
## affine, so a luma tint wins over the affine path — and precedence follows the PSX
## per-palette-view last-write-wins order:
##   1. A unit's OWN {32} luma tint WINS over the {33} field. On PSX the {32} op
##      re-tints the unit's palette view AFTER the field broadcast (scn8 PC29 > PC28),
##      so view 3 (unit sprites) ends up with the unit-op's delta while view 0 (map)
##      keeps the field's. Letting the field override made every sprite render the
##      grayer field wash instead of its browner own — COLOR_TINT_LUMA_MODE_SEPIA.md §3.1/3.2.
##   2. Else a luma FIELD applies to this (un-luma'd) unit — a base-luma field (6/7)
##      reads raw albedo (affine bypassed/identity); a current-luma field (2/3) reads
##      the unit's {32} output, so its affine feeds the luma source via unit_tint_scale/bias.
##   3. Else both are affine → the existing field∘unit affine composition.
func _effective_unit_tint(tint: ScenarioColorTint) -> Dictionary:
	if tint.luma_div > 0:
		# The unit's affine (scale/bias) is the base it fades TO during a mode-8
		# restore cross-fade — normally identity, but pass it through faithfully.
		return {
			"scale": tint.scale,
			"bias": tint.bias,
			"luma_div": tint.luma_div,
			"luma_delta5": tint.luma_delta5,
			"from_current": not tint.luma_from_base,
			"luma_mix": tint.luma_mix,
		}
	if _field_tint != null and _field_tint.luma_div > 0:
		var from_current := not _field_tint.luma_from_base
		return {
			"scale": tint.scale if from_current else Vector3.ONE,
			"bias": tint.bias if from_current else Vector3.ZERO,
			"luma_div": _field_tint.luma_div,
			"luma_delta5": _field_tint.luma_delta5,
			"from_current": from_current,
			"luma_mix": _field_tint.luma_mix,
		}
	var sb := _compose_with_field(tint.scale, tint.bias)
	return {
		"scale": sb[0],
		"bias": sb[1],
		"luma_div": 0,
		"luma_delta5": Vector3i.ZERO,
		"from_current": false,
		"luma_mix": 1.0,
	}


## Event-script Color Field ({0x33}) — the whole-scene palette-content fade
## (the dominant Orbonne prayer darkening: every unit sprite AND the map palette
## darken, then untint when the prayer text clears). The BROADCAST sibling of
## {0x32} Color Unit — the same Color(mode)/RGB/Time affine, no per-unit target
## (PSX FUN_800933c4 takes the slot >= 0x10 broadcast path). Modelled faithfully
## in palette space: the affine is pushed to every unit's `unit_tint_scale`/
## `unit_tint_bias` (composed with any per-unit {32} tint) and to the map palette
## via `MapComposer.set_field_tint` — the same CLUT rewrite the PSX applier does
## per surface, NOT a screen filter. Coupling (untint follows the prayer Display
## Message advancing, §6.4) is automatic: the untint op dispatches only after the
## dialog gate releases, and the ramp ticks in _tick_once regardless of the halt
## gate. Decode: prayer_screen_tint_quad_decode.md §8.5-8.7.
func _op_color_field(inst: Dictionary) -> void:
	ScenarioApply.color_field(ScenarioDecode.color_field(EventInstructionSet.args(inst)), _world)


## Event-script {0x66} Commit Palette — bake the live {33} Color Field field-tint
## into the BASE map palette so it PERSISTS, then reset the transient field tint to
## identity. In scenario_004 PC12 {33} mode-4 (−3,−1,+3) tints the working CLUT
## blue and PC14 {0x66} commits it; without the commit a later flash's mode-8
## restore snapped the map back to the raw warm palette (the scenario-3/4/5/6
## map-hue bug). PSX FUN_8008f63c copies the working CLUT strip → base; the Godot
## analogue folds `_field_tint`'s (scale,bias) into MapComposer.palette_texture.
## The field then lives in the base, so we clear `_field_tint` and re-push identity
## to units + map — the flash restore now lands on the committed blue base.
## Decode: research/working_documents/MAP_HUE_WEATHER_STATE_CLUT_BAKE.md §0.
func _op_commit_palette(_inst: Dictionary) -> void:
	# The {66} commit bakes the SETTLED field tint. On PSX the pre-commit {E5}/wait
	# lets the {33} fade's DDA finish first, so the committed CLUT is always the ramp
	# TARGET. A fast-forward path-walk (or a ramp that outlasts its wait) can reach
	# here mid-fade; snap the ramp to its end-state so we bake the resolved colour,
	# not a half-faded frame (the scn10→11 "map is blue" bug — the fade to neutral
	# was committed at ~half progress). No-op when nothing is ramping.
	if _field_tint != null:
		_field_tint.resolve()
	var scale := _field_tint.scale if _field_tint != null else Vector3.ONE
	var bias := _field_tint.bias if _field_tint != null else Vector3.ZERO
	# Forward the FULL field spec so a luma {33} (sepia/grey wash) commits its wash,
	# not an identity affine — same spec set_field_color_stack broadcasts live.
	var div := _field_tint.luma_div if _field_tint != null else 0
	var delta5 := _field_tint.luma_delta5 if _field_tint != null else Vector3i.ZERO
	var from_current := _field_tint != null and not _field_tint.luma_from_base
	var mix := _field_tint.luma_mix if _field_tint != null else 1.0
	if map_composer != null and map_composer.has_method("commit_field_tint"):
		map_composer.commit_field_tint(scale, bias, div, delta5, from_current, mix)
	# The tint now lives in the committed base — drop the transient field tint and
	# re-push identity to every unit + the map palette.
	_field_tint = null
	_apply_field_tint_to_all()


## Broadcast the current global {33} field tint to every spawned unit (composed
## with each unit's own {32} tint via _apply_unit_tint) and to the map palette
## (MapComposer.set_field_tint → indexed_color.gdshader). With `_field_tint` null
## or identity this restores each unit to its own tint and the map to its base
## palette. Called on arm and on every ramp tick.
func _apply_field_tint_to_all() -> void:
	for uid in units_by_id:
		# Re-push each unit through its own {32} tint (identity if none), which
		# composes the live field affine on top — see _compose_with_field.
		var ua := peek_actor(uid)
		var unit_tint: ScenarioColorTint = ua.tint if ua != null else null
		if unit_tint == null:
			unit_tint = _identity_tint
		_apply_unit_tint(uid, unit_tint)
	# ADR-0067: broadcast the {33} field spec to the map's color stack (the map folds it
	# via color_apply). div == 0 is an affine field; div > 0 is the sepia/grey luma.
	if map_composer != null and map_composer.has_method("set_field_color_stack"):
		var scale := _field_tint.scale if _field_tint != null else Vector3.ONE
		var bias := _field_tint.bias if _field_tint != null else Vector3.ZERO
		var div := _field_tint.luma_div if _field_tint != null else 0
		var delta5 := _field_tint.luma_delta5 if _field_tint != null else Vector3i.ZERO
		var from_current := _field_tint != null and not _field_tint.luma_from_base
		# Cross-fade weight (1 = full sepia, 0 = base) drives the {33} mode-8 map restore.
		var mix := _field_tint.luma_mix if _field_tint != null else 1.0
		map_composer.set_field_color_stack(scale, bias, div, delta5, from_current, mix)


func _op_wait(inst: Dictionary) -> void:
	var t := EventInstructionSet.args(inst).raw("Time", 1)
	if play_through_skip_unknown and t > play_through_max_ticks:
		t = play_through_max_ticks
	_current_ctx.wait_ticks = t
	print("[ScenarioVM] Wait T=%d (ctx=%s)" % [t, _current_ctx.label])


## Event-script `0xBE Zero` writer — `vars[id] = 0`. Resets a counter/flag word.
## In the prayer scene the `Zero(87); Add(87, 0)` pair zeroes the frame counter
## as the sync point before the parallel rotate block. See
## `research/wiki_articles/event_instruction_b0_be_variable_math.md`.
func _op_var_zero(inst: Dictionary) -> void:
	var id := EventInstructionSet.args(inst).raw("Variable")
	vars_store.set_var(id, 0)
	print("[ScenarioVM] Zero var[%d] = 0" % id)


## The `0xB0`–`0xBD` arithmetic writers, keyed by the EVEN (immediate-operand)
## opcode of each pair → the op core it selects in ROM `FUN_8014a018`
## (`0x8014a12c` add · `a13c` sub · `a148` mult · `a170` div · `a190` mod ·
## `a1a8` and · `a1b4` or). The ODD sibling of each is the same op with a
## VARIABLE operand — `op & 0xFE` maps it back onto this table, which is exactly
## the ROM's own `andi op, 1` operand-mode test (writers doc §0).
##
## `0xBE Zero` is deliberately absent: it takes no operand and has its own
## handler, mirroring the ROM's `beq s2, 0xBE` early-out at `0x8014a048`.
const _VAR_MATH_OPS := {
	EventInstruction.ADD: "Add",             # 0xB0 / 0xB1
	EventInstruction.SUBTRACT: "Subtract",   # 0xB2 / 0xB3
	EventInstruction.MULTIPLY: "Multiply",   # 0xB4 / 0xB5
	EventInstruction.DIVIDE: "Divide",       # 0xB6 / 0xB7
	EventInstruction.MODULO: "Modulo",       # 0xB8 / 0xB9
	EventInstruction.AND: "AND",             # 0xBA / 0xBB
	EventInstruction.OR: "OR",               # 0xBC / 0xBD
}

## Every opcode `_op_var_math` answers — the even/odd pairs of [constant
## _VAR_MATH_OPS] expanded. Used by the registrar and by the coverage assertions.
const _VAR_MATH_OPCODES := [
	EventInstruction.ADD, EventInstruction.ADD_VARIABLE,
	EventInstruction.SUBTRACT, EventInstruction.SUBTRACT_VARIABLE,
	EventInstruction.MULTIPLY, EventInstruction.MULTIPLY_VARIABLE,
	EventInstruction.DIVIDE, EventInstruction.DIVIDE_VARIABLE,
	EventInstruction.MODULO, EventInstruction.MODULO_VARIABLE,
	EventInstruction.AND, EventInstruction.AND_VARIABLE,
	EventInstruction.OR, EventInstruction.OR_VARIABLE,
]

## The six `0xA0`–`0xA5` comparisons → their display name. All six share ROM
## handler `FUN_80149f10` and all six write their boolean back into var[0].
const _VAR_COMPARE_OPS := {
	EventInstruction.VARIABLE_LE: "<=",   # 0xA0
	EventInstruction.VARIABLE_GE: ">=",   # 0xA1
	EventInstruction.VARIABLE_EQ: "==",   # 0xA2
	EventInstruction.VARIABLE_NE: "!=",   # 0xA3
	EventInstruction.VARIABLE_LT: "<",    # 0xA4
	EventInstruction.VARIABLE_GT: ">",    # 0xA5
}

## The comparison ALU's two FIXED scratch operands — `[base + 0]` and
## `[base + 4]` in ROM (`0x8005771C` / `0x80057720`). The boolean result
## overwrites A, which is the word `0xD0 Jump Forward If Zero` then tests.
const VAR_COMPARE_A := 0
const VAR_COMPARE_B := 1

## How many `0xD3 Jump Back` hops one VM tick may take before the fiber is
## declared runaway. A real loop waits at least a frame per pass, so it can only
## be reached by a loop with no Wait in it — which on PSX is a hang too, but on
## PSX it is a hang inside an emulator you can break into.
const BACK_JUMP_BUDGET_PER_TICK := 1024

# Reset at the top of every `_tick_once`; see [constant BACK_JUMP_BUDGET_PER_TICK].
var _back_jumps_this_tick: int = 0


## `_var_get` reads the store's RAW word, and [WorldMapVariables] masks a word
## var to u32 — so a `Subtract` that went below zero reads back as ~4 billion.
## ROM arithmetic and ROM comparison are both SIGNED (`slt`, and a plain `lw`
## into a 32-bit register), so re-widen here. Bit / nibble vars can never reach
## the sign bit, so this is a no-op for them.
func _var_signed(id: int) -> int:
	var v := _var_get(id)
	return v - 0x100000000 if v >= 0x80000000 else v


## The `0xB0`–`0xBD` arithmetic writers — `vars[dst] = vars[dst] <op> operand`,
## ONE handler for all fourteen because the ROM has one (`FUN_8014a018`).
##
## [b]The operand mode is the opcode's low bit[/b] (writers doc §0, ROM
## `andi v0, s2, 0x1` at `0x8014a050`): an EVEN opcode's second operand is an
## immediate, an ODD one's is a variable id read for its current value. So
## `0xB0 Add(v, k)` adds a constant and `0xB1 Add Variable(v, w)` adds `vars[w]`
## — and the catalog names BOTH operands "Variable" on the odd forms, which is
## why this reads them positionally rather than by name.
##
## `Zero(v); Add(v, k)` is FFT's set idiom (there is no SET opcode); the
## `Zero(0); Zero(1); Add Variable(0, w); Add(1, k)` quartet is how a named
## variable gets staged into the comparison scratch pair — see [method
## _op_var_compare].
##
## Divide/modulo by zero ABORT the fiber, as in ROM (`0x8014a170`'s guard jumps
## to `event_fiber_mark_complete`); they do not write and do not fall through.
func _op_var_math(inst: Dictionary) -> void:
	var op := int(inst.get("opcode", -1))
	var a := EventInstructionSet.args(inst)
	var dst := a.nth(0)
	var operand_raw := a.nth(1)
	var by_variable := (op & 1) == 1
	var operand := _var_signed(operand_raw) if by_variable else operand_raw
	var lhs := _var_signed(dst)
	var core := op & 0xFE
	var out := 0
	match core:
		EventInstruction.ADD:
			out = lhs + operand
		EventInstruction.SUBTRACT:
			out = lhs - operand
		EventInstruction.MULTIPLY:
			out = lhs * operand
		EventInstruction.DIVIDE, EventInstruction.MODULO:
			if operand == 0:
				push_warning(("[ScenarioVM] %s var[%d] by ZERO @0x%X (pc=%d, ctx=%s)"
					+ " — the ROM aborts the fiber here (writers doc §2)") %
					[_VAR_MATH_OPS.get(core, "?"), dst, int(inst.get("offset", 0)),
					_current_ctx.pc - 1, _current_ctx.label])
				_current_ctx.alive = false
				return
			out = (lhs / operand) if core == EventInstruction.DIVIDE else (lhs % operand)
		EventInstruction.AND:
			out = lhs & operand
		EventInstruction.OR:
			out = lhs | operand
		_:
			push_warning("[ScenarioVM] _op_var_math reached with opcode 0x%X" % op)
			return
	vars_store.set_var(dst, out)
	print("[ScenarioVM] %s var[%d] by %s (was %d) -> %d" % [
		_VAR_MATH_OPS.get(core, "?"), dst,
		"var[%d]=%d" % [operand_raw, operand] if by_variable else str(operand),
		lhs, _var_signed(dst)])


## The `0xA0`–`0xA5` comparisons — ROM `FUN_80149f10`, a two-register ALU that
## reads NO operand bytes: it compares the fixed scratch pair var[0] (A) and
## var[1] (B), SIGNED, and stores the boolean back into var[0]
## (`sw v1, 0x0(v0)` at `0x8014a00c`). Overwriting A is not a quirk to route
## around — it is the whole link to `0xD0`, which reads that same word.
func _op_var_compare(inst: Dictionary) -> void:
	var op := int(inst.get("opcode", -1))
	var a := _var_signed(VAR_COMPARE_A)
	var b := _var_signed(VAR_COMPARE_B)
	var result := false
	match op:
		EventInstruction.VARIABLE_LE:
			result = a <= b
		EventInstruction.VARIABLE_GE:
			result = a >= b
		EventInstruction.VARIABLE_EQ:
			result = a == b
		EventInstruction.VARIABLE_NE:
			result = a != b
		EventInstruction.VARIABLE_LT:
			result = a < b
		EventInstruction.VARIABLE_GT:
			result = a > b
		_:
			push_warning("[ScenarioVM] _op_var_compare reached with opcode 0x%X" % op)
			return
	vars_store.set_var(VAR_COMPARE_A, 1 if result else 0)
	print("[ScenarioVM] Variable %s: %d %s %d -> var[0]=%d" % [
		_VAR_COMPARE_OPS.get(op, "?"), a, _VAR_COMPARE_OPS.get(op, "?"), b,
		1 if result else 0])


## `0xD2` / `0xD4` / `0xD5` — the jump LABELS. Runtime no-ops: they exist to be
## found by the label scan, and the ROM's scan returns the index AFTER them, so
## falling through is the whole behaviour.
func _op_label_anchor(inst: Dictionary) -> void:
	print("[ScenarioVM] label %s id=%d (pc=%d)" % [
		str(inst.get("name", "?")), EventInstructionSet.args(inst).nth(0),
		_current_ctx.pc - 1])


## `0xD0 Jump Forward If Zero` — the consumer half of the comparison family.
##
## [b]It jumps when var[0] is ZERO[/b], i.e. when the `0xA0`–`0xA5` compare that
## staged it was FALSE (ROM `0x801444b8`: `bne v0, zero, <skip the jump>`). The
## pattern it compiles is `if (cond) { block }` — a false condition jumps PAST
## the block. Scans for `0xD2` OR `0xD4` (readers doc §3's table).
func _op_jump_forward_if_zero(inst: Dictionary) -> void:
	var cond := _var_signed(VAR_COMPARE_A)
	if cond != 0:
		print("[ScenarioVM] Jump Forward If Zero id=%d — var[0]=%d TRUE, falling through" %
			[EventInstructionSet.args(inst).nth(0), cond])
		return
	_jump_to_label(inst, [EventInstruction.FORWARD_TARGET,
			EventInstruction.FORWARD_IF_ZERO_TARGET], true)


## `0xD1 Jump Forward` — unconditional; `0xD2` anchors only (`a2 = -1` in ROM).
func _op_jump_forward(inst: Dictionary) -> void:
	_jump_to_label(inst, [EventInstruction.FORWARD_TARGET], true)


## `0xD3 Jump Back` — unconditional; `0xD5` anchors only, scanning from the top
## of the chunk up to the jump (ROM `FUN_80149d6c`'s backward branch).
func _op_jump_back(inst: Dictionary) -> void:
	_jump_to_label(inst, [EventInstruction.BACK_TARGET], false)


## Move `_current_ctx.pc` to the instruction after the `markers` label whose id
## matches this jump's `Target` operand.
##
## [b]A jump carries a LABEL ID, never a distance[/b] (readers doc §3) — ROM
## `FUN_80149d6c` walks the bytecode opcode-by-opcode looking for the anchor. We
## walk `_insts` instead, which is the same walk without the operand-length table
## (the disassembler already did that decode).
##
## `pc` is already advanced past the jump when a handler runs, so the forward
## scan starts exactly where ROM's `s8 + 2` does. A forward scan STOPS at
## `0xDB Event End`, and a scan that finds nothing marks the fiber complete
## rather than falling through — a fall-through would run the block the jump
## exists to skip.
func _jump_to_label(inst: Dictionary, markers: Array, forward: bool) -> void:
	var target := EventInstructionSet.args(inst).nth(0)
	var name := str(inst.get("name", "?"))
	if not forward:
		_back_jumps_this_tick += 1
		if _back_jumps_this_tick > BACK_JUMP_BUDGET_PER_TICK:
			push_warning(("[ScenarioVM] %s id=%d — %d backward jumps in one tick (ctx=%s);"
				+ " this loop has no Wait in it. Ending the fiber rather than hanging.") %
				[name, target, _back_jumps_this_tick, _current_ctx.label])
			_current_ctx.alive = false
			return
	var from := _current_ctx.pc if forward else 0
	var to := _insts.size() if forward else _current_ctx.pc - 1
	for i in range(from, to):
		var op := int(_insts[i].get("opcode", -1))
		if forward and op == EventInstruction.EVENT_END:
			break
		if not markers.has(op):
			continue
		if EventInstructionSet.args(_insts[i]).nth(0) != target:
			continue
		print("[ScenarioVM] %s id=%d -> pc %d (ctx=%s)" % [name, target, i + 1, _current_ctx.label])
		_current_ctx.pc = i + 1
		return
	push_warning("[ScenarioVM] %s id=%d found no label (ctx=%s) — ending the fiber, as ROM does" %
		[name, target, _current_ctx.label])
	_current_ctx.alive = false


## Event-script `0x7E Wait Value` reader — a PREDICATE barrier on the calling
## context: hold until `vars[id] >= value` (SIGNED `>=`, NOT `==`; ROM handler
## `FUN_8014a3f8` does `slt; beq` then yields the fiber and re-polls — an
## overshoot still releases). See readers doc §1. Reuses `_arm_wait_until`, so
## the watchdog (10 s) backstops a counter that never climbs. var 87 is driven
## by the `_tick_once` incrementer; because the barrier holds only
## `_current_ctx` (the block coroutine), the main thread keeps draining to the
## Display Message in parallel.
func _op_wait_value(inst: Dictionary) -> void:
	var a := EventInstructionSet.args(inst)
	var id := a.raw("Variable")
	var value := a.raw("Value")
	_arm_wait_until(_current_ctx, func() -> bool: return _var_get(id) >= value)
	print("[ScenarioVM] Wait Value var[%d] >= %d (ctx=%s, now=%d)" %
		[id, value, _current_ctx.label, _var_get(id)])


## Event-script `0x10 Display Message` handler.
##
## The chapel prayer at scenario-1 PC=42 is the canonical overlay case:
## `Dialog=0x09 Message=0x01 Unit=0x0C Y=0x3C Open Type=0`. Per the living
## doc `research/working_documents/scenario_1_captures/
## display_message_overlay_decode.md`, `Dialog=0x09` is the OVERLAY mode
## (no box, no input-wait, raw body with inline `{Delay NN}` pacing);
## boxed variants (`0x11/0x12/0x91/0x92`) are out of scope here.
##
## Text is NOT in the opcode params — it's resolved offline by
## `tools/disasm_event.py --with-text` from the chunk's post-Event-End
## string table and baked into the JSON record as `dialogue.tokens` (see
## `_fft_strings.tokenize`). The Godot side just dispatches the right
## variant + forwards the tokens to `DialogueOverlay.show_overlay`.
##
## **Non-blocking:** the next opcode in scenario 1 after the prayer is
## `0xF1 Wait Time=0x56` (86 frames), which handles dwell. The handler
## does NOT arm `_wait_ticks`; the overlay types asynchronously per its
## own frame-discrete cursor.
##
## Clear trigger: per the living doc's Phase 3 default (pending A.3/B.3
## live confirmation), the overlay clears on the NEXT Display Message
## opcode of any kind. Map Darkness + scene exit don't clear today (no
## evidence the prayer ever needs to be torn down by anything else in
## scenario 1).
func _op_display_message(inst: Dictionary) -> void:
	# The overlay-vs-box dispatch + box-pool access moved onto ScenarioApply through
	# ScenarioWorld verbs (Card 2 seam). The advance GATE stays VM scheduler state
	# (Option A): apply returns whether a boxed box was shown; the VM arms the gate.
	# The overlay is deliberately NON-BLOCKING — the real barrier is the later {E5}
	# Wait For Instruction Task=1 (chunk PC 50), whose kind-1 predicate holds on the
	# overlay being active. See display_message_overlay_decode.md §round-2.
	var intent := ScenarioDecode.display_message(EventInstructionSet.args(inst))
	var tokens: Array = inst.get("dialogue", {}).get("tokens", [])
	if ScenarioApply.display_message(intent, tokens, _world):
		_pending_dialog_gate = true


## {0x50} Portrait Row — latch the EVTFACE row-block for subsequent dialogue
## boxes. The operand is a single `Row` byte; the render column comes from the
## following {10}/{51} Portrait byte (col = byte - 1). No VRAM upload / disc read
## is modeled — Godot resolves EVTFACE[row, col] to a face texture directly when a
## box is shown. PORTRAIT_ROW_OPCODE_50_EVTFACE.md §2.1/§5.1.
func _op_portrait_row(inst: Dictionary) -> void:
	_portrait_row = ScenarioDecode.portrait_row(EventInstructionSet.args(inst))




# Resolve the active Camera3D — `player_camera` directly if it is one, else the
# viewport's active camera (the scenario rig nests the real Camera3D under the
# PlayerCamera body).
func _active_camera() -> Camera3D:
	if player_camera is Camera3D:
		return player_camera
	if is_inside_tree():
		return get_viewport().get_camera_3d()
	return null




## Event-script `Wait For Instruction(Task=N)` — a cooperative-task barrier.
## `Task` names a KIND of async activity (dialog, camera move, child cutscene
## block, screen-tint FX, …); the opcode holds the calling script until no
## activity of that kind is still running, then resumes. It is NOT a player-input
## gate — the lone exception is Task=1 (dialog), which also drives the boxed-
## dialog advance gate.
##
## Modeled as a per-kind `wait_until` predicate (the same hold primitive the
## dedicated Wait Rotate / Wait Field Object barriers ride): if nothing of that
## kind is in flight the barrier passes through this tick; otherwise it re-polls
## each tick until the activity finishes. Kinds we model no async activity for
## fall straight through. PSX decode + the kind catalogue:
## research/working_documents/scenario_1_captures/wait_for_instruction_halt_decode.md.
func _op_wait_for_instruction(inst: Dictionary) -> void:
	var task := EventInstructionSet.args(inst).raw("Task", 1)
	# Task=1 (dialog): the boxed-dialog advance gate (Cross-to-advance /
	# auto-advance dwell) is held by the dialog-gate PARK — an indefinite,
	# player-driven, per-context hold (round-robin skip of `_dialog_gate_ctx`),
	# NOT a `wait_until`. The park has no watchdog, which is correct: a real box
	# waits as long as the player takes. So once the park is engaged we return
	# WITHOUT arming a `wait_until` — the kind-1 predicate below reports the
	# foreground box as live (honest registry), but arming a wait_until on top
	# would double-hold AND impose the 10 s watchdog on an indefinite wait.
	if task == 1:
		_consume_dialog_gate()
		if _dialog_gate_active:
			return
	var pred := _wfi_predicate(task)
	if pred.is_valid() and _current_ctx != null and not pred.call():
		# Task=1 holding on the on-map overlay typewriter can legitimately run far
		# past the default 10 s watchdog — the scenario-8 Gariland narration is a
		# multi-page block that types for 30-40 s (Part Z §Z.5). A fixed deadline
		# force-releases it mid-narration, so `{33}` Color Field / `{32}` Color
		# Unit dispatch while the text is still up and the screen colour shifts
		# under the narration (the divergence the prayer's shorter text hid). Arm
		# the overlay hold with a PROGRESS probe: while the typewriter keeps
		# revealing glyphs (or fading out) the deadline is pushed forward, so the
		# barrier holds for the WHOLE narration; a genuinely-stuck overlay (no
		# progress for the window) still force-releases as a deadlock backstop.
		var watchdog := _WAIT_UNTIL_WATCHDOG_TICKS
		var progress := Callable()
		if task == 1 and dialogue_overlay != null \
				and dialogue_overlay.has_method("is_active") \
				and dialogue_overlay.is_active():
			watchdog = _OVERLAY_TYPEWRITER_WATCHDOG_TICKS
			if dialogue_overlay.has_method("overlay_progress"):
				progress = Callable(dialogue_overlay, "overlay_progress")
		_arm_wait_until(_current_ctx, pred, watchdog, progress)


## Consume a pending boxed-dialog advance gate (the Task=1 half of Wait For
## Instruction). After a boxed Display Message / Change-Dialog swap arms the
## gate, this holds opcode dispatch on the owning context until the player
## advances (Cross / confirm) — or, in auto-advance / play-through, after a
## fixed dwell. No-op when no gate is pending.
func _consume_dialog_gate() -> void:
	if not _pending_dialog_gate:
		return
	_pending_dialog_gate = false
	# The gate is scoped to the FOREGROUND box (the just-opened / just-swapped
	# kind-1 slot); background (kind-0x33) boxes stay up but don't gate.
	var box := box_pool._foreground_box()
	if box == null:
		return
	if DebugConfig.chapel_trace_enabled:
		# Trace burn-through: reveal + page through every page instantly (no dwell).
		if box.has_method("finish_typing"):
			box.finish_typing()
		while box.has_method("has_more_pages") and box.has_more_pages():
			box.advance_page()
			if box.has_method("finish_typing"):
				box.finish_typing()
		_dialog_dwell_ticks = 0
		_release_dialog_gate()
		return
	_dialog_gate_active = true
	_dialog_gate_ctx = _current_ctx
	if dialog_auto_advance or play_through_skip_unknown:
		# Reveal the whole box now and hold for a fixed dwell so automated runs
		# don't deadlock and the camera choreography keeps moving.
		if box.has_method("finish_typing"):
			box.finish_typing()
		_dialog_dwell_ticks = maxi(1, dialog_auto_advance_ticks)
	else:
		# Interactive: block indefinitely until `_advance_dialog` clears it.
		_dialog_dwell_ticks = 0


## Cooperative-task registry — the Godot mirror of PSX's 16-slot kind array.
##
## PSX models every async activity as a slot tagged with a `kind`; `{E5} Wait For
## Instruction(Task=N)` yields while any slot is active with `kind == N`, then
## resumes (wait_for_instruction_halt_decode.md §3). Godot's activities are
## poll-based (camera lerp/spline state, overlay is_active, oxide fade ticks), so
## rather than a literal slot array we register ONE liveness predicate per kind —
## "is a task of this kind still in flight?" — defined once, by the subsystem that
## owns the activity. `_wfi_predicate(N)` is then the single generic "no live task
## of kind N" poll shared by every Task value, instead of a bespoke branch per
## kind. This holds a Task=4 / 8 / 54 barrier for the real activity duration rather
## than racing ahead, and generalizes to any future scenario with no new per-kind
## predicate.
##
## Kind catalogue + PSX provenance: §3.4. Ground truth for the prayer beat
## (probe_prayer_interp_hold.py, 2026-07-01): the interpreter sat on Task=4 for the
## camera swoop (~135f) then Task=1 for the dialog (~255f) — BOTH holds are already
## faithful here (kind-4 = not camera-idle, held through the fusion spline; kind-1 =
## overlay active). The earlier "255f dialog-coupled kind-4 camera" reading was a
## decoder-timestamp off-by-one; corrected in §4.
const TASK_DIALOG := 1       # Display Message / Change Dialog (box + on-map overlay)
const TASK_SPRITEMOVE := 11  # {3B}/{6E} Sprite Move (kind 0x0B) — generic, no unit filter
const TASK_CAMERA := 4       # Camera move — immediate step + fusion swoop
const TASK_BLOCK := 8        # nested event-block coroutine (Block Start)
const TASK_BGSOUND := 53     # {6B}/{6A} BG Sound cooperative task (kind 0x35)
const TASK_DARKSCREEN := 54  # Dark Screen / screen-tint FX (oxide fade)
const TASK_SHOWGRAPHIC := 61 # {7D} Show Graphic fullscreen fade (kind 0x3D)
const TASK_CONDITIONS := 56  # {78} Display Conditions screen (kind 0x38)
const TASK_COLORSCREEN := 12 # {3E} Color Screen full-screen colour ramp (kind 0x0C)

# Kinds that legitimately have NO async activity in Godot, so a {E5} barrier on
# them falls straight through (matching PSX: nothing of that kind is ever live →
# release after one yield). 52 = EVTCHR load (synchronous in Godot). This is the
# ONLY silent fall-through — any OTHER unregistered kind is a MISSING registration
# (the scn6 carry-down class of bug, where kind 0x0B had a real activity but no
# predicate) and gets warned once via `_warned_task_kinds`, so registry drift stops
# failing silently.
#
# 🔴 56 (0x38) WAS LISTED HERE AS "no PSX task exists". It is {78} Display
# Conditions' own kind: `0x801CAFD4`'s first act is `0x80149D48(0x38)`, and every
# {78} in all 500 events is followed by `{E5} 38 00` (BATTLE_RESULTS_SCREEN.md
# §13). It now has a real predicate below.
const INSTANT_TASK_KINDS := {52: true}

# kind:int -> Callable(waiter) -> bool  (true while a task of that kind is live).
# Populated in `_ready` via `_register_task_kinds`.
var _task_liveness: Dictionary = {}

# Unregistered, non-instant kinds we've already warned about (warn-once dedupe).
var _warned_task_kinds: Dictionary = {}


## Register the per-kind liveness predicates (called once from `_ready`). Each
## clear-condition lives here, defined by the subsystem that owns the activity —
## the single place kind→liveness is expressed, replacing the old per-kind branch
## inside `_wfi_predicate`.
func _register_task_kinds() -> void:
	# kind-1 dialog: live while EITHER the on-map overlay typewriter (the prayer)
	# is up OR the foreground boxed dialog is still awaiting advance
	# (`_dialog_gate_active`). This is the honest kind-1 slot — a Task=1 barrier
	# raised by ANY context sees both. The context that OWNS the box hold is
	# parked by the advance park (`_consume_dialog_gate`, indefinite/no-watchdog);
	# `_op_wait_for_instruction` returns early for it so it doesn't also arm a
	# watchdog'd wait_until on this same predicate.
	_task_liveness[TASK_DIALOG] = func(_waiter) -> bool:
		if dialogue_overlay != null \
				and dialogue_overlay.has_method("is_active") \
				and dialogue_overlay.is_active():
			return true
		return _dialog_gate_active
	# kind-11 (0x0B) sprite-move: live while ANY actor has an in-flight
	# [ScenarioMotion]. The generic, unit-filter-free sibling of {6F} Wait Sprite
	# Move — PSX's {E5} Task=11 scans all kind-0x0B cooperative slots with NO
	# +0x50 unit filter (wait_for_instruction_halt_decode.md §3;
	# SPRITE_MOVE_INVESTIGATION.md). scn6's carry-down walks Delita + Ovelia in
	# lockstep and gates each step on this, so the no-filter form waits for BOTH to
	# settle. Godot collapses the motion family ({6F}/{29}/{64} all answer
	# `motion_done`), so "any live motion" is the faithful analogue; reuses
	# `_actor_motion_live`, the same per-actor liveness `motion_done` reads.
	_task_liveness[TASK_SPRITEMOVE] = func(_waiter) -> bool:
		for uid in actors:
			if _actor_motion_live(actors[uid]):
				return true
		return false
	# kind-4 camera: live while any camera motion is in flight — per-frame lerp,
	# fusion-chain spline, or a queued waypoint. Holds through the whole fusion
	# swoop (`_chain_spline != null`), exactly as the PSX kind-4 slot does.
	_task_liveness[TASK_CAMERA] = func(_waiter) -> bool:
		return not camera_director.is_idle()
	# kind-8 nested block: live while any spawned child block coroutine is still
	# running (the waiter + main are excluded so a block can't self-block).
	_task_liveness[TASK_BLOCK] = func(waiter) -> bool:
		return not _child_blocks_drained(waiter)
	# kind-53 (0x35) bg-sound: live while ANY {6B}/{6A} volume ramp is still in
	# flight. A later {E5} Wait For Instruction on Task=0x35 holds until every
	# ambient fade has settled. Not exercised in scenario 4 (the {6B} there is
	# fire-and-forget with no following Wait), but wired for faithfulness so a
	# scenario that DOES wait on a fade blocks correctly.
	_task_liveness[TASK_BGSOUND] = func(_waiter) -> bool:
		for sid in _bg_sounds:
			if not (_bg_sounds[sid] as ScenarioBgSound).is_idle():
				return true
		return false
	# kind-54 dark-screen FX: live while EITHER a {76}/{77} Dark Screen sweep is in
	# flight — in EITHER direction, because the PSX barrier is on the task KIND and
	# {77} re-labels the slot back to 0x36 for the whole retract, so the {E5} 36 00
	# after {77} holds for all 112 frames of it (ScenarioDarkScreen.is_sweeping) — OR
	# the map-darkness oxide fade is settling (the prayer-scene tint, which shares this
	# kind). Releases once the controller parks and the oxide has landed.
	_task_liveness[TASK_DARKSCREEN] = func(_waiter) -> bool:
		if _dark_screen != null and _dark_screen.is_sweeping():
			return true
		return _oxide_remaining_ticks > 0
	# kind-61 (0x3D) show-graphic FX: live while the {7D} fullscreen graphic is
	# still on screen (fading in, held, or fading out). The {E5} Wait For
	# Instruction(Task=61) that follows every Show Graphic holds on this until the
	# graphic has fully faded away — the chapter-intro card plays in full before
	# the scene proceeds. show_graphic_op7d_decode.md §3/§6.
	_task_liveness[TASK_SHOWGRAPHIC] = func(_waiter) -> bool:
		return _show_graphic != null and _show_graphic.is_live()
	# kind-56 (0x38) display-conditions: live while a {78} screen is still on its
	# own clock. `0x801CAFD4` writes 0x38 into its slot's kind field and
	# `0x8014C958` clears it on exit, so the `{E5} 38 00` after every {78} is a
	# plain "wait for the screen to finish" — which is what lets the gil reel own
	# the frame for four seconds without the victory text still being up. A mode
	# with nothing to draw (4/5/6/7 on a battle with no loot, no departure and no
	# recruit) clears it the same frame, exactly as §17 measured.
	_task_liveness[TASK_CONDITIONS] = func(_waiter) -> bool:
		return _results_screen != null and _results_screen.is_live()
	# kind-12 (0x0C) color-screen FX: live while the {3E} full-screen colour ramp is
	# still fading start->end. The {E5} Wait For Instruction(Task=12) that follows
	# every {3E} holds on this until the ramp lands on `end` (PSX
	# event_fiber_mark_complete). COLOR_SCREEN_OPCODE_3E.md §2.4.
	_task_liveness[TASK_COLORSCREEN] = func(_waiter) -> bool:
		return _color_screen != null and _color_screen.is_active()


## True while a cooperative task of `kind` is registered AND live — the generic
## slot-scan analog (PSX yields WFI(Task=N) while any slot has kind==N active).
func _task_kind_live(kind: int, waiter) -> bool:
	var pred: Callable = _task_liveness.get(kind, Callable())
	return pred.is_valid() and pred.call(waiter)


## Map a Wait For Instruction `Task` kind to the barrier predicate: release (return
## true) when NO task of that kind is live. A kind with no registered predicate
## returns an INVALID Callable so the barrier falls straight through — matching PSX
## finding no matching slot and releasing after a single yield. That silent
## fall-through is CORRECT only for the deliberately-unmodeled kinds
## (`INSTANT_TASK_KINDS`: 52 EVTCHR load — synchronous in Godot; 56 — no such task).
## Any OTHER unregistered kind is a missing registration — the scn6 carry-down bug,
## where kind 0x0B had a real activity (a live [ScenarioMotion]) but no predicate,
## so the barrier no-op'd and the descent raced ahead. Those get warned ONCE so the
## drift is visible instead of manifesting as a silent timing/speed bug.
func _wfi_predicate(task: int) -> Callable:
	if _task_liveness.is_empty():
		_register_task_kinds()  # lazy backstop for callers that bypass `_ready`
	if not _task_liveness.has(task):
		if not INSTANT_TASK_KINDS.has(task) and not _warned_task_kinds.has(task):
			_warned_task_kinds[task] = true
			push_warning("[ScenarioVM] Wait For Instruction Task=%d (0x%02X): no " \
				% [task, task] + "liveness predicate registered — barrier falls " \
				+ "through (no wait). If this kind has a modeled activity, register " \
				+ "it in _register_task_kinds; if it's genuinely instant, add it to " \
				+ "INSTANT_TASK_KINDS.")
		return Callable()
	var waiter = _current_ctx
	return func() -> bool: return not _task_kind_live(task, waiter)


## kind-8 predicate: true when every spawned cutscene-block coroutine has
## finished. The waiting context and the main script are excluded so a block
## waiting on its siblings doesn't block on itself or on the never-terminating
## main thread.
func _child_blocks_drained(waiter) -> bool:
	var main_ctx = _contexts[0] if not _contexts.is_empty() else null
	for ctx in _contexts:
		if ctx == waiter or ctx == main_ctx:
			continue
		if ctx.alive:
			return false
	return true


## Event-script `{51} Change Dialog`. `Target=N` addresses box N (1-based, open
## order); Message==0xFFFF CLOSES that box (each Change Dialog closes exactly its
## own target — two boxes need two ops), otherwise swaps that box's text in place
## (no teardown — the frame persists) and makes it the foreground again, re-arming
## the advance gate. Per boxed_dialog_decode.md A6 the PSX re-composites into the
## same buffer; we mirror that with an in-place re-show. Target=0/out-of-range
## falls back to the current foreground box. See
## concurrent_dialogue_boxes_decode.md.
func _op_change_dialog(inst: Dictionary) -> void:
	# Box-pool access (resolve/close/swap) routes through ScenarioApply + the world
	# verbs (Card 2 seam); the advance-gate scheduler state stays VM-side. Apply
	# returns the gate action for the closed/swapped slot.
	var a := EventInstructionSet.args(inst)
	# Portrait Column re-picks the live box's EVTFACE face in place ({50} row stays
	# put); 0 / no active row leaves the current portrait untouched (§2.5, issue #165).
	var result := ScenarioApply.change_dialog(a.raw("Message"), a.raw("Target"),
		a.raw("Portrait Column"), _world)
	match result.get("action", "noop"):
		"close_fg":
			# Closing the FOREGROUND box tears down its advance gate.
			_pending_dialog_gate = false
			_dialog_gate_active = false
			_dialog_gate_ctx = null
		"swap":
			_pending_dialog_gate = true


# Tick the active advance gate once. Auto-advance dwell counts down; the
# interactive gate (dwell==0) holds until `_advance_dialog` releases it. On a
# paginated box the dwell auto-turns each page (revealing it in full) and only
# releases the gate after the last page's dwell — mirroring the player pressing
# O/Circle per page.
func _tick_dialog_gate() -> void:
	var box := box_pool._foreground_box()
	if _dialog_dwell_ticks > 0:
		_dialog_dwell_ticks -= 1
		if _dialog_dwell_ticks <= 0:
			if box != null and box.has_method("has_more_pages") \
					and box.has_more_pages():
				box.advance_page()
				if box.has_method("finish_typing"):
					box.finish_typing()
				_dialog_dwell_ticks = maxi(1, dialog_auto_advance_ticks)
				return
			_release_dialog_gate()


# Does this event mean "advance the dialog"? Prefers a project `dialog_advance` action (map to
# Cross/confirm), falling back to the built-in `ui_accept`. `is_action_pressed` on the EVENT
# excludes echoes by default, which is the edge `is_action_just_pressed` used to give.
func _advance_action_pressed(event: InputEvent) -> bool:
	if InputMap.has_action(&"dialog_advance") and event.is_action_pressed(&"dialog_advance"):
		return true
	return event.is_action_pressed(&"ui_accept")


# Player pressed advance while the box is up (O/Circle). Press order matches PSX
# pagination (decode Part 2 / §1.2): while typing → finish the reveal; else if a
# later page is pending → advance the page in place; else release the gate so the
# VM resumes (the box closes on the following Change Dialog 0xFFFF).
func _advance_dialog() -> void:
	if not _dialog_gate_active:
		return
	var box := box_pool._foreground_box()
	# The ROM's open tween is fiber-BLOCKING (`jal dialog_box_open_close_tween`
	# @0x80131344 returns only after the whole curve), so no advance press is
	# consumed while the box is still growing — the fiber isn't back to read one.
	# Without this a mashed Circle finish-types a box that has not finished opening.
	if box != null and box.has_method("is_opening") and box.is_opening():
		return
	if box != null and box.has_method("is_typing") and box.is_typing():
		if box.has_method("finish_typing"):
			box.finish_typing()
		return
	if box != null and box.has_method("has_more_pages") \
			and box.has_more_pages():
		box.advance_page()
		return
	_release_dialog_gate()


## Release the foreground advance gate. A box whose Dialog bit 0x80 is CLEAR does
## NOT persist as a background box: it closes the instant it stops being the
## foreground (i.e. when advanced past its `Wait For Instruction Task=1`). PSX
## proof: the dialog fiber tears the slot down (LAB_80131a80) when the stored
## (Dialog & 0x80) bit is clear; 0x9x boxes take the keep/yield path instead and
## linger until a `Change Dialog` closes them. Without this, an advanced non-
## persist box (Orbonne msg2, bottom) wrongly stayed on screen alongside the next
## box (msg3, top) — see dialogue_box_visual_parity_investigation.md.
func _release_dialog_gate() -> void:
	var slot := box_pool._foreground_slot
	_dialog_gate_active = false
	_dialog_gate_ctx = null
	if slot >= 1 and not bool(box_pool._slot_persists.get(slot, true)):
		var box := box_pool._box_at(slot)
		if box != null and box.has_method("close") \
				and box.has_method("is_active") and box.is_active():
			box.close()
		box_pool._slot_persists.erase(slot)
		if box_pool._foreground_slot == slot:
			box_pool._foreground_slot = 0


func _op_warp_unit(inst: Dictionary) -> void:
	# Decode the opcode's meaning (uid, PSX tile, spawn facing) purely, then apply
	# it to the world through the seam — the placement + home-reset + facing writes
	# live in ScenarioApply.warp against ScenarioWorld verbs (ADR-0058).
	var intent := ScenarioDecode.warp_unit(EventInstructionSet.args(inst))
	ScenarioApply.warp(intent, _world)
	print("[ScenarioVM] Warp Unit 0x%02X -> (%d,%d) facing 12bit 0x%03X" %
		[intent.uid, intent.psx_x, intent.psx_y, intent.facing_12bit])


## Event-script Add Unit (opcode 0x45). Per BATTLE.BIN `FUN_BATTLE.BIN__8008d05c`
## (Ghidra-wiki-labelled "Post add/transform Graphic Update by Battle ID"), this
## fetches the unit's battle stats by id and commits its SHP/SEQ — it does NOT
## create the unit AND does NOT toggle sprite visibility. The actual on-screen
## reveal is `Draw Unit` (0x44).
##
## Disassembly basis: scenario 1 adds units 0x02/0x17/0x83/0x84 with Draw=1
## here, then later inside Blocks runs Color Unit (invisible) → Sprite Move
## off-screen → `Draw Unit` (the real reveal) → fade in → walk to tile. If
## Add Unit toggled visibility we'd see them pop on at the wrong moment, and
## the later Draw Unit would be a no-op.
##
## The unit is already pre-spawned by `ScenarioPlayerScene._spawn_units` with
## `visible = always_present` from its ENTD flags, so this handler is a no-op
## by default — left in the dispatch table for logging and future stat-commit
## work.
func _op_add_unit(inst: Dictionary) -> void:
	var a := EventInstructionSet.args(inst)
	ScenarioApply.add_unit(a.raw("Unit"), a.raw("Draw", 1), _world)


## Event-script Draw Unit (opcode 0x44). The actual on-screen reveal — flips
## the sprite to visible. Units start hidden (per ENTD `always_present` flag);
## this is what brings them on stage for their choreographed walk-on.
func _op_draw_unit(inst: Dictionary) -> void:
	ScenarioApply.draw_unit(EventInstructionSet.args(inst).raw("Unit"), _world)


## Event-script Erase Unit (opcode 0x46). Inverse of Draw Unit — hides the
## sprite. Scenario 1 uses this for Argath's off-screen exit (`0x46 Erase
## Unit Unit=0x34` after he runs through a chain of Sprite Move ops).
func _op_erase_unit(inst: Dictionary) -> void:
	ScenarioApply.erase_unit(EventInstructionSet.args(inst).raw("Unit"), _world)


## Event-script Add Ghost Unit (opcode 0x47). Spawns a sprite-only "ghost" actor —
## a unit with graphics but no ENTD roster/stat record (BATTLE.BIN FUN_8008cf78). The
## chunk decodes the 8-byte body to `Spritesheet(u16), Index, X, Y, Z, Facing, Draw`,
## which map to the authoritative fields `xSP, x00, xID, X, Y, xEL, xFD, xDR` (§3.1):
## `Spritesheet` is the u16 `xSP` sprite_set (byte[+2]=0 so u16==xSP), `Index` is
## `xID` (control-id = xID+0x64), `Z` is elevation `xEL`, `Draw` is the inverted
## `xDR`. The apply layer computes the control-id / facing / visibility and drives the
## `spawn_ghost_unit` world verb (which honors the PSX idempotency gate). Scenario 6's
## abduction tableau adds three (sprite_set 0x61/0x62/0x63 → ctrl 0x64/0x65/0x66),
## held (`xDR=1`) at the map corner (operand 0,0 = off the framed camera — polish, not
## a scene rescue; see §4.5). Full RE: ADD_GHOST_UNIT_OPCODE_47.md.
func _op_add_ghost_unit(inst: Dictionary) -> void:
	var a := EventInstructionSet.args(inst)
	ScenarioApply.add_ghost_unit(
		a.raw("Spritesheet"), a.raw("Index"), a.raw("X"), a.raw("Y"),
		a.raw("Z"), a.raw("Facing"), a.raw("Draw"), _world)


## Event-script Remove Unit (opcode 0x3D). Faithful to PSX FUN_80086f2c (the one
## true removal core, exercised by both {3D} and scene-end teardown): tears a
## unit fully off the field AND out of memory — clears its combat-roster slot
## (active word 1->0, synchronously in the handler), its per-ID registry byte,
## and frees its sprite slot — instantly. No fade, no War Trophy: that's {44}
## Blue Remove Unit. Distinct from {46} Erase Unit, which only hides the sprite
## and leaves the registry intact.
##
## In our engine this collapses to: erase the id from `units_by_id` (so later
## references no-op and a following {45} Add Unit can reuse the slot — exactly
## what scenario-1 PC 384-385 does with 0x82), tear down the unit's per-unit
## bookkeeping (`forget` erases its ScenarioActor entry), and `queue_free` the
## sprite node. Because ScenarioPlayerScene hands the VM the SAME dict reference
## (`_vm.units_by_id = _units_by_id`), erasing here removes it from the scene's
## registry too — no second container to clean.
##
## The Masked-Data 2nd operand is ignored (stock behaviour; the ROM handler never
## reads it — see remove_unit_decode.md §3.2). Live-validated at both scenario-1
## sites (0x83, 0x13): the roster slot active word transitions 1->0 inside the
## handler. The PSX busy-wait (FUN_80146004) only matters for a unit removed
## mid-action; in scenario 1 both are already {46} Erased + idle, so an immediate
## free is faithful.
func _op_remove_unit(inst: Dictionary) -> void:
	ScenarioApply.remove_unit(EventInstructionSet.args(inst).raw("Unit"), _world)


## {92} Inflict Status. Operands `Unit`:2 / `Status`:1 / `Unknown`(=Wait):2. The
## PSX handler (0x80145EE0) spawns a fire-and-forget cooperative task whose body
## (FUN_80148E88) branches on `Status`; we reproduce the stock `Status == 0`
## revive/normalise branch synchronously (ScenarioApply.inflict_status).
##
## Status 0 (revive), 1 (Crystal), 2 (Poison+Critical) are implemented. The 0x80+
## single-status ROM-hack range is dead code on stock (§11.2); rather than silently
## no-op past it we FAIL LOUD: `push_error` + drop `_running` so the drain loop halts.
func _op_inflict_status(inst: Dictionary) -> void:
	var a := EventInstructionSet.args(inst)
	var status := int(a.raw("Status"))
	if status != 0 and status != 1 and status != 2:
		# Status 0 (revive/normalise), 1 (Crystal), 2 (Poison+Critical) are
		# implemented. The 0x80+ single-status range is dead code on stock (§11.2);
		# it fails loud + halts rather than advancing past an unmodelled status.
		push_error("[ScenarioVM] {92} Inflict Status=0x%02X not implemented (only Status 0/1/2). Halting — see issue #154" % status)
		_running = false            # FAIL LOUD — do not advance past an unmodelled status
		return
	ScenarioApply.inflict_status(a.raw("Unit"), status, a.raw("Unknown"), _world)


## {43} Call Function — dispatches an engine subroutine indexed by `Function`. Most
## indexes are unemulated (custom MIPS; RE pending — issue #155) and FAIL LOUD on
## every call (push_error, not a one-shot), but do NOT halt the VM (unlike
## `_op_inflict_status`) so the scene keeps rendering. `_current_ctx.pc` has already
## advanced past this opcode at the dispatch site, so `pc - 1` is its pc.
##
## `Function=4` IS decoded (research/working_documents/SCENARIO6_DEAD_UNIT_FADE.md):
## the battle->scenario-6 dead-unit sweep (ROM FUN_80147cf0) that fades out and
## removes every on-field non-persisting-side unit, then halts the VM 120 frames.
func _op_call_function(inst: Dictionary) -> void:
	var fn := EventInstructionSet.args(inst).raw("Function")
	if fn == 4:
		_begin_dead_unit_fade()
		return
	push_error("[ScenarioVM] UNIMPLEMENTED Call Function %d @pc=%d — NOT executing engine subroutine (likely custom MIPS); rendering continues but behaviour is INFIDEL" %
		[fn, _current_ctx.pc - 1])


## {43} Call Function 4 — the dead-unit "fade away" sweep (ROM FUN_80147cf0, then
## `event_fiber_yield_n(0x78)`). SCENARIO6_DEAD_UNIT_FADE.md.
##
## The ROM iterates all 21 unit slots and fades every one that has a live on-field
## sprite AND is on the *non-persisting side* (`unit+0x1BA & 0x30 != 0`, a stable
## ENTD-assigned team/side index — NOT hp==0, §4.3). In scenario 6 (ENTD 387) that
## resolves to the five enemy corpses (uids 134-138: team_color 1, always_present),
## while the abduction's staged actors (uids 5,139: team_color 1 but NOT yet on
## field) are spared and re-Added by the following block. The Godot gate is the
## byte-aligned equivalent: `scenario_team_color != 0` (cleared side) AND
## `scenario_present` (the "live sprite exists" allocation gate). Pass 1 arms here;
## `_advance_dead_unit_fades` runs pass 2 + the removal. The VM then holds 120
## frames so the faded corpses linger before the cutscene proper.
func _begin_dead_unit_fade() -> void:
	var faded := 0
	for uid in units_by_id:
		var unit = units_by_id[uid]
		if unit == null or not is_instance_valid(unit):
			continue
		if not _is_dead_unit_fade_target(unit):
			continue
		# Switch the sprite to ADDITIVE blend (the ROM sets tpage ABR=1 +STP in
		# FUN_8008945c). Additive + the palette ramping to black below = the corpse
		# adds progressively less light until it contributes nothing, dissolving INTO
		# the background instead of turning into a black silhouette. §5.1 / §6.1.
		_set_unit_fade_additive(unit, true)
		# KILL THE GROUND SHADOW ON THE SAME FRAME THE FADE ARMS. `FUN_8008945c`
		# @ `0x8008945C` writes `sb zero,0x298(s0)` @ `0x800894CC` — two
		# instructions before the tpage/STP write and four before the pass-1
		# `color_unit_fanout` — and `+0x298` is the drop-shadow SHOW-FLAG the
		# render dispatch gates on (`lbu v0,0x298(s3)` @ `0x80086ACC` →
		# `jal unit_shadow_render` @ `0x80086AF0`; UNIT_SHADOW_RENDERING.md §2,
		# same byte {4E} and anim 0xE0/0xE1 write). So on PSX the blob is gone
		# BEFORE the corpse even turns blue — it never fades, because it is never
		# drawn again. Without this the shadow held full strength through the
		# whole ~40-frame dissolve and then popped, leaving a bare blob sitting
		# under nothing for the back half of the fade.
		if _world != null:
			_world.set_unit_shadow(int(uid), false)
		# Pass 1: mode 4 (palette + delta) Δ=(-31,-31,0) over the fast ramp —
		# kill R,G toward 0, keep B; pass 2 then blacks it out (additive → gone).
		var a := actor(int(uid))
		if a.tint == null:
			a.tint = ScenarioColorTint.new()
		a.tint.apply(4, -31, -31, 0, _DEAD_FADE_PASS1_TIME)
		_apply_unit_tint(int(uid), a.tint)
		_dead_unit_fades[int(uid)] = 1
		faded += 1
	# The event VM fiber yields 0x78 = 120 frames after the sweep before the staging
	# warps + Ovelia's "Let go of me!" box run. Hold THIS context's dispatch.
	_current_ctx.wait_ticks = _DEAD_FADE_HOLD_TICKS
	print("[ScenarioVM] Call Function 4 — dead-unit fade: %d unit(s) swept, holding %d ticks" %
		[faded, _DEAD_FADE_HOLD_TICKS])


## The ROM sweep's selection gate, in Godot terms. True iff `unit` is on the
## non-persisting (cleared) side AND has a live on-field sprite — the set the fade
## removes. See `_begin_dead_unit_fade` for the byte-level correspondence.
func _is_dead_unit_fade_target(unit) -> bool:
	# Persisting side (team_color 0 = Ramza's party + guests) is never faded.
	var team_color := int(unit.scenario_team_color) if "scenario_team_color" in unit else 0
	if team_color == 0:
		return false
	# Not-yet-on-field (staged) units are spared — the ROM's live-sprite gate. The
	# abduction actors (uids 5,139) are on the cleared side but arrive via the block
	# after this sweep, so `scenario_present` is false for them here.
	if "scenario_present" in unit and not bool(unit.scenario_present):
		return false
	return true


## Advance the two-pass dead-unit fade one 60 Hz tick (called from `_tick_once`,
## right after the {32} tint ramps so each faded unit's tint has already ticked
## this frame). When a unit's current pass lands (`is_ramping()` goes false), arm
## the next: pass 1 -> pass 2 (black), pass 2 -> remove from the field. Mirrors the
## ROM's `+0x13e` 1->2->hide/despawn removal machine (FUN_800870ac, §5.4).
func _advance_dead_unit_fades() -> void:
	if _dead_unit_fades.is_empty():
		return
	for uid in _dead_unit_fades.keys():
		var a: ScenarioActor = peek_actor(int(uid))
		if a == null or a.tint == null:
			_dead_unit_fades.erase(uid)
			continue
		if a.tint.is_ramping():
			continue  # this pass is still fading
		var phase: int = _dead_unit_fades[uid]
		if phase == 1:
			# Pass 1 (R,G killed) landed -> pass 2: Δ=(-31,-31,-31) collapses to black.
			a.tint.apply(4, -31, -31, -31, _DEAD_FADE_PASS2_TIME)
			_apply_unit_tint(int(uid), a.tint)
			_dead_unit_fades[uid] = 2
		else:
			# Pass 2 (black) landed -> remove from the field. The ROM's 3-state end is
			# hide-or-despawn; functionally "gone from the field". Additive-black is
			# already invisible; restore the opaque shader (leaving the material clean
			# for any later navigator/replay reuse) then hide the node.
			var unit = units_by_id.get(uid)
			if unit != null and is_instance_valid(unit):
				_set_unit_fade_additive(unit, false)
				unit.visible = false
			# Re-arm the shadow show-flag with the material, for the same reason:
			# the corpse is off the field now, so nothing renders either way, and a
			# navigator/replay reuse of this unit must not inherit a shadowless one.
			# (On PSX `+0x298` is re-armed from the SEQ stream — `seq_interp_type1`
			# @ `0x80084968`/`0x80084970` — so a re-shown unit gets its blob back
			# there; we have no such re-arm, so restore it here.)
			if _world != null:
				_world.set_unit_shadow(int(uid), true)
			_dead_unit_fades.erase(uid)


## Swap a fading unit's sprite material between the OPAQUE and ADDITIVE variants.
## The additive one renders `blend_add`, so the palette-to-black ramp dissolves the
## corpse into the background instead of leaving a black silhouette (ROM tpage ABR=1,
## §5.1). The material is a per-instance duplicate (Unit.gd) and only its `.shader`
## changes, so every color_layer_*/sprite param already pushed carries over untouched —
## which rests on the two variants declaring the same uniforms, pinned by
## tests/UnitMaterialVariantTest.gd (ADR-0189). Which files those variants are is Sprite
## Rig's business; this asks for the blend.
## No-op unless the unit exposes a real ShaderMaterial (VM-only tests use a fake).
func _set_unit_fade_additive(unit, additive: bool) -> void:
	if unit == null:
		return
	var mat = unit.get("material")
	if not (mat is ShaderMaterial):
		return
	mat.shader = UnitMaterial.shader_for(
		UnitMaterialVariant.ADDITIVE if additive else UnitMaterialVariant.OPAQUE)


## Event-script Weather ({3C}). Decodes the two operand bytes to an active gate +
## strength, then drives the world-space rain particle system. Lazily creates the
## ScenarioWeather node on first use and parents it into the scene so the game
## camera transforms it (occlusion is free from the depth buffer). `Unknown=0` (or
## strength < 2) cancels. Fire-and-forget — no barrier opcode; the VM walks past it.
func _op_weather(inst: Dictionary) -> void:
	ScenarioApply.weather(ScenarioDecode.weather(EventInstructionSet.args(inst)), _world)


## The live rain particle node, or null if {3C} hasn't fired yet. For the F3
## Weather tuning panel — it dials the look on the running system, then bakes.
func get_weather_node() -> ScenarioWeather:
	return _weather


## Force the rain on/off from the F3 Weather panel so the look can be dialled
## BEFORE the scenario's {3C} fires (lazily spawns the node like the opcode does).
## Not part of the event script — a tuning affordance only.
func debug_force_weather(active: bool, strength: int) -> ScenarioWeather:
	if _weather == null:
		if not active:
			return null
		_weather = _make_weather()
	_weather.set_weather(active, strength)
	return _weather


## Build + configure the rain particle node, parenting it into the scene. Footprint
## comes from the loaded map dims (host-set map_size_x/z); the ground line for each
## drop is sampled per-tile at spawn from the MapComposer (modernized stand-in for
## the PSX baked 0x8018f8cc grid — see ScenarioWeather).
func _make_weather() -> ScenarioWeather:
	var w := ScenarioWeather.new()
	w.name = "ScenarioWeather"
	if map_size_x > 0:
		w.map_width = map_size_x
	if map_size_z > 0:
		w.map_depth = map_size_z
	w.lattice = _lattice()
	add_child(w)
	return w


# --- {76}/{77}/{78} Dark Screen family ---------------------------------------

## Event-script Dark Screen ({76}). Starts the expanding diamond-mosaic overlay
## with the decoded operands and raises the kind-54 barrier (the very next opcode
## is {E5} Wait For Instruction(0x36), which holds until the mosaic settles).
## Lazily creates the overlay node on first use. DARKSCREEN doc §9/§10/§11.
func _op_dark_screen(inst: Dictionary) -> void:
	ScenarioApply.dark_screen(ScenarioDecode.dark_screen(EventInstructionSet.args(inst)), _world)


## Remove Dark Screen ({77}). Retracts the mosaic; the kind-54 barrier is already
## clear by this point (it releases when the mosaic finishes growing in, not on
## teardown), so this is purely the visual reversal.
func _op_remove_dark_screen(_inst: Dictionary) -> void:
	ScenarioApply.remove_dark_screen(_world)


## {3E} Color Screen — arm the full-screen colour ramp (fade the whole frame from
## start RGB to end RGB over Time, blended per Mode). Lazily creates the overlay.
## The following {E5} Wait For Instruction(Task=12) blocks the VM on this fiber
## (kind 0x0C) until the ramp lands on `end`. COLOR_SCREEN_OPCODE_3E.md.
func _op_color_screen(inst: Dictionary) -> void:
	ScenarioApply.color_screen(ScenarioDecode.color_screen(EventInstructionSet.args(inst)), _world)


## {2E} Background — set/ramp the full-screen gradient backdrop (the Orbonne storm
## sky and its scripted lightning flashes). Decode the 8 operand bytes, arm the
## ScenarioBackground ramp model, and push the corners to the ScreenBackground
## quad. Time>0 ramps linearly over Time*8 frames (ticked in _tick_once); Time=0
## snaps. Full RE: research/working_documents/LIGHTNING_FLASH_OPCODE_2E_BACKGROUND.md.
func _op_background(inst: Dictionary) -> void:
	ScenarioApply.background(ScenarioDecode.background(EventInstructionSet.args(inst)), _world)


## Push the current gradient corners to the full-screen background quad via the
## ScreenEffectOverlay autoload. Top colour → both top vertices, Bottom → both
## bottom vertices (a pure vertical Gouraud gradient, matching the PSX quad). The
## autoload finds the active camera's ScreenBackground child; absent it (headless
## unit tests, no camera), this is a silent no-op — the ramp model is what tests
## assert, the push is verified headful.
func _apply_screen_background() -> void:
	if _background == null or not is_inside_tree():
		return
	# The overlay resolves the quad off the active 3D camera; skip cleanly when
	# there's no camera yet (headless tests) so it doesn't spam "no camera" errors.
	var vp := get_viewport()
	if vp == null or vp.get_camera_3d() == null:
		return
	var overlay = get_node_or_null("/root/ScreenEffectOverlay")
	if overlay == null:
		return
	var top := Color(_background.top.x, _background.top.y, _background.top.z)
	var bottom := Color(_background.bottom.x, _background.bottom.y, _background.bottom.z)
	overlay.set_corners(top, top, bottom, bottom, 0)


## Display Conditions ({78}). Paints the win/lose conditions ("Defeat all
## enemies!") over the dimmed field. The mosaic overlay is the {76} half that
## was the PC-130 halt; the conditions TEXT is a follow-up render not yet wired
## to BattleConditionalDatabase / ScenarioDirector — logged here so the VM walks
## past it instead of halting. GAP: paint the actual conditions text (doc §10.3).
func _op_display_conditions(inst: Dictionary) -> void:
	var a := EventInstructionSet.args(inst)
	ScenarioApply.display_conditions(a.raw("Conditions"), a.raw("Time"), _world)


## Show Graphic ({7D}). Fades a fullscreen graphic (chapter card / ending still /
## GAME OVER / WLDBK background) in, holds, then fades out, and raises the kind-61
## barrier — the very next opcode is {E5} Wait For Instruction(Task=61), which
## holds until the graphic has fully faded away so the intro card plays in full
## before the scene proceeds. Lazily creates the overlay node on first use.
func _op_show_graphic(inst: Dictionary) -> void:
	ScenarioApply.show_graphic(ScenarioDecode.show_graphic(EventInstructionSet.args(inst)), _world)


## Show Map Title ({91}). Reveals the pre-battle location-name strip with a
## LEFT->RIGHT wipe, holds, then ERASES it with a second LEFT->RIGHT wipe (the
## left end vanishes first — NOT {7D}'s global fade). The image is selected by map
## context (current_map_id → MAPTITLE slot), not the X/Y/Speed operand.
##
## {91} BLOCKS the VM until the whole effect completes — the ROM interpreter case
## ends with FUN_8014c9d0 (yield-until-the-spawned-task-inactive), an implicit wait
## built into the opcode (NOT a following {E5}). Dynamically confirmed: the scene
## holds on the sepia tint through the entire title, then advances only once it has
## erased away (show_map_title_op91_decode.md §6). So we park the MAIN context on
## the effect's liveness here; it self-ticks outside the halt gate to completion.
func _op_show_map_title(inst: Dictionary) -> void:
	ScenarioApply.show_map_title(ScenarioDecode.show_map_title(EventInstructionSet.args(inst)), _world)
	if _map_title != null and _current_ctx != null:
		# Release when the strip has fully erased away (task inactive). Progress =
		# the effect's frame counter, so the ~591-frame block never times out.
		var mt := _map_title
		var pred := func() -> bool: return not mt.is_live()
		if not pred.call():
			_arm_wait_until(_current_ctx, pred, _MAP_TITLE_WATCHDOG_TICKS,
				Callable(mt, "progress"))


## Build + configure the Show Map Title overlay node, parenting it into the scene.
## Like Show Graphic, its shader remaps the quad to NDC (fills the screen
## regardless of camera), so parenting under the VM is enough for it to render.
func _make_map_title() -> ScenarioMapTitle:
	var m := ScenarioMapTitle.new()
	m.name = "ScenarioMapTitle"
	add_child(m)
	return m


## Build + configure the Show Graphic overlay node, parenting it into the scene.
## Like Dark Screen, its shader remaps the quad to NDC (fills the screen
## regardless of camera), so parenting under the VM is enough for it to render.
func _make_show_graphic() -> ScenarioShowGraphic:
	var g := ScenarioShowGraphic.new()
	g.name = "ScenarioShowGraphic"
	add_child(g)
	return g


## Build + configure the {78} Display Conditions screen, parenting it into the
## scene. Its meshes are laid out in PSX framebuffer pixels and mapped to clip space
## in the vertex shader, so — like Dark Screen — parenting under the VM is enough.
func _make_results_screen() -> ScenarioResultsScreen:
	var r := ScenarioResultsScreen.new()
	r.name = "ScenarioResultsScreen"
	add_child(r)
	return r


## Build + configure the Dark Screen overlay node, parenting it into the scene.
## The mosaic shader remaps the quad to NDC (fills the screen regardless of
## camera), so it needs no camera-child wiring — parenting under the VM (like
## Weather) is enough for it to render in the game viewport.
func _make_dark_screen() -> ScenarioDarkScreen:
	var d := ScenarioDarkScreen.new()
	d.name = "ScenarioDarkScreen"
	add_child(d)
	return d


## Lazily create the {3E} Color Screen overlay node (owned by the VM, ticked in
## _tick_time_driven_effects).
func _make_color_screen() -> ScenarioColorScreen:
	var c := ScenarioColorScreen.new()
	c.name = "ScenarioColorScreen"
	add_child(c)
	return c


## Get-or-create the [ScenarioActor] for `uid`. The single entry point handlers
## use to reach a unit's cutscene state — one instance per uid, created on first
## touch and returned unchanged thereafter so state accumulates across opcodes.
func actor(uid: int) -> ScenarioActor:
	var a: ScenarioActor = actors.get(uid)
	if a == null:
		a = ScenarioActor.new()
		actors[uid] = a
	return a


## The [ScenarioActor] for `uid`, or null if none exists — non-creating. Lets a
## caller distinguish "unit forgotten" (`peek_actor(uid) == null`) from "sub-state
## cleared" (`peek_actor(uid).tint == null`), a distinction the old flat dicts
## blurred into one `has()` check.
func peek_actor(uid: int) -> ScenarioActor:
	return actors.get(uid)


## Count of units with an in-flight [ScenarioMotion] — the read-helper that
## replaces the old `motions.size()` aggregate now that motions live on actors
## alongside tints/walkers (a bare `actors.size()` would over-count tint-only or
## walker-only entries). Used by the concurrent-slide assertions and tests.
func active_motion_count() -> int:
	var n := 0
	for uid in actors:
		if (actors[uid] as ScenarioActor).motion != null:
			n += 1
	return n


## Un-register `uid`'s actor entirely — "this unit is gone" (Remove Unit). Erases
## the whole entry (tint, motion, walker, atlas, home all go with it), behavior-
## identical to the former `_forget_unit`: it does NOT reset any Unit field. That
## reset is `reset_all`'s job ("the scene rewound, units persist"). Idempotent.
## `_node` is the removed node the caller has in hand — kept for call-site parity
## with the PSX teardown; home now lives on the actor, so no per-node erase remains.
func forget(uid: int, _node) -> void:
	actors.erase(uid)


## Reset every unit's cutscene state — "the scene rewound, units persist" (the
## `start()`/`set_rewind_target()` path). Clears the WHOLE registry (all five
## per-unit structures for every unit at once) AND resets each live unit's three
## Unit-owned fields via `Unit.reset_scenario_cutscene_state()`. This is the fix:
## the three previously-disagreeing reset paths cleared different subsets and
## leaked stale tint/motion/walker/facing across a live-VM restart; collapsing
## them onto this one method makes that inconsistency unrepresentable (ADR-0064).
## Takes `units_by_id` explicitly so the reset targets exactly the caller's live
## roster (and stays testable with injected mocks). Units whose node doesn't
## implement the cutscene contract (bare test stubs) are skipped.
##
## `preserve_poses` is the combat->scenario POSE CARRY: forwarded to each unit's
## `reset_scenario_cutscene_state` so the woven victory beat can keep the
## combat-committed `current_anim_id` (corpse / kneel / idle) instead of standing
## every unit up (see `Unit.reset_scenario_cutscene_state`). Default off — the
## rewind/replay path (`set_rewind_target`) and ordinary member advances reset the
## pose to idle as before.
func reset_all(units_by_id: Dictionary, preserve_poses: bool = false) -> void:
	actors.clear()
	for uid in units_by_id:
		var unit = units_by_id[uid]
		if unit != null and is_instance_valid(unit) and unit.has_method("reset_scenario_cutscene_state"):
			unit.reset_scenario_cutscene_state(preserve_poses)


## Event-script Sprite Move ({3B}). A relative straight-line interpolation of
## the unit's world position from its current spot to `current + (ΔX,ΔZ,ΔY)`
## over `Time` frames, eased by `Type`. It is NOT a pathfind and does NOT pick
## an animation or facing — those arrive as sibling {11} Unit Anim / {2D}
## Rotate Unit opcodes (so do NOT touch anim/facing here). Faithful to the ROM
## handler FUN_80149C48; deltas ignore terrain/Jump (units slide through/over
## geometry). See SPRITE_MOVE_INVESTIGATION.md.
func _op_sprite_move(inst: Dictionary) -> void:
	# {3B}: fixed duration = `Time` frames.
	var a := EventInstructionSet.args(inst)
	var intent := ScenarioDecode.sprite_move_intent(
		a, sprite_move_position_divisor, maxi(1, a.raw("Time", 1)), 0)
	ScenarioApply.sprite_move(intent, _world, sprite_move_position_divisor, _TICK_HZ,
		_play_through_max_dur_s(), "Sprite Move")


## Event-script Sprite Move Beta ({6E}). Same interpolator (FUN_80146940) as
## {3B} but the last field is `Speed` (opcode-units / frame) instead of a fixed
## `Time`, so the ROM derives the frame count as `sqrt(Σ Δ²·0x10)/Speed`
## = `4·dist / Speed` (the ×4 from the `·0x10` under the root — was missing
## before). Shares ROM handler FUN_80149C48.
func _op_sprite_move_beta(inst: Dictionary) -> void:
	var a := EventInstructionSet.args(inst)
	var intent := ScenarioDecode.sprite_move_intent(
		a, sprite_move_position_divisor, 0, maxi(1, a.raw("Speed", 1)))
	ScenarioApply.sprite_move(intent, _world, sprite_move_position_divisor, _TICK_HZ,
		_play_through_max_dur_s(), "Sprite Move Beta")


## The play-through duration clamp (seconds) for scripted motions/camera lerps: cap
## at `play_through_max_ticks` frames while play-through is on so an orientation
## race doesn't stall on an 8-minute slide; INF (no clamp) otherwise.
##
## ⚠️ **`{28} Walk To` IS EXEMPT AND MUST STAY EXEMPT** — see `_op_walk_to`. Every
## motion this caps has a duration the SCRIPT chose and can therefore make absurd; a
## walk's is emergent from a route buffer that holds at most 127 steps, so there is
## nothing here to protect against and capping it just abandons the unit mid-route.
func _play_through_max_dur_s() -> float:
	return (float(play_through_max_ticks) / _TICK_HZ) if play_through_skip_unknown else INF


## Return the unit's Sprite-Move BASE (tile) position — the `unit+0x40` anchor the
## PSX dialogue box projects, NOT the drawn sprite at `base + 0x60`. Captured in
## `_unit_move_home` on the unit's first Sprite Move (the `+0x60` offset is 0 then,
## so the seat == the world position); falls back to the unit's current world
## position for a never-moved unit (base == position, offset 0). This is the datum
## the box pool needs to reproduce PSX's base-vs-work split for pose-displaced
## speakers (e.g. Simon's carry pose, offset −64). See
## dialogue_box_triangle_aim_decode.md §9.6/§9.7.
func sprite_move_base_position(unit: Node) -> Vector3:
	if unit == null or not is_instance_valid(unit) or not ("global_position" in unit):
		return Vector3.ZERO
	# The home now lives on the actor keyed by uid, but this query has only the
	# node — match on the actor's owner_iid guard (the former iid-keyed lookup).
	var iid := unit.get_instance_id()
	for uid in actors:
		var a: ScenarioActor = actors[uid]
		if a.has_home and a.owner_iid == iid:
			return a.home
	return unit.global_position


## Event-script Wait Sprite Move ({6F}). The barrier that stalls the calling
## script context until the unit's in-flight Sprite Move finishes. We translate
## the move's remaining duration into VM `wait_ticks` (both advance at ~60 Hz);
## a step/rewind fast-play just plays the move out faster while this barrier
## holds the context. No active move → no wait.
func _op_wait_sprite_move(inst: Dictionary) -> void:
	_arm_motion_wait(_resolve_unit_key(EventInstructionSet.args(inst).raw("Unit")))


## True while actor `a`'s in-flight sprite-move [ScenarioMotion] has NOT finished —
## the single per-actor motion-liveness primitive. Both the unit-FILTERED motion
## barriers ({6F}/{29}/{64} via `motion_done`) and the unit-filter-FREE {E5}
## Task=11 kind-0x0B predicate read this one function, so the two liveness views
## can't drift apart (the split-model bug that let scn6's carry-down race ahead of
## its per-step barriers). A null actor / no motion is not live.
func _actor_motion_live(a: ScenarioActor) -> bool:
	return a != null and a.motion != null and not a.motion.is_done()


## Unified motion-completion predicate for the {6F}/{29}/{64}/{65} wait barriers
## (ADR-0055): a registered [ScenarioMotion] answers via `_actor_motion_live`; a uid
## with no motion falls back to the Unit-owned rotate stepper (`_rotate_done`), which
## itself short-circuits "done" for an absent/unresolved unit. So every motion wait
## asks the same question regardless of whether the unit is sliding, walking, or
## rotating.
func motion_done(uid: int) -> bool:
	var a := peek_actor(uid)
	if a != null and a.motion != null:
		return not _actor_motion_live(a)
	return _rotate_done(uid)


## Arm the shared motion-wait barrier on the current context: if the unit's motion
## is already done, don't block; otherwise hold the context (re-polling `motion_done`
## each tick) until it completes or the duration-derived watchdog fires. Collapses
## the {6F} Wait Sprite Move, {29} Wait Walk, and {64} Wait Rotate Unit barriers to
## one body (ADR-0055) — replacing the two old tick-countdown waits with a predicate.
func _arm_motion_wait(uid: int) -> void:
	if _current_ctx == null or motion_done(uid):
		return
	_arm_wait_until(_current_ctx, func() -> bool: return motion_done(uid),
		_motion_watchdog(uid))


## Watchdog-tick budget for a motion wait. A registered motion contributes its own
## duration (`ceil(dur_s·60) + slack`) so a legitimately long slide/walk isn't clipped
## by the default 10 s (`_WAIT_UNTIL_WATCHDOG_TICKS`) ceiling the predicate barrier
## inherits — the old tick-countdown waits had no watchdog. Floored at that ceiling
## for short motions and for the rotate fallback (which registers no motion).
func _motion_watchdog(uid: int) -> int:
	var a := peek_actor(uid)
	if a != null and a.motion != null:
		return maxi(_WAIT_UNTIL_WATCHDOG_TICKS, int(ceil(a.motion.dur_s * _TICK_HZ)) + 60)
	return _WAIT_UNTIL_WATCHDOG_TICKS


## Per-frame motion advance (Sprite Move + Walk To): step every active motion by
## `delta` seconds, resolve the node via `units_by_id`, write the eased world
## position, and pop motions that have reached their target. Per-unit so concurrent
## motions coexist. Walk-completion returns the body to idle (`_end_walk_anim`),
## gated on the FFT walk anim so a Sprite Move — which never enters that anim — is
## untouched; a resolved-away node is dropped without a write.
func _advance_motions(delta: float) -> void:
	for uid in actors.keys():
		var a: ScenarioActor = actors[uid]
		var m = a.motion  # ScenarioMotion (slide) or ScenarioPathMotion (walk) — duck-typed
		if m == null:
			continue
		var unit = units_by_id.get(uid)
		if unit == null or not is_instance_valid(unit) or not ("global_position" in unit):
			a.motion = null
			continue
		m.advance(delta)
		unit.global_position = m.position()
		# A Walk To route turn re-faces the body per segment (facing-only, no SEQ replay).
		if m.has_method("poll_facing_change"):
			var fd: int = m.poll_facing_change()
			if fd >= 0:
				_world.set_walk_facing(uid, fd)
		if m.is_done():
			# End the motion ON ITS END, not wherever the clock ran out. For an
			# unclamped motion this is what `position()` already returned; for a
			# CLAMPED one it is the difference between arriving and being abandoned
			# mid-route, because a `max_dur_s` clamp cuts a `ScenarioPathMotion`'s
			# frame count while `_track` still holds the whole trajectory. The seat is
			# latched on ARM (ADR-0219 dec. 6), so a unit left mid-route is a unit
			# whose transform contradicts its own logical cell. Same pair
			# `_drain_motions_to_target` uses for the chapel-trace burn-through.
			m.snap_to_end()
			unit.global_position = m.position()
			a.motion = null
			if "current_anim_id" in unit and unit.current_anim_id == FFT_WALK_ANIM_ID:
				_end_walk_anim(unit)


## Pump every scenario unit's anim clock one VM tick (ADR-0065). Scenario units
## are flipped to `tick_based` on `start()`, so their `Unit._process` delta pump
## no-ops and the frame index only advances here — once per VM tick — making the
## drawn pose a function of tick count, not host frame rate. Idempotently flips
## any unit not yet in tick mode (covers {47} ghost units spawned mid-run).
## Driven for ALL scenario units, cinematic or not: the same units were pumped by
## `Unit._process` before, and a live cinematic walker (which owns the BODY via
## `force_complete_body`) keeps ticking separately in `_tick_cinematic_walkers`.
func _advance_scenario_anim() -> void:
	# Command-mode Pause survey freeze-frame (ADR-0083): hold every SCENARIO-owned body clock so a
	# paused battlefield is a true freeze (both loops below). Distinct from `paused`, which lets a
	# scenario park breathe. The VM/CombatLoop double-pump is handled per-unit in
	# `_advance_unit_body_clock` (COMBAT-owned skipped), NOT here — this is only the Pause freeze.
	if survey_frozen:
		return
	# ONE UNIT, ONE DECISION PER TICK — the registry is keyed by EVENT ID and an event id is not
	# a unit. The deployed leader answers to `0x78` AND to the `0x01` protagonist alias
	# ([constant NavigatorMain.RAMZA_EVENT_UID]), so walking `keys()` and advancing as we go
	# reached that one body TWICE per tick: measured at Gariland, Ramza's idle ran at 120
	# sprite-frames/s against the other nine units' 60, through the whole opener and the whole
	# Deployment hold, and then HALVED at `_go_live` when the CombatLoop's single pump took over
	# — a 2x animation-rate step on the protagonist at the exact moment of the story→battle
	# handoff. ADR-0083's one-owner-per-unit invariant does not cover this: both advances came
	# from the SAME owner.
	#
	# So the two gates below are collected across EVERY id that names a body, and the advance is
	# applied once per body. Collecting rather than first-key-wins is load-bearing: `_units_by_id`
	# is insertion-ordered and the squad's `0x78`+ ids go in BEFORE the `0x01` alias, so a
	# first-key-wins dedupe would walk past a `{11}` paint mark left on `0x01` and advance a unit
	# that is supposed to be holding its freshly-painted frame 0.
	var pending: Array = []   # bodies to advance, in first-seen order
	var held := {}            # instance id -> true, a body some id says to hold this tick
	var seen := {}            # instance id -> true, so a body is queued once
	for uid in units_by_id.keys():
		var unit = units_by_id[uid]
		if unit == null or not is_instance_valid(unit):
			continue
		var iid: int = unit.get_instance_id()
		if not seen.has(iid):
			seen[iid] = true
			pending.append(unit)
		# {11} latch consume-before-advance ordering (§8g Gap B): a unit whose
		# pending pose was PAINTED this tick holds its freshly-set frame 0 — the
		# PSX consumer paints `+0x1DC` and zeroes the frame counter without also
		# advancing a SEQ frame; the NEXT tick (latch now empty, uid unmarked)
		# advances it. Skip its `advance_frame` for exactly this one tick.
		if uid in _painted_this_tick:
			held[iid] = true
			continue
		# {43} dead-unit fade freezes the corpse's body clock. This is a PORT-LEVEL
		# STAND-IN, not a transcription — the ROM has no clock freeze here, and the
		# reason it needs none is the POSE, not any byte `FUN_8008945c` writes
		# (SCENARIO6_DEAD_UNIT_FADE.md §5.6).
		#
		# STATIC: `FUN_8008719c` @ `0x8008719C` walks `unit_sprite_list_head`
		# (`0x80098A54`) every vsync and calls `unit_anim_state_machine` @
		# `0x80085C0C` UNCONDITIONALLY for every sprite object — there is no gate in
		# the walker. The state machine's only early-out is `lhu v0,0xa(s2)` @
		# `0x80085D94` → `beq v0,zero` @ `0x80085D9C`, and `+0xa` is not among the
		# fade's stores. Each candidate dies to its own readers: `+0x13e` is read only
		# by `unit_team_recolor_gate` @ `0x800822C4` and the palette machine
		# `FUN_800870ac` @ `0x800870BC` (both pure palette); `+0x12` is read at
		# `0x80085E44`/`0x800861CC`/`0x80086354`, all three `andi 0xfff9` + `or` +
		# store — it WRITES mirror bits 1-2 and never TESTS the byte, so bits 0/5/6
		# are render/tpage; `+0x74`/`+0x76` are never read by the state machine at all.
		#
		# DYNAMIC (`scenario6_pre_deadunit_fade.sstate`, PCSX-Redux): a KO'd unit is
		# parked in a terminal KO pose (`+0x1dc` = 0x34/0x35, wait timer `+0x1e2` = 0)
		# that does not advance, fade or no fade. Across ~240 frames spanning the arm,
		# every swept corpse's anim block `+0x1d8..+0x1e5` stayed byte-identical
		# (`0100000035000200180000000000`) while living slots 00/01/02/0A advanced
		# every sample. The control that settles it: slot 03 is a corpse on the
		# PERSISTING side — never swept, `+0x13e` stays 0 — and it is exactly as
		# frozen. So the stillness is the KO pose's, and the fade is incidental to it.
		#
		# We still freeze because our swept set is chosen by SIDE (`_is_dead_unit_fade_target`),
		# not by hp, so it can include units that are NOT in a KO pose — a freshly-spawned
		# scenario enemy would otherwise keep running its idle/spawn clock and visibly
		# "stand up"/bob through the ~40-frame dissolve. The faithful fix is to put the
		# swept units into the KO pose and let the clock run; until then this holds the
		# current frame for the whole fade window — the uid leaves `_dead_unit_fades`
		# only when it's removed (hidden), after which resuming its clock is moot.
		if int(uid) in _dead_unit_fades:
			held[iid] = true
			continue
	for unit in pending:
		if held.has(unit.get_instance_id()):
			continue
		_advance_unit_body_clock(unit)
	# Extra idle-only units (e.g. the navigator's deployed generics) ride the SAME tick —
	# no {11}/{43}/uid gating (they carry no uid and take no opcode). One clock, ADR-0065.
	# NOT deduped against `pending`: this list is the REMAINDER by construction
	# (`NavigatorMain._register_deployed_idle_pump`), and a unit on both is a registration bug
	# the remainder exists to prevent — silently absorbing it here would hide it.
	for unit in idle_only_units:
		_advance_unit_body_clock(unit)


## Advance one unit's body/SEQ clock by a single VM tick. The shared per-unit advance for
## `_advance_scenario_anim`'s `units_by_id` pump AND its `idle_only_units` pump, so both ride
## exactly one clock (ADR-0065). Null/validity + capability guarded.
##
## The single-owner filter (ADR-0083) lives here: a unit a `CombatLoop` owns (COMBAT) is SKIPPED —
## the CombatLoop tick is its sole clock, so the VM pump running over the same node would
## double-advance it (racing the SEQ 0xDE hit-cloud opcode past the GPU damage tick, or idle-walking
## a paused cast). A unit still SELF-owned when the VM first sees it is CLAIMED for SCENARIO (covers
## {47} ghost units spawned mid-run). Only drives units whose claim actually took: a real Unit's
## `clock_owner` setter is a no-op until its `display` exists (Unit._ready), so a not-yet-initialized
## unit stays SELF and is skipped rather than crashing on `display.advance_frame` (bare-Unit harnesses).
func _advance_unit_body_clock(unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if not ("clock_owner" in unit) or not unit.has_method("advance_frame"):
		return
	if unit.clock_owner == ClockOwner.COMBAT:
		return  # CombatLoop owns this body — its tick is the sole clock (ADR-0083)
	if unit.clock_owner == ClockOwner.SELF:
		unit.clock_owner = ClockOwner.SCENARIO  # claim (e.g. {47} ghost spawns)
	if unit.clock_owner != ClockOwner.SELF:  # claim took (display exists)
		unit.advance_frame()


## Event-script {28} Walk To. Grid relocation: walk the unit from its current
## position to tile (X, Y) at `Speed`, advancing its tile (the new home). The
## chapel walk-in is Warp (stage) → Sprite Move (slide on) → Walk To (seat); the
## handler was a skip-stub, which stranded the three actors at the entry column
## (HANDOFF_unit_tile_alignment.md, 2026-06-28). Operand layout
## (`28 Unit X Y Z Unknown Speed`): `Y` is the grid Z row, `Z` is the TERRAIN LEVEL.
##
## First-cut motion: a straight world-space lerp through to the seat (the chapel
## floor is open, so a path-around isn't needed for scenario 1). FFT's Walk To
## is 4-directional A* — left as a refinement; the endpoint tile is exact.
func _op_walk_to(inst: Dictionary) -> void:
	var a := EventInstructionSet.args(inst)
	# event-Y is already the Godot grid Z row (parser pre-flipped, ADR-0057). `Z` is
	# the TERRAIN LEVEL and is carried (ADR-0219 dec. 7). It used to be dropped under
	# a comment asserting it was a height the map re-derived from the seat tile; that
	# premise was false twice over — `Z` indexes `tile_ptr`'s bounds-checked third
	# argument (`sltiu v0,a2,0x2` @ 0x8018400c) and is binary over all 634 exported
	# unit-placement instructions, and at MAP009 (4,11) there are TWO seat tiles, so
	# "the seat tile" does not name one. Dropping it is what walks Algus through the
	# Igros moat instead of over the bridge.
	# Speed is ONE 16-bit 8.8 fixed-point operand, not the single `Speed` byte the
	# catalog names — the low byte is a 1/256 fraction the ROM reads in the same
	# `lhu` (ScenarioDecode.walk_to_speed). Five of the six corpus instructions that
	# carry a nonzero fraction are in this scenario, and pc 34's 3.5 (not 3) is what
	# kept Algus sliding through his own opening line.
	# The LAST operand byte is the movement-cost switch, and the catalog names it
	# `Unknown` — the same name as the byte before `Speed`, so it cannot be read by
	# name. `0` flattens the whole cost row to 1 (`FUN_8017813C`, research README
	# §20.1); 20 of the 561 shipped `{28}`s do it, and on those the planner stops
	# routing around water.
	var switch_i := a.index_of("Speed") + 1
	var flat_cost := switch_i > 0 and a.nth(switch_i, 1) == 0
	# 🔴 `INF`, NOT `_play_through_max_dur_s()`. A Walk To is the one scripted motion
	# whose duration is EMERGENT and BOUNDED BY CONSTRUCTION — the stepper runs the
	# whole route at arm time and the frame count is what came out, and a route buffer
	# holds at most 127 steps (the longest shipped corpus route is 12 tiles). The
	# play-through cap exists so an orientation race can't stall a seek on an 8-minute
	# camera slide; a walk cannot be 8 minutes, so capping it only truncates it.
	#
	# What that cost, measured on scenario 29 seeking to PC 148: the three walks in
	# are 169, 215 and 215 ROM frames and every one was armed at 60, so each unit
	# walked a quarter of its route and stopped — in the Igros moat, never having
	# armed the leap. It compounds, because `ScenarioApply.walk_to` seats the unit's
	# logical cell at ARM time (ADR-0219 dec. 6): a truncated walk leaves the seat and
	# the transform disagreeing, and `_unit_cell` then discards the latched level.
	# Pre-dates the ADR-0226 port — the port only made it legible, by giving the route
	# a leap to visibly skip. ScenarioSeekWalkTruncationTest.
	ScenarioApply.walk_to(a.raw("Unit"), a.raw("X"), a.raw("Y"),
		maxf(1.0, ScenarioDecode.walk_to_speed(a, 8.0)), _world,
		sprite_move_position_divisor, _TICK_HZ,
		INF, FFT_WALK_ANIM_ID, a.raw("Z", 0), flat_cost)


## Plan a `{28} Walk To` route for unit `uid` to tile (`tx`, `tz`, `level`) — the
## ROM's own planner ([EventPathfinder]), over the ROM's own tiles ([RomTerrain]),
## emitting the ROM's own route BYTE BUFFER.
##
## TERRAIN ONLY: other units do not block, so the route walks straight through them
## (the `a0 = 3` map build skips occupancy — `EventPathfinder` header).
##
## 🔴 **A REFUSED WALK IS A NO-OP, NOT A SHORTER WALK.** This used to hand back the
## reachable tile NEAREST an unreachable target. `FUN_8017813C` has no such fallback:
## it returns NULL and the opcode does nothing. So `{}` now means both "no map" and
## "the ROM would not have walked", and the caller bails either way. Measured before
## the switch: over the 209 replayable shipped `{28}`s, **zero** routes newly stop
## short — including under the destination gate, which the corpus replay had never
## applied.
##
## Returns `{start, target, endpoint, waypoints, terrain, psx_start, route,
## psx_rows, world_y_at_start, grid_origin}`, or `{}`.
##   * `waypoints` is the route's world-space tile centres, kept so "where does this
##     walk end" is answerable without replaying the trajectory;
##   * `terrain` / `psx_start` / `route` are what `ScenarioPathMotion.configure_rom`
##     needs, and they are in PSX coordinates. `psx_rows` is the map's `size_z`, the
##     ADR-0052 mirror the motion undoes.
## The cell a scenario actor is standing on, level included.
##
## The grid axes come from the transform, as they always did. The LEVEL is read off
## the unit's own `current_cell` and never re-derived (ADR-0219 dec. 6): a warp or a
## previous walk latched it there, and world Y cannot answer it — a bridge deck and
## the water beneath it occupy the same two grid axes. A unit with no movement
## component, or one that has never been placed, falls back to the column's ground,
## which is where every actor stood before the upper level existed.
func _unit_cell(unit) -> Vector3i:
	var gx := int(floor(unit.global_position.x))
	var gz := int(floor(unit.global_position.z))
	var mc = unit.get("movement_component") if unit != null else null
	if mc != null and is_instance_valid(mc):
		var held: Vector3i = mc.current_cell
		if held != TerrainCell.NONE and held.x == gx and held.y == gz:
			return held
	return TerrainCell.ground(gx, gz)


func _plan_walk_route(uid: int, tx: int, tz: int, level: int = 0,
		flat_cost: bool = false) -> Dictionary:
	if map_composer == null:
		push_warning("[ScenarioVM] Walk To: no map_composer ref")
		return {}
	var lattice: Lattice = _lattice()
	if lattice == null:
		push_warning("[ScenarioVM] Walk To: no lattice")
		return {}
	# The ROM plans over the MAP FILE, not over the scene's lattice. `TerrainCell`
	# carries height and two flags; the planner reads eight fields per tile, and the
	# other four — depth, slope height, slope type, thickness — decide the leap, the
	# gait bits and every ceiling test. They are all in `terrain.json` already (#819).
	var terrain = RomTerrain.load_map(RomTerrain.map_name_for(current_map_id))
	if terrain == null:
		# A scene with no `map_id`, or a map with no export. One planner still runs —
		# on a POORER map: a `TerrainCell` states four of the eight bytes, so there is
		# no depth, no drape and no ceiling, and therefore no gait bits and a
		# leap-clearance test that sees only floors. Warned, because a silent
		# downgrade of the map under a planner scored on real tiles reads as a routing
		# bug months later.
		terrain = RomTerrain.from_lattice(lattice)
		if terrain == null:
			push_warning("[ScenarioVM] Walk To: no terrain.json for map %d and no "
				% current_map_id + "lattice cells — cannot plan")
			return {}
		if not _warned_lattice_terrain:
			_warned_lattice_terrain = true
			push_warning("[ScenarioVM] Walk To: map %d has no terrain.json; routing "
				% current_map_id + "off the lattice, which states no depth, slope or "
				+ "thickness — no leap clearance and no gait bits (ADR-0226)")
	var unit = units_by_id[uid]
	var start_cell := _unit_cell(unit)
	var ny: int = terrain.ny
	# ADR-0052, applied ONCE, here: the planner and the stepper both live in PSX
	# coordinates and the Godot grid is the mirror of them about `size_z - 1`.
	var psx_start := Vector3i(start_cell.x, ny - 1 - start_cell.y, start_cell.z)
	var psx_dest := Vector3i(tx, ny - 1 - tz, level)
	# The `{28}` operand's own cost switch: its last byte flattens the whole movement
	# cost row, which is how a scenario walks a unit across water it would otherwise
	# route around. 20 of the 561 shipped instructions set it.
	var cost: PackedInt32Array = EventPathfinder.flat_cost_row() if flat_cost \
		else EventPathfinder.cost_row(1)
	var plan: Dictionary = _event_pathfinder.plan(terrain, psx_start, psx_dest, cost)
	if not plan["reached_target"]:
		print("[ScenarioVM] Walk To 0x%02X (%d,%d,L%d) -> (%d,%d,L%d) REFUSED by the ROM's planner: %s"
			% [uid, start_cell.x, start_cell.y, start_cell.z, tx, tz, level,
				String(plan["refused"])])
		return {}
	# Back to the Godot grid for everything the scene needs to say.
	var cells: Array = plan["cells"]
	var waypoints: Array[Vector3] = []
	var prev_y: float = unit.global_position.y
	var endpoint := Vector3i(tx, tz, level)
	for i in cells.size():
		var c: Vector3i = cells[i]
		var g := Vector3i(c.x, ny - 1 - c.y, c.z)
		if i == 0:
			waypoints.append(unit.global_position)
			continue
		var wy: float = lattice.world_position_at(g).y \
			if lattice.terrain_at(g) != null else prev_y
		prev_y = wy
		waypoints.append(Vector3(float(g.x) + 0.5, wy, float(g.y) + 0.5))
	var endpoint_y: float = waypoints[waypoints.size() - 1].y
	return {
		"start": unit.global_position,
		"target": Vector3(float(tx) + 0.5, endpoint_y, float(tz) + 0.5),
		"endpoint": endpoint,
		"waypoints": waypoints,
		"terrain": terrain,
		"psx_start": psx_start,
		"route": Array(plan["route"] as PackedByteArray),
		"psx_rows": ny,
		"world_y_at_start": unit.global_position.y,
		"grid_origin": Vector2i.ZERO,
	}


## Event-script {29} Wait Walk — barrier that stalls the calling context until
## the unit's in-flight Walk To finishes (mirrors `_op_wait_sprite_move`).
func _op_wait_walk(inst: Dictionary) -> void:
	_arm_motion_wait(_resolve_unit_key(EventInstructionSet.args(inst).raw("Unit")))


## Event-script {64} Wait Rotate Unit — predicate barrier that holds the calling
## context until the unit's in-flight `scenario_rotate` finishes. PSX FUN_801498fc
## (@ 0x801498fc) yields one frame at a time, polling the unit's 7-byte command's
## +4 "rotation active" flag until it clears; the consumer clears it the moment
## current facing reaches the target. `_rotate_done` is the Godot analogue: an
## empty `_rotate_state` ⇔ +4 == 0. An absent/unresolved unit short-circuits to
## "done" (PSX's 0x7d0 not-deployed → don't block).
func _op_wait_rotate_unit(inst: Dictionary) -> void:
	_arm_motion_wait(_resolve_unit_key(EventInstructionSet.args(inst).raw("Unit")))


## Event-script {65} Wait Rotate All — same barrier across every deployed unit
## (PSX passes a0 = -1, looping all 21 handles; done only when every +4 flag is
## 0). Holds until no unit has an active `scenario_rotate`.
func _op_wait_rotate_all(_inst: Dictionary) -> void:
	if _current_ctx == null or _all_rotations_done():
		return
	_arm_wait_until(_current_ctx, func() -> bool: return _all_rotations_done())


## True when the unit resolved to `uid` has no active rotation — either it's
## absent/invalid (not deployed; PSX short-circuits the same way via the 0x7d0
## sentinel) or its `_rotate_state` stepper has cleared (facing reached target).
func _rotate_done(uid: int) -> bool:
	if uid < 0 or not units_by_id.has(uid):
		return true
	var unit = units_by_id[uid]
	if unit == null or not is_instance_valid(unit):
		return true
	if not ("_rotate_state" in unit):
		return true
	return unit._rotate_state.is_empty()


## True when no deployed unit has an active `scenario_rotate` stepper (the {65}
## Wait Rotate All completion predicate).
func _all_rotations_done() -> bool:
	for uid in units_by_id.keys():
		if not _rotate_done(uid):
			return false
	return true


# --- {54}/{55}/{56}/{57} Use/Wait 3D/Field Object ----------------------------
#
# Map textured-animation objects. Full live-validated PSX decode:
# research/working_documents/scenario_1_captures/use_field_object_decode.md.
# Stage 1: latch the request + model a duration so the {56}/{57} barriers
# resolve with plausible timing (no real map animation rendered yet — Stage 2).

## Per-tick pump for the modeled field/3D-object animations — the Godot analogue
## of the PSX consumer FUN_80143418's completion poll (FUN_800f0be0 cmd 0x82/
## 0x81), which clears the active flag (0x80166070 / 0x8016606e) when the
## animation ends. Each record's `ticks_left` drains; a record is erased when it
## reaches 0, releasing any {57}/{56} barrier waiting on it. Stage 2 replaces
## this with the real `MapComposer.is_animation_active(id)` completion signal.
func _tick_field_objects() -> void:
	for id in _field_objects.keys():
		var rec: Dictionary = _field_objects[id]
		rec["ticks_left"] = max(0, int(rec["ticks_left"]) - 1)
		if rec["ticks_left"] == 0:
			_field_objects.erase(id)
	for id in _threed_objects.keys():
		var rec: Dictionary = _threed_objects[id]
		rec["ticks_left"] = max(0, int(rec["ticks_left"]) - 1)
		if rec["ticks_left"] == 0:
			_threed_objects.erase(id)


## Event-script {55} Use Field Object — start textured-anim #ID on the map mesh.
## Non-blocking (PSX latches the request + yields once via Thread_doNext; the
## next opcode in the chapel scene is a `Wait 6`, so a plain return matches the
## observed cadence). PSX: handler @0x801447fc latches ID into 0x80174058 +
## a use-pulse 0x80165fe4; the per-frame consumer FUN_80143418 picks it up ->
## FUN_8008e11c(ID,arg2) -> FUN_800f0be0(cmd=0x83,ID) which copies the map
## Mesh-Resource descriptor #ID (table 0x80121d7c) into the active slot and
## arms it (duration 0x7e). Stage 2: the map renders descriptor #ID for real via
## MapComposer.play_texture_animation(id) — a source→canvas blit on the indexed
## atlas, the Godot analogue of the PSX VRAM copy. Falls back to the modeled
## tick drain when the map has no animator (e.g. a stale export).
func _op_use_field_object(inst: Dictionary) -> void:
	var a := EventInstructionSet.args(inst)
	ScenarioApply.use_field_object(a.raw("ID"), a.raw("Unknown"), _world)


## Attempt the {55} Use Field Object map texture-animation render for `id`, falling
## back to a modeled-timer record (+ a diagnostic warning) when the map can't render
## it. Returns whether it really rendered. The map-composer access, the modeled
## `_field_objects` fallback state, and `_field_anim_rendered_id` are VM/scene
## machinery the `play_field_object` verb wraps; the {57} Wait barrier polls them.
func _play_field_object_render(id: int, arg2: int) -> bool:
	_field_anim_rendered_id = -1
	var can_render := map_composer != null and map_composer.has_method("play_texture_animation")
	if can_render:
		map_composer.play_texture_animation(id)
		if map_composer.has_method("is_animation_active") and map_composer.is_animation_active(id):
			_field_anim_rendered_id = id
	if _field_anim_rendered_id < 0:
		# Modeled fallback: no real render, drain a plausible duration. Don't fail
		# silently — a field object showing nothing (e.g. the chapel door at {55}
		# ID=1) is almost always a stale/missing map export.
		_field_objects[id] = {"ticks_left": _FIELD_OBJ_DEFAULT_TICKS, "arg2": arg2}
		if can_render:
			# The map accepted the request but the slot never went active → the
			# parsed manifest lacks `animations.texture_animations` for this map.
			# Fix: reparse maps, e.g.
			#   uv run --project tools python tools/parse_all_maps.py <MAP_DIR> --force
			push_warning("[ScenarioVM] {55} Use Field Object id=%d did NOT render — map '%s' has no active texture-animation slot (likely a stale export missing animations.texture_animations; reparse maps). Falling back to a timed no-op." % [id, str(map_composer.name) if map_composer else "?"])
		else:
			push_warning("[ScenarioVM] {55} Use Field Object id=%d: no map_composer render path available; using modeled timer fallback." % id)
	return _field_anim_rendered_id >= 0


## Event-script {57} Wait Field Object — barrier until the field-object
## animation completes. Takes NO operands (PSX waits on "the" single active
## slot, polling 0x80166070 until the consumer clears it). Here: hold until no
## field-object record is active. If none is active when {57} runs, return
## immediately (PSX's flag would already read 0). PSX: spin-loop @0x80144830.
func _op_wait_field_object(_inst: Dictionary) -> void:
	if _current_ctx == null:
		return
	# Real render in flight: barrier on the map's completion signal (PSX flag
	# 0x80166070 analogue).
	if _field_anim_rendered_id >= 0 and map_composer != null \
			and map_composer.has_method("is_animation_active"):
		var aid := _field_anim_rendered_id
		if not map_composer.is_animation_active(aid):
			_field_anim_rendered_id = -1
			return
		_arm_wait_until(_current_ctx, func() -> bool:
			var still: bool = map_composer.is_animation_active(aid)
			if not still:
				_field_anim_rendered_id = -1
			return not still)
		return
	# Modeled fallback.
	if _field_objects.is_empty():
		return
	_arm_wait_until(_current_ctx, func() -> bool: return _field_objects.is_empty())


## Event-script {54} Use 3D Object — set 3D-object #ID to State. PSX: handler
## @0x80144790 latches ID->0x80173c94, State->0x80173c96 + use-pulse 0x80165fe2;
## consumer -> FUN_8008e0bc(ID,State) -> FUN_800f0be0(cmd=0x80,ID,State). Doesn't
## appear in the chapel scene; registered so the next scenario doesn't halt. The
## `State` operand selects the object's state/animation (stashed for Stage 2).
func _op_use_3d_object(inst: Dictionary) -> void:
	var a := EventInstructionSet.args(inst)
	ScenarioApply.use_3d_object(a.raw("ID"), a.raw("State"), _world)


## Event-script {56} Wait 3D Object — barrier until the 3D-object animation
## completes (PSX: spin-loop @0x801447c4 on flag 0x8016606e). No operands.
func _op_wait_3d_object(_inst: Dictionary) -> void:
	if _current_ctx == null or _threed_objects.is_empty():
		return
	_arm_wait_until(_current_ctx, func() -> bool: return _threed_objects.is_empty())


## Chapel-trace burn-through: snap EVERY in-flight motion — Sprite Move too, new
## per ADR-0055; previously only Walk (and Rotate, separately) drained, so the trace
## sampled slides mid-flight — to its target and clear the registry. This makes the
## per-opcode snapshot reflect the end-of-slide/seated state PSX renders after the
## cinematic Wait. Mirrors `_drain_unit_rotations_to_target` (Rotate stays Unit-owned
## and drains separately). Walk-completion returns the body to idle, gated on the FFT
## walk anim so a snapped Sprite Move is untouched.
func _drain_motions_to_target() -> void:
	for uid in actors.keys():
		var a: ScenarioActor = actors[uid]
		var m = a.motion  # ScenarioMotion or ScenarioPathMotion — duck-typed
		if m == null:
			continue
		var unit = units_by_id.get(uid)
		if unit != null and is_instance_valid(unit) and ("global_position" in unit):
			m.snap_to_end()
			unit.global_position = m.position()
			if "current_anim_id" in unit and unit.current_anim_id == FFT_WALK_ANIM_ID:
				_end_walk_anim(unit)
		a.motion = null


## Return a unit to idle when its Walk To completes. Mirrors PSX: the moment the
## route buffer clears, the unit's SEQ key flips from the walk (29) back to the
## standing idle (4). We only undo OUR walk anim (`FFT_WALK_ANIM_ID`) so a walk
## interrupted by another opcode that already re-armed the body isn't clobbered.
## The activity reset is kept for any combat-context caller of the walk lerp.
func _end_walk_anim(unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if "current_anim_id" in unit and unit.current_anim_id == FFT_WALK_ANIM_ID:
		unit.play_body(0)  # idle anchor (clock_key "1")
	if "anim_state" in unit and unit.anim_state != null:
		unit.anim_state.current_state = DisplayActivity.Activity.IDLE


## Cinematic placement: position the unit at the tile's world coordinates
## without reserving the tile. Cinematics routinely overlap units on the same
## tile (e.g., scenario 1 warps both 0x17 and 0x84 to (1,4)); the gameplay
## tile-reservation system from `Unit.place_on_tile()` would reject the
## second warp, so we bypass it.
static func cinematic_place(unit: Node3D, grid_x: int, grid_z: int, lattice: Lattice,
		level: int = 0) -> void:
	if lattice == null:
		push_warning("[ScenarioVM] cinematic_place: no lattice")
		return
	# `{24} Warp Unit` carries the same `Z` level byte `{28} Walk To` does — binary
	# over 352 instructions in the corpus (ADR-0219). Asked for a specific level, place
	# on it; asked for nothing, take the column's ground rather than guessing a level
	# that may not exist there.
	var cell: TerrainCell = lattice.terrain_at(Vector3i(grid_x, grid_z, level)) \
		if level != 0 else lattice.ground_at(grid_x, grid_z)
	if cell == null:
		push_warning("[ScenarioVM] cinematic_place: no tile at (%d,%d,L%d)" %
			[grid_x, grid_z, level])
		return
	unit.global_position = Vector3(
		float(grid_x) + 0.5, lattice.world_position_at(cell.grid).y, float(grid_z) + 0.5)


## Force-skip the current opcode and resume execution. Useful when the VM
## halts on an unhandled opcode (like the first Display Message) — the debug
## panel's "Skip Halt" button calls this to advance past the wall manually.
## Operates on the MAIN context (slot 0); parallel block contexts are not
## addressable from the debug panel today. No-op if the PC is already at
## end-of-chunk.
func force_skip_current() -> void:
	if _contexts.is_empty():
		return
	var main_ctx: ScriptContext = _contexts[0]
	if main_ctx.pc >= _insts.size():
		return
	var inst = _insts[main_ctx.pc]
	print("[ScenarioVM] force-skip '%s' @0x%X (pc=%d)" %
		[str(inst.get("name", "?")), int(inst.get("offset", 0)), main_ctx.pc])
	main_ctx.pc += 1
	_running = true
	main_ctx.wait_ticks = 0


## Block→segment hardcode for the chapel cinematic. Scenario 1's Load EVTCHR
## emits `Block=1, Slot=0x88`, but RAM at 0x800AED3C byte-matches segment 0 of
## EVTCHR.BIN, so the engine's Slot→segment indirection isn't identity. Until
## that indirection is traced (issue #124), block 1/2 both resolve to segment 0
## — the only cinematic we render today.
##
## Default-to-segment-0 even when no Load EVTCHR has fired: the chapel chunk
## we play is actually scenario 2, and scenario 1 ("Setup") — which is what
## issues the real Load EVTCHR on PSX — isn't extracted yet (see
## `ScenarioPlayerScene.gd` for the same caveat with initial facings). Until
## Setup-chunk extraction lands, segment 0 is the right pose set for the only
## cinematic this Godot side runs.
## Classify a body anim id into the base of its cinematic band, or -1 when it is
## a low-range SEQ anim (not cinematic). PSX (`FUN_80084818`,
## `research/working_documents/scenario_1_captures/cinematic_seq_source_decode.md`)
## splits cinematic ids into two runtime SEQ tables, each with its own zero-based
## slot:
##   * mid  `[0x1F4, 0x258)` → base `0x1F4` (scenario 6 carry, table `0x800A77D8`)
##   * high `[0x258, …)`     → base `0x258` (Orbonne chapel,  table `0x800AED3C`)
##   * low  `[1, 0x1F4)`      → not cinematic (per-unit SHP SEQ) → returns -1
## The per-band local index into `cinematic_seq.json[seg]` is
## `anim_id - _cinematic_band_base(anim_id)`. The boundary is 0x1F4 (NOT the
## chapel's 0x258) — the whole mid band used to fall through to the SEQ path and
## freeze. See `SCENARIO6_CARRY_POSE_EVTCHR_RENDER.md`.
static func _cinematic_band_base(anim_id: int) -> int:
	if anim_id >= 0x258:
		return 0x258
	if anim_id >= 0x1F4:
		return 0x1F4
	return -1


## The EVTCHR BLOCK (VRAM page) a cinematic anim id reads from — mid band → 0,
## high band → 1; -1 for a non-cinematic id.
##
## FFT keeps TWO EVTCHR pages resident at once: the 2-entry rect table at
## `0x800880a8` maps block 0 → VRAM (256,0) and block 1 → (320,0), each a
## 256x200 4bpp page. Each loaded segment carries its OWN cinematic SEQ table at
## `+0x0000..+0x04FF`, and `{58} Load EVTCHR {Block:B}` installs that table as
## block B's — the runtime keeps exactly the two `_cinematic_band_base` names
## (mid `0x800A77D8`, high `0x800AED3C`). Two tables, two pages: the band selects
## the TABLE, therefore the PAGE. So this is a fixed map, not a heuristic.
##
## Corpus-wide (replay of all 500 chunks): across 2711 cinematic anims in chunks
## that load ONLY block 1, not one is mid-band. See
## `research/working_documents/EVTCHR_CHARACTER_ATTRIBUTION.md` § "The band
## selects the PAGE".
static func _cinematic_band_block(anim_id: int) -> int:
	match _cinematic_band_base(anim_id):
		0x1F4:
			return 0
		0x258:
			return 1
	return -1


## Which EVTCHR block a cinematic `{11}` paints from: the anim BAND's block when
## that block is resident, else the fallback (`_active_evtchr_block`).
##
## The fallback is not a tie-break, it is the one-page case. A chunk that loads
## only ONE block cannot honour the band for the other one — scenario 461 loads
## `{Block:0, Slot:132}` and then plays BOTH bands off it (mid 500-508 and high
## 607-610/635 on unit 0x80), and the Orbonne chapel issues its `{58}` in the
## un-extracted Setup scenario 1 so nothing is loaded here at all and block 2 →
## seg 0 has to survive. Those are the only shapes in which band and outcome
## differ corpus-wide.
##
## `{7F} EVTCHR Palette {Unit, Block, Palette}` is deliberately NOT consulted.
## An earlier reading made it a per-unit page binding that overrides the band;
## the replay refutes that. It disagrees with the band 6 times in 115 bindings,
## and every disagreement is one where the band is right: scenario 283 gives
## units 100 and 101 `Block=0` and `Block=1` and then plays the SAME mid anim 521
## on both back-to-back (one anim cannot be two pages), and scenario 167's
## `{7F} Unit=133 Block=1` precedes mid anim 514 sitting inside the contiguous
## 500-520 run that block 0 / Slot 41 was loaded for 85 instructions earlier.
## `{7F}`'s Block is the palette-upload counter it waits on (`FUN_8013b590(Block)
## >= Palette`), not the unit's page. It stays `_skip`ped in the registrar.
func _resolve_cinematic_block(anim_id: int) -> int:
	var band_block := _cinematic_band_block(anim_id)
	if band_block >= 0 and _evtchr_block_to_slot.has(band_block):
		return band_block
	return _active_evtchr_block


func _resolve_cinematic_segment(block: int) -> int:
	# Debug-panel override wins so we can flip segments live.
	if cinematic_segment_override >= 0:
		return cinematic_segment_override
	# The live `Load EVTCHR` Slot is the segment for the identity scenarios
	# (scenario 6: `Slot 1 → seg 1`, proven by a 28/28 frame-id byte-match
	# against the live PSX mid-cinematic table — see
	# `SCENARIO6_CARRY_POSE_EVTCHR_RENDER.md` §4.3). When no Load EVTCHR has
	# fired (the chapel issues its own in the un-extracted Setup scenario 1),
	# fall back to segment 0 — the only pose set that Godot side runs today.
	# TODO(#124): the chapel's non-identity `Slot 0x88 → seg 0` still needs the
	# real BATTLE.BIN Slot→segment table; that's the remaining #124 special-case.
	return int(_evtchr_block_to_slot.get(block, 0))


func _op_unit_anim(inst: Dictionary) -> void:
	# `flag` (0=unset move-flag-bit-1, 1=flip) is advisory in Godot — our SEQ
	# playback runs to completion regardless. The range-dispatch animation machine
	# (_apply_unit_animation) stays VM-side, reached via the play_unit_anim verb.
	ScenarioApply.unit_anim(ScenarioDecode.unit_anim(EventInstructionSet.args(inst)), _world)


## {80} March (opcode 0x80; params Units:1, Multi:1, Time:1). NOW RE'd
## (MARCH_OPCODE_80_SEMANTICS.md, 2026-08-01): March does NOT start a walk. It RE-APPLIES
## each ADDRESSED unit's status-default animation — it RELEASES a unit from a cinematic
## pose back to the combat-idle "march in place" it already had by spawn default. In the
## port that idle is `is_cinematic_unit == false` (Unit.gd); most units are already there
## by `scenario_spawn_facing` (change #1), so March only needs to release the units the
## selector names. ROM handler FUN_80149490 @0x80149490: resolve the (Units,Multi) selector,
## re-run the status-anim selector per member. Gariland is SINGLE (Units=0x80) → releases
## ONLY the dialogue speaker (frozen by its {11} at PC8), lockstep (Time=0); everyone else
## was never frozen. So this HONORS the selector (via ScenarioApply.march → resolve_unit_set)
## instead of the old blanket flip that wrongly touched every unit (living doc §5).
func _op_march(inst: Dictionary) -> void:
	var a := EventInstructionSet.args(inst)
	ScenarioApply.march(a.raw("Units"), a.raw("Multi"), a.raw("Time"), _world)


## Apply an event-script animation id to a resolved unit. Shared by {11} Unit
## Anim and {8C} Unit Anim Rotate (which both route through the ROM's
## BATTLE_set_unit_anim_value).
##
## Dispatch-time entry ({11} Unit Anim / {8C} Unit Anim Rotate anim, via the
## play_unit_anim verb). LATCH ONLY — the Godot mirror of the PSX writer
## `set_unit_animation_with_flags`, which writes `anim_id+1` to `unit+0x0C` and
## paints NOTHING (SCENARIO_WAIT_SEMANTICS.md §6b/§7b Finding 5). Records the
## pending anim on the actor (last-write-wins = the PSX single `+0x0C` slot); the
## per-tick consumer `_consume_pending_body_anims` paints it on the NEXT elapsed
## tick — so the visible pose update lands on the Wait that FOLLOWS the {11}, not
## on {11} itself. Returns false (with a warn) if the unit's sprite pipeline isn't
## ready yet (matching the old immediate-apply contract callers assert on).
func _apply_unit_animation(unit, uid: int, anim_id: int) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	if unit.animation_set == null or unit.display == null or unit.display.type1_playback == null:
		print("[ScenarioVM] WARN Unit Anim 0x%04X — unit not ready" % uid)
		return false
	actor(uid).pending_anim = anim_id
	return true


## Drain every pending {11} anim latch — the clear-and-paint half of the PSX
## `FUN_8008719C → FUN_80085C0C` per-frame step (SCENARIO_WAIT_SEMANTICS.md §8g).
## For each actor with a pending anim (>= 0): paint it via `_paint_unit_animation`,
## clear the latch (`pending_anim = -1`), and mark the uid in `_painted_this_tick`
## so this tick's `_advance_scenario_anim` skips its `advance_frame` (frame 0 held,
## §8g Gap B) and `_tick_cinematic_walkers` skips its walker (no double-advance,
## §8f). Runs on EVERY dispatched tick, ABOVE the `_ff_skip_first_visual` guard —
## the consume is an event-clock transition, not a render-clock advance, so a
## step-resumed tick must still paint (§8h Gap C). Called from the `_advance_frame`
## accumulator loop before `_advance_tick_visuals`/`_tick_once`.
func _consume_pending_body_anims() -> void:
	if actors.is_empty():
		return
	for uid in actors.keys():
		_paint_pending_body_anim(uid)


## Paint (and clear) ONE actor's pending {11} latch — the per-uid half of
## `_consume_pending_body_anims`, shared with the {44} reveal drain
## (`_paint_revealed_unit_anims`) so both drains clear the latch, paint through
## `_paint_unit_animation`, and set `_painted_this_tick` identically. No latch, or
## no live unit, is a no-op.
func _paint_pending_body_anim(uid: int) -> void:
	var a: ScenarioActor = actors.get(uid)
	if a == null or a.pending_anim < 0:
		return
	var anim_id := a.pending_anim
	a.pending_anim = -1
	var unit = units_by_id.get(uid)
	if unit == null or not is_instance_valid(unit):
		return
	_paint_unit_animation(unit, uid, anim_id)
	_painted_this_tick[uid] = true


## Record that {44} Draw Unit revealed `uid` during this tick's dispatch (called
## from the `set_unit_visible` verb on a hidden->visible flip only).
func note_unit_revealed(uid: int) -> void:
	_revealed_this_tick[uid] = true


## Drain the pending {11} latch for units REVEALED this tick — run at the end of
## the dispatch tick, before the frame is drawn.
##
## WHY THIS EXISTS. {11} Unit Anim latches and paints on the NEXT elapsed tick
## (the PSX `+0x0C` slot; §6b/§8g-k) while {44} Draw Unit flips `visible` at
## dispatch. A script that reveals a unit and dresses it on the SAME tick —
## scenario 29 pc76 `Draw Unit 8` / pc77 `Unit Anim 8` — therefore rendered one
## frame of the unit wearing its PREVIOUS pose. Unit 8 is a tiny thrown EVTCHR
## prop, so that one frame drew its full-size TYPE1 human sprite on unit 7's seat:
## a whole extra character blinking on top of Algus.
##
## The §8i one-tick latch is NOT weakened. It models the visible transition
## BETWEEN two poses, and a unit that was hidden has no previous pose the player
## was looking at — there is nothing for PSX to hold for that frame. Only units
## whose reveal landed this very tick are drained; an already-visible unit still
## waits for `_consume_pending_body_anims` on the next tick (ScenarioUnitAnimLatchTest,
## and arm 2 of ScenarioDrawUnitRevealPoseTest).
func _paint_revealed_unit_anims() -> void:
	for uid in _revealed_this_tick.keys():
		_paint_pending_body_anim(uid)
	_revealed_this_tick.clear()


## The PAINT half of {11} — the Godot analogue of the PSX per-frame consumer
## `FUN_80085C0C` (`+0x0C` → `+0x1DC`). Runs from `_consume_pending_body_anims`
## on the elapsed tick after the latch, NOT at dispatch. Unchanged range-dispatch
## logic (formerly the body of `_apply_unit_animation`); split out so dispatch can
## latch without painting.
##
## Path D (ADR-0053): the event-script writer hands the anim_id to Unit, which
## dispatches on the value range in `_paint_body_variant`:
##   * `0`         → idle (Sub-tables A+B, pose-octant LUT)
##   * `1..0x1f3`  → SEQ-range (Sub-tables E+F, cardinal LUT)
##   * `>= 0x1f4`  → EVTCHR — the cinematic walker drives the BODY shader from
##                 the EVTCHR atlas while the unit-side painter no-ops.
func _paint_unit_animation(unit, uid: int, anim_id: int) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	if unit.animation_set == null or unit.display == null or unit.display.type1_playback == null:
		print("[ScenarioVM] WARN Unit Anim 0x%04X — unit not ready" % uid)
		return false
	var band_base := _cinematic_band_base(anim_id)
	if band_base >= 0:
		# Cinematic-range: write the raw id (the renderer no-ops on it) and spawn
		# the bytecode walker. The per-band local index is `anim_id - band_base`
		# (mid band slot = anim-0x1F4, high band slot = anim-0x258 — see
		# `_cinematic_band_base` + `SCENARIO6_CARRY_POSE_EVTCHR_RENDER.md`).
		#
		# The BAND also picks the EVTCHR page (`_resolve_cinematic_block`): both
		# pages can be resident at once, so `_active_evtchr_block` — "whichever
		# `{58}` fired last" — is only the one-page fallback. Reading it as the
		# page for EVERY unit is what painted all three of scenario 29's cinematic
		# units out of seg 21 (the root-28 wrong-sprite bug).
		unit.play_body(anim_id)
		_play_cinematic_unit_anim(unit, uid, _resolve_cinematic_block(anim_id), anim_id - band_base, anim_id)
	else:
		# Low-range SEQ anim (idle/walk/…). Hardware stores `event_anim_id + 1`
		# at `unit+0x0C`, and the per-frame SEQ player computes the slot as
		# `(unit+0x0C - 1) * 2 + facing_base` = `event_anim_id * 2`, indexing the
		# unit's OWN per-sprite-type SEQ table. The index math is type-INDEPENDENT
		# (verified live, BATTLE.BIN FUN_80085c0c @ 0x80085c0c); type-awareness is
		# already covered Godot-side by loading the correct `*_seq.json` per
		# `sprite_types.json`. So mirror `+0x0C` exactly: write `anim_id + 1`, and
		# Unit's existing `(current_anim_id - 1) * 2` slot math yields the faithful
		# offset for EVERY sprite type (priest walk 0x03 → slot 6, idle 0x02 →
		# slot 4). See HANDOFF_type_aware_animation_routing.md.
		#
		# A low-range anim takes the BODY back from any in-flight cinematic walker:
		# the per-tick painter renders this SEQ (`current_anim_id < 0x1f5`), so a
		# still-live looping walker would fight it by repainting EVTCHR frames every
		# tick. Evict it. (FK's wounded walk 0x26A loops until her 0x021 stop pose
		# lands here; cinematic-range follow-ups self-evict in _play_cinematic_unit_anim.)
		var la := peek_actor(uid)
		if la != null:
			la.walker = null
		unit.play_body(anim_id + 1)
	return true


## Event-script {8C} Unit Anim Rotate (ROM handler 0x80147fac). A combined
## INSTANT set-facing + set-animation for a single unit. The ROM handler writes
## the Direction nibble to the shared rotate queue slot[0] (0x8016d9d8+handle*7)
## but clears the +4 "active" flag (slot[4]=0), so the per-vsync stepper
## FUN_8013f20c never interpolates it — the facing SNAPS. It then calls
## BATTLE_set_unit_anim_value (the same routine {11} Unit Anim uses). The Unknown
## byte toggles a misc move-flag bit (advisory in Godot). Decode: the 0x8C disasm
## at 0x80147fac–0x80148064 + face_unit_decode.md §10.
##
## Direction is an ABSOLUTE 16-direction facing nibble in the project's validated
## wheel (0=E, 4=S, 8=W, 0xC=N — `angle_12bit_to_facing`, canonical), so
## target_12bit = Direction << 8. Unlike {53}'s computed look-at, this is already
## in PSX-facing space (identical to {2D}'s absolute-Facing path) — fed straight
## through, NO Godot↔PSX transpose.
func _op_unit_anim_rotate(inst: Dictionary) -> void:
	var a := EventInstructionSet.args(inst)
	ScenarioApply.unit_anim_rotate(a.raw("Unit"), a.raw("Direction"), a.raw("Animation"), _world)


## Render a cinematic-range anim by spawning a `CinematicWalkState` for the
## unit. The walker honors LoadFrameWait timing across the whole bytecode and
## terminates on PauseAnimation / EndAnimation. Pinned to per-unit by uid so a
## new cinematic Unit Anim for the same unit replaces the old walker (the
## chapel kneel + Ovelia-nod don't actually overlap, but the dispatcher should
## be idempotent for replays via the debug panel).
##
## When `cinematic_frame_override >= 0` we skip the walker and render that
## single static frame — keeps the F3 "Frame override" knob working for
## scrubbing through poses without restarting the scenario.
func _play_cinematic_unit_anim(unit, uid: int, block: int, local_idx: int, anim_id: int) -> void:
	var seg_id := _resolve_cinematic_segment(block)
	if seg_id < 0:
		print("[ScenarioVM] WARN cinematic Unit Anim 0x%04X — Load EVTCHR block %d not set; skipping" %
			[anim_id, block])
		return
	var cinematic_db: Dictionary = unit.animation_set.cinematic_seq if "cinematic_seq" in unit.animation_set else {}
	if cinematic_db.is_empty():
		cinematic_db = _load_cinematic_seq_db()
	var seg_key := str(seg_id)
	if not cinematic_db.has(seg_key):
		print("[ScenarioVM] WARN cinematic Unit Anim 0x%04X — seg %d missing in cinematic_seq.json" %
			[anim_id, seg_id])
		return
	var seg_anims: Dictionary = cinematic_db[seg_key]
	var anim_key := str(local_idx)
	if not seg_anims.has(anim_key):
		print("[ScenarioVM] WARN cinematic Unit Anim 0x%04X — seg %d local idx %d missing" %
			[anim_id, seg_id, local_idx])
		return
	var opcodes: Array = seg_anims[anim_key]

	var slm = unit.sprite_layers if "sprite_layers" in unit else null
	if slm == null:
		push_error("[ScenarioVM] cinematic Unit Anim 0x%04X — unit has no SpriteLayerManager" % anim_id)
		return
	# Pause the unit's normal type1 playback so its per-tick frame_changed signal
	# stops overwriting the cinematic frame.
	unit.force_complete_body()

	_last_cinematic_unit_uid = uid
	_last_cinematic_block = block
	_last_cinematic_local_idx = local_idx
	_last_cinematic_anim_id = anim_id

	var ay := actor(uid)
	var y_offset := ay.atlas_y

	# Frame-override path — debug-panel scrub. Skip the walker, render the
	# overridden frame statically. enter_cinematic_mode + load_cinematic_frame
	# match the pre-walker behavior so the knob keeps working as before.
	if cinematic_frame_override >= 0:
		if not slm.enter_cinematic_mode(seg_id):
			return
		slm.load_cinematic_frame(seg_id, cinematic_frame_override, y_offset)
		ay.walker = null
		print("[ScenarioVM] Cinematic Unit Anim uid=0x%02X anim=0x%04X (block %d, seg %d, local %d, dy %d) → override frame 0x%02X" %
			[uid, anim_id, block, seg_id, local_idx, y_offset, cinematic_frame_override])
		return

	var walker := CinematicWalkState.new()
	walker.unit = unit
	walker.seg_id = seg_id
	walker.atlas_y_offset = y_offset
	walker.opcodes = opcodes
	ay.walker = walker
	# Initial advance — renders the first LoadFrameWait immediately so the unit
	# doesn't stall on its prior pose for one tick.
	walker.advance()
	print("[ScenarioVM] Cinematic Unit Anim uid=0x%02X anim=0x%04X (block %d, seg %d, local %d, dy %d) → walker armed (%d opcodes)" %
		[uid, anim_id, block, seg_id, local_idx, y_offset, opcodes.size()])


## Drain every in-flight `scenario_rotate` stepper to its target by ticking
## it up to a safety cap. Used by the chapel-trace burn-through so each
## opcode's trace row already reflects the rotation's terminal state
## (matching what PSX renders after the cinematic Wait that normally
## follows a Rotate Unit). 256 ticks is well above the worst-case
## cascade in scenario 1 (Agrias = 8 steps × Speed=1, ~16 ticks).
func _drain_unit_rotations_to_target() -> void:
	if units_by_id.is_empty():
		return
	for uid in units_by_id.keys():
		var unit = units_by_id[uid]
		if unit == null or not is_instance_valid(unit):
			continue
		if not unit.has_method("_tick_rotate"):
			continue
		var safety := 256
		while not unit._rotate_state.is_empty() and safety > 0:
			unit._tick_rotate()
			safety -= 1


## Per-VM-tick fan-out: advance any in-flight `scenario_rotate` stepper on
## every spawned unit. Mirrors the FFT per-vsync consumer `FUN_8013f20c`
## (real RAM 0x8013f20c) that loops all 21 unit handles and steps each
## active rotation one 16-direction notch. Idempotent for units with no
## active rotation. See `Unit._tick_rotate` for the per-step math + the
## `HANDOFF_rotation_interpolation.md` for the static decode this mirrors.
func _tick_unit_rotations() -> void:
	if units_by_id.is_empty():
		return
	for uid in units_by_id.keys():
		var unit = units_by_id[uid]
		if unit == null or not is_instance_valid(unit):
			continue
		if unit.has_method("_tick_rotate"):
			unit._tick_rotate()


## Per-VM-tick fan-out: advance every live cinematic walker. Called from
## `_tick_once` between the not-running guard and the wait gate so walkers
## keep animating during camera-lerp wait holds. Walkers that mark `done`
## (PauseAnimation, EndAnimation, or end-of-bytecode) are removed.
func _tick_cinematic_walkers() -> void:
	for uid in actors.keys():
		var a: ScenarioActor = actors[uid]
		var walker: CinematicWalkState = a.walker
		if walker == null:
			continue
		# A cinematic walker SPAWNED by this tick's `_consume_pending_body_anims`
		# already painted its first LoadFrameWait frame (the initial `advance()` in
		# `_play_cinematic_unit_anim`). Skip it for this one tick so the same tick's
		# dispatch phase doesn't advance it twice (§8f walker-clock alignment); the
		# NEXT tick (uid no longer marked) ticks it normally.
		if uid in _painted_this_tick:
			continue
		walker.advance()
		if walker.done:
			a.walker = null


## Set the atlas Y-offset (signed px) for a specific uid and re-render any
## live walker for that unit so the change is visible immediately. Use from
## the F3 debug panel to tune per-character row mapping until the scene
## matches PCSX. `y_px` is treated as i16 (`-32768..32767`); pass 0 to
## disable the offset.
func set_cinematic_y_offset(uid: int, y_px: int) -> void:
	var a := actor(uid)
	a.atlas_y = y_px
	if a.walker != null:
		var walker: CinematicWalkState = a.walker
		walker.atlas_y_offset = y_px
		# Re-render the walker's current frame so the offset takes effect
		# without waiting for the next LoadFrameWait pop. Reach back to the
		# last opcode we executed (op_index - 1) and re-render its fb.
		var last_idx := walker.op_index - 1
		if last_idx >= 0 and last_idx < walker.opcodes.size():
			var op = walker.opcodes[last_idx]
			if str(op.get("op_code_name", "")) == "LoadFrameWait":
				walker._render(int(op.get("op_code_param_0", 0)))


## Re-apply the most recent cinematic Unit Anim with the current
## `cinematic_segment_override` / `cinematic_frame_override` knobs. Used by
## the debug panel to A/B segments and frames without restarting the scenario.
## Returns false if no cinematic Unit Anim has fired yet this run.
func reapply_last_cinematic() -> bool:
	if _last_cinematic_anim_id < 0:
		return false
	if not units_by_id.has(_last_cinematic_unit_uid):
		return false
	var unit = units_by_id[_last_cinematic_unit_uid]
	_play_cinematic_unit_anim(
		unit, _last_cinematic_unit_uid,
		_last_cinematic_block, _last_cinematic_local_idx, _last_cinematic_anim_id,
	)
	return true


## Bind the EVTCHR cinematic-scrub overrides to their `scenario.*` Tune slugs
## (ADR-0068). The VM OWNS these, so a scrub coalesces here (and re-fires the last
## cinematic to show the new pose) in any scene — the cinematic debug panel is just
## a view (decision 12), and the override now survives a scenario reload for free
## (the freshly-booted VM's bind re-reads it). `bind` because the value is applied
## imperatively (it re-drives the resolver), not re-read at a use-site. reapply is a
## safe no-op until a cinematic Unit Anim has actually fired. Not @tool-guarded:
## ScenarioVM never runs in the editor (no @tool). bind is SPLIT from on_update: the
## static-var homes + hints are bound in register_tunables() (below); each VM instance
## subscribes its on_update push here.
func _bind_cinematic_tunables() -> void:
	Tune.on_update(self, CINEMATIC_SEGMENT_OVERRIDE_SLUG, func(v: int) -> void:
		cinematic_segment_override = v
		reapply_last_cinematic())
	Tune.on_update(self, CINEMATIC_FRAME_OVERRIDE_SLUG, func(v: int) -> void:
		cinematic_frame_override = v
		reapply_last_cinematic())


## Register the cinematic-override slugs to their static-var homes + hints ONCE at class load
## (R2). Split from _bind_cinematic_tunables (the per-instance on_update push) so
## it is this owner's named registration entry point — _static_init calls it at class load, and
## the ADR-0173 guards call it to read back which slugs this owner binds.
static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	register_tunables()


static func register_tunables() -> void:
	Tune.bind(CINEMATIC_SEGMENT_OVERRIDE_SLUG, CINEMATIC_SEGMENT_OVERRIDE_DEFAULT,
		CINEMATIC_SEGMENT_OVERRIDE_HINT)
	Tune.bind(CINEMATIC_FRAME_OVERRIDE_SLUG, CINEMATIC_FRAME_OVERRIDE_DEFAULT,
		CINEMATIC_FRAME_OVERRIDE_HINT)


# --- Chapel-cinematic per-opcode trace --------------------------------------

const _CARDINAL_TO_12BIT := {0: 0xC00, 1: 0x000, 2: 0x400, 3: 0x800}
const _CARDINAL_NAMES := ["NORTH", "EAST", "SOUTH", "WEST"]
# Under `user://` so it is writable on any host. It used to default to an
# absolute path into a checkout that does not exist here, so the trace could
# never be written even with `DebugConfig.chapel_trace_enabled` set.
# NOT an env var: ADR-0051 keeps configuration out of src/.
const _DEFAULT_CHAPEL_TRACE_PATH := "user://chapel_opcode_trace/godot_run.jsonl"


func _open_chapel_trace() -> void:
	"""Open the JSONL writer if `DebugConfig.chapel_trace_enabled` is set.
	Truncates any prior run; closed on Node exit (`_notification`)."""
	if not DebugConfig.chapel_trace_enabled:
		return
	if _chapel_trace_file != null:
		_chapel_trace_file.close()
	var path: String = DebugConfig.chapel_trace_path
	if path.is_empty():
		path = _DEFAULT_CHAPEL_TRACE_PATH
	_chapel_trace_file = FileAccess.open(path, FileAccess.WRITE)
	if _chapel_trace_file == null:
		push_warning("[ScenarioVM] chapel-trace: cannot open '%s' for write (err=%s)" %
			[path, FileAccess.get_open_error()])
		return
	_chapel_trace_rows = 0
	print("[ScenarioVM] chapel-trace ON → %s" % path)


func _close_chapel_trace() -> void:
	if _chapel_trace_file != null:
		_chapel_trace_file.close()
		_chapel_trace_file = null
		print("[ScenarioVM] chapel-trace flushed (%d rows)" % _chapel_trace_rows)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		_close_chapel_trace()


func _emit_chapel_trace_row(pc: int, inst: Dictionary, handled: bool) -> void:
	if _chapel_trace_file == null:
		return
	var row := {
		"pc": pc,
		"offset": int(inst.get("offset", 0)),
		"opcode": str(inst.get("name", "?")),
		"handled": handled,
		"params": inst.get("params", []),
		"wait_ticks_after": (_current_ctx.wait_ticks if _current_ctx != null else 0),
		"ctx_label": (_current_ctx.label if _current_ctx != null else "?"),
		"units": _snapshot_all_units(),
	}
	_chapel_trace_file.store_line(JSON.stringify(row))
	_chapel_trace_rows += 1


func _snapshot_all_units() -> Array:
	var out: Array = []
	var keys := units_by_id.keys()
	keys.sort()
	for uid in keys:
		var unit = units_by_id[uid]
		if unit == null or not is_instance_valid(unit):
			continue
		out.append(_snapshot_unit(int(uid), unit))
	return out


func _snapshot_unit(uid: int, unit) -> Dictionary:
	var snap := {
		"uid": uid,
		"sprite_set": int(unit.body_sprite_id) if "body_sprite_id" in unit else -1,
		"visible": bool(unit.visible),
	}

	# World position + derived tile for the unit-tile alignment trace. Units sit
	# at tile centre +0.5 (see `cinematic_place`), so the occupied tile is
	# `floor(world)`. Compared opcode-by-opcode against the PSX `(base+offset)/28`
	# tile (probe_all_units_trace.jsonl) to find the first divergence.
	if "global_position" in unit:
		var gp: Vector3 = unit.global_position
		snap["world"] = [
			snappedf(gp.x, 0.001), snappedf(gp.y, 0.001), snappedf(gp.z, 0.001)]
		snap["tile"] = [int(floor(gp.x)), int(floor(gp.z))]
	else:
		snap["world"] = []
		snap["tile"] = []

	# Facing: cardinal enum (0..3) + precise 12-bit angle. The cardinal is
	# what the sprite renders; the 12-bit value is what scenario_rotate stored
	# (target angles like 0x200 between S and E survive intact here). If the
	# unit has never been rotated by the scenario, `facing_angle` is -1 and we
	# fall back to the cardinal-derived value so older trace rows still parse.
	#
	# `pose_idx` is the PSX truncate `(angle_12bit >> 10) & 3` — the value the
	# PSX sprite renderer (FUN_8006bbfc) feeds to FUN_8017fddc, captured in
	# the PSX probe too. Comparing against `cardinal_idx` (Godot's center-snap
	# label index) tells us when Godot's sprite would render a different pose
	# than PSX for the same byte. See HANDOFF_sprite_cardinal_mapping.md.
	var cardinal := -1
	if unit.anim_state != null:
		cardinal = int(unit.anim_state.current_facing)
	var precise_angle := -1
	if "facing_angle" in unit:
		precise_angle = int(unit.facing_angle)
	var angle_12bit := precise_angle if precise_angle >= 0 else int(_CARDINAL_TO_12BIT.get(cardinal, -1))
	var pose_idx := -1
	if angle_12bit >= 0:
		# Render class (ADR-0057): the raw cardinal bucket is a derived view of
		# the angle — route through the one converter, never re-derive inline.
		pose_idx = AnimationStateController.angle_12bit_to_cardinal_bucket(angle_12bit)
	snap["facing"] = {
		"cardinal_idx": cardinal,
		"cardinal_name": (_CARDINAL_NAMES[cardinal] if cardinal >= 0 and cardinal < 4 else "?"),
		"angle_12bit": angle_12bit,
		"angle_source": "scenario_rotate" if precise_angle >= 0 else "cardinal_derived",
		"pose_idx": pose_idx,
	}

	# Camera-relative sprite variant the body layer is currently using —
	# the {use_back, revert} pair `_paint_body_variant` picked. This is
	# the analog of PSX's per-cardinal sprite-table flags.
	if unit.anim_state != null and unit.has_method("get_camera_quadrant"):
		var quad := int(unit.get_camera_quadrant())
		var variant: Dictionary = AnimationStateController.get_camera_variant(
			unit.anim_state.current_facing, quad)
		snap["sprite_pose"] = {
			"camera_quad": quad,
			"use_back": bool(variant.get("use_back", false)),
			"revert": bool(variant.get("revert", false)),
		}
	else:
		snap["sprite_pose"] = {}

	# Normal type1 playback (idle/walk/etc.).
	var t1 = unit.display.type1_playback if ("display" in unit and unit.display) else null
	if t1 != null:
		snap["type1"] = {
			"anim_id": str(t1.anim_id),
			"anim_frame": int(t1.anim_frame),
			"last_display_frame": int(t1.last_display_frame),
			"is_paused": bool(t1.is_paused),
		}
	else:
		snap["type1"] = {}

	# Cinematic walker (EVTCHR-driven). When the walker last popped a
	# LoadFrameWait we surface its frame byte — that's the value PCSX writes
	# to the BODY shader during cinematic blocks.
	var snap_actor := peek_actor(uid)
	if snap_actor != null and snap_actor.walker != null:
		var walker: CinematicWalkState = snap_actor.walker
		var last_fb := -1
		var prev := walker.op_index - 1
		if prev >= 0 and prev < walker.opcodes.size():
			var prev_op = walker.opcodes[prev]
			if str(prev_op.get("op_code_name", "")) == "LoadFrameWait":
				last_fb = int(prev_op.get("op_code_param_0", 0))
		snap["cinematic"] = {
			"active": true,
			"seg_id": walker.seg_id,
			"atlas_y_offset": walker.atlas_y_offset,
			"op_index": walker.op_index,
			"ticks_left": walker.ticks_left,
			"done": walker.done,
			"in_cinematic_mode": walker._in_cinematic_mode,
			"last_fb": last_fb,
		}
	else:
		snap["cinematic"] = {"active": false}

	# In-flight Sprite Move ({3B}/{6E}) — surfaced so the chapel trace can diff
	# unit slides against PSX. Includes the live world position (the value the
	# slide is interpolating) and lerp progress.
	if snap_actor != null and snap_actor.motion is ScenarioMotion:
		var mv: ScenarioMotion = snap_actor.motion
		snap["sprite_move"] = {
			"active": true,
			"easing": mv.easing,
			"progress": mv.frac(),
			"pos": [unit.global_position.x, unit.global_position.y, unit.global_position.z],
			"target": [mv.target.x, mv.target.y, mv.target.z],
		}
	else:
		snap["sprite_move"] = {"active": false}

	return snap


## Cinematic Unit Anim bytecode walker.
##
## Owns one anim's playback state on one unit: walks the `cinematic_seq.json`
## opcode list, honors `LoadFrameWait(frame, ticks)` timing, and terminates on
## `PauseAnimation` / `EndAnimation`. Routes frames < 0xD2 through the unit's
## TYPE1 SHP path and frames ≥ 0xD2 through the EVTCHR atlas — see
## `cinematic_frame_offset_decode.md` for why 0xD2 is the boundary.
##
## Per-tick advance: `ticks_left` counts down each call; when it hits 0 the
## walker pops the next opcode. Initial `advance()` (called from
## `_play_cinematic_unit_anim`) renders the first frame immediately.
class CinematicWalkState extends RefCounted:
	const SpriteLayerManagerClass = ExMateriaSpriteRig.SpriteLayerManager
	var unit  # Unit (untyped so tests can pass a mock)
	var seg_id: int = 0
	var atlas_y_offset: int = 0
	var opcodes: Array = []
	var op_index: int = 0
	var ticks_left: int = 0
	var done: bool = false
	# Last EVTCHR frame byte handed to the renderer by `_render` (-1 until the
	# first frame draws). Pure observability — lets a comparator read the exact
	# rendered frame identity per unit without reconstructing it from `opcodes`.
	var last_fb: int = -1
	# Tracks whether the last `_render` left the BODY shader bound to the
	# EVTCHR atlas. Anim 0x25C (`E7 08 08 02 FF FF`) flips mid-bytecode from
	# `>= 0xD2` (EVTCHR) to `< 0xD2` (TYPE1.SHP); the SHP `_render` path must
	# call `exit_cinematic_mode` before writing its rects, otherwise the SHP
	# coordinates sample EVTCHR pixels and the unit looks like a different
	# character. Mirrors the engine's per-byte FUN_80083f18 0xD2 split.
	var _in_cinematic_mode: bool = false

	func advance() -> void:
		if done:
			return
		if ticks_left > 0:
			ticks_left -= 1
		# Budget guards against a degenerate IncrementLoop with no intervening
		# LoadFrameWait (which would spin forever): a real loop always pops a
		# LoadFrameWait — setting ticks_left > 0 — and breaks long before this.
		var budget := opcodes.size() + 1
		while ticks_left == 0 and op_index < opcodes.size() and budget > 0:
			budget -= 1
			var op = opcodes[op_index]
			op_index += 1
			var op_name := str(op.get("op_code_name", ""))
			if op_name == "LoadFrameWait":
				var fb := int(op.get("op_code_param_0", 0))
				var wait := int(op.get("op_code_param_1", 1))
				_render(fb)
				ticks_left = max(wait, 1)
			elif op_name == "IncrementLoop":
				# 0xFFD5: loop the whole sequence back to frame 0. EVTCHR bytecode
				# has no LoopStart marker, so the loop spans the entire anim —
				# matching AnimationPlayback's wrap-to-frame-0 for type1 SEQs. The
				# trailing PauseAnimation is an unreachable fallback; the walker now
				# PERSISTS (e.g. FK's wounded walk loops the full Sprite Move) until
				# a follow-up Unit Anim evicts it (low-range via _apply_unit_animation;
				# cinematic-range via _play_cinematic_unit_anim replacing the entry).
				op_index = 0
			elif op_name == "PauseAnimation" or op_name == "EndAnimation":
				done = true
				return
			# Other undecoded 0xFFxx opcodes: skip and continue walking.
		# A non-looping anim that drains all opcodes is done. (A looping anim never
		# reaches here with op_index past the end — IncrementLoop resets it first.)
		if op_index >= opcodes.size() and ticks_left == 0:
			done = true

	func _render(fb: int) -> void:
		last_fb = fb
		var slm = unit.sprite_layers
		if slm == null:
			return
		if fb >= 0xD2:
			slm.enter_cinematic_mode(seg_id)
			# Whole-sprite H-flip must be a pure function of (facing, camera) — the
			# same derivation the combat/react painter uses. Without this the
			# cinematic path inherited a STALE `apply_reversion` from each unit's
			# last pre-cinematic paint, so two units at the SAME facing+camera could
			# mirror differently (scn6: Delita kept true, Ovelia kept false → Ovelia
			# hung off the wrong side of the chocobo). Derived here so both agree.
			# Resolves SCENARIO6_CARRY_POSE_EVTCHR_RENDER.md open item #3 (facing/
			# octant of the carry poses); the chapel high-band gets the same
			# deterministic flip (ADR-0039).
			_apply_cinematic_reversion(slm)
			slm.load_cinematic_frame(seg_id, fb, atlas_y_offset)
			_in_cinematic_mode = true
		else:
			if _in_cinematic_mode:
				slm.exit_cinematic_mode()
				_in_cinematic_mode = false
			slm.load_frame_by_id(SpriteLayer.TYPE1, fb)

	# Deterministic whole-sprite reversion for a cinematic EVTCHR frame: mirror
	# the combat/react painter's rule (AnimationStateController.get_camera_variant
	# → `revert`), a pure function of the unit's facing + camera quadrant. Applied
	# on every EVTCHR render so a facing change mid-cinematic tracks. Guarded for
	# the test mocks (which may lack facing_direction / get_camera_quadrant).
	func _apply_cinematic_reversion(slm) -> void:
		if unit == null or not ("facing_direction" in unit):
			return
		var quad := 0
		if unit.has_method("get_camera_quadrant"):
			quad = unit.get_camera_quadrant()
		var variant := AnimationStateController.get_camera_variant(unit.facing_direction, quad)
		slm.set_global_reversion(bool(variant["revert"]))


const _CINEMATIC_SEQ_PATH := "res://assets/sprites/animations/cinematic_seq.json"
var _cinematic_seq_db_cache: Dictionary = {}
var _cinematic_seq_db_loaded: bool = false

func _load_cinematic_seq_db() -> Dictionary:
	if _cinematic_seq_db_loaded:
		return _cinematic_seq_db_cache
	_cinematic_seq_db_loaded = true
	if not FileAccess.file_exists(_CINEMATIC_SEQ_PATH):
		# LOUD, not silent: without this file EVERY cinematic anim aborts and no
		# EVTCHR cinematics render. See AssetManifest (boot-time guard).
		push_error("[ScenarioVM] cinematic_seq.json MISSING — no EVTCHR cinematics will play. Run: uv run python tools/parse_cinematic_seq.py (or bash tools/bootstrap_assets.sh)")
		return _cinematic_seq_db_cache
	var f := FileAccess.open(_CINEMATIC_SEQ_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) == TYPE_DICTIONARY:
		_cinematic_seq_db_cache = data
	return _cinematic_seq_db_cache


func _op_rotate_unit(inst: Dictionary) -> void:
	# The Facing-mode dispatch (camera-relative / relative / face-target / absolute
	# per hacktics disasm 0x80148284) + the current-facing baseline read live in
	# ScenarioApply.rotate_unit + the rotate_baseline_12bit verb; the unit-side
	# scenario_rotate stepper stays on Unit (ADR-0055).
	ScenarioApply.rotate_unit(ScenarioDecode.rotate_unit(EventInstructionSet.args(inst)), _world)


## Unit `uid`'s current 12-bit facing baseline for a {2D} relative rotation. Its live
## `facing_angle` if it's been rotated before (>= 0), else a cardinal-derived seed
## from its animation state (so the first relative rotation has a baseline), else 0.
func _rotate_baseline_12bit(uid: int) -> int:
	var unit = units_by_id[uid]
	if "facing_angle" in unit and int(unit.facing_angle) >= 0:
		return PsxNum.wrap12(int(unit.facing_angle))
	if unit.anim_state != null:
		return int(_CARDINAL_TO_12BIT.get(int(unit.anim_state.current_facing), 0))
	return 0


## Event-script {53} Face Unit (ROM handler evt0x53_face_unit @ 0x80148084).
## Makes the affected unit rotate to LOOK AT the faced unit's tile. Reuses the
## SAME `scenario_rotate` → `_tick_rotate` stepper and pending-rotate queue
## (0x8016d9d8 + handle*7) as {2D} Rotate Unit — the only difference is that the
## target facing is COMPUTED as the compass look-at instead of decoded from a
## Facing byte. Decode + live validation (PCSX-Redux, scenario 1/2):
## research/working_documents/scenario_1_captures/face_unit_decode.md.
##
## Look-at math (decode-doc §4.3/§8): the ROM computes, in PSX tile coords,
##   Δx = affected.x − faced.x,  Δy = affected.y − faced.y
##   atan12 = ratan2_12bit(Δx, Δy)  ; 12-bit CW wheel, 0 at +Δy, 0x400 at +Δx
##   target_12bit = (0x1400 − atan12) & 0xF00
## Live-validated: affected 0x0c vs faced 0x84 (Δx=0, Δy=+) → facing 0x400 (East).
## Multi 1/2 (team-set targeting) is static-only in the ROM (no scenario-1/2 scene
## uses it) — skipped with a warning (decode-doc §2.1/§10).
func _op_face_unit(inst: Dictionary) -> void:
	_do_face_unit(inst, false)


## Event-script {2C} Face Unit 2 (ROM: same evt0x53_face_unit @ 0x80148084 as
## {53}, dispatched with a1=0). Identical to {53} Face Unit EXCEPT the faced
## unit ALSO rotates 180° back to look at the affected unit — the two units end
## up facing each other (mutual). Decode: face_unit_decode.md §11 (scenario
## dispatch @ 0x80144dec, `_clear a1`; handler a1==0 branch @ 0x80148180 writes
## the faced unit's rotate command with facing F_A = F_B+180°, same
## Direction/Speed/Delay operands as the affected unit).
func _op_face_unit_2(inst: Dictionary) -> void:
	_do_face_unit(inst, true)


## Event-script {69} Face Tile — the FaceUnit-family sibling that rotates the
## affected unit to LOOK AT a map tile (operand X,Y) instead of a faced unit.
## Reuses the {53} Face Unit look-at (`_face_tile_look_at_12bit`) feeding the same
## {2D} `scenario_rotate` stepper / pending-rotate queue. Multi=1 (team set) is
## static-only in the ROM → warn-skipped in ScenarioApply, as with {53}.
## Decode + validation: FACE_TILE_UNIT_SHADOW_WAIT_ADD_UNIT.md §2.
func _op_face_tile(inst: Dictionary) -> void:
	var a := EventInstructionSet.args(inst)
	ScenarioApply.face_tile(a.raw("Units"), a.raw("Multi"), a.raw("X"), a.raw("Y"),
		a.raw("Direction"), a.raw("Speed"), a.raw("Delay"), _world)


## Event-script {4E} Unit Shadow — enable/disable a unit's ground drop-shadow.
## ROM sets/clears the unit-struct show-flag at unit+0x298 (shadow renderer
## @ 0x8007D5D0 is gated on it; anim opcodes 0xE0 HideShadow / 0xE1 ShowShadow
## toggle the same flag). Operand `Disable`: 0=enable, 1=disable. Wired to the
## existing per-unit UnitShadow (Unit.gd `$ShadowMesh`, UnitShadow.set_enabled).
## Decode + validation: FACE_TILE_UNIT_SHADOW_WAIT_ADD_UNIT.md §3.
func _op_unit_shadow(inst: Dictionary) -> void:
	var a := EventInstructionSet.args(inst)
	ScenarioApply.unit_shadow(a.raw("Unit"), a.raw("Disable"), _world)


## Shared core for {53} Face Unit (mutual=false) and {2C} Face Unit 2
## (mutual=true). See _op_face_unit / _op_face_unit_2.
func _do_face_unit(inst: Dictionary, mutual: bool) -> void:
	var a := EventInstructionSet.args(inst)
	# The look-at computation (reads both unit positions + map depth) stays VM-side
	# via the face_look_at_12bit verb; the rotate stepper stays on Unit (ADR-0055).
	ScenarioApply.face_unit(a.raw("Units"), a.raw("Faced Unit"), a.raw("Multi"),
		a.raw("Direction"), a.raw("Speed"), a.raw("Delay"),
		mutual, _world, "Face Unit 2" if mutual else "Face Unit")


## PSX 12-bit look-at angle from `affected` toward `faced`, reproducing the ROM's
## `(0x1400 − ratan2_12bit(Δx, Δy)) & 0xF00`. Δ is taken in PSX tile space — X
## passes through (Godot grid_x == PSX tile x); the depth row is recovered by
## undoing the ADR-0052 chirality flip (psx_y = size_z-1 - godot_z, the
## PsxNum.flip_depth_row formula), which negates the Z delta. Producing the angle
## in PSX space keeps it in the SAME
## 12-bit facing space {2D} Rotate Unit already feeds the renderer correctly.
func _face_unit_look_at_12bit(affected: Node3D, faced: Node3D) -> int:
	# The ROM's FUN_80133088 returns PSX-internal unit coords whose axes are the
	# TRANSPOSE of the chunk's Warp X(column)/Y(row) param naming: PSX-x is the
	# depth/row axis, PSX-y is the lateral/column axis. (Live capture §5: two
	# onlookers on the SAME chunk row read back with identical PSX-x and differing
	# PSX-y.) Map Godot world deltas into that frame:
	#   PSX-y (atan "+Δy→0" axis)      = lateral  =  +ΔGodot_x
	#   PSX-x (atan "+Δx→0x400" axis)  = depth    =  −ΔGodot_z  (ADR-0052: PSX +depth → Godot −Z)
	# Live-validated: affected 0x0c vs faced 0x84 sit on the same row (ΔGodot_z=0)
	# with the knight to lateral −X, giving PSX (Δx=0, Δy>0) → 0x400 (East) —
	# matching PCSX's written nibble 0x04 AND the sibling {2D} ops that also turn
	# the other onlookers East to face her. (Closes face_unit_decode.md §10.)
	var psx_dx := int(floor(faced.global_position.z)) - int(floor(affected.global_position.z))
	var psx_dy := int(floor(affected.global_position.x)) - int(floor(faced.global_position.x))
	return face_unit_look_at_12bit_psx(psx_dx, psx_dy)


## PSX 12-bit look-at from `affected` toward a map TILE (tile_x, tile_y) — the
## {69} Face Tile analogue of `_face_unit_look_at_12bit`. The ROM handler
## FUN_8014978c takes the delta in the PSX-INTERNAL frame: it feeds operand Y
## straight into the target's world coord (X*28+14 per axis) and subtracts the
## actor's FUN_80133088 coords, where PSX-x = depth/row, PSX-y = lateral/column
## (face_unit_decode.md §5). Operand X = column (lateral), Y = row (depth) — raw
## PSX rows, NOT flipped (Y=13 hits size_z−1=13, the far row). To take that delta
## from a Godot-placed actor we undo the ADR-0052 depth flip on the actor's row
## (psx_row = size_z−1 − godot_z) and keep tile_y as the PSX row:
##   Δ_psx_x (depth)   = (size_z−1 − floor(affected.z)) − tile_y
##   Δ_psx_y (lateral) = floor(affected.x) − tile_x
## This reduces EXACTLY to `_face_unit_look_at_12bit` when tile_y is itself a
## flipped unit row ((size_z−1 − floor(faced.z))), so both share the live-validated
## (0x1400 − ratan2_12bit) & 0xF00 fold. Dynamically corroborated in scenario 6:
## flipped tile (0,13) → Godot (0.5,0.5), exactly the chocobo-139 rest tile the
## onlookers 2/23/52 turn to watch (FACE_TILE_UNIT_SHADOW_WAIT_ADD_UNIT.md §2).
func _face_tile_look_at_12bit(affected: Node3D, tile_x: int, tile_y: int) -> int:
	var psx_dx := (map_size_z - 1 - int(floor(affected.global_position.z))) - tile_y
	var psx_dy := int(floor(affected.global_position.x)) - tile_x
	return face_unit_look_at_12bit_psx(psx_dx, psx_dy)


## Pure ROM-faithful look-at: 12-bit facing from a PSX-space (Δx, Δy) where
## Δ = affected − faced. Reproduces evt0x53_face_unit's
## `(0x1400 − ratan2_12bit(Δx,Δy)) & 0xF00`, with the 12-bit clockwise arctangent
## (SUB_8001d8e8) 0 along +Δy and 0x400 along +Δx. Validated against the §8
## controlled-call octant table — see ScenarioFaceUnitTest.
static func face_unit_look_at_12bit_psx(dx: int, dy: int) -> int:
	return PsxNum.look_at_12bit(dx, dy)


func _op_reveal(inst: Dictionary) -> void:
	ScenarioApply.reveal(EventInstructionSet.args(inst).raw("Time", 1), _world)


func _apply_fade_alpha(a: float) -> void:
	if fade_rect == null:
		return
	var c := fade_rect.color
	c.a = clamp(a, 0.0, 1.0)
	fade_rect.color = c


## Sign-extend a PSX byte (R/G/B params are signed bytes in the applier).
static func _signed_byte(b: int) -> int:
	return PsxNum.s8(b)


## {1A} Map Darkness — the prayer-scene "oxide" tint. Mirrors the PSX applier
## FUN_80090840 (map_darkness_oxide_decode.md): Blend selects 1 of 11 modes;
## scenario 1 uses mode 4 ("byte-register add"): target = rest_baseline +
## signed(R,G,B). The current color integrates toward target over Time*8 frames
## (Time==0 snaps); the rendered subtraction is the delta from rest, so the rest
## tint itself stays invisible. Modes other than 4 don't appear in scenario 1 —
## log + treat them as the byte-add for now (so they animate rather than halt).
func _op_map_darkness(inst: Dictionary) -> void:
	ScenarioApply.map_darkness(
		ScenarioDecode.map_darkness(EventInstructionSet.args(inst), _OXIDE_BASELINE), _world)


## Set the oxide ramp state from a decoded Map Darkness intent: latch the target,
## snapshot the start, and either snap (Time≤0) or arm the fade over `duration_ticks`.
## The ramp itself is ticked by `_tick_once` outside the halt gate (the oxide fields
## are VM state); this is the state-mutation the `set_map_darkness` verb wraps.
func _set_oxide_from_intent(intent: ScenarioDecode.MapDarknessIntent) -> void:
	_oxide_target_byte = intent.target
	_oxide_start_byte = _oxide_current_byte
	if intent.snap:
		# PSX `if Time==0: snap current = target` (no fade).
		_oxide_current_byte = intent.target
		_oxide_duration_ticks = 0
		_oxide_remaining_ticks = 0
	else:
		_oxide_duration_ticks = intent.duration_ticks
		_oxide_remaining_ticks = intent.duration_ticks


## One independent thread of scenario-script execution. Mirrors a single slot
## in PSX's 16-slot cooperative scheduler (FUN_8014ca80 / DAT_80174038); see
## BLOCK_EXECUTION_INVESTIGATION.md for the static + dynamic decode.
## `_contexts[0]` is always the main scenario thread; parallel `Block Start`
## opcodes append children. Per-context `wait_ticks` is the cooperative yield
## (PSX equivalent: the busy-wait loop inside a blocking opcode handler that
## repeatedly calls FUN_8014ca80 until its wait condition clears).
class ScriptContext extends RefCounted:
	var pc: int = 0
	var wait_ticks: int = 0
	# Predicate-hold barrier (PSX yield+poll loop — e.g. {64} Wait Rotate Unit's
	# FUN_801498fc @ 0x801498fc spinning on the +4 "rotation active" flag). While
	# `wait_until` is valid the context holds, re-polling the predicate each tick,
	# until it returns true or `wait_until_deadline_tick` passes (watchdog).
	# Coexists with `wait_ticks` — a handler arms one or the other.
	var wait_until: Callable = Callable()
	var wait_until_deadline_tick: int = 0
	# Optional PROGRESS probe for the watchdog. When set, `_hold_wait_until` polls
	# it each tick; whenever its returned int changes, the watchdog deadline is
	# pushed forward by `wait_until_watchdog_ticks`. This distinguishes a barrier
	# that is legitimately-long-but-advancing (e.g. a multi-page narration whose
	# typewriter keeps revealing glyphs for 30-40 s) from one that is genuinely
	# STUCK (predicate true but nothing moving). A stalled probe still trips the
	# deadline, so the deadlock backstop is intact. Empty = fixed-deadline (old
	# behaviour). See display_message_overlay_decode.md Part Z §Z.5.
	var wait_until_progress: Callable = Callable()
	var wait_until_last_progress: int = 0
	var wait_until_watchdog_ticks: int = 0
	var alive: bool = true
	var label: String = ""
