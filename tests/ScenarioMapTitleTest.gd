extends Node
## Tests for ScenarioVM's {91} Show Map Title — the pre-battle location-name
## strip (e.g. "Military Academy's Auditorium") that reveals with a LEFT->RIGHT
## wipe, holds, then ERASES with a second LEFT->RIGHT wipe. Unlike {7D} Show
## Graphic, {91} BLOCKS the VM until the effect completes (built-in FUN_8014c9d0
## wait, not a following {E5}) and the fade-out is a wipe, not a global fade. RE:
## research/working_documents/scenario_1_captures/show_map_title_op91_decode.md.
##
## Pure-logic asserts (no headful / no generated assets needed): the operand
## decodes X/Y/Speed, {91} dispatches to a real handler (not skip/halt), the
## map_id -> MAPTITLE slot resolution works (24 -> 23 verified), and the
## controller's reveal-wipe / hold / erase-wipe drives the two fronts correctly.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioMapTitleTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const MapTitleClass = preload("res://src/scenarios/ScenarioMapTitle.gd")

var _passed: int = 0
var _failed: int = 0
var _nodes: Array = []


func _ready() -> void:
	_test_decode_operand()
	_test_handler_registered_not_skip()
	_test_slot_resolution_from_map()
	_test_rom_render_params()
	_test_scenario14_map_renders()
	_test_reveal_wipes_left_to_right()
	_test_holds_then_erases_left_to_right()
	_test_blocks_vm_until_complete()
	_test_unmapped_slot_does_not_block()

	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()

	print("\n=== ScenarioMapTitleTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioMapTitleTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioMapTitleTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioMapTitleTest")
		get_tree().quit(0)


# --- decode -----------------------------------------------------------------

func _reader(vals: Dictionary) -> EventInstructionArgs:
	var arr: Array = []
	for k in vals:
		arr.append({"name": String(k), "value": int(vals[k]), "bytes": 1})
	return EventInstructionArgs.from_instruction({"params": arr}, {})


func _test_decode_operand() -> void:
	# Scenario-8 PC43: Show Map Title [X=0, Y=0, Speed=1].
	var intent := ScenarioDecode.show_map_title(_reader({"X": 0, "Y": 0, "Speed": 1}))
	_assert_eq(intent.x, 0, "X decoded")
	_assert_eq(intent.y, 0, "Y decoded")
	_assert_eq(intent.speed, 1, "Speed decoded")
	# A placed, faster variant.
	var i2 := ScenarioDecode.show_map_title(_reader({"X": 8, "Y": 4, "Speed": 2}))
	_assert_eq(i2.x, 8, "X offset decoded")
	_assert_eq(i2.y, 4, "Y offset decoded")
	_assert_eq(i2.speed, 2, "Speed>1 decoded")
	# Missing operands -> defaults (no crash); Speed defaults to 1 (not 0).
	var i3 := ScenarioDecode.show_map_title(_reader({}))
	_assert_eq(i3.speed, 1, "missing Speed -> 1")


func _test_handler_registered_not_skip() -> void:
	var vm := _make_vm()
	_assert_handler(vm, EventInstruction.SHOW_MAP_TITLE, "_op_show_map_title")


# --- slot resolution --------------------------------------------------------

func _test_slot_resolution_from_map() -> void:
	# The image is selected by MAP context, not the operand (§3). The ROM rule is
	# arithmetic: strip = map_id - 1 (worker 0x801C9EC0 reads event var 0x33 = map_id).
	# map_id 24 (Military Academy) -> slot 23 (0x17), byte-proven vs the live strip.
	_assert_eq(MapTitleClass.slot_for_map(24), 23, "map 24 -> MAPTITLE slot 23")
	# map_id 104 (Beoulve Residence, scenario 14) -> slot 103, visually confirmed
	# ("The end of the 50 Year War / The Beoulve Residence"). Regression for the
	# silent no-op where only map 24 was seeded in the table.
	_assert_eq(MapTitleClass.slot_for_map(104), 103, "map 104 -> MAPTITLE slot 103")
	# First inked strip: map_id 1 -> slot 0 (proves the -1 offset, not identity).
	_assert_eq(MapTitleClass.slot_for_map(1), 0, "map 1 -> MAPTITLE slot 0")
	# An out-of-range / titleless map resolves to -1 (timing still runs, nothing
	# renders — must NOT arm the ~606-frame VM block on an empty strip).
	_assert_eq(MapTitleClass.slot_for_map(9999), -1, "unknown map -> slot -1")
	_assert_eq(MapTitleClass.slot_for_map(116), -1, "map 116 (Arena, no title) -> -1")


func _test_rom_render_params() -> void:
	# Placement/timing are ROM-sourced from ATTACK.OUT (op91 §II), NOT capture
	# estimates. Guard the values so a manifest regression is caught.
	var m := _make_map_title()
	m.start(23, 1)
	_assert_eq(m.grow_limit, 248.0, "grow_limit 248 (ATTACK.OUT 0xADD8)")
	_assert_eq(m.hold_frames, 110, "hold 110 frames (ATTACK.OUT 0xAE24)")
	_assert_eq(m.edge, 32.0, "edge 32px (ATTACK.OUT 0xABD4)")
	_assert_eq(m.prim_y_base, 96.0, "prim_y_base 96 (ATTACK.OUT 0xAA68)")


func _test_scenario14_map_renders() -> void:
	# End-to-end for the reported bug: scenario 14 (map_id 104) reaches {91} at
	# PC 29 but showed nothing, because only map 24 was seeded in the slot table.
	# With the ROM rule (strip = map_id - 1) the strip resolves, the texture loads,
	# and the overlay goes live + visible (arming the VM block) — not a silent no-op.
	var slot := MapTitleClass.slot_for_map(104)
	_assert_eq(slot, 103, "map 104 -> slot 103")
	var m := _make_map_title()
	m.start(slot, 1)
	_assert_eq(m.slot(), 103, "started on slot 103")
	# The fix's core invariant is asset-INDEPENDENT: a resolved slot makes the
	# strip LIVE, which arms the VM block. Pre-fix, slot -1 left _live=false → the
	# silent no-op. is_live() alone distinguishes fixed from broken.
	_assert_true(m.is_live(), "map 104 title is live (arms the VM block)")
	# The on-screen draw additionally needs the generated + Godot-imported PNG.
	# map_titles/ is gitignored (regen per-machine) and `visible` gates only the
	# draw (start() docstring: PNG-absent still sequences via is_live()). So only
	# assert visible when the texture is actually present — else a fresh clone /
	# pre-bootstrap CI would red-bar a correct code path.
	if ResourceLoader.exists(MapTitleClass.TITLES_DIR + "title_103.png"):
		_assert_true(m.visible, "map 104 title is visible (texture resolved + drawn)")


# --- controller animation ---------------------------------------------------

func _test_reveal_wipes_left_to_right() -> void:
	# Fade-in is a LEFT->RIGHT wipe (§6.4): reveal front sweeps 0 -> grow_limit at
	# grow_step px/frame while the erase front stays at 0.
	var m := _make_map_title()
	m.start(23, 1)
	_assert_eq(m.reveal_front(), 0.0, "reveal front starts at the left edge")
	_assert_eq(m.erase_front(), 0.0, "erase front starts at 0")
	_assert_true(m.is_live(), "live immediately after start")

	m.tick()
	_assert_true(is_equal_approx(m.reveal_front(), m.grow_step), "reveal advances grow_step/frame")
	_assert_eq(m.erase_front(), 0.0, "nothing erased during reveal")

	# Drive to the end of the reveal: front pins at grow_limit (no overshoot),
	# erase still 0.
	var grow := int(ceil(m.grow_limit / m.grow_step))
	for _f in grow:
		m.tick()
	_assert_true(is_equal_approx(m.reveal_front(), m.grow_limit), "reveal reaches grow_limit")
	_assert_eq(m.erase_front(), 0.0, "still nothing erased at end of reveal")
	_assert_true(m.is_live(), "live through the full reveal")


func _test_holds_then_erases_left_to_right() -> void:
	# After the reveal the strip holds, then a SECOND L->R front (erase) sweeps
	# across (§6.5) — NOT a global brightness fade — and the task completes.
	var m := _make_map_title()
	m.start(23, 1)
	var grow := int(ceil(m.grow_limit / m.grow_step))

	for _f in grow + m.hold_frames:
		m.tick()
	_assert_true(is_equal_approx(m.reveal_front(), m.grow_limit), "fully revealed through hold")
	_assert_eq(m.erase_front(), 0.0, "no erase during the hold")
	_assert_true(m.is_live(), "still live at end of hold (before erase)")

	# Erase: the erase front passes through the mid range (left dies first) then
	# reaches grow_limit and the strip clears. Reveal stays pinned full throughout.
	var mid_seen := false
	for _f in grow + 2:
		m.tick()
		var e: float = m.erase_front()
		if e > m.grow_limit * 0.05 and e < m.grow_limit * 0.95:
			mid_seen = true
		_assert_true(is_equal_approx(m.reveal_front(), m.grow_limit) or not m.is_live(),
			"reveal stays full during erase (no global dim)")
	_assert_true(mid_seen, "erase front swept through the mid range (L->R wipe)")
	_assert_true(is_equal_approx(m.erase_front(), m.grow_limit), "erase reaches grow_limit")
	_assert_true(not m.is_live(), "strip no longer live once erased away")


func _test_blocks_vm_until_complete() -> void:
	# {91} BLOCKS the event VM until the whole effect erases away — the ROM case
	# ends with FUN_8014c9d0 (yield-until-task-inactive), an implicit wait built
	# into the opcode (NOT fire-and-forget, NOT a following {E5}). Dynamically
	# confirmed: the scene holds on the sepia tint through the whole title, then
	# advances only once it's gone (op91 decode §6).
	var vm := _make_vm()
	vm.current_map_id = 24
	var ctx = ScenarioVMClass.ScriptContext.new()
	vm._contexts = [ctx]
	vm._current_ctx = ctx
	# Dispatch {91} X=0 Y=0 Speed=1 through the real handler.
	vm._op_show_map_title({"opcode": 0x91, "name": "Show Map Title", "params": [
		{"name": "X", "value": 0, "bytes": 1},
		{"name": "Y", "value": 0, "bytes": 1},
		{"name": "Speed", "value": 1, "bytes": 1}]})
	_adopt(vm._map_title)
	_assert_true(vm._map_title != null and vm._map_title.is_live(), "map title started + live")
	_assert_true(vm._main_ctx_blocked(), "VM main context BLOCKS on the map title (not fire-and-forget)")
	# Drive the effect (ticked outside the halt gate) to completion; the release
	# predicate then goes true so the VM would unblock and run the next opcode.
	var m = vm._map_title
	var total: int = int(ceil(m.grow_limit / m.grow_step)) * 2 + m.hold_frames + 4
	for _f in total:
		m.tick()
	_assert_true(not m.is_live(), "effect fully erased away")
	_assert_true(ctx.wait_until.is_valid() and ctx.wait_until.call(),
		"wait predicate releases once the title has gone")


func _test_unmapped_slot_does_not_block() -> void:
	# An UNMAPPED map (slot -1: every scenario except map 24 until the table is
	# filled) must NOT arm the ~606-frame block on a strip that renders nothing —
	# that would freeze the scene ~10 s looking like a hang. start(-1) => not live.
	var m := _make_map_title()
	m.start(-1, 1)
	_assert_true(not m.is_live(), "unmapped slot (-1) is NOT live (no block armed)")
	# Through the real handler: unmapped map_id => slot -1 => VM does not block.
	var vm := _make_vm()
	vm.current_map_id = 9999
	var ctx = ScenarioVMClass.ScriptContext.new()
	vm._contexts = [ctx]
	vm._current_ctx = ctx
	vm._op_show_map_title({"opcode": 0x91, "name": "Show Map Title", "params": [
		{"name": "X", "value": 0, "bytes": 1},
		{"name": "Y", "value": 0, "bytes": 1},
		{"name": "Speed", "value": 1, "bytes": 1}]})
	_adopt(vm._map_title)
	_assert_true(not vm._main_ctx_blocked(),
		"unmapped map_id: VM does NOT block on {91} (no blank multi-second stall)")


# --- fixtures ---------------------------------------------------------------

func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	vm.set_process(false)
	_nodes.append(vm)
	return vm


func _make_map_title() -> ScenarioMapTitle:
	var m := MapTitleClass.new()
	add_child(m)  # _ready() builds the render resources
	_nodes.append(m)
	return m


func _adopt(m: ScenarioMapTitle) -> ScenarioMapTitle:
	_nodes.append(m)
	return m


# --- assert helpers ---------------------------------------------------------

func _assert_handler(vm, op: int, method: String) -> void:
	var op_name := EventInstructionSet.name_of(op)
	var h = vm._handlers.get(op, null)
	_assert_true(h != null, "%s handler registered" % op_name)
	if h != null:
		_assert_eq((h as Callable).get_method(), method, "%s -> %s (not skip/halt)" % [op_name, method])


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_true(cond: bool, name: String) -> void:
	_assert_eq(cond, true, name)
