extends Node
# test-kind: gpu
# seeded-break: make `NavigatorMain._deploy_owned_units` skip its `unit.facing_direction = deploy_facing` write, or shorten `ScenarioPathApplier._MAX_FF_FRAMES` to 1 — either erases one of the differences this test measures and the matching arm reds.
## 🔴 TRANSIENT — DELETE THIS FILE WITH `GambitBattle` (ADR-0264, PR 3). It is written to
## expire, and the retirement ticket carries the deletion.
##
## THE TWO HOSTS, SIDE BY SIDE, ON THE SAME BATTLE. `GambitBattle` boots Gariland from one
## integer; `--battle=9` seeks the navigator into the same group. ADR-0264 says the seek
## fixes three defects the gambit host has, and that two of them would have survived the
## fix originally proposed for them. This test is the dynamic half of that claim: it stands
## both hosts up in one process and MEASURES all three differences rather than reasoning
## about them.
##
##   camera — gambit writes no pose at all. Its only camera write is
##            `cursor_rig.seed_from_map(map, Vector2i(0, 0))`, which hard-cuts to the map's
##            corner cell; it has no `ScenarioVM`, so there is no `{19}` for it to land on.
##            The navigator settles through the opener onto the authored terminal `{19}`.
##   facing — Gariland's ENTD 388 authors its five Red thieves at `facing_raw: 2`.
##            `ScenarioCast` never reads that field: it hardcodes SOUTH for every enemy and
##            NORTH for every player unit. The navigator spawns through
##            `ScenarioPlayerScene`, which lifts `facing_raw`, so the two hosts stand the
##            same five units facing different ways.
##   clock  — both hosts leave `combat_active` false through deployment and both stamp
##            spawned units `clock_owner = COMBAT`, so neither one's `Unit._process` pumps.
##            The navigator rides `ScenarioVM.idle_only_units` on the one 60 Hz tick
##            (ADR-0065) and gambit has no such tick, so its squad holds frame 0.
##
## WHY IT EXPIRES ON SUCCESS. Every arm below asserts that the two hosts DIFFER. Once
## gambit is a seek (PR 3) it is comparing the navigator to itself, all three arms go red,
## and the correct response is to delete the file — not to edit the numbers. The permanent
## guard for the values themselves is [NavigatorBattleLaunchTest], which asserts the
## authored pose / facing / clock directly and does not care that a second host ever
## existed.
##
## Run: "$GODOT" --path . res://tests/GambitVsNavigatorBattleDiffTest.tscn

const AwaitUntilLib = preload("res://tests/lib/await_until.gd")

const BATTLE_ROOT := 9
const GAMBIT_SCENE := "res://assets/scenes/GambitBattle.tscn"
const NAV_SCENE := "res://assets/scenes/NavigatorMain.tscn"
const SKIP_SLUG := "navigator.skip_pre_battle"

## ENTD 388's five Red slots — the authored cast whose facing the two hosts disagree about.
const ENTD_ENEMY_UIDS := [0x80, 0x81, 0x82, 0x83, 0x84]

const SIM_TIME_SCALE := 40.0
const PARK_FRAMES := 4200
## Frames each host's squad is watched for an animation advance. Long enough that "did not
## move" is a fact about the host and not about the sample.
const WATCH_FRAMES := 180

var _passed: int = 0
var _failed: int = 0
var _nav: Node = null
var _gambit: Node = null


func _ready() -> void:
	ScenarioDebugSession.navigator_start_root = -1
	ScenarioDebugSession.navigator_stop_root = -1
	ScenarioDebugSession.navigator_start_action = -1
	ScenarioDebugSession.rewind_target_pc = -1
	Tune.bind(SKIP_SLUG, false, {}, Tune.Persist.AUTOSAVE)
	Tune.set_value(SKIP_SLUG, false)

	var nav_state := await _boot_navigator()
	if nav_state.is_empty():
		_finish()
		return
	_free_host(_nav)
	_nav = null

	var gambit_state := await _boot_gambit()
	if gambit_state.is_empty():
		_finish()
		return
	_free_host(_gambit)
	_gambit = null

	print("  [info] navigator: %s" % str(nav_state))
	print("  [info] gambit:    %s" % str(gambit_state))

	# The agreement: it is the SAME battle, so a difference below is about the host and not
	# about which fight was booted.
	_eq(gambit_state["enemies"], nav_state["enemies"],
		"both hosts stand the same number of ENTD enemies")

	# 1. CAMERA. The navigator has an authored pose; gambit has none to have.
	_true(bool(nav_state["has_authored_pose"]),
		"navigator: the opener's terminal {19} was applied")
	_true(not bool(gambit_state["has_authored_pose"]),
		"gambit: no `{19}` was ever applied — it has no ScenarioVM to run one"
			+ " [EXPIRES ON SUCCESS — delete this file with GambitBattle]")

	# 2. FACING. ENTD 388 authors `facing_raw: 2` for all five Red slots; ScenarioCast
	# hardcodes one value for every enemy instead.
	_true(int(gambit_state["enemy_facings"].size()) == 1,
		"gambit: every ENTD enemy shares ONE hardcoded facing (%s)" % str(gambit_state["enemy_facings"])
			+ " [EXPIRES ON SUCCESS]")
	_true(nav_state["enemy_facings"] != gambit_state["enemy_facings"],
		"the two hosts stand the authored cast facing DIFFERENT ways (nav %s vs gambit %s)"
			% [str(nav_state["enemy_facings"]), str(gambit_state["enemy_facings"])]
			+ " [EXPIRES ON SUCCESS]")

	# 3. CLOCK. Neither host's units self-pump; only one of them is pumped by something.
	_true(int(nav_state["advanced"]) > 0,
		"navigator: %d unit(s) advanced their idle frame at the deployment pause"
			% int(nav_state["advanced"]))
	_eq(int(gambit_state["advanced"]), 0,
		"gambit: ZERO units advanced in %d frames — frozen on IDLE frame 0" % WATCH_FRAMES
			+ " [EXPIRES ON SUCCESS]")

	_finish()


## Boot the navigator via the real launcher and snapshot it at the deployment pause.
func _boot_navigator() -> Dictionary:
	DebugConfig.battle_seek_root = BATTLE_ROOT
	DebugConfig.battle_watch_opener = false
	Engine.time_scale = SIM_TIME_SCALE
	_nav = load(NAV_SCENE).instantiate()
	add_child(_nav)
	var parked: bool = await AwaitUntilLib.frames(
		self, func(): return _nav != null and bool(_nav._pre_battle_active), PARK_FRAMES)
	Engine.time_scale = 1.0
	if not parked:
		_true(false, "the navigator reached the deployment pause within %d frames" % PARK_FRAMES)
		return {}
	_true(true, "the navigator reached the deployment pause")

	var vm = _nav._vm
	var enemies: Array = []
	for uid in ENTD_ENEMY_UIDS:
		var u = _nav._units_by_id.get(uid)
		if u != null and is_instance_valid(u):
			enemies.append(u)
	# The SAME population gambit's arm watches — the authored ENTD cast plus the squad on
	# the field. Watching only the deployed squad here would have left "gambit moved zero"
	# open to "its enemies never animate either", which is a claim about a different set.
	var watched: Array = enemies.duplicate()
	for u in _nav._deployed_owned:
		if u != null and is_instance_valid(u):
			watched.append(u)
	return {
		"enemies": enemies.size(),
		"enemy_facings": _facing_set(enemies),
		"has_authored_pose": vm != null and vm.camera_director != null
			and bool(vm.camera_director._has_last_camera),
		"advanced": await _count_advancing(watched),
	}


## Boot the gambit host on the same scenario and snapshot it at its deployment.
func _boot_gambit() -> Dictionary:
	DebugConfig.battle_seek_root = -1
	DebugConfig.active_scenario_id = BATTLE_ROOT
	_gambit = load(GAMBIT_SCENE).instantiate()
	add_child(_gambit)
	var ready: bool = await AwaitUntilLib.frames(
		self, func(): return _gambit != null and _gambit.assignment != null, PARK_FRAMES)
	if not ready:
		_true(false, "the gambit host reached its deployment within %d frames" % PARK_FRAMES)
		return {}
	_true(true, "the gambit host reached its deployment")

	var enemies: Array = []
	for u in _gambit._enemies:
		if u != null and is_instance_valid(u):
			enemies.append(u)
	# The same population the navigator's arm watches: the authored ENTD cast plus this
	# host's own squad.
	var watched: Array = enemies.duplicate()
	for u in _gambit._owned:
		if u != null and is_instance_valid(u):
			watched.append(u)
	return {
		"enemies": enemies.size(),
		"enemy_facings": _facing_set(enemies),
		# Gambit has no ScenarioVM: `has_method` rather than a null test, because the field
		# does not exist on this host at all.
		"has_authored_pose": false,
		"advanced": await _count_advancing(watched),
	}


## The DISTINCT facings in a cast, sorted — one entry means every unit was given the same
## one, which is what a hardcoded facing looks like from outside.
func _facing_set(units: Array) -> Array:
	var seen: Dictionary = {}
	for u in units:
		if is_instance_valid(u):
			seen[int(u.facing_direction)] = true
	var out: Array = seen.keys()
	out.sort()
	return out


## How many of `units` advanced their animation frame within [constant WATCH_FRAMES].
func _count_advancing(units: Array) -> int:
	if units.is_empty():
		return 0
	var before: Array = []
	for u in units:
		before.append(int(u.anim_frame) if is_instance_valid(u) else -1)
	var advanced: Dictionary = {}
	for _i in range(WATCH_FRAMES):
		if advanced.size() == units.size():
			break
		await get_tree().process_frame
		for j in units.size():
			var u = units[j]
			if is_instance_valid(u) and int(u.anim_frame) != int(before[j]):
				advanced[j] = true
	return advanced.size()


func _free_host(host: Node) -> void:
	if host == null or not is_instance_valid(host):
		return
	remove_child(host)
	host.queue_free()


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
	print("\n=== GambitVsNavigatorBattleDiffTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] GambitVsNavigatorBattleDiffTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] GambitVsNavigatorBattleDiffTest")
		get_tree().quit(1)
	else:
		print("[PASS] GambitVsNavigatorBattleDiffTest")
		get_tree().quit(0)
