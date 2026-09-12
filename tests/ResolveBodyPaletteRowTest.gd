extends Node
# test-kind: logic
# seeded-break: SpritePaletteResolver.resolve_body_palette_row's monster branch honors the ENTD palette byte instead of the job's body_palette_row — the scenario-6 chocobo bug class this test exists to keep out; the 5 monster-axis cases ('chocobo job 0x5E ignores palette byte 2 -> row 0 (YELLOW)', 'Black Chocobo 0x5F -> row 1' x2, 'Goblin 0x61 -> row 0', 'Gobbledeguck 0x63 -> row 2') red (the Red Chocobo 0x60 case is accidentally still green); the generic-human pass-throughs, all four named-unique clamp cases, the unknown-sprite pass-through, and the missing-key defaults stay green
## Regression test for the unified BODY palette-row resolver.
##
## Pins the two-axis event-script CLUT rule (see
## `research/working_documents/EVTCHR_CLUT_RESOLUTION.md` §3.1). Colors resolve
## by unit kind, then clamp:
##   - MONSTER: row = the JOB's `body_palette_row` (SCUS 0x2E, ADR-0022); the
##     ENTD `palette` byte is ignored (it's an enemy-squad team selector).
##   - HUMAN/NAMED: row = the ENTD `palette` byte, but ONLY where the resolved
##     SPR authored that row. Generics author rows 0-4 (Blue=0/Red=2 pass
##     through); a named unique SPR authors only body row 0, so an out-of-range
##     byte CLAMPS to 0.
##
## Ground truth: verified on real PSX (scenario-6 abduction) — chocobo unit 0x8B
## is job 0x5E (Yellow) and renders row 0 despite `palette: 2`. Delita (SPR 0x05,
## ENTD byte 2) is the clamp case: `05.palette.tga` body rows = {0,1}, so byte 2
## points at an all-black row and must clamp to row 0 (tan body, not black).
##
## `_resolve_body_palette_row` is a static pure function; we call it directly on
## the script with no scene instance. The resolver reads the bake-time manifest
## `addons/exmateria_sprite_rig/resources/populated_rows.json`
## (tools/bake_populated_rows.py).
##
## Run: <GODOT> --path . --quit-after 5 res://tests/ResolveBodyPaletteRowTest.tscn

const ScenarioPlayerScript := preload("res://src/scenarios/ScenarioPlayerScene.gd")

# Sprite ids with known authored body rows (see populated_rows.json):
const SPR_GENERIC := 0x60   # generic squire -> body rows {0,1,2,3,4}
const SPR_DELITA := 0x05    # DILY2.SPR -> body rows {0,1}
const SPR_RAMZA := 0x01     # RAMUZA.SPR -> body rows {0}
const SPR_OVELIA := 0x0C    # HIME.SPR  -> body rows {0}

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	# job, palette_byte, sprite_id, expected_row, name
	var cases := [
		# --- MONSTERS: JOB row, sprite irrelevant (returns before the clamp) ---
		# THE BUG: scenario-6 chocobo. Job 0x5E is Yellow Chocobo -> row 0 even
		# though the ENTD enemy-squad `palette` byte is 2. Real PSX = yellow.
		[0x5E, 2, 0x86, 0, "chocobo job 0x5E ignores palette byte 2 -> row 0 (YELLOW)"],
		[0x5F, 2, 0x86, 1, "Black Chocobo job 0x5F -> row 1"],
		[0x60, 2, 0x86, 2, "Red Chocobo job 0x60 -> row 2"],
		[0x5F, 0, 0x86, 1, "Black Chocobo job 0x5F -> row 1 even with palette byte 0"],
		[0x61, 3, 0x87, 0, "Goblin job 0x61 -> row 0"],
		[0x63, 0, 0x87, 2, "Gobbledeguck job 0x63 -> row 2"],

		# --- GENERIC HUMANS: SPR authors rows 0-4, so the byte passes through ---
		[0x4C, 0, SPR_GENERIC, 0, "generic Knight, byte 0 -> row 0"],
		[0x4C, 2, SPR_GENERIC, 2, "generic Knight, byte 2 (team color) passes -> row 2"],
		[0x4C, 1, SPR_GENERIC, 1, "generic Knight, byte 1 passes -> row 1"],
		[0x4C, 4, SPR_GENERIC, 4, "generic Knight, byte 4 (max authored) passes -> row 4"],

		# --- NAMED UNIQUE HUMANS: SPR authors only row 0, so byte clamps ---
		# Delita, regression test #1: DILY2 body rows {0,1}, ENTD byte 2 clamps.
		[0x05, 2, SPR_DELITA, 0, "DELITA sprite 0x05 byte 2 -> CLAMP to row 0"],
		[0x05, 1, SPR_DELITA, 1, "Delita sprite 0x05 byte 1 authored -> row 1"],
		[0x05, 5, SPR_DELITA, 0, "Delita sprite 0x05 byte 5 (portrait row) -> CLAMP to 0"],
		[0x4C, 2, SPR_RAMZA, 0, "named-unit sprite 0x01 (Ramza) byte 2 -> CLAMP to row 0"],
		[0x4C, 3, SPR_OVELIA, 0, "named-unit sprite 0x0C (Ovelia) byte 3 -> CLAMP to row 0"],
		[0x4C, 0, SPR_OVELIA, 0, "named-unit sprite 0x0C (Ovelia) byte 0 (authored) -> row 0"],
	]
	for c in cases:
		_check(c[0], c[1], c[2], c[3], c[4])

	# Unknown sprite (absent from manifest) -> conservative pass-through, no clamp.
	_check_slot({"job": 0x4C, "palette": 2}, 0xFE, 2,
		"unknown sprite 0xFE -> pass byte through (no manifest data)")
	# Missing `palette` key on a human slot defaults to row 0.
	_check_slot({"job": 0x4C}, SPR_GENERIC, 0,
		"human slot with no palette key -> row 0")
	# Missing `job` key -> job 0x00 (a special human) uses the (clamped) byte.
	_check_slot({"palette": 2}, SPR_GENERIC, 2,
		"slot with no job key -> uses palette byte 2 (generic authors it)")

	print("\n=== ResolveBodyPaletteRowTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ResolveBodyPaletteRowTest")
		get_tree().quit(1)
	else:
		print("[PASS] ResolveBodyPaletteRowTest")
		get_tree().quit(0)


func _check(job: int, palette_byte: int, sprite_id: int, want: int, name: String) -> void:
	_check_slot({"job": job, "palette": palette_byte}, sprite_id, want, name)


func _check_slot(slot: Dictionary, sprite_id: int, want: int, name: String) -> void:
	var got: int = ScenarioPlayerScript._resolve_body_palette_row(slot, sprite_id)
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])
