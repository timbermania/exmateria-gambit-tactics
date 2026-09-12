extends "res://tests/GPUMeleeCombatTest.gd"
## Live end-to-end guard for the faithful post-battle pose (ADR-0026 follow-up).
## (GPUMeleeCombatTest has no class_name, so extend it by path.)
##
## Reuses the melee fixture (two full-HP swordsmen, one dies) but flips the loop
## to `celebrate_on_victory = false`. The GPU still reports the winner in the
## CELEBRATING settled state (so stage_victory declares the win — the handshake
## is untouched), but the CPU must render the winner in its faithful
## HP-appropriate pose: a full-HP survivor settles to plain IDLE, NOT the dance.
##
## Complements the pure-logic CombatVictoryPoseTest by proving the wiring holds
## across the real interpret → apply → victory pump.
##
## Run: "$GODOT" --path . res://tests/CombatFaithfulPoseTest.tscn


func get_test_name() -> String:
	return "Combat Faithful Pose Test"


func _ensure_loop() -> void:
	# The base creates + configures the loop here (setting celebrate=true); flip
	# it to faithful right after, before start_battle wires the pump. Done here
	# rather than in _ready because the base _ready is a coroutine that awaits, so
	# the loop does not yet exist when our _ready runs.
	super()
	combat_loop.celebrate_on_victory = false


# Replace the base's celebrating-invariant victory hook: in faithful mode the
# winner must be IDLE, not CELEBRATING. Bound virtually via the base's
# `victory.connect(_on_loop_victory)`, so this override is what runs.
func _on_loop_victory(winner: int, _team0_alive: int, _team1_alive: int) -> void:
	var A = DisplayActivity.Activity
	if winner < 0:
		print("\n[FAIL] Combat Faithful Pose Test: ended in a draw")
		get_tree().quit(1)
		return
	if not gpu_state_reader:
		print("\n[FAIL] Combat Faithful Pose Test: no gpu_state_reader")
		get_tree().quit(1)
		return

	var states = gpu_state_reader.get_all_unit_states()
	var ok := true
	var checked := 0
	for i in range(units.size()):
		var unit = units[i]
		if not is_instance_valid(unit):
			continue
		var st: Dictionary = states[i] if i < states.size() else {}
		if st.get("team", -1) != winner or _is_unit_dead(st):
			continue
		checked += 1
		# Full-HP fixture → the faithful settle is plain IDLE.
		if unit.activity != A.IDLE:
			print("\n[FAIL] faithful: winner %s activity=%s (want IDLE) — GPU state=%s" % [
				unit.name, A.keys()[unit.activity], st.get("state", -1)])
			ok = false
		elif unit.activity == A.CELEBRATING:
			print("\n[FAIL] faithful: winner %s is still CELEBRATING (the dance was not disabled)" % unit.name)
			ok = false

	if checked == 0:
		print("\n[FAIL] Combat Faithful Pose Test: no surviving winner to check")
		get_tree().quit(1)
		return
	if ok:
		print("\n[PASS] Combat Faithful Pose Test — winner settled to IDLE (no victory dance)")
	else:
		print("\n[FAIL] Combat Faithful Pose Test")
	get_tree().quit(0 if ok else 1)
