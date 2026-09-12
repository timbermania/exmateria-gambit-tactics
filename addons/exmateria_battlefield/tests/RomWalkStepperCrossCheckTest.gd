extends Node
## Differential cross-check: `RomWalkStepper.gd` against `rom_walk_render.py`, on
## randomised terrain and randomised route buffers.
##
## 🔴 **THIS TEST SAYS NOTHING ABOUT THE ROM.** `RomWalkStepperTest` is the one that
## does — it replays thirteen live PSX captures, and those are hardware. This one
## replays a seeded random corpus whose expected values come from the **Python
## transcription**, so it cannot catch a misreading: both implementations were
## written from the same reading of `battle_decompilation.c`, and a shared mistake
## passes here silently.
##
## What it CAN catch is the entire population of errors a PORT introduces — a
## mistyped constant, an inverted comparison, a dropped sign, a wrong table index —
## and it catches them where the captures cannot look.
##
## The thirteen captures are all ordinary `{28} Walk To` traversals on MAP009, so
## whole arms of the machine are never entered by them. This corpus reaches **all
## 32 states** of `unit+0x7f`, `0x01`–`0x20`, over 8 751 frames, and fires 222
## landing sounds and 82 puffs. Concretely, it is the only coverage of:
##
##   * the LEAP (`FUN_8006A538`) and the WIND-UP states it arms at `extra >= 2`
##   * the BIG JUMP (`FUN_8006A7C0`) — a >= 4-level climb, which `{28}` itself can
##     never emit, so no capture will ever reach it
##   * HARD LANDING and `FUN_8006C3D8`'s recovery hold
##   * the landing SOUND and PUFF tables — 46 surfaces across four sound classes
##   * the FAR-FALL pose swap at 42 render units
##   * the steep-slope GAIT and its ACCELERATING `+0x3C`
##
## Regenerate: `uv run python tools/gen_rom_walk_fuzz_fixtures.py` (seeded, so the
## corpus is reproducible and reviewable).
##
## Run: "$GODOT" --path . --quit-after 15 res://addons/exmateria_battlefield/tests/RomWalkStepperCrossCheckTest.tscn

const RomWalkStepper = preload("res://addons/exmateria_battlefield/motion/RomWalkStepper.gd")

const FIXTURE_DIR := "res://addons/exmateria_battlefield/tests/fixtures/rom_walk_fuzz"

## Fixture column name -> the `RomWalkStepper` property holding the same thing.
const FIELD_MAP := {
	"st": "state",
	"x": "render_x", "y": "render_y", "z": "render_z",
	"vx": "vel_x", "vy": "vel_y", "vz": "vel_z",
	"dstx": "dst_x", "dsty": "dst_y", "dstlevel": "dst_level",
	"tilex": "tile_x", "tiley": "tile_y", "level": "level",
	"idx": "route_index", "rb": "route_byte",
	"anim": "anim", "facing": "facing", "altmag": "alt_mag",
}

## Matches the generator's own cap, so a non-terminating configuration is bounded
## identically on both sides rather than differing because one gave up first.
const MAX_FRAMES: int = 900

## The machine has 32 states, `0x01`..`0x20`. Anything less than all of them means
## the corpus stopped covering what this test exists to cover — a regenerated
## fixture set that quietly narrowed is the failure mode.
const EXPECTED_STATES: int = 32

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
	_test_every_fuzz_case_agrees()

	print("\n=== RomWalkStepperCrossCheckTest: %d passed, %d failed, %d/1 arms reported ==="
		% [_passed, _failed, _completed.size()])
	if _passed == 0 and _failed == 0:
		print("[FAIL] RomWalkStepperCrossCheckTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _completed.size() != 1:
		# See `_completed`: an aborted arm adds no failures, so the line above is
		# clean while most of this file did not run.
		print("[FAIL] RomWalkStepperCrossCheckTest: only %d of 1 arms ran to completion — ran %s"
			% [_completed.size(), str(_completed.keys())])
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] RomWalkStepperCrossCheckTest")
		get_tree().quit(1)
	else:
		print("[PASS] RomWalkStepperCrossCheckTest")
		get_tree().quit(0)


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


func _test_every_fuzz_case_agrees() -> void:
	var index: Variant = _load_json("%s/index.json" % FIXTURE_DIR)
	if index == null:
		_failed += 1
		print("  [FAIL] fixtures missing — run tools/gen_rom_walk_fuzz_fixtures.py")
		return
	var cases: Array = index["cases"]
	_true(cases.size() >= 40, "a corpus worth running (%d cases)" % cases.size())

	var ok: int = 0
	var total: int = 0
	var frames: int = 0
	var states := {}
	var sounds: int = 0
	var puffs: int = 0
	for name: String in cases:
		var fx: Variant = _load_json("%s/%s.json" % [FIXTURE_DIR, name])
		if fx == null:
			_failed += 1
			print("  [FAIL] %s: fixture unreadable" % name)
			continue
		var res: Array = _score(fx)
		ok += res[0]
		total += res[1]
		frames += res[2]
		for s: int in res[3]:
			states[s] = true
		sounds += int(fx["sounds"].size())
		puffs += int(fx["puffs"].size())

	print("  VERDICT: %d of %d field-frames over %d cases, %d frames, %d states, %d sound(s), %d puff(s)"
		% [ok, total, cases.size(), frames, states.size(), sounds, puffs])
	_eq(ok, total, "every fuzz case agrees with the spec")
	# 🔴 The coverage claim is asserted, not printed. A regenerated corpus that
	# quietly stopped reaching the leap, the big jump or the landings would still
	# report "0 differ" — over a machine it never entered.
	_eq(states.size(), EXPECTED_STATES,
		"the corpus reaches all %d states of `unit+0x7f`" % EXPECTED_STATES)
	_true(sounds > 0, "the landing SOUND table is driven (%d)" % sounds)
	_true(puffs > 0, "the landing PUFF table is driven (%d)" % puffs)
	_completed["_test_every_fuzz_case_agrees"] = true



## Returns `[matching, total, frames, states_seen]`.
func _score(fx: Dictionary) -> Array:
	var name: String = fx["name"]
	var size: Array = fx["size"]
	var start: Array = fx["start"]
	var fields: Array = fx["fields"]
	var want: Array = fx["frames"]

	var terrain := RomWalkStepper.terrain_from_packed(
		fx["tiles"], int(size[0]), int(size[1]))
	var s := RomWalkStepper.new()
	s.configure(terrain, Vector3i(int(start[0]), int(start[1]), int(start[2])),
		fx["route"], float(fx["speed"]), int(fx["anim0"]), int(fx["landing_frames"]))

	var got: Array = []
	var states: Array = []
	while got.size() < MAX_FRAMES and s.step():
		var row: Array = []
		for f: String in fields:
			row.append(s.get(FIELD_MAP[f]))
		got.append(row)
		states.append(s.state)

	# The frame COUNT is part of the comparison. A port that terminates early
	# matches on every frame it produced and is still a different machine.
	_eq(got.size(), want.size(), "%s: %d frames" % [name, want.size()])

	var n: int = mini(got.size(), want.size())
	var bad: int = 0
	var first_bad := {}
	for i in n:
		for c in fields.size():
			if want[i][c] != got[i][c]:
				bad += 1
				if not first_bad.has(fields[c]):
					first_bad[fields[c]] = [i, want[i][c], got[i][c]]
	var total: int = n * fields.size()

	# The landing tables are only exercised through their EFFECTS, so compare the
	# emitted sequences too — a wrong surface class is otherwise invisible.
	_eq(s.sounds, _ints(fx["sounds"]), "%s: landing sound sequence" % name)
	_eq(s.puffs, _ints(fx["puffs"]), "%s: landing puff sequence" % name)

	if bad == 0:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %-8s %d of %d field-frames (%d differ)" % [name, total - bad, total, bad])
		for k: String in first_bad:
			var fb: Array = first_bad[k]
			print("         %-8s first at frame +%d: spec %s, port %s"
				% [k, fb[0], str(fb[1]), str(fb[2])])
	return [total - bad, total, n, states]


## JSON numbers arrive as floats; the stepper's lists are `Array[int]`.
func _ints(a: Array) -> Array[int]:
	var out: Array[int] = []
	for v in a:
		out.append(int(v))
	return out
