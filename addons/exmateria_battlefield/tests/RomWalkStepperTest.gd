extends Node
## Scores `RomWalkStepper` against the PSX wire — the thirteen `{28} Walk To`
## captures taken off a live emulator in 2026-09, frame for frame, over sixteen
## logged fields.
##
## The fixtures under `tests/fixtures/rom_walk/` hold the **LIVE** rows, not a
## simulation's: `tools/gen_rom_walk_fixtures.py` bakes them straight out of the
## PSX logs in `research/scenario29_walk_vs_jump/evidence/`, together with the
## post-patch MAP009 tile array each arm ran against. So this test is scored
## against hardware, and it needs no `res://assets/maps` — that is an asset
## SYMLINK, absent from a bare worktree, and a test that reached for it would go
## red for a reason that has nothing to do with the walk.
##
## The thirteen are not thirteen repeats of one thing:
##
##   control, armK, armL      the shipped walk, a widened moat, a leap that climbs
##   armV1, armV3             the steep-slope gait — route bits 2 and 3
##   armSPD3H/4/16/32         Speeds 3.5, 4, 16 and 32 — three animation bands and
##                            one FRACTIONAL operand
##   armW1..armW4             all ten previously unexercised drape shapes
##
## ⚠️ `compare_frames` is asserted, not just the mismatch count. A stepper that
## halts after three frames scores "0 differ" over three frames, which reads
## exactly like a pass.
##
## Run: "$GODOT" --path . --quit-after 5 res://addons/exmateria_battlefield/tests/RomWalkStepperTest.tscn

const RomWalkStepper = preload("res://addons/exmateria_battlefield/motion/RomWalkStepper.gd")

const FIXTURE_DIR := "res://addons/exmateria_battlefield/tests/fixtures/rom_walk"

## Live-trace column name -> the `RomWalkStepper` property holding the same thing.
const FIELD_MAP := {
	"st": "state",
	"x": "render_x", "y": "render_y", "z": "render_z",
	"vx": "vel_x", "vy": "vel_y", "vz": "vel_z",
	"dx": "dst_x", "dy": "dst_y",
	"i": "route_index",
	"tx": "tile_x", "ty": "tile_y", "tl": "level",
	"c11c": "route_byte",
	"anim": "anim",
	"v3c": "alt_mag",
}

## Frames of headroom over the longest capture, so a stepper that never terminates
## is bounded rather than hanging the suite.
const MAX_FRAMES: int = 4000

## Arms that ran to COMPLETION, by name.
##
## 🔴 A GDScript runtime error aborts only its ENCLOSING function. An arm that dies
## part-way — on a malformed fixture, a bad index, a renamed member — contributes
## NO failures, so `_ready` resumes, the counters still read `N passed, 0 failed`,
## and this file prints **[PASS]** over a test that never ran. That is strictly
## worse than a hang: a hang is scored HUNG and somebody looks at it; a false green
## is believed, and its assertion count goes into a commit message as evidence.
##
## The pattern is `BattlefieldProvidesTest`'s, four files away in this same addon.
var _completed := {}

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_fixed_point_primitives()
	_test_walk_anim_is_a_band_not_a_constant()
	_test_fractional_speed_is_little_endian_8_8()
	_test_the_wading_band_is_reached()
	_test_every_capture_matches_the_wire()

	print("\n=== RomWalkStepperTest: %d passed, %d failed, %d/5 arms reported ==="
		% [_passed, _failed, _completed.size()])
	if _passed == 0 and _failed == 0:
		print("[FAIL] RomWalkStepperTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _completed.size() != 5:
		# See `_completed`: an aborted arm adds no failures, so the line above is
		# clean while most of this file did not run.
		print("[FAIL] RomWalkStepperTest: only %d of 5 arms ran to completion — ran %s"
			% [_completed.size(), str(_completed.keys())])
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] RomWalkStepperTest")
		get_tree().quit(1)
	else:
		print("[PASS] RomWalkStepperTest")
		get_tree().quit(0)


# --- helpers ------------------------------------------------------------------

func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


func _load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


# --- tests --------------------------------------------------------------------

## The two GTE routines the whole trajectory is built on, at the values that make
## them load-bearing.
func _test_fixed_point_primitives() -> void:
	# 🔴 A cardinal axis normalises to 4095, NOT 4096. That one-subunit shortfall
	# is why a Speed-10 walk moves 5118 subunits a frame against a magnitude of
	# 5120 — the cadence is not `224/Speed` exactly, it falls out of this.
	var v := RomWalkStepper.vec3_normalize(RomWalkStepper.TILE, 0, 0)
	_eq(v, Vector3i(4095, 0, 0), "vec3_normalize(+X) = 4095, not 4096")
	_eq(RomWalkStepper.vec3_normalize(0, 0, -RomWalkStepper.TILE), Vector3i(0, 0, -4095),
		"vec3_normalize(-Z) = -4095")

	# `SquareRoot0` is NOT `64*sqrt(x)`: that approximation runs 0.15 % high and
	# misses the hop's launch velocity by 25 subunits.
	var dh_one_level := 2                                    # a 1-level rise, half-levels
	var arg := (dh_one_level * 6 + 1) * RomWalkStepper.GRAVITY * 2
	_eq(RomWalkStepper.square_root0(arg), 15764, "hop launch velY, 1-level rise")
	_eq(RomWalkStepper.square_root0(arg) / RomWalkStepper.GRAVITY, 6,
		"1-level rise: 6 airborne frames")
	var arg2 := (4 * 6 + 1) * RomWalkStepper.GRAVITY * 2
	_eq(RomWalkStepper.square_root0(arg2), 21864, "hop launch velY, 2-level rise")
	_eq(RomWalkStepper.square_root0(arg2) / RomWalkStepper.GRAVITY, 9,
		"2-level rise: 9 airborne frames")

	# MIPS divides toward zero. A floor would put the drape one render unit low on
	# every tile west or north of the origin.
	_eq(RomWalkStepper.trunc_div(-7, 2), -3, "trunc_div rounds toward zero")
	_eq(RomWalkStepper.sar12(-1), 0, "sar12(-1) = 0, not -1")
	_completed["_test_fixed_point_primitives"] = true



## 🔴 The finding six sessions of transcription missed. `FUN_80082DF8` re-picks the
## walk animation from a BAND of `unit+0x38` on every re-latch, and Speed 10 —
## the only Speed ever shipped on the wire before 2026-09 — clears the first
## threshold by ONE subunit. A hard-coded `14` scored 14 502 of 14 502 field-frames
## across five captures and was still wrong for 80 of the 282 shipped `{28}`s.
func _test_walk_anim_is_a_band_not_a_constant() -> void:
	var terrain := RomWalkStepper.terrain_flat(_flat_heights(4, 4, 0), 4, 4)
	for probe: Array in [
			[3.5, 14], [4.0, 14], [10.0, 14],     # +0x38 < 0x1401
			[11.0, 12], [16.0, 12], [23.0, 12],   # < 0x3000
			[24.0, 13], [32.0, 13]]:              # else
		var s := RomWalkStepper.new()
		s.configure(terrain, Vector3i(1, 1, 0), [1, 0x00], probe[0])
		s.step()                                   # arms the first step, latching
		s.step()                                   # paints it
		_eq(s.anim, probe[1], "Speed %.1f -> walk anim %d" % [probe[0], probe[1]])

	# The boundary itself: Speed 10 is 5120 against a threshold of 5121.
	var s10 := RomWalkStepper.new()
	s10.configure(terrain, Vector3i(1, 1, 0), [1, 0x00], 10.0)
	_eq(s10.mag, 5120, "Speed 10 -> +0x38 = 5120")
	_eq(RomWalkStepper.WALK_ANIM_SLOW, 5121, "the threshold it clears by one")
	_completed["_test_walk_anim_is_a_band_not_a_constant"] = true



## The Speed operand is a LITTLE-ENDIAN 8.8 halfword, not an integer: `+0x38` is
## `raw << 1`. Six shipped `{28}`s are fractional (scenario 29 PCs 19/27/34/152/478
## and scenario 117 PC 65), and an `int` operand rounds all six to the wrong
## magnitude — which is a different animation band for at least one of them.
func _test_fractional_speed_is_little_endian_8_8() -> void:
	var terrain := RomWalkStepper.terrain_flat(_flat_heights(4, 4, 0), 4, 4)
	var s := RomWalkStepper.new()
	s.configure(terrain, Vector3i(1, 1, 0), [1, 0x00], 3.5)
	_eq(s.mag, 1792, "Speed 3.5 -> +0x38 = (0x0380) << 1")
	var s2 := RomWalkStepper.new()
	s2.configure(terrain, Vector3i(1, 1, 0), [1, 0x00], 4.297)
	_eq(s2.mag, 0x044C << 1, "scenario 29 pc 19's 0x044C survives the round trip")
	_completed["_test_fractional_speed_is_little_endian_8_8"] = true



## The wading band — `FUN_8008278C`'s `depth >= 2` column — is `[STATIC]`, and until
## 2026-09-03 it was also UNREACHABLE: `rom_walk_render.py` made `depth_class` a
## defaulted parameter and nothing passed it, while its comment claimed the band was
## merely unobserved. The ROM has no parameter — `FUN_80082DF8` reads the depth
## itself at `0x80082E1C`. This is the arm that says the wire is connected; the
## thirteen captures cannot say it, because MAP009's moat is depth 1.
func _test_the_wading_band_is_reached() -> void:
	for probe: Array in [[3.5, 11], [10.0, 11], [16.0, 9], [32.0, 10]]:
		var terrain := RomWalkStepper.terrain_flat(_flat_heights(4, 4, 0), 4, 4)
		# Depth 2 under the unit's own render position — the tile it STANDS on when
		# `arm_walk` re-latches, which is not the tile it is walking to.
		terrain.tile(1, 1, 0).depth = 2
		var s := RomWalkStepper.new()
		s.configure(terrain, Vector3i(1, 1, 0), [1, 0x00], probe[0])
		s.step()
		s.step()
		_eq(s.anim, probe[1], "Speed %.1f wading -> anim %d" % [probe[0], probe[1]])
	# depth 1 is NOT wading: the threshold is `>= 2`, and MAP009's moat is depth 1,
	# which is why every capture reads the dry column.
	var shallow := RomWalkStepper.terrain_flat(_flat_heights(4, 4, 0), 4, 4)
	shallow.tile(1, 1, 0).depth = 1
	var d1 := RomWalkStepper.new()
	d1.configure(shallow, Vector3i(1, 1, 0), [1, 0x00], 10.0)
	d1.step()
	d1.step()
	_eq(d1.anim, 14, "depth 1 is not wading — the dry band, as every capture reads")
	_completed["_test_the_wading_band_is_reached"] = true



## The load-bearing one: every capture, every compared frame, every field.
func _test_every_capture_matches_the_wire() -> void:
	var index: Variant = _load_json("%s/index.json" % FIXTURE_DIR)
	if index == null:
		# ABSENT IS NOT WRONG in a standalone clone. Each capture carries MAP009's
		# tile array verbatim, so `export_standalone.py` excludes this whole fixture
		# directory as Square Enix data (register step 9, the user's "no square
		# assets" ruling) and `tools/gen_rom_walk_fixtures.py` cannot rebuild it
		# there — it bakes from `research/scenario29_walk_vs_jump/`, outside the
		# package. The exclusion is permanent, not a bootstrap step.
		#
		# SKIP THE ARM, NOT THE TEST, and mark it completed. The other four arms are
		# pure integrator logic over literals and are unaffected, so a clone still
		# scores 4 of 5 arms; declaring the arm complete is what keeps the
		# `_completed.size() != 5` check from calling that a silent abort, which is
		# the one thing it exists to catch.
		print("  [SKIP] wire captures absent — excluded from the standalone repo as "
			+ "Square Enix data (MAP009 tile geometry). The other 4 arms still ran.")
		_completed["_test_every_capture_matches_the_wire"] = true
		return
	var cases: Array = index["cases"]
	_true(cases.size() == 13, "13 scored captures on disk (got %d)" % cases.size())

	var grand_ok: int = 0
	var grand_total: int = 0
	for name: String in cases:
		var fx: Variant = _load_json("%s/%s.json" % [FIXTURE_DIR, name])
		if fx == null:
			_failed += 1
			print("  [FAIL] %s: fixture unreadable" % name)
			continue
		var res: Array = _score(fx)
		grand_ok += res[0]
		grand_total += res[1]
	print("  VERDICT: %d of %d field-frames over %d captures (%d differ)"
		% [grand_ok, grand_total, cases.size(), grand_total - grand_ok])
	_true(grand_total > 0, "the captures produced field-frames to compare")
	_eq(grand_ok, grand_total, "every capture reproduces the wire")
	_completed["_test_every_capture_matches_the_wire"] = true



## Replay one fixture and compare. Returns `[matching_field_frames, total]`.
func _score(fx: Dictionary) -> Array:
	var name: String = fx["name"]
	var size: Array = fx["size"]
	var start: Array = fx["start"]
	var fields: Array = fx["fields"]
	var live: Array = fx["frames"]

	var terrain := RomWalkStepper.terrain_from_packed(
		fx["tiles"], int(size[0]), int(size[1]))
	var s := RomWalkStepper.new()
	s.configure(terrain, Vector3i(int(start[0]), int(start[1]), int(start[2])),
		fx["route"], float(fx["speed"]), int(fx["anim0"]), int(fx["landing_frames"]))

	var sim: Array = []
	while sim.size() < MAX_FRAMES and s.step():
		var row: Array = []
		for f: String in fields:
			row.append(s.get(FIELD_MAP[f]))
		sim.append(row)

	var n: int = mini(live.size(), sim.size())
	# ⚠️ Without this, a stepper that halts after three frames scores 0 differ.
	_eq(n, int(fx["compare_frames"]), "%s: compared %d frames" % [name, fx["compare_frames"]])

	var bad: int = 0
	var first_bad := {}
	for i in n:
		for c in fields.size():
			if live[i][c] != sim[i][c]:
				bad += 1
				if not first_bad.has(fields[c]):
					first_bad[fields[c]] = [i, live[i][c], sim[i][c]]
	var total: int = n * fields.size()
	if bad == 0:
		_passed += 1
		print("  [ok] %-9s %5d of %5d field-frames" % [name, total, total])
	else:
		_failed += 1
		print("  [FAIL] %-9s %d of %d field-frames (%d differ)" % [name, total - bad, total, bad])
		for k: String in first_bad:
			var fb: Array = first_bad[k]
			print("         %-5s first at frame +%d: live %s, sim %s"
				% [k, fb[0], str(fb[1]), str(fb[2])])
	return [total - bad, total]


## `[level][psx_y][x] -> height`, every tile the same — the shape `terrain_flat`
## wants for a synthetic probe.
func _flat_heights(nx: int, ny: int, h: int) -> Array:
	var out: Array = []
	for _lvl in 2:
		var rows: Array = []
		for _y in ny:
			var row: Array = []
			for _x in nx:
				row.append(h)
			rows.append(row)
		out.append(rows)
	return out
