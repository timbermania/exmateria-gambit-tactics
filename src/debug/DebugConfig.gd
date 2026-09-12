@tool
extends Node

## DebugConfig - Global debug settings singleton
##
## Controls debug logging verbosity throughout the game.
## Toggle via UI or directly set flags.
##
## Command line args (for regression testing):
##   godot --scene ... -- --time-scale=10 --quit-after=10
##   --time-scale=N     - Set game speed (1-20, default 1)
##   --quit-after=N     - Auto-quit after N seconds (real time)
##   --test=<name>      - Run regression test (name or "all")
##   --update-baseline  - Save result as new baseline
##   --seed=N           - Custom RNG seed for deterministic tests
##   --effects=E001,E020 - Effects to test (comma-separated)

# Debug-preference flags are Tune tunables (ADR-0068 decision 10): the property
# coalesces a committed `debug.*` override over the code default, and an assignment
# routes the write through Tune, so a toggle in the F3 panel / generated dashboard
# persists across scene reloads and the flag is enumerable. DebugConfig OWNS the
# value; consumers read `DebugConfig.<flag>` live (no per-scene fan-out, decision 12).
# @tool-guarded: this script's accessors also run at edit time, where Tune is a
# placeholder instance (Tune.gd is not @tool) that cannot be called — route around
# it to the raw code default. These two helpers keep each property a tight 3 lines.
# The debug.* prefs are DebugConfig-OWNED (decision 12). Their default lives at the getter
# call, so a boot bind-list would duplicate it — instead register the slug ONCE here (guarded
# by is_registered so the get_stack cost is paid once) then PULL-read via get_value (R5). A
# pure-pull pref needs no on_update; the enumerable bind + coalesced read is the whole model.
func _dbg_get(default_value: bool, slug: String) -> bool:
	if Engine.is_editor_hint():
		return default_value
	if not Tune.is_registered(slug):
		Tune.bind(slug, default_value)
	return Tune.get_value(slug)

func _dbg_set(slug: String, value: bool) -> void:
	if Engine.is_editor_hint():
		return
	Tune.set_value(slug, value)

# Numeric (float) siblings of the bool helpers, same @tool guard — for the handful of
# scalar debug prefs (e.g. the spike threshold) that are also tunables.
func _dbg_get_num(default_value: float, slug: String) -> float:
	if Engine.is_editor_hint():
		return default_value
	if not Tune.is_registered(slug):
		Tune.bind(slug, default_value)
	return Tune.get_value(slug)

func _dbg_set_num(slug: String, value: float) -> void:
	if Engine.is_editor_hint():
		return
	Tune.set_value(slug, value)

# Action/animation debug logging (weapon loading, sprite changes, reaction anims)
var action_debug_enabled: bool:
	get: return _dbg_get(false, "debug.action_debug_enabled")
	set(value): _dbg_set("debug.action_debug_enabled", value)

# Camera system debug logging
var camera_debug_enabled: bool:
	get: return _dbg_get(false, "debug.camera_debug_enabled")
	set(value): _dbg_set("debug.camera_debug_enabled", value)

# Free-pan camera override MOVED to its production owner (#500, ADR-0140 dec. 5):
# `PlayerCamera.FREE_CAMERA_SLUG` / `PlayerCamera.free_camera()`, on `camera.*`.
# All three readers are Battlefield's and all three poll, so the signal that used to
# live here delivered to nobody — see the note at the new home.

# Map loading debug logging
var map_debug_enabled: bool:
	get: return _dbg_get(false, "debug.map_debug_enabled")
	set(value): _dbg_set("debug.map_debug_enabled", value)

# === Effect Subsystem Debug Flags ===
# Screen: background color, flash effects
var screen_debug_enabled: bool:
	get: return _dbg_get(false, "debug.screen_debug_enabled")
	set(value): _dbg_set("debug.screen_debug_enabled", value)

# Palette: unit/map color tinting
var palette_debug_enabled: bool:
	get: return _dbg_get(false, "debug.palette_debug_enabled")
	set(value): _dbg_set("debug.palette_debug_enabled", value)

# Particle: emitter spawn, physics
var particle_debug_enabled: bool:
	get: return _dbg_get(false, "debug.particle_debug_enabled")
	set(value): _dbg_set("debug.particle_debug_enabled", value)

# === Feedback-HUD feature toggles (ADR-0063, #89/#90) ===
# Over-unit billboards, defaulting ON (current behavior). These are FEATURE gates,
# not logging — kept here so they ride the same Tune-backed F3 toggle plumbing.
# Diagnostic use: turn both OFF to confirm whether the over-unit HUD is involved in
# the Fire-on-caster compositing artifact (if it persists with these off, it isn't).
# Damage / heal numbers that pop on hp_changed (FeedbackHudManager._on_hp_changed).
var feedback_numbers_enabled: bool:
	get: return _dbg_get(true, "debug.feedback_numbers_enabled")
	set(value): _dbg_set("debug.feedback_numbers_enabled", value)

# The charge "speech bubble" over a unit while it is SPELL_CHARGING (the placeholder
# charge indicator, StatusBubble3D CHARGE_ICON). Gates only the charge bubble; a
# persistent status icon (poison etc.) is unaffected.
var feedback_charge_bubble_enabled: bool:
	get: return _dbg_get(true, "debug.feedback_charge_bubble_enabled")
	set(value): _dbg_set("debug.feedback_charge_bubble_enabled", value)

# Timeline: frame sequencing, phase transitions
var timeline_debug_enabled: bool:
	get: return _dbg_get(false, "debug.timeline_debug_enabled")
	set(value): _dbg_set("debug.timeline_debug_enabled", value)

# Iteration debugging: temporary verbose logging during bug investigation
# Gate any temporary debug prints behind this flag so user can toggle spam
var iteration_debug_enabled: bool:
	get: return _dbg_get(false, "debug.iteration_debug_enabled")
	set(value): _dbg_set("debug.iteration_debug_enabled", value)

# Chapel-cinematic per-opcode trace. When enabled, ScenarioVM emits a JSONL
# row after every dispatched opcode with the post-state of every spawned
# unit (visibility, facing cardinal + 12-bit, type1 anim_id/frame, last
# painted frame, cinematic walker state). Pair with the PCSX-side probe at
# research/lua_scripts/probe_chapel_opcodes.lua to diff PSX vs Godot.
# Toggle via `--chapel-trace` on the command line, or set this flag from
# the F3 Scenario panel before scene reload.
var chapel_trace_enabled: bool = false
var chapel_trace_path: String = ""

# The STATE census to STDOUT (ADR-0177 Amendment 3). [StateDebugPanel] is an F3 panel and
# the F3 window is a thing a person LOOKS at; with this armed the same eight rows are printed
# whenever one of them CHANGES, so a run reaching a state nobody was watching still leaves a
# record of it. That is the whole reason it exists: all four Orbonne bugs were found at a
# keyboard, and the run log said nothing about any of them. Toggle via `--state-census`.
var state_census_enabled: bool = false

# EVTCHR wrong-row detector (HANDOFF_ramza_wrong_sprite_detector.md). When ON,
# ScenarioPlayerScene polls uid 0x02's BODY material every frame and flags the
# "row 1 instead of row 5" bug (EVTCHR atlas still bound while a low-y TYPE1
# rect is written), then auto-quits with a non-zero exit code on FAIL so it
# doubles as a regression gate. Also gates the per-write causal timeline in
# SpriteLayerManager.{load_cinematic_frame,load_frame_by_id}. Toggle via
# `--evtchr-row-detect` on the command line.
var evtchr_row_detect_enabled: bool:
	get: return _dbg_get(false, "debug.evtchr_row_detect_enabled")
	set(value): _dbg_set("debug.evtchr_row_detect_enabled", value)

# Land-skirt logging LEFT this file at #500 — a system logs itself (ADR-0140
# dec. 5), so the gate is SkirtGeometryGenerator's static var on `skirt.land_debug`.

# Animation state transition debugging: logs rejected locked state transitions
var transition_debug_enabled: bool:
	get: return _dbg_get(false, "debug.transition_debug_enabled")
	set(value): _dbg_set("debug.transition_debug_enabled", value)

## Pose-octant camera-offset calibration knob (ADR-0053). The Path D idle
## dispatcher in `_paint_body_variant` reads
## `AnimationStateController.get_pose_octant(facing_angle, psx_camera_angle)`,
## which composes facing with the SAME continuous PSX angle the polygon-cull
## shader consumes (one angle convention across both renderers). PSX
## additionally adds the camera-rotation global `DAT_800a7786` (full 12-bit
## world camera angle, updated by `FUN_8006fb20`); this knob folds it in
## without re-baking the formula. Units: 12-bit angle steps (0x100 = 22.5°,
## one pose_octant).
##
## Default `0x400` derivation (2026-06-27 chapel calibration):
##   PSX `DAT_800a7786` = 0x0E00 at the chapel scenario_1 just-after-spawn
##     beat (read from `orbonne_prayer_mid_dialog.sstate` via PCSX-Redux).
##   Godot `PSXDisplay.live_camera_angle` = 0xE00 at the same beat (from the
##     `[PSXAngle]` log line after `_spawn_units` and before the first
##     Camera opcode rotates the view).
##   offset = (DAT_800a7786 + POSE_OCTANT_CAMERA_BASELINE_12BIT - psx_cam) & 0xfff
##          = (0xE00 + 0x400 - 0xE00) & 0xfff = 0x400.
## Lands inside the user's visually-confirmed plateau (0x400..0x500 both
## render Agrias + Priest facing correctly — consecutive pose_octants
## share frames on the SUB_A tent's plateau pairs).
var pose_octant_camera_offset_12bit: int:
	get: return int(_dbg_get_num(float(0x400), "debug.pose_octant_camera_offset_12bit"))
	set(value): _dbg_set_num("debug.pose_octant_camera_offset_12bit", float(value))

# `psx_camera_angle_12bit` was DELETED here (#590). It was a mirror of the
# `psx_camera_angle` global shader uniform, written by PlayerCamera and read by
# `Unit._build_view` and `CameraRelativeRenderer` — i.e. `Debug` hosting live
# camera state for two other systems, which is not a debug flag under any
# reading of ADR-0140 dec. 5. It is `PSXDisplay.live_camera_angle` now, beside
# the five other global shader parameters that port pushes (ADR-0171 dec. 1).

# Reaction debug logging (evasion rolls, hit/miss detection, reaction animations)
var reaction_debug_enabled: bool:
	get: return _dbg_get(false, "debug.reaction_debug_enabled")
	set(value): _dbg_set("debug.reaction_debug_enabled", value)

# GPU combat system debug logging (simulator init, buffer creation, timing)
var gpu_debug_enabled: bool:
	get: return _dbg_get(false, "debug.gpu_debug_enabled")
	set(value): _dbg_set("debug.gpu_debug_enabled", value)

# Emitter debug logging (particle emitters)
var emitter_debug_enabled: bool:
	get: return _dbg_get(false, "debug.emitter_debug_enabled")
	set(value): _dbg_set("debug.emitter_debug_enabled", value)

# Combat simulation debug logging
var simulation_debug_enabled: bool = false

# Game speed multiplier for stress testing (1.0 = normal, 2.0 = 2x, 5.0 = 5x, 10.0 = 10x)
var time_scale: float = 1.0
signal time_scale_changed(value: float)

# Show depth as grayscale for debugging. Tune tunable (ADR-0068 decision 10): getter
# coalesces `debug.show_depth`, setter routes through Tune, and _apply_show_depth
# (bound in _ready) emits show_depth_changed — so a dashboard scrub reaches the units'
# _on_show_depth_changed shader write, not just a direct assignment.
var _show_depth_applied: Variant = null
var show_depth: bool:
	get: return _dbg_get(false, "debug.show_depth")
	set(value): _dbg_set("debug.show_depth", value)

func _apply_show_depth(on: bool) -> void:
	if on == _show_depth_applied:
		return
	_show_depth_applied = on
	show_depth_changed.emit(on)

# Show a marker at each unit's computed OT depth-sample center (ADR-0009 tuning)
var show_depth_center: bool:
	get: return _dbg_get(false, "debug.show_depth_center")
	set(value): _dbg_set("debug.show_depth_center", value)

# PSX ordered dithering + 15-bit quantization (global shader uniform). Backed by
# the Tune tunable "render.psx_dither_enabled" (ADR-0068 decision 10 — debug prefs
# are tunables too). The bool analog of PSXDisplay.live_par: the getter coalesces
# override-over-default, the setter routes writes through Tune, and `_apply_dither`
# (bound in _ready) pushes the `psx_dither_enabled` global shader parameter + emits
# psx_dither_changed. The default has ONE home — project.godot [shader_globals] —
# sourced into `_dither_default` in _ready (was a rival `= true` literal here).
var _dither_default: bool = true
var _dither_applied: Variant = null  # last value pushed to shader/signal, for dedup

var psx_dither_enabled: bool:
	get:
		# @tool guard: in the editor Tune is a placeholder instance (Tune.gd is not
		# @tool), so route around it and report the code default. At runtime the
		# coalescing read is authoritative.
		if Engine.is_editor_hint():
			return _dither_default
		return Tune.get_value("render.psx_dither_enabled")
	set(value):
		if Engine.is_editor_hint():
			return
		if psx_dither_enabled == value:
			return
		Tune.set_value("render.psx_dither_enabled", value)
signal psx_dither_changed(value: bool)


## Bound to "render.psx_dither_enabled" in _ready: push the coalesced value to the
## `psx_dither_enabled` global shader parameter and notify subscribers. Deduped so
## an unchanged re-apply is a no-op (preserves the old setter's semantics).
func _apply_dither(on: bool) -> void:
	if on == _dither_applied:
		return
	_dither_applied = on
	RenderingServer.global_shader_parameter_set("psx_dither_enabled", on)
	psx_dither_changed.emit(on)

# === Performance monitor (PerfMonitor autoload + F3 Performance tab) ===
# Always-on corner HUD: FPS / frame time / GPU vs CPU split / draw calls / particles
# Tune tunable (ADR-0068 decision 10): getter coalesces `debug.perf_hud_enabled`,
# setter routes through Tune, and _apply_perf_hud (bound in _ready) emits the signal —
# so a dashboard scrub reaches PerfMonitor/PerfHUD, not just a direct assignment.
var _perf_hud_applied: Variant = null
var perf_hud_enabled: bool:
	get: return _dbg_get(false, "debug.perf_hud_enabled")
	set(value): _dbg_set("debug.perf_hud_enabled", value)

func _apply_perf_hud(on: bool) -> void:
	if on == _perf_hud_applied:
		return
	_perf_hud_applied = on
	perf_hud_toggled.emit(on)

# Spike log: record any frame whose real frame_time_ms exceeds the threshold
var perf_spike_log_enabled: bool:
	get: return _dbg_get(true, "debug.perf_spike_log_enabled")
	set(value): _dbg_set("debug.perf_spike_log_enabled", value)

# Threshold (in ms) above which a frame is logged as a spike. 33ms = sub-30fps.
var perf_spike_threshold_ms: float:
	get: return _dbg_get_num(33.0, "debug.perf_spike_threshold_ms")
	set(value): _dbg_set_num("debug.perf_spike_threshold_ms", value)

signal perf_hud_toggled(value: bool)

# === Regression Testing Settings ===
# When true, the game is running in regression test mode
var regression_test_mode: bool = false

# Name of the test to run (or "all" for all tests)
var test_name: String = ""

# If true, save results as new baselines
var update_baseline: bool = false

# Custom RNG seed for deterministic tests
var test_seed: int = 42

# Combat RNG seed (0 = random each reset, >0 = fixed seed for reproducibility)
var combat_seed: int = 0

# When true, next scene load will auto-place units and start combat (reset after use)
var run_with_seed: bool = false

# The actual seed used for the current battle (set by GPUArena on startup)
var active_combat_seed: int = -1

# The scenario the arena/effect viewer boots into, backed by the AUTOSAVE Tune slug
# `scenario.active_id` (ADR-0068). Assigning it — what the F3 Scenario picker does on
# select — commits to the staging file in the same gesture, so the pick survives an app
# restart, not just a scene reload. -1 means "use the scene's default_scenario_id". The
# picker WIDGET stays a raw dynamic dropdown (tune-exempt in ScenarioDebugPanel); only
# the VALUE is Tune-backed. DebugConfig OWNS the slug (decision 12) — no panel fan-out.
const _ACTIVE_SCENARIO_SLUG := "scenario.active_id"
var active_scenario_id: int:
	get:
		if Engine.is_editor_hint():
			return -1
		if not Tune.is_registered(_ACTIVE_SCENARIO_SLUG):
			Tune.bind(_ACTIVE_SCENARIO_SLUG, -1, {}, Tune.Persist.AUTOSAVE)
		return int(Tune.get_value(_ACTIVE_SCENARIO_SLUG))
	set(value):
		# SESSION-ONLY seed (survives a scene reload via the live override, NOT the
		# disk). A scene's BOOT DEFAULT (GPUArena.gd assigns default_scenario_id here)
		# must not pin a default nobody explicitly chose into the git-tracked overrides
		# — else every arena launch rewrites config and leaks its default to the effect
		# viewer. An explicit user PICK persists instead via set_active_scenario_id().
		if Engine.is_editor_hint():
			return
		Tune.set_value(_ACTIVE_SCENARIO_SLUG, value)

# Explicit pick: set the live value AND commit it to the staging file so the choice
# STICKS across an app restart with no Pin (AUTOSAVE, ADR-0068). The F3 Scenario
# picker calls this on select. `path` is a test seam: EMPTY takes Tune's staging file (the
# repo file in the game, NOTHING in a test process — ADR-0281), and an explicit path lets a
# guard round-trip a temp file.
func set_active_scenario_id(value: int, path: String = "") -> void:
	if Engine.is_editor_hint():
		return
	Tune.set_value(_ACTIVE_SCENARIO_SLUG, value)
	Tune.commit_slug(_ACTIVE_SCENARIO_SLUG, path)

# Effects to test (comma-separated, e.g., "E001,E020")
var test_effects: Array[String] = []

# Auto-start combat in GPUArena (for headless testing)
var combat_autostart: bool = false

## The slug behind [member gambit_auto_deploy]. Named so the F3 view row and the tests that
## turn it OFF spell it once (`gambit.*`, not `debug.*`: it changes what the host DOES, and
## `debug.*` is this file's logging-flag namespace).
const GAMBIT_AUTO_DEPLOY_SLUG := "gambit.auto_deploy"

## Open [GambitBattle]'s deployment with the zone ALREADY FILLED — the squad standing on the
## first n zone tiles, exactly as `DeploymentAssignment.auto_fill` would place it.
##
## A testing convenience, and deliberately NOT [member combat_autostart]: that one fills AND
## commits, so it lands you in a running battle with nothing to edit. This one only PLACES.
## The deployment stays open, every editing verb still works, and the battle still starts on
## your Space — so a scene reload costs one keypress instead of five picks.
##
## AUTOSAVE (green in the panel): ticking the box commits the slug, so it stays ticked across
## an app restart. That is the point — a toggle you had to re-arm every launch would not save
## the gesture it exists to save. The three host-subclass tests turn it off explicitly for the
## same reason they turn `combat_autostart` off: the assignment is their subject.
var gambit_auto_deploy: bool:
	get: return _dbg_get(false, GAMBIT_AUTO_DEPLOY_SLUG)
	set(value): _dbg_set(GAMBIT_AUTO_DEPLOY_SLUG, value)


## W7 stress fixture: pad EACH team to this many units (0 = off, the shipped cast).
## A perf lever, not a gameplay path — CLI only, deliberately NOT `Tune`-bound, so it
## cannot be persisted into a run that did not ask for it (the trap the retired
## `simulation.skip_march` slug set, R24/F27). `GPUArena` is its only reader.
var stress_units: int = 0

# Auto-reset combat after victory/defeat (for stress testing name bug)
var combat_auto_reset: bool = false
var combat_reset_count: int = 0  # Track number of resets for reporting

# === Placement Validation Settings ===
# Path to export placements after auto-placement completes
var export_placements_path: String = ""

# Path to load placements from (skips normal placement, uses fixed positions)
var load_placements_path: String = ""

# Scenario id to boot ScenarioPlayer into, from `--scenario=N` (-1 = use picker /
# scene default). For headful verification runs that bypass the F3 picker.
var scenario_override: int = -1

# Battle group root to LAUNCH the navigator walk into, from `--battle=N` (-1 = none).
# "Play battle N" is a SEEK into NavigatorMain, not a second combat host (ADR-0264
# dec. 4): the walk is planned as that one battle group and begun at its `pre_battle`
# action, so the opener fast-forwards and the battle inherits the spine's framing,
# clock and facing. Addressing is scenario-id-shaped — a battle group's root IS its
# setup record's id, so `--battle=9` is Gariland, the id `--scenario=9` already names.
#   godot --path . res://assets/scenes/NavigatorMain.tscn -- --battle=9
# NOT consumed: the process was launched to play this battle, so a Ctrl+R replays it.
var battle_seek_root: int = -1

# Begin the `--battle=N` walk one action earlier, at the `opener`, and WATCH it play at
# normal speed instead of fast-forwarding it (`--watch-opener`). Ignored without
# `--battle=`. The framing it settles on is the same either way; this is for looking at
# the cinematic that settles it.
var battle_watch_opener: bool = false

# Arm the navigator's turn stop for this launch (`--stop-on-turn`), the CLI form of the
# F3 → Navigator "Stop on every turn" toggle. `NavigatorMain.stop_on_turn_armed` reads
# this OR the `navigator.stop_on_turn` slug — one launch REQUEST beside one stored
# preference, the same relationship `--battle=` has with the seek panel.
#
# It exists because the toggle is AUTOSAVE (ADR-0068): ticking it from a script means
# committing a value into the tracked `config/tune_overrides.json`, and a stray value in
# that file has already hung every navigator walk on `main` once. A launch flag cannot
# leak into anyone else's tree, which is the whole reason ADR-0051 dec. 5 allows one.
var battle_stop_on_turn: bool = false

# PC to fast-play (seek) to on boot, from `--rewind-pc=N` (-1 = play from the
# start). The command-line form of double-clicking an instruction in the F3
# Scenario VM panel: `ScenarioPlayerScene` seeds `ScenarioDebugSession` with it, so
# a seek is reproducible from a shell instead of only by hand.
var scenario_rewind_pc: int = -1

# === Debug Overlay Settings ===
# Whether the debug overlay is currently visible (F3 toggle)
var debug_overlay_visible: bool = false:
	set(value):
		if debug_overlay_visible != value:
			debug_overlay_visible = value
			debug_overlay_toggled.emit(value)

# Currently active tab in the debug overlay (0=General, 1=UI, 2=Font)
var debug_overlay_active_tab: int = 0

signal debug_settings_changed()
signal show_depth_changed(value: bool)  # emitted by the show_depth setter
signal debug_overlay_toggled(visible: bool)
signal run_with_seed_requested()  # emitted by request_run_with_seed()

# Signal emitted before auto-quit to allow final validation
signal quit_requested()

# Auto-quit timer for regression testing
var _quit_timer: float = 0.0
var _quit_after: float = 0.0

# Error tracking for test exit codes
var _error_count: int = 0

func _ready():
	"""Check environment variables and command line args for regression test mode"""
	# Source the dither default from its single home (project.godot [shader_globals])
	# and bind the tunable, so a committed override reaches the shader on the first
	# frame (ADR-0068 decision 5). Tune is the first autoload, so its overrides are
	# already resident here. Skipped in the editor: this @tool script's _ready also
	# runs at edit time, where Tune is a placeholder instance that cannot be called.
	if not Engine.is_editor_hint():
		var decl: Dictionary = ProjectSettings.get_setting("shader_globals/psx_dither_enabled", {})
		_dither_default = bool(decl.get("value", true))
		Tune.bind_update(self, "render.psx_dither_enabled", _dither_default, _apply_dither)
		# The setter+signal debug flags (decision 10): bind so a `debug.*` override
		# change — from any scrub, including the generated dashboard — drives the
		# _apply_* that emits the flag's signal to its consumers. The default is false;
		# the boot emit reaches no one (consumers connect in their own later _ready).
		Tune.bind_update(self, "debug.show_depth", false, _apply_show_depth)
		Tune.bind_update(self, "debug.perf_hud_enabled", false, _apply_perf_hud)
		# Sticky simulation setup (ADR-0068 AUTOSAVE): the combat seed is
		# owned HERE (decision 12) and read as the boot DEFAULT so a value dialed in the
		# Simulation panel survives an app restart. Read BEFORE _check_command_line_args so
		# an explicit --combat-seed CLI flag still overrides the persisted
		# pref. The seed slug stores raw text ("" = random), matching the panel's LineEdit.
		# bind returns the coalesced value, so this one-shot boot read registers + reads in one
		# call (the get_stack cost is paid once, at boot — fine for a non-hot path).
		combat_seed = str(Tune.bind("simulation.combat_seed", "", {}, Tune.Persist.AUTOSAVE)).to_int()
		# The gambit auto-deploy pref, bound HERE rather than at its getter so the class is
		# AUTOSAVE from the first read and the F3 view row resolves an owner at boot (a
		# `_dbg_get` bind would register it TUNABLE, and the box would need a Pin).
		Tune.bind(GAMBIT_AUTO_DEPLOY_SLUG, false, {}, Tune.Persist.AUTOSAVE)
	_check_command_line_args()

func request_run_with_seed() -> void:
	"""Ask listeners to (re)run the scene with the current debug seed.
	A command signal — emitted here so DebugConfig owns its own signal."""
	run_with_seed_requested.emit()

func _check_command_line_args():
	"""Parse command line args for debugging and regression testing."""
	var args = OS.get_cmdline_user_args()  # Args after "--"

	for arg in args:
		if arg.begins_with("--time-scale="):
			var scale = float(arg.split("=")[1])
			if scale >= 1.0 and scale <= 20.0:
				set_time_scale(scale)
				print("[DebugConfig] Time scale from CLI: %.1fx" % scale)
		elif arg.begins_with("--quit-after="):
			_quit_after = float(arg.split("=")[1])
			if _quit_after > 0:
				print("[DebugConfig] Auto-quit after %.1f seconds" % _quit_after)
		elif arg.begins_with("--test="):
			test_name = arg.split("=")[1]
			regression_test_mode = true
			print("[DebugConfig] Regression test mode: %s" % test_name)
		elif arg == "--update-baseline":
			update_baseline = true
			print("[DebugConfig] Update baseline mode enabled")
		elif arg.begins_with("--seed="):
			test_seed = int(arg.split("=")[1])
			print("[DebugConfig] Test seed: %d" % test_seed)
		elif arg.begins_with("--effects="):
			var effects_str = arg.split("=")[1]
			test_effects.clear()
			for effect in effects_str.split(","):
				test_effects.append(effect.strip_edges())
			print("[DebugConfig] Test effects: %s" % str(test_effects))
		elif arg == "--combat-autostart":
			combat_autostart = true
			print("[DebugConfig] Combat autostart enabled")
		elif arg.begins_with("--stress-units="):
			stress_units = maxi(0, int(arg.split("=")[1]))
			print("[DebugConfig] Stress fixture: pad each team to %d units" % stress_units)
		elif arg.begins_with("--combat-seed="):
			combat_seed = int(arg.split("=")[1])
			print("[DebugConfig] Combat seed from CLI: %d" % combat_seed)
		elif arg == "--combat-auto-reset":
			combat_auto_reset = true
			print("[DebugConfig] Combat auto-reset enabled (will restart after each battle)")
		elif arg == "--iteration-debug":
			iteration_debug_enabled = true
			print("[DebugConfig] Iteration debug enabled")
		elif arg == "--chapel-trace":
			chapel_trace_enabled = true
			print("[DebugConfig] Chapel-cinematic opcode trace enabled")
		elif arg.begins_with("--chapel-trace-path="):
			chapel_trace_path = arg.split("=", true, 1)[1]
			chapel_trace_enabled = true
			print("[DebugConfig] Chapel-cinematic opcode trace enabled → %s" % chapel_trace_path)
		elif arg == "--evtchr-row-detect":
			evtchr_row_detect_enabled = true
			print("[DebugConfig] EVTCHR wrong-row detector enabled (uid 0x02 BODY material poll + auto-quit gate)")
		elif arg == "--state-census":
			state_census_enabled = true
			print("[DebugConfig] STATE census enabled — the F3 State panel also prints every change")
		elif arg == "--map-debug":
			map_debug_enabled = true
			print("[DebugConfig] Map debug enabled (strategy-phase sourcing prints)")
		elif arg == "--audio-monitor":
			# The gate belongs to the sound package (ADR-0140 dec. 5), so this writes its
			# DECLARED slug rather than a flag here. The adapter binds it later in the
			# autoload order and the override coalesces on that bind.
			Tune.set_value("audio.monitor_enabled", true)
			print("[DebugConfig] Audio monitor enabled (per-second SFX scheduler/rail + Master clip)")
		elif arg == "--perf-debug":
			# Surface CombatLoop's periodic per-bucket perf report (gpu/state/visual ms)
			# without flipping the regular gpu_debug flag's other side effects.
			gpu_debug_enabled = true
			print("[DebugConfig] Perf debug enabled (CombatLoop bucket prints)")
		elif arg == "--debug-overlay":
			# Open the F3 dashboard on boot. W4 measures what the overlay costs WHILE
			# OPEN, and until this existed there was no way to get an automated run into
			# that state: `GPUArena` deleted its unconditional `show_overlay()` (#866) and
			# the strategy-phase call is gated on `not combat_autostart`, so every
			# auto-deploy run measured the CLOSED arm no matter what it was asked for.
			# `DebugOverlay` is a later autoload and is not listening yet, so it re-reads
			# this flag in its own `_ready` rather than hearing the toggle.
			debug_overlay_visible = true
			print("[DebugConfig] Debug overlay opened from CLI (W4 open-arm measurement)")
		elif arg.begins_with("--scenario="):
			# Boot ScenarioPlayer straight into a scenario id (== ScenarioDatabase
			# key), bypassing the F3 picker — for headful verification runs.
			scenario_override = int(arg.split("=")[1])
			print("[DebugConfig] Scenario override from CLI: %d" % scenario_override)
		elif arg.begins_with("--rewind-pc="):
			# Seek (high-speed fast-play) to this PC on boot — the CLI form of the F3
			# panel's double-click-to-rewind, so a seek can be reproduced headfully.
			scenario_rewind_pc = int(arg.split("=")[1])
			print("[DebugConfig] Scenario rewind PC from CLI: %d" % scenario_rewind_pc)
		elif arg.begins_with("--battle="):
			# Launch the navigator straight into ONE battle group (ADR-0264) —
			# `NavigatorMain` plans that group alone and begins at its pre_battle action.
			battle_seek_root = int(arg.split("=")[1])
			print("[DebugConfig] Battle launch from CLI: group root %d" % battle_seek_root)
		elif arg == "--stop-on-turn":
			# Arm the navigator's turn stop for this launch — the CLI form of the F3
			# toggle, and the only way to reach that state from a shell without writing
			# the tracked tune-override file (ADR-0265).
			battle_stop_on_turn = true
			print("[DebugConfig] Navigator turn stop armed from CLI")
		elif arg == "--watch-opener":
			# Begin the `--battle=` walk at the opener and watch it play, rather than
			# fast-forwarding it inside the seek.
			battle_watch_opener = true
			print("[DebugConfig] Battle launch will play the opener at normal speed")
		elif arg.begins_with("--export-placements="):
			export_placements_path = arg.split("=")[1]
			print("[DebugConfig] Export placements to: %s" % export_placements_path)
		elif arg.begins_with("--load-placements="):
			load_placements_path = arg.split("=")[1]
			print("[DebugConfig] Load placements from: %s" % load_placements_path)

func _process(delta: float):
	"""Handle auto-quit timer (uses real time, not scaled time)"""
	if _quit_after > 0:
		# Use unscaled delta for real-time counting
		_quit_timer += delta / Engine.time_scale
		if _quit_timer >= _quit_after:
			quit_requested.emit()  # Allow tests to run final validation
			var exit_code = 1 if _error_count > 0 else 0
			print("[DebugConfig] Auto-quit (%.1fs) - %d errors, exit code %d" % [_quit_after, _error_count, exit_code])
			get_tree().quit(exit_code)

func record_error(message: String = ""):
	"""Record an error for test exit code tracking"""
	_error_count += 1
	if message:
		push_error(message)

func cycle_time_scale():
	"""Toggle between paused (0) and normal (1)"""
	if time_scale == 0.0:
		time_scale = 1.0
	else:
		time_scale = 0.0

	Engine.time_scale = time_scale
	print("[DebugConfig] %s" % ("PAUSED" if time_scale == 0.0 else "RUNNING"))
	time_scale_changed.emit(time_scale)
	debug_settings_changed.emit()

func set_time_scale(scale: float):
	"""Set specific time scale value"""
	time_scale = scale
	Engine.time_scale = time_scale
	print("[DebugConfig] Time scale: %.1fx" % time_scale)
	time_scale_changed.emit(time_scale)
	debug_settings_changed.emit()
