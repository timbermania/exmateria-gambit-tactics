extends Node
## Unit tests for ScenarioDecode — the pure decode layer that turns event-script
## opcode operands into typed intent. No VM, no nodes, no scene: that is the whole
## point of splitting decode out of the apply handlers. Where the old tests had to
## stand up a mock Unit and drive `_op_*`, these exercise the reverse-engineered
## decode directly.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioDecodeTest.tscn

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_warp_unit_intent()
	_test_warp_facing_cardinals()
	_test_sprite_move_offset_axis_remap()
	_test_beta_duration()
	_test_walk_to_fixed_point_speed()
	_test_unit_anim_params()
	_test_rotate_unit_params()
	_test_unit_set_mode()
	_test_unit_set_member()
	_test_resolve_rotate_target_modes()
	_test_map_darkness_intent()
	_test_heading_facing_dir()
	_test_sound_decoders()

	print("\n=== ScenarioDecodeTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioDecodeTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioDecodeTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioDecodeTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(got: bool, name: String) -> void:
	if got:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=false want=true" % name)


func _near(got: float, want: float, name: String, eps: float = 1e-4) -> void:
	if absf(got - want) <= eps:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%f want=%f" % [name, got, want])


# Build an EventInstructionArgs reader from a name->value dict for decoder tests
# (the decoders take the typed reader, not a bare dict). `widths` overrides an
# operand's byte width (default 1) — needed only where a decoder does a width-
# driven signed read (e.g. Sprite Move's 2-byte +X/+Z/+Y).
func _reader(vals: Dictionary, widths: Dictionary = {}) -> EventInstructionArgs:
	var arr: Array = []
	for k in vals:
		arr.append({"name": String(k), "value": int(vals[k]), "bytes": int(widths.get(k, 1))})
	return EventInstructionArgs.from_instruction({"params": arr}, {})


func _test_warp_unit_intent() -> void:
	# Female-knight ground truth: Facing field 3 -> NORTH (0xC00).
	var p := {"Unit": 0x84, "X": 7, "Y": 3, "Facing": 3}
	var intent := ScenarioDecode.warp_unit(_reader(p))
	_eq(intent.uid, 0x84, "warp uid")
	_eq(intent.psx_x, 7, "warp psx_x (raw, not flipped)")
	_eq(intent.psx_y, 3, "warp psx_y (raw — apply does the depth flip)")
	_eq(intent.facing_12bit, 0xC00, "warp facing 3 -> NORTH")


func _test_warp_facing_cardinals() -> void:
	for pair in [[0, 0x000], [1, 0x400], [2, 0x800], [3, 0xC00]]:
		var intent := ScenarioDecode.warp_unit(_reader({"Unit": 1, "X": 0, "Y": 0, "Facing": pair[0]}))
		_eq(intent.facing_12bit, pair[1], "warp facing field %d" % pair[0])
	# The 2-bit field masks — a stray high bit does not change the cardinal.
	var masked := ScenarioDecode.warp_unit(_reader({"Unit": 1, "X": 0, "Y": 0, "Facing": 0x07}))
	_eq(masked.facing_12bit, 0xC00, "warp facing masks to 2 bits (0x07 & 3 = 3)")


func _test_sprite_move_offset_axis_remap() -> void:
	# 28 units = 1 tile. ADR-0052 remap: +X->+X, +Z(height)->-Y, +Y(depth)->-Z.
	var w2 := {"+X": 2, "+Z": 2, "+Y": 2}
	var one_tile := ScenarioDecode.sprite_move_offset(_reader({"+X": 28, "+Z": 0, "+Y": 0}, w2), 28.0)
	_near(one_tile.x, 1.0, "sprite +X one tile -> +X")
	_near(one_tile.y, 0.0, "sprite +X leaves Y")
	_near(one_tile.z, 0.0, "sprite +X leaves Z")
	var height := ScenarioDecode.sprite_move_offset(_reader({"+X": 0, "+Z": 28, "+Y": 0}, w2), 28.0)
	_near(height.y, -1.0, "sprite +Z(height) -> -Y (Y-down->Y-up)")
	var depth := ScenarioDecode.sprite_move_offset(_reader({"+X": 0, "+Z": 0, "+Y": 28}, w2), 28.0)
	_near(depth.z, -1.0, "sprite +Y(depth) -> -Z (ADR-0052)")
	# Signed operands: a negative half-word sign-extends (width from the catalog).
	var neg := ScenarioDecode.sprite_move_offset(_reader({"+X": 0xFFFF, "+Z": 0, "+Y": 0}, w2), 28.0)
	_near(neg.x, -1.0 / 28.0, "sprite -1 operand sign-extends")


func _test_beta_duration() -> void:
	# 4·dist/speed, floored at 1; speed floored at 1.
	_near(ScenarioDecode.beta_duration_frames(28.0, 4), 28.0, "beta 4*28/4 = 28f")
	_near(ScenarioDecode.beta_duration_frames(7.0, 4), 7.0, "beta 4*7/4 = 7f")
	_near(ScenarioDecode.beta_duration_frames(0.0, 4), 1.0, "beta floors at 1 frame")
	_near(ScenarioDecode.beta_duration_frames(28.0, 0), 112.0, "beta floors speed at 1")
	# ⚠️ The `{28}` Walk To cadence is NOT decoded here and is no longer `224/speed`.
	# ADR-0225: it is an integer recurrence the ROM's own stepper runs, and this file's
	# `walk_to_duration_frames` — which asserted 14 f/tile at Speed 16, where the ROM
	# takes 15 — went with it. `ScenarioPathMotionTest.FRAMES_PER_TILE` is where the
	# measured cadence lives now, and `RomWalkStepperTest` is what scores it.


## Positional Walk To operand reader minted against the REAL catalog descriptor
## (opcode 0x28), so a catalog reshuffle fails here rather than silently moving
## which byte is read. `_reader` can't express this instruction: its two
## `Unknown` operands collide as Dictionary keys.
func _walk_to_args(fraction: int, speed: int) -> EventInstructionArgs:
	return EventInstructionSet.args({
		"opcode": 0x28,
		"params": [
			{"name": "Unit", "value": 0x07, "bytes": 2},
			{"name": "X", "value": 4, "bytes": 1},
			{"name": "Y", "value": 11, "bytes": 1},
			{"name": "Z", "value": 1, "bytes": 1},
			{"name": "Unknown", "value": fraction, "bytes": 1},
			{"name": "Speed", "value": speed, "bytes": 1},
			{"name": "Unknown", "value": 1, "bytes": 1},
		],
	})


## `{28}` Speed is ONE 16-bit little-endian 8.8 operand at opcode+6, not the
## `Speed` byte alone (`event_op_walk_to_setup` @0x8013E5C0 ->
## `event_bytecode_reader_c` @0x80146078 -> `unit+0x38 = halfword << 1`
## @0x8008c77c). Dropping the low byte is what made Algus's scenario-29 opening
## walk 224/3 f/tile instead of 224/3.5, so his 4-tile route ran 299 frames
## against the script's 154-frame `Wait 150` + `Wait 4` budget and the pc 47
## Display Message opened on top of a unit still sliding.
func _test_walk_to_fixed_point_speed() -> void:
	# A ZERO fraction is the 276-of-282 corpus case and must decode exactly as
	# the integer operand always did — this is the no-traded-artifact arm.
	for whole in [4, 8, 10, 16]:
		_near(ScenarioDecode.walk_to_speed(_walk_to_args(0, whole)), float(whole),
			"walk speed fraction 0 -> integer Speed %d" % whole)
	# The six corpus instructions that DO carry a fraction (five are scenario 29).
	_near(ScenarioDecode.walk_to_speed(_walk_to_args(0x80, 3)), 3.5, "0x0380 -> Speed 3.5 (scn29 pc 34, Algus)")
	_near(ScenarioDecode.walk_to_speed(_walk_to_args(0x4C, 4)), 4.296875, "0x044C -> Speed 4.297 (scn29 pc 19, Delita)")
	_near(ScenarioDecode.walk_to_speed(_walk_to_args(0x9C, 4)), 4.609375, "0x049C -> Speed 4.609 (scn29 pc 27, Ramza)")
	_near(ScenarioDecode.walk_to_speed(_walk_to_args(0xB4, 5)), 5.703125, "0x05B4 -> Speed 5.703 (scn29 pc 152)")
	_near(ScenarioDecode.walk_to_speed(_walk_to_args(0xB0, 5)), 5.6875, "0x05B0 -> Speed 5.688 (scn29 pc 478)")
	_near(ScenarioDecode.walk_to_speed(_walk_to_args(0x92, 4)), 4.5703125, "0x0492 -> Speed 4.570 (scn117 pc 65)")
	# The cadence that follows is the stepper's, not a formula's: Algus's 4-tile route
	# at Speed 3.5 costs 4x66 + 1 = 265 ROM frames, not the 256 that `224/3.5` predicts
	# and not the 299 the Speed-3 misread produced. ScenarioPathMotionTest asserts it.
	# No `Speed` operand at all -> the caller's default, not a crash.
	_near(ScenarioDecode.walk_to_speed(_reader({"Unit": 7}), 8.0), 8.0, "absent Speed -> default")
	# Independent oracle: the SHIPPED scenario-29 chunk, not a hand-built reader.
	# chunks/ is gitignored and regenerated per machine, so skip loudly if absent.
	const SCN29 := "res://assets/scenarios/chunks/scenario_029_chunk.json"
	if not FileAccess.file_exists(SCN29):
		print("  [skip] scenario 29 chunk not present (gitignored) — asset arm skipped")
		return
	var ins: Array = JsonAsset.load_dict(SCN29).get("instructions", [])
	for row in [[19, 4.296875], [27, 4.609375], [34, 3.5], [152, 5.703125], [478, 5.6875]]:
		var pc: int = row[0]
		if pc >= ins.size():
			_failed += 1
			print("  [FAIL] scn29 chunk has no pc %d" % pc)
			continue
		var inst: Dictionary = ins[pc]
		_eq(String(inst.get("name", "")), "Walk To", "scn29 pc %d is a Walk To" % pc)
		_near(ScenarioDecode.walk_to_speed(EventInstructionSet.args(inst)), float(row[1]),
			"scn29 pc %d decodes its shipped 8.8 Speed" % pc)


func _test_unit_anim_params() -> void:
	# Units/Multi are the raw selector operands (NOT a split u16) — Multi!=0 rows.
	var d := ScenarioDecode.unit_anim(
		_reader({"Units": 0x2E, "Multi": 0x01, "Animation": 0x25A, "Unknown": 0x80}))
	_eq(d.units, 0x2E, "unit_anim Units operand")
	_eq(d.multi, 0x01, "unit_anim Multi operand")
	_eq(d.anim_id, 0x25A, "unit_anim anim id")
	_eq(d.flag, 0x80, "unit_anim flag byte")
	# Missing operands default to 0 (Multi absent -> single-unit selector).
	var d2 := ScenarioDecode.unit_anim(_reader({"Units": 0x0C}))
	_eq(d2.units, 0x0C, "unit_anim Units lo-only")
	_eq(d2.multi, 0, "unit_anim Multi defaults 0 (single)")
	_eq(d2.flag, 0, "unit_anim flag defaults 0")


func _test_rotate_unit_params() -> void:
	var d := ScenarioDecode.rotate_unit(
		_reader({"Units": 0x3A, "Multi": 0x01, "Facing": 0x11, "Direction": 2,
			"Speed": 4, "Delay": 8}))
	_eq(d.units, 0x3A, "rotate Units operand")
	_eq(d.multi, 0x01, "rotate Multi operand")
	_eq(d.facing, 0x11, "rotate facing byte")
	_eq(d.direction, 2, "rotate direction")
	_eq(d.speed, 4, "rotate speed")
	_eq(d.delay, 8, "rotate delay")


func _test_unit_set_mode() -> void:
	var M := ScenarioDecode.UnitSetMode
	# Multi=0, Units≠0 → single unit id. But the selector is V=Units|Multi<<8, and
	# V==0 is the ROM's all-units broadcast sentinel (resolve_event_unit_handle
	# @0x80147928: V==0 → mode 1; FUN_801479ac mode 1 = every existing unit, no team
	# filter). You cannot single-target unit 0 on PSX — id 0 → V=0 → broadcast. So
	# (Units=0,Multi=0) is ALL, not SINGLE. See COLOR_TINT_LUMA_MODE_SEPIA.md §10.4.
	_eq(ScenarioDecode.unit_set_mode(0x0C, 0), M.SINGLE, "Multi=0, Units≠0 → SINGLE")
	_eq(ScenarioDecode.unit_set_mode(0x8B, 0), M.SINGLE, "Multi=0 special-id → SINGLE")
	_eq(ScenarioDecode.unit_set_mode(0, 0), M.ALL, "Units=0,Multi=0 (selector V=0) → ALL (PSX mode 1 broadcast)")
	# Multi=1 → team set indexed by Units (mode = Units+2 in ROM V−0xFE space).
	_eq(ScenarioDecode.unit_set_mode(0, 1), M.PLAYER, "Units=0,Multi=1 → PLAYER")
	_eq(ScenarioDecode.unit_set_mode(1, 1), M.PLAYER_ALIVE, "Units=1,Multi=1 → PLAYER_ALIVE (scn6 rotate)")
	_eq(ScenarioDecode.unit_set_mode(2, 1), M.ENEMY, "Units=2,Multi=1 → ENEMY")
	_eq(ScenarioDecode.unit_set_mode(3, 1), M.ENEMY_ALIVE, "Units=3,Multi=1 → ENEMY_ALIVE")
	_eq(ScenarioDecode.unit_set_mode(4, 1), M.ALL, "Units=4,Multi=1 → ALL")
	_eq(ScenarioDecode.unit_set_mode(5, 1), M.ALL, "Units≥5,Multi=1 → ALL (default arm)")
	# Multi≥2 → the iterator default arm = all present (Multi=2 aliases Units=4).
	_eq(ScenarioDecode.unit_set_mode(0, 2), M.ALL, "Multi=2 → ALL")
	_eq(ScenarioDecode.unit_set_mode(0x2E, 0x3C), M.ALL, "scn1 large-Multi row → ALL")


func _test_unit_set_member() -> void:
	var M := ScenarioDecode.UnitSetMode
	# The scn6 mode-3 (PLAYER_ALIVE) truth table (EVENT_UNIT_SET §5.1): team-0 alive
	# kept (Ovelia team 0), enemy team (Delita team_color 1) dropped. Alliance filter
	# is a documented superset gap — team-0 units are all kept regardless.
	_true(ScenarioDecode.unit_set_member(M.PLAYER_ALIVE, 0, true), "PLAYER_ALIVE keeps team-0 alive (Ovelia)")
	_true(not ScenarioDecode.unit_set_member(M.PLAYER_ALIVE, 1, true), "PLAYER_ALIVE drops enemy team (Delita)")
	_true(not ScenarioDecode.unit_set_member(M.PLAYER_ALIVE, 0, false), "PLAYER_ALIVE drops incapacitated")
	# PLAYER (no alive filter) keeps a team-0 dead unit; ENEMY is its complement.
	_true(ScenarioDecode.unit_set_member(M.PLAYER, 0, false), "PLAYER keeps team-0 regardless of alive")
	_true(ScenarioDecode.unit_set_member(M.ENEMY, 1, true), "ENEMY keeps non-zero team")
	_true(not ScenarioDecode.unit_set_member(M.ENEMY, 0, true), "ENEMY drops team-0")
	_true(ScenarioDecode.unit_set_member(M.ENEMY_ALIVE, 2, true), "ENEMY_ALIVE keeps team-2 alive")
	_true(not ScenarioDecode.unit_set_member(M.ENEMY_ALIVE, 3, false), "ENEMY_ALIVE drops dead enemy")
	# ALL keeps everyone present.
	_true(ScenarioDecode.unit_set_member(M.ALL, 0, true), "ALL keeps player")
	_true(ScenarioDecode.unit_set_member(M.ALL, 1, true), "ALL keeps enemy")


func _test_resolve_rotate_target_modes() -> void:
	# Absolute: byte * 0x100 on the wheel.
	_eq(ScenarioDecode.resolve_rotate_target_12bit(0x04, 0, 0), 0x400, "rotate absolute 0x04 -> 0x400")
	_eq(ScenarioDecode.resolve_rotate_target_12bit(0x0C, 0, 0), 0xC00, "rotate absolute 0x0C -> NORTH")
	# Relative 0x11..0x13: current + N*0x100.
	_eq(ScenarioDecode.resolve_rotate_target_12bit(0x11, 0x400, 0), 0x500, "rotate +1 step from SOUTH")
	_eq(ScenarioDecode.resolve_rotate_target_12bit(0x13, 0xE00, 0), 0x100, "rotate +3 wraps 12-bit")
	# 0x10 camera-relative: yaw quantized to cardinal.
	_eq(ScenarioDecode.resolve_rotate_target_12bit(0x10, 0, 0x300), 0x000, "rotate camera-rel cardinal12(0x300)")
	# 0x14 face-target: no change (keeps current).
	_eq(ScenarioDecode.resolve_rotate_target_12bit(0x14, 0x700, 0), 0x700, "rotate 0x14 no change")


func _test_map_darkness_intent() -> void:
	var baseline := Vector3(20, 4, 0)
	# Scenario-1 darken arm: signed(20,31,31) added to baseline -> (40,35,31).
	var darken := ScenarioDecode.map_darkness(
		_reader({"Blend": 4, "Red": 20, "Green": 31, "Blue": 31, "Time": 4}), baseline)
	_eq(darken.blend, 4, "map_darkness blend")
	_eq(darken.target, Vector3(40, 35, 31), "map_darkness byte-add target")
	_eq(darken.snap, false, "map_darkness Time>0 fades")
	_eq(darken.duration_ticks, 32, "map_darkness dur = Time*8")
	# Time==0 snaps.
	var snap := ScenarioDecode.map_darkness(
		_reader({"Blend": 4, "Red": 20, "Green": 31, "Blue": 31, "Time": 0}), baseline)
	_eq(snap.snap, true, "map_darkness Time==0 snaps")
	_eq(snap.duration_ticks, 0, "map_darkness snap dur 0")
	# Signed bytes + clamp: -20 (=0xEC) drops below rest, clamps at 0.
	var neg := ScenarioDecode.map_darkness(
		_reader({"Blend": 4, "Red": 0xEC, "Green": 0, "Blue": 0, "Time": 2}), baseline)
	_eq(neg.target, Vector3(0, 4, 0), "map_darkness signed R clamps at 0")


func _test_heading_facing_dir() -> void:
	# +X NORTH(0) / -X SOUTH(2) / +Z EAST(1) / -Z WEST(3); dominant axis wins.
	_eq(ScenarioDecode.heading_facing_dir(3.0, 1.0), 0, "heading +X dominant -> NORTH")
	_eq(ScenarioDecode.heading_facing_dir(-3.0, 1.0), 2, "heading -X dominant -> SOUTH")
	_eq(ScenarioDecode.heading_facing_dir(1.0, 3.0), 1, "heading +Z dominant -> EAST")
	_eq(ScenarioDecode.heading_facing_dir(1.0, -3.0), 3, "heading -Z dominant -> WEST")
	# Tie |dx|==|dz| resolves to the X axis (>= test).
	_eq(ScenarioDecode.heading_facing_dir(2.0, 2.0), 0, "heading tie -> X axis (+X NORTH)")
	_eq(ScenarioDecode.heading_facing_dir(-2.0, -2.0), 2, "heading tie -> X axis (-X SOUTH)")


func _test_sound_decoders() -> void:
	# {21} Sound Effect -> raw catalog id.
	_eq(ScenarioDecode.sound_effect(_reader({"Sound": 0x2A})), 0x2A, "sound_effect id")
	# {60} Fade Sound -> PsxNum.fade_ramp_ticks(Time, Shift) = (Time<<(Shift+2))&0x3FFC.
	_eq(ScenarioDecode.fade_sound(_reader({"Time": 4, "Shift Amount": 0})).ticks, 16,
		"fade_sound Time=4 Shift=0 -> 16 ticks")
	_eq(ScenarioDecode.fade_sound(_reader({"Time": 2, "Shift Amount": 1})).ticks, 16,
		"fade_sound Time=2 Shift=1 -> 16 ticks")
	# {22} Switch Track -> volume curve (Volume*127/96) + ticks (Time<<2).
	var sw := ScenarioDecode.switch_track(_reader({"Volume": 48, "Time": 10}))
	_eq(sw.target_vol, 63, "switch_track vol curve 48 -> 63")
	_eq(sw.ticks, 40, "switch_track ticks Time*4")
	_eq(ScenarioDecode.switch_track(_reader({"Volume": 96, "Time": 0})).target_vol, 127,
		"switch_track vol curve caps at 127")
	# {6B}/{6A} BG Sound -> positional [Sound, StartVol, Volume, Stacking, Time].
	var bg := ScenarioDecode.bg_sound(_reader({
		"Sound": 0x11, "Echo": 20, "Volume": 80, "Stacking": 7, "Time": 42}))
	_eq(bg.sound_id, 0x11, "bg_sound id (pos 0)")
	_eq(bg.start_vol, 20, "bg_sound start_vol (pos 1 = Echo)")
	_eq(bg.target_vol, 80, "bg_sound target_vol (pos 2)")
	_eq(bg.stacking, 7, "bg_sound stacking (pos 3)")
	_eq(bg.time, 42, "bg_sound time (pos 4)")
