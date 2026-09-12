extends Node
## TDD guard for EmitterChannel (ADR-0089) — the write-side encoder for SHARED
## emitter parameters. Raw ints are authoritative: an edit writes the raw value
## (raw_data array slot or the direct field), recomputes the converted Godot-unit
## cache with the parser's proven conversion (tiles /28 + Y-flip, angle TAU/4096,
## radial /14336, accel /114688), and always declares `invalidates_sim` (particles
## are born from params at spawn — no read-live). Out-of-range raw is a REFUSAL
## (`no_edit`), never a clamp. Edits ride EffectEditSession's scalar undo.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EmitterChannelTest.tscn

const EffectEmitter = ExMateriaEffects.EffectEmitter

const EmitterChannel = preload("res://src/effects/studio/EmitterChannel.gd")
const EffectDataClass = ExMateriaEffects.EffectData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_position_component_edit_writes_raw_and_recomputes_tile_cache()
	_test_y_component_cache_is_y_flipped()
	_test_angle_component_recomputes_radians()
	_test_radial_velocity_scalar_recomputes_units_per_frame()
	_test_accel_vec3_component_recomputes_accel_scale()
	_test_raw_direct_scalar_weight()
	_test_raw_direct_u16_lifetime_and_count()
	_test_u8_anim_index()
	_test_every_edit_invalidates_sim()
	_test_s16_overflow_is_refused_not_clamped()
	_test_u16_overflow_is_refused()
	_test_unknown_field_is_empty()
	_test_curve_assignment_writes_the_decoded_index_not_the_nibble()
	_test_curve_assignment_accepts_an_index_past_the_rom_table()
	_test_sibling_curve_assignments_are_independent()
	_test_curve_assignment_refuses_below_no_curve()
	_test_color_curve_assignment()
	_test_read_raw_mirrors_apply_raw_storage()
	_test_packed_subfield_edit_masks_one_field_and_recomputes_flags()
	_test_packed_boolean_edit_preserves_sibling_bits()
	_test_packed_two_bit_mode_refuses_overflow()
	_test_layout_affecting_packed_edits_report_relayout()
	_test_callback_param_edit()
	_test_child_wiring_picker_edit()
	_test_from_json_stashes_packed_bytes()
	_test_session_routes_emitter_channel_and_undo_restores_cache()

	print("\n=== EmitterChannelTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EmitterChannelTest")
		get_tree().quit(1)
	else:
		print("[PASS] EmitterChannelTest")
		get_tree().quit(0)


## Editing a position component writes the raw s16 into raw_data and re-derives the
## Godot-unit cache exactly as the parser does (28 raw units per tile).
func _test_position_component_edit_writes_raw_and_recomputes_tile_cache() -> void:
	var ed = _effect()
	var res: Dictionary = EmitterChannel.apply_raw(ed, _ref("position_start_x"), 56)
	_assert_eq(res.get("before_raw"), 28, "before_raw reads the pre-edit raw")
	_assert_eq(res.get("after_raw"), 56, "after_raw is the written raw")
	_assert_eq(ed.emitters[0].raw_data["position_start"][0], 56, "raw storage updated")
	_assert_approx(ed.emitters[0].position_start.x, 2.0, "cache re-derived: 56 raw / 28 = 2 tiles")


## The parser negates Y (FFT -Y is up); the recompute must mirror it or the refold lies.
func _test_y_component_cache_is_y_flipped() -> void:
	var ed = _effect()
	EmitterChannel.apply_raw(ed, _ref("position_start_y"), -56)
	_assert_eq(ed.emitters[0].raw_data["position_start"][1], -56, "raw Y stored unflipped")
	_assert_approx(ed.emitters[0].position_start.y, 2.0, "cache Y negated: -(-56)/28 = 2")


## Velocity angles cache in radians: raw 1024 of 4096 = quarter turn = TAU/4.
func _test_angle_component_recomputes_radians() -> void:
	var ed = _effect()
	EmitterChannel.apply_raw(ed, _ref("velocity_base_angle_start_x"), 1024)
	_assert_eq(ed.emitters[0].raw_data["angle_start"][0], 1024, "raw angle stored")
	_assert_approx(ed.emitters[0].velocity_base_angle_start.x, TAU / 4.0, "cache = raw * TAU/4096")


## Radial velocity caches in Godot units/frame (raw / 14336).
func _test_radial_velocity_scalar_recomputes_units_per_frame() -> void:
	var ed = _effect()
	var res: Dictionary = EmitterChannel.apply_raw(ed, _ref("radial_velocity_min_start"), 7168)
	_assert_eq(res.get("before_raw"), 14336, "before_raw from raw_data")
	_assert_approx(ed.emitters[0].radial_velocity_min_start, 0.5, "cache = raw / 14336")


## Acceleration components cache at the accel scale (raw / 114688) with Y-flip.
func _test_accel_vec3_component_recomputes_accel_scale() -> void:
	var ed = _effect()
	EmitterChannel.apply_raw(ed, _ref("acceleration_min_start_y"), -4096)
	_assert_eq(ed.emitters[0].raw_data["accel_min_start"][1], -4096, "raw stored")
	_assert_approx(ed.emitters[0].acceleration_min_start.y, 4096.0 / 114688.0,
		"cache Y negated at accel scale (raw / 114688)")


## Weight is stored raw on the emitter itself (the physics formula consumes it raw) —
## the edit writes the field directly, before_raw reads it back.
func _test_raw_direct_scalar_weight() -> void:
	var ed = _effect()
	var res: Dictionary = EmitterChannel.apply_raw(ed, _ref("weight_min_start"), 4096)
	_assert_eq(res.get("before_raw"), 0, "before_raw from the direct field")
	_assert_approx(ed.emitters[0].weight_min_start, 4096.0, "direct raw field written")


## Lifetime / particle count are unsigned 16-bit direct fields.
func _test_raw_direct_u16_lifetime_and_count() -> void:
	var ed = _effect()
	EmitterChannel.apply_raw(ed, _ref("lifetime_min_start"), 120)
	_assert_eq(ed.emitters[0].lifetime_min_start, 120, "lifetime written")
	EmitterChannel.apply_raw(ed, _ref("particle_count_start"), 8)
	_assert_eq(ed.emitters[0].particle_count_start, 8, "particle count written")


func _test_u8_anim_index() -> void:
	var ed = _effect()
	var res: Dictionary = EmitterChannel.apply_raw(ed, _ref("anim_index"), 5)
	_assert_eq(res.get("before_raw"), 3, "before_raw reads the u8")
	_assert_eq(ed.emitters[0].anim_index, 5, "anim_index written")


## Particles are born from emitter params at spawn — read-live is impossible, so EVERY
## emitter edit must force a re-fold.
func _test_every_edit_invalidates_sim() -> void:
	var ed = _effect()
	for f in ["position_start_x", "weight_min_start", "lifetime_min_start", "anim_index"]:
		var res: Dictionary = EmitterChannel.apply_raw(ed, _ref(f), 1)
		_assert_true(bool(res.get("invalidates_sim", false)), "%s invalidates the sim" % f)


## An s16 field refuses raw outside [-32768, 32767]: `no_edit`, faithful not-ok,
## storage untouched — a clamp would silently diverge from what the author typed.
func _test_s16_overflow_is_refused_not_clamped() -> void:
	var ed = _effect()
	var res: Dictionary = EmitterChannel.apply_raw(ed, _ref("position_start_x"), 40000)
	_assert_true(bool(res.get("no_edit", false)), "overflow edit reports no_edit")
	_assert_true(not bool(res.get("faithful", {}).get("ok", true)), "faithful explains the refusal")
	_assert_eq(ed.emitters[0].raw_data["position_start"][0], 28, "raw storage untouched")


func _test_u16_overflow_is_refused() -> void:
	var ed = _effect()
	var res: Dictionary = EmitterChannel.apply_raw(ed, _ref("lifetime_min_start"), 70000)
	_assert_true(bool(res.get("no_edit", false)), "u16 overflow refused")
	_assert_eq(ed.emitters[0].lifetime_min_start, 60, "storage untouched")
	var neg: Dictionary = EmitterChannel.apply_raw(ed, _ref("particle_count_start"), -1)
	_assert_true(bool(neg.get("no_edit", false)), "negative raw refused on an unsigned field")


func _test_unknown_field_is_empty() -> void:
	var ed = _effect()
	_assert_true(EmitterChannel.apply_raw(ed, _ref("no_such_field"), 1).is_empty(),
		"unknown field returns empty (choke point records nothing)")


## The choke point routes channel "emitter" and its scalar undo replays the pre-edit
## raw back through the channel — so the converted cache is restored too.
func _test_session_routes_emitter_channel_and_undo_restores_cache() -> void:
	var ed = _effect()
	var session = load("res://src/effects/studio/EffectEditSession.gd").new(ed)
	var res: Dictionary = session.apply_edit(_ref("position_start_x"), 84)
	_assert_eq(res.get("after_raw"), 84, "session dispatches to EmitterChannel")
	_assert_approx(ed.emitters[0].position_start.x, 3.0, "cache recomputed via session")
	_assert_true(session.undo(), "undo pops the scalar entry")
	_assert_eq(ed.emitters[0].raw_data["position_start"][0], 28, "undo restores the raw")
	_assert_approx(ed.emitters[0].position_start.x, 1.0, "undo restores the cache")
	# A refused edit records nothing: undo again finds an empty stack.
	session.apply_edit(_ref("position_start_x"), 40000)
	_assert_true(not session.undo(), "refused edit left nothing on the undo stack")


## A curve-assignment edit writes the DECODED `curves` index the runtime samples (raw 0 =
## none, N>0 = curve N−1) and leaves the ROM nibble in `curve_indices_raw` alone.
##
## It used to write the nibble and derive the cache from it. ADR-0089's curve-ownership
## amendment inverted that: after the explode a use site's index is a private array position
## (median ~22 per effect, max 67), which no 4-bit field can hold, so the decoded dict is the
## authoring truth and the nibble is read-only PROVENANCE the deferred compiler packs from.
func _test_curve_assignment_writes_the_decoded_index_not_the_nibble() -> void:
	var ed = _effect()
	var nibble_before: int = int(ed.emitters[0].raw_data["curve_indices_raw"][5])
	var res: Dictionary = EmitterChannel.apply_raw(ed, _ref("curve_lifetime"), 3)
	_assert_eq(res.get("before_raw"), 0, "before_raw is the pre-edit assignment")
	# Assigning/clearing a curve flips the group's end-axis relevance (end row +
	# header glyph appear/disappear), so it must re-project the inspector.
	_assert_true(bool(res.get("relayout", false)), "a curve edit relayouts (unhides the end axis)")
	_assert_eq(ed.emitters[0].curves.get("lifetime", -99), 2, "decoded index: raw 3 = curve 2")
	_assert_eq(int(ed.emitters[0].raw_data["curve_indices_raw"][5]), nibble_before,
		"the ROM nibble is left as provenance, not overwritten")
	EmitterChannel.apply_raw(ed, _ref("curve_lifetime"), 0)
	_assert_eq(ed.emitters[0].curves.get("lifetime", -99), -1, "raw 0 decodes to none (-1)")


## An index past the ROM's 15 slots is a LEGAL edit now — that cap was a PSX packing rule
## enforced in the authoring layer, and it is the compiler's to enforce at export. This is
## the ordinary case, not an exotic one: the explode alone puts most use sites past 15.
func _test_curve_assignment_accepts_an_index_past_the_rom_table() -> void:
	var ed = _effect()
	var res: Dictionary = EmitterChannel.apply_raw(ed, _ref("curve_lifetime"), 41)
	_assert_true(not bool(res.get("no_edit", false)), "an index past 15 is not refused")
	_assert_eq(ed.emitters[0].curves.get("lifetime", -99), 40, "…and lands in the decoded index")
	var colour: Dictionary = EmitterChannel.apply_raw(ed, _ref("color_curve_g"), 37)
	_assert_true(not bool(colour.get("no_edit", false)), "colour accepts one past 15 too")
	_assert_eq(ed.emitters[0].color_curves.get("g", -99), 37, "…and stores it")


## Two use sites sharing a nibble BYTE no longer share anything that matters: each writes its
## own decoded index, so one assignment cannot disturb the other's.
func _test_sibling_curve_assignments_are_independent() -> void:
	var ed = _effect()
	EmitterChannel.apply_raw(ed, _ref("curve_lifetime"), 3)
	EmitterChannel.apply_raw(ed, _ref("curve_target_offset"), 5)
	_assert_eq(ed.emitters[0].curves.get("lifetime", -99), 2, "sibling assignment untouched")
	_assert_eq(ed.emitters[0].curves.get("target_offset", -99), 4, "edited assignment decoded")
	EmitterChannel.apply_raw(ed, _ref("curve_homing_strength"), 2)
	EmitterChannel.apply_raw(ed, _ref("curve_homing_blend"), 3)
	_assert_eq(ed.emitters[0].curves.get("homing_strength", -99), 1, "2-bit-packed sibling A")
	_assert_eq(ed.emitters[0].curves.get("homing_blend", -99), 2, "2-bit-packed sibling B")


## Below "no curve" there is no address: -1 is the floor for colour (the storage encoding),
## and 0 (= none) is the floor for the +1 param convention.
func _test_curve_assignment_refuses_below_no_curve() -> void:
	var ed = _effect()
	_assert_true(bool(EmitterChannel.apply_raw(ed, _ref("color_curve_g"), -2).get("no_edit", false)),
		"colour refuses below -1")
	_assert_true(bool(EmitterChannel.apply_raw(ed, _ref("curve_lifetime"), -1).get("no_edit", false)),
		"a param refuses below 0 (0 IS none)")


## Colour curve assignments store in the decoded color_curves dict (the compiler
## reconstructs bytes 0x10/0x11 from them).
func _test_color_curve_assignment() -> void:
	var ed = _effect()
	var res: Dictionary = EmitterChannel.apply_raw(ed, _ref("color_curve_g"), 7)
	_assert_eq(res.get("before_raw"), 0, "before_raw is the pre-edit colour index")
	_assert_eq(ed.emitters[0].color_curves.get("g", -99), 7, "colour index written")
	_assert_true(bool(res.get("invalidates_sim", false)), "colour curve edit re-folds")


## A packed sub-field edit (camera-command-word style) masks ONLY its bits out of
## the host byte and re-derives the decoded flags cache. Fixture motion_type_flag =
## 0x42: align bit set (0x02) + target anchor mode 2 (CAMERA, 0x40).
func _test_packed_subfield_edit_masks_one_field_and_recomputes_flags() -> void:
	var ed = _effect()
	var res: Dictionary = EmitterChannel.apply_raw(ed, _ref("target_anchor_mode"), 4)
	_assert_eq(res.get("before_raw"), 2, "before_raw is the sub-field's own value (mode 2)")
	_assert_eq(ed.emitters[0].raw_data["motion_type_flag"], 0x82, "anchor bits replaced, align bit kept")
	_assert_eq(ed.emitters[0].flags.get("target_anchor_mode", ""), "TARGET", "decoded flags re-derived (0x80 = TARGET)")
	_assert_true(bool(res.get("invalidates_sim", false)), "packed edit re-folds")


func _test_packed_boolean_edit_preserves_sibling_bits() -> void:
	var ed = _effect()
	EmitterChannel.apply_raw(ed, _ref("align_to_velocity"), 0)
	_assert_eq(ed.emitters[0].raw_data["motion_type_flag"], 0x40, "align bit cleared, anchor mode kept")
	_assert_eq(ed.emitters[0].flags.get("align_to_velocity", true), false, "flags bool re-derived")


## child_death_mode is a 2-bit MODE (0 disabled / 1 spawn / 2 alt / 3 disabled),
## not a bool — an edit writes bits 0-1 of emitter_flags_lo and re-derives the
## child_death_enabled gate the runtime reads.
func _test_packed_two_bit_mode_refuses_overflow() -> void:
	var ed = _effect()
	EmitterChannel.apply_raw(ed, _ref("child_death_mode"), 1)
	_assert_eq(ed.emitters[0].raw_data["emitter_flags_lo"], 0x41, "mode bits written, colour bit kept")
	_assert_eq(ed.emitters[0].flags.get("child_death_enabled", false), true, "enabled gate re-derived")
	var refused: Dictionary = EmitterChannel.apply_raw(ed, _ref("child_death_mode"), 4)
	_assert_true(bool(refused.get("no_edit", false)), "2-bit mode refuses raw > 3")


## velocity_inward / align_to_facing feed the derived "Velocity mode" const row —
## those edits ask the page to re-project the section (relayout).
func _test_layout_affecting_packed_edits_report_relayout() -> void:
	var ed = _effect()
	var res: Dictionary = EmitterChannel.apply_raw(ed, _ref("velocity_inward"), 1)
	_assert_true(bool(res.get("relayout", false)), "velocity_inward relayouts the derived row")
	_assert_eq(ed.emitters[0].flags.get("velocity_inward", false), true, "flags re-derived")


## Callback params are REAL raw values read by the effect's native callback —
## editable in place in the callback_params dict.
func _test_callback_param_edit() -> void:
	var ed = _effect()
	var res: Dictionary = EmitterChannel.apply_raw(ed, _ref("callback_param_A8"), -100)
	_assert_eq(res.get("before_raw"), 7, "before_raw from callback_params")
	_assert_eq(ed.emitters[0].callback_params.get("param_A8"), -100, "param written")
	var refused: Dictionary = EmitterChannel.apply_raw(ed, _ref("callback_param_4C"), 300)
	_assert_true(bool(refused.get("no_edit", false)), "u8 callback param refuses overflow")


## Child wiring: raw u8 (255 = none) writes the -1-normalized runtime field, and
## the edit re-projects the score child graph (relayout).
func _test_child_wiring_picker_edit() -> void:
	var ed = _effect()
	var res: Dictionary = EmitterChannel.apply_raw(ed, _ref("child_emitter_on_death"), 0)
	_assert_eq(res.get("before_raw"), 255, "before_raw is 255 when unwired")
	_assert_eq(ed.emitters[0].child_emitter_on_death, 0, "wired to emitter 0")
	_assert_true(bool(res.get("relayout", false)), "rewiring re-projects the child graph")
	EmitterChannel.apply_raw(ed, _ref("child_emitter_on_death"), 255)
	_assert_eq(ed.emitters[0].child_emitter_on_death, -1, "raw 255 normalizes back to none (-1)")


## from_json must stash the packed control bytes into raw_data — the channel's
## storage for sub-field edits (the parser emits them top-level in emitters.json).
func _test_from_json_stashes_packed_bytes() -> void:
	var em = EffectEmitter.from_json({
		"byte_00": 1, "byte_05": 2, "motion_type_flag": 0x42,
		"animation_target_flag": 0x07, "emitter_flags_lo": 0x40, "emitter_flags_hi": 0x05,
	})
	_assert_eq(em.raw_data.get("motion_type_flag"), 0x42, "motion_type_flag stashed")
	_assert_eq(em.raw_data.get("animation_target_flag"), 0x07, "animation_target_flag stashed")
	_assert_eq(em.raw_data.get("emitter_flags_lo"), 0x40, "emitter_flags_lo stashed")
	_assert_eq(em.raw_data.get("emitter_flags_hi"), 0x05, "emitter_flags_hi stashed")
	_assert_eq(em.raw_data.get("byte_00"), 1, "reserved byte_00 stashed for the const row")
	_assert_eq(em.raw_data.get("byte_05"), 2, "reserved byte_05 stashed for the const row")


## read_raw is the projector's read side of the ONE field→storage map: whatever
## apply_raw wrote, read_raw reports — for every storage kind. Missing raw_data
## keys read as 0 (defensive: projection must not crash on a sparse fixture).
func _test_read_raw_mirrors_apply_raw_storage() -> void:
	var ed = _effect()
	var em = ed.emitters[0]
	_assert_eq(EmitterChannel.read_raw(em, "position_start_x"), 28, "vec3 raw read")
	_assert_eq(EmitterChannel.read_raw(em, "radial_velocity_min_start"), 14336, "scalar raw read")
	_assert_eq(EmitterChannel.read_raw(em, "anim_index"), 3, "direct u8 read")
	EmitterChannel.apply_raw(ed, _ref("curve_lifetime"), 3)
	_assert_eq(EmitterChannel.read_raw(em, "curve_lifetime"), 3, "curve assignment read")
	EmitterChannel.apply_raw(ed, _ref("color_curve_b"), 9)
	_assert_eq(EmitterChannel.read_raw(em, "color_curve_b"), 9, "colour nibble read")
	_assert_eq(EmitterChannel.read_raw(em, "spread_start_z"), 0, "missing raw_data key reads 0")


# --- fixtures -------------------------------------------------------------

## One emitter with parser-consistent raw + cache pairs: position (28, -28, 0) raw =
## (1, 1, 0) tiles after Y-flip; radial min_start raw 14336 = 1.0 units/frame.
func _effect():
	var ed = EffectDataClass.new()
	var em = EffectEmitter.new()
	em.anim_index = 3
	em.raw_data = {
		"position_start": [28, -28, 0],
		"angle_start": [0, 0, 0],
		"accel_min_start": [0, 0, 0],
		"radial_min_start": 14336,
		"curve_indices_raw": [0, 0, 0, 0, 0, 0, 0, 0],
		# Packed control bytes: align bit (0x02) + target anchor CAMERA (0x40);
		# colour-curve enable (0x40); homing threshold 1.
		"motion_type_flag": 0x42, "animation_target_flag": 0x00,
		"emitter_flags_lo": 0x40, "emitter_flags_hi": 0x01,
	}
	em.curves = {"lifetime": -1, "target_offset": -1, "homing_strength": -1, "homing_blend": -1}
	em.color_curves = {"r": 0, "g": 0, "b": 0}
	em.callback_params = {"param_4C": 0, "param_A8": 7}
	em.flags = {"align_to_velocity": true, "target_anchor_mode": "CAMERA",
		"velocity_inward": false, "child_death_enabled": false}
	em.position_start = Vector3(1.0, 1.0, 0.0)
	em.radial_velocity_min_start = 1.0
	ed.emitters.append(em)
	return ed


func _ref(field: String) -> Dictionary:
	return {"channel": "emitter", "emitter_index": 0, "field": field}


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) < 0.0001:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %f, got %f" % [label, expected, actual])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
