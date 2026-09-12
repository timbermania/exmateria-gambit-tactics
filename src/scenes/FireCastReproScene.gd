extends GPUCombatTestBase
## Deterministic "cast Fire" reproduction scene (handoff 2026-07-30).
##
## A purpose-built harness for OBSERVING the caster-side Fire artifact — the "extra
## fire / particle / flash" reported when a Wizard casts Fire on/next to a unit. The
## prior repro (EffectViewer's fixed geometry) never overlapped caster and effect, so
## it failed to recreate the bug; this scene stands up the REAL GPU combat cinematic
## path (CombatLoop → CinematicManager → EffectManager.spawn_cinematic_effect) with a
## one-button trigger, so the artifact reproduces every time it's pressed.
##
## Reuses the whole GPUCombatTestBase harness (units from configs, a live CombatLoop,
## the GPU simulator, combat UI, debug panels). Deviations from a normal GPU test:
##   - All three units default to a WAIT gambit, so combat is live (ATB runs, the
##     cinematic edge can fire) but nobody acts until an F3 button arms them.
##   - The arm buttons inject a real gambit via gpu_simulator.set_unit_gambits; the
##     unit acts on its next turn, then auto-disarms back to WAIT (one-shot) when it
##     returns to IDLE, so each press is a single clean repro.
##   - player_camera is wired into the loop (the base test host leaves it null) so the
##     Fire cinematic actually takes over the camera — "auto drop into cinematic mode".
##   - Huge HP + huge max_ticks so nothing dies and the battle never times out; the
##     scene persists as an observation rig (the base's victory/timeout quit never fires).
##
## Layout (flat MapComposer default; +X = NORTH, +Z = EAST):
##   Wizard  (team0) @ (5,7)  — Black Mage sprite 0x37, casts Fire (E016, ct=4)
##   Target  (team1) @ (6,7)  — d1 east of Wizard; Fire's nearest-enemy pick
##   Squire  (team1) @ (3,7)  — d2 west; Male Squire sprite 0x60, Dashes the Wizard
## Fire (range 4, area 1) hits only the adjacent Target; the Squire (d2, move 3)
## approaches the Wizard and Dashes it (range 1). Nearest-enemy resolution is
## unambiguous: Target is strictly nearer to the Wizard than the Squire.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const CursorRig = ExMateriaBattlefield.CursorRig


const ABILITY_FIRE := 16   # E016, charge_time 4 -> cinematic
const ABILITY_DASH := 147  # Squire "Dash" (effect 154, ct 0 -> non-cinematic)

const WIZARD_IDX := 0
const TARGET_IDX := 1
const SQUIRE_IDX := 2

# Unit indices armed and awaiting their turn (presence = armed). Cleared the moment
# the unit commits to its action (enters SPELL_CHARGING / ACTING), so each button is
# a clean one-shot — the in-flight cast finishes but the gambit won't re-fire.
var _armed: Dictionary = {}   # unit_idx -> true
var _panel = null
var cursor_rig: CursorRig = null

# The cursor NODE, by path — a scene-tree coupling, not a type reference (ADR-0196
# dec. 2). The published port is `cursor_rig` (ADR-0206).
@onready var tile_cursor: Node3D = get_node_or_null("TileCursor")


func get_test_name() -> String:
	return "Fire-Cast Repro"


func _ready() -> void:
	# Persist as an observation rig — never time out. (start_battle reads this into
	# the loop via _ensure_loop, so set it before the base runs.)
	max_ticks = 999999
	# Real-time, not the 4x the test host runs at — this is a rig to watch, not a
	# fast regression test. (The base sets Engine.time_scale = test_time_scale.)
	test_time_scale = 1.0
	# Await the full base boot (unit spawn, loop + simulator, the 1s settle, and the
	# auto_start that flips combat_active on) before touching the live loop below.
	await super._ready()
	# Seed the on-grid tile cursor so the camera moves/rotates like a normal scene
	# (WASD walks the cursor, Q/E rotate) — mirrors EffectViewerScene/GPUArena.
	if tile_cursor:
		cursor_rig = CursorRig.bind(self, tile_cursor, player_camera)
		# #589: the cursor's player-driven step is an `Audio` cue, and the cue name
		# is host vocabulary (`OpeningMenu` plays the same one). Wired by the root
		# that OWNS the node -- a cursor handed onward (FormationMapHost.bind_map)
		# is already wired by its owner.
		BattlefieldWiring.wire_cursor(cursor_rig)
		cursor_rig.seed_from_map(map, Vector2i(5, 7))
	# Surface the F3 overlay on the repro panel so the buttons are one keypress away.
	DebugOverlay.show_overlay()
	DebugOverlay.switch_to_tab(DebugOverlay.Category.SIMULATION)


func _ensure_loop() -> void:
	# Wire the production PlayerCamera into the loop so the Fire cinematic can take
	# over the camera (the base test host deliberately leaves this null). Everything
	# else about the loop is the base's.
	super._ensure_loop()
	if combat_loop and player_camera:
		combat_loop.player_camera = player_camera


func _setup_debug_panels() -> void:
	super._setup_debug_panels()
	_panel = preload("res://src/debug/FireCastReproPanel.gd").new()
	_panel.setup(self)
	DebugOverlay.register_panel(_panel, DebugOverlay.Category.SIMULATION)


# === Unit + gambit config =====================================================

func get_team0_unit_configs() -> Array:
	return [
		{
			"name": "Wizard",
			"pos_x": 5, "pos_z": 7,
			"hp": 9999, "max_hp": 9999,
			"pa": 5, "ma": 12, "wp": 1,
			"brave": 50, "faith": 100,
			"mp": 99, "max_mp": 99,
			"speed": 100, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x37,  # Male Black Mage ("Wizard")
		},
	]


func get_team1_unit_configs() -> Array:
	return [
		{
			"name": "Target",
			"pos_x": 6, "pos_z": 7,
			"hp": 9999, "max_hp": 9999,
			"pa": 5, "ma": 5, "wp": 1,
			"brave": 50, "faith": 100,
			"mp": 0, "max_mp": 0,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x05,  # generic humanoid stand-in
		},
		{
			"name": "Squire",
			"pos_x": 3, "pos_z": 7,
			"hp": 9999, "max_hp": 9999,
			"pa": 12, "ma": 5, "wp": 5,
			"brave": 50, "faith": 50,
			"mp": 0, "max_mp": 0,
			"speed": 100, "move": 3, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x60,  # Male Squire
		},
	]


func get_gambits_for_unit(_unit_idx: int, _team: int) -> Array:
	# Everyone idles until an F3 button arms them.
	return [make_wait_gambit()]


# === Arm / disarm (F3 panel callbacks) ========================================

func arm_wizard_fire() -> void:
	if not gpu_simulator:
		return
	gpu_simulator.set_unit_gambits(0, WIZARD_IDX,
		[make_spell_gambit(ABILITY_FIRE, GPUConstants.TARGET_NEAREST_ENEMY)])
	_armed[WIZARD_IDX] = true
	_set_status("Wizard armed — casts Fire on the Target next turn (auto-cinematic).")


func arm_squire_dash() -> void:
	if not gpu_simulator:
		return
	# Dash is a physical skill; ACTION_ABILITY routes it through the ability
	# dispatcher. Nearest enemy of the Squire (team1) is the Wizard (the only team0
	# unit); with move 3 it approaches to range 1, then Dashes.
	gpu_simulator.set_unit_gambits(0, SQUIRE_IDX,
		[make_ability_gambit(ABILITY_DASH, GPUConstants.TARGET_NEAREST_ENEMY)])
	_armed[SQUIRE_IDX] = true
	_set_status("Squire armed — approaches and Dashes the Wizard next turn.")


func disarm_all() -> void:
	if not gpu_simulator:
		return
	for idx in [WIZARD_IDX, TARGET_IDX, SQUIRE_IDX]:
		gpu_simulator.set_unit_gambits(0, idx, [make_wait_gambit()])
	_armed.clear()
	_set_status("Disarmed — all units waiting.")


func _disarm(unit_idx: int) -> void:
	if gpu_simulator:
		gpu_simulator.set_unit_gambits(0, unit_idx, [make_wait_gambit()])
	_armed.erase(unit_idx)


# === One-shot state machine ===================================================

## One-shot: disarm the moment an armed unit commits to its action (enters
## SPELL_CHARGING for a charged spell, or ACTING for an instant skill). Resetting the
## gambit to WAIT here doesn't cancel the in-flight action — that decision is already
## committed — it just stops the unit re-casting on its next ATB cycle. Without this,
## the still-armed gambit re-fires every turn (observed as a double Fire cast).
func on_state_changed(unit_idx: int, _old_state: int, new_state: int) -> void:
	if not _armed.has(unit_idx):
		return
	if new_state == GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING \
			or new_state == GPUConstants.LOGICAL_ACTIVITY_ACTING:
		_disarm(unit_idx)
		var who := "Wizard" if unit_idx == WIZARD_IDX else "Squire"
		_set_status("%s acting — disarmed (press a button to repeat)." % who)


func _set_status(text: String) -> void:
	print("[FireCastRepro] %s" % text)
	if _panel and is_instance_valid(_panel):
		_panel.set_status(text)
