extends Node
## TDD guard for EffectEmitterSaver (ADR-0089 slice 4) — the emitter half of the
## Studio game→json→bin repack. `to_emitters_json` serializes the LIVE (possibly
## edited) EffectEmitter objects back into the parser-shaped dicts the byte-exact
## Python writer consumes: raw ints only, present-keys-only (a sparse emitter
## patches nothing it doesn't carry), child wiring re-normalized (-1 → 255).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectEmitterSaverTest.tscn

const EffectEmitter = ExMateriaEffects.EffectEmitter

const Saver = preload("res://src/effects/studio/EffectEmitterSaver.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const EffectCurveClass = ExMateriaEffects.EffectCurve

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_full_emitter_serializes_parser_shaped_raw_dict()
	_test_child_wiring_renormalizes_to_255()
	_test_sparse_emitter_emits_only_present_keys()
	_test_index_is_the_array_position()
	_test_a_minted_colour_curve_is_omitted_not_guessed()

	print("\n=== EffectEmitterSaverTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectEmitterSaverTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectEmitterSaverTest")
		get_tree().quit(0)


func _test_full_emitter_serializes_parser_shaped_raw_dict() -> void:
	var res: Dictionary = Saver.to_emitters_json(_effect())
	_assert_true(res.get("ok", false), "adapter reports ok")
	var em: Dictionary = res["json"][0]
	_assert_eq(em.get("anim_index"), 3, "direct u8 carried")
	_assert_eq(em.get("motion_type_flag"), 0x42, "packed byte carried from raw_data")
	_assert_eq(em.get("byte_00"), 0, "reserved byte carried for byte-identity")
	_assert_eq(em.get("raw", {}).get("position_start"), [28, -28, 0], "raw vec3 carried as ints")
	_assert_eq(em.get("raw", {}).get("radial_min_start"), 14336, "raw scalar carried")
	_assert_eq(em.get("curve_indices_raw"), [3, 0, 0, 0, 0, 0, 0, 0], "curve nibbles carried")
	# The PROVENANCE slot (7), not the live exploded address (1) — the nibble is a ROM table
	# slot and the live address is an offset into an array that routinely runs past 15.
	_assert_eq(em.get("color_curves", {}).get("g"), 7, "colour nibble carried by provenance")
	_assert_eq(em.get("inertia", {}).get("min_start"), 4096, "inertia raw int from the float field")
	_assert_eq(em.get("weight", {}).get("max_end"), -50, "weight raw int (signed)")
	_assert_eq(em.get("lifetime", {}).get("min_start"), 60, "lifetime frames carried")
	_assert_eq(em.get("spawn", {}).get("particle_count_start"), 2, "spawn count carried")
	_assert_eq(em.get("spawn", {}).get("interval_start"), 4, "spawn interval carried")
	_assert_eq(em.get("callback_params", {}).get("param_A8"), 7, "callback params carried")


func _test_child_wiring_renormalizes_to_255() -> void:
	var ed = _effect()
	ed.emitters[0].child_emitter_on_death = -1
	ed.emitters[0].child_emitter_mid_life = 2
	var em: Dictionary = Saver.to_emitters_json(ed)["json"][0]
	_assert_eq(em.get("child_emitter_on_death"), 255, "unwired saves as 255")
	_assert_eq(em.get("child_emitter_mid_life"), 2, "wired index passes through")


## A sparse emitter (no raw_data / callback_params) must emit dicts WITHOUT those
## keys — the writer then leaves the corresponding bytes verbatim.
func _test_sparse_emitter_emits_only_present_keys() -> void:
	var ed = EffectDataClass.new()
	ed.emitters.append(EffectEmitter.new())
	var res: Dictionary = Saver.to_emitters_json(ed)
	_assert_true(res.get("ok", false), "sparse emitter still ok")
	var em: Dictionary = res["json"][0]
	_assert_true(not em.has("motion_type_flag"), "absent packed byte omitted")
	_assert_true(not em.has("curve_indices_raw"), "absent curve nibbles omitted")
	_assert_true(not em.has("callback_params"), "empty callback params omitted")
	_assert_true(not em.has("color_curves"), "empty colour curves omitted")
	_assert_true(em.get("raw", {}).is_empty() or not em.has("raw"), "no raw keys invented")


func _test_index_is_the_array_position() -> void:
	var ed = _effect()
	ed.emitters.append(EffectEmitter.new())
	var json: Array = Saver.to_emitters_json(ed)["json"]
	_assert_eq(json[0].get("index"), 0, "first emitter is record 0")
	_assert_eq(json[1].get("index"), 1, "second emitter is record 1")


# --- fixtures -------------------------------------------------------------

## A MINTED colour curve has no ROM slot to name, so its channel is OMITTED and the writer
## leaves the record's nibble as the base has it. Guessing 0 would silently repoint the
## emitter at the first ROM curve — a real edit to an effect nobody touched. Same answer for
## an address that does not resolve (the 60 corpus references into an empty curves.json, all
## in E509/E510): "no curve" everywhere else must not become slot 0 here.
func _test_a_minted_colour_curve_is_omitted_not_guessed() -> void:
	var ed = _effect()
	ed.curves[1].index = -1                      # as CurveExplode.mint_identity stamps it
	ed.emitters[0].color_curves["b"] = 99        # an address past the end of the table
	var em: Dictionary = Saver.to_emitters_json(ed)["json"][0]
	var cc: Dictionary = em.get("color_curves", {})
	_assert_true(not cc.has("g"), "a minted channel is omitted")
	_assert_true(not cc.has("b"), "an unresolvable address is omitted")
	_assert_eq(cc.get("r"), 0, "…and the channels that DO have a slot still carry it")
	# All three gone → the key itself goes, so present-keys-only holds and the writer skips
	# both nibble bytes entirely rather than patching one of them with a partial dict.
	var bare = _effect()
	for c in bare.curves:
		c.index = -1
	var bare_em: Dictionary = Saver.to_emitters_json(bare)["json"][0]
	_assert_true(not bare_em.has("color_curves"),
		"no channel has a slot → the key is absent, not an empty dict")


func _curve_from(rom_slot: int):
	var c = EffectCurveClass.new()
	c.index = rom_slot
	c.samples.resize(160)
	c.samples.fill(0.0)
	return c


func _effect():
	var ed = EffectDataClass.new()
	var em = EffectEmitter.new()
	em.anim_index = 3
	em.anim_param = 1
	em.raw_data = {
		"position_start": [28, -28, 0],
		"radial_min_start": 14336,
		"curve_indices_raw": [3, 0, 0, 0, 0, 0, 0, 0],
		"motion_type_flag": 0x42, "animation_target_flag": 0x00,
		"emitter_flags_lo": 0x40, "emitter_flags_hi": 0x01,
		"byte_00": 0, "byte_05": 0,
	}
	# EXPLODED, the way load leaves it (ADR-0089 curve-ownership amendment). `color_curves`
	# holds addresses into the PRIVATE table, and each private curve remembers the ROM slot it
	# was copied from in `EffectCurve.index`. A fixture with a bare `{"r":0,"g":7,"b":0}` and no
	# curve table was the pre-explode shape and is not a state the live model can be in — which
	# matters, because the whole point of the assertion below is which of the two numbers
	# reaches the nibble.
	em.color_curves = {"r": 0, "g": 1, "b": 2}
	# `append`, not an array literal — `EffectData.curves` is typed `Array[EffectCurve]` and
	# refuses an untyped one.
	for rom_slot in [0, 7, 0]:
		ed.curves.append(_curve_from(rom_slot))
	em.inertia_min_start = 4096.0
	em.weight_max_end = -50.0
	em.lifetime_min_start = 60
	em.particle_count_start = 2
	em.spawn_interval_start = 4
	em.child_emitter_on_death = -1
	em.child_emitter_mid_life = -1
	em.callback_params = {"param_4C": 0, "param_A8": 7}
	ed.emitters.append(em)
	return ed


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
