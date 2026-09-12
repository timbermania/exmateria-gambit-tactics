extends Node
# test-kind: gpu
# seeded-break: set `ScenarioPathApplier._MAX_FF_FRAMES` to 1 — the opener's fast-forward is cut off before its terminal {19} and the camera arm reds with an earlier pose (PC 28 is `angle 301 / map_rot 5637`) instead of the PC-35 one. A second, independent seed: delete the `unit.facing_direction = deploy_facing` line in `NavigatorMain._deploy_owned_units` and the facing arm reds.
## "Play battle N" is a SEEK into the navigator, and this is its permanent guard (ADR-0264).
##
## `--battle=9` plans Gariland's group alone and begins the walk at its `pre_battle` action.
## Everything the old gambit host got wrong about that battle is a thing the spine already
## does right, and this test asserts the three of them ON THE LIVE WALK, at the deployment
## pause, in one process:
##
##   1. FRAMING is the opener's terminal `{19}`, not a default. Gariland's opener (scn 10)
##      settles at PC 35 — `Angle 302 / Map Rotation 5632 / Zoom 4096`, where 302 and 4096
##      are the ROM's `camera_init` constants (`FUN_8008e468`) and 5632 is the map-dependent
##      yaw. The seek reaches it by fast-forwarding the opener at 30x, and a truncated
##      fast-forward fails SILENTLY into an earlier `{19}` — scn 10 carries five of them and
##      the one before the terminal (PC 28) is `301 / 5637`, a few units away. That near-miss
##      is why this arm asserts the whole pose and not "the camera moved".
##
##   2. FACING is the deployment zone's authored nibble. Zone 256 carries
##      `unit_facing: 2 -> unit_facing_12bit: 0x000` (East, toward the far-half thieves) and
##      a separate `zone_facing: 3`. `tools/parse_placement.py:94` records that `zone_facing`
##      rotates the zone's TILES but is deliberately not folded into `unit_facing`, validated
##      against one zone, with the note *"revisit with a second live oracle if a future battle
##      deploys facing wrong."* THIS ARM IS THAT SECOND ORACLE: it pins the deployed squad to
##      the unfolded 0x000. If the fold turns out to be right, this reds — and the fix is a
##      ticket against the parser, not a number edited here.
##
##   3. THE CLOCK RUNS at the deployment pause. `ScenarioCast` stamps spawned units
##      `clock_owner = COMBAT`, `TurnDirector.open_deployment()` leaves `combat_active` false
##      and no GPU simulator exists until commit — so on any host that does not arrange
##      otherwise, NOTHING ticks and the squad stands on IDLE frame 0. The spine arranges
##      otherwise by riding `ScenarioVM.idle_only_units` on the one 60 Hz tick (ADR-0065), so
##      the honest assertion is that the frames ADVANCE, not that a register is populated.
##      A `{80}` March opcode would supply a pose and not a tick; it cannot substitute.
##
## The three share one boot (world + ENTD spawn + opener fast-forward + deploy), which is
## exactly the setup charter clause 13 says to carry every assertion of.
##
## Run: "$GODOT" --path . res://tests/NavigatorBattleLaunchTest.tscn

const AnimationStateController = ExMateriaSpriteRig.AnimationStateController
const DeploymentZoneDatabase = ExMateriaAlmanac.DeploymentZoneDatabase
const ScenarioDatabase = ExMateriaAlmanac.ScenarioDatabase
const AwaitUntilLib = preload("res://tests/lib/await_until.gd")

## Gariland Fight — the battle group whose ROOT is its setup record's id (ADR-0264),
## so this is the same 9 that `--scenario=9` has always named.
const BATTLE_ROOT := 9

## The opener's TERMINAL `{19}` (scn 10, PC 35) — the authored entry framing, in opcode units.
const OPENER_SETTLE := {"x": 504, "y": 840, "z": 19, "angle": 302, "map_rot": 5632, "zoom": 4096}

## Gariland's deployment zone and the facing it authors. Written out rather than read from the
## table alone so that a table edit reds this test instead of silently redefining it.
const ZONE_IDX := 256
const ZONE_UNIT_FACING_NIBBLE := 2
const ZONE_UNIT_FACING_12BIT := 0x000
const ZONE_FACING_NIBBLE := 3

const SKIP_SLUG := "navigator.skip_pre_battle"

## Accelerate the walk's async boot (world -> deploy -> 30x opener fast-forward). Scales the
## SIMULATION, not the verdict: every budget below is in FRAMES (charter clause 14).
const SIM_TIME_SCALE := 40.0

## Frame budget for the walk to reach the deployment pause. Deliberately far above what the
## boot needs (the whole test measures 5.6 s wall on an idle box) — the budget is not a
## measurement, it is the bound that turns a hang into a VERDICT instead of the runner's
## 360 s HUNG, and a budget tuned close to the observed cost is a flake under load.
const PARK_FRAMES := 4200

## Frame budget for every deployed unit to advance one animation frame. The VM ticks at 60 Hz
## and an idle clip holds each frame for a handful of ticks, so a squad that is ticking at all
## clears this in single digits.
const IDLE_FRAMES := 180

var _passed: int = 0
var _failed: int = 0
var _nav: Node = null


func _ready() -> void:
	# The CLI launcher's own entry point (`--battle=N` parks it here), set directly so the
	# test drives the real launch path rather than a hand-built seek.
	DebugConfig.battle_seek_root = BATTLE_ROOT
	DebugConfig.battle_watch_opener = false
	# No competing seek: a stale panel request would re-root the walk and win (NavigatorMain).
	ScenarioDebugSession.navigator_start_root = -1
	ScenarioDebugSession.navigator_stop_root = -1
	ScenarioDebugSession.navigator_start_action = -1
	ScenarioDebugSession.rewind_target_pc = -1
	# Skip OFF is the whole point: the walk must PARK at the deployment pause, which is where
	# all three assertions are taken.
	Tune.bind(SKIP_SLUG, false, {}, Tune.Persist.AUTOSAVE)
	Tune.set_value(SKIP_SLUG, false)

	Engine.time_scale = SIM_TIME_SCALE
	_nav = load("res://assets/scenes/NavigatorMain.tscn").instantiate()
	add_child(_nav)

	var parked: bool = await AwaitUntilLib.frames(
		self, func(): return _nav != null and bool(_nav._pre_battle_active), PARK_FRAMES)
	# Back to real time before anything is observed: the animation arm below watches a clock,
	# and watching it at 40x proves less than watching it at 1x.
	Engine.time_scale = 1.0
	if not parked:
		_true(false, "the --battle=%d walk reached the deployment pause within %d frames"
			% [BATTLE_ROOT, PARK_FRAMES])
		_finish()
		return
	_true(true, "the --battle=%d walk reached the deployment pause" % BATTLE_ROOT)

	_assert_opener_framing()
	_assert_zone_facing()
	await _assert_march_idle()
	_finish()


## 1. The camera settled on the opener's terminal `{19}`.
func _assert_opener_framing() -> void:
	var vm = _nav._vm
	if vm == null or vm.camera_director == null:
		_true(false, "the battle world has a scenario VM with a camera director")
		return
	var director = vm.camera_director
	if not bool(director._has_last_camera):
		_true(false, "the opener fast-forward applied a Camera opcode (none did)")
		return
	var got: Dictionary = director._last_camera_params
	print("  [info] settled camera pose: %s" % str(got))
	for key in OPENER_SETTLE:
		_eq(int(got.get(key, -0x7FFFFFFF)), int(OPENER_SETTLE[key]),
			"opener scn 10 PC 35 settled camera %s" % key)


## 2. The deployed squad faces the zone's authored `unit_facing`, unfolded.
func _assert_zone_facing() -> void:
	var scenario: Dictionary = ScenarioDatabase.get_scenario(BATTLE_ROOT)
	var zone_idx := int(scenario.get("first_squad_deployment_idx", -1))
	_eq(zone_idx, ZONE_IDX, "Gariland's setup record names deployment zone %d" % ZONE_IDX)
	var zone: Dictionary = DeploymentZoneDatabase.get_zone(zone_idx)
	# The DATA half of the oracle: the parser's unfolded reading of this zone.
	_eq(int(zone.get("unit_facing", -1)), ZONE_UNIT_FACING_NIBBLE, "zone %d unit_facing nibble" % ZONE_IDX)
	_eq(int(zone.get("zone_facing", -1)), ZONE_FACING_NIBBLE, "zone %d zone_facing nibble" % ZONE_IDX)
	_eq(int(zone.get("unit_facing_12bit", -1)), ZONE_UNIT_FACING_12BIT,
		"zone %d unit_facing lifts to 0x%03X with zone_facing NOT folded in" % [ZONE_IDX, ZONE_UNIT_FACING_12BIT])

	# The LIVE half: every deployed unit stands that way after the opener has run over it.
	var want := AnimationStateController.angle_12bit_to_facing(ZONE_UNIT_FACING_12BIT)
	var deployed: Array = _nav._deployed_owned
	_true(deployed.size() > 0, "the launch deployed the owned squad")
	var wrong := 0
	for u in deployed:
		if not is_instance_valid(u) or int(u.facing_direction) != int(want):
			wrong += 1
	_eq(wrong, 0, "all %d deployed units face the zone's authored 0x%03X (survived the opener)"
		% [deployed.size(), ZONE_UNIT_FACING_12BIT])


## 3. The squad is march-idling at the pause — frames ADVANCE, on the one VM tick.
func _assert_march_idle() -> void:
	var deployed: Array = _nav._deployed_owned
	if deployed.is_empty():
		_true(false, "there is a deployed squad whose animation clock can be watched")
		return
	var before: Array = []
	for u in deployed:
		before.append(int(u.anim_frame) if is_instance_valid(u) else -1)
	var advanced := {}
	for _i in range(IDLE_FRAMES):
		if advanced.size() == deployed.size():
			break
		await get_tree().process_frame
		for j in deployed.size():
			var u = deployed[j]
			if is_instance_valid(u) and int(u.anim_frame) != int(before[j]):
				advanced[j] = true
	_eq(advanced.size(), deployed.size(),
		"all %d deployed units advanced their idle frame within %d frames (none frozen on frame 0)"
			% [deployed.size(), IDLE_FRAMES])


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
		print("  [PASS] %s (%s)" % [name, str(got)])
	else:
		_failed += 1
		print("  [FAIL] %s — got %s, want %s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % name)
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


func _finish() -> void:
	print("\n=== NavigatorBattleLaunchTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] NavigatorBattleLaunchTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] NavigatorBattleLaunchTest")
		get_tree().quit(1)
	else:
		print("[PASS] NavigatorBattleLaunchTest")
		get_tree().quit(0)
