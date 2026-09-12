extends Node
# test-kind: logic
# seeded-break: ScenarioPlayerScene._frame0_visible drops the presence master gate (returns not _chunk_reveals_first(uid, instructions) without the `present and`) — the reported-bug state where a not-yet-present unit renders at frame 0 (scn6 uid 1/4 drawn ~434 instructions early); 'absent + Add Draw=0 -> hidden' and 'absent + no vis-op -> hidden' red (got=true want=false); every first-visibility-opcode branch, the Erase-before-later-Draw case, the present-frame-0 cases, and the scn1 real anchor stay green
## Pure-logic guard (no scene/VM/nodes) for the scenario-6 unit-visibility fix.
##
## A unit's initial (frame-0) on-screen visibility is decided by the FIRST
## visibility-affecting opcode that names it in the loaded chunk:
##   {44} Draw Unit            -> reveal on cue  => start HIDDEN
##   {45} Add Unit, Draw==1    -> held on load   => start HIDDEN
##   {46} Erase Unit           -> was on-screen  => start VISIBLE
##   {45} Add Unit, Draw==0    -> draw now       => start VISIBLE
##   (no visibility opcode)                      => start VISIBLE
## This replaces the old `unit.visible = always_present` (a formation RNG-cull
## flag, NOT the render flag). See
## research/working_documents/SCENARIO6_UNIT_REVEAL_VISIBILITY.md §4.2/§5.
##
## Fixtures are INLINE synthetic instruction lists (opcode + params, the shape
## `EventInstructionSet.args` reads) so the branch coverage is hermetic — it does
## NOT depend on the gitignored per-scenario chunks (chunks/ is 212 MiB, regen
## per-machine). One real-data anchor uses the COMMITTED scenario_1 chunk; a
## bonus block asserts the real scn6 oracle IFF that gitignored chunk exists
## locally (auto-skips on a fresh clone / CI).
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioUnitVisibilityTest.tscn

const ScenarioPlayerScene = preload("res://src/scenarios/ScenarioPlayerScene.gd")

const DRAW_UNIT := 0x44
const ADD_UNIT := 0x45
const ERASE_UNIT := 0x46

const SCN1_CHUNK := "res://assets/scenarios/scenario_1_chunk.json"          # committed
const SCN6_CHUNK := "res://assets/scenarios/chunks/scenario_006_chunk.json" # gitignored

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	# --- Synthetic branch coverage (hermetic) ---
	_test_draw_first_starts_hidden()
	_test_add_draw1_starts_hidden()
	_test_add_draw0_starts_visible()
	_test_erase_first_starts_visible()
	_test_first_op_wins_erase_before_later_draw()
	_test_no_visibility_op_starts_visible()
	_test_non_visibility_opcode_is_ignored()
	_test_scn6_ordering_fixture()
	# --- Frame-0 render visibility gates on PRESENCE ---
	_test_frame0_absent_add_draw0_hidden()
	_test_frame0_absent_no_visop_hidden()
	_test_frame0_absent_add_draw1_hidden()
	_test_frame0_present_add_draw0_visible()
	_test_frame0_present_draw_first_hidden()
	_test_frame0_present_erase_first_visible()
	# --- Real committed data (scenario 1) ---
	_test_scn1_real_walkin_hidden_simon_visible()
	# --- Bonus: real scn6 oracle, only if the gitignored chunk is present ---
	_test_scn6_real_oracle_if_present()

	print("\n=== ScenarioUnitVisibilityTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioUnitVisibilityTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioUnitVisibilityTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioUnitVisibilityTest")
		get_tree().quit(0)


func _true(got: bool, name: String) -> void:
	if got:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=false want=true" % name)


func _false(got: bool, name: String) -> void:
	if not got:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=true want=false" % name)


# Build one runtime instruction dict of the shape ScenarioPlayerScene reads
# (`{opcode, params:[{name,value}]}`). `draw` < 0 omits the Add-Unit Draw byte.
func _inst(opcode: int, unit: int, draw: int = -1) -> Dictionary:
	var params: Array = [{"name": "Unit", "value": unit}]
	if draw >= 0:
		params.append({"name": "Draw", "value": draw})
	return {"opcode": opcode, "params": params}


func _reveals(uid: int, insts: Array) -> bool:
	return ScenarioPlayerScene._chunk_reveals_first(uid, insts)


# {44} Draw Unit as the first op = revealed on cue => starts HIDDEN. (Ovelia.)
func _test_draw_first_starts_hidden() -> void:
	_true(_reveals(12, [_inst(DRAW_UNIT, 12)]), "Draw-first -> hidden")


# {45} Add Unit Draw=1 = held on load => starts HIDDEN. (Delita / chocobo.)
func _test_add_draw1_starts_hidden() -> void:
	_true(_reveals(5, [_inst(ADD_UNIT, 5, 1)]), "Add Draw=1 -> hidden")


# {45} Add Unit Draw=0 = draw now (inverted byte) => starts VISIBLE.
func _test_add_draw0_starts_visible() -> void:
	_false(_reveals(1, [_inst(ADD_UNIT, 1, 0)]), "Add Draw=0 -> visible")


# {46} Erase Unit as the first op implies it was on-screen => starts VISIBLE.
func _test_erase_first_starts_visible() -> void:
	_false(_reveals(52, [_inst(ERASE_UNIT, 52)]), "Erase-first -> visible")


# Only the FIRST op naming the unit counts: an Erase before a later Draw leaves
# the unit VISIBLE. This is the Agrias case (Erase@71 then Draw@259) that kills
# every naive "has-a-Draw" / ENTD-flag theory (§4.1).
func _test_first_op_wins_erase_before_later_draw() -> void:
	var insts := [_inst(ERASE_UNIT, 52), _inst(DRAW_UNIT, 52)]
	_false(_reveals(52, insts), "Erase-before-later-Draw -> visible (first op wins)")


# A unit with NO visibility op in the chunk starts VISIBLE. (scn1 Simon.)
func _test_no_visibility_op_starts_visible() -> void:
	_false(_reveals(19, [_inst(ADD_UNIT, 5, 1), _inst(DRAW_UNIT, 5)]),
		"no vis-op for unit -> visible")


# Non-visibility opcodes that name the unit are NOT its "first visibility op".
# Guards the opcode gate: a decoy op (here 0x28) before the real Draw must not
# short-circuit the scan. Also implicitly guards name-prefix collisions ("Add
# Unit Start/End", "Wait Add Unit" are distinct opcodes, not 0x45).
func _test_non_visibility_opcode_is_ignored() -> void:
	var insts := [_inst(0x28, 12), _inst(DRAW_UNIT, 12)]   # 0x28 = Walk To (decoy)
	_true(_reveals(12, insts), "non-vis opcode ignored; Draw still reveals -> hidden")


# The real scn6 doorway ordering, encoded inline (indices mirror the chunk):
# Add(5,1)@10, Add(139,1)@11, Erase(52)@71, Draw(5)@88, Draw(12)@104,
# Draw(139)@184, Draw(52)@259. Asserts the full per-unit oracle hermetically.
func _test_scn6_ordering_fixture() -> void:
	var insts := [
		_inst(ADD_UNIT, 5, 1),
		_inst(ADD_UNIT, 139, 1),
		_inst(ERASE_UNIT, 52),
		_inst(DRAW_UNIT, 5),
		_inst(DRAW_UNIT, 12),
		_inst(DRAW_UNIT, 139),
		_inst(DRAW_UNIT, 52),
	]
	_true(_reveals(5, insts), "scn6 fixture: Delita (5) Add Draw=1 -> hidden")
	_true(_reveals(139, insts), "scn6 fixture: Chocobo (139) Add Draw=1 -> hidden")
	_true(_reveals(12, insts), "scn6 fixture: Ovelia (12) Draw-first -> hidden")
	_false(_reveals(52, insts), "scn6 fixture: Agrias (52) Erase-first -> visible")


# --- Frame-0 render visibility = PRESENCE ∧ ¬(first-op holds it hidden) ----------
# `_chunk_reveals_first` answers "IF this unit is present, does its first op hold it
# hidden?". But a unit that isn't PRESENT yet (PSX: no sprite object in the list —
# an `always_present`=false ENTD slot introduced only by a later {45} Add) is never
# drawn at frame 0, even though its lone Add Draw=0 would "draw now" WHEN it fires.
# `_frame0_visible` is the gate the spawn/reapply sites use; presence is the master.
func _frame0(present: bool, uid: int, insts: Array) -> bool:
	return ScenarioPlayerScene._frame0_visible(present, uid, insts)


# scn6 uid 1 @ (0,4) / uid 4 @ (0,3): always_present=false, only op is {45} Add Draw=0
# at pc434 — NOT present at frame 0 → HIDDEN (the reported bug: they were drawn ~434
# instructions early because the static scan revealed them independent of presence).
func _test_frame0_absent_add_draw0_hidden() -> void:
	_false(_frame0(false, 1, [_inst(ADD_UNIT, 1, 0)]),
		"absent + Add Draw=0 -> hidden (not drawn until its Add fires)")


# scn6 uid 131 @ (0,8): always_present=false with NO visibility op at all in scn6 →
# never introduced → HIDDEN (same bug class as 1/4).
func _test_frame0_absent_no_visop_hidden() -> void:
	_false(_frame0(false, 131, [_inst(ADD_UNIT, 5, 1)]),
		"absent + no vis-op -> hidden")


# An absent unit held by Add Draw=1 is hidden either way (presence AND first-op agree).
func _test_frame0_absent_add_draw1_hidden() -> void:
	_false(_frame0(false, 5, [_inst(ADD_UNIT, 5, 1)]),
		"absent + Add Draw=1 -> hidden")


# Present (allocated) + Add Draw=0 draws now → VISIBLE. This is the runtime state
# once the {45} Add has fired and marked the unit present.
func _test_frame0_present_add_draw0_visible() -> void:
	_true(_frame0(true, 1, [_inst(ADD_UNIT, 1, 0)]),
		"present + Add Draw=0 -> visible")


# Ovelia (12): always_present=true (present at load) but Draw-first → held HIDDEN
# until her {44} Draw. Presence must NOT override the first-op hold (the doorway
# early-reveal regression this whole model exists to prevent).
func _test_frame0_present_draw_first_hidden() -> void:
	_false(_frame0(true, 12, [_inst(DRAW_UNIT, 12)]),
		"present + Draw-first -> hidden until {44} Draw (Ovelia)")


# Agrias (52): always_present=true, Erase-first → was on-screen → VISIBLE.
func _test_frame0_present_erase_first_visible() -> void:
	_true(_frame0(true, 52, [_inst(ERASE_UNIT, 52)]),
		"present + Erase-first -> visible (Agrias)")


func _load_instructions(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var raw := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if parsed == null or not parsed.has("instructions"):
		return []
	return parsed["instructions"]


# Real-data anchor on the COMMITTED scenario_1 chunk: walk-in (2) is held by an
# `Add Unit Draw=1` @34 -> hidden; Simon (19) has no visibility op -> visible.
func _test_scn1_real_walkin_hidden_simon_visible() -> void:
	var insts := _load_instructions(SCN1_CHUNK)
	if insts.is_empty():
		_failed += 1
		print("  [FAIL] scn1 real anchor: %s missing (should be committed)" % SCN1_CHUNK)
		return
	_true(_reveals(2, insts), "scn1 real: walk-in (2) Add Draw=1 -> hidden")
	_false(_reveals(19, insts), "scn1 real: Simon (19) no vis-op -> visible")


# Bonus real confirmation against the actual scn6 chunk when present locally.
# chunks/scenario_006_chunk.json is gitignored (regen per-machine), so this
# auto-skips on a fresh clone / CI rather than failing.
func _test_scn6_real_oracle_if_present() -> void:
	var insts := _load_instructions(SCN6_CHUNK)
	if insts.is_empty():
		print("  [skip] scn6 real oracle: %s not present (gitignored) — skipping" % SCN6_CHUNK)
		return
	_true(_reveals(12, insts), "scn6 real: Ovelia (12) Draw@104 -> hidden")
	_true(_reveals(5, insts), "scn6 real: Delita (5) Add Draw=1 @10 -> hidden")
	_true(_reveals(139, insts), "scn6 real: Chocobo (139) Add Draw=1 @11 -> hidden")
	_false(_reveals(52, insts), "scn6 real: Agrias (52) Erase@71 -> visible (Draw@259 ignored)")
	_false(_reveals(1, insts), "scn6 real: uid 1 Add Draw=0 @434 -> visible")
