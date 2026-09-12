extends Node
## AbilityView fixture test (ADR-0008). Pure GDScript — no AbilityDatabase, no
## GPU / RenderingDevice, no scene. Builds views over hand-made record dicts via
## AbilityView.from_record() and checks the three behaviors the generator's
## type inference produces:
##
##   1. Typed coercion — each accessor returns its inferred type.
##   2. Default-on-absent — a missing key returns the typed zero-value (the
##      sparse-record case: 144 abilities omit the combat fields).
##   3. Null preservation — nullable fields (effect_id / effect_file) return
##      null for both present-null and absent, never a sentinel; and the
##      never-present fields (start_seq_slot / sustain_seq_slot) are nullable.
##
## Plus has() (distinguishes absent from a genuine zero) and is_empty().

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityView = ExMateriaAlmanac.AbilityView



func _ready() -> void:
	var failed := false

	# 1. Typed accessors coerce to their inferred type.
	var full := AbilityView.from_record({
		"name": "Bolt",
		"mp_cost": 6,
		"ct": 4,
		"range": 5,
		"formula": 8,
		"elements": ["Lightning"],
		"reflectable": true,
		"ability_type": "Normal",
		"effect_id": 20,
	})
	failed = _expect(full.name == "Bolt", "name reads through", failed)
	failed = _expect(full.mp_cost == 6 and typeof(full.mp_cost) == TYPE_INT, "mp_cost is int 6", failed)
	failed = _expect(full.reflectable == true, "reflectable is bool true", failed)
	failed = _expect(full.elements == ["Lightning"], "elements is the array", failed)
	failed = _expect(full.effect_id == 20, "effect_id present non-null", failed)

	# 2. Absent keys fall back to typed zero-defaults (the sparse-field case).
	var sparse := AbilityView.from_record({"name": "Wish"})
	failed = _expect(sparse.mp_cost == 0, "absent int -> 0", failed)
	failed = _expect(sparse.range == 0, "absent int 'range' -> 0", failed)
	failed = _expect(sparse.reflectable == false, "absent bool -> false", failed)
	failed = _expect(sparse.ability_type == "", "absent String -> ''", failed)
	failed = _expect(sparse.elements == [], "absent Array -> []", failed)
	failed = _expect(not sparse.has("mp_cost"), "has() false when absent", failed)
	failed = _expect(full.has("mp_cost"), "has() true when present", failed)

	# 3. Nullable fields preserve null (present-null AND absent both -> null).
	var nulled := AbilityView.from_record({"effect_id": null})
	failed = _expect(nulled.effect_id == null, "present-null effect_id -> null", failed)
	failed = _expect(sparse.effect_id == null, "absent effect_id -> null", failed)
	failed = _expect(sparse.sustain_seq_slot == null, "never-present field -> null", failed)

	# 4. Empty record.
	var empty := AbilityView.from_record({})
	failed = _expect(empty.is_empty(), "empty record is_empty()", failed)
	failed = _expect(not full.is_empty(), "non-empty record not is_empty()", failed)

	if failed:
		print("[FAIL] AbilityView fixture test")
	else:
		print("[PASS] AbilityView: coercion + defaults + null-preservation OK")
	get_tree().quit()


func _expect(cond: bool, label: String, failed_so_far: bool) -> bool:
	if not cond:
		print("[FAIL] %s" % label)
		return true
	return failed_so_far
