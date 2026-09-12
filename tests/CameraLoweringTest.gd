extends Node
## TDD guard for the CAMERA coalescing lowerer (ADR-0086).
##
## Camera has two models: the AUTHORING model is three independent sub-channel
## lanes (angle / position / zoom) of ordinary lane events; the STORAGE model is
## the flat `channel_mask` + shared-command keyframe array. `CameraLowering` is the
## compiler between them:
##   * `parse(table)`  — expand one masked keyframe into one event per set mask bit.
##   * `lower(lanes)`  — coalesce events that COINCIDE (same end_frame) AND AGREE
##     (same source / interp / param / flags) into one masked keyframe; SPLIT them
##     into separate keyframes when they disagree.
## parse and lower are inverses. Faithful is SEMANTIC (equal per-sub-channel event
## streams), NOT byte-exact (ADR-0086) — irregular ROM packings and mask-ignored
## junk vecs (e.g. E317 for_each kf1's non-zero angle/position under a zoom-only
## mask) are NOT required to survive an untouched round-trip.
##
## Seams under test (pre-agreed, handoff-camera-subchannel-lowering-build.md):
##   1. CameraLowering.parse(PhaseTable) -> {angle,position,zoom: [event]}
##   2. CameraLowering.lower({angle,position,zoom}) -> PhaseTable   (merge + split)
##   3. round-trip semantic equivalence on real E317 for_each
##
## Command-word bit layout (independent source of truth, mirrors parse_effect):
##   mask 0x0007 | param<<3 (0x0018) | source 0x01E0 | interp 0x1E00 | flags<<13.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/CameraLoweringTest.tscn

const CameraData = ExMateriaEffects.CameraData
const CameraLowering = preload("res://src/effects/studio/CameraLowering.gd")

# Positioned command-word bits (already-shifted, like CameraChannel's decode maps).
const SRC_MAP := 0x0C0
const SRC_DIRECT := 0x040
const SRC_TARGET := 0x000
const INTERP_COSINE_A := 0x0400

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_parse_expands_each_set_mask_bit_into_its_own_event()
	_test_lower_merges_agreeing_coincident_events()
	_test_lower_splits_disagreeing_coincident_events()
	_test_a_tie_keeps_each_lane_in_its_own_authored_order()
	_test_roundtrip_is_semantically_equivalent_on_real_E317()
	_test_capacity_faithful_flags_over_native_slots()

	print("\n=== CameraLoweringTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] CameraLoweringTest")
		get_tree().quit(1)
	else:
		print("[PASS] CameraLoweringTest")
		get_tree().quit(0)


# --- Slice 1: parse (expand) -----------------------------------------------

## A masked keyframe with mask=3 fans into one angle event AND one position event,
## each carrying the SHARED command word (source/interp/param/flags) but its OWN
## channel value vec. A zoom-only keyframe fans into a single zoom event. mask=0
## (padding) keyframes produce nothing.
func _test_parse_expands_each_set_mask_bit_into_its_own_event() -> void:
	var table = _table([
		# idx0: empty padding — mask 0, contributes nothing.
		_kf(0, 0, 0, Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO),
		# idx1: mask 3 (angle+position), MAP, COSINE_A. angle=(1,2,3) position=(4,5,6).
		_kf(1, 10, INTERP_COSINE_A | SRC_MAP | 3, Vector3i(1, 2, 3), Vector3i(4, 5, 6), Vector3i.ZERO),
		# idx2: mask 4 (zoom only), DIRECT, COSINE_A. zoom slot0=100.
		_kf(2, 20, INTERP_COSINE_A | SRC_DIRECT | 4, Vector3i.ZERO, Vector3i.ZERO, Vector3i(100, 0, 0)),
	], 2)

	var lanes: Dictionary = CameraLowering.parse(table)

	_assert_eq(lanes["angle"].size(), 1, "one angle event (from the mask=3 keyframe)")
	_assert_eq(lanes["position"].size(), 1, "one position event (from the mask=3 keyframe)")
	_assert_eq(lanes["zoom"].size(), 1, "one zoom event (from the zoom-only keyframe)")

	var a: Dictionary = lanes["angle"][0]
	_assert_eq(a["channel"], 1, "angle event carries channel bit 1")
	_assert_eq(a["end_frame"], 10, "angle event carries the keyframe end_frame")
	_assert_eq(a["source_bits"], SRC_MAP, "angle event carries the shared source bits")
	_assert_eq(a["interp_bits"], INTERP_COSINE_A, "angle event carries the shared interp bits")
	_assert_eq(a["value"], Vector3i(1, 2, 3), "angle event carries its OWN angle vec")

	var p: Dictionary = lanes["position"][0]
	_assert_eq(p["value"], Vector3i(4, 5, 6), "position event carries its OWN position vec")
	_assert_eq(p["end_frame"], 10, "position event shares the coincident end_frame")

	var z: Dictionary = lanes["zoom"][0]
	_assert_eq(z["channel"], 4, "zoom event carries channel bit 4")
	_assert_eq(z["source_bits"], SRC_DIRECT, "zoom event carries the zoom keyframe's source bits")
	_assert_eq(z["value"], Vector3i(100, 0, 0), "zoom event carries its OWN zoom vec")


# --- Slice 2: lower — merge (coincide AND agree) ---------------------------

## An angle event and a position event that COINCIDE (same end_frame) AND AGREE
## (same source / interp / param / flags) coalesce into ONE masked keyframe:
## mask = OR of their channel bits, one shared command word, each channel's value
## slotted into its own vec, the un-selected channel left ZERO. This is the packing
## the author never authors — it is born here, in the compiler.
func _test_lower_merges_agreeing_coincident_events() -> void:
	var lanes := {
		"angle": [_event(1, 10, SRC_MAP, INTERP_COSINE_A, 0, 0, Vector3i(1, 2, 3))],
		"position": [_event(2, 10, SRC_MAP, INTERP_COSINE_A, 0, 0, Vector3i(4, 5, 6))],
		"zoom": [],
	}

	var table = CameraLowering.lower(lanes)

	_assert_eq(table.keyframes.size(), 1, "the two agreeing coincident events merge into ONE keyframe")
	_assert_eq(table.max_keyframe, 0, "max_keyframe is the last live index (inclusive)")
	var kf = table.keyframes[0]
	_assert_eq(kf.channel_mask, 3, "mask = angle | position")
	# cmd = flags<<13 | interp | source | param<<3 | mask = 0x400 | 0xC0 | 3 = 0x4C3
	_assert_eq(kf.command_raw, 0x04C3, "command word packs the shared source/interp + merged mask")
	_assert_eq(kf.end_frame, 10, "the shared coincident end_frame")
	_assert_eq(kf.angle, Vector3i(1, 2, 3), "angle vec slotted from the angle event")
	_assert_eq(kf.position, Vector3i(4, 5, 6), "position vec slotted from the position event")
	_assert_eq(kf.zoom, Vector3i.ZERO, "the un-selected zoom channel is left ZERO")
	_assert_eq(kf.source_mode, "MAP", "decoded source_mode is recomputed for the runtime/score")
	_assert_eq(kf.interpolation, "COSINE_A", "decoded interpolation is recomputed")


# --- Slice 3: lower — split (coincide but DISAGREE) ------------------------

## An angle event and a position event that COINCIDE (same end_frame) but DISAGREE
## (different source) must NOT be forced to share one command word — they split into
## two separate keyframes. This is what decouples authoring: the angle event keeps
## its source without dragging position along. The runtime searches each sub-channel
## independently, so two keyframes at the same end_frame — one per channel — reproduce
## both events exactly.
func _test_lower_splits_disagreeing_coincident_events() -> void:
	var lanes := {
		"angle": [_event(1, 10, SRC_MAP, INTERP_COSINE_A, 0, 0, Vector3i(1, 2, 3))],
		"position": [_event(2, 10, SRC_TARGET, INTERP_COSINE_A, 0, 0, Vector3i(4, 5, 6))],
		"zoom": [],
	}

	var table = CameraLowering.lower(lanes)

	_assert_eq(table.keyframes.size(), 2, "disagreeing coincident events split into TWO keyframes")
	# angle lane is walked before position, so the angle keyframe comes first.
	var ka = table.keyframes[0]
	var kp = table.keyframes[1]
	_assert_eq(ka.channel_mask, 1, "first keyframe carries only the angle channel")
	_assert_eq(ka.source_mode, "MAP", "the angle keyframe keeps the angle event's source")
	_assert_eq(ka.angle, Vector3i(1, 2, 3), "angle vec preserved on the angle keyframe")
	_assert_eq(kp.channel_mask, 2, "second keyframe carries only the position channel")
	_assert_eq(kp.source_mode, "TARGET", "the position keyframe keeps its OWN (different) source")
	_assert_eq(kp.position, Vector3i(4, 5, 6), "position vec preserved on the position keyframe")

	# Re-parsing the split result reproduces both single-channel event streams.
	var back: Dictionary = CameraLowering.parse(table)
	_assert_eq(back["angle"].size(), 1, "one angle event survives the split round-trip")
	_assert_eq(back["position"].size(), 1, "one position event survives the split round-trip")
	_assert_eq(back["angle"][0]["source_bits"], SRC_MAP, "angle event's source is intact after split")
	_assert_eq(back["position"][0]["source_bits"], SRC_TARGET, "position event's source stays independent")


## THE TIE CASE. `lower`'s contract is that a per-channel walk of the result re-yields each
## lane IN ORDER — the semantic inverse of parse. Two events of the SAME channel at the SAME
## end_frame (what a zero-width HOLD is: a hold re-timed down to its own start, which both the
## boundary drag and MOVE write) put that contract under strain, because the tie-break was a
## GLOBAL group-creation counter while the order that must be preserved is PER LANE.
##
## Here the zoom lane authors drawn-then-hold at frame 10, and an ANGLE hold at 10 shares the
## hold's command word. Walking angle first creates that group early; the zoom hold then merges
## into it and inherits its low ordinal, overtaking the zoom event authored BEFORE it. The lane
## comes back hold-then-drawn — which silently hands the hold the drawn keyframe's whole span,
## so the camera holds where the author drew a move.
func _test_a_tie_keeps_each_lane_in_its_own_authored_order() -> void:
	var lanes := {
		"angle": [_event(1, 10, SRC_MAP, INTERP_COSINE_A, 0, 0, Vector3i.ZERO)],
		"position": [],
		# zoom: a DRAWN event, then a HOLD closed to zero width on top of it.
		"zoom": [
			_event(4, 10, SRC_DIRECT, INTERP_COSINE_A, 0, 0, Vector3i(3072, 0, 0)),
			_event(4, 10, SRC_MAP, INTERP_COSINE_A, 0, 0, Vector3i.ZERO),
		],
	}

	var back: Dictionary = CameraLowering.parse(CameraLowering.lower(lanes))

	_assert_eq(back["zoom"].size(), 2, "both zoom events survive the tie")
	_assert_eq(back["zoom"][0]["source_bits"], SRC_DIRECT,
		"the DRAWN zoom event still comes first — it is what the author authored first")
	_assert_eq(back["zoom"][0]["value"], Vector3i(3072, 0, 0), "…carrying its own value")
	_assert_eq(back["zoom"][1]["source_bits"], SRC_MAP,
		"…and the zero-width hold still comes second, owning nothing")
	_assert_eq(back["angle"].size(), 1, "the angle lane is untouched by the zoom lane's tie")


# --- Slice 4: round-trip semantic equivalence on real ROM data -------------

## The load-bearing invariant on REAL data: for E317's for_each camera table (nine
## live keyframes, masks 1/2/3/4/7 across MAP/CASTER/TARGET/DIRECT/SLOT_COPY),
## `parse(lower(parse(t)))` reproduces the exact per-sub-channel event streams of
## `parse(t)`. Byte-identity is NOT expected (ADR-0086) — e.g. the zoom-only kf1
## carries junk angle/position vecs the mask ignores, which do NOT survive; only the
## SEMANTIC content (each channel's events) round-trips. This is the guarantee that
## makes whole-section recompile safe.
func _test_roundtrip_is_semantically_equivalent_on_real_E317() -> void:
	var camera = _load_e317_camera()
	if camera == null:
		_failed += 1
		print("[FAIL] could not load res://assets/effects/E317/camera.json")
		return
	var table = camera.get_table("for_each")

	var original: Dictionary = CameraLowering.parse(table)
	# Sanity: the fixture really exercises merge (mask 3 / mask 7) and multiple masks.
	_assert_eq(original["angle"].size(), 5, "E317 for_each has 5 angle events (masks 1,3,7)")
	_assert_eq(original["position"].size(), 5, "E317 for_each has 5 position events (masks 2,3,7)")
	_assert_eq(original["zoom"].size(), 3, "E317 for_each has 3 zoom events (masks 4,7)")

	var recompiled = CameraLowering.lower(original)
	var back: Dictionary = CameraLowering.parse(recompiled)

	_assert_lanes_equal(back, original, "E317 for_each round-trips semantically")

	# The mask-3 (end 10) and mask-7 (end 70, 82) keyframes re-merge, so the compiled
	# table has 8 live keyframes (ends 8,10,19,21,39,41,70,82) — fewer than a naive
	# one-per-event packing (13) — proving coalescing, not just passthrough.
	_assert_eq(recompiled.keyframes.size(), 8, "coalescing folds the 13 events into 8 keyframes")
	_assert_eq(recompiled.max_keyframe, 7, "max_keyframe is the last live index (8 keyframes → 7)")


# --- Slice 5: Faithful capacity (a POST-COMPILE property) ------------------

## Free authoring can produce more non-mergeable coincident keyframes than the native
## SoA slots (for_each 17, phase1/phase2 21). Capacity is checked AFTER coalescing —
## on the compiled count — so Faithful reports it consistently with the conformance
## profile. Within-capacity → ok; over → a non-destructive advisory (Free still saves).
func _test_capacity_faithful_flags_over_native_slots() -> void:
	_assert_eq(CameraLowering.capacity_faithful(17, "for_each").get("ok"), true,
		"17 compiled keyframes fit the for_each table's 17 slots")
	_assert_eq(CameraLowering.capacity_faithful(18, "for_each").get("ok"), false,
		"18 exceeds for_each's 17 slots — flagged un-Faithful")
	_assert_eq(CameraLowering.capacity_faithful(21, "phase1").get("ok"), true,
		"21 fits phase1's 21 slots")
	_assert_eq(CameraLowering.capacity_faithful(22, "phase2").get("ok"), false,
		"22 exceeds phase2's 21 slots")


# --- fixtures --------------------------------------------------------------

## Load the real E317 camera table from the parsed ROM asset (the same camera.json
## the studio reads), or null if the asset is missing.
func _load_e317_camera():
	var path := "res://assets/effects/E317/camera.json"
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return null
	return CameraData.from_json(parsed)


## Assert two lane dicts hold the same per-sub-channel event streams, comparing only
## the SEMANTIC fields (origin_index is provenance and goes stale after a re-lower).
func _assert_lanes_equal(a: Dictionary, b: Dictionary, label: String) -> void:
	for name in ["angle", "position", "zoom"]:
		var la: Array = a.get(name, [])
		var lb: Array = b.get(name, [])
		if la.size() != lb.size():
			_failed += 1
			print("[FAIL] %s — %s lane size %d != %d" % [label, name, la.size(), lb.size()])
			continue
		var ok := true
		for i in range(la.size()):
			if not _events_equal(la[i], lb[i]):
				ok = false
				print("[FAIL] %s — %s event %d differs: %s vs %s" % [label, name, i, str(la[i]), str(lb[i])])
		if ok:
			_passed += 1
		else:
			_failed += 1


func _events_equal(a: Dictionary, b: Dictionary) -> bool:
	for k in ["channel", "end_frame", "source_bits", "interp_bits", "param", "flags", "value"]:
		if a.get(k) != b.get(k):
			return false
	return true

## Build a CameraData.PhaseTable from a list of Keyframe objects + a max_keyframe
## watermark (the last LIVE index, inclusive — matching the runtime search bound).
func _table(keyframes: Array, max_keyframe: int) -> CameraData.PhaseTable:
	var t = CameraData.PhaseTable.new()
	t.table_name = "for_each"
	t.max_keyframe = max_keyframe
	t.keyframes = keyframes
	return t


## One Keyframe with a hand-built command word (command_raw is authoritative; the
## decoded sibling fields are set to mirror parse so the object is self-consistent).
func _kf(index: int, end_frame: int, command_raw: int,
		angle: Vector3i, position: Vector3i, zoom: Vector3i) -> CameraData.Keyframe:
	var kf = CameraData.Keyframe.new()
	kf.index = index
	kf.end_frame = end_frame
	kf.command_raw = command_raw
	kf.angle = angle
	kf.position = position
	kf.zoom = zoom
	kf.channel_mask = command_raw & 0x0007
	kf.param_index = (command_raw >> 3) & 0x03
	kf.flags = (command_raw >> 13) & 0x07
	return kf


## Build a sub-channel event the way parse() emits one (origin_index defaulted —
## it is provenance, not semantic).
func _event(channel: int, end_frame: int, source_bits: int, interp_bits: int,
		param: int, flags: int, value: Vector3i) -> Dictionary:
	return {
		"channel": channel, "end_frame": end_frame,
		"source_bits": source_bits, "interp_bits": interp_bits,
		"param": param, "flags": flags, "value": value, "origin_index": -1,
	}


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
