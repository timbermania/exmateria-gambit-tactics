extends Node
## Tests for ScenarioVM's {0x50} Portrait Row — the EVTFACE.BIN event-dialogue
## portrait selector. {50} latches which EVTFACE row-block is resident; the
## following {10} DisplayMessage / {51} ChangeDialog `Portrait` byte picks a
## COLUMN (col = Portrait_byte - 1, 0 => none). Together they address one EVTFACE
## cell = the message-box face. Distinct from the in-battle unit-SPR portrait path.
##
## FFT decode (research/working_documents/PORTRAIT_ROW_OPCODE_50_EVTFACE.md, static
## + live-pcsx byte-proven): {50} handler FUN_8013c748 uploads the row's 8 portraits
## (32x48 4bpp) to VRAM (448,206); render FUN_8012e65c draws column `col`. The
## portrait is drawn IFF (Dialog & 0x70) == 0x10 AND Portrait_byte in [1,8].
## scenario 14 (Balbanes deathbed): instr 34 {50} Row=0, instr 39 {10} Portrait=1
## => EVTFACE(row0,col0) = Balbanes. Before this opcode was bound the VM HALTED at
## instr 34 (named opcode, verified:false, unbound).
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioPortraitRowTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

var _passed: int = 0
var _failed: int = 0
var _vms: Array = []


func _ready() -> void:
	_test_op_registered()
	_test_scn14_real_chunk_does_not_halt()
	_test_column_and_visibility_gate()
	_test_face_catalog_resolves()
	_test_scn14_balbanes_face_resolution()
	_test_row_latch_resets_on_start()
	_test_uiportrait_evtface_mode()

	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioPortraitRowTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioPortraitRowTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioPortraitRowTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioPortraitRowTest")
		get_tree().quit(0)


# --- assert helpers ----------------------------------------------------------

func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_true(cond: bool, name: String) -> void:
	_assert_eq(cond, true, name)


func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	_vms.append(vm)
	return vm


# --- tests -------------------------------------------------------------------

## The {50} handler is bound (not the null-halt path). Before this it was unbound,
## so scenario 14 HALTED at instr 34.
func _test_op_registered() -> void:
	var vm := _make_vm()
	_assert_true(vm._handlers.has(EventInstruction.PORTRAIT_ROW),
		"Portrait Row handler registered (not null-halt)")


## The real scenario-14 chunk (Balbanes deathbed) carries {50} at instr 34. Before
## this opcode was bound the VM HALTED there. Dispatching it must keep the VM
## running AND latch the EVTFACE row (scn14 {50} 0x00 => row 0).
const SCN14_CHUNK := "res://assets/scenarios/chunks/scenario_014_chunk.json"

func _test_scn14_real_chunk_does_not_halt() -> void:
	var vm := _make_vm()
	var ok := vm.load_chunk_json(SCN14_CHUNK)
	_assert_true(ok, "loaded real scenario_014_chunk.json")
	if not ok:
		return
	vm.start()
	var count := 0
	for inst in vm._insts:
		if str(inst.get("name", "")) != "Portrait Row":
			continue
		vm._op_portrait_row(inst)
		count += 1
		_assert_true(vm._running, "VM still running after the scn14 Portrait Row op")
	_assert_true(count > 0, "scn14 chunk contains a Portrait Row op")
	_assert_eq(vm._portrait_row, 0, "scn14 {50} 0x00 latches EVTFACE row 0")


## The {10}/{51} Portrait byte is a 1-based COLUMN: col = byte - 1 (0 => none).
## The EVTFACE face is drawn IFF (Dialog & 0x70) == 0x10 AND byte in [1,8]. This
## replaces the incomplete `portrait_row != 0x09` gate — it now also rejects
## byte 0 (scn14 instrs 43/47) and non-0x10 box modes. §2.6.
func _test_column_and_visibility_gate() -> void:
	_assert_eq(ScenarioDecode.portrait_column(1), 0, "byte 1 => col 0 (Balbanes)")
	_assert_eq(ScenarioDecode.portrait_column(2), 1, "byte 2 => col 1 (Teta)")
	_assert_eq(ScenarioDecode.portrait_column(0), -1, "byte 0 => col -1 (none)")

	# Mode 0x10 (scn14 Dialog 0x92/0x91/0x92 all & 0x70 == 0x10).
	_assert_true(ScenarioDecode.portrait_visible(0x92, 1), "0x92 + byte 1 => shown")
	_assert_true(not ScenarioDecode.portrait_visible(0x92, 0), "0x92 + byte 0 => none")
	_assert_true(not ScenarioDecode.portrait_visible(0x92, 9), "0x92 + byte 9 (col 8) => none")
	_assert_true(ScenarioDecode.portrait_visible(0x92, 8), "0x92 + byte 8 (col 7) => shown")
	# Non-0x10 box modes carry no face even with a valid column.
	_assert_true(not ScenarioDecode.portrait_visible(0x70, 1), "mode 0x70 => no face")
	_assert_true(not ScenarioDecode.portrait_visible(0x00, 1), "mode 0x00 (overlay) => no face")


## The EVTFACE catalog resolves (row, col) -> the parser-emitted 32x48 face
## texture (assets/scenarios/faces/, keyed off evtface.json). scn14 (row0,col0) =
## Balbanes. Out-of-grid coords resolve to null (no crash).
func _test_face_catalog_resolves() -> void:
	var tex := EvtFaceCatalog.face_texture(0, 0)
	_assert_true(tex != null, "EVTFACE (row0,col0) resolves to a texture")
	if tex != null:
		_assert_eq(tex.get_width(), 32, "face texture is 32 wide")
		_assert_eq(tex.get_height(), 48, "face texture is 48 tall")
	_assert_true(EvtFaceCatalog.face_texture(0, 8) == null, "col 8 out of grid => null")
	_assert_true(EvtFaceCatalog.face_texture(8, 0) == null, "row 8 out of grid => null")
	_assert_true(EvtFaceCatalog.face_texture(0, -1) == null, "col -1 => null")


## End-to-end on the REAL scn14 chunk: {50} 0x00 latches row 0; the boxed Display
## Messages where Balbanes speaks (Portrait 0x01) resolve to EVTFACE (row0, col0)
## = Balbanes; the other speakers' boxes (Portrait 0x00) take NO EVTFACE override
## (they fall through to the speaker's own unit-SPR face — the sons at the
## deathbed). This is the headline scn14 behavior the whole opcode exists for.
func _test_scn14_balbanes_face_resolution() -> void:
	var vm := _make_vm()
	if not vm.load_chunk_json(SCN14_CHUNK):
		_assert_true(false, "scn14 chunk load for face resolution")
		return
	vm.start()
	# Latch the {50} row exactly as the VM would when it reaches instr 34.
	for inst in vm._insts:
		if str(inst.get("name", "")) == "Portrait Row":
			vm._op_portrait_row(inst)
			break
	_assert_eq(vm._portrait_row, 0, "scn14 latched EVTFACE row 0")

	# Walk the boxed Display Messages and resolve each face the way the box pool
	# does (portrait_visible gate + column + EVTFACE catalog).
	var balbanes_seen := false
	var faceless_count := 0
	for inst in vm._insts:
		if str(inst.get("name", "")) != "Display Message":
			continue
		var intent := ScenarioDecode.display_message(EventInstructionSet.args(inst))
		if (intent.dialog & 0x70) != 0x10:
			continue
		var byte := intent.portrait_row  # the {10} Portrait byte (misnamed field)
		if ScenarioDecode.portrait_visible(intent.dialog, byte):
			var col := ScenarioDecode.portrait_column(byte)
			var face := EvtFaceCatalog.face_texture(vm._portrait_row, col)
			_assert_true(face != null, "visible box resolves an EVTFACE face (byte=%d)" % byte)
			if col == 0 and face != null:
				balbanes_seen = true
		else:
			faceless_count += 1
	_assert_true(balbanes_seen, "scn14 box Portrait 0x01 => EVTFACE(row0,col0) Balbanes")
	_assert_true(faceless_count >= 1, "scn14 Portrait 0x00 boxes take NO EVTFACE override (unit-SPR fallback)")


## The {50} row latch is per-scenario execution state: start() (fresh boot, F3
## rewind/replay, group-member advance) must reset it to -1 so a stale row from a
## previous scene can't paint a spurious EVTFACE portrait on a later box that
## carries no {50} of its own. Mirrors the {22} track-toggle reset.
func _test_row_latch_resets_on_start() -> void:
	var vm := _make_vm()
	vm._portrait_row = 3  # simulate a {50} Row=3 latched by a prior scene
	vm.start()
	_assert_eq(vm._portrait_row, -1, "start() resets the {50} row latch (no cross-scene leak)")


## UIPortrait's EVTFACE render path: display_evtface() switches into EVTFACE mode
## (RGBA face + un-rotated mesh) and shows; going back to a unit SPR via
## display_sprite_id() restores the indexed/rotated path. This is the render seam
## the box uses for {50} event portraits vs the in-battle unit-SPR portrait.
func _test_uiportrait_evtface_mode() -> void:
	var face := EvtFaceCatalog.face_texture(0, 0)
	if face == null:
		_assert_true(false, "EVTFACE face for UIPortrait test")
		return
	var p := UIPortrait.new()
	add_child(p)   # runs _ready (loads shaders, builds mesh)

	p.display_evtface(face)
	_assert_true(p._evtface_mode, "display_evtface => EVTFACE mode")
	_assert_true(p.visible, "display_evtface => visible")
	_assert_true(p._mesh_instance.rotation_degrees.z == 0.0, "EVTFACE mesh un-rotated")

	# Switching to a unit SPR restores the rotated indexed path.
	p.display_sprite_id(0x01)
	_assert_true(not p._evtface_mode, "display_sprite_id restores SPR mode")
	_assert_true(p._mesh_instance.rotation_degrees.z == 90.0, "SPR mesh rotated 90°")

	# Null face hides without crashing.
	p.display_evtface(null)
	_assert_true(not p.visible, "display_evtface(null) hides")

	p.queue_free()
