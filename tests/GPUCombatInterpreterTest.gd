extends Node
## GPUCombatInterpreter unit test (ADR-0018). Pure GDScript — no RenderingDevice,
## no Unit nodes, no scene. Feeds synthetic snapshot dicts and asserts the event
## list: first-sight seeding, death precedence (suppresses other events), and the
## hp / mp / stat / position / projectile-fired diffs in their documented order.
## Covers the simple-diff slice; cast/charge events arrive in a later slice.

const InterpClass = preload("res://src/gpu/GPUCombatInterpreter.gd")

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true


# Build a full snapshot dict from defaults, applying `overrides`.
func _state(overrides: Dictionary = {}) -> Dictionary:
	var s := {
		"flags": 0,
		"pos_x": 0, "pos_z": 0,
		"hp": 100, "mp": 10,
		"anim_flags": 0,
		"pa": 5, "ma": 5, "speed": 7, "wp": 4, "s_ev": 10,
		"state": GPUConstants.LOGICAL_ACTIVITY_IDLE,
		"casting_ability_id": -1, "cast_target": -1, "cast_step_id": 0,
	}
	for k in overrides:
		s[k] = overrides[k]
	return s


# First event of `kind` in a list, or null.
func _first(events: Array, kind: int):
	for e in events:
		if e.kind == kind:
			return e
	return null


# Extract the kind sequence from an event list for order assertions.
func _kinds(events: Array) -> Array:
	var out := []
	for e in events:
		out.append(e.kind)
	return out


func _ready() -> void:
	_test_first_sight_seeds_no_events()
	_test_hp_damage_and_heal()
	_test_mp_change()
	_test_stat_change()
	_test_position_change()
	_test_projectile_fired_is_edge()
	_test_death_emits_once_and_suppresses()
	_test_cast_began_once_per_cast_step()
	_test_no_cast_began_without_ability()
	_test_event_order_in_one_frame()
	_test_forget_reseeds()

	if _failed:
		print("[FAIL] GPUCombatInterpreter test")
	else:
		print("[PASS] GPUCombatInterpreter: seed, death precedence, hp/mp/stat/pos/projectile diffs, cast-step dedup + state change OK")
	get_tree().quit()


func _test_first_sight_seeds_no_events() -> void:
	var it = InterpClass.new()
	var ev = it.interpret(0, _state({"hp": 80}))
	_check(ev.is_empty(), "first sight of a unit seeds and emits nothing")


func _test_hp_damage_and_heal() -> void:
	var it = InterpClass.new()
	it.interpret(0, _state())  # seed at hp=100
	var dmg = it.interpret(0, _state({"hp": 70}))
	_check(_kinds(dmg) == [InterpClass.EventKind.HP_CHANGED], "hp drop ⇒ single HP_CHANGED")
	_check(dmg[0].delta == -30 and not dmg[0].was_heal, "damage delta=-30, was_heal=false")
	_check(dmg[0].new_value == 70 and dmg[0].prev_value == 100, "HP_CHANGED carries new/prev")
	var heal = it.interpret(0, _state({"hp": 90}))
	_check(heal[0].delta == 20 and heal[0].was_heal, "heal delta=+20, was_heal=true")


func _test_mp_change() -> void:
	var it = InterpClass.new()
	it.interpret(0, _state())  # seed at mp=10
	var ev = it.interpret(0, _state({"mp": 4}))
	_check(_kinds(ev) == [InterpClass.EventKind.MP_CHANGED], "mp change ⇒ MP_CHANGED")
	_check(ev[0].new_value == 4 and ev[0].prev_value == 10, "MP_CHANGED carries new/prev")


func _test_stat_change() -> void:
	var it = InterpClass.new()
	it.interpret(0, _state())  # seed pa=5
	var ev = it.interpret(0, _state({"pa": 3}))
	_check(_kinds(ev) == [InterpClass.EventKind.STAT_CHANGED], "stat change ⇒ STAT_CHANGED")
	_check(ev[0].stat_key == "pa" and ev[0].stat_label == "PA", "STAT_CHANGED names the stat")
	_check(ev[0].prev_value == 5 and ev[0].new_value == 3, "STAT_CHANGED carries old/new")


func _test_position_change() -> void:
	var it = InterpClass.new()
	it.interpret(0, _state({"pos_x": 1, "pos_z": 1}))  # seed
	var ev = it.interpret(0, _state({"pos_x": 2, "pos_z": 1}))
	_check(_kinds(ev) == [InterpClass.EventKind.POSITION_CHANGED], "pos change ⇒ POSITION_CHANGED")
	_check(ev[0].from_pos == Vector2i(1, 1) and ev[0].to_pos == Vector2i(2, 1), "POSITION_CHANGED carries from/to")


func _test_projectile_fired_is_edge() -> void:
	var it = InterpClass.new()
	it.interpret(0, _state({"anim_flags": 0}))  # seed
	var fired = it.interpret(0, _state({"anim_flags": 2}))
	_check(_kinds(fired) == [InterpClass.EventKind.PROJECTILE_FIRED], "anim_flags bit1 0→1 ⇒ PROJECTILE_FIRED")
	var still = it.interpret(0, _state({"anim_flags": 2}))
	_check(still.is_empty(), "bit stays set ⇒ no repeat PROJECTILE_FIRED (edge only)")


func _test_death_emits_once_and_suppresses() -> void:
	var it = InterpClass.new()
	it.interpret(0, _state())  # seed alive
	# Die AND change mp the same frame — death must suppress the mp event.
	var died = it.interpret(0, _state({"flags": 1, "hp": 0, "mp": 0}))
	_check(_kinds(died) == [InterpClass.EventKind.DIED], "death suppresses other events (only DIED)")
	var after = it.interpret(0, _state({"flags": 1, "hp": 0, "mp": 0}))
	_check(after.is_empty(), "already-dead unit emits nothing")


func _test_cast_began_once_per_cast_step() -> void:
	var it = InterpClass.new()
	it.interpret(0, _state())  # seed idle
	# Charge: casting_ability_id set, cast_step unchanged ⇒ no CAST_BEGAN yet.
	var ch = it.interpret(0, _state({
		"state": GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING, "casting_ability_id": 12, "cast_target": 1, "cast_step_id": 0,
	}))
	_check(_first(ch, InterpClass.EventKind.CAST_BEGAN) == null, "charging (no cast_step bump) ⇒ no CAST_BEGAN")
	_check(_first(ch, InterpClass.EventKind.STATE_CHANGED) != null, "idle→charging ⇒ STATE_CHANGED")
	# Enter acting: cast_step bumps to 1, GPU cleared casting_ability_id ⇒ resolve from prev.
	var act = it.interpret(0, _state({
		"state": GPUConstants.LOGICAL_ACTIVITY_ACTING, "casting_ability_id": -1, "cast_target": 1, "cast_step_id": 1,
	}))
	var cb = _first(act, InterpClass.EventKind.CAST_BEGAN)
	_check(cb != null, "→acting w/ new cast_step + valid ability ⇒ CAST_BEGAN")
	_check(cb.ability_id == 12 and cb.target == 1, "CAST_BEGAN resolves ability from prev casting (got %d,%d)" % [cb.ability_id, cb.target])
	var sc = _first(act, InterpClass.EventKind.STATE_CHANGED)
	_check(sc != null and sc.cast_began_this_frame, "STATE_CHANGED carries cast_began_this_frame=true")
	# Stay acting, same cast_step ⇒ no repeat CAST_BEGAN.
	var act2 = it.interpret(0, _state({
		"state": GPUConstants.LOGICAL_ACTIVITY_ACTING, "casting_ability_id": -1, "cast_target": 1, "cast_step_id": 1,
	}))
	_check(_first(act2, InterpClass.EventKind.CAST_BEGAN) == null, "same cast_step ⇒ no repeat CAST_BEGAN")


func _test_no_cast_began_without_ability() -> void:
	var it = InterpClass.new()
	it.interpret(0, _state())  # seed idle
	# Physical attack: enters acting, cast_step bumps, but no ability/target.
	var act = it.interpret(0, _state({
		"state": GPUConstants.LOGICAL_ACTIVITY_ACTING, "casting_ability_id": -1, "cast_target": -1, "cast_step_id": 1,
	}))
	_check(_first(act, InterpClass.EventKind.CAST_BEGAN) == null, "attack (no ability) ⇒ no CAST_BEGAN despite cast_step bump")
	var sc = _first(act, InterpClass.EventKind.STATE_CHANGED)
	_check(sc != null and not sc.cast_began_this_frame, "attack ⇒ STATE_CHANGED with cast_began_this_frame=false")


func _test_event_order_in_one_frame() -> void:
	var it = InterpClass.new()
	it.interpret(0, _state({"pos_x": 0, "pos_z": 0, "mp": 10, "anim_flags": 0, "hp": 100, "pa": 5}))
	var ev = it.interpret(0, _state({
		"pos_x": 1, "pos_z": 0, "mp": 8, "anim_flags": 2, "hp": 90, "pa": 4,
	}))
	_check(_kinds(ev) == [
		InterpClass.EventKind.POSITION_CHANGED,
		InterpClass.EventKind.MP_CHANGED,
		InterpClass.EventKind.PROJECTILE_FIRED,
		InterpClass.EventKind.HP_CHANGED,
		InterpClass.EventKind.STAT_CHANGED,
	], "one frame emits events in documented order (got %s)" % str(_kinds(ev)))


func _test_forget_reseeds() -> void:
	var it = InterpClass.new()
	it.interpret(0, _state())  # seed
	_check(not it.interpret(0, _state({"hp": 50})).is_empty(), "forget: change emits before forget")
	it.forget(0)
	_check(it.interpret(0, _state({"hp": 50})).is_empty(), "after forget(), next interpret re-seeds (no events)")
