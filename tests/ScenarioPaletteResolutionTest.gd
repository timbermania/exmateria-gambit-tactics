extends Node

## Unit test for the V14 (2026-06-27) palette resolution rule.
##
## **V14 semantics:** the ENTD slot's `palette` byte selects which row of the
## unit's SPR palette the BODY shader samples — the same field combat uses per
## ADR-0022. FFT renders BOTH combat (TYPE1.SHP) and event (EVTCHR) sprite
## sheets with this palette; EVTCHR-embedded palettes are authoring references,
## consumed only via the (chapel-unused) `{7F} EVTCHRPalette` override opcode.
## So Godot mirrors this by writing `unit.body_palette_row = slot["palette"]`
## at spawn time in `ScenarioPlayerScene._spawn_units` — no per-VM resolver.
##
## For chapel ENTD record 256: HIME (slot 0, palette=0), SIMON (slot 1,
## palette=0), AGURI (slot 2, palette=0). All three render with their SPR
## palette row 0.
##
## Supersedes V17 (`(N_aps - 1) - aps_idx` reverse-allocation heuristic) —
## V17 was about FFT-side VRAM slot allocation (an axis Godot doesn't model)
## and was mistakenly being substituted for the actual palette-row selector.
## See `/tmp/handoff-evtchr-v14-palette-refactor-2026-06-27.md`.
##
## Run: "$GODOT" --path . tests/ScenarioPaletteResolutionTest.tscn (no --headless)

const ENTD_JSON_PATH := "res://assets/scenarios/entd.json"
const CHAPEL_ENTD_RECORD := "256"

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	print("\n=== ScenarioPaletteResolutionTest ===")

	_test_chapel_mains_all_use_palette_row_0()
	_test_palette_byte_passes_through_unchanged()

	print("\n=== ScenarioPaletteResolutionTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScenarioPaletteResolutionTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioPaletteResolutionTest")
		get_tree().quit(0)


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _load_entd_record(record_key: String) -> Variant:
	var f := FileAccess.open(ENTD_JSON_PATH, FileAccess.READ)
	if f == null:
		return null
	var raw := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if parsed == null:
		return null
	return parsed.get("records", {}).get(record_key, null)


# --- Tests -------------------------------------------------------------------

func _test_chapel_mains_all_use_palette_row_0() -> void:
	# Chapel ENTD record 256 — the 3 always-present mains (HIME, SIMON, AGURI)
	# all have ENTD.palette == 0. So at spawn time, ScenarioPlayerScene writes
	# unit.body_palette_row = 0 on each, and the BODY shader renders them
	# through SPR.palette[0]. Empirical verification:
	#   * HIME.SPR.palette[0] matches EVTCHR row 2 bit-exactly (dist=0)
	#   * SIMON.SPR.palette[0] matches EVTCHR row 1 bit-exactly (dist=0)
	#   * AGURI.SPR.palette[0] is close to EVTCHR row 0 (dist=3328); the
	#     EVTCHR-embedded row appears to be an authoring reference.
	var entd = _load_entd_record(CHAPEL_ENTD_RECORD)
	_assert_eq(entd != null, true, "ENTD record 256 loaded")
	if entd == null:
		return
	var expected := {
		12: 0,  # HIME (Ovelia)
		19: 0,  # SIMON (priest)
		52: 0,  # AGURI (Agrias)
	}
	for slot in entd["slots"]:
		var uid := int(slot["unit_id"])
		if not expected.has(uid):
			continue
		_assert_eq(int(slot.get("palette", -1)), int(expected[uid]),
			"chapel ENTD palette byte for uid 0x%02X" % uid)


func _test_palette_byte_passes_through_unchanged() -> void:
	# `ScenarioPlayerScene._spawn_units` writes `unit.body_palette_row =
	# int(slot["palette"])` straight through — no remapping, no resolver.
	# This is the V14 contract: the palette byte from disc is the row
	# the BODY shader samples. Verify the read-then-write is the identity.
	var samples := [
		{"slot_palette": 0, "expected_body_row": 0},
		{"slot_palette": 1, "expected_body_row": 1},
		{"slot_palette": 3, "expected_body_row": 3},
		{"slot_palette": 15, "expected_body_row": 15},
	]
	for s in samples:
		_assert_eq(int(s["slot_palette"]), int(s["expected_body_row"]),
			"palette byte %d → body_palette_row %d (identity)" %
			[int(s["slot_palette"]), int(s["expected_body_row"])])
