extends Node
## Slice 2 guard (issue #289 TIER-2): the SoundContainer write-side encoder + its dispatch
## through the single choke point (EffectEditSession.apply_edit).
##
## A SoundContainer is shared, effect-global (ADR-0073), so its address is ONE-dimensional
## — just the container `index` — unlike the sound TIMELINE's three (phase / channel_index /
## event_index). The writable fields are the raw resolver inputs: `mode` (0-4 named, 5+
## pass-through) and the three FEDS-pair ids `id_a`/`id_b`/`id_c`, all u8. The edit has NO
## framebuffer impact (invalidates_sim=false) but DOES change what every referencing trigger
## resolves to, so it declares `invalidates_containers` — the fan-out signal the page acts on.
##
## Seam under test: EffectEditSession.apply_edit(field_ref, new_raw) with
## field_ref.channel == "sound_container", plus undo() replaying it.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/SoundContainerChannelTest.tscn

const EffectData = ExMateriaEffects.EffectData
const EffectEditSession = preload("res://src/effects/studio/EffectEditSession.gd")
const SoundContainerModel = preload("res://src/effects/studio/SoundContainerModel.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_editing_mode_writes_the_raw_on_the_live_entry()
	_test_editing_id_a_writes_the_raw()
	_test_apply_edit_reports_before_and_after_raw()
	_test_container_edit_is_not_sim_invalidating_but_invalidates_containers()
	_test_undo_restores_the_previous_raw()
	_test_in_range_byte_is_faithful()
	_test_out_of_range_byte_is_flagged_but_still_applied()
	_test_unknown_field_is_a_noop()
	_test_edit_changes_what_the_container_resolves()

	print("\n=== SoundContainerChannelTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] SoundContainerChannelTest")
		get_tree().quit(1)
	else:
		print("[PASS] SoundContainerChannelTest")
		get_tree().quit(0)


## Two containers: index 0 = DIRECT_A(mode 0, id_a 5), index 1 = TRIPLE_CYCLE(mode 4,
## id_a 7 / id_b 8 / id_c 9). `data.sound_containers` is the raw doc the channel edits.
func _effect_with_containers():
	var data = EffectData.new()
	data.sound_containers = {"containers": [
		{"mode": 0, "id_a": 5, "id_b": 0, "id_c": 0, "index": 0},
		{"mode": 4, "id_a": 7, "id_b": 8, "id_c": 9, "index": 1},
	]}
	return data


func _ref(index: int, field: String) -> Dictionary:
	return {"channel": "sound_container", "index": index, "field": field}


## Editing a container's mode through the choke point writes the raw on the live entry
## (a reference the resolver/views read), so the container now selects a different way.
func _test_editing_mode_writes_the_raw_on_the_live_entry() -> void:
	var data = _effect_with_containers()
	var session = EffectEditSession.new(data)
	session.apply_edit(_ref(0, "mode"), 4)
	_assert_eq(int(data.sound_containers["containers"][0]["mode"]), 4,
		"container 0 mode written to TRIPLE_CYCLE")


## Editing an id (id_a) writes the raw FEDS-pair id on the live entry.
func _test_editing_id_a_writes_the_raw() -> void:
	var data = _effect_with_containers()
	var session = EffectEditSession.new(data)
	session.apply_edit(_ref(1, "id_a"), 12)
	_assert_eq(int(data.sound_containers["containers"][1]["id_a"]), 12,
		"container 1 id_a written")


func _test_apply_edit_reports_before_and_after_raw() -> void:
	var data = _effect_with_containers()
	var session = EffectEditSession.new(data)
	var res: Dictionary = session.apply_edit(_ref(1, "id_c"), 20)
	_assert_eq(int(res.get("before_raw", -1)), 9, "before_raw is the prior id_c")
	_assert_eq(int(res.get("after_raw", -1)), 20, "after_raw is the new id_c")


## A container edit repaints no framebuffer (invalidates_sim=false) but DOES change what
## referencing triggers resolve, so it declares invalidates_containers — the page's signal
## to recompute the container views + re-project dependent ghosts (Slice 3).
func _test_container_edit_is_not_sim_invalidating_but_invalidates_containers() -> void:
	var data = _effect_with_containers()
	var session = EffectEditSession.new(data)
	var res: Dictionary = session.apply_edit(_ref(0, "id_a"), 6)
	_assert_eq(bool(res.get("invalidates_sim", true)), false, "container edit is not sim-invalidating")
	_assert_eq(bool(res.get("invalidates_containers", false)), true, "container edit invalidates the container views")


func _test_undo_restores_the_previous_raw() -> void:
	var data = _effect_with_containers()
	var session = EffectEditSession.new(data)
	session.apply_edit(_ref(1, "mode"), 1)
	_assert_eq(int(data.sound_containers["containers"][1]["mode"]), 1, "mode edited to PARITY_A")
	_assert_true(session.undo(), "undo reported success")
	_assert_eq(int(data.sound_containers["containers"][1]["mode"]), 4, "undo restored TRIPLE_CYCLE")


## In-range u8 (0..255) lowers to the byte encoding → faithful.
func _test_in_range_byte_is_faithful() -> void:
	var data = _effect_with_containers()
	var session = EffectEditSession.new(data)
	var res: Dictionary = session.apply_edit(_ref(0, "id_a"), 200)
	_assert_true(bool(res.get("faithful", {}).get("ok", false)), "in-range id_a is faithful")


## Out of the 0..255 byte range → flagged non-faithful, but still applied (non-destructive
## advisory, as the other channels do).
func _test_out_of_range_byte_is_flagged_but_still_applied() -> void:
	var data = _effect_with_containers()
	var session = EffectEditSession.new(data)
	var res: Dictionary = session.apply_edit(_ref(0, "id_a"), 300)
	_assert_true(not bool(res.get("faithful", {}).get("ok", true)), "out-of-range id_a is flagged")
	_assert_eq(int(data.sound_containers["containers"][0]["id_a"]), 300, "value still applied")


## An unknown field name is a no-op ({} result → nothing recorded on the undo stack).
func _test_unknown_field_is_a_noop() -> void:
	var data = _effect_with_containers()
	var session = EffectEditSession.new(data)
	var res: Dictionary = session.apply_edit(_ref(0, "id_z"), 1)
	_assert_true(res.is_empty(), "unknown field returns empty (no-op)")
	_assert_true(not session.undo(), "nothing was recorded to undo")


## The effect-global fan-out at the DATA layer (ADR-0073): after editing a container's mode
## through the choke point, the resolver-driven view reflects the new selection — DIRECT_A
## (fires only id_a=5) becomes PARITY_A (alternates id_a=5 / id_b=8). This is what makes the
## change "visible on every trigger that plays that container": the shared doc the view (and
## playback resolver) reads is the SAME one the choke point mutated. No SPU needed — the view
## drives the real EffectSoundResolver forward over the mutated doc.
func _test_edit_changes_what_the_container_resolves() -> void:
	var data = EffectData.new()
	data.sound_containers = {"containers": [
		{"mode": 0, "id_a": 5, "id_b": 8, "id_c": 0, "index": 0},
	]}
	var session = EffectEditSession.new(data)
	var before := SoundContainerModel.container_view(data.sound_containers, null, null, 0)
	_assert_eq(before.get("emitted_ids", []), [5], "DIRECT_A fires only id_a before the edit")
	session.apply_edit(_ref(0, "mode"), 1)   # → PARITY_A
	var after := SoundContainerModel.container_view(data.sound_containers, null, null, 0)
	_assert_eq(str(after.get("mode_name", "")), "PARITY_A", "the view's mode name follows the edit")
	_assert_eq(after.get("emitted_ids", []), [5, 8], "PARITY_A now alternates id_a / id_b")


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % label)
