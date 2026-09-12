extends Node
## Unit tests for PsxNum — the PSX numeric conventions of the event-script
## interpreter (sign extension, u16 LE packing, the 12-bit clockwise facing wheel,
## ADR-0052 depth-flip). Pure static functions, so this needs no scene, no VM, no
## nodes — the point of extracting them.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/PsxNumTest.tscn

## ADR-0212 dec. 1 — `addons/exmateria_platform` used to declare `DisplayPort`
## (the name of a hardware standard), `PsxNum` and `TunePort` as bare globals. It
## now declares only `ExMateriaPlatform`; aliasing them back keeps every use site
## below spelled the way it was (ADR-0211 dec. 4).
const PsxNum = ExMateriaPlatform.PsxNum

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_sign_extension()
	_test_u16_pack()
	_test_facing_wheel_cardinals()
	_test_heading_to_12bit()
	_test_warp_facing_field()
	_test_direction_and_facing_byte()
	_test_look_at_matches_vm_delegate()
	_test_depth_flip()
	_test_track_volume_curve()
	_test_fade_ramp_ticks()

	print("\n=== PsxNumTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] PsxNumTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] PsxNumTest")
		get_tree().quit(1)
	else:
		print("[PASS] PsxNumTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _test_sign_extension() -> void:
	_eq(PsxNum.s8(0x00), 0, "s8 zero")
	_eq(PsxNum.s8(0x7F), 127, "s8 max positive")
	_eq(PsxNum.s8(0x80), -128, "s8 min negative")
	_eq(PsxNum.s8(0xFF), -1, "s8 -1")
	_eq(PsxNum.s8(0x1FF), -1, "s8 masks high bits")
	_eq(PsxNum.s16(0x0000), 0, "s16 zero")
	_eq(PsxNum.s16(0x7FFF), 32767, "s16 max positive")
	_eq(PsxNum.s16(0x8000), -32768, "s16 min negative")
	_eq(PsxNum.s16(0xFFFF), -1, "s16 -1")
	_eq(PsxNum.s16(0x1_0001), 1, "s16 masks high bits")


func _test_u16_pack() -> void:
	_eq(PsxNum.u16_lohi(0x2E, 0x01), 0x012E, "u16 lohi scenario-1 row")
	_eq(PsxNum.u16_lohi(0x34, 0x00), 0x0034, "u16 lohi high-byte zero")
	_eq(PsxNum.u16_lohi(0x1FF, 0x1FF), 0xFFFF, "u16 lohi masks each byte")


func _test_facing_wheel_cardinals() -> void:
	# The wheel: 0=E, 0x400=S, 0x800=W, 0xC00=N.
	_eq(PsxNum.EAST_12BIT, 0x000, "east const")
	_eq(PsxNum.SOUTH_12BIT, 0x400, "south const")
	_eq(PsxNum.WEST_12BIT, 0x800, "west const")
	_eq(PsxNum.NORTH_12BIT, 0xC00, "north const")
	_eq(PsxNum.wrap12(0x1000), 0x000, "wrap12 full turn -> 0")
	_eq(PsxNum.wrap12(0x1C00), 0xC00, "wrap12 over one turn")
	_eq(PsxNum.cardinal12(0xC80), 0xC00, "cardinal12 snaps to N")
	_eq(PsxNum.octant12(0x1234), 0x200, "octant12 masks to 0xF00 grid")


func _test_heading_to_12bit() -> void:
	# Forward world-heading (dx, dz) -> 12-bit ORIENTATION angle. A Walk To knows its
	# real heading, so it writes facing_angle straight from the heading — NOT by routing
	# through the FacingDirection enum (that render-view backward arrow is what ADR-0057
	# forbids). Godot world axes: +X=NORTH, -X=SOUTH, +Z=EAST, -Z=WEST. The wheel is the
	# same one heading_facing_dir maps to: +X->0xC00(N), -X->0x400(S), +Z->0x000(E),
	# -Z->0x800(W). A tie (|dx| >= |dz|) resolves to the X axis, matching the handler.
	_eq(PsxNum.heading_to_12bit(3.0, 1.0), 0xC00, "heading +X dominant -> NORTH 0xC00")
	_eq(PsxNum.heading_to_12bit(-3.0, 1.0), 0x400, "heading -X dominant -> SOUTH 0x400")
	_eq(PsxNum.heading_to_12bit(1.0, 3.0), 0x000, "heading +Z dominant -> EAST 0x000")
	_eq(PsxNum.heading_to_12bit(1.0, -3.0), 0x800, "heading -Z dominant -> WEST 0x800")
	# Ties resolve to the X axis (|dx| >= |dz|).
	_eq(PsxNum.heading_to_12bit(2.0, 2.0), 0xC00, "heading tie -> X axis (+X NORTH)")
	_eq(PsxNum.heading_to_12bit(-2.0, -2.0), 0x400, "heading tie -> X axis (-X SOUTH)")
	# The chocobo beat: Warp faced WEST (0x800); the +X walk must orient NORTH.
	_eq(PsxNum.heading_to_12bit(1.07, 0.0), 0xC00, "chocobo +X walk -> NORTH 0xC00")


func _test_warp_facing_field() -> void:
	# ROM writer 0x80087c1c: field << 10. 3 -> NORTH is the female-knight ground truth.
	_eq(PsxNum.warp_facing_to_12bit(0), 0x000, "warp field 0 -> EAST")
	_eq(PsxNum.warp_facing_to_12bit(1), 0x400, "warp field 1 -> SOUTH")
	_eq(PsxNum.warp_facing_to_12bit(2), 0x800, "warp field 2 -> WEST")
	_eq(PsxNum.warp_facing_to_12bit(3), 0xC00, "warp field 3 -> NORTH")


func _test_direction_and_facing_byte() -> void:
	# Unit Anim Rotate Direction nibble << 8, masked to the octant grid.
	_eq(PsxNum.direction_to_12bit(0), 0x000, "direction 0")
	_eq(PsxNum.direction_to_12bit(4), 0x400, "direction 4 -> SOUTH")
	_eq(PsxNum.direction_to_12bit(0xC), 0xC00, "direction C -> NORTH")
	# Rotate Unit absolute facing byte * 0x100.
	_eq(PsxNum.facing_byte_to_12bit(0x04), 0x400, "facing byte 0x04 -> SOUTH")
	_eq(PsxNum.facing_byte_to_12bit(0x10), 0x000, "facing byte 0x10 wraps a full turn")


func _test_look_at_matches_vm_delegate() -> void:
	# PsxNum.look_at_12bit is the impl; ScenarioVM.face_unit_look_at_12bit_psx now
	# delegates to it. The octant table is pinned in ScenarioFaceUnitTest — here we
	# assert the delegate is wired and the canonical live-validated beat holds.
	var ScenarioVMClass = load("res://src/scenarios/ScenarioVM.gd")
	# affected 0x0c vs faced 0x84 on the same row, knight to lateral: (Δx=0, Δy>0) -> East.
	_eq(PsxNum.look_at_12bit(0, 5), 0x400, "look_at (0,+) -> 0x400 East")
	_eq(ScenarioVMClass.face_unit_look_at_12bit_psx(0, 5),
		PsxNum.look_at_12bit(0, 5), "VM delegate == PsxNum impl")


func _test_depth_flip() -> void:
	# ADR-0052: godot_z = size_z - 1 - psx_z. Ramza raw row 3 on a 10-deep map.
	_eq(PsxNum.flip_depth_row(3, 10), 6, "depth flip row 3 of 10")
	_eq(PsxNum.flip_depth_row(0, 10), 9, "depth flip near edge")
	_eq(PsxNum.flip_depth_row(9, 10), 0, "depth flip far edge")
	# Continuous sibling (#140, ADR-0057 chokepoint): godot_z = size_z - psx_z,
	# the closed form for the camera body's real-valued depth. At a tile CENTRE
	# it agrees with the integer row flip: row r at psx_z=r+0.5 -> size-1-r+0.5.
	_eq(PsxNum.flip_depth_continuous(3.5, 10), 6.5, "continuous flip at row-3 centre")
	_eq(PsxNum.flip_depth_continuous(0.0, 10), 10.0, "continuous flip near edge")
	_eq(PsxNum.flip_depth_continuous(10.0, 10), 0.0, "continuous flip far edge")
	# The two chokepoint forms differ by exactly the +0.5 tile-centring: a body
	# at the map's flip centre (size/2) maps to itself only via the continuous form.
	_eq(PsxNum.flip_depth_continuous(5.0, 10), 5.0, "continuous flip centre is fixed point")


func _test_track_volume_curve() -> void:
	# {22} FUN_8012db90: 0->0, >=96->127, else Volume*127/96 (integer division).
	_eq(PsxNum.track_volume_curve(0), 0, "vol 0 -> 0")
	_eq(PsxNum.track_volume_curve(-5), 0, "vol negative floors at 0")
	_eq(PsxNum.track_volume_curve(96), 127, "vol 96 -> 127 (clamp threshold)")
	_eq(PsxNum.track_volume_curve(200), 127, "vol above threshold clamps at 127")
	_eq(PsxNum.track_volume_curve(48), (48 * 127) / 96, "vol 48 -> linear 63")
	_eq(PsxNum.track_volume_curve(95), (95 * 127) / 96, "vol 95 -> linear (just below clamp)")


func _test_fade_ramp_ticks() -> void:
	# {60}: (Time << (Shift+2)) & 0x3FFC. Shift 0 == Time*4.
	_eq(PsxNum.fade_ramp_ticks(1, 0), 4, "fade Time=1 Shift=0 -> 4 ticks")
	_eq(PsxNum.fade_ramp_ticks(10, 0), 40, "fade Time=10 Shift=0 -> 40")
	_eq(PsxNum.fade_ramp_ticks(1, 2), 16, "fade Shift=2 scales by 16")
	# The 0x3FFC mask both caps the count and clears the low 2 bits.
	_eq(PsxNum.fade_ramp_ticks(0x1000, 0), 0x0000, "fade mask wraps large Time to 0")
	_eq(PsxNum.fade_ramp_ticks(0xFFF, 0), 0x3FFC, "fade mask caps at 0x3FFC")
