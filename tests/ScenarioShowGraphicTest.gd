extends Node
## Tests for ScenarioVM's {7D} Show Graphic — the fullscreen event graphic
## (chapter title card, ending still, GAME OVER, or a WLDBK world background) that
## fades in, holds, then fades out. This is the new #1 post-Face-Unit-2 halt
## (171/216 chunks first-halt on Show Graphic 0x01 = "CHAPTER 1 THE MEAGER").
## RE + formats: research/working_documents/scenario_1_captures/
## show_graphic_op7d_decode.md.
##
## Pure-logic asserts (no headful / no generated assets needed): the operand
## decodes, {7D} dispatches to a real handler (not skip/halt), the controller's
## fade-in/hold/fade-out drives alpha + liveness correctly, and the kind-61 ({E5}
## Task=61) barrier goes live while the graphic is on screen then clears once it
## has fully faded away.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioShowGraphicTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const ShowGraphicClass = preload("res://src/scenarios/ScenarioShowGraphic.gd")

var _passed: int = 0
var _failed: int = 0
var _nodes: Array = []


func _ready() -> void:
	_test_decode_operand()
	_test_handler_registered_not_skip()
	_test_adopts_iso_animation_params()
	_test_reveal_wipes_left_to_right()
	_test_holds_then_fades_grey_to_zero()
	_test_barrier_predicate_live_then_clear()
	_test_barrier_holds_through_hold_phase()

	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()

	print("\n=== ScenarioShowGraphicTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioShowGraphicTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioShowGraphicTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioShowGraphicTest")
		get_tree().quit(0)


# --- decode -----------------------------------------------------------------

# Mint an EventInstructionArgs reader from a name->value dict (the decoder takes
# the typed reader now, not a bare dict). Show Graphic's operand is unsigned, so
# the default byte width is fine.
func _reader(vals: Dictionary) -> EventInstructionArgs:
	var arr: Array = []
	for k in vals:
		arr.append({"name": String(k), "value": int(vals[k]), "bytes": 1})
	return EventInstructionArgs.from_instruction({"params": arr}, {})


func _test_decode_operand() -> void:
	# CHAPTER1 card (the #1 halt): Show Graphic [Graphic=1].
	var intent := ScenarioDecode.show_graphic(_reader({"Graphic": 1}))
	_assert_eq(intent.graphic_id, 1, "Graphic id decoded")
	# A WLDBK background id and the byte mask.
	_assert_eq(ScenarioDecode.show_graphic(_reader({"Graphic": 0x48})).graphic_id, 0x48,
		"WLDBK Graphic id decoded")
	_assert_eq(ScenarioDecode.show_graphic(_reader({"Graphic": 0x1FF})).graphic_id, 0xFF,
		"Graphic id masked to a byte")
	# Missing operand -> 0 (no crash).
	_assert_eq(ScenarioDecode.show_graphic(_reader({})).graphic_id, 0, "missing Graphic -> 0")


func _test_handler_registered_not_skip() -> void:
	var vm := _make_vm()
	_assert_handler(vm, EventInstruction.SHOW_GRAPHIC, "_op_show_graphic")


# --- controller animation ---------------------------------------------------

# The ISO animation block the parser emits per graphic id (III.4/III.7). The
# controller must drive its reveal/hold/fade timing from THESE, not from a
# hardcoded placeholder, so the effect regenerates from files.
func _iso_anim() -> Dictionary:
	return {
		"grow_limit": 248, "grow_step": 1,
		"hold_frames": 80, "fade_frames": 128, "edge": 32,
	}


func _test_adopts_iso_animation_params() -> void:
	# configure_animation() adopts the manifest's animation block verbatim, so a
	# fresh clone's timing comes from ETC.OUT, not the controller's defaults.
	var g := _make_show_graphic()
	g.configure_animation(_iso_anim())
	_assert_eq(g.grow_limit, 248.0, "grow_limit from manifest")
	_assert_eq(g.grow_step, 1.0, "grow_step from manifest")
	_assert_eq(g.hold_frames, 80, "hold_frames from manifest")
	_assert_eq(g.fade_frames, 128, "fade_frames from manifest")
	_assert_eq(g.edge, 32.0, "edge kernel from manifest")


func _test_reveal_wipes_left_to_right() -> void:
	# Fade-in is a LEFT->RIGHT wipe (II.4), not a global alpha: reveal_front
	# sweeps 0 -> grow_limit at grow_step px/frame while grey stays full.
	var g := _make_show_graphic()
	g.configure_animation(_iso_anim())
	g.start(_default_intent())
	_assert_eq(g.reveal_front(), 0.0, "front starts at the left edge")
	_assert_true(g.is_live(), "live immediately after start")

	g.tick()
	_assert_true(is_equal_approx(g.reveal_front(), 1.0), "front advances 1 px/frame")
	_assert_true(is_equal_approx(g.grey_level(), 1.0), "grey full behind the front")

	# Drive to the end of the grow phase: front pins at grow_limit (no overshoot).
	for _f in int(g.grow_limit):
		g.tick()
	_assert_true(is_equal_approx(g.reveal_front(), g.grow_limit), "front reaches grow_limit")
	_assert_true(is_equal_approx(g.grey_level(), 1.0), "still full grey at end of reveal")
	_assert_true(g.is_live(), "live through the full reveal")


func _test_holds_then_fades_grey_to_zero() -> void:
	# After the reveal the card holds at full grey, then the WHOLE card's grey
	# ramps uniformly 1 -> 0 over fade_frames (II.6), and the task completes.
	var g := _make_show_graphic()
	g.configure_animation(_iso_anim())
	g.start(_default_intent())

	var grow := int(ceil(g.grow_limit / g.grow_step))
	for _f in grow + g.hold_frames:
		g.tick()
	_assert_true(is_equal_approx(g.grey_level(), 1.0), "full grey through the hold")
	_assert_true(g.is_live(), "still live at end of hold (before fade)")

	# Fade-out: grey passes through the mid range then hits 0 and clears.
	var mid_seen := false
	for _f in g.fade_frames + 2:
		g.tick()
		var gl: float = g.grey_level()
		if gl > 0.05 and gl < 0.95:
			mid_seen = true
	_assert_true(mid_seen, "grey passed through the mid fade range")
	_assert_eq(g.grey_level(), 0.0, "grey returns to 0 after fade")
	_assert_true(not g.is_live(), "graphic no longer live once faded away")


# --- VM barrier wiring ------------------------------------------------------

func _test_barrier_predicate_live_then_clear() -> void:
	# The kind-61 predicate (what {E5} Wait For Instruction(Task=61) polls) must be
	# LIVE while the graphic is on screen and CLEAR once it has fully faded away.
	var vm := _make_vm()
	vm._show_graphic = _adopt(vm._make_show_graphic())
	vm._show_graphic.configure_animation(_iso_anim())
	vm._show_graphic.start(_default_intent())
	_assert_true(vm._task_kind_live(ScenarioVMClass.TASK_SHOWGRAPHIC, null),
		"kind-61 barrier LIVE while the graphic is on screen")

	var g := vm._show_graphic
	var total: int = int(ceil(g.grow_limit / g.grow_step)) + g.hold_frames \
		+ g.fade_frames + 2
	for _f in total:
		g.tick()
	_assert_true(not vm._task_kind_live(ScenarioVMClass.TASK_SHOWGRAPHIC, null),
		"kind-61 barrier CLEAR once the graphic has faded away")


func _test_barrier_holds_through_hold_phase() -> void:
	# The whole point vs. Dark Screen: the barrier stays live through the HOLD (not
	# just the grow-in) — the chapter card must play in FULL before the scene runs.
	var g := _make_show_graphic()
	g.configure_animation(_iso_anim())
	g.start(_default_intent())
	# Halfway through the hold, the graphic is fully opaque yet still live.
	var grow := int(ceil(g.grow_limit / g.grow_step))
	for _f in grow + int(g.hold_frames / 2.0):
		g.tick()
	_assert_true(is_equal_approx(g.grey_level(), 1.0), "full grey during hold")
	_assert_true(g.is_live(), "barrier still holds mid-hold (card not done yet)")


# --- fixtures ---------------------------------------------------------------

func _default_intent() -> ScenarioDecode.ShowGraphicIntent:
	return ScenarioDecode.show_graphic(_reader({"Graphic": 1}))


func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	vm.set_process(false)
	_nodes.append(vm)
	return vm


func _make_show_graphic() -> ScenarioShowGraphic:
	var g := ShowGraphicClass.new()
	add_child(g)  # _ready() builds the render resources
	_nodes.append(g)
	return g


## Track a VM-parented node for cleanup too.
func _adopt(g: ScenarioShowGraphic) -> ScenarioShowGraphic:
	_nodes.append(g)
	return g


# --- assert helpers ---------------------------------------------------------

func _assert_handler(vm, op: int, method: String) -> void:
	# op is an EventInstruction member (byte); the display name is the descriptor
	# label, kept for readable assertion messages only (dispatch is byte-keyed).
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
