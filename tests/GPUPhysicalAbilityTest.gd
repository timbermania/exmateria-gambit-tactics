extends GPUCombatTestBase

## GPU Physical Ability Test
##
## A Knight-Break skill must play the WEAPON SWING animation, not the spell-cast pose.
##
## The discriminator is one branch in `CombatLoop._on_spell_cast_complete`: an ability with
## `weapon_range == true` (the Knight Breaks 138-145, the Holy Swords 155-165) routes to
## `_start_attack_animation` -> `Unit.attack()` -> `anim_state.current_state = ATTACKING`;
## everything else routes to `Unit.cast_spell()` -> `SPELL_CASTING`. This test drives
## ArmorBreak (139) through the real GPU loop and asserts which side of that branch it
## landed on.
##
## WHY THIS TEST WAS REWRITTEN (2026-08-22). It asserted NOTHING about animation — the
## claim above lived only in the header. Its sole verdict was `on_victory`, and it could
## never reach one: ArmorBreak is formula 37, which destroys equipment and deals ZERO HP
## damage, so the Knight cannot win; and the Target never lands a hit either (see
## `_report_target_diagnostic` below). The run therefore spent 6000 ticks emitting 95
## identical swings and reported `TIMEOUT`, deterministically, every time. It was a debug
## harness wearing a test's name. It now asserts its own header.
##
## Note the header used to say "CT=1, Range=1"; ability_attributes.json says ct=0, range=0
## and `weapon_range = true` — the range comes from the equipped weapon, which is the whole
## point of the branch under test.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase


const ABILITY_BREAK_ARMOR = 139
const ABILITY_HEAD_BREAK = 138
## Give the Knight enough ticks to walk one tile and swing; the first cast lands ~T:47.
const CAST_DEADLINE_TICKS = 600


func get_test_name() -> String:
	return "GPU Physical Ability Test"


func get_team0_unit_configs() -> Array:
	return [{
		"name": "Knight",
		"pos_x": 0, "pos_z": 0,
		"hp": 200, "max_hp": 200,
		"pa": 10, "ma": 5, "wp": 5,
		"brave": 50, "faith": 50,
		"mp": 50, "max_mp": 50,
		"move": 4, "jump": 3,
		"weapon_range": 1,
		"weapon_flags": 1,  # STRIKING
		"weapon_type": 1,   # Sword -> SWING animation
		"weapon_id": 19,    # Broad Sword
		"body_sprite_id": 0x02
	}]


func get_team1_unit_configs() -> Array:
	return [{
		"name": "Target",
		"pos_x": 2, "pos_z": 0,
		"hp": 300, "max_hp": 300,
		"pa": 6, "ma": 5, "wp": 3,
		"brave": 50, "faith": 50,
		"mp": 50, "max_mp": 50,
		"move": 3, "jump": 3,
		"weapon_range": 1,
		"weapon_flags": 1,
		"weapon_type": 1,
		"weapon_id": 19,
		"body_sprite_id": 0x05
	}]


func get_gambits_for_unit(unit_idx: int, team: int) -> Array:
	if team == 0:
		# Knight uses Break Armor on nearest enemy
		return [make_ability_gambit(ABILITY_BREAK_ARMOR, GPUConstants.TARGET_NEAREST_ENEMY)]
	else:
		# Target just attacks back
		return [make_attack_gambit()]


var _cast_seen := false
var _cast_ability := -1
var _sample_after_frames := -1
var _verdict_done := false
var _passed := 0
var _failed := 0


func _ready():
	# Enable verbose debugging for this test
	DebugConfig.iteration_debug_enabled = true
	max_ticks = CAST_DEADLINE_TICKS
	# AWAIT it: the base `_ready` is a coroutine (it awaits process frames and a settle
	# timer), so a bare `super._ready()` returns at its first await and `combat_loop` would
	# still be null on the next line — the cast_began connect would silently never happen.
	await super._ready()
	if combat_loop:
		combat_loop.cast_began.connect(_on_cast_began)
	else:
		print("[FAIL] no combat_loop after boot — cannot observe the cast")
		_failed += 1
	# Print ability data at startup for verification
	call_deferred("_print_ability_debug")


## `cast_began` fires from `_apply_cast_began` BEFORE `_on_spell_cast_complete` picks the
## animation branch, so the pose is not chosen yet at this instant. Latch here, sample two
## frames later.
func _on_cast_began(unit_idx: int, ability_id: int, _target: int) -> void:
	if unit_idx != 0 or _cast_seen:
		return
	_cast_seen = true
	_cast_ability = ability_id
	_sample_after_frames = 2


func _process(delta: float) -> void:
	super._process(delta)
	if _verdict_done:
		return
	if _sample_after_frames > 0:
		_sample_after_frames -= 1
		if _sample_after_frames == 0:
			_finish()
		return
	if current_tick >= CAST_DEADLINE_TICKS:
		_finish()


func _check(ok: bool, msg: String) -> void:
	if ok:
		_passed += 1
		print("  [ok] %s" % msg)
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)


func _finish() -> void:
	if _verdict_done:
		return
	_verdict_done = true
	print("\n=== PHYSICAL ABILITY TEST RESULTS ===")

	# The data premise: ArmorBreak is the weapon_range kind. If this flips, the branch
	# under test is not the branch this ability takes and the pose assertion below is
	# measuring something else.
	var ab := AbilityDatabase.get_ability_view(ABILITY_BREAK_ARMOR)
	_check(ab.weapon_range,
		"ArmorBreak (%d) is a weapon_range ability (got %s) — the swing branch is the one "
		% [ABILITY_BREAK_ARMOR, str(ab.weapon_range)] + "it should take")

	_check(_cast_seen and _cast_ability == ABILITY_BREAK_ARMOR,
		"the Knight cast ArmorBreak within %d ticks (seen=%s ability=%d)" % [
			CAST_DEADLINE_TICKS, str(_cast_seen), _cast_ability])

	if _cast_seen and units.size() > 0:
		var knight = units[0]
		var act: int = knight.activity
		var act_name: String = DisplayActivity.Activity.keys()[act] if act < DisplayActivity.Activity.keys().size() else str(act)
		_check(act == DisplayActivity.Activity.ATTACKING,
			"the Knight plays the WEAPON SWING pose, not the cast pose (activity=%s, "
			% act_name + "want ATTACKING; SPELL_CASTING would mean the weapon_range branch "
			+ "was skipped)")
		var slot: int = knight.last_resolution.body_slot if knight.last_resolution else -1
		print("  [info] resolved BODY slot = %d (weapon_type 1 = Sword swing)" % slot)

	_report_target_diagnostic()

	print("\n=== GPU Physical Ability Test: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0 or _passed == 0:
		print("[FAIL] GPU Physical Ability Test")
	else:
		print("[PASS] GPU Physical Ability Test")
	get_tree().quit()


## NOT an assertion — a note for whoever reads this log next.
##
## The Target cannot fight back here and it is not a fixture mistake. It stands on MAP042's
## (2,0) at h=10 while the Knight closes to (1,0) at h=13, and `check_striking` allows only
## VERTICAL_UP_HALFSTEPS = 2 upward against VERTICAL_DOWN_HALFSTEPS = 3 downward — so the
## Knight can strike DOWN at it and it cannot strike UP back. It should then reposition, and
## in the 6000-tick run that produced this test's old TIMEOUT it never did: it entered
## WALKING at tick 15 and emitted no further state change and no MOVE for the rest of the
## run. That is worth a look on its own; it is not what this test measures.
func _report_target_diagnostic() -> void:
	if units.size() < 2 or gpu_state_reader == null:
		return
	var states = gpu_state_reader.get_all_unit_states()
	if states.size() < 2:
		return
	var st = states[1]
	var s_id: int = int(st.get("state", -1))
	var s_name: String = GPUConstants.LOGICAL_ACTIVITY_NAMES[s_id] if s_id >= 0 and s_id < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(s_id)
	print("  [info] Target: state=%s pos=(%d,%d) timer=%d hp=%d — see _report_target_diagnostic" % [
		s_name, int(st.get("pos_x", -1)), int(st.get("pos_z", -1)),
		int(st.get("timer", -1)), int(st.get("hp", -1))])


func _print_ability_debug():
	print("\n=== PHYSICAL ABILITY TEST DEBUG ===")
	var ability := AbilityDatabase.get_ability_view(ABILITY_BREAK_ARMOR)
	print("[ABILITY_DATA] Break Armor (ID %d):" % ABILITY_BREAK_ARMOR)
	print("  start_seq_slot = %s (type: %s)" % [str(ability.start_seq_slot), typeof(ability.start_seq_slot)])
	print("  effect_anim_id = %d" % ability.effect_anim_id)
	print("  has_effect_file = %s" % str(ability.has_effect_file))
	print("  sustain_seq_slot = %s" % str(ability.sustain_seq_slot))
	print("  ability_type = %s" % ability.ability_type)
	print("  name = %s" % ability.name)
	print("  ct = %d" % ability.ct)
	print("  range = %d" % ability.range)
	print("  formula = %d" % ability.formula)

	# Check null comparison
	var start_seq = ability.start_seq_slot
	print("\n[NULL_CHECK] start_seq_slot value: %s" % str(start_seq))
	print("[NULL_CHECK] start_seq == null: %s" % str(start_seq == null))
	print("[NULL_CHECK] start_seq is null (typeof): %s" % str(typeof(start_seq) == TYPE_NIL))

	# Compare with Fire spell
	var fire := AbilityDatabase.get_ability_view(16)
	print("\n[COMPARISON] Fire (ID 16):")
	print("  start_seq_slot = %s (type: %s)" % [str(fire.start_seq_slot), typeof(fire.start_seq_slot)])

	# Print weapon animation lookup info (Sword = Swing base 128, MID height offset 2)
	print("\n[WEAPON_ANIM] Checking weapon animation for Sword (type 1):")
	var front = str(128 + 2)   # Swing_Attack_Mid_Front = 130
	var back = str(128 + 2 + 1) # Swing_Attack_Mid_Back = 131
	print("  front_anim = %s, back_anim = %s" % [front, back])

	# Verify the unit has this animation
	if units.size() > 0:
		var unit = units[0]
		print("\n[UNIT_ANIM_DATA] Knight animation data check:")
		print("  has animation_set: %s" % str(unit.animation_set != null))
		if unit.animation_set:
			print("  type1_seq has '%s': %s" % [front, str(unit.animation_set.type1_seq.has(front))])
			print("  type1_seq has '%s': %s" % [back, str(unit.animation_set.type1_seq.has(back))])
			if unit.animation_set.type1_seq.has(front):
				var seq = unit.animation_set.type1_seq[front]
				print("  SEQ %s opcodes (%d):" % [front, seq.size()])
				for j in range(min(seq.size(), 10)):
					print("    [%d] %s" % [j, str(seq[j])])
	print("=== END ABILITY DEBUG ===\n")


func on_state_changed(unit_idx: int, old_state: int, new_state: int):
	var unit_name = units[unit_idx].name if unit_idx < units.size() else "Unit%d" % unit_idx
	var old_name = GPUConstants.LOGICAL_ACTIVITY_NAMES[old_state] if old_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(old_state)
	var new_name = GPUConstants.LOGICAL_ACTIVITY_NAMES[new_state] if new_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(new_state)
	print("  [STATE] %s: %s -> %s" % [unit_name, old_name, new_name])

	if new_state == GPUConstants.LOGICAL_ACTIVITY_ACTING:
		# Print detailed info when entering ACTING state
		var states = gpu_state_reader.get_all_unit_states()
		if unit_idx < states.size():
			var state = states[unit_idx]
			print("  [ACTING_DETAIL] casting_ability_id=%d cast_target=%d weapon_type=%d" % [
				state.get("casting_ability_id", -1),
				state.get("cast_target", -1),
				state.get("weapon_type", 0)])
			print("  [ACTING_DETAIL] anim_flags=%d timer=%d projectile_frame=%d" % [
				state.get("anim_flags", -1),
				state.get("timer", -1),
				state.get("projectile_frame", -1)])

		# Print animation state of unit
		var unit = units[unit_idx]
		print("  [ACTING_ANIM] activity=%s current_anim=%s spell_cast_active=%s" % [
			DisplayActivity.Activity.keys()[unit.activity],
			unit.current_animation_index,
			str(_spell_cast_active.get(unit_idx, false))])


func on_hp_changed(unit_idx: int, old_hp: int, new_hp: int, delta: int):
	var unit_name = units[unit_idx].name if unit_idx < units.size() else "Unit%d" % unit_idx
	if delta < 0:
		print("  [DAMAGE] %s hit for %d! HP: %d -> %d" % [unit_name, abs(delta), old_hp, new_hp])
	elif delta > 0:
		print("  [HEAL] %s healed for %d! HP: %d -> %d" % [unit_name, delta, old_hp, new_hp])


## Informational only. A victory is not this test's verdict — ArmorBreak deals no HP damage,
## so the Knight cannot produce one, and treating "someone won" as PASS is what made the old
## version unpassable. `_finish` owns the verdict.
func on_victory(winning_team: int):
	print("\n[info] combat resolved — team %d won (not this test's criterion)" % winning_team)
	_finish()
