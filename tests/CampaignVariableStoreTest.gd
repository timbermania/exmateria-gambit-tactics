extends Node
## X1 step 3 — one variable store, shared between the cutscene VM and the world map.
##
## ADR-0179. The port had three disjoint stores where the ROM has one array at
## `0x8005771C`, and the VM's was cleared on every `start()` and modelled only words
## `0..127`. Both defects are load-bearing: the first evaporates the story counter a
## scenario writes, the second silently drops the bit and nibble writes that go with it.
##
## The numbers below are not invented for the test — they are scenario 14's own bytecode,
## `assets/scenarios/chunks/scenario_014_chunk.json` offsets 1385–1436, driven through the
## VM's REAL `Zero` / `Add` handlers. *Balbanes's Death* is the scene that ends the first
## world-map hop, and `var[110] = 2` is exactly what node 24 Mandalia Plains' `enter` is
## gated on. If this test passes, the campaign loop closes.
##
## Run: <GODOT> --path . --quit-after 10 res://tests/CampaignVariableStoreTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const CHUNK_14 := "res://assets/scenarios/chunks/scenario_014_chunk.json"

## What scenario 14 writes on its way out, by var id. Two of these live in regions the
## old per-VM Dictionary did not model at all.
const SCENARIO_14_WRITES := {
	110: 2,     # word   — the STORY COUNTER; opens Mandalia Plains
	49: 6,      # word
	445: 1,     # BIT    (128..863)
	963: 1,     # NIBBLE (864..1023)
	964: 1,
	965: 1,
	1008: 1,
}

var _passed := 0
var _failed := 0


func _ready() -> void:
	_test_bare_vm_owns_a_private_store()
	_test_injection_shares_the_array()
	_test_null_injection_is_a_noop()
	_test_scenario_14_advances_the_story_counter()
	_test_all_three_regions_round_trip()

	if _failed > 0:
		print("[FAIL] CampaignVariableStoreTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] CampaignVariableStoreTest — %d/%d" % [_passed, _passed])
	get_tree().quit(0)


func _new_vm() -> Node:
	var vm = ScenarioVMClass.new()
	add_child(vm)
	return vm


## An unowned VM behaves exactly as it did before: its own store, everything reads 0.
func _test_bare_vm_owns_a_private_store() -> void:
	var vm := _new_vm()
	_true("a bare VM has a store", vm.vars_store != null)
	_eq("unwritten ids read 0", vm.vars_store.get_var(110), 0)
	_true("it is NOT Campaign's", vm.vars_store != Campaign.vars())
	vm.queue_free()


## The point of the whole ADR: a write inside the VM is visible to the world map, because
## it is the same object.
func _test_injection_shares_the_array() -> void:
	var shared := WorldMapVariables.new()
	var vm := _new_vm()
	vm.set_variable_store(shared)
	_true("the VM now holds the injected store", vm.vars_store == shared)
	vm.vars_store.set_var(110, 7)
	_eq("a VM write is visible through the shared store", shared.get_var(110), 7)

	var progress := WorldMapProgress.new()
	progress.vars = shared
	_eq("...and through WorldMapProgress's named query", progress.story_counter(), 7)
	vm.queue_free()


## A mis-wire must degrade, not crash mid-scene.
func _test_null_injection_is_a_noop() -> void:
	var vm := _new_vm()
	var before = vm.vars_store
	vm.set_variable_store(null)
	_true("null injection keeps the private store", vm.vars_store == before)
	vm.queue_free()


## Scenario 14's real writes, through the real handlers.
func _test_scenario_14_advances_the_story_counter() -> void:
	var instructions := _chunk_instructions(CHUNK_14)
	if instructions.is_empty():
		_fail("%s missing or unreadable" % CHUNK_14)
		return

	var store := WorldMapVariables.new()
	var vm := _new_vm()
	vm.set_variable_store(store)

	var applied := 0
	for inst in instructions:
		match String(inst.get("name", "")):
			"Zero":
				vm._op_var_zero(inst)
				applied += 1
			"Add":
				vm._op_var_add(inst)
				applied += 1
	_true("the chunk carried Zero/Add pairs to run", applied > 0)

	for id in SCENARIO_14_WRITES:
		_eq("scenario 14 writes var[%d]" % id,
			store.get_var(int(id)), int(SCENARIO_14_WRITES[id]))

	var progress := WorldMapProgress.new()
	progress.vars = store
	_eq("the story counter is 2 — Mandalia Plains is now live",
		progress.story_counter(), 2)
	vm.queue_free()


## The old per-VM Dictionary modelled words 0..127 only, so scenario 14's writes to 445 /
## 963..965 / 1008 went nowhere. Pin all three regions at their boundaries.
func _test_all_three_regions_round_trip() -> void:
	var s := WorldMapVariables.new()
	s.set_var(0, 0xDEADBEEF)
	_eq("word region, first slot", s.get_var(0), 0xDEADBEEF)
	s.set_var(127, 42)
	_eq("word region, last slot", s.get_var(127), 42)
	s.set_var(128, 1)
	_eq("bit region, first bit", s.get_var(128), 1)
	s.set_var(863, 1)
	_eq("bit region, last bit", s.get_var(863), 1)
	s.set_var(864, 0xF)
	_eq("nibble region, first nibble", s.get_var(864), 0xF)
	s.set_var(1023, 0xA)
	_eq("nibble region, last nibble", s.get_var(1023), 0xA)
	# Neighbours must not smear — a bit write that clobbered its word would pass every
	# single-slot assertion above.
	s.set_var(129, 0)
	_eq("writing bit 129 leaves bit 128 alone", s.get_var(128), 1)
	s.set_var(865, 0)
	_eq("writing nibble 865 leaves nibble 864 alone", s.get_var(864), 0xF)


func _chunk_instructions(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var d: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(d) != TYPE_DICTIONARY:
		return []
	return d.get("instructions", [])


func _eq(what: String, got: Variant, want: Variant) -> void:
	if str(got) == str(want):
		_passed += 1
		return
	_failed += 1
	print("  FAIL %s: got %s, want %s" % [what, got, want])


func _true(what: String, ok: bool) -> void:
	if ok:
		_passed += 1
		return
	_failed += 1
	print("  FAIL %s" % what)


func _fail(msg: String) -> void:
	_failed += 1
	print("  FAIL %s" % msg)
