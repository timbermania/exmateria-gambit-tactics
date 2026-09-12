extends GPUCombatTestBase

## GPU Dash Performance Test
##
## Stress test for Dash effect (E154/E386) performance.
## A fast Dasher repeatedly casts Dash (ability 147) on a slow Target.
## Both have 9999 HP so nobody dies, so `on_victory` never fires.
##
## Tracks per-frame times and detects spikes (effect vs idle).
##
## IT ENDS ON ITS OWN (#504). It used to set `max_ticks = 999999` — "Run indefinitely" —
## which disabled the base class's own timeout, and since nobody ever dies there was no
## other way out: every run that selected it paid the full `timeout 360` and scored HUNG.
## A rig is allowed to assert nothing; it is not allowed to hang. It now runs a TOTAL_TIME
## budget, prints the final bucket table and quits, and `max_ticks` is left at the base
## default so the loop timeout is a backstop again rather than being switched off.
##
## Touch any key and the budget is cancelled — watching the live perf HUD is what the rig
## is for, and a by-eye session must not be cut off mid-measurement.

const EffectInstance = ExMateriaEffects.EffectInstance
const TrapEffect = ExMateriaEffects.TrapEffect

const ABILITY_DASH = 147  # Squire Dash, effect E154

const WARMUP_FRAMES = 120  # Ignore first N frames (scene loading)

# --- Per-frame spike detection ---
const SPIKE_THRESHOLD_MS = 20.0  # Log any frame above this

# Buckets: "idle", "cam", "effect", "cam+fx"
var _bucket_frame_times: Dictionary = {
	"idle": [], "effect": []
}
var _bucket_spikes: Dictionary = {
	"idle": 0, "effect": 0
}

# --- HUD ---
var _perf_label: Label
var _perf_canvas: CanvasLayer
var _frame_counter: int = 0
var _console_timer: float = 0.0
## Unattended budget — long enough to clear WARMUP_FRAMES and collect a real sample in
## both buckets. A key press hands the session to the human and cancels it.
## WALL CLOCK, deliberately, and not `delta`. The budget exists to bound this scene
## under the runner's `timeout 360`, and `delta` is not a bound on real time:
## GPUCombatTestBase sets `Engine.time_scale = test_time_scale` (4.0 by default), so a
## delta-summed budget runs 4x fast there and 4x SLOW at time_scale 0.25 — the direction
## that would walk straight back into a hang.
const TOTAL_TIME := 60.0
var _t0_ms: int = Time.get_ticks_msec()
var _manual: bool = false
var _effect_spawn_count: int = 0
var _effect_active: bool = false


func get_test_name() -> String:
	return "GPU Dash Performance Test"


func get_team0_unit_configs() -> Array:
	return [
		{
			"name": "Dasher",
			"pos_x": 2, "pos_z": 1,
			"hp": 9999, "max_hp": 9999,
			"pa": 15, "ma": 5, "wp": 8,
			"brave": 70, "faith": 50,
			"mp": 9999, "max_mp": 9999,
			"speed": 120,
			"move": 4, "jump": 3,
			"weapon_range": 1,
			"weapon_flags": 1,  # STRIKING
			"weapon_type": 1,   # Sword
			"weapon_id": 19,    # Broad Sword
			"body_sprite_id": 0x02,
			"job_id": "4a",     # Squire
			"gambits": [{
				"enabled": true,
				"cond_target_type": GPUConstants.TARGET_NEAREST_ENEMY,
				"conditions": [{"type": GPUConstants.COND_ALWAYS, "value": 0}],
				"action_type": GPUConstants.ACTION_ABILITY,
				"action_id": ABILITY_DASH,
				"action_target_type": GPUConstants.TARGET_THEM
			}]
		},
	]


func get_team1_unit_configs() -> Array:
	return [
		{
			"name": "Target",
			"pos_x": 2, "pos_z": 3,
			"hp": 9999, "max_hp": 9999,
			"pa": 5, "ma": 5, "wp": 10,
			"brave": 50, "faith": 50,
			"mp": 50, "max_mp": 50,
			"speed": 10,
			"move": 3, "jump": 3,
			"weapon_range": 1,
			"weapon_flags": 1,
			"weapon_type": 1,
			"weapon_id": 19,
			"body_sprite_id": 0x05,
			"gambits": [{
				"enabled": true,
				"cond_target_type": GPUConstants.TARGET_NEAREST_ENEMY,
				"conditions": [{"type": GPUConstants.COND_ALWAYS, "value": 0}],
				"action_type": GPUConstants.ACTION_ATTACK,
				"action_id": 0,
				"action_target_type": GPUConstants.TARGET_THEM
			}]
		},
	]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	var all_configs = get_team0_unit_configs() + get_team1_unit_configs()
	if unit_idx < all_configs.size():
		return all_configs[unit_idx].get("gambits", [make_attack_gambit()])
	return [make_attack_gambit()]


func _ready():
	# #463/#504: a rig, not a test. Declared FIRST so it is on the record whatever the
	# base setup below does. The verdict reader scores it NOT_A_TEST — see
	# tests/lib/verdict.sh. Note the budget in _process must fire BEFORE the base's
	# `_on_loop_timed_out`, which prints "TIMEOUT at tick" and would score rule 5 instead.
	print("[NOT_A_TEST] a by-eye Dash (E154/E386) frame-time rig — it buckets effect-vs-idle frame times and prints a spike table for a human, and asserts nothing; named *Test, but it is a rig")
	DebugConfig.particle_debug_enabled = true
	super._ready()
	_setup_perf_hud()
	print("\n=== DASH PERFORMANCE TEST ===")
	print("Spike threshold: %.0fms" % SPIKE_THRESHOLD_MS)
	print("Buckets: idle | effect")
	print("=== END DASH PERF SETUP ===\n")


func _setup_perf_hud():
	_perf_canvas = CanvasLayer.new()
	_perf_canvas.layer = 99
	add_child(_perf_canvas)

	_perf_label = Label.new()
	_perf_label.position = Vector2(10, 10)
	_perf_label.add_theme_font_size_override("font_size", 16)
	_perf_label.add_theme_color_override("font_color", Color.YELLOW)
	_perf_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_perf_label.add_theme_constant_override("shadow_offset_x", 1)
	_perf_label.add_theme_constant_override("shadow_offset_y", 1)
	_perf_label.text = "Warming up..."
	_perf_canvas.add_child(_perf_label)


func _process(delta):
	# Budget FIRST, so it beats the base's tick timeout to the exit and the run scores
	# NOT_A_TEST rather than TIMEOUT.
	var elapsed := float(Time.get_ticks_msec() - _t0_ms) / 1000.0
	if not _manual and elapsed >= TOTAL_TIME:
		_print_final("budget reached at %.0fs wall" % elapsed)
		get_tree().quit(0)
		return
	super._process(delta)
	_frame_counter += 1

	# Detect effect active this frame
	_effect_active = _count_active_effects() > 0

	# Record frame time into the right bucket (skip warmup)
	if _frame_counter > WARMUP_FRAMES:
		var frame_ms = delta * 1000.0
		var bucket = _get_bucket()
		_bucket_frame_times[bucket].append(frame_ms)
		# Cap stored frames to avoid unbounded memory (keep last 600 per bucket)
		if _bucket_frame_times[bucket].size() > 600:
			_bucket_frame_times[bucket].remove_at(0)

		if frame_ms > SPIKE_THRESHOLD_MS:
			_bucket_spikes[bucket] += 1
			var draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			print("[SPIKE] %.1fms in [%s] tick=%d effects=%d particles=%d draws=%d" % [
				frame_ms, bucket, current_tick,
				_count_active_effects(), _count_active_particles(), draw_calls])

	# Update HUD every 20 frames
	if _frame_counter % 20 == 0 and _frame_counter > WARMUP_FRAMES:
		_update_perf_hud()

	# Console summary every 5 seconds
	_console_timer += delta
	if _console_timer >= 5.0 and _frame_counter > WARMUP_FRAMES:
		_console_timer = 0.0
		_print_console_summary()


func _get_bucket() -> String:
	if _effect_active:
		return "effect"
	return "idle"


func _count_active_effects() -> int:
	var count = 0
	for child in get_tree().root.get_children():
		if child is EffectInstance:
			count += 1
	for child in get_children():
		if child is TrapEffect:
			count += 1
	return count


func _count_active_particles() -> int:
	var count = 0
	for child in get_tree().root.get_children():
		if child is EffectInstance:
			count += child.get_active_particle_count()
	for child in get_children():
		if child is TrapEffect:
			count += child.get_particle_count()
	return count


func _bucket_stats(bucket: String) -> Dictionary:
	var times = _bucket_frame_times[bucket]
	if times.is_empty():
		return {"min": 0.0, "max": 0.0, "avg": 0.0, "count": 0, "spikes": 0}
	var mn = 9999.0
	var mx = 0.0
	var total = 0.0
	for t in times:
		if t < mn:
			mn = t
		if t > mx:
			mx = t
		total += t
	return {
		"min": mn, "max": mx, "avg": total / times.size(),
		"count": times.size(), "spikes": _bucket_spikes[bucket]
	}


func _update_perf_hud():
	var fps = Performance.get_monitor(Performance.TIME_FPS)
	var draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var particles = _count_active_particles()
	var effects = _count_active_effects()

	var fx = _bucket_stats("effect")
	var idle = _bucket_stats("idle")

	_perf_label.text = (
		"FPS: %d  |  Particles: %d  |  Draw Calls: %d  |  Effects: %d  |  Spawns: %d\n" % [
			fps, particles, draw_calls, effects, _effect_spawn_count] +
		"--- Frame times (min / avg / max) --- spikes > %.0fms ---\n" % SPIKE_THRESHOLD_MS +
		"EFFECT: %5.1f / %5.1f / %5.1f ms  spikes: %d  (n=%d)\n" % [
			fx["min"], fx["avg"], fx["max"], fx["spikes"], fx["count"]] +
		"IDLE:   %5.1f / %5.1f / %5.1f ms  spikes: %d  (n=%d)" % [
			idle["min"], idle["avg"], idle["max"], idle["spikes"], idle["count"]]
	)


func _print_console_summary():
	var fx = _bucket_stats("effect")
	var idle = _bucket_stats("idle")

	print("[DASH_PERF] tick=%d spawns=%d | FX: %.1f/%.1f/%.1f ms (%d spikes, n=%d) | IDLE: %.1f/%.1f/%.1f ms (%d spikes, n=%d)" % [
		current_tick, _effect_spawn_count,
		fx["min"], fx["avg"], fx["max"], fx["spikes"], fx["count"],
		idle["min"], idle["avg"], idle["max"], idle["spikes"], idle["count"],
	])


func on_state_changed(unit_idx: int, old_state: int, new_state: int):
	if new_state == GPUConstants.LOGICAL_ACTIVITY_ACTING:
		if unit_idx < units.size() and units[unit_idx].name == "Dasher":
			_effect_spawn_count += 1

	if DebugConfig.iteration_debug_enabled:
		var unit_name = units[unit_idx].name if unit_idx < units.size() else "Unit%d" % unit_idx
		var old_name = GPUConstants.LOGICAL_ACTIVITY_NAMES[old_state] if old_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(old_state)
		var new_name = GPUConstants.LOGICAL_ACTIVITY_NAMES[new_state] if new_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(new_state)
		print("  [STATE] %s: %s -> %s" % [unit_name, old_name, new_name])


func on_hp_changed(unit_idx: int, old_hp: int, new_hp: int, delta_hp: int):
	if DebugConfig.iteration_debug_enabled:
		var unit_name = units[unit_idx].name if unit_idx < units.size() else "Unit%d" % unit_idx
		if delta_hp < 0:
			print("  [DAMAGE] %s hit for %d! HP: %d -> %d" % [unit_name, abs(delta_hp), old_hp, new_hp])


func _unhandled_input(event):
	# A human is here. Cancel the budget, then let the base keep its Ctrl+R / SPACE keys.
	if event is InputEventKey and event.pressed and not event.echo:
		_manual = true
	super._unhandled_input(event)


## The final table. Shared by the budget exit and by on_victory, so the rig reports the
## same thing however it ends — and so its numbers survive its own termination.
func _print_final(why: String) -> void:
	_print_console_summary()
	print("\n=== DASH PERF FINAL (%s) ===" % why)
	var fx = _bucket_stats("effect")
	var idle = _bucket_stats("idle")
	print("  EFFECT worst frame: %.1fms  spikes(>%.0fms): %d  (n=%d)" % [
		fx["max"], SPIKE_THRESHOLD_MS, fx["spikes"], fx["count"]])
	print("  IDLE   worst frame: %.1fms  spikes(>%.0fms): %d  (n=%d)" % [
		idle["max"], SPIKE_THRESHOLD_MS, idle["spikes"], idle["count"]])
	print("  Dash casts observed: %d" % _effect_spawn_count)
	print("=========================")


func on_victory(_winning_team: int):
	_print_final("victory")
