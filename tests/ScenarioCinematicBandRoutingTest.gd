extends Node
## Regression tests for the cinematic anim-id BAND routing that renders the
## scenario-6 abduction carry poses (Delita hoisting Ovelia).
##
## PSX splits cinematic anim ids into two runtime SEQ tables, each zero-based
## (research/working_documents/scenario_1_captures/cinematic_seq_source_decode.md
## + SCENARIO6_CARRY_POSE_EVTCHR_RENDER.md):
##   * mid  [0x1F4, 0x258)  slot = anim - 0x1F4   (scenario 6, Load EVTCHR Slot 1)
##   * high [0x258, ...)    slot = anim - 0x258   (Orbonne chapel)
## Before the fix, `_apply_unit_animation` gated cinematic on `>= 0x258` and the
## segment resolver ignored the loaded Slot — so the whole mid band froze on both
## leads. This pins:
##   1. the band classifier (`_cinematic_band_base`) for low / mid / high;
##   2. the segment resolver (`_resolve_cinematic_segment`) tracking the live
##      Load EVTCHR Slot (scn6 identity Slot 1 → seg 1) while keeping the chapel's
##      default seg 0 when no Load EVTCHR fired.
##
## And (2026-09-02, root 28 / scenario 29 wrong-sprite fix) the BLOCK selector:
## FFT keeps TWO EVTCHR pages resident at once — VRAM (256,0) = block 0, (320,0) =
## block 1 — and each page owns one of the two runtime SEQ tables, so the anim BAND
## selects the PAGE: mid `[0x1F4,0x258)` → block 0 (table 0x800A77D8), high
## `[0x258,…)` → block 1 (table 0x800AED3C). This pins:
##   3. the band → block map (`_cinematic_band_block`);
##   4. the residency-guarded resolution (`_resolve_cinematic_block`) — the band's
##      block when it is loaded, else the single resident block (which keeps the
##      chapel's block-2 default and scenario 461's block-0-only chunk correct).
## See EVTCHR_CHARACTER_ATTRIBUTION.md § "The band selects the PAGE".
##
## Run via: <GODOT> --path . --quit-after 5 res://tests/ScenarioCinematicBandRoutingTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_test_band_classifier()
	_test_local_index_matches_psx_slots()
	_test_segment_resolver_tracks_loaded_slot()
	_test_segment_resolver_default_chapel()
	_test_segment_override_wins()
	_test_band_block_map()
	_test_block_resolution_scenario29()
	_test_block_resolution_falls_back_when_band_block_unloaded()

	print("\n=== ScenarioCinematicBandRoutingTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScenarioCinematicBandRoutingTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioCinematicBandRoutingTest")
		get_tree().quit(0)


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


# --- Tests -------------------------------------------------------------------

func _test_band_classifier() -> void:
	# Low range (per-unit SHP SEQ) is NOT cinematic.
	_assert_eq(ScenarioVMClass._cinematic_band_base(0), -1, "band: idle 0 not cinematic")
	_assert_eq(ScenarioVMClass._cinematic_band_base(2), -1, "band: anim 2 (at-ease) not cinematic")
	_assert_eq(ScenarioVMClass._cinematic_band_base(0x1F3), -1, "band: 0x1F3 (499) last low-range")
	# Mid band (scenario 6 carry) — base 0x1F4.
	_assert_eq(ScenarioVMClass._cinematic_band_base(0x1F4), 0x1F4, "band: 500 mid-band base 0x1F4")
	_assert_eq(ScenarioVMClass._cinematic_band_base(515), 0x1F4, "band: 515 (Delita) mid-band")
	_assert_eq(ScenarioVMClass._cinematic_band_base(0x257), 0x1F4, "band: 0x257 last mid-band")
	# High band (chapel) — base 0x258.
	_assert_eq(ScenarioVMClass._cinematic_band_base(0x258), 0x258, "band: 600 high-band base 0x258")
	_assert_eq(ScenarioVMClass._cinematic_band_base(628), 0x258, "band: 628 (chapel) high-band")


func _test_local_index_matches_psx_slots() -> void:
	# The per-band local index is `anim - base`. Verified byte-for-byte against
	# the live PSX mid-cinematic table for scenario 6 (28/28 frames match — see
	# SCENARIO6_CARRY_POSE_EVTCHR_RENDER.md §4.3).
	_assert_eq(500 - ScenarioVMClass._cinematic_band_base(500), 0,
		"local idx: anim 500 → seg-1 local 0 (frame 0xDA)")
	_assert_eq(515 - ScenarioVMClass._cinematic_band_base(515), 15,
		"local idx: anim 515 → seg-1 local 15 (frame 0xEE)")
	_assert_eq(527 - ScenarioVMClass._cinematic_band_base(527), 27,
		"local idx: anim 527 → seg-1 local 27 (frame 0xD9)")
	# High band stays zero-based off 0x258 (chapel anim 600 → local 0).
	_assert_eq(0x258 - ScenarioVMClass._cinematic_band_base(0x258), 0,
		"local idx: chapel anim 600 → local 0")


func _test_segment_resolver_tracks_loaded_slot() -> void:
	# Scenario 6: Load EVTCHR {Block:0, Slot:1} → block 0 resolves to segment 1.
	var vm = ScenarioVMClass.new()
	vm._evtchr_block_to_slot = {0: 1}
	_assert_eq(vm._resolve_cinematic_segment(0), 1, "resolver: scn6 block 0 → seg 1 (Slot identity)")
	vm.free()


func _test_segment_resolver_default_chapel() -> void:
	# Chapel issues its Load EVTCHR in the un-extracted Setup scenario 1, so the
	# map is empty here; the resolver must fall back to segment 0.
	var vm = ScenarioVMClass.new()
	vm._evtchr_block_to_slot = {}
	_assert_eq(vm._resolve_cinematic_segment(2), 0, "resolver: chapel block 2 (no load) → seg 0")
	vm.free()


func _test_segment_override_wins() -> void:
	# The F3 debug knob forces a segment regardless of the loaded slot.
	var vm = ScenarioVMClass.new()
	vm._evtchr_block_to_slot = {0: 1}
	vm.cinematic_segment_override = 5
	_assert_eq(vm._resolve_cinematic_segment(0), 5, "resolver: override wins over loaded slot")
	vm.free()


# --- The band selects the PAGE (root 28 / scenario 29) -----------------------

func _test_band_block_map() -> void:
	# Each EVTCHR page owns one runtime SEQ table, so the band IS the page:
	# mid → block 0, high → block 1. Non-cinematic ids have no page.
	_assert_eq(ScenarioVMClass._cinematic_band_block(2), -1, "band block: anim 2 not cinematic")
	_assert_eq(ScenarioVMClass._cinematic_band_block(0x1F3), -1, "band block: 0x1F3 not cinematic")
	_assert_eq(ScenarioVMClass._cinematic_band_block(0x1F4), 0, "band block: 500 mid → block 0")
	_assert_eq(ScenarioVMClass._cinematic_band_block(521), 0, "band block: 521 (Delita) mid → block 0")
	_assert_eq(ScenarioVMClass._cinematic_band_block(0x257), 0, "band block: 0x257 last mid → block 0")
	_assert_eq(ScenarioVMClass._cinematic_band_block(0x258), 1, "band block: 600 high → block 1")
	_assert_eq(ScenarioVMClass._cinematic_band_block(632), 1, "band block: 632 (Ramza) high → block 1")


func _test_block_resolution_scenario29() -> void:
	# Scenario 29 "Family Meeting" (ENTD 390, group root 28) loads BOTH pages —
	# `{Block:1, Slot:6}` at PC 13 and `{Block:0, Slot:21}` at PC 177, with no
	# `{5A}`/`{5B}`, so both stay resident. `_active_evtchr_block` is 0 from PC 177
	# on, which is exactly the state that used to paint everybody from seg 21.
	# Expected pages are the render-both-candidates verdict in
	# EVTCHR_CHARACTER_ATTRIBUTION.md, NOT a restatement of the rule.
	var vm = ScenarioVMClass.new()
	vm._evtchr_block_to_slot = {1: 6, 0: 21}
	vm._active_evtchr_block = 0
	# High band → block 1 → seg 6: Ramza, Zalbag, Alma.
	_assert_eq(vm._resolve_cinematic_block(632), 1, "scn29: 0x01 Ramza 632 → block 1")
	_assert_eq(vm._resolve_cinematic_block(623), 1, "scn29: 0x08 Zalbag 623 → block 1")
	_assert_eq(vm._resolve_cinematic_block(619), 1, "scn29: 0x30 Alma 619 → block 1")
	_assert_eq(vm._resolve_cinematic_segment(vm._resolve_cinematic_block(623)), 6,
		"scn29: Zalbag 623 → seg 6")
	# Mid band → block 0 → seg 21: Teta, Delita. Correct-by-accident today; must not regress.
	_assert_eq(vm._resolve_cinematic_block(500), 0, "scn29: 0x1C Teta 500 → block 0")
	_assert_eq(vm._resolve_cinematic_block(521), 0, "scn29: 0x04 Delita 521 → block 0")
	_assert_eq(vm._resolve_cinematic_segment(vm._resolve_cinematic_block(521)), 21,
		"scn29: Delita 521 → seg 21")
	vm.free()


func _test_block_resolution_falls_back_when_band_block_unloaded() -> void:
	# Only one page resident → the band cannot select the other one; fall back to
	# the live `Load EVTCHR` block. Three real corpus shapes:
	var vm = ScenarioVMClass.new()
	# (a) Chapel — no Load EVTCHR here at all (it fires in the un-extracted Setup
	#     scenario 1), so block 2 → seg 0 must survive for its HIGH-band anims.
	vm._evtchr_block_to_slot = {}
	vm._active_evtchr_block = 2
	_assert_eq(vm._resolve_cinematic_block(628), 2, "chapel: high band, nothing loaded → block 2")
	_assert_eq(vm._resolve_cinematic_segment(vm._resolve_cinematic_block(628)), 0,
		"chapel: high band → seg 0")
	# (b) Scenario 6 — `{Block:0, Slot:1}` only; MID band already agrees with the band rule.
	vm._evtchr_block_to_slot = {0: 1}
	vm._active_evtchr_block = 0
	_assert_eq(vm._resolve_cinematic_block(510), 0, "scn6: mid band, block 0 loaded → block 0")
	_assert_eq(vm._resolve_cinematic_segment(vm._resolve_cinematic_block(510)), 1,
		"scn6: mid band → seg 1")
	# (c) Scenario 461 — `{Block:0, Slot:132}` only, and unit 0x80 plays BOTH bands
	#     off it (anims 500-508 mid AND 607-610/635 high). These are the 8 high-band
	#     anims on a block-0-only chunk in the 500-chunk replay: block 1 was never
	#     loaded, so the fallback — not a counterexample to the band rule — owns them.
	vm._evtchr_block_to_slot = {0: 132}
	vm._active_evtchr_block = 0
	_assert_eq(vm._resolve_cinematic_block(608), 0, "scn461: high band, block 1 unloaded → block 0")
	_assert_eq(vm._resolve_cinematic_block(500), 0, "scn461: mid band → block 0")
	vm.free()
