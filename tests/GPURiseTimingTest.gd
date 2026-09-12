extends GPUCombatTestBase

## GPU Rise Timing Test
##
## Isolates the question "when does the Reraise carrier visibly stand up
## relative to the cinematic's CPU-side keyframe processing?"
##
## Same battle setup as GPUReraiseTest (lethal attacker vs reraise carrier),
## but instead of asserting the final outcome we record a timeline of five
## semantic events and check the two deltas the bug surfaced:
##
##   1. t_getting_up - t_hit_react      should be ~contemporaneous.
##      The runtime PhaseBlock fires HIT_REACT mid-cinematic (effect_frame
##      ≈ 99). The carrier's activity should flip to GETTING_UP at roughly
##      that beat. Today it fires off the GPU's FLAG_DEAD bit-edge instead
##      (effect_frame 724 per the parser's first_hit_frame), so this delta
##      is huge — that's the parser-vs-runtime mismatch documented in
##      `tmp/handoff-reraise-rise-pose-2026-06-18.md`.
##
##   2. t_visible_rise - t_getting_up   should be small.
##      Even after activity = GETTING_UP, U_PAUSED gates the unit's
##      type1_playback during the cinematic spotlight. If this delta is
##      large the SEQ doesn't visually advance until cinematic teardown —
##      the user's "cinematic-mode interaction" hypothesis. Diagnostic:
##      large delta here ⇒ pause-stall is the culprit; small delta here
##      with large (1) ⇒ trigger-source (parser/first_hit_frame) is the
##      culprit; both large ⇒ both fixes needed.
##
## The test PASSES only when both deltas stay under DELTA_THRESHOLD_TICKS.
## It does NOT assert anything about the final HP / RERAISE bit / killing
## blow — GPUReraiseTest already covers that surface.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const StatusRegistry = ExMateriaAlmanac.StatusRegistry


const RERAISE_HP_DIVISOR = 10

# Loose enough to absorb per-frame jitter / a few interpolation ticks, tight
# enough to catch the ~625-frame parser gap and the ~700-frame cinematic
# pause-stall. Tune down once the underlying timing is fixed.
const DELTA_THRESHOLD_TICKS: int = 60

const SENTINEL: int = -1

var _t_cinematic_began: int = SENTINEL
var _t_hit_react: int = SENTINEL
var _t_getting_up: int = SENTINEL
var _t_visible_rise: int = SENTINEL
var _t_cinematic_ended: int = SENTINEL

var _signals_wired: bool = false
var _activity_hook_wired: bool = false
var _results_printed: bool = false
var _last_tick_polled: int = -1


func get_test_name() -> String:
	return "GPU Rise Timing Test"


func get_team0_unit_configs() -> Array:
	return [
		{
			"name": "Attacker", "pos_x": 1, "pos_z": 0,
			"hp": 400, "max_hp": 400, "pa": 20, "ma": 5, "wp": 10,
			"brave": 50, "faith": 50, "mp": 50, "max_mp": 50,
			"speed": 100, "move": 4, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
			"weapon_id": 19, "body_sprite_id": 0x02,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
		},
	]


func get_team1_unit_configs() -> Array:
	return [
		{
			"name": "ReraiseCarrier", "pos_x": 2, "pos_z": 0,
			"hp": 100, "max_hp": 200, "pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 50, "mp": 0, "max_mp": 0,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x05,
			# RERAISE and NO countdown: the ROM gives it none (#1116 — it is not
			# one of the sixteen statuses with a slot at unit+0x5D), so it lasts
			# until it fires. The seeded timer this fixture used to carry was inert
			# even before that — a dead unit's compute step early-returns before
			# `tick_status_timers` — and the packer now refuses a duration for an
			# unslotted status rather than writing it somewhere it does not belong.
			"status_flags_lo": (1 << StatusRegistry.bit(&"reraise")),
		},
	]


func get_gambits_for_unit(_unit_idx: int, team: int) -> Array:
	return [make_attack_gambit()] if team == 0 else []


func _ready() -> void:
	max_ticks = 1500
	test_time_scale = 1.0
	super._ready()


func _process(delta: float) -> void:
	super._process(delta)
	if _results_printed:
		return

	# Wire manager signals once (combat_loop / its managers are constructed
	# in the base _ready, but EffectManager is plumbed before any cinematic
	# spawn so a _process-time hookup is plenty early for the Reraise window).
	if not _signals_wired and combat_loop and combat_loop.effect_manager \
			and combat_loop.cinematic_manager:
		combat_loop.cinematic_manager.cinematic_began.connect(_on_cinematic_began)
		combat_loop.cinematic_manager.cinematic_ended.connect(_on_cinematic_ended)
		combat_loop.effect_manager.hit_reaction_triggered.connect(_on_hit_reaction)
		_signals_wired = true

	# Wire the activity-change hook on the carrier once it's spawned.
	if not _activity_hook_wired and units.size() > 1 and units[1] \
			and units[1].anim_state:
		units[1].anim_state.activity_changed.connect(_on_defender_activity_changed)
		_activity_hook_wired = true

	# Once we know the carrier is in GETTING_UP, look for the first tick where
	# the body SEQ actually advances. type1_playback.anim_frame == 0 means the
	# SEQ is parked at start; once it ticks past 0 the rise is visible. Latch
	# the first tick that satisfies this. Polling once per tick.
	if _t_getting_up != SENTINEL and _t_visible_rise == SENTINEL \
			and current_tick != _last_tick_polled \
			and units.size() > 1 and units[1] and units[1].display.type1_playback:
		_last_tick_polled = current_tick
		var act_now: int = int(units[1].activity)
		var frame_now: int = int(units[1].anim_frame)
		if act_now == DisplayActivity.Activity.GETTING_UP and frame_now > 0:
			_t_visible_rise = current_tick

	# We're done when the cinematic has torn down AND we've observed (or
	# given up on) the visible-rise tick. Use cinematic_ended as the spine
	# so the test doesn't fire too early to see the pause-stall delta.
	if _t_cinematic_ended != SENTINEL and not _results_printed:
		# Give the body SEQ a generous window beyond cinematic teardown so
		# the t_visible_rise latch has a chance to fire even on a slow path.
		if _t_visible_rise != SENTINEL or current_tick - _t_cinematic_ended > 120:
			_print_results()


func _on_cinematic_began(_caster_idx: int, target_idx: int) -> void:
	if target_idx == 1 and _t_cinematic_began == SENTINEL:
		_t_cinematic_began = current_tick


func _on_cinematic_ended(_prev_caster_idx: int) -> void:
	if _t_cinematic_ended == SENTINEL:
		_t_cinematic_ended = current_tick


func _on_hit_reaction(_frame: int, target_idx: int, _ability_id: int) -> void:
	if target_idx == 1 and _t_hit_react == SENTINEL:
		_t_hit_react = current_tick


func _on_defender_activity_changed(_old: int, new_state: int) -> void:
	if new_state == DisplayActivity.Activity.GETTING_UP and _t_getting_up == SENTINEL:
		_t_getting_up = current_tick


func _print_results() -> void:
	if _results_printed:
		return
	_results_printed = true

	var have_hit_react: bool = _t_hit_react != SENTINEL
	var have_getting_up: bool = _t_getting_up != SENTINEL
	var have_visible_rise: bool = _t_visible_rise != SENTINEL

	var delta_react_to_rise_state: int = -1
	var delta_state_to_visible: int = -1
	if have_hit_react and have_getting_up:
		delta_react_to_rise_state = _t_getting_up - _t_hit_react
	if have_getting_up and have_visible_rise:
		delta_state_to_visible = _t_visible_rise - _t_getting_up

	print("\n=== RISE TIMING TEST RESULTS ===")
	print("  cinematic_began:    tick=%d" % _t_cinematic_began)
	print("  hit_reaction(CPU):  tick=%d" % _t_hit_react)
	print("  activity=GETTING_UP: tick=%d" % _t_getting_up)
	print("  visible_rise:       tick=%d" % _t_visible_rise)
	print("  cinematic_ended:    tick=%d" % _t_cinematic_ended)
	print("")
	print("  delta (GETTING_UP - hit_reaction):  %d ticks (must be ≤ %d)" % [
		delta_react_to_rise_state, DELTA_THRESHOLD_TICKS])
	print("  delta (visible_rise - GETTING_UP):  %d ticks (must be ≤ %d)" % [
		delta_state_to_visible, DELTA_THRESHOLD_TICKS])

	var why: Array = []
	if not have_hit_react:
		why.append("HIT_REACT never fired (CPU keyframe path missing)")
	if not have_getting_up:
		why.append("carrier activity never became GETTING_UP")
	if not have_visible_rise:
		why.append("GETTING_UP SEQ never advanced past frame 0 (pause-stall?)")
	if delta_react_to_rise_state > DELTA_THRESHOLD_TICKS:
		why.append("rise state lagged HIT_REACT by %d ticks (trigger source wrong)" % delta_react_to_rise_state)
	if delta_state_to_visible > DELTA_THRESHOLD_TICKS:
		why.append("SEQ playback lagged GETTING_UP by %d ticks (U_PAUSED stall)" % delta_state_to_visible)

	if why.is_empty():
		print("[PASS] Rise pose contemporaneous with HIT_REACT and not pause-stalled")
	else:
		print("[FAIL] %s" % ", ".join(why))
	print("================================\n")
	get_tree().quit()


func on_victory(_winning_team: int) -> void:
	if not _results_printed:
		_print_results()


func _on_loop_timed_out(_tick: int) -> void:
	if not _results_printed:
		_print_results()
	super._on_loop_timed_out(_tick)
