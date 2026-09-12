extends GPUCombatTestBase

## GPU Cinematic Single-Spawn Test (double-cast regression, 2026-07-30)
##
## Guards the fix for "charged spells play their effect twice" — a charged
## (cinematic) cast spawned its EffectInstance ONCE on the cinematic-timer edge
## (CinematicManager._handle_began -> spawn_cinematic_effect, issue #53) and then
## AGAIN at resolution (CombatLoop._on_spell_cast_complete -> _spawn_spell_effect),
## because the resolution path had no cinematic guard. Visually: Fire cast once,
## exploded twice ("once during the cinematic, once after").
##
## The GPU routes charge_time > 0 abilities to cast_cinematic_spell
## (stage_spell.glsl:633); the cinematic path OWNS the visual, so
## _on_spell_cast_complete now skips its effect spawn when `ct > 0 and not is_item`.
##
## Harness: one Mage casts Fire (ct=4 -> cinematic) at one defenseless target.
## The base routes the resolution-time spawn through _spawn_spell_effect (the
## ADR-0018 seam); we override it as a counter. The cinematic path spawns via
## effect_manager.spawn_cinematic_effect directly (NOT this seam), so a correctly
## guarded cinematic cast calls the resolution seam ZERO times.
##
## PASS: target takes the expected Fire hit (proves the cast really ran and
## resolved through the cinematic path) AND the resolution seam fired 0 times.
## FAIL (pre-fix): the resolution seam fired >= 1 time = a second, redundant
## EffectInstance = the double cast.

const ABILITY_FIRE = 16
const TARGET_START_HP = 9999
# Base Fire damage on this PA=5/MA=12/Faith=100 Mage vs a Faith=100 defenseless
# target — same stat block as GPUSimultaneousCinematicTest (witnessed 168).
const EXPECTED_BASE_DAMAGE = 168

var _resolution_spawns: int = 0
var _target_delta: int = 0
var _results_printed: bool = false


func get_test_name() -> String:
	return "GPU Cinematic Single-Spawn Test (charged Fire spawns its effect once, via the cinematic path only)"


func get_team0_unit_configs() -> Array:
	return [
		{
			"name": "Mage",
			"pos_x": 0, "pos_z": 0,
			"hp": 500, "max_hp": 500,
			"pa": 5, "ma": 12, "wp": 1,
			"brave": 50, "faith": 100,
			"mp": 99, "max_mp": 99,
			"speed": 100, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x04,
		},
	]


func get_team1_unit_configs() -> Array:
	return [
		{
			"name": "Target",
			"pos_x": 4, "pos_z": 0,
			"hp": TARGET_START_HP, "max_hp": TARGET_START_HP,
			"pa": 5, "ma": 5, "wp": 1,
			"brave": 50, "faith": 100,
			"mp": 0, "max_mp": 0,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x05,
		},
	]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	if unit_idx == 0:
		return [make_spell_gambit(ABILITY_FIRE, GPUConstants.TARGET_NEAREST_ENEMY)]
	return []


func _ready() -> void:
	# Fire ct=4 -> ~80 ticks charge; generous tail so a post-cinematic re-spawn
	# (present iff the bug regresses) would still land inside the window.
	max_ticks = 1500
	super._ready()


# Resolution-path spawn counter (ADR-0018 seam). A cinematic cast must never
# reach here; do NOT call super so no real EffectInstance is built for the count.
func _spawn_spell_effect(_caster: Unit, _target: Unit, ability_id: int, effect_id: int):
	_resolution_spawns += 1
	print("  [RESOLUTION SPAWN] ability=%d effect=E%03d (count now %d) — should be 0 for a cinematic cast" % [
		ability_id, effect_id, _resolution_spawns])


func on_hp_changed(unit_idx: int, _old_hp: int, _new_hp: int, delta: int) -> void:
	if _results_printed:
		return
	if delta >= 0:
		return  # heal / no-op
	if unit_idx == 1 and _target_delta == 0:
		_target_delta = -delta
		# Give the resolution edge a beat to fire (it lands at cinematic teardown,
		# after damage) before we judge — defer the verdict to the tail poll.


func _process(delta: float) -> void:
	super._process(delta)
	if _results_printed:
		return
	if not gpu_state_reader:
		return
	# Judge once the target has been hit AND we're a comfortable margin past the
	# cinematic teardown (where a stray resolution spawn would land), or at timeout.
	if current_tick >= max_ticks - 1:
		_print_results()


func on_victory(_winning_team: int) -> void:
	if not _results_printed:
		_print_results()


func _print_results() -> void:
	if _results_printed:
		return
	_results_printed = true

	print("\n=== CINEMATIC SINGLE-SPAWN TEST RESULTS ===")
	print("  Target Fire delta:        %d (expected %d)" % [_target_delta, EXPECTED_BASE_DAMAGE])
	print("  Resolution-path spawns:   %d (expected 0 — cinematic path owns the effect)" % _resolution_spawns)

	var hit_ok := _target_delta == EXPECTED_BASE_DAMAGE
	var spawn_ok := _resolution_spawns == 0

	if hit_ok and spawn_ok:
		print("\n[PASS] charged Fire resolved once via the cinematic path; no redundant resolution spawn")
	else:
		var why: Array = []
		if not hit_ok:
			why.append("Fire didn't land as expected (got %d, expected %d) — scenario didn't run, so the spawn count is meaningless" % [_target_delta, EXPECTED_BASE_DAMAGE])
		if not spawn_ok:
			why.append("resolution seam fired %d time(s) for a cinematic cast — the double-spawn is back" % _resolution_spawns)
		print("\n[FAIL] %s" % ", ".join(why))
	print("===========================================\n")
	get_tree().quit()
