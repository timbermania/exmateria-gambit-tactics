extends Node3D
## EffectViewerScene - Lightweight scene for previewing spell effects.
## Spawns two units on a small map and provides a debug panel to select
## and play any of the 510 effects (E001-E510) on demand, with optional looping.

## ADR-0212 dec. 1 — `addons/exmateria_platform` publishes one global,
## `ExMateriaPlatform`; aliasing a member back keeps every use site below
## spelled the way it was (ADR-0211 dec. 4). The PSX trio arrived at
## extraction #7 (#1220) and lost its three bare `class_name`s on the way.
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude
const CameraCalibration = ExMateriaPlatform.CameraCalibration
const PsxChirality = ExMateriaPlatform.PsxChirality


# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const DisplayActivity = ExMateriaSpriteRig.DisplayActivity

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const CursorRig = ExMateriaBattlefield.CursorRig

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const ReactionType = ExMateriaAlmanac.ReactionType


const EffectInstanceClass = ExMateriaEffects.EffectInstance
const EffectStudioPageClass = preload("res://src/effects/studio/EffectStudioPage.gd")
const EffectEditSessionClass = preload("res://src/effects/studio/EffectEditSession.gd")
const EffectScreenSaverClass = preload("res://src/effects/studio/EffectScreenSaver.gd")
const EffectTextureSaverClass = preload("res://src/effects/studio/EffectTextureSaver.gd")
const TextureTgaClass = preload("res://src/effects/studio/TextureTga.gd")
const EffectCameraSaverClass = preload("res://src/effects/studio/EffectCameraSaver.gd")
const EffectSoundSaverClass = preload("res://src/effects/studio/EffectSoundSaver.gd")
const EffectPaletteSaverClass = preload("res://src/effects/studio/EffectPaletteSaver.gd")
const EffectEmitterSaverClass = preload("res://src/effects/studio/EffectEmitterSaver.gd")
const EffectParticleTimelineSaverClass = preload("res://src/effects/studio/EffectParticleTimelineSaver.gd")
const EffectTimelineHeaderSaverClass = preload("res://src/effects/studio/EffectTimelineHeaderSaver.gd")
const EffectFlagsSaverClass = preload("res://src/effects/studio/EffectFlagsSaver.gd")
const EffectTimeScaleSaverClass = preload("res://src/effects/studio/EffectTimeScaleSaver.gd")
const EffectScriptSaverClass = preload("res://src/effects/studio/EffectScriptSaver.gd")
const ColourKeyframeSessionClass = preload("res://src/effects/studio/ColourKeyframeSession.gd")
const ColourKeyframeSaverClass = preload("res://src/effects/studio/ColourKeyframeSaver.gd")
const BlendTargetSolverClass = preload("res://src/effects/studio/BlendTargetSolver.gd")
const PaletteTintSolverClass = preload("res://src/effects/studio/PaletteTintSolver.gd")

@onready var map: Node3D = $ProceduralMap
# The cursor NODE, by path — a scene-tree coupling, not a type reference (ADR-0196
# dec. 2). The published port is `cursor_rig` (ADR-0206).
@onready var tile_cursor: Node3D = get_node_or_null("TileCursor")

var _caster: Unit
var _target: Unit
var _current_effect: Node = null
var _panel: EffectViewerPanel
var _unit_panel: UnitControlPanel
var _looping: bool = false
var _polling: bool = false
var _last_effect_id: int = -1
# Effect Studio Solo/Mute selection — the whole EffectScoreModel.resolve_audibility result.
# Held on the host so a re-spawn (select, loop restart) re-applies it to the fresh instance.
# Written by studio_set_audibility.
var _studio_audibility: Dictionary = {}
var _effect_to_ability: Dictionary = {}  # effect_id (int) -> ability_id (int)
var _caster_casting: bool = false
var _react_enabled: bool = true
var _camera_enabled: bool = true
var cursor_rig: CursorRig = null
var _studio_page: Control = null  # Effect Studio (F3 dashboard page; ADR-0069)
var _studio_parked: bool = false  # the current instance was spawned parked by the Studio
# #255 authoring choke point (host side): the mutation session over the CURRENT instance's
# EffectData. Rebound whenever a fresh instance is spawned (its effect_data changes).
var _edit_session = null
var _edit_session_data = null
# ADR-0089 Drag preview: set true when a live drag deferred a sim-invalidating edit's rescrub;
# studio_commit_refold folds once on release and clears it. False for read-live colour drags.
var _deferred_refold_pending: bool = false
# ADR-0089 colour-keyframe authoring (host side): per-emitter edit sessions over the CURRENT
# instance's EffectData (keyed by emitter index), and a flag so studio_save also writes the
# game-JSON colour half. Rebound when the instance's effect_data changes.
var _colour_sessions: Dictionary = {}
var _colour_sessions_data = null
var _colour_authored: bool = false
var _studio_free_cam: bool = false  # "free camera" debug toggle: scene keeps the camera while the effect plays

const DEFAULT_CASTER_POS := Vector2i(4, 6)
const DEFAULT_TARGET_POS := Vector2i(7, 6)

# Unit positions PERSIST across reloads via AUTOSAVE Tune slugs (ADR-0068): the scene
# OWNS them here (declares the code default + AUTOSAVE mode at the read use-site) and
# UnitControlPanel is the VIEW that edits them. `Tune.of` coalesces any auto-saved
# override over the default, so a position the user dialed last run comes back at spawn
# with no Pin. UnitControlPanel binds the SAME slugs ("effect_viewer.<prefix>_<axis>").
const CASTER_X_SLUG := "effect_viewer.caster_x"
const CASTER_Z_SLUG := "effect_viewer.caster_z"
const TARGET_X_SLUG := "effect_viewer.target_x"
const TARGET_Z_SLUG := "effect_viewer.target_z"

# The caster/target sprite is deliberate test-setup state, so it PERSISTS across reloads
# the same way positions do (ADR-0068 AUTOSAVE): the scene owns the slugs here (default +
# AUTOSAVE) and applies them to body_sprite_id at spawn; UnitControlPanel is the VIEW.
const DEFAULT_CASTER_SPRITE := 0x01  # Ramza (RAMUZA.SPR)
const DEFAULT_TARGET_SPRITE := 0x80
const CASTER_SPRITE_SLUG := "effect_viewer.caster_sprite"
const TARGET_SPRITE_SLUG := "effect_viewer.target_sprite"
const _SPRITE_HINT := {"min": 0, "max": 0xFF, "step": 1}


## Register the effect-viewer setup slugs at scene boot (ADR-0068 R5), so the one-shot
## _ready reads pull them via Tune.get_value and UnitControlPanel is a pure VIEW (decision
## 12). AUTOSAVE: an edit persists across reloads like the positions/sprites it drives.
## Public so a test that clears the registry via Tune.reset() can re-establish the binds.
func register_tunables() -> void:
	Tune.bind(CASTER_X_SLUG, DEFAULT_CASTER_POS.x, {}, Tune.Persist.AUTOSAVE)
	Tune.bind(CASTER_Z_SLUG, DEFAULT_CASTER_POS.y, {}, Tune.Persist.AUTOSAVE)
	Tune.bind(TARGET_X_SLUG, DEFAULT_TARGET_POS.x, {}, Tune.Persist.AUTOSAVE)
	Tune.bind(TARGET_Z_SLUG, DEFAULT_TARGET_POS.y, {}, Tune.Persist.AUTOSAVE)
	Tune.bind(CASTER_SPRITE_SLUG, DEFAULT_CASTER_SPRITE, _SPRITE_HINT, Tune.Persist.AUTOSAVE)
	Tune.bind(TARGET_SPRITE_SLUG, DEFAULT_TARGET_SPRITE, _SPRITE_HINT, Tune.Persist.AUTOSAVE)


func _caster_pos() -> Vector2i:
	return Vector2i(
		int(Tune.get_value(CASTER_X_SLUG)),
		int(Tune.get_value(CASTER_Z_SLUG)))


func _target_pos() -> Vector2i:
	return Vector2i(
		int(Tune.get_value(TARGET_X_SLUG)),
		int(Tune.get_value(TARGET_Z_SLUG)))


func _exit_tree() -> void:
	# Restore background music for whatever scene comes next — the studio's silence
	# is scene-local (see the set_suppressed(true) in _ready).
	MusicPlayer.set_suppressed(false)


func _ready() -> void:
	register_tunables()
	# The previewer auditions effect SFX only — silence scenario/map background music
	# for the lifetime of this scene, so a boot apply_scenario (or an F3 scenario
	# switch) never starts a battle track over the effect being authored. Lowered on
	# exit (_exit_tree). Effect SFX runs on a separate SPU and is unaffected.
	MusicPlayer.set_suppressed(true)
	# Wait for map to build its default
	await get_tree().process_frame
	await get_tree().process_frame

	# Build ability lookup before anything else
	_build_effect_ability_map()

	# A scenario picked in the F3 panel persists in DebugConfig (AUTOSAVE slug
	# scenario.active_id); re-apply it on open so the previewer boots into the same
	# map/lighting/music the user left it in — mirroring GPUArena's boot apply. With
	# nothing picked (-1), fall back to the MAP042 previewer default below.
	# #589: hand the map's two outputs to the host systems that consume them.
	# Replay-then-connect, so a map the composer auto-built in ITS `_ready`
	# (children ready before parents) is covered by the replay and every later
	# `change_map` by the connect. See BattlefieldWiring.
	BattlefieldWiring.wire_map(map)
	if DebugConfig.active_scenario_id >= 0:
		ScenarioLoader.apply_scenario(DebugConfig.active_scenario_id, map)
	else:
		# Preview effects on MAP042 (matches GPUArena terrain), but pick the weather
		# state explicitly: with no scenario to supply one, the selector defaults to
		# MAP042's clear-day state 0 — a 6.46x directional-light key gain (top of the
		# 119-map light-gain tail; median ~2x), which the map lighting model bleaches
		# to white. MAP042 has no canonical battle context, so weather_raw=1 (1.87x,
		# nearest the tuned median) is a deliberate cosmetic pick for the previewer.
		map.change_map("MAP042", 1)

	# Wait for map to finish loading
	await get_tree().process_frame

	# Spawn units
	await _spawn_units()

	# Connect map_loaded for map changes via ScenarioDebugPanel
	map.map_loaded.connect(_on_map_loaded)

	# Seed the on-grid tile cursor so the camera moves/rotates like a normal
	# scene (WASD walks the cursor, Q/E rotate) — see GPUArena.gd for the model.
	_setup_tile_cursor()

	# Rotate camera 180° (like pressing E twice) so caster is visible
	var cam = get_node_or_null("PlayerCamera")
	if cam:
		cam.y_target_rot = 135.0
		cam.rotation_settled = false

	# Slice D (#221): the particle producers' in-scene linear mode-shader path is retired — their
	# transparent prims fold through the display-space compositor. #228 Phase 3: the raw-RD GLSL
	# driver was retired; that fold is now owned by the CompositorAutopilot autoload (fork + Forward+),
	# which auto-attaches EngineFoldCompositor to the active camera for every scene — so the
	# previewer/Studio needs no per-scene compositor wiring (it shows the faithful display-space fold).

	# Hide the combat roster bars. The previewer has no roster to populate, so
	# CombatUI's empty 4+4 unit slots just clutter the frame the effect renders in.
	_hide_combat_roster(cam)

	# Set up debug panel
	_setup_debug_panel()

	# The Effect Studio lives as a full-width page in the F3 dashboard window
	# (ADR-0069 hosted per ADR-0035). It supersedes the old bottom-strip timeline:
	# the effect renders here in the MAIN window, unobstructed, while the Studio
	# controls (timeline/inspector/curve painter/transport) live in the dashboard.
	_setup_studio_page()


func _setup_studio_page() -> void:
	"""Build the Studio page, bind it to this scene, and inject it into the
	dashboard's full-width Studio page slot. The page drives our live preview
	instance via the studio_* methods below."""
	_studio_page = EffectStudioPageClass.new()
	_studio_page.bind_host(self)
	DebugOverlay.set_studio_page(_studio_page)
	# Open the dashboard straight to the Studio page.
	DebugOverlay.show_studio_page()


func _hide_combat_roster(cam: Node) -> void:
	"""Hide the friendly/enemy roster bars in the shared CombatUI. They live at
	CombatUI/BaseLayer/{Friendly,Enemy}Roster (see CombatUI.tscn). In the effect
	previewer they're never populated with units, so the empty slots only get in
	the way — hide the two roster nodes specifically, leaving the rest of BaseLayer
	(vitals, popups) intact."""
	if cam == null:
		return
	var combat_ui = cam.get_node_or_null("FocusPoint/Camera/CombatUI")
	if combat_ui == null:
		return
	for roster_path in ["BaseLayer/FriendlyRoster", "BaseLayer/EnemyRoster"]:
		var roster = combat_ui.get_node_or_null(roster_path)
		if roster:
			roster.visible = false


func _setup_tile_cursor() -> void:
	"""Seed the on-grid cursor so the camera moves/rotates like a normal scene:
	WASD walks the cursor (scrolling the camera via the deadzone), Q/E rotate, and
	the tile-under-cursor wears the CURSOR_ACTIVE highlight. All the wiring lives in
	CursorRig; here we only own build/seed timing. Re-callable on map change."""
	if tile_cursor == null:
		return
	if cursor_rig == null:
		cursor_rig = CursorRig.bind(self, tile_cursor, get_node_or_null("PlayerCamera"))
		# #589: the cursor's player-driven step is an `Audio` cue, and the cue name
		# is host vocabulary (`OpeningMenu` plays the same one). Wired by the root
		# that OWNS the node -- a cursor handed onward (FormationMapHost.bind_map)
		# is already wired by its owner.
		BattlefieldWiring.wire_cursor(cursor_rig)
	cursor_rig.seed_from_map(map, _caster_pos())


func _spawn_units() -> void:
	var unit_scene = load("res://assets/scenes/Unit.tscn")

	# Caster - sprite 0x01 (Ramza, RAMUZA.SPR). The ROM-faithful sprite map
	# (sprite_files.json) starts at 0x01; 0x00 doesn't resolve to a texture.
	_caster = unit_scene.instantiate()
	_caster.name = "Caster"
	add_child(_caster)
	await get_tree().process_frame

	_caster.body_sprite_id = int(Tune.get_value(CASTER_SPRITE_SLUG))
	_relocate_unit(_caster, _caster_pos())
	# Load a default weapon so ATTACKING animation shows a visible sword
	_caster.update_weapon_sprite(19)  # Broad Sword (item_type_id=3)

	# Target - sprite 0x80, 3 tiles apart
	_target = unit_scene.instantiate()
	_target.name = "Target"
	add_child(_target)
	await get_tree().process_frame

	_target.body_sprite_id = int(Tune.get_value(TARGET_SPRITE_SLUG))
	_relocate_unit(_target, _target_pos())

	# Face toward each other
	_caster.face_toward_unit(_target)
	_target.face_toward_unit(_caster)


func _setup_debug_panel() -> void:
	# The map's Skirts + Map Render panels. Mounted host-side (#555) — `MapComposer`
	# used to construct and register them itself, which is an ADR-0068 R1 violation:
	# the production owner of the tunables also instantiated their view. Placed here,
	# after the map is composed, so the pure-VIEW rows resolve their owners' defaults.
	MapDebugPanels.register_map_panels(map)

	# Workflow-split panels (replaced GeneralDebugPanel — see ADR-0035).
	var scenario_panel = ScenarioDebugPanel.new()
	scenario_panel.setup(map)
	DebugOverlay.register_panel(scenario_panel, DebugOverlay.Category.SCENARIO, "scenario")

	var simulation_panel = SimulationDebugPanel.new()
	simulation_panel.setup()
	DebugOverlay.register_panel(simulation_panel, DebugOverlay.Category.SIMULATION, "simulation")

	var ui_display_panel = UIDisplayDebugPanel.new()
	ui_display_panel.setup()
	DebugOverlay.register_panel(ui_display_panel, DebugOverlay.Category.DISPLAY, "ui_display")

	# AUDIO tab — whole-game volume slider (68ced39d3) + SPU tunables. Registered here so the
	# Effect Studio's F3 overlay exposes it too (it was only in ScenarioPlayerScene before).
	AudioHostAdapter.register_audio_tab()

	var units_func = func(): return [_caster, _target].filter(func(u): return is_instance_valid(u))
	var unit_shader_panel = UnitShaderDebugPanel.new()
	unit_shader_panel.setup(self, units_func)
	DebugOverlay.register_panel(unit_shader_panel, DebugOverlay.Category.SHADERS, "unit_shader")


	# Unit control panel
	_unit_panel = UnitControlPanel.new()
	_unit_panel.setup(_caster, _target, map)
	DebugOverlay.register_panel(_unit_panel, DebugOverlay.Category.UNIT)

	# Effects tab panel
	_panel = EffectViewerPanel.new()
	_panel.setup()
	_panel.play_requested.connect(play_effect)
	_panel.stop_requested.connect(stop_effect)
	_panel.loop_toggled.connect(set_looping)
	_panel.react_toggled.connect(set_react_enabled)
	_panel.camera_toggled.connect(set_camera_enabled)
	_panel.emitter_toggled.connect(_on_emitter_toggled)
	DebugOverlay.register_panel(_panel, DebugOverlay.Category.EFFECTS)

	# Apply-on-boot (ADR-0068): drive the scene from the panel's persisted Animate/Camera
	# prefs (AUTOSAVE) now that the toggle signals are wired, so a remembered choice takes
	# effect on the first frame. The effect selection is restored by the panel itself
	# (add_dropdown + resync, default E065) — no hardcoded pick needed here.
	set_react_enabled(_panel.get_react_enabled())
	set_camera_enabled(_panel.get_camera_enabled())

## Studio host interface — render-layer compare toggle (#7916): flip the always-on autopilot between
## the display-space fold (correct) and native in-scene blend (the muddy "wrong" side) so both can be
## captured from the Effect Studio. Called by EffectStudioPage's render-layer button.
func studio_set_native_blend(enabled: bool) -> void:
	var ap := get_node_or_null("/root/CompositorAutopilot")
	if ap != null and ap.has_method("set_native_blend"):
		ap.set_native_blend(enabled)
	else:
		push_warning("[effect-viewer] no CompositorAutopilot — native-blend toggle inert (stock build?)")


func play_effect(effect_id: int, parked: bool = false) -> void:
	# `parked` = the Studio owns the clock (spawn paused at frame 0). Panel-driven
	# plays (the play_requested signal, one arg) free-run as before.
	_studio_parked = parked
	_last_effect_id = effect_id

	# Stop any current effect
	_stop_current_effect()

	var effect_id_str = "E%03d" % effect_id
	var effect_path = "res://assets/effects/%s" % effect_id_str

	var effect = EffectInstanceClass.new()
	get_viewport().add_child(effect)

	# Set _current_effect early so signal handlers can access it
	_current_effect = effect

	# Connect camera signals BEFORE initialize (camera_started emits during init)
	effect.camera_started.connect(_on_effect_camera_started)
	effect.camera_finished.connect(_on_effect_camera_finished)

	var caster_pos = _caster.global_position
	var target_pos = _target.global_position

	# Set map center for CAMERA anchor before initialize (anchor is set during init)
	if map and map.dynamic_geo_builder:
		var bounds: Rect2i = map.dynamic_geo_builder.map_bounds
		effect.map_center_godot = Vector3(float(bounds.size.x) / 2.0, 0.0, float(bounds.size.y) / 2.0)

	var success = effect.initialize(
		effect_id_str,
		effect_path,
		caster_pos,
		512
	)

	if not success:
		effect.queue_free()
		_current_effect = null
		_panel.update_status("Failed to load %s" % effect_id_str)
		return

	effect.global_position = caster_pos
	var target_offset = target_pos - caster_pos

	effect.set_anchors(
		target_offset,   # world
		target_offset,   # cursor
		Vector3.ZERO,    # origin
		target_offset    # target
	)

	effect.set_unit_targets(_caster, _target)
	effect.attach_anchors_to_units(_caster, _target)
	effect.auto_loop = false

	# Connect reaction signals
	effect.ability_react_triggered.connect(_on_ability_react)
	effect.refresh_tile_triggered.connect(_on_refresh_tile)

	# Set up caster animation
	if _react_enabled:
		var ability_id = _effect_to_ability.get(effect_id, -1)
		if ability_id >= 0:
			_caster.active_ability_id = ability_id
		_caster.set_distort_context(_caster.global_position, _target.global_position)
		# Weapon abilities (effect_anim_id == 0) swing weapon; spells use casting pose
		var cast_state = DisplayActivity.Activity.SPELL_CASTING
		if ability_id >= 0:
			var ability := AbilityDatabase.get_ability_view(ability_id)
			var effect_anim = ability.effect_anim_id if ability.has("effect_anim_id") else -1
			if effect_anim == 0:
				cast_state = DisplayActivity.Activity.ATTACKING
		_caster.activity = cast_state
		_caster_casting = true

	# Populate emitter checkboxes and re-apply disabled state
	_panel.populate_emitters(effect, effect_id)
	effect.set_debug_emitter_filter(_panel.get_disabled_emitters())

	_panel.update_status("Playing %s" % effect_id_str)

	# If the Studio spawned this instance, keep it PARKED at frame 0 (the Studio
	# owns the clock via seek/transport) instead of free-running + completion-polling.
	if _studio_parked:
		# Fresh instance starts fully audible; the page (EffectStudioPage._load_effect)
		# re-resolves and pushes the current Solo/Mute selection immediately after this
		# spawn returns, so DON'T apply the stale held selection here — its lane ids /
		# emitter indices belong to the PREVIOUS effect and would fold twice. (Studio
		# loop-restart re-seeks this same instance; it never re-spawns.)
		effect.set_paused(true)
		effect.seek(0)
		return

	# Start polling for completion
	_poll_effect_completion(effect)


# --- Effect Studio host interface (driven by EffectStudioPage) -------------

## Camera ownership in the Studio is a PURE FUNCTION OF THE PLAYHEAD: frame 0 →
## the scene (tile cursor) owns the camera; frame ≠ 0 → the editor (effect) owns
## it. That single rule is the whole model — pressing Play (frame leaves 0),
## scrubbing to a frame, the natural-end freeze (playhead holds at the last
## frame), and Stop (= seek to 0) are all just "the frame moved," and this
## reconciles the owner from it. `acquire` is the host's _acquire_effect_camera
## (idempotent: no-ops when the camera is disabled, the effect has no camera
## controller, or we're already in takeover). Static + camera-injected so the
## invariant is unit-testable against a real PlayerCamera without standing up the
## whole viewer scene (see EffectStudioCameraOwnershipTest).
##
## `free_cam` is a SECOND input to ownership: the "free camera" debug toggle. When
## on, the scene owns the camera at EVERY playhead (treated exactly like frame 0),
## so the user can fly the tile-cursor camera while the effect keeps playing. The
## owner is the scene when `free_cam OR frame <= 0`; only a playing effect with
## free-cam off (frame > 0) takes over.
static func reconcile_studio_camera(cam, frame: int, acquire: Callable, free_cam: bool = false) -> void:
	if cam == null:
		return
	if free_cam or frame <= 0:
		if cam.camera_mode == cam.CameraMode.TAKEOVER:
			cam.release_takeover()
	else:
		acquire.call()


func studio_select_effect(effect_id: int) -> void:
	"""Spawn the effect PARKED at frame 0 for the Studio (reuses play_effect's
	unit-anchored setup + real framing, but the Studio owns the clock)."""
	play_effect(effect_id, true)


func studio_save() -> Dictionary:
	"""Lower the live edited effect back to a byte-patched E###.BIN on disk
	(game→json→bin). Serializes the CURRENT (edited) models — the choke point mutates
	_current_effect.effect_data in place — and hands them to the byte-exact writers.
	Each bridged section patches independently and is layered into ONE file: the screen
	writer patches the pristine ROM extract, the camera writer LAYERS its patch onto that
	output BIN, and the sound saver (ADR-0085 slice 4: triggers + containers + FEDS bytes
	in one pass) layers onto that too. Neither channel depends on the other — an effect
	with camera data but NO screen section still saves its camera edits (the camera writer
	patches the pristine extract directly), per ADR-0086. Returns {ok, out_path, error};
	never raises."""
	if _current_effect == null or not is_instance_valid(_current_effect) \
			or _current_effect.effect_data == null:
		return {"ok": false, "out_path": "", "error": "no live effect to save"}
	var data = _current_effect.effect_data
	# ADR-0085 sound seams (TIER-1 triggers / TIER-2 containers / TIER-3 FEDS bytes):
	# present when any of the three sound halves carries data.
	var has_sound_sections: bool = (data.sound is Dictionary and not data.sound.is_empty()) \
			or (data.sound_containers is Dictionary and not data.sound_containers.is_empty()) \
			or data.feds_bank != null
	if data.screen == null and data.camera == null and data.palette == null \
			and data.emitters.is_empty() and data.timeline == null and data.flags.is_empty() \
			and data.time_scale.is_empty() and not has_sound_sections:
		return {"ok": false, "out_path": "", "error": "effect has no bridged section to save"}

	# Layer the present sections in a fixed order (screen → camera → palette), each patching the
	# PREVIOUS writer's output BIN so every channel's edits land in one file (ADR-0087). The
	# sections don't overlap; an absent one leaves the running base untouched. `base_override`
	# empty means "patch the pristine extract" — where the first present section starts.
	var base_override := ""
	var last_res := {}
	if data.screen != null:
		last_res = EffectScreenSaverClass.save(_last_effect_id, data.screen)
		if not last_res.get("ok", false):
			return last_res
		base_override = last_res.get("out_path", "")
	if data.camera != null:
		last_res = EffectCameraSaverClass.save(_last_effect_id, data.camera, base_override)
		if not last_res.get("ok", false):
			return last_res
		base_override = last_res.get("out_path", "")
	if data.palette != null:
		last_res = EffectPaletteSaverClass.save(_last_effect_id, data.palette, base_override)
		if not last_res.get("ok", false):
			return last_res
		base_override = last_res.get("out_path", "")
	if not data.emitters.is_empty():
		last_res = EffectEmitterSaverClass.save(_last_effect_id, data, base_override)
		if not last_res.get("ok", false):
			return last_res
		base_override = last_res.get("out_path", "")
	if data.timeline != null:
		last_res = EffectParticleTimelineSaverClass.save(_last_effect_id, data.timeline, base_override)
		if not last_res.get("ok", false):
			return last_res
		base_override = last_res.get("out_path", "")
		# The three GLOBAL phase durations (#271) — disjoint header words, layered onto the
		# particle-timeline patch of the SAME section so both land in one file.
		last_res = EffectTimelineHeaderSaverClass.save(_last_effect_id, data.timeline, base_override)
		if not last_res.get("ok", false):
			return last_res
		base_override = last_res.get("out_path", "")
	# The GLOBAL flags byte (#272) — disjoint from everything above (it lives at
	# effect_flags_ptr, not the timeline section), layered onto the running base so the
	# flags edit lands in the same file. Present in every effect, so it always re-serializes
	# (byte-identical when unedited); a flags-only effect still saves through this path.
	if not data.flags.is_empty():
		last_res = EffectFlagsSaverClass.save(_last_effect_id, data.flags, base_override)
		if not last_res.get("ok", false):
			return last_res
		base_override = last_res.get("out_path", "")
	# The two PACING curves (#270, ADR-0093) — the time_scale region is disjoint from every
	# section above (it sits between the anim table and the effect_flags byte), layered onto the
	# running base so a curve edit lands in the same file. Conditional: only effects that carry a
	# time_scale section save through this path (time_scale_ptr can be 0).
	if not data.time_scale.is_empty():
		last_res = EffectTimeScaleSaverClass.save(_last_effect_id, data.time_scale, base_override)
		if not last_res.get("ok", false):
			return last_res
		base_override = last_res.get("out_path", "")
	# Layer the three sound seams (TIER-1 triggers / TIER-2 containers / TIER-3 FEDS
	# bytes, ADR-0085 slice 4) onto the chain. A soundless effect has nothing to layer
	# and keeps the running base.
	if has_sound_sections:
		last_res = EffectSoundSaverClass.save(_last_effect_id, data, base_override)
		if not last_res.get("ok", false):
			return last_res
		base_override = last_res.get("out_path", "")
	# ADR-0089 colour-keyframe authoring: the game-JSON half (forked curves.json + repointed
	# emitters.json). Independent of the BIN writers above (the byte-exact BIN pack is deferred to
	# #292), so it runs whenever colour was authored and reports its own out_path.
	# The SCRIPT PATTERN (#273, ADR-0094) — the ONLY variable-length rewrite, so it runs LAST:
	# it regenerates the canonical section and shifts the whole tail, carrying every fixed-offset
	# patch above along with it (the writer no-ops a non-swappable / unchanged script, so this
	# re-serializes byte-identically when unedited). A Custom/CODE script is skipped (not an error).
	if not data.script_ops.is_empty():
		var script_res: Dictionary = EffectScriptSaverClass.save(_last_effect_id, data.script_ops, base_override)
		if script_res.get("ok", false):
			last_res = script_res
			base_override = script_res.get("out_path", "")
		elif not String(script_res.get("error", "")).contains("not swappable") \
				and not String(script_res.get("error", "")).contains("Custom"):
			return script_res
	# The TEXTURE sheet (#280, ADR-0199) — the file's LAST section, so it runs after the
	# script swap that shifts the tail. The writer re-derives the header from whatever base
	# it is handed, so it always splices at the post-shift texture_ptr. Nothing was imported
	# → the saver reports a no-op and the running base is untouched.
	if not data.authored_texture_tga.is_empty():
		last_res = EffectTextureSaverClass.save(_last_effect_id, data.authored_texture_tga, base_override)
		if not last_res.get("ok", false):
			return last_res
		if not last_res.get("no_edit", false):
			base_override = last_res.get("out_path", "")
	if _colour_authored:
		var col_res: Dictionary = ColourKeyframeSaverClass.save(_last_effect_id, data)
		if not col_res.get("ok", false):
			return col_res
		last_res = col_res
	return last_res


func studio_export_texture(path: String) -> Dictionary:
	"""#280: write the live sheet out as a 32-bit RGBA .tga for an author to paint
	(ADR-0199 dec. 6). Exports what is on screen, so an already-imported sheet
	round-trips rather than reverting to the ROM's.

	Returns `{ok, error}` so the page can SHOW the verdict. A round trip that reports
	nothing is indistinguishable from one that silently did nothing — the failure mode
	that hid this whole path's breakage from the author."""
	if not (_current_effect and is_instance_valid(_current_effect)) or _current_effect.effect_data == null:
		return {"ok": false, "error": "no live effect to export"}
	var res: Dictionary = EffectTextureSaverClass.export_tga(
		_last_effect_id, _current_effect.effect_data.texture, path)
	if not res.get("ok", false):
		push_warning("texture export failed: %s" % res.get("error", ""))
	return {"ok": bool(res.get("ok", false)), "error": str(res.get("error", ""))}


func studio_import_texture(path: String) -> Dictionary:
	"""#280: replace the live sheet from a repainted RGBA .tga (ADR-0199).

	The preview swaps immediately; the BYTES are lowered on the next Save, where
	the Python writer does the fixed-CLUT index delta against the original plane
	(which lives only in the BIN). A same-size sheet touches zero frame records,
	so this needs no relayout.

	"Swaps immediately" is two pushes, not one. `TextureChannel.replace` mints a NEW
	ImageTexture on the model, but every surface that shows the sheet CACHED the old
	object: the particle renderer bound it into its pool slot's shader material once at
	initialize(), and `refold()` only rescrubs the timeline — it never touches materials.
	So the swap must be followed by `refresh_texture()` (re-push the uniforms) as well as
	the re-fold (re-run the sim that samples them). The frameset canvas caches it too, but
	that one is the page's to refresh; it re-renders on the verdict below.

	Returns `{ok, error}` — every refusal here (unreadable file, a .tga the decoder won't
	take, a dimension mismatch) used to be a bare `push_warning` the author never saw, so
	a refused import and a working one looked identical on screen."""
	if not (_current_effect and is_instance_valid(_current_effect)) or _current_effect.effect_data == null:
		return {"ok": false, "error": "no live effect to import into"}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "cannot read %s" % path}
	var raw := f.get_buffer(f.get_length())
	f.close()

	var img: Dictionary = TextureTgaClass.decode(raw)
	if not img.get("ok", false):
		return {"ok": false, "error": str(img.get("error", ""))}

	if _edit_session == null or _edit_session_data != _current_effect.effect_data:
		_edit_session = EffectEditSessionClass.new(_current_effect.effect_data)
		_edit_session_data = _current_effect.effect_data
	var res: Dictionary = _edit_session.replace_texture(
		img["pixels"], int(img["width"]), int(img["height"]))
	if not res.get("ok", false):
		return {"ok": false, "error": str(res.get("error", ""))}
	# The sheet is sampled by every particle sprite through a material uniform bound at
	# renderer init — re-push it BEFORE the re-fold so the rescrub renders the new pixels.
	_current_effect.refresh_texture()
	_current_effect.refold()
	return {"ok": true, "error": ""}


func studio_seek(frame: int) -> void:
	# Move the playhead so the effect's last-RENDERED frame equals the studio playhead
	# `frame`. The timeline clock (effect_frame) counts frames ELAPSED — it is one AHEAD
	# of the last-folded frame (seek(N) pumps advance(0..N-1), leaving effect_frame=N and
	# the last fold at N-1). So to render frame D we pump one further: seek(D+1). This makes
	# "park the playhead at a span's END → SEE the colour authored there" true (the ramp
	# settles at start+dur, and the display now maps to the rendered frame), and it is uniform
	# across every subsystem, not just the screen gradient. The deterministic clock, spawn
	# frames, sound, and ADR-0070 seek are UNTOUCHED — only this studio display mapping shifts.
	#
	# Frame 0 is the exception: seek(0) is the reset/Stop state (no pump, camera returns to the
	# tile cursor via the per-frame reconcile that keys on effect_frame==0). Mapping it to
	# seek(1) would flip the camera to the effect and fight studio_stop's frame-0 hand-back, so
	# D<=0 stays seek(0). Cost: fold-frame 0 is not individually parkable (its render ~= the
	# reset state anyway, progress 0), a deliberate trade to preserve Stop.
	#
	# Camera ownership still follows: scrubbing to D>0 leaves effect_frame=D+1>0 (effect camera),
	# scrubbing to 0 leaves effect_frame=0 (cursor) — same thresholds as before.
	if _current_effect and is_instance_valid(_current_effect):
		_current_effect.seek(0 if frame <= 0 else frame + 1)


func studio_seek_silent(frame: int) -> void:
	# Silent seek for the Studio's ping-pong REVERSE leg (ADR-0090): identical display
	# mapping to studio_seek (+1, with frame 0 the reset exception), but routes to
	# EffectInstance.seek_silent so the sound cast is NOT re-armed on the backward step.
	if _current_effect and is_instance_valid(_current_effect):
		_current_effect.seek_silent(0 if frame <= 0 else frame + 1)


func studio_set_playing(playing: bool) -> void:
	# Just start/stop the clock. Play advances the frame past 0 → _process's
	# reconcile hands the camera to the effect. Pause holds the frame (still > 0)
	# so the effect keeps the camera. No camera logic needed here.
	if _current_effect and is_instance_valid(_current_effect):
		_current_effect.set_paused(not playing)


func studio_stop() -> void:
	"""Studio Stop hand-back. The page has already seek(0)'d the instance, so the
	per-frame reconcile in _process would return the camera to the tile cursor
	next frame anyway; this makes the deliberate Stop instant (zero one-frame lag)
	by reconciling to frame 0 immediately."""
	reconcile_studio_camera(get_node_or_null("PlayerCamera"), 0, _acquire_effect_camera, _studio_free_cam)


func studio_set_free_camera(on: bool) -> void:
	"""Free-camera debug toggle: force the frame-0 (scene owns) camera branch at
	every playhead so the user can fly the tile-cursor camera (WASD/Q/E) while the
	effect keeps playing. Reconciles IMMEDIATELY — turning it ON at a frame > 0
	releases takeover now (hands the camera back, cursor returns); turning it OFF
	re-acquires the effect camera at the current playhead. The effect clock is
	untouched: playback still advances, only camera ownership changes."""
	_studio_free_cam = on
	var frame: int = _current_effect.get_effect_frame() if (_current_effect and is_instance_valid(_current_effect)) else 0
	reconcile_studio_camera(get_node_or_null("PlayerCamera"),
		frame, _acquire_effect_camera, _studio_free_cam)
	# Re-acquiring on OFF seeds a FRESH camera base (from the flown-to free-camera
	# pose). The effect camera controller computes its pose incrementally as
	# base + keyframe-delta and only recomputes on a clock advance, so a PARKED
	# effect would sit at the bare base pose. Force a deterministic rescrub (reset →
	# re-pump to the current frame) so the effect camera snaps to THIS frame's pose
	# against the new base right away — same path a studio scrub takes. Only when an
	# effect with a camera is parked past frame 0; ON never rescrubs (clock is the
	# effect's, only ownership moved).
	if not on and frame > 0 and _current_effect and is_instance_valid(_current_effect) \
			and _current_effect.camera_controller:
		_current_effect.refold()


func studio_current_frame() -> int:
	# Report the frame the studio playhead RENDERS — the last-folded frame, which is one behind
	# the timeline clock (effect_frame counts frames elapsed). The inverse of studio_seek's +1:
	# it round-trips the studio display space (seek(D) then current == D) and mirrors the live
	# clock onto the playhead one-behind during playback, so the playhead line sits on the frame
	# actually on screen. The raw clock (get_effect_frame) stays authoritative for the host's own
	# internal re-seeks (studio_apply_edit, free-cam).
	if _current_effect and is_instance_valid(_current_effect):
		return maxi(0, _current_effect.get_effect_frame() - 1)
	return 0


func studio_set_child_edge_suppressed(parent_index: int, edge: String, suppressed: bool) -> void:
	"""ADR-0075: per-edge child-spawn suppression from the inspector checkbox. Forwards to
	the live instance, which sets the sim flag and re-seeks to the current playhead."""
	if _current_effect and is_instance_valid(_current_effect):
		_current_effect.set_child_edge_suppressed(parent_index, edge, suppressed)


func studio_is_child_edge_suppressed(parent_index: int, edge: String) -> bool:
	"""Suppressed-state provider for the inspector checkbox (ADR-0075)."""
	if _current_effect and is_instance_valid(_current_effect):
		return _current_effect.is_child_edge_suppressed(parent_index, edge)
	return false


func studio_effect_data():
	"""The LIVE authoring model (the instance's EffectData the choke point mutates in
	place). The Studio page projects from THIS so its inspector/timeline reflect edits —
	one source of truth, no page-vs-host copy drift."""
	if _current_effect and is_instance_valid(_current_effect):
		return _current_effect.effect_data
	return null


func studio_audition_container(index: int) -> void:
	"""Host side of the container "Audition sequence" action: hear a SoundContainer's
	Pick-mode alternation. Delegates to the LIVE effect instance (it owns the loaded FEDS
	bank + the open SFX cast), which fires the container several times through the SFX
	engine. Inert if no effect is loaded. Pure playback — no edit."""
	if _current_effect and _current_effect.has_method("audition_container"):
		_current_effect.audition_container(index)


func studio_audition_sound(resolved_id: int) -> void:
	"""Host side of the ▶ slot-preview action: hear ONE resolved sound id (a container's
	Sound A/B/C entry) exactly once, so an author can tell the bank entries apart while
	picking. Delegates to the LIVE effect instance (it owns the loaded FEDS bank + the
	open SFX cast). Inert if no effect is loaded. Pure playback — no edit."""
	if _current_effect and _current_effect.has_method("audition_sound"):
		_current_effect.audition_sound(resolved_id)


func studio_apply_edit(field_ref: Dictionary, new_raw, defer_refold: bool = false) -> Dictionary:
	"""#255 authoring choke point (host side): lower one raw-byte edit into the LIVE
	instance's EffectData through EffectEditSession.apply_edit (the single mutation entry
	point; it writes the raw, re-derives the value cache, and reports invalidates_sim).
	Screen colour is READ-LIVE — ScreenSubsystem rebuilds the ColorStack by-reference each
	frame — so an invalidates_sim=false edit repaints in place with NO re-seek. A
	sim-invalidating edit re-seeks to the current playhead to re-pump (ADR-0070). Returns
	the choke point's result (incl. `structural`) so the page can re-project when the field
	set reshapes (e.g. a Blend↔Gradient kind flip)."""
	if not (_current_effect and is_instance_valid(_current_effect)) or _current_effect.effect_data == null:
		return {}
	# (Re)bind the session to the current instance's data (a respawn swaps EffectData).
	if _edit_session == null or _edit_session_data != _current_effect.effect_data:
		_edit_session = EffectEditSessionClass.new(_current_effect.effect_data)
		_edit_session_data = _current_effect.effect_data
	var res: Dictionary = _edit_session.apply_edit(field_ref, new_raw)
	# An emitter edit can change the particle renderer's per-emitter caches (colour curves,
	# align_to_velocity) — built once at the renderer's initialize() and otherwise never rebuilt.
	# Refresh them so a live colour-curve enable toggle / reassignment takes effect instead of
	# sampling stale data (the E312 idx0 "colour curves do nothing" report). The enable toggle
	# refolds below (invalidates_sim); a reassignment is relayout-only and never refolds — either
	# way the refreshed cache feeds the next update_particles frame.
	# A `curve_assign` counts too (ADR-0089 curve-ownership amendment): the picker's verb can
	# MINT a curve and re-point a colour channel at it, and the renderer's per-emitter colour
	# caches hold the old EffectCurve BY REFERENCE, so without this the pick would repaint
	# nothing. (A plain `curve` contents edit needs no refresh for the same reason: the cached
	# object IS the one that was written.)
	if String(field_ref.get("channel", "")) in ["emitter", "curve_assign"]:
		_current_effect.refresh_render_emitter_caches()
	if res.get("invalidates_sim", false):
		# A FOLDED channel (camera framing) only re-shows after a re-fold. seek() to the
		# CURRENT frame is a same-frame no-op — rescrub via refold() so the edit takes.
		# ADR-0089 Drag preview: during a live drag defer the (expensive) rescrub — the page
		# reprojects the sim-free geometry per motion and folds ONCE via studio_commit_refold
		# on release, so a dense particle cloud doesn't replay-from-0 every rendered frame.
		if defer_refold:
			_deferred_refold_pending = true
		else:
			_current_effect.refold()
	else:
		# Read-live channel (screen colour): re-fold in place at the current frame. The
		# once-per-frame guard holds the folded output between ticks, so a parked preview
		# needs an explicit re-deliver to show the live edit — zero re-seek (ADR-0070).
		_current_effect.redeliver_colors()
	return res


func studio_author_colour(emitter_index: int, frame: int, curve: Color) -> Dictionary:
	"""ADR-0089 colour-keyframe authoring (host side): the author picked a CURVE colour for
	`emitter_index` at `frame`. Lower it through a per-emitter ColourKeyframeSession, which compiles
	the keyframes down into the emitter's three colour curves. Those are PRIVATE to
	this emitter since the ADR-0089 curve-ownership amendment — the explode at load gave every use
	site its own copy — so the write moves nothing else and the old copy-on-write fork is gone.
	Refresh the
	renderer's per-emitter colour caches (built once at initialize()) and refold so the live burst
	repaints.

	THE PICK IS NO LONGER PROJECTED (decision 4, amended 2026-08-21). It used to arrive as a MUXED
	target and get clamped into the emitter's reachable box on the way in, which is what made the
	picker unable to hold 255 in any channel for 97.5% of corpus colour emitters. It arrives as the
	curve triple now and is written as picked. `renders_as` is what the sprite makes of it — the
	same bound, reported instead of imposed. Returns {ok, curve, renders_as}. Never raises."""
	var sess = _colour_session(emitter_index)
	if sess == null:
		return {"ok": false, "curve": curve, "renders_as": curve}
	sess.place(frame, curve)  # place() clamps to the unit cube itself
	_colour_commit(sess)      # compile + repaint the live burst
	return {"ok": true, "curve": sess.curve_at(frame), "renders_as": sess.renders_as(frame)}


func studio_colour_enable(emitter_index: int, on: bool) -> Dictionary:
	"""ADR-0089 colour on/off (host side). The author asked for the toggle *"near where all
	the 'color' stuff is"*; the machinery it drives is `emitter_flags_lo` bit 6, which the
	inspector's flag section has always exposed. What is NEW here is the second half.

	TURNING COLOUR ON MUST PRODUCE A COLUMN. Of the 605 corpus emitters with colour off, 591
	have r/g/b indices that already resolve and simply light up; **14 point at nothing**, and
	`SequenceCellColour._curves` is deliberately all-or-nothing (a partial resolve would tint
	two channels and zero the third, which reads as a colour cast rather than as the absence
	it is). So on those the flag would flip, no column would appear, and the toggle would
	read as broken. Offered the alternative — refuse on those 14 and say why — the author
	chose to MINT, so the toggle means the same thing on all 605.

	The mint is FLAT AT 255, which is the identity: the Godot render is `ALBEDO = S * curve`
	and a disabled emitter modulates by white, so a curve of 1.0 is exactly the untinted
	picture. Nothing on screen changes until the author authors something — the same promise
	`CurveChannel.assign_shape` already makes for the picker's own mint.

	ONE COMPOUND EDIT, so it is one undo: the flag flip plus up to three `curve_assign`
	members. Both go through the #255 choke point rather than writing `EffectData` here.
	Returns {ok, minted}."""
	if not (_current_effect and is_instance_valid(_current_effect)) \
			or _current_effect.effect_data == null:
		return {"ok": false, "minted": 0}
	var data = _current_effect.effect_data
	if emitter_index < 0 or emitter_index >= data.emitters.size():
		return {"ok": false, "minted": 0}
	var edits: Array = [{
		"field_ref": {"channel": "emitter", "emitter_index": emitter_index,
			"field": "color_curve_enable"},
		"new_raw": 1 if on else 0}]
	var minted: int = 0
	if on:
		for chan in ["r", "g", "b"]:
			var cur = data.get_curve(int(data.emitters[emitter_index].color_curves.get(chan, -1)))
			if cur != null and not cur.samples.is_empty():
				continue
			var flat: Array = []
			flat.resize(160)
			flat.fill(255)
			# All 14 of the corpus's non-resolving colour-off emitters are in E509 and
			# E510, whose `curves.json` has ZERO entries. Their emitter records still name
			# slot 0 for r, g AND b on disk — but `CurveExplode` normalises an unresolvable
			# reference to an explicit -1 at load, so by the time this runs each channel is
			# honestly curveless and `mint_identity` gives each its own. (Worth stating
			# because the raw JSON says otherwise, and a fix aimed at the JSON's story was
			# written, tested, and found to be solving nothing.)
			edits.append({"field_ref": {"channel": "curve_assign",
				"emitter_index": emitter_index, "slot": chan, "kind": "colour"},
				"new_raw": flat})
			minted += 1
	studio_apply_compound(edits)
	# THE SESSION HELD THE OLD CURVES. `_colour_session` imports keyframes on first touch and
	# caches per emitter, so a session begun while this emitter had no curves would keep
	# answering from that import and the track would stay empty behind a lit toggle. Drop it
	# and let the next read re-import what is actually there now.
	_colour_sessions.erase(emitter_index)
	_current_effect.refresh_render_emitter_caches()
	return {"ok": true, "minted": minted}


func studio_colour_keyframes(emitter_index: int) -> Dictionary:
	"""ADR-0089 colour-keyframe track: the emitter's current colour keyframes (age-domain) + the
	reachable-box gamut, so the studio can draw the track markers and seed the box-clamped picker.
	Ensures the per-emitter session is begun (imports the ROM curve on first touch). Never raises."""
	var sess = _colour_session(emitter_index)
	if sess == null:
		return {"ok": false, "gamut": Color.WHITE, "keyframes": []}
	return {"ok": true, "gamut": sess.gamut(), "keyframes": sess.keyframes().duplicate(true)}


func studio_colour_add(emitter_index: int, frame: int) -> Dictionary:
	"""ADR-0089 colour-keyframe track: add a keyframe at particle-age `frame`, seeded with the
	colour already there (a visual no-op until recoloured). Returns {ok, frame, color}."""
	var sess = _colour_session(emitter_index)
	if sess == null:
		return {"ok": false, "frame": frame, "color": Color.WHITE}
	var idx: int = sess.add(frame)
	_colour_commit(sess)
	var kfs: Array = sess.keyframes()
	var col: Color = kfs[idx]["color"] if idx >= 0 and idx < kfs.size() else Color.WHITE
	return {"ok": true, "frame": frame, "color": col}


func studio_colour_delete(emitter_index: int, frame: int) -> Dictionary:
	"""ADR-0089 colour-keyframe track: delete the keyframe at particle-age `frame`."""
	var sess = _colour_session(emitter_index)
	if sess == null:
		return {"ok": false}
	sess.delete(sess.index_of_frame(frame))
	_colour_commit(sess)
	return {"ok": true}


## Get-or-create the per-emitter ColourKeyframeSession bound to the CURRENT instance's data
## (rebound when a respawn swaps EffectData). Null when there's no live emitter.
func _colour_session(emitter_index: int):
	if not (_current_effect and is_instance_valid(_current_effect)) or _current_effect.effect_data == null:
		return null
	var data = _current_effect.effect_data
	if emitter_index < 0 or emitter_index >= data.emitters.size():
		return null
	if _colour_sessions_data != data:
		_colour_sessions.clear()
		_colour_sessions_data = data
	var sess = _colour_sessions.get(emitter_index)
	if sess == null:
		sess = ColourKeyframeSessionClass.new()
		sess.begin(data, emitter_index)  # imports the current curve; gamut from the sprite texel
		_colour_sessions[emitter_index] = sess
	return sess


## Compile the session's keyframes into the emitter's (forked) curves and repaint the live burst:
## the renderer's per-emitter colour cache is built once at initialize(), so refresh it + refold.
func _colour_commit(sess) -> void:
	sess.apply()
	_colour_authored = true
	_current_effect.refresh_render_emitter_caches()
	_current_effect.refold()


func studio_begin_coalesce(field_ref: Dictionary) -> void:
	"""ADR-0086 boundary-drag (host side): open a drag-scoped undo coalesce on the live
	session, so a whole edge-drag gesture (many per-frame end_frame edits) collapses to ONE
	undo. Bind the session lazily like the scalar choke point; no-op if there's no effect."""
	if not (_current_effect and is_instance_valid(_current_effect)) or _current_effect.effect_data == null:
		return
	if _edit_session == null or _edit_session_data != _current_effect.effect_data:
		_edit_session = EffectEditSessionClass.new(_current_effect.effect_data)
		_edit_session_data = _current_effect.effect_data
	_edit_session.begin_coalesce(field_ref)


func studio_end_coalesce() -> void:
	"""ADR-0086 boundary-drag (host side): close the drag's undo coalesce (release)."""
	if _edit_session != null:
		_edit_session.end_coalesce()


func studio_begin_move(field_ref: Dictionary) -> void:
	"""ADR-0089 Move (host side): open the body-drag's single-snapshot undo on the live
	session. Bind lazily like the other choke points; no-op with no live effect."""
	if not (_current_effect and is_instance_valid(_current_effect)) or _current_effect.effect_data == null:
		return
	if _edit_session == null or _edit_session_data != _current_effect.effect_data:
		_edit_session = EffectEditSessionClass.new(_current_effect.effect_data)
		_edit_session_data = _current_effect.effect_data
	_edit_session.begin_move(field_ref)


func studio_move_preview(field_ref: Dictionary, delta: int, defer_refold: bool = false) -> Dictionary:
	"""ADR-0089 Move (host side): apply the drag's absolute slide (restore-then-reapply, no
	per-motion undo) and re-fold so the moved span re-simulates. Returns the reproject hint,
	or {} when refused (wedged / first span) or no live session. ADR-0089 Drag preview: while
	the drag is live (defer_refold) the rescrub is deferred to studio_commit_refold on release
	— the page still reprojects the sim-free geometry so the span tracks the cursor each motion."""
	if _edit_session == null or not (_current_effect and is_instance_valid(_current_effect)):
		return {}
	var res: Dictionary = _edit_session.move_preview(field_ref, delta)
	if not res.is_empty():
		if defer_refold:
			_deferred_refold_pending = true
		else:
			_current_effect.refold()
	return res


func studio_end_move() -> Dictionary:
	"""ADR-0089 Move (host side): close the body-drag. For the STRUCTURE-FREE colour kinds this
	is where the move actually happens — every motion only planned, so the session splices once
	here, at the last previewed delta, against data no motion touched. Then the drag's single
	undo entry is recorded. Returns the commit's reproject hint (carrying the span's new
	`event_index`, since a colour Move renumbers the lane), or {} when nothing was committed —
	a click, a cancelled slide, or one of the apply-per-motion kinds."""
	if _edit_session == null:
		return {}
	return _edit_session.end_move()


func studio_commit_refold() -> void:
	"""ADR-0089 Drag preview (host side): a live edge/body drag deferred every sim rescrub to
	keep the per-motion preview cheap; on release the page calls this to fold ONCE so the
	particle cloud snaps to the committed result. No-op unless a sim-invalidating edit was
	actually deferred — a read-live colour drag never sets the flag, so it stays untouched."""
	if _deferred_refold_pending and _current_effect and is_instance_valid(_current_effect):
		_current_effect.refold()
	_deferred_refold_pending = false


func studio_undo() -> bool:
	"""#255 undo (host side): unwind the last edit through the SAME EffectEditSession the
	choke point records to, then re-pump so the reverted state shows. Undo is a rare,
	explicit gesture (Ctrl+Z), so it always refold()s — a superset of the forward path's
	folded/read-live split that shows any channel's revert without the page tracking which.
	Returns false (no re-derive) when there is nothing to undo or no live session/effect."""
	if not (_current_effect and is_instance_valid(_current_effect)) or _edit_session == null:
		return false
	if not _edit_session.undo():
		return false
	# Same superset reasoning as the refold: a texture-snapshot undo (#280) puts the OLD
	# ImageTexture object back on the model, and the particle renderer cached the imported
	# one in its pool slot's material — without this, Ctrl+Z would revert the bytes but
	# leave the imported sheet on screen. Two uniform writes; harmless for every other kind.
	_current_effect.refresh_texture()
	_current_effect.refold()
	return true


func studio_insert_event(field_ref: Dictionary) -> Dictionary:
	"""#287 lane-editing verb (host side): the INSERT-WAYPOINT add, lowered through the SAME
	EffectEditSession the scalar choke point uses (so undo / faithful / re-derive all hold).
	Structural — the camera section recompiles — so it always invalidates the folded sim and
	we refold(). Returns the choke point's result (incl. `structural` + the new `ordinal`)."""
	return _studio_structural_verb(field_ref, "insert")


func studio_delete_event(field_ref: Dictionary) -> Dictionary:
	"""#287 lane-editing verb (host side): the inverse DELETE. Same session + refold contract
	as studio_insert_event."""
	return _studio_structural_verb(field_ref, "delete")


func studio_unrest_event(field_ref: Dictionary) -> Dictionary:
	"""The FEDS time lane's UN-REST (ADR-0085 2026-08-19): sound the addressed rest span —
	the inverse of a delete, which on that lane means putting a rest there. Same session +
	re-derive contract as the other two."""
	return _studio_structural_verb(field_ref, "unrest")


func studio_paint_event(field_ref: Dictionary) -> Dictionary:
	"""The FEDS time lane's PAINT (ADR-0085 2026-08-19b §2): a note INSIDE the addressed rest
	span, splitting it. Carries `offset_ticks` / `duration_ticks` beside the head's byte
	boundary — span identity for the anchor, ticks for the position. Same session +
	re-derive contract as the other three."""
	return _studio_structural_verb(field_ref, "paint")


func studio_drag_event(field_ref: Dictionary) -> Dictionary:
	"""The FEDS time lane's DRAG (ADR-0085 2026-08-19b §2/§3): move / resize-right /
	resize-left of the addressed note span, spending the silence around it. Carries
	`gesture` + a signed `delta_ticks` beside the head's byte boundary — the pixel was read
	once at grab time and everything downstream speaks ticks (§5). Bracket it with
	studio_begin_coalesce / studio_end_coalesce so one gesture is one undo. Same session +
	re-derive contract as the other four."""
	return _studio_structural_verb(field_ref, "drag")


func studio_set_outro(field_ref: Dictionary) -> Dictionary:
	"""The FEDS time lane's OUTRO (ADR-0085 2026-08-19c): set the silence between the
	addressed track's last authored event and its EndBar. Carries `outro_ticks` (absolute)
	beside `track_idx` — the outro is not an event, so unlike the other four verbs it is
	addressed by TRACK, not by a byte boundary. The one verb that moves end_tick; same
	session + re-derive contract as the rest."""
	return _studio_structural_verb(field_ref, "outro")


func _studio_structural_verb(field_ref: Dictionary, verb: String) -> Dictionary:
	if not (_current_effect and is_instance_valid(_current_effect)) or _current_effect.effect_data == null:
		return {}
	if _edit_session == null or _edit_session_data != _current_effect.effect_data:
		_edit_session = EffectEditSessionClass.new(_current_effect.effect_data)
		_edit_session_data = _current_effect.effect_data
	var res: Dictionary = {}
	match verb:
		"insert":
			res = _edit_session.insert_event(field_ref)
		"unrest":
			res = _edit_session.unrest_event(field_ref)
		"paint":
			res = _edit_session.paint_event(field_ref)
		"drag":
			res = _edit_session.drag_event(field_ref)
		"outro":
			res = _edit_session.set_outro(field_ref)
		"delete":
			res = _edit_session.delete_event(field_ref)
		_:
			# NAMED, never a fall-through. This match used to end in a bare `_: delete`, so a
			# verb added at the page without a case here ran a DELETE at an address it had
			# never built — which is exactly what a new verb's first e2e run does.
			push_error("EffectViewerScene: no studio verb '%s'" % verb)
			return {}
	if not res.is_empty() and not bool(res.get("invalidates_feds", false)):
		# Camera / palette / screen / particle are FOLDED — a structural edit only shows
		# after a re-fold. A structural sound_def edit (ADR-0085 2026-08-18b) is SOUND,
		# not the folded framebuffer, so it re-derives through `invalidates_feds` exactly
		# as a byte patch and a prune-for-real do, and refolding would be pure cost.
		_current_effect.refold()
	return res


func studio_prune_feds_noops(pair_idx: int) -> Dictionary:
	"""Prune-for-real (ADR-0085 2026-08-13 amendment): DELETE every no-op opcode from the open
	pair's two tracks through the SAME EffectEditSession the scalar sound_def edits use — so undo
	(Ctrl+Z) and the byte-exact save path all hold. Size-changing (the blob shrinks), so it goes
	through the structural `prune_feds_noops` verb, not the same-size patcher. The FEDS bytes are
	SOUND, not the folded framebuffer, so there is no refold here — the page re-derives the pair
	views + ghosts off `invalidates_feds` (mirroring a sound_def byte patch). Returns the verb's
	result ({} when the pair has nothing prunable)."""
	if not (_current_effect and is_instance_valid(_current_effect)) or _current_effect.effect_data == null:
		return {}
	if _edit_session == null or _edit_session_data != _current_effect.effect_data:
		_edit_session = EffectEditSessionClass.new(_current_effect.effect_data)
		_edit_session_data = _current_effect.effect_data
	return _edit_session.prune_feds_noops(pair_idx)


func studio_apply_compound(edits: Array) -> Dictionary:
	"""ADR-0085 fire-drag choke point (host side): lower a MULTI-field author gesture
	(the two neighbouring sound gaps a stay-local trigger move trades) as ONE compound
	edit through EffectEditSession.apply_compound — a single undo. Mirrors studio_apply_edit:
	(re)bind the session to the live instance's data, then re-derive per the aggregate
	invalidates_sim. Sound gap edits are invalidates_sim=false (no framebuffer impact), so
	this repaints in place with no re-seek."""
	if not (_current_effect and is_instance_valid(_current_effect)) or _current_effect.effect_data == null:
		return {}
	if _edit_session == null or _edit_session_data != _current_effect.effect_data:
		_edit_session = EffectEditSessionClass.new(_current_effect.effect_data)
		_edit_session_data = _current_effect.effect_data
	var res: Dictionary = _edit_session.apply_compound(edits)
	if res.get("invalidates_sim", false):
		_current_effect.refold()
	else:
		_current_effect.redeliver_colors()
	return res


func studio_screen_top_color() -> Color:
	"""#255 WYSIWYG target-colour SEED: the backdrop's live folded TOP colour at the parked
	frame — what the Studio picker opens showing, so the author nudges from the current look.
	Black if there is no live screen channel."""
	if _current_effect and is_instance_valid(_current_effect) and _current_effect.screen_controller:
		return _current_effect.screen_controller.top_color
	return Color.BLACK


func studio_pick_target(field_refs: Dictionary, target: Color) -> Color:
	"""#255 WYSIWYG target-colour authoring: the author picked the colour the backdrop TOP
	should BECOME at the parked frame. Back-solve the SIGNED Blend param by brute-forcing all
	256 candidate raw bytes per channel through the REAL forward blend fold (ScreenSubsystem.
	fold_top, the exact path the preview uses — so the solved param provably matches the preview
	and a target that can't be reached lands on the nearest achievable colour). The solver's
	chosen bytes lower through the SAME EffectEditSession choke point studio_apply_edit uses (so
	undo/faithful/re-derive all hold). Returns the ACHIEVED top colour (may differ from the pick
	when unreachable) for the widget's honest feedback.

	Dispatched by the pick's channel: the PALETTE tint (ADR-0087) shares the identical
	result-picker widget but back-solves a SIGNED Δ against the palette fold over a fixed
	mid-grey reference (PaletteTintSolver), not the live screen backdrop."""
	if field_refs.get("r", {}).get("channel", "") == "palette":
		return _pick_palette_tint(field_refs, target)
	if not (_current_effect and is_instance_valid(_current_effect)) \
			or _current_effect.screen_controller == null or _current_effect.effect_data == null \
			or _current_effect.effect_data.screen == null:
		return Color.BLACK
	var sc = _current_effect.screen_controller
	var kf = _resolve_screen_keyframe(field_refs)
	if kf == null:
		return Color.BLACK

	# Probe the forward fold per candidate by transiently overriding this tween's raw bytes
	# (restored below — a read-only probe that never touches the choke point / undo stack).
	var saved := {"r": kf.start_r_raw, "g": kf.start_g_raw, "b": kf.start_b_raw}
	var eval := func(r: int, g: int, b: int) -> Vector3:
		kf.start_r_raw = r
		kf.start_g_raw = g
		kf.start_b_raw = b
		var top: Color = sc.fold_top()
		return Vector3(top.r, top.g, top.b)
	var best: Dictionary = BlendTargetSolverClass.solve(eval, saved, Vector3(target.r, target.g, target.b))
	kf.start_r_raw = saved.r
	kf.start_g_raw = saved.g
	kf.start_b_raw = saved.b

	# Lower the solved bytes through the real choke point (records undo + re-derives + repaints).
	studio_apply_edit(field_refs.get("r", {}), int(best.get("r", saved.r)))
	studio_apply_edit(field_refs.get("g", {}), int(best.get("g", saved.g)))
	studio_apply_edit(field_refs.get("b", {}), int(best.get("b", saved.b)))
	return sc.top_color


## Resolve the screen keyframe a target-colour pick addresses (its R component's field_ref
## carries the context + event_index — all three share the tween).
func _resolve_screen_keyframe(field_refs: Dictionary):
	var ref: Dictionary = field_refs.get("r", {})
	var ch = _current_effect.effect_data.screen.get_channel(ref.get("context", ""))
	if ch == null:
		return null
	return ch.get_keyframe(int(ref.get("event_index", -1)))


func _pick_palette_tint(field_refs: Dictionary, target: Color) -> Color:
	"""ADR-0087 palette tint pick (host side): the author picked the colour the mid-grey
	reference should BECOME under this keyframe's blend mode. The solve is PURE — it needs only
	the keyframe's current mode + raw bytes — so PaletteTintSolver back-solves the signed Δ
	against the same forward fold the preview uses. The solved bytes lower through the SAME
	choke point studio_apply_edit uses (undo / faithful / read-live repaint all hold). Returns
	the ACHIEVED colour (nearest when unreachable) for the widget's honest 'actual' swatch."""
	var kf = _resolve_palette_keyframe(field_refs)
	if kf == null:
		return Color.BLACK
	var orig := {"r": int(kf.rgb.x), "g": int(kf.rgb.y), "b": int(kf.rgb.z)}
	var best: Dictionary = PaletteTintSolverClass.solve(
		int(kf.blend_mode), orig, Vector3(target.r, target.g, target.b))
	studio_apply_edit(field_refs.get("r", {}), int(best.get("r", orig.r)))
	studio_apply_edit(field_refs.get("g", {}), int(best.get("g", orig.g)))
	studio_apply_edit(field_refs.get("b", {}), int(best.get("b", orig.b)))
	return best.get("achieved", Color.BLACK)


## Resolve the palette keyframe a tint pick addresses — palette's TWO-dimensional address
## (phase context AND channel_name) rides the R component's field_ref (all three share it).
func _resolve_palette_keyframe(field_refs: Dictionary):
	if _current_effect == null or _current_effect.effect_data == null \
			or _current_effect.effect_data.palette == null:
		return null
	var ref: Dictionary = field_refs.get("r", {})
	var ch = _current_effect.effect_data.palette.get_channel(
		ref.get("context", ""), ref.get("channel_name", ""))
	if ch == null:
		return null
	return ch.get_keyframe(int(ref.get("event_index", -1)))


func studio_set_audibility(audibility: Dictionary) -> void:
	"""Apply the Studio Solo/Mute selection (the resolve_audibility result) to the live
	preview: per-emitter particle render-skip + per-lane exclusion filters for
	screen/palette/camera/sound. Color re-folds in place immediately; camera/sound reflect
	on the next rescrub. Held so a re-spawn re-applies it."""
	_studio_audibility = audibility
	_apply_studio_audibility()


## Push the held Solo/Mute selection onto the current instance (no-op if none).
func _apply_studio_audibility() -> void:
	if _current_effect and is_instance_valid(_current_effect):
		_current_effect.apply_audibility(_studio_audibility)


func stop_effect() -> void:
	_looping = false
	_stop_current_effect()
	_panel.update_status("Idle")


func set_looping(enabled: bool) -> void:
	_looping = enabled


func _stop_current_effect() -> void:
	_polling = false
	if _current_effect and is_instance_valid(_current_effect):
		_current_effect.queue_free()
		_current_effect = null
	# Restore camera if still in effect mode
	var cam = get_node_or_null("PlayerCamera")
	if cam and cam.camera_mode == cam.CameraMode.TAKEOVER:
		cam.release_takeover()
	_cleanup_unit_animations()
	_panel.clear_emitters()


func _poll_effect_completion(effect: Node) -> void:
	_polling = true

	# Wait for initial particles to spawn
	await get_tree().create_timer(0.5).timeout

	if not is_instance_valid(effect) or effect != _current_effect or not _polling:
		return

	var poll_count = 0
	var last_active = effect.manager.get_last_active_effect_frame()
	while is_instance_valid(effect) and effect == _current_effect and _polling:
		var count = effect.get_active_particle_count()
		var frame = effect.get_effect_frame()
		poll_count += 1
		# Done when all particle keyframes have fired and all particles have died
		if count == 0 and frame > last_active:
			_on_effect_finished()
			return
		# Timeout after 200 polls (~20s)
		if poll_count > 200:
			_on_effect_finished()
			return
		await get_tree().create_timer(0.1).timeout


func _on_effect_finished() -> void:
	if _looping and _last_effect_id >= 0:
		_stop_current_effect()
		_panel.update_status("Looping E%03d..." % _last_effect_id)
		await get_tree().create_timer(0.3).timeout
		if _looping:
			play_effect(_last_effect_id)
	else:
		_stop_current_effect()
		_panel.update_status("Idle")


func _on_map_loaded(_map_name: String) -> void:
	"""Handle map change from ScenarioDebugPanel — stop effect, reposition units."""
	stop_effect()

	# Wait a frame for the new map tiles to be ready
	await get_tree().process_frame

	# Reposition both units to their persisted positions (or fallback if tiles don't exist)
	_relocate_unit(_caster, _caster_pos())
	_relocate_unit(_target, _target_pos())

	# Re-seed the cursor: its old grid_pos may be off-grid on the new map.
	_setup_tile_cursor()

	# Update facing
	if _caster and _target:
		_caster.face_toward_unit(_target)
		_target.face_toward_unit(_caster)

	# Sync the unit control panel
	if _unit_panel:
		_unit_panel.sync_from_units()


func _build_effect_ability_map() -> void:
	for ability_id in range(512):
		var ability := AbilityDatabase.get_ability_view(ability_id)
		if ability.is_empty():
			continue
		var eid = ability.effect_id
		if eid != null and eid is int and eid >= 0:
			if not _effect_to_ability.has(eid):
				_effect_to_ability[eid] = ability_id


func set_react_enabled(enabled: bool) -> void:
	_react_enabled = enabled


func set_camera_enabled(enabled: bool) -> void:
	_camera_enabled = enabled
	if enabled:
		# Re-enabled mid-preview: re-acquire for a live camera effect so it starts
		# driving again (no-op if there's no effect / no camera controller).
		_acquire_effect_camera()
	else:
		# Exit effect mode immediately if camera was just disabled — free camera returns.
		var cam = get_node_or_null("PlayerCamera")
		if cam and cam.camera_mode == cam.CameraMode.TAKEOVER:
			cam.release_takeover()


func _cleanup_unit_animations() -> void:
	if _caster_casting and _caster and is_instance_valid(_caster):
		_caster.active_ability_id = -1
		_caster.activity = DisplayActivity.Activity.IDLE
		_caster_casting = false
	if _target and is_instance_valid(_target) and _target.is_reacting:
		_target.end_reaction()


func _on_ability_react(_frame: int) -> void:
	if not _react_enabled or not _target or not is_instance_valid(_target):
		return
	var reaction_type_str = "taking_damage"
	if _last_effect_id >= 0:
		var ability_id = _effect_to_ability.get(_last_effect_id, -1)
		if ability_id >= 0:
			var ability := AbilityDatabase.get_ability_view(ability_id)
			reaction_type_str = ability.target_reaction_type if ability.has("target_reaction_type") else "taking_damage"
	if reaction_type_str == "none":
		return
	var seq_id = ReactionType.get_seq_id("type1", reaction_type_str)
	if seq_id >= 0:
		_target.play_reaction_animation(seq_id, ReactionType.from_string(reaction_type_str), false)


func _on_refresh_tile(_frame: int) -> void:
	if not _target or not is_instance_valid(_target):
		return
	if _target.is_reacting:
		_target.end_reaction()


func _on_effect_camera_started() -> void:
	# Effect declares a camera timeline. camera_started is INFO ("this effect has
	# a camera"), NOT a command to seize the camera. The PANEL free-run path wants
	# immediate takeover (it starts advancing at once), so it acquires here. The
	# STUDIO parked path does NOT: a Studio instance spawns at frame 0, and camera
	# ownership there is a pure function of the playhead (reconcile_studio_camera,
	# driven per-frame in _process). Acquiring on load would seize the camera at
	# frame 0 and hide the tile cursor before the user plays anything — the exact
	# "no cursor at boot" regression. So the Studio opts out and lets its playhead
	# drive takeover (Play/scrub past 0), releasing at frame 0 (Stop/scrub-to-0).
	if _studio_parked:
		return
	_acquire_effect_camera()


func _acquire_effect_camera() -> void:
	"""Switch PlayerCamera into effect-driven TAKEOVER and seed the controller's
	base pose from the live (free-camera) pose. No-op unless Camera is enabled and
	the current effect actually has a camera controller — effects without camera
	keyframes never emit camera_started, so they keep the free cursor camera.
	Idempotent: if we're already driving, the base is already seeded — leave it."""
	if not _camera_enabled:
		return
	if not _current_effect or not is_instance_valid(_current_effect):
		return
	var ctrl = _current_effect.camera_controller
	if not ctrl:
		return
	var cam = get_node_or_null("PlayerCamera")
	if not cam:
		return
	if cam.camera_mode == cam.CameraMode.TAKEOVER:
		return
	# request_takeover snapshots the pre-takeover pose into cam._saved_* — must run
	# before we read them below. Seeding the controller's base + current pose must
	# precede the first advance() so the effect's relative camera math has a base
	# (the Studio's seek(0) in play_effect drives that first advance).
	cam.request_takeover(self)
	ctrl.saved_position = PsxChirality.godot_position_to_psx(cam.global_position)
	ctrl.saved_angles = Vector3(
		PsxMagnitude.deg_to_angle(-cam._saved_x_rot),
		PsxMagnitude.deg_to_angle(cam._saved_y_rot + 360.0),
		0)
	ctrl.saved_zoom = CameraCalibration.ortho_size_to_zoom(cam._saved_camera_size)
	ctrl.current_position = ctrl.saved_position
	ctrl.current_angles = ctrl.saved_angles
	ctrl.current_zoom = ctrl.saved_zoom
	# Map center for EFFECT_CTR (map_tiles * 14 in PSX coords).
	if map:
		var bounds: Rect2i = map.dynamic_geo_builder.map_bounds if map.dynamic_geo_builder else Rect2i()
		ctrl.map_center = Vector3(float(bounds.size.x) * 14.0, 0.0, float(bounds.size.y) * 14.0)


func _on_effect_camera_finished() -> void:
	if not _camera_enabled:
		return
	var cam = get_node_or_null("PlayerCamera")
	if cam and cam.camera_mode == cam.CameraMode.TAKEOVER:
		cam.release_takeover()


func _on_emitter_toggled(_index: int, _enabled: bool) -> void:
	if _current_effect and is_instance_valid(_current_effect):
		_current_effect.set_debug_emitter_filter(_panel.get_disabled_emitters())


func _relocate_unit(unit: Unit, pos: Vector2i) -> void:
	"""Place unit at pos, falling back to defaults if tile doesn't exist."""
	if not unit or not is_instance_valid(unit):
		return

	# Try requested position
	if unit.place_on_tile(pos.x, pos.y, map):
		return

	# Fallback to default positions
	if pos != DEFAULT_CASTER_POS and unit.place_on_tile(DEFAULT_CASTER_POS.x, DEFAULT_CASTER_POS.y, map):
		return
	if pos != DEFAULT_TARGET_POS and unit.place_on_tile(DEFAULT_TARGET_POS.x, DEFAULT_TARGET_POS.y, map):
		return

	# Last resort: tile (0, 0)
	unit.place_on_tile(0, 0, map)


func _process(_delta: float) -> void:
	# Studio camera ownership is a pure function of the playhead — reconcile it
	# from the LIVE effect frame every frame (see reconcile_studio_camera). This
	# one call makes Play (frame advances past 0 → effect owns), Stop/scrub-to-0
	# (→ cursor owns), and the natural-end freeze (playhead holds at last frame →
	# effect keeps the camera) all correct with no per-transport wiring. Scoped to
	# Studio-parked instances; the panel free-run path manages its own takeover
	# via camera_started/camera_finished.
	if _studio_parked and _current_effect and is_instance_valid(_current_effect):
		reconcile_studio_camera(get_node_or_null("PlayerCamera"),
			_current_effect.get_effect_frame(), _acquire_effect_camera, _studio_free_cam)

	# Apply camera controller output to PlayerCamera
	if not _camera_enabled:
		return
	if not _current_effect or not is_instance_valid(_current_effect):
		return
	if not _current_effect.camera_controller or not _current_effect.camera_controller.is_active():
		return
	var cam = get_node_or_null("PlayerCamera")
	if not cam or cam.camera_mode != cam.CameraMode.TAKEOVER:
		return
	var ctrl = _current_effect.camera_controller
	var pos = PsxChirality.psx_position_to_godot(ctrl.current_position)
	var rot = PsxChirality.psx_angles_to_godot_rotation(
		ctrl.current_angles.x, ctrl.current_angles.y, ctrl.current_angles.z)
	var ortho_size = CameraCalibration.zoom_to_ortho_size(ctrl.current_zoom)
	cam.apply_takeover(pos, rot, ortho_size)
