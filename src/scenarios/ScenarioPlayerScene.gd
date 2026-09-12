extends Node3D

## Scenario tracer-bullet scene (handoff `/tmp/handoff_tracer_bullet_scenario_1.md`).
##
## Loads MAP062 (Chapel of Orbonne), spawns every non-empty ENTD record 256
## slot with its ROM-specified sprite_set, then hands the unit table to
## ScenarioVM and starts execution. Frame-0 visibility is CHUNK-DERIVED
## (`_chunk_reveals_first`): a slot starts hidden iff its first visibility
## opcode reveals/holds it ({44} Draw / {45} Add Draw=1); else visible — the
## PSX `+0xa` show flag, NOT the ENTD `always_present` formation gate (see
## research/working_documents/SCENARIO6_UNIT_REVEAL_VISIBILITY.md). Runtime
## reveal mirrors BATTLE.BIN `FUN_BATTLE.BIN__8008d05c` (the "Post add/transform
## Graphic Update by Battle ID" handler the wiki cites at 0x8008d05c). The legacy
## chunk-reference fallback is a defensive net for scenarios that reference uids
## NOT in ENTD (genuine Load-EVTCHR-only characters) — scenario 1 doesn't trigger it.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const SpritePaletteResolver = ExMateriaSpriteRig.SpritePaletteResolver

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const FacingDirection = ExMateriaSchema.Facing.Direction

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const Lattice = ExMateriaBattlefield.Lattice
## And the same for `addons/exmateria_platform`, which shed `DisplayPort` — the
## name of a hardware standard — under ADR-0212 dec. 1.
const PsxNum = ExMateriaPlatform.PsxNum

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const JobDatabase = ExMateriaAlmanac.JobDatabase
const ScenarioDatabase = ExMateriaAlmanac.ScenarioDatabase


const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const ResidueManifest = ExMateriaCatalogue.ResidueManifest
const UNIT_SCENE_PATH := "res://assets/scenes/Unit.tscn"
const ENTD_JSON_PATH := "res://assets/scenarios/entd.json"
# --- Scenario selection ----------------------------------------------------
# The scene boots into ONE scenario, identified by its canonical id (==
# TEST.EVT event index == ScenarioDatabase key). Everything else — map, ENTD
# record, music pair, and the event-script chunk — is resolved from that id at
# `_ready` (see `_resolve_scenario`). The F3 → Scenario VM → "Scenario" picker
# writes `ScenarioDebugSession.selected_scenario_id` and reloads the scene to
# switch; on a fresh boot (no pick) we fall back to DEFAULT_SCENARIO_ID.
#
# DEFAULT = 2 "Orbonne Prayer" (the reverse-engineered chapel cinematic, event
# index 2). NOTE this is the scenario the scene has always played — the legacy
# flat file `scenario_1_chunk.json` is *misnamed*: it is event 2's chunk, byte-
# identical to `chunks/scenario_002_chunk.json`. Scenario 1 is the *Setup*.
const DEFAULT_SCENARIO_ID := 2
# On a truly fresh boot (no picker selection, CLI override, or pending path/
# rewind), default to the Military Academy cinematic: group root 7 (Gariland
# Magic City, map 24, entd 392) path-walked to member scenario 8 "Military
# Academy" — the scene under active development. Guarded by chunk existence in
# `_ready`, so a fresh clone without the (gitignored) per-scenario chunks still
# falls back to DEFAULT_SCENARIO_ID's committed cinematic.
const DEFAULT_PATH_TARGET := 8
# Per-id chunk JSONs live here, keyed `scenario_%03d_chunk.json` by scenario id.
# Regenerate with `uv run python tools/export_all_scenario_chunks.py`.
const CHUNK_DIR := "res://assets/scenarios/chunks"
# Committed fallback for the default cinematic when `chunks/` hasn't been
# generated yet (the dir is gitignored — 212 MiB). Byte-identical to
# `chunks/scenario_002_chunk.json`, so a fresh clone still plays the default.
const DEFAULT_CHUNK_FALLBACK := "res://assets/scenarios/scenario_1_chunk.json"

# Resolved from the selected scenario id at `_ready`, before any spawn.
var _scenario_id: int = DEFAULT_SCENARIO_ID
var _map_name: String = "MAP062"
# Raw weather index (0-4) + night flag selecting the map's environment state
# (sky/ambient/lights/palette) at load — matched by raw int, never label (ADR-0056).
var _weather_raw: int = 0
var _is_night: int = 0
var _entd_record: String = "256"
var _chunk_path: String = DEFAULT_CHUNK_FALLBACK
# Defensive fallback for unit_ids referenced by the chunk but absent from
# ENTD — those are event-only characters loaded by Load EVTCHR (opcode 0x58),
# which we don't parse yet. Scenario 1 has zero such refs.
const FALLBACK_SPRITE_ID := 0x01
# ENTD slot sentinel for "empty slot" (FFTPatcher convention).
const ENTD_EMPTY_UID := 0xFF

# Cardinal/16-direction names indexed by the raw-PSX angle high-nibble byte
# (angle >> 8). This is the SAME wheel `Unit.facing_angle_to_world_radians`
# (the yellow arrow) uses: 0x0=E, 0x4=S, 0x8=W, 0xC=N, advancing CCW. The
# The debug facing label reads names off this table (the precise angle), which
# stays the authoritative source. As of the 2026-06-30 harmonization the
# `current_facing` enum (set via `angle_12bit_to_facing`) now ALSO uses this
# canonical wheel — the old E/S swap that made the label disagree with the
# arrow ("EAST" while the arrow points south) is fixed — but the raw-angle
# table remains preferred since it carries the full 16-direction resolution.
const _RAW_WHEEL_NAMES := [
	"E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW",
	"W", "WNW", "NW", "NNW", "N", "NNE", "NE", "ENE",
]

# ENTD `facing_raw` (2-bit, 0..3) → 12-bit world angle. The RE-faithful rule is
# the ROM spawn-init writer at `0x80087c1c` (`sll;sra` = `angle = Facing << 10`)
# — the SAME lift `PsxNum.warp_facing_to_12bit` gives the Warp Unit opcode:
# 0->EAST(0x000), 1->SOUTH(0x400), 2->WEST(0x800), 3->NORTH(0xC00).
#
# This replaces the earlier bespoke spawn table (`[0x400,0x800,0xC00,0x000]`),
# which was `Facing<<10` rotated one cardinal too far (an extra +0x400): every
# spawned unit came up 90° off — Orbonne Battle enemies faced South not West,
# Agrias North not East. The chapel cinematic hid it two ways. First, its
# rotator cast (0x0C/0x13/0x34) carries ENTD `facing_raw = 3`, which lands on
# NORTH (0xC00) faithfully here — matching the live-PSX `+0x70 = 0xC00` capture
# (event_unit_anim_decode.md "later 2") — so the old hardcoded North override is
# no longer needed and has been dropped. Second, its Rotate/Face opcodes
# re-orient the cast within the first instructions, so spawn facing is transient
# there; in a battle it is the resting pose, which is why scenario 4 exposed it.
static func initial_spawn_facing_12bit(facing_raw: int) -> int:
	return PsxNum.warp_facing_to_12bit(facing_raw)


# Resolve the scenario to boot and derive map / ENTD / chunk path from its id.
# Selection comes from the F3 picker via ScenarioDebugSession (survives scene
# reload); absent a pick we use DEFAULT_SCENARIO_ID. The chunk path prefers the
# id-addressable `chunks/scenario_%03d_chunk.json`; if that's absent (dir not
# generated) and we're on the default cinematic, fall back to the committed
# legacy file so a fresh clone still plays.
func _resolve_scenario() -> void:
	_scenario_id = DEFAULT_SCENARIO_ID
	if ScenarioDebugSession.selected_scenario_id > 0:
		_scenario_id = ScenarioDebugSession.selected_scenario_id
	# CLI override (`--scenario=N`) wins — for headful verification runs.
	if DebugConfig.scenario_override > 0:
		_scenario_id = DebugConfig.scenario_override

	var scenario := ScenarioDatabase.get_scenario(_scenario_id)
	if scenario.is_empty():
		push_warning("[ScenarioPlayer] unknown scenario id %d; using default %d"
			% [_scenario_id, DEFAULT_SCENARIO_ID])
		_scenario_id = DEFAULT_SCENARIO_ID
		scenario = ScenarioDatabase.get_scenario(_scenario_id)

	_map_name = "MAP%03d" % int(scenario.get("map_id", 62))
	_weather_raw = int(scenario.get("weather_raw", 0))
	_is_night = 1 if bool(scenario.get("is_nighttime", false)) else 0
	_entd_record = str(int(scenario.get("entd_idx", 256)))

	_chunk_path = _chunk_path_for(_scenario_id)

	var name_str: String = scenario.get("scenario_name", "?")
	print("[ScenarioPlayer] scenario %d '%s' → map=%s entd=%s chunk=%s weather_raw=%d night=%d"
		% [_scenario_id, name_str, _map_name, _entd_record, _chunk_path, _weather_raw, _is_night])


# Resolve the on-disk chunk JSON for a scenario id. Prefers the id-addressable
# `chunks/scenario_%03d_chunk.json`; falls back to the committed legacy file for the
# default cinematic (the chunks/ dir is gitignored, 212 MiB). Absent both, returns
# the (missing) per-id path so a downstream `load_chunk_json` error names the right
# file and tells the user to run the exporter.
func _chunk_path_for(scenario_id: int) -> String:
	var per_id := "%s/scenario_%03d_chunk.json" % [CHUNK_DIR, scenario_id]
	if FileAccess.file_exists(per_id):
		return per_id
	if scenario_id == DEFAULT_SCENARIO_ID:
		return DEFAULT_CHUNK_FALLBACK
	push_warning("[ScenarioPlayer] no chunk for scenario %d at %s — run "
		% [scenario_id, per_id]
		+ "`uv run python tools/export_all_scenario_chunks.py`")
	return per_id


# Load a group member's event-script chunk onto the already-booted VM (used by
# [ScenarioPathApplier] during a path walk). The applier calls `_vm.start()` after
# this — that reruns the VM's per-scenario resets on the same live world. Returns
# false if the chunk can't be loaded so the walk can stop cleanly.
func _play_member(scenario_id: int) -> bool:
	if not _vm.load_chunk_json(_chunk_path_for(scenario_id)):
		return false
	# Tag the VM with the member now playing so its group_finished signal (fired at
	# this chunk's main-context Event End) carries the right id for the navigator.
	_vm.current_scenario_id = scenario_id
	# Publish what is ACTUALLY playing. `_ready` writes this once, before the world boots —
	# which covers the single-scenario path but says nothing as a member walk advances, and
	# says nothing AT ALL under [NavigatorMain], whose navigator branch returns before that
	# write and left the field reading -1 for the whole walk. Setting it per member makes
	# the field mean what its doc claims for both scenes.
	ScenarioDebugSession.active_scenario_id = scenario_id
	# Refresh the map context for {91} Show Map Title: group members do NOT all
	# share a map (e.g. scn 8 = MAP024, scn 9/10 = MAP022), and current_map_id was
	# set once at boot from the entry scenario. Without this, a member on a
	# different map resolves the wrong (or -1 → blank) MAPTITLE slot.
	_vm.current_map_id = int(ScenarioDatabase.get_scenario(scenario_id).get("map_id", -1))
	# Re-derive frame-0 visibility from the MEMBER chunk now loaded. Units are
	# spawned ONCE against the group-ROOT chunk (`_spawn_units` runs before the
	# path walk), and the root/setup chunk carries none of the member's doorway
	# Draw/Erase ops — so without this, a member-only reveal (e.g. scenario 6
	# Ovelia, first vis-op `Draw@104`) would spawn visible and stay visible until
	# its Draw fires. Recomputing here makes visibility a function of the chunk
	# actually playing. See SCENARIO6_UNIT_REVEAL_VISIBILITY.md §5.
	_apply_initial_visibility(_vm.get_instructions())
	return true

const DIALOGUE_BOX_SCENE := preload("res://src/ui3/assemblies/DialogueBox.tscn")

@onready var _map: Node3D = $ProceduralMap
@onready var _player_camera: Node = $PlayerCamera
@onready var _fade_rect: ColorRect = $FadeLayer/FadeRect
@onready var _dialogue_overlay: Node = $DialogueOverlay

var _vm: Node = null
var _units_by_id: Dictionary = {}

## Per-unit facing debug gizmos: the yellow uid/facing TEXT label + yellow 3D
## facing ARROW floating above each spawned unit. OFF by default — they clutter
## the scene once facing alignment is dialled in. The nodes are still BUILT (so
## their facing wires stay live and toggling on is instant), just hidden.
## Toggle from the F3 → Scenario → "View" panel, the F6 key, or the inspector.
## Node names: "DebugIdLabel" / "DebugFacingArrow".
@export var show_facing_debug: bool = false:
	set(value):
		show_facing_debug = value
		_set_facing_debug_visible(value)

## Screen-space compass overlay (top-right N/E/S/W). ON by default. Toggle from
## the F3 → Scenario → "View" panel or the inspector.
@export var show_compass: bool = true:
	set(value):
		show_compass = value
		if is_instance_valid(_compass_layer):
			_compass_layer.visible = value

## The CanvasLayer built by `_setup_compass`, kept so `show_compass` can flip it.
var _compass_layer: CanvasLayer = null

# --- EVTCHR wrong-row detector (HANDOFF_ramza_wrong_sprite_detector.md Task 2) ---
# Ground-truth poll of uid 0x02's (Ramza) BODY material. Reading the bound atlas
# + source rects sidesteps camera framing entirely (Ramza walks off the left
# edge at the cinematic beat, so screenshots can't see him). The bug: the EVTCHR
# atlas (`segment_000.tga`) stays bound while a TYPE1 idle frame writes a low-y
# rect ⇒ the BODY shader samples EVTCHR *row 1* instead of the correct *row 5*.
const DETECT_UID := 0x02
const _EVTCHR_ATLAS_TOKEN := "segment_"  # cinematic atlas basename prefix
const _ROW_PX := 40                       # EVTCHR rows are 40 px tall
const _ROW5_Y_MIN := 160                  # row 5 band: [160, 200)
const _ROW5_Y_MAX := 200
const _WRONG_ROW_Y_MAX := 80              # y < 80 ⇒ row 1/2 (the bug)
const _DETECT_PASS_TIMEOUT_S := 20.0      # held on a correct frame this long ⇒ PASS
var _detect_armed: bool = false
var _detect_verdict_emitted: bool = false
var _detect_saw_row5: bool = false
var _detect_armed_elapsed_s: float = 0.0

# Debug panels are intentionally NOT held as fields here — they're owned by
# the DebugOverlay autoload, persist across scene reload (including
# click-to-rewind), and get their `_vm` ref refreshed via `rebind(_vm)`
# rather than being recreated. See `_register_debug_panels` below.

# Four black ColorRects mounted in a top-level CanvasLayer; sized by the VM's
# `camera_crop_padding` Vector4 (left, top, right, bottom — screen fractions).
# Used to "stop down" the framing without touching the camera itself.
var _crop_bars: Dictionary = {}


func _ready() -> void:
	# Fresh-boot default → princess-abduction cinematic (group root 3 → member
	# scenario 6). Only when nothing else has picked a target: no path walk, no
	# single-scenario pick, no CLI `--scenario=`, no pending rewind. Guarded by
	# the member's chunk existing on disk, so a fresh clone (chunks/ gitignored)
	# falls through to DEFAULT_SCENARIO_ID's committed fallback instead of failing.
	# A plain scenario-player boot is not a navigator walk, so retire any parked walk
	# position. `NavigatorMain` reaches this `super._ready()` only when it is deliberately
	# handing the scene a single-scenario / path boot, which is exactly that case; its own
	# navigator branch returns before here and keeps publishing its position.
	ScenarioDebugSession.navigator_resume_root = -1
	ScenarioDebugSession.navigator_resume_stop_root = -1
	ScenarioDebugSession.navigator_resume_action = -1

	if ScenarioDebugSession.path_target_scenario_id <= 0 \
			and ScenarioDebugSession.selected_scenario_id <= 0 \
			and ScenarioDebugSession.rewind_target_pc < 0 \
			and DebugConfig.scenario_override <= 0 \
			and FileAccess.file_exists("%s/scenario_%03d_chunk.json" % [CHUNK_DIR, DEFAULT_PATH_TARGET]):
		ScenarioDebugSession.path_target_scenario_id = DEFAULT_PATH_TARGET

	# Path mode? The F3 path front-ends (flat picker / group flowchart) park a
	# target scenario in ScenarioDebugSession.path_target_scenario_id. A [Path]
	# boots that target's GROUP ROOT world once, then walks the planned member
	# route onto it (ADR-0054). Resolve this BEFORE `_resolve_scenario` so the
	# world is derived from the root, not the target member. An empty plan (target
	# IS the root) falls through to the normal single-scenario boot of the root.
	var plan: Array = []
	var path_bc_id: int = -1
	var path_target: int = ScenarioDebugSession.path_target_scenario_id
	if path_target > 0:
		ScenarioDebugSession.path_target_scenario_id = -1  # consume the request
		var group := ScenarioGroupDatabase.get_group_for_scenario(path_target)
		if group.is_empty():
			push_warning("[ScenarioPlayer] scenario %d belongs to no group — booting it directly" % path_target)
			ScenarioDebugSession.selected_scenario_id = path_target
		else:
			path_bc_id = int(group.get("battle_conditionals_id", -1))
			var root := int(group.get("group_root_id", path_target))
			ScenarioDebugSession.selected_scenario_id = root  # boot the root world
			plan = ScenarioPath.new().plan(path_bc_id, path_target)
			print("[ScenarioPlayer] PATH mode: target=%d group_root=%d bc=%d → %d step(s)"
				% [path_target, root, path_bc_id, plan.size()])

	# Resolve which scenario to boot (picker selection survives scene reload via
	# ScenarioDebugSession) and derive map / ENTD / chunk / music from its id.
	_resolve_scenario()

	# Record which scenario is ACTUALLY playing (the target member in path mode,
	# else the resolved single id — NOT the root the world booted from) so the F3
	# rewind can detect a nested group member and replay it from the group root.
	ScenarioDebugSession.active_scenario_id = path_target if path_target > 0 else _scenario_id

	# Cinematics don't show the friendly/enemy roster bars — those are battle UI.
	_hide_combat_ui()

	# Boot the persistent world for the resolved scenario: map load + ENTD spawn +
	# VM construct/wire + dialogue/compass/panels + initial fade-to-black. Factored
	# so the game-state navigator (NavigatorMain, which extends this scene) reuses
	# the exact same world boot before driving its own multi-group walk.
	await _boot_scenario_world()

	# Path mode with real steps: walk the planned member route onto the booted root
	# world instead of playing a single chunk. The applier forces each step's
	# director state, verifies isolation, loads the member's chunk, and starts the
	# VM — intermediate members run to completion, the target member is left playing.
	if not plan.is_empty():
		# Rewind-from-root: a double-click in a nested member parks BOTH the target
		# member (path_target) and the clicked PC. Consume the PC here and hand it to
		# the applier so the final member rewinds to it instead of playing through.
		var path_rewind_pc: int = -1
		if ScenarioDebugSession.rewind_target_pc >= 0:
			path_rewind_pc = ScenarioDebugSession.rewind_target_pc
			ScenarioDebugSession.rewind_target_pc = -1
		var applier := ScenarioPathApplier.new(_vm, _play_member, get_tree())
		await applier.walk(plan, path_bc_id, path_rewind_pc)
		return

	# Single-scenario boot: load the resolved chunk and play it.
	if not _vm.load_chunk_json(_chunk_path):
		push_error("[ScenarioPlayer] failed to load chunk JSON '%s'; halting" % _chunk_path)
		return
	# Re-derive frame-0 visibility from the chunk now loaded (matches `_play_member`
	# in path mode). Here the loaded chunk == the spawn chunk, so it agrees with
	# `_spawn_units`; kept for a single, uniform "visibility follows the loaded
	# chunk" rule across both boot paths.
	_apply_initial_visibility(_vm.get_instructions())
	_vm.start()

	# Click-to-rewind hand-off — when the user double-clicked an instruction
	# in the previous run of this scene, `ScenarioDebugSession.rewind_target_pc`
	# carries the target PC across the scene reload. Fast-forward to it.
	# Consume the sentinel (set back to -1) so a later manual Ctrl+R doesn't
	# loop back into rewind.
	# `--rewind-pc=N` is the same hand-off arriving from a shell instead of from a
	# double-click, and it loses to a live session sentinel.
	if ScenarioDebugSession.rewind_target_pc < 0 and DebugConfig.scenario_rewind_pc >= 0:
		ScenarioDebugSession.rewind_target_pc = DebugConfig.scenario_rewind_pc
	if ScenarioDebugSession.rewind_target_pc >= 0:
		var target_pc: int = ScenarioDebugSession.rewind_target_pc
		ScenarioDebugSession.rewind_target_pc = -1
		_vm.set_rewind_target(target_pc)
	# Side-by-side rig: screenshot trigger lives in the Scenario VM debug panel
	# (F3 → Scenario → Scenario VM → "Screenshot" / "Pause + Screenshot"); see
	# ADR-0051. The older `SCENARIO_TRACER_SCREENSHOT` env-var path used to live
	# here and was deleted with that ADR — the env approach leaked across
	# shells and was invisible to a running editor session.


## Boot the persistent world for the currently-resolved scenario (`_resolve_scenario`
## must have run): load the map, spawn the ENTD cast, construct + wire the VM, set up
## the dialogue box / compass / debug panels, and prime the fade-to-black. Leaves the
## VM built but NOT started — the caller (`_ready` here, or the navigator) decides how
## to drive the opcode stream (single chunk / applier walk / member-by-member).
## The shared game-variable store to run scenarios against, or null for a private one.
## Set by whoever owns the campaign (see [NavigatorMain]); read once, at VM construction.
var campaign_store: WorldMapVariables = null


func _boot_scenario_world() -> void:
	# Load under black FIRST — before change_map + the two process_frame yields below, which
	# RENDER the freshly-built world. On a re-boot the fade may be revealed (the prior group
	# left it transparent), so priming black last would flash the new world's default camera
	# for those frames. Blacking it up front hides the whole build; the Reveal opcode fades
	# it back in. (Redundant-but-harmless on first boot, where nothing is revealed yet.)
	_fade_rect.color = Color(0, 0, 0, 1)
	# MapComposer.auto_build_on_ready is false; we drive the first load here.
	# Forward the scenario's weather/night so MapComposer renders the matching
	# map-state sky/lighting/palette in the initial pass (ADR-0056). Arrangement
	# stays Primary (0) — scenarios expose no Secondary selector yet.
	# #589: hand the map's two outputs to the host systems that consume them.
	# Replay-then-connect, so a map the composer auto-built in ITS `_ready`
	# (children ready before parents) is covered by the replay and every later
	# `change_map` by the connect. See BattlefieldWiring.
	BattlefieldWiring.wire_map(_map)
	_map.change_map(_map_name, _weather_raw, _is_night, 0)
	await get_tree().process_frame
	await get_tree().process_frame

	await _spawn_units()

	_vm = ScenarioVMClass.new()
	_vm.name = "ScenarioVM"
	# ADR-0179: hand the VM the CAMPAIGN's variable store when a campaign owns this run,
	# so a scenario's own `Zero(110); Add(110, k)` advances the world map's story counter.
	# Null (the default, and every standalone/debug boot) leaves the VM on its private
	# store, which is exactly the old behaviour.
	if campaign_store != null:
		_vm.set_variable_store(campaign_store)
	add_child(_vm)
	_vm.units_by_id = _units_by_id
	_vm.player_camera = _player_camera
	_vm.map_composer = _map
	_vm.map_size_z = _load_map_size_z(_map_name)
	_vm.map_size_x = _load_map_size_x(_map_name)
	_vm.fade_rect = _fade_rect
	_vm.dialogue_overlay = _dialogue_overlay
	# {47} Add Ghost Unit spawns a sprite-only actor with no ENTD record at runtime —
	# the VM can't pre-spawn it, so it calls back into the host to instantiate one.
	_vm.ghost_spawn_fn = Callable(self, "_spawn_ghost_actor")
	# Auto-play-through by default: boxed Display Messages reveal in full and
	# release after a fixed dwell instead of blocking on the Cross/confirm key,
	# so the whole chapel cinematic runs start→end with zero key presses. This
	# is the real-opcode path (NOT `play_through_skip_unknown`, which *skips*
	# opcodes) — only the dialog gate is auto-released; Wait-For-Instruction
	# Task=N anim/move gates still self-resolve when their activity completes.
	# (HANDOFF_ramza_wrong_sprite_detector.md Task 1.) Flip OFF in the F3
	# Scenario VM panel to drive the pace by hand.
	_vm.dialog_auto_advance = true
	# {22} Switch Track needs the scenario's two ATTACK.OUT songs. Resolve them
	# from ScenarioDatabase and play song one at load (mirroring FFT scenario-
	# load / ScenarioLoader) so {60} Fade Sound has a live track and the first
	# {22} toggles song one → song two (Pray → Enemy Attack).
	var scenario := ScenarioDatabase.get_scenario(_scenario_id)
	_vm.current_scenario_id = _scenario_id
	_vm.music_slot_one_id = int(scenario.get("music_file_one_id", 0))
	_vm.music_slot_two_id = int(scenario.get("music_file_two_id", 0))
	# {91} Show Map Title selects its location-name strip by map context (§3), so
	# hand the VM the scenario's map_id to resolve the MAPTITLE slot.
	_vm.current_map_id = int(scenario.get("map_id", -1))
	if _vm.music_slot_one_id != 0:
		MusicPlayer.play_slot(_vm.music_slot_one_id)
	_setup_dialogue_box()
	_apply_debug_id_labels()
	_apply_facing_arrows()
	_setup_compass()

	_build_crop_overlay()
	_vm.camera_director.crop_padding_changed.connect(_apply_crop_padding)

	_register_debug_panels()


func _process(delta: float) -> void:
	if DebugConfig.evtchr_row_detect_enabled:
		_detect_tick(delta)


# Poll uid 0x02's BODY material for the wrong-row condition. Sampled EVERY frame
# (not on a coarse timer) because the cinematic beat passes in well under a
# second under auto-advance. Verdict state machine, latched once emitted:
#   - bound atlas == segment_* AND a rect.y < 80  → FAIL (EVTCHR row 1/2 bug)
#   - was in cinematic, atlas reverted to own SPR → PASS (clean exit_cinematic_mode)
#   - held on a correct (row-5) cinematic frame past the timeout → PASS
# On a verdict the scene quits with a matching exit code so this doubles as a
# regression gate for the eventual fix.
func _detect_tick(delta: float) -> void:
	if _detect_verdict_emitted:
		return
	var unit: Node = _units_by_id.get(DETECT_UID)
	if unit == null or not ("material" in unit) or unit.material == null:
		return
	var mat: ShaderMaterial = unit.material
	var tex := mat.get_shader_parameter("type1_tex") as Texture2D
	var atlas := tex.resource_path.get_file() if tex != null else "<none>"
	var in_cinematic := atlas.contains(_EVTCHR_ATLAS_TOKEN)

	var rects: Array = mat.get_shader_parameter("type1_rects")
	var min_y := INF
	if rects != null:
		for r in rects:
			min_y = min(min_y, (r as Vector2).y)

	if not _detect_armed:
		if in_cinematic:
			_detect_armed = true
			_detect_armed_elapsed_s = 0.0
			print("[DETECT] armed — uid 0x%02X entered cinematic mode (atlas=%s)" % [DETECT_UID, atlas])
		return

	_detect_armed_elapsed_s += delta

	if in_cinematic:
		if min_y < _WRONG_ROW_Y_MAX:
			# 1-based row label to match the handoff convention (row5 = y∈[160,200)).
			var row := int(min_y) / _ROW_PX + 1 if min_y < INF else -1
			_emit_verdict(false, "uid 0x%02X BODY rect row%d y=%s (expected row5 ~160) atlas=%s" % [
				DETECT_UID, row, str(min_y), atlas])
			return
		if min_y >= _ROW5_Y_MIN and min_y < _ROW5_Y_MAX:
			_detect_saw_row5 = true
	else:
		# Atlas reverted to the unit's own SPR after the cinematic — the renderer
		# exited cleanly, so no wrong-row sample can occur. That's the fix's PASS.
		_emit_verdict(true, "uid 0x%02X exited cinematic cleanly (atlas=%s, saw_row5=%s)" % [
			DETECT_UID, atlas, _detect_saw_row5])
		return

	if _detect_saw_row5 and _detect_armed_elapsed_s >= _DETECT_PASS_TIMEOUT_S:
		_emit_verdict(true, "uid 0x%02X held on correct row5 frame for %.0fs, no wrong-row write" % [
			DETECT_UID, _DETECT_PASS_TIMEOUT_S])


func _emit_verdict(passed: bool, detail: String) -> void:
	_detect_verdict_emitted = true
	if passed:
		print("[DETECT][PASS] %s" % detail)
		get_tree().quit(0)
	else:
		print("[DETECT][FAIL] %s" % detail)
		get_tree().quit(1)


## Register the "Scenario" root picker + group flowchart ([ScenarioPathDebugPanel]) —
## the SCENARIO-PLAYER navigation launcher. Stateless w.r.t. the VM (it parks a target
## in `ScenarioDebugSession.path_target_scenario_id` and reloads), so it is find-or-skip
## rather than rebound.
##
## [b]Its own seam because a subclass can legitimately not want it.[/b] [NavigatorMain]
## drives a multi-group STORY WALK and has its own launcher (the Navigator panel) in the
## same masonry cell; a second, rival "pick a scene" picker there navigates the scene the
## one way that scene is never meant to be navigated. It overrides this to nothing.
func _register_scenario_path_panel() -> void:
	for panel in DebugOverlay._panels.get(DebugOverlay.Category.SCENARIO, []):
		if is_instance_valid(panel) and panel is ScenarioPathDebugPanel:
			return
	var path_panel := ScenarioPathDebugPanel.new()
	path_panel.setup()
	DebugOverlay.register_panel(path_panel, DebugOverlay.Category.SCENARIO, "scenario_path")


# Hook the per-scenario debug panels into DebugOverlay. The autoload outlives
# the scene, so on every scene reload (Ctrl+R or click-to-rewind) we LOOK FOR
# an existing panel of each type and just rebind it to the new VM instead of
# creating a fresh one — that's what preserves the panel's UI state (scroll
# position, selected disassembly row, every spinbox/checkbox value) across
# the reload. First boot: panels don't exist yet, fall through to the
# create+register path.
func _register_debug_panels() -> void:
	# Re-entry point for the catalogue page's checkboxes. `CombatPanelCatalog.mount` sets
	# the same hook for a combat host; without one here, turning an entry back ON while
	# standing on a scenario scene only recorded the preference for next boot — the panel
	# did not appear until a reload. Every branch below is find-or-create, so re-entering
	# builds exactly the missing entries. The Callable goes invalid when this scene is
	# freed, which is the guard against remounting into a dead host.
	DebugOverlay.set_catalog_remount(func() -> void:
		if is_inside_tree():
			_register_debug_panels())

	# The map's Skirts + Map Render panels. Mounted host-side (#555) — `MapComposer`
	# used to construct and register them itself, which is an ADR-0068 R1 violation:
	# the production owner of the tunables also instantiated their view. Placed here,
	# after the map is composed, so the pure-VIEW rows resolve their owners' defaults.
	# Gated by the same `map` catalogue id the combat hosts use — the two panels carry it,
	# so the switch on the F3 Catalogue page governs them here too. Before the id reached
	# this line, turning `map` off left the Skirts panel up on this scene and every scene
	# that inherits it, because nothing on the path from `.new()` to the dashboard asked.
	if DebugOverlay.is_panel_enabled("map"):
		MapDebugPanels.register_map_panels(_map)

	# Scenario debug UI is split across three masonry cells so it packs like the
	# rest of the dashboard instead of one giant column:
	#   SCENARIO          → "Scenario" : the root picker (pick-a-scene, top priority)
	#   SCENARIO_PLAYBACK → "Scenario Playback" : disassembly + instruction stepping
	#   SCENARIO_LOOK     → "Scenario Look" : on-screen look tuners (dialogue box,
	#                       view gizmos, weather, cinematic EVTCHR pose scrub)
	# Panels persist across scene reload in the DebugOverlay autoload; find an
	# existing one of each type (across all three cells) and rebind it to the
	# freshly-booted VM/scene instead of recreating — that preserves UI state
	# (scroll pos, selected row, spinbox values).
	var existing_vm: ScenarioVMDebugPanel = null
	var existing_box: ScenarioDialogueBoxDebugPanel = null
	var existing_view: ScenarioViewDebugPanel = null
	var existing_weather: ScenarioWeatherDebugPanel = null
	var existing_cine: ScenarioCinematicDebugPanel = null
	var existing_unit_shader: UnitShaderDebugPanel = null
	var existing_align: ScenarioUnitAlignmentDebugPanel = null
	var existing_sprite_off: ScenarioUnitSpriteOffsetDebugPanel = null
	for cat in [DebugOverlay.Category.SCENARIO, DebugOverlay.Category.SCENARIO_PLAYBACK, DebugOverlay.Category.SCENARIO_LOOK]:
		for panel in DebugOverlay._panels.get(cat, []):
			if not is_instance_valid(panel):
				continue
			if existing_vm == null and panel is ScenarioVMDebugPanel:
				existing_vm = panel
			elif existing_box == null and panel is ScenarioDialogueBoxDebugPanel:
				existing_box = panel
			elif existing_view == null and panel is ScenarioViewDebugPanel:
				existing_view = panel
			elif existing_weather == null and panel is ScenarioWeatherDebugPanel:
				existing_weather = panel
			elif existing_cine == null and panel is ScenarioCinematicDebugPanel:
				existing_cine = panel
			elif existing_unit_shader == null and panel is UnitShaderDebugPanel:
				existing_unit_shader = panel
			elif existing_align == null and panel is ScenarioUnitAlignmentDebugPanel:
				existing_align = panel
			elif existing_sprite_off == null and panel is ScenarioUnitSpriteOffsetDebugPanel:
				existing_sprite_off = panel

	# --- Scenario · Scene (top): root picker + group flowchart — the primary
	# "pick a scene" surface. Registered FIRST so it heads its column.
	_register_scenario_path_panel()

	# --- Scenario · Playback: disassembly + instruction stepping.
	if existing_vm != null:
		existing_vm.rebind(_vm)
	else:
		var vm_panel := ScenarioVMDebugPanel.new()
		vm_panel.setup(_vm)
		DebugOverlay.register_panel(vm_panel, DebugOverlay.Category.SCENARIO_PLAYBACK, "scenario_vm")

	# --- Scenario · Look: dialogue-box placement.
	if existing_box != null:
		existing_box.rebind(_vm)
	else:
		var box_panel := ScenarioDialogueBoxDebugPanel.new()
		box_panel.setup(_vm)
		DebugOverlay.register_panel(box_panel, DebugOverlay.Category.SCENARIO_LOOK, "scenario_dialogue_box")

	# View gizmos (facing text/arrows + compass) live on THIS scene, not the VM,
	# so this panel binds to `self`.
	if existing_view != null:
		existing_view.rebind(self)
	else:
		var view_panel := ScenarioViewDebugPanel.new()
		view_panel.setup(self)
		DebugOverlay.register_panel(view_panel, DebugOverlay.Category.SCENARIO_LOOK, "scenario_view")

	# {3C} Weather look-knobs (drop/splat intensity, px width/length, splat size +
	# straddle-gate). Binds to the VM, which owns the lazy ScenarioWeather node.
	if existing_weather != null:
		existing_weather.rebind(_vm)
	else:
		var weather_panel := ScenarioWeatherDebugPanel.new()
		weather_panel.setup(_vm)
		DebugOverlay.register_panel(weather_panel, DebugOverlay.Category.SCENARIO_LOOK, "scenario_weather")

	# Cinematic EVTCHR pose scrubber (issue #124) — segment/frame override + re-apply.
	if existing_cine != null:
		existing_cine.rebind(_vm)
	else:
		var cine_panel := ScenarioCinematicDebugPanel.new()
		cine_panel.setup(_vm)
		DebugOverlay.register_panel(cine_panel, DebugOverlay.Category.SCENARIO_LOOK, "scenario_cinematic")

	# Unit Shader depth tuner (ADR-0009): scrub `ot_unit_forward` (the unit
	# sprite's forward nudge in front of its own tile) and `center_bias` (the
	# billboard depth-sample height) live across every spawned unit. The units
	# accessor reads the live `_units_by_id`, so it tracks spawns/ghosts. Grouped
	# in the Scenario · Look cell; rebinds to the fresh scene on reload.
	if existing_unit_shader != null:
		existing_unit_shader.rebind(self, func(): return _units_by_id.values())
	else:
		var unit_shader_panel := UnitShaderDebugPanel.new()
		unit_shader_panel.setup(self, func(): return _units_by_id.values())
		DebugOverlay.register_panel(unit_shader_panel, DebugOverlay.Category.SCENARIO_LOOK, "unit_shader")

	# Unit Alignment rig: every knob that moves a unit sprite relative to its tile
	# (pixel_aspect spacing, unit_stretch/mesh-scale width, mesh Y-lift + loc_offset
	# pivot) plus a tile-grid overlay + feet-vs-tile-center readout. Same units
	# accessor + rebind-on-reload contract as the Unit Shader panel above.
	if existing_align != null:
		existing_align.rebind(self, func(): return _units_by_id.values())
	else:
		var align_panel := ScenarioUnitAlignmentDebugPanel.new()
		align_panel.setup(self, func(): return _units_by_id.values())
		DebugOverlay.register_panel(align_panel, DebugOverlay.Category.SCENARIO_LOOK, "scenario_unit_align")

	# Per-unit sprite-offset nudge: pick ONE unit and move only ITS shared_loc_offset
	# (art placement on its billboard). Companion to the global alignment panel above;
	# used to dial a carried/cinematic pose onto its target (scn6: Ovelia onto Delita's
	# shoulder at PC210). Overrides are keyed by unit id and re-applied on reload, so a
	# tweak survives double-clicking a beat in the VM panel. Same rebind contract.
	if existing_sprite_off != null:
		existing_sprite_off.rebind(self, func(): return _units_by_id)
	else:
		var sprite_off_panel := ScenarioUnitSpriteOffsetDebugPanel.new()
		sprite_off_panel.setup(self, func(): return _units_by_id)
		DebugOverlay.register_panel(sprite_off_panel, DebugOverlay.Category.SCENARIO_LOOK, "scenario_sprite_offset")

	# PAR / Display panels (ADR-0036/0044): the world `pixel_aspect` clip-X stretch, UI
	# PAR, and per-taxonomy sprite-width stretches. These scrub the PSXDisplay
	# autoload (stateless w.r.t. the VM), so unlike the VM/camera panels above they
	# need no rebind — just ensure one of each exists in the DISPLAY category so the
	# scenario can tune PAR live (matches GPUArena / EffectViewer). Idempotent
	# across scene reloads (DebugOverlay outlives the scene).
	# DisplayDebugPanel is GONE (ADR-0151): it was two TuneField rows over slugs
	# DebugConfig already binds, so the F3 Registry page renders both and a
	# hand-built panel for them was the surface ADR-0068 dec. 9 superseded.
	# The ten panels ANY host can build — Simulation, Logging, Performance, Tiles, Font,
	# Projectile, Feedback HUD, Cursor, Camera Feel and the PSX Display panel this block
	# used to hand-roll on its own. They were reachable only from `CombatPanelCatalog`,
	# i.e. only from the two scenes that `extends CombatHost`, which is why a CHECKED
	# "Simulation" box produced nothing here: no code path on this scene mounted it. The
	# mount is idempotent by id, so this is also the reload path — an entry already up is
	# left alone, and one the user has just switched back on is the only thing built.
	UniversalDebugPanels.mount(self)

	# The F3 AUDIO tab — the package's SPU panel plus the host's volume slider. Both
	# halves are stateless w.r.t. the VM, so the mount is idempotent across reloads;
	# that guard lives in the adapter now, beside the mount it guards.
	AudioHostAdapter.register_audio_tab()


# Mount the boxed-portrait DialogueBox under the scenario's orthographic
# camera (the same screen-space rig CombatUI uses) so it is screen-locked at
# the correct ui3 scale, then hand it to the VM. The VM positions it on the
# speaker per Display Message and drives the typewriter + advance gate.
func _setup_dialogue_box() -> void:
	var cam := get_node_or_null("PlayerCamera/FocusPoint/Camera")
	if cam == null:
		push_warning("[ScenarioPlayer] no Camera under PlayerCamera; DialogueBox unwired")
		return
	# FFT keeps up to THREE dialogue boxes on screen at once (the Orbonne opening
	# stacks two, the 161-176 beat three — concurrent_dialogue_boxes_decode.md), so
	# wire a 3-box pool. Slot 1 is `dialogue_box`; slots 2-3 are `extra_dialogue_boxes`.
	# The VM opens each Display Message into the next free slot and closes by
	# `Change Dialog Target=N`.
	var boxes: Array = []
	for i in range(3):
		var box := DIALOGUE_BOX_SCENE.instantiate()
		box.name = "DialogueBox%d" % (i + 1)
		# Sit on the same screen-space depth plane as CombatUI (camera-local z=-10).
		# Set BEFORE add_child so DialogueBox._ready captures z=-10 as its tween base
		# (the open/close grow-shrink composes on top of this placement).
		box.position = Vector3(0, 0, -10)
		box.visible = false
		cam.add_child(box)
		boxes.append(box)
	_vm.box_pool.dialogue_box = boxes[0]
	_vm.box_pool.extra_dialogue_boxes = boxes.slice(1)


func _hide_combat_ui() -> void:
	# CombatUI is parented under PlayerCamera/FocusPoint/Camera in PlayerCamera.tscn.
	var combat_ui := _player_camera.get_node_or_null("FocusPoint/Camera/CombatUI")
	if combat_ui:
		combat_ui.visible = false


func _build_crop_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CropOverlay"
	layer.layer = 100  # On top of CombatUI (which is hidden anyway in cinematic).
	add_child(layer)
	for k in ["left", "top", "right", "bottom"]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_FULL_RECT)
		bar.visible = false
		layer.add_child(bar)
		_crop_bars[k] = bar


func _apply_crop_padding(pad: Vector4) -> void:
	# pad = (left, top, right, bottom) as 0..0.5 fractions of viewport extent.
	var vp := get_viewport().get_visible_rect().size
	var l := _crop_bars["left"] as ColorRect
	var t := _crop_bars["top"] as ColorRect
	var r := _crop_bars["right"] as ColorRect
	var b := _crop_bars["bottom"] as ColorRect

	var lw := pad.x * vp.x
	var tw := pad.y * vp.y
	var rw := pad.z * vp.x
	var bw := pad.w * vp.y

	l.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	l.position = Vector2.ZERO
	l.size = Vector2(lw, vp.y)
	l.visible = lw > 0.0

	r.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	r.position = Vector2(vp.x - rw, 0)
	r.size = Vector2(rw, vp.y)
	r.visible = rw > 0.0

	t.set_anchors_preset(Control.PRESET_TOP_WIDE)
	t.position = Vector2.ZERO
	t.size = Vector2(vp.x, tw)
	t.visible = tw > 0.0

	b.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	b.position = Vector2(0, vp.y - bw)
	b.size = Vector2(vp.x, bw)
	b.visible = bw > 0.0


func _spawn_units() -> void:
	var entd = _load_entd_record(_entd_record)
	if entd == null:
		push_error("[ScenarioPlayer] ENTD record %s missing" % _entd_record)
		return

	var unit_scene: PackedScene = load(UNIT_SCENE_PATH)
	if unit_scene == null:
		push_error("[ScenarioPlayer] cannot load Unit.tscn")
		return

	# Spawn every non-empty ENTD slot with its ROM-specified sprite_set. Frame-0
	# visibility is CHUNK-DERIVED (`_chunk_reveals_first`): a unit starts hidden
	# iff its first visibility opcode reveals/holds it ({44} Draw / {45} Add
	# Draw=1); else visible. This is the PSX `+0xa` show flag, NOT the ENTD
	# `always_present` formation gate the old code wired in here (which drew
	# Ovelia at the doorway a beat early — see SCENARIO6_UNIT_REVEAL_VISIBILITY.md).
	#
	# Disassembly basis: BATTLE.BIN `FUN_BATTLE.BIN__8008d05c` (Ghidra wiki
	# comment "Post add/transform Graphic Update by Battle ID") is the AddUnit
	# handler; it commits the SHP/SEQ via `BATTLE_get_battle_stats_from_battle_id`
	# rather than spawning the unit — the unit already exists in the loaded
	# ENTD record. Mirroring that, every ENTD slot is pre-instantiated here.
	var chunk_insts := _load_chunk_instructions()
	for slot in entd["slots"]:
		var uid := int(slot["unit_id"])
		if uid == ENTD_EMPTY_UID:
			continue
		var sprite_set := _resolve_sprite_set(slot)
		var unit = await _spawn_unit_at(unit_scene, uid, sprite_set,
			int(slot["x"]), int(slot["y"]), int(slot["facing_raw"]))
		if unit:
			# PRESENCE (allocated in the PSX sprite list): an `always_present` unit is
			# allocated at event load, so it's a valid team-broadcast target even while
			# held/hidden (scn6 Ovelia at the pc31 player-team rotate). Non-always_present
			# units are NOT yet allocated — they join the roster only when {45} Add /
			# {44} Draw introduces them (ScenarioWorld). Presence is also the master gate
			# on frame-0 render visibility (_frame0_visible): a not-yet-present unit can't
			# be drawn, so scn6 uid 1/4 (added by {45} Add Draw=0 at pc434) stay hidden
			# for all of scenario 6 rather than rendering ~434 instructions early.
			var present := bool(
				slot.get("flags2_decoded", {}).get("always_present", false))
			unit.visible = _frame0_visible(present, uid, chunk_insts)
			unit.scenario_present = present
			# Select the BODY shader's palette row. Two sources, split by unit
			# kind (see `_resolve_body_palette_row`): MONSTERS take the row baked
			# into their JOB (jobs.json body_palette_row, ADR-0022); humans/named
			# keep the ENTD `palette` byte CLAMPED to rows the resolved SPR
			# actually authored (which bit-matched PSX for scenario-1 generics).
			# FFT renders BOTH combat (TYPE1.SHP) and event (EVTCHR) sprite sheets
			# with this row. `sprite_set` here is the RESOLVED SPR id (the clamp
			# is per-SPR — a named unit like Delita authors only body row 0).
			unit.body_palette_row = _resolve_body_palette_row(slot, sprite_set)
			# Team colour for the event multi-unit broadcast selector (Units|Multi):
			# ENTD flags2 bits 5..4, 0=Blue/player. The ROM reads the same field as
			# structB[+0x5]&0x30 == team_color<<4. See ScenarioDecode.unit_set_*.
			unit.scenario_team_color = int(slot.get("team_color", 0))
			# Resolve the unique's OWNED template folder (ADR-0072 #223) so the
			# DialogueBox portrait path fronts the flat sheet with its portrait.tga.
			# Scenario spawn bypasses UnitSpawn.build (the combat seam that
			# sets template_folder, #203), so we populate it here; "" for a
			# generic/monster keeps the flat sprite-sheet portrait.
			unit.template_folder = _resolve_template_folder(slot)
			_units_by_id[uid] = unit

	# Defensive: chunk references a unit_id absent from ENTD. In vanilla FFT
	# such uids are loaded by Load EVTCHR (opcode 0x58 → `Open_EVTCHR` in
	# BATTLE.BIN at ~0x8013c7c0, allocates 30 KB per slot from EVTCHR.BIN),
	# which we don't parse yet. Spawn with the placeholder sprite so the
	# downstream opcodes have a unit to operate on. Scenario 1 has zero such
	# references — this is a safety net for future scenarios.
	var referenced := _scan_referenced_unit_ids()
	for uid in referenced:
		if _units_by_id.has(uid):
			continue
		print("[ScenarioPlayer] unit_id 0x%02X referenced by chunk but absent from ENTD — spawning EVTCHR-fallback placeholder" % uid)
		var unit = await _spawn_unit_at(unit_scene, uid, FALLBACK_SPRITE_ID, -1, -1, 3)
		if unit:
			unit.visible = false
			unit.set_meta("scenario_fallback", true)
			_units_by_id[uid] = unit


# FFT generic/monster sprite resolution — ENTD `sprite_set` -> real SPR id.
# The discriminator is the `sprite_set` VALUE, per the spec's "The rule"
# (research/key_documents/SPRITE_SET_RESOLUTION.md): `< 0x80` is a NAMED unit
# (the byte IS the SPR id), and 0x80/0x81/0x82 are the three MARKER values
# (Generic Male / Generic Female / Monster) whose real sprite comes from the
# unit's JOB via `JobDatabase.get_sprite_id` (ADR-0013), the same path combat
# uses at unit-load. Scenario-6's chocobo (0x82 + job 0x5E) resolves to SPR
# 0x86; passed raw it drew 82.SPR = "Male Bard".
#
# Keyed on the sprite_set value, NOT the `flags1_decoded.monster` bit: real
# ENTD has 0x82 monster slots with that bit CLEAR (records 297/425: uid 0x86,
# sprite_set 0x82, job 0x5E, monster=false) — a flag-gated resolver leaks those
# through as raw 0x82. The bit is unreliable for monsters (those same slots also
# set `female`); the sprite_set byte is the authoritative art selector. Only
# 0x80/0x81/0x82 occur ≥0x80 in the shipped ENTD, so `< 0x80` cleanly splits
# marker from direct index. Pure function (arg + JobDatabase statics only).
static func _resolve_sprite_set(slot: Dictionary) -> int:
	var sprite_set := int(slot.get("sprite_set", 0))
	if sprite_set < 0x80:
		# Named / story unit: the byte IS the SPR id; job is irrelevant to art.
		return sprite_set
	var job_id := int(slot.get("job", 0))
	# 0x80 Generic Male / 0x81 Generic Female / 0x82 Monster. Gender from flags1
	# (authoritative for humans); fall back to the 0x81 marker. Monster jobs hold
	# the same sprite in both gender keys, so the choice is a no-op for 0x82.
	var is_female: bool = bool(
		slot.get("flags1_decoded", {}).get("female", sprite_set == 0x81))
	var resolved := JobDatabase.get_sprite_id("%02x" % job_id, is_female)
	if resolved <= 0:
		# Unknown job — keep the placeholder rather than blanking the body.
		return sprite_set
	return resolved


# FFT sprite palette-row resolution — delegates to the unified two-axis rule in
# `SpritePaletteResolver` (research/working_documents/EVTCHR_CLUT_RESOLUTION.md
# §3.1). A MONSTER's color is a palette-row swap sourced from the JOB (SCUS byte
# 0x2E -> jobs.json `body_palette_row`, ADR-0022); the ENTD `palette` byte does
# NOT drive it (real PSX scenario-6: unit 0x8B job 0x5E renders YELLOW despite
# ENTD `palette: 2`). Humans/named units keep the byte, but ONLY where the
# resolved SPR authored that row — generics author rows 0-4 so Blue=0/Red=2 pass
# through, while a named unique unit (Delita 0x05) authors only body row 0, so a
# stale byte of 2 clamps to 0 (else it samples an all-black row).
#
# Thin wrapper kept so `ResolveBodyPaletteRowTest` and the spawn loop call one
# named entry point; `sprite_id` is the RESOLVED SPR id (from
# `_resolve_sprite_set`). Pure function (args + database statics only).
static func _resolve_body_palette_row(slot: Dictionary, sprite_id: int) -> int:
	return SpritePaletteResolver.resolve_body_palette_row(slot, sprite_id)


# The unique speaker's OWNED template folder (ADR-0072 #202/#203) addressed by the
# ENTD slot's `special_name` — the resolver's unique branch, a pure static residue
# lookup. Returns "" for a generic/monster (special_name not in the residue), which
# keeps the flat sprite-sheet portrait. Populated onto the spawned Unit so the
# DialogueBox portrait path (#223) fronts the sheet with the unit's OWNED
# portrait.tga, mirroring what UnitSpawn.build does for combat units. Pure
# function (arg + ResidueManifest statics only).
static func _resolve_template_folder(slot: Dictionary) -> String:
	return ResidueManifest.folder_of(int(slot.get("special_name", 0)))


func _spawn_unit_at(unit_scene: PackedScene, uid: int, sprite_set: int,
		grid_x: int, grid_y: int, fft_facing: int) -> Node:
	var unit = unit_scene.instantiate()
	unit.body_sprite_id = sprite_set
	unit.name = "Unit_%02X" % uid
	add_child(unit)
	# Wait for _ready to finish so animation_set + playbacks exist.
	await get_tree().process_frame
	if grid_x >= 0 and grid_y >= 0:
		ScenarioVMClass.cinematic_place(unit, grid_x, grid_y, _map_lattice())
	# Seed `facing_angle` (raw 12-bit) from the ENTD facing via the faithful ROM
	# rule so a never-rotated spawn renders the correct idle pose via the
	# camera-composed pose-octant + yellow arrow (both consume the raw angle),
	# instead of falling back to `Unit._CARDINAL_TO_12BIT` at facing_angle == -1.
	# Derive the world-cardinal enum from that SAME angle (single source of
	# truth). Mirrors the raw-PSX seeding `ScenarioVM._op_warp_unit` does for
	# Warp-placed units — spawn and Warp now share one convention.
	var angle_12bit := initial_spawn_facing_12bit(fft_facing)
	# FAITHFUL spawn default (MARCH_OPCODE_80_SEMANTICS.md §2.1 / §4.1): a placed battle
	# sprite march-idles the instant it's built (ROM status-anim selector FUN_80082eec runs
	# at construction), so it spawns into COMBAT IDLE, not the cinematic tent. `scenario_spawn_facing`
	# seeds the precise 12-bit facing (source of truth) + derived cardinal WITHOUT the cinematic
	# freeze — the marching counterpart to `scenario_set_facing`. Units that must hold a static
	# pose are frozen by their own opcode ({11} Unit Anim on the speaker, {8C} Rotate); {80}
	# March later RELEASES the addressed unit back to this same march-idle (op_march).
	unit.scenario_spawn_facing(angle_12bit)
	print("[ScenarioPlayer] spawned unit_id=0x%02X sprite_set=0x%02X tile=(%d,%d) entd_facing=%d facing_angle=0x%03X" %
		[uid, sprite_set, grid_x, grid_y, fft_facing, unit.facing_angle])
	return unit


## Host callback for {47} Add Ghost Unit (wired onto the VM as `ghost_spawn_fn`).
## Instantiates a sprite-only ghost actor at runtime — a ghost has no ENTD record, so
## it can't ride the pre-spawn pass in `_spawn_units`; this mirrors `_spawn_unit_at`
## (body_sprite_id, cinematic_place, seed the raw 12-bit facing + derived cardinal,
## set visibility) and registers it under `control_id` in the shared `_units_by_id`
## (the same dict handed to `_vm.units_by_id`), so later ops address it by that id.
## Unit._ready is synchronous, so no await is needed (unlike the pre-spawn awaits,
## which pace the ENTD batch). Placement is the operand tile; scenario 6 passes (0,0),
## a map corner off the tableau camera (ADD_GHOST_UNIT_OPCODE_47.md §4.5a). `elevation`
## (xEL) is carried for logging; cinematic_place derives height from the tile.
func _spawn_ghost_actor(control_id: int, sprite_set: int, psx_x: int, psx_y: int,
		elevation: int, facing_12bit: int, visible: bool) -> Node:
	var unit_scene: PackedScene = load(UNIT_SCENE_PATH)
	if unit_scene == null:
		push_error("[ScenarioPlayer] Add Ghost Unit: cannot load Unit.tscn")
		return null
	var unit = unit_scene.instantiate()
	unit.body_sprite_id = sprite_set
	unit.name = "Ghost_%02X" % control_id
	add_child(unit)  # Unit._ready runs synchronously → animation_set + playbacks exist
	if psx_x >= 0 and psx_y >= 0:
		ScenarioVMClass.cinematic_place(unit, psx_x, psx_y, _map_lattice())
	# Ghost actors are cutscene units (render the tent idle). scenario_set_facing sets
	# the orientation source of truth + derived cardinal + is_cinematic_unit atomically.
	unit.scenario_set_facing(facing_12bit)
	unit.visible = visible
	unit.scenario_present = true  # {47} adds the ghost to the scene → broadcast target
	_units_by_id[control_id] = unit
	print("[ScenarioPlayer] ghost ctrl=0x%02X sprite_set=0x%02X tile=(%d,%d) elev=%d facing_angle=0x%03X visible=%s" %
		[control_id, sprite_set, psx_x, psx_y, elevation, facing_12bit, str(visible)])
	return unit


func _unhandled_input(event: InputEvent) -> void:
	# F6 toggles the yellow per-unit facing gizmos (text label + arrow). They
	# start hidden (`show_facing_debug`); this flips every built gizmo's
	# visibility live so they can be summoned back for facing debugging.
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F6:
		show_facing_debug = not show_facing_debug  # setter repaints the gizmos
		get_viewport().set_input_as_handled()


## Show/hide every per-unit facing gizmo built by `_apply_debug_id_labels` /
## `_apply_facing_arrows` (nodes are kept alive so this is instant).
func _set_facing_debug_visible(vis: bool) -> void:
	for uid in _units_by_id.keys():
		var unit: Node3D = _units_by_id[uid]
		if unit == null:
			continue
		var label := unit.get_node_or_null("DebugIdLabel")
		if label != null:
			label.visible = vis
		var arrow := unit.get_node_or_null("DebugFacingArrow")
		if arrow != null:
			arrow.visible = vis
	print("[ScenarioPlayer] facing debug gizmos %s" % ("ON" if vis else "OFF"))


# Temporary debug labels above each spawned unit so we can talk about
# "the character with uid=0x0C" instead of guessing at names. Shows uid,
# sprite_set (the body SPR table the unit draws from in TYPE1 mode), the
# resolved cinematic palette_row, and the live facing direction (cardinal
# + 12-bit byte). The facing line refreshes on every rotation step via
# `facing_angle_changed` + cardinal flips so PSX-vs-Godot per-opcode
# alignment can be eyeballed against the running game. The label is
# parented to the unit so it follows the sprite around, billboards toward
# the camera, and ignores depth so it stays readable even when the unit
# is occluded. Removable later — node name "DebugIdLabel".
func _apply_debug_id_labels() -> void:
	for uid in _units_by_id.keys():
		var unit: Node3D = _units_by_id[uid]
		if unit == null:
			continue
		var sprite_set := 0
		if "body_sprite_id" in unit:
			sprite_set = int(unit.body_sprite_id)
		var palette_row: int = int(unit.body_palette_row) if "body_palette_row" in unit else 0
		var label := Label3D.new()
		label.name = "DebugIdLabel"
		label.visible = show_facing_debug  # hidden by default; F6 toggles
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 48
		label.outline_size = 12
		label.modulate = Color.YELLOW
		label.outline_modulate = Color.BLACK
		label.pixel_size = 0.003
		label.position = Vector3(0, 2.6, 0)
		unit.add_child(label)
		_refresh_debug_id_label(label, uid, sprite_set, palette_row, unit)
		# Update facing line on every rotation step (sub-cardinal precision)
		# AND on cardinal flips (covers units the scenario VM never rotates).
		var captured_label: Label3D = label
		var captured_uid: int = int(uid)
		var captured_sprite: int = sprite_set
		var captured_pal: int = palette_row
		var captured_unit: Node3D = unit
		unit.facing_angle_changed.connect(
			func(_a): _refresh_debug_id_label(captured_label, captured_uid,
				captured_sprite, captured_pal, captured_unit)
		)
		if unit.anim_state != null:
			unit.anim_state.facing_direction_changed.connect(
				func(_old, _new): _refresh_debug_id_label(captured_label, captured_uid,
					captured_sprite, captured_pal, captured_unit)
			)


func _refresh_debug_id_label(label: Label3D, uid: int, sprite_set: int,
		palette_row: int, unit: Node3D) -> void:
	# Three lines: identity / cinematic palette / live facing. The facing line
	# carries cardinal name + 12-bit angle + byte position (the rotation
	# consumer at FUN_8013f20c operates on the byte 0..F). When the unit has
	# never been scenario-rotated, falls back to the cardinal-derived angle.
	var face_str := "?"
	if unit.anim_state != null:
		var card_idx: int = int(unit.anim_state.current_facing)
		var ang := -1
		if "facing_angle" in unit and int(unit.facing_angle) >= 0:
			ang = int(unit.facing_angle) & 0xFFF
		else:
			# Combat-cardinal fallback (canonical). 0=N(0xC00) 1=E(0x000) 2=S(0x400) 3=W(0x800).
			var fallback := [0xC00, 0x000, 0x400, 0x800]
			ang = fallback[card_idx] if card_idx >= 0 and card_idx < fallback.size() else -1
		if ang >= 0:
			var byte_pos := (ang >> 8) & 0xF
			# Name from the RAW PSX wheel (the same one the yellow arrow uses),
			# NOT the E/S-swapped `current_facing` enum — see _RAW_WHEEL_NAMES.
			face_str = "%s 0x%03X b=%X" % [_RAW_WHEEL_NAMES[byte_pos], ang, byte_pos]
	label.text = "uid=0x%02X\nspr=0x%02X pal=%d\n%s" % [
		uid, sprite_set, palette_row, face_str]


## Yellow 3D arrow above each spawned unit, pointing in the unit's current
## facing. Unshaded + no_depth_test so it stays visible through sprites.
## Prefers the precise `unit.facing_angle` (12-bit, set by scenario_rotate
## and per-tick stepped by `Unit._tick_rotate`) when ≥ 0 — wired via
## `facing_angle_changed` so the arrow updates on every rotation step, not
## just on cardinal flips. Falls back to the cardinal-derived snap (matches
## the combat 4-way sprite render) when no precise angle is on file.
## The arrow points +X by default (= NORTH per the Godot world-coord
## convention in CLAUDE.md). Helper: `Unit.facing_angle_to_world_radians`
## maps the 12-bit angle onto the Godot Y-rotation, interpolating within
## the FFT 16-direction wheel's per-segment author-intent path.
func _apply_facing_arrows() -> void:
	for uid in _units_by_id.keys():
		var unit: Node3D = _units_by_id[uid]
		if unit == null:
			continue
		if not "anim_state" in unit or unit.anim_state == null:
			continue
		var arrow := _build_facing_arrow()
		arrow.name = "DebugFacingArrow"
		arrow.visible = show_facing_debug  # hidden by default; F6 toggles
		arrow.position = Vector3(0, 2.0, 0)
		unit.add_child(arrow)
		_update_facing_arrow_from_unit(arrow, unit)
		# Re-orient on per-step facing_angle changes (sub-cardinal precision)
		# AND on cardinal flips (which cover units that never rotate via the
		# scenario VM — they keep their ENTD-default cardinal facing).
		var captured := arrow
		var captured_unit := unit
		unit.facing_angle_changed.connect(
			func(_new_angle): _update_facing_arrow_from_unit(captured, captured_unit)
		)
		unit.anim_state.facing_direction_changed.connect(
			func(_old, _new_dir): _update_facing_arrow_from_unit(captured, captured_unit)
		)


## Screen-space compass in the top-right corner that tracks the live camera so
## world N/E/S/W stay legible while the isometric camera pans/rotates during the
## scenario (the per-unit yellow facing arrows are easy to misread against a
## tilted, rotating view). See `CompassOverlay`.
func _setup_compass() -> void:
	var cam := get_node_or_null("PlayerCamera/FocusPoint/Camera") as Camera3D
	if cam == null:
		push_warning("[ScenarioPlayer] no Camera under PlayerCamera; compass unwired")
		return
	var layer := CanvasLayer.new()
	layer.name = "CompassLayer"
	layer.layer = 50
	layer.visible = show_compass
	add_child(layer)
	_compass_layer = layer
	var compass := CompassOverlay.new()
	compass.name = "CompassOverlay"
	compass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(compass)
	compass.setup(cam)


func _update_facing_arrow_from_unit(arrow: Node3D, unit: Node3D) -> void:
	# Prefer the precise 12-bit angle when scenario_rotate has set it.
	if "facing_angle" in unit and int(unit.facing_angle) >= 0:
		arrow.rotation.y = Unit.facing_angle_to_world_radians(int(unit.facing_angle))
		return
	_update_facing_arrow(arrow, int(unit.anim_state.current_facing))


func _build_facing_arrow() -> Node3D:
	var root := Node3D.new()

	# psx-ot-depth-exempt: debug facing-arrow gizmo (no_depth_test overlay), not a battle-OT mesh.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true

	# CylinderMesh defaults to its length running along +Y; rotate -90° around
	# Z so the top moves to +X and the cylinder lies horizontal along +X.
	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.height = 0.40
	shaft_mesh.top_radius = 0.025
	shaft_mesh.bottom_radius = 0.025
	shaft.mesh = shaft_mesh
	shaft.material_override = mat
	shaft.rotation_degrees = Vector3(0, 0, -90)
	shaft.position = Vector3(0.20, 0, 0)
	root.add_child(shaft)

	# Cone for the arrowhead — same rotate so the pointy top lands at +X.
	var head := MeshInstance3D.new()
	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.0
	head_mesh.bottom_radius = 0.09
	head_mesh.height = 0.18
	head.mesh = head_mesh
	head.material_override = mat
	head.rotation_degrees = Vector3(0, 0, -90)
	head.position = Vector3(0.49, 0, 0)
	root.add_child(head)

	return root


func _update_facing_arrow(arrow: Node3D, facing: int) -> void:
	# Godot world: +X=NORTH, -X=SOUTH, +Z=EAST, -Z=WEST (CLAUDE.md).
	# Enum: NORTH=0 EAST=1 SOUTH=2 WEST=3 (FacingDirection).
	# Arrow built pointing +X, so a Y rotation of -90·facing lines it up.
	arrow.rotation_degrees = Vector3(0, -90.0 * float(facing), 0)


## Read the map's depth (`size_z`, tiles) from its terrain.json so the VM can
## apply the ADR-0052 chirality flip to in-chunk unit depth rows. The chunk JSON
## is committed raw (PSX-RAM-faithful); the VM mirrors each placement row about
## `size_z-1` to land on the 180°-rotated map. Returns 0 on failure (the VM
## treats 0 as "unset" → no flip + warning).
func _load_map_size_z(map_name: String) -> int:
	var path := "res://assets/maps/%s/terrain.json" % map_name
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[ScenarioPlayer] cannot open %s for size_z" % path)
		return 0
	var raw := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	# terrain.json wraps dims under a "terrain" key: {"terrain": {size_x, size_z, ...}}.
	var dims = parsed
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("terrain"):
		dims = parsed["terrain"]
	if typeof(dims) != TYPE_DICTIONARY or not dims.has("size_z"):
		push_error("[ScenarioPlayer] %s missing size_z" % path)
		return 0
	return int(dims["size_z"])


## Map width in tiles (`size_x`) for the {3C} Weather rain scatter box. Same
## terrain.json shape as `_load_map_size_z`; 0 if missing (Weather uses a default).
func _load_map_size_x(map_name: String) -> int:
	var path := "res://assets/maps/%s/terrain.json" % map_name
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[ScenarioPlayer] cannot open %s for size_x" % path)
		return 0
	var raw := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	var dims = parsed
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("terrain"):
		dims = parsed["terrain"]
	if typeof(dims) != TYPE_DICTIONARY or not dims.has("size_x"):
		push_error("[ScenarioPlayer] %s missing size_x" % path)
		return 0
	return int(dims["size_x"])


## One ENTD record, through the shared cached reader. This used to re-open and re-parse
## the whole ~1 MB table on every call; [EntdBattle.record] does it once per process, and
## the arena needs the same reader now that it composes from the ENTD too (ADR-0180).
func _load_entd_record(record_key: String) -> Variant:
	return EntdBattle.record(record_key)


# Parse the loaded chunk file and return its `instructions` array (empty on any
# read/parse failure). Spawn-time visibility (`_chunk_reveals_first`) and the
# EVTCHR-fallback scan (`_scan_referenced_unit_ids`) both run BEFORE the VM
# loads the chunk (see `_ready`: `_spawn_units` precedes `_vm.load_chunk_json`),
# so they read the file directly rather than `_vm.get_instructions()`.
func _load_chunk_instructions() -> Array:
	var f := FileAccess.open(_chunk_path, FileAccess.READ)
	if f == null:
		return []
	var raw := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if parsed == null:
		return []
	return parsed.get("instructions", [])


func _scan_referenced_unit_ids() -> Array:
	var ids: Array = []
	for inst in _load_chunk_instructions():
		var name := str(inst.get("name", ""))
		if name != "Warp Unit" and name != "Unit Anim":
			continue
		for p in inst.get("params", []):
			var pname := str(p.get("name", ""))
			if pname == "Unit" or pname == "Units":
				var v := int(p["value"])
				if not (v in ids):
					ids.append(v)
				break
	return ids


# Frame-0 visibility for `uid`, derived from the loaded chunk. Returns true
# (spawn HIDDEN) iff the unit's FIRST visibility-affecting opcode is a reveal-on-
# cue or held-on-load; false (spawn VISIBLE) otherwise. This replaces the old
# `unit.visible = always_present` — a formation RNG-cull flag, NOT the render
# flag (see research/working_documents/SCENARIO6_UNIT_REVEAL_VISIBILITY.md §4.2).
#
# The PSX `+0xa` show flag is code-initialised at EVTCHR-load in
# `evtchr_unit_clut_writer` @0x80087bb8 (show) / @0x80087bc4 (hide), gated on the
# held flag `s5`; the chunk's first `{45} Add Draw=1` / `{44} Draw` is the on-disk
# encoding of `s5` (§4.3). The rule:
#   {44} Draw Unit          -> reveal on cue  => HIDDEN (true)
#   {45} Add Unit Draw==1   -> held on load   => HIDDEN (true)
#   {46} Erase Unit         -> was on-screen  => VISIBLE (false)
#   {45} Add Unit Draw==0   -> draw now       => VISIBLE (false)
#   (no visibility opcode)                    => VISIBLE (false)
# Only the FIRST matching op counts: Agrias' `Erase@71` wins over her later
# `Draw@259`, so she starts visible — the case that kills every ENTD-flag theory.
#
# Pure function of (uid, instructions) — no scene/VM/file-IO — so the visibility
# model is guarded without standing up the scene (ScenarioUnitVisibilityTest).
static func _chunk_reveals_first(uid: int, instructions: Array) -> bool:
	for inst in instructions:
		var opcode := int(inst.get("opcode", -1))
		# {44} Draw Unit / {45} Add Unit / {46} Erase Unit — the visibility ops.
		# Match by opcode so "Add Unit Start/End" and "Wait Add Unit" (distinct
		# opcodes that share the name prefix) are not mistaken for {45}.
		if opcode != 0x44 and opcode != 0x45 and opcode != 0x46:
			continue
		var a := EventInstructionSet.args(inst)
		if a.raw("Unit") != uid:
			continue
		if opcode == 0x46:
			return false   # Erase -> already on-screen -> visible
		if opcode == 0x44:
			return true    # Draw -> revealed on cue -> starts hidden
		return a.raw("Draw", 1) == 1   # Add: Draw=1 held/hidden, Draw=0 draw-now
	return false


## Frame-0 render visibility: a unit is drawn at load iff it is PRESENT — allocated
## in the PSX sprite list (an `always_present` ENTD slot at load, or introduced by a
## runtime {45} Add / {44} Draw) — AND its first visibility opcode doesn't hold it
## hidden (`_chunk_reveals_first`). Presence is the master gate: a not-yet-present
## unit has no sprite object, so there is nothing to show, even when its lone
## {45} Add Draw=0 nominally "draws now" — that reveal only takes effect WHEN the Add
## fires (ScenarioApply.add_unit), not statically at frame 0. This is scn6 uid 1/4 at
## (0,4)/(0,3): `always_present`=false, added by {45} Add Draw=0 at pc434 with the
## camera panned away (next-scene setup) — they must NOT render for all of scenario 6.
## Same presence signal the broadcast roster keys on (ScenarioWorld._unit_roster).
## Pure (uid, present, instructions) → guarded by ScenarioUnitVisibilityTest.
static func _frame0_visible(present: bool, uid: int, instructions: Array) -> bool:
	return present and not _chunk_reveals_first(uid, instructions)


# Set every spawned unit's frame-0 visibility from `instructions` (a loaded
# chunk's opcode list), via `_chunk_reveals_first`. Called after each chunk load
# so visibility follows the chunk ACTUALLY playing — the group model spawns the
# ENTD roster once at the root and reuses it across members, so a member-only
# reveal must be (re)applied when that member loads. The real game establishes
# `+0xa` per event at unit-load; this mirrors that within the spawn-once model.
func _apply_initial_visibility(instructions: Array) -> void:
	for uid in _units_by_id:
		var u = _units_by_id[uid]
		if not is_instance_valid(u):
			continue
		# EVTCHR-fallback placeholders (uids referenced by the chunk but absent
		# from ENTD) are spawned hidden and revealed by their own Warp+Draw — leave
		# their visibility alone rather than flip a no-vis-op placeholder visible.
		if u.has_meta("scenario_fallback"):
			continue
		# Gate on PRESENCE, same as the spawn site: a unit not yet allocated in the
		# scene (scn6 uid 1/4, whose {45} Add is at pc434 — still un-dispatched when a
		# member chunk (re)loads) must NOT be revealed here just because its lone
		# Add Draw=0 reads "draw now" in the static scan. Its {45} Add reveals it live
		# (ScenarioApply.add_unit) once dispatch reaches it. A node lacking the flag
		# (defensive) is treated as present so this never wrongly hides it.
		var present: bool = (not ("scenario_present" in u)) or u.scenario_present
		u.visible = _frame0_visible(present, int(uid), instructions)


## The map's lattice, or null before the map builds one. ONE untyped step at the seam
## (ADR-0192 dec. 3): `_map` is the `$ProceduralMap` node, which infers `Node`, and
## criterion 1 forbids publishing `MapComposer`, so this handle can never carry a type.
func _map_lattice() -> Lattice:
	if _map == null or not ("lattice" in _map):
		return null
	var lat: Lattice = _map.lattice
	return lat
