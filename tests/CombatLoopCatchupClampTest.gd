extends Node3D
# test-kind: logic
# seeded-break: drop the clamp itself in src/gpu/CombatLoop.gd (`var capped_delta: float = minf(delta, _catchup_ceiling)` -> `= delta`), leaving `max_catchup_real_s` at its 1.0 default so the fixture's own in-window guard still passes — arm 1 (a 4 s frame drains 240 ticks, expected 59), arm 4 (playback_scale 4) and arm 5 (the SECOND, post-victory drain) all red. Raising `max_catchup_real_s` instead is the WRONG seed: it trips the fixture's meaningful-window precondition before any arm runs
## W6 — the tick catch-up drain is bounded, and the bound is REAL wall clock.
##
## `CombatLoop.tick()` converts `delta` into whole `TICK_INTERVAL` steps. Unbounded,
## one long frame schedules more ticks, which makes the next frame longer still. The
## ruling taken here is that the simulation may run SLOW under load rather than catch
## up — which is the contract the loop already advertises (`playback_scale`: a beat is
## a function of ticks and never of wall clock, ADR-0065), so no clamp can change an
## outcome, only how fast it is watched.
##
## ⚠ The ticket described ONE loop. There are TWO, and both drain the same
## accumulator: the combat drain, and a second inside `if victory_achieved:` that keeps
## animations running post-victory. A clamp on one and not the other is a partial fix,
## so arm 5 is the second one, counted separately.
##
## Every arm asserts COUNTED WORK — ticks drained, `update` calls made — never
## milliseconds (W8's standing ruling). Each has its control arm: the same call with
## the ceiling lifted must do the unbounded amount, or the clamped arm would pass for
## a loop that simply never ran.
##
##   1. The clamp bites on the shipped path — a fat frame at `time_scale == 1` drains
##      one ceiling's worth of ticks, not four. Control: ceiling lifted → all four.
##   2. A deliberate fast-forward is EXEMPT — at `Engine.time_scale = 40` the same
##      frame drains the lot. This is the arm that protects the four navigator proofs
##      that run at `SIM_TIME_SCALE := 40.0`; a naive tick cap would have red them.
##   3. No debt banks. After a clamped fat frame the very next normal frame drains
##      exactly the ticks its OWN delta earns. This is the anti-compounding assertion:
##      the clamped-away seconds are discarded, not carried.
##   4. `playback_scale` multiplies AFTER the clamp, so a 4x playback rate still buys
##      4x the sim out of the clamped budget.
##   5. The post-victory drain is clamped too, counted through a ProjectileManager
##      that tallies its own `update` calls (the victory branch's one per-tick call).

const Lattice = ExMateriaBattlefield.Lattice

const TICK_INTERVAL: float = 1.0 / 60.0
const SEED := 12345
const UNITS_PER_BATTLE := 8
## Four times the default ceiling of delta, so the clamped and unclamped counts stay
## far apart whatever the ceiling is set to. The gap between them is what every arm
## below reads.
const FAT_FRAME: float = 4.0
## What a nominal second and the default ceiling actually BUY, derived through
## `_ticks_in` rather than typed in. Both are set in `_ready`.
var _fat_frame_ticks: int = 0
var _clamp_ticks: int = 0

var _loop: CombatLoop = null
var _sim = null


## A ProjectileManager that counts the calls the post-victory drain makes to it.
## Subclassed rather than duck-typed because `CombatLoop.projectile_manager` is
## statically typed, so a bare stub object would not assign.
class CountingProjectileManager extends ProjectileManager:
	var update_calls: int = 0

	func _init(base) -> void:
		super(base)

	func update(current_tick: int, all_states: Array) -> void:
		update_calls += 1
		super(current_tick, all_states)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if not _build_bare_loop():
		print("[FAIL] Catch-up clamp: bare CombatLoop did not come up")
		get_tree().quit()
		return

	_fat_frame_ticks = _ticks_in(FAT_FRAME)
	_clamp_ticks = _ticks_in(_loop.max_catchup_real_s)
	if _clamp_ticks <= 0 or _clamp_ticks >= _fat_frame_ticks:
		print("[FAIL] the default ceiling (%.3f s = %d ticks) is outside the (0, %d) window every arm needs to be meaningful" % [
			_loop.max_catchup_real_s, _clamp_ticks, _fat_frame_ticks])
		get_tree().quit()
		return

	var failed := false
	failed = _arm_1_clamp_bites_on_the_shipped_path() or failed
	failed = _arm_2_fast_forward_is_exempt() or failed
	failed = _arm_3_no_debt_banks() or failed
	failed = _arm_4_playback_rate_survives_the_clamp() or failed
	failed = _arm_5_the_victory_drain_is_clamped_too() or failed

	if failed:
		print("[FAIL] Catch-up clamp test")
	else:
		print("[PASS] Catch-up clamp: a %.0f s frame drains %d ticks not %d, a 40x fast-forward still drains %d, no debt banks, playback_scale still buys its rate, and the post-victory drain is bounded too — on a bare CombatLoop" % [
			FAT_FRAME, _clamp_ticks, _fat_frame_ticks, _fat_frame_ticks])
	get_tree().quit()


# === Harness ==================================================================

## Stand up a `CombatLoop` with no host and no `Unit` nodes — the same bare mount
## `TurnDirectorTest` uses, minus the director, so nothing but the drain is in play.
## Every unit holds an EMPTY gambit list: a battle that is a pure clock.
func _build_bare_loop() -> bool:
	var map_node: Node3D = $ProceduralMap
	BattlefieldWiring.wire_map(map_node)
	var lat: Lattice = map_node.lattice
	if lat == null:
		push_error("[CombatLoopCatchupClampTest] map has no lattice")
		return false

	_loop = CombatLoop.new()
	_loop.name = "CombatLoop"
	_loop.battle_name = "CombatLoopCatchupClampTest"
	_loop.units_per_battle = UNITS_PER_BATTLE
	_loop.lattice = lat
	add_child(_loop)

	_loop.setup_distance_field()
	_loop.setup_gpu_simulator()
	if _loop.gpu_simulator == null:
		return false
	_sim = _loop.gpu_simulator
	_sim.set_battle_units(0, _team(0), _team(1), SEED)
	for i in range(UNITS_PER_BATTLE):
		_sim.set_unit_gambits(0, i, [])
	_loop.gpu_state_reader.initialize(_sim, 0)
	_loop._initialize_managers()
	# No director is mounted, so no turn gate can break a drain early and none of the
	# tick counts below can be explained by ADR-0239 stopping the world.
	if _loop.turn_gate.is_valid():
		push_error("[CombatLoopCatchupClampTest] a turn gate is installed — the counts would not be the clamp's")
		return false

	_loop.combat_active = true
	return true


func _team(team_id: int) -> Array:
	var out: Array = []
	var base_x: int = 2 if team_id == 0 else 12
	var speeds: Array = [7, 9, 11, 13] if team_id == 0 else [8, 10, 12, 14]
	for i in range(4):
		out.append({
			"pos_x": base_x, "pos_z": 3 + i * 2,
			"hp": 200, "max_hp": 200, "mp": 50, "max_mp": 50,
			"speed": speeds[i], "move": 3, "jump": 3,
			"pa": 10, "ma": 10, "wp": 5, "brave": 60, "faith": 50,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		})
	return out


## How many ticks `seconds` of accumulated delta actually buys — a repeated float
## subtraction, mirroring the loop's own drain rather than dividing.
##
## The two are NOT the same number. `TICK_INTERVAL` is 1/60 rounded UP in binary, so
## sixty of them sum to slightly more than 1.0 and a nominal one-second frame drains
## 59 ticks, not 60. Typing the round number in would have asserted the engine was
## wrong about its own arithmetic.
func _ticks_in(seconds: float) -> int:
	var n: int = 0
	var acc: float = seconds
	while acc >= TICK_INTERVAL:
		acc -= TICK_INTERVAL
		n += 1
	return n


## Drain one frame from a known-empty accumulator and report the ticks it ran.
func _ticks_in_one_frame(delta: float) -> int:
	_loop._tick_accumulator = 0.0
	var before: int = _loop.current_tick
	_loop.tick(delta)
	return _loop.current_tick - before


# === 1. The clamp bites on the shipped path ===================================

func _arm_1_clamp_bites_on_the_shipped_path() -> bool:
	var failed := false
	var clamped: int = _ticks_in_one_frame(FAT_FRAME)
	if clamped != _clamp_ticks:
		print("[FAIL] arm 1: a %.2f s frame drained %d ticks, expected %d (%.3f real s at time_scale 1)" % [
			FAT_FRAME, clamped, _clamp_ticks, _loop.max_catchup_real_s])
		failed = true

	# The control. Without it this arm passes for a loop that stopped ticking at all.
	var ceiling: float = _loop.max_catchup_real_s
	_loop.max_catchup_real_s = INF
	var unclamped: int = _ticks_in_one_frame(FAT_FRAME)
	_loop.max_catchup_real_s = ceiling
	if unclamped != _fat_frame_ticks:
		print("[FAIL] arm 1 control: with the ceiling lifted the same frame drained %d ticks, expected %d — the clamped arm proves nothing" % [
			unclamped, _fat_frame_ticks])
		failed = true
	return failed


# === 2. A deliberate fast-forward is exempt ===================================

## `delta` reaches `tick()` already multiplied by `Engine.time_scale`, so the ceiling
## is multiplied by it too. A fast-forward is a REQUEST to decouple sim time from real
## time; the clamp answers a machine that cannot keep up, not a developer who asked to
## go faster. Four navigator proofs run at `SIM_TIME_SCALE := 40.0` and a naive
## tick-count cap would have quietly throttled every one of them.
func _arm_2_fast_forward_is_exempt() -> bool:
	var failed := false
	var previous: float = Engine.time_scale
	Engine.time_scale = 40.0
	var ran: int = _ticks_in_one_frame(FAT_FRAME)
	Engine.time_scale = previous
	if ran != _fat_frame_ticks:
		print("[FAIL] arm 2: at time_scale 40 a %.2f s frame drained %d ticks, expected the full %d — the clamp is throttling a deliberate fast-forward" % [
			FAT_FRAME, ran, _fat_frame_ticks])
		failed = true
	if not is_equal_approx(Engine.time_scale, previous):
		print("[FAIL] arm 2: time_scale was left at %s" % Engine.time_scale)
		failed = true
	return failed


# === 3. No debt banks =========================================================

## The compounding this item exists to stop. The clamped-away time must be DISCARDED,
## not carried: if the second the clamp refused were still sitting in the accumulator,
## the next frame would run at the ceiling again, and the frame after that, forever.
func _arm_3_no_debt_banks() -> bool:
	var failed := false
	_loop._tick_accumulator = 0.0
	_loop.tick(FAT_FRAME)

	var before: int = _loop.current_tick
	_loop.tick(TICK_INTERVAL)
	var second: int = _loop.current_tick - before
	if second != 1:
		print("[FAIL] arm 3: the frame after a clamped fat frame drained %d ticks, expected exactly 1 — the refused time was banked, not discarded" % second)
		failed = true
	if _loop._tick_accumulator >= TICK_INTERVAL:
		print("[FAIL] arm 3: %.4f s is still banked after the drain (one tick is %.4f) — a later frame will inherit it" % [
			_loop._tick_accumulator, TICK_INTERVAL])
		failed = true
	return failed


# === 4. The playback rate survives the clamp ==================================

## `playback_scale` multiplies AFTER the clamp. The clamp bounds the REAL second a
## frame may bank; a 4x playback rate asked for four times the sim per real second and
## must still get it out of that bounded second.
func _arm_4_playback_rate_survives_the_clamp() -> bool:
	var failed := false
	_loop.playback_scale = 4.0
	var ran: int = _ticks_in_one_frame(FAT_FRAME)
	_loop.playback_scale = 1.0
	var expected: int = _ticks_in(_loop.max_catchup_real_s * 4.0)
	if ran != expected:
		print("[FAIL] arm 4: at playback_scale 4 a clamped frame drained %d ticks, expected %d (4x the %d-tick budget)" % [
			ran, expected, _clamp_ticks])
		failed = true
	if ran <= _clamp_ticks:
		print("[FAIL] arm 4: the playback rate bought nothing — %d ticks at 4x, %d at 1x" % [ran, _clamp_ticks])
		failed = true
	return failed


# === 5. The post-victory drain is clamped too =================================

## The second loop, the one the ticket did not name. It drains the SAME accumulator to
## keep animations running after victory, and it had the same absent ceiling. Counted
## through the one per-tick call its body makes.
func _arm_5_the_victory_drain_is_clamped_too() -> bool:
	var failed := false
	var displaced := _loop.projectile_manager
	var counter := CountingProjectileManager.new(_loop)
	_loop.projectile_manager = counter
	_loop.victory_achieved = true

	_loop._tick_accumulator = 0.0
	counter.update_calls = 0
	_loop.tick(FAT_FRAME)
	var clamped: int = counter.update_calls
	if clamped != _clamp_ticks:
		print("[FAIL] arm 5: the post-victory drain ran %d ticks on a %.2f s frame, expected %d" % [
			clamped, FAT_FRAME, _clamp_ticks])
		failed = true

	var ceiling: float = _loop.max_catchup_real_s
	_loop.max_catchup_real_s = INF
	_loop._tick_accumulator = 0.0
	counter.update_calls = 0
	_loop.tick(FAT_FRAME)
	var unclamped: int = counter.update_calls
	_loop.max_catchup_real_s = ceiling
	if unclamped != _fat_frame_ticks:
		print("[FAIL] arm 5 control: with the ceiling lifted the post-victory drain ran %d ticks, expected %d — the clamped arm proves nothing" % [
			unclamped, _fat_frame_ticks])
		failed = true

	_loop.victory_achieved = false
	_loop.projectile_manager = displaced
	return failed
