extends Node
## HEADFUL end-to-end guard for the MANDALIA PLAINS (group root 15) opener camera — the
## defect where the opener panned to empty terrain and popped Ramza's dialogue there.
##
## Mandalia's opener (scn 16) is the first opener that ADDRESSES THE PLAYER'S SQUAD. It
## never *adds* those units — it `Erase`s them at PC 7-13, `Draw`s them back at PC 58-64,
## then `Focus`es 0x01 at PC 76 and speaks as 0x01 at PC 81. The event's own shape is the
## proof that the formation squad must already stand on the field when the opener boots.
## The port used to deploy it one action LATER (inside `run_pre_battle`), so at opener time
## `units_by_id` held only the ENTD cast (0x04 Delita, 0x07 Algus, 0x80+ the corps), the
## `{1F}` Focus(0x01) resolved to nothing, and the `{19}` Camera fell back to the authored
## pose it was only ever meant to OVERWRITE — an off-map tile. 28 of 72 battle groups name
## a player-squad id in their opener; Gariland (root 9) passes only because scn 10 names none.
##
## Asserts, all sampled on the LIVE walk seeked to root 15's opener:
##   (1) the squad is deployed BEFORE the opener's first opcode;
##   (2) it is registered under the formation-squad event ids `0x78`+ AND the `0x01` alias,
##       so the opener's Erase/Draw sweeps address real units;
##   (3) the opener's own Focus(0x01) → Camera RESOLVED onto the deployed leader (not the
##       "target not present" authored-pose fallback = the pan to nowhere).
##
## The opener does not reach `Event End`: it halts on the unimplemented `{B1} Add Variable`
## at PC 84 (the destroy-corps / save-Algus choice is a separate, unwired ticket). That halt
## is this test's settle point — every opcode this test cares about is BEFORE it — so the
## test waits for `is_running()` to go false rather than for a walk terminal.
##
## Real GPU, standalone (never in the parallel suite):
##   godot --path . --quit-after 120 res://tests/NavigatorMandaliaOpenerFocusTest.tscn

const NavigatorMainClass = preload("res://src/scenarios/NavigatorMain.gd")

const SKIP_SLUG := "navigator.skip_pre_battle"
## UNSCALED wall-clock budget (independent of time_scale + the agent-shell present-throttle).
const TIMEOUT_MS := 120000
## Accelerate the async walk (world boot → deploy → opener playback) so it reaches the
## PC-84 halt in a few frames. Matches NavigatorCommandModeProofTest's rationale.
const SIM_TIME_SCALE := 40.0

const MANDALIA_ROOT := 15
const MANDALIA_OPENER_SID := 16
## Mandalia chains onward; stop the plan one group later so root 15 expands in full.
const STOP_ROOT := 24

var _passed: int = 0
var _failed: int = 0
var _nav: Node = null
var _start_ms: int = 0
var _done: bool = false
var _asserted: bool = false
## Latched the first frame the VM is playing with a non-empty registry — i.e. AT the
## opener's boot, before any of its opcodes could have changed the population.
var _uids_at_opener: Array = []
var _saw_running: bool = false
## Sampled every frame while the opener plays; at the PC-84 halt the last value is the
## PC-76 Focus(0x01) result (the opener's final Focus).
var _focus_resolved: bool = false
var _focus_target: Vector3 = Vector3.ZERO
## 🔴 THE DEPLOY IS AS TIME-SENSITIVE AS THE OTHER TWO READINGS, and it was the one
## read after the run instead of latched during it. `NavigatorMain._deployed_owned` is
## provenance for the CURRENT group: `deploy_formation_squad` calls
## `_free_deployed_owned()` first, so the moment the plan walks on to the next root the
## array is empty and the units are freed. The test then read `0 unit(s)` and failed the
## deploy arm while the arm two lines below printed the very squad ids it was looking
## for — two arms of one test disagreeing about one fact. Latch the count and the
## leader's position WHILE the opener plays, the same way `_uids_at_opener` already is.
var _deployed_count: int = 0
var _leader_pos: Vector3 = Vector3.ZERO
var _squad_where: Array = []


func _ready() -> void:
	var action_index := _mandalia_opener_index()
	if action_index < 0:
		print("  [FAIL] could not locate the Mandalia opener action in the plan")
		_failed += 1
		_finish()
		return
	ScenarioDebugSession.navigator_start_root = MANDALIA_ROOT
	ScenarioDebugSession.navigator_stop_root = STOP_ROOT
	ScenarioDebugSession.navigator_start_action = action_index

	# Auto-advance the pre-battle breakpoint: this test's whole subject is what stands on
	# the field BEFORE pre_battle runs, so parking there would prove nothing and hang.
	Tune.bind(SKIP_SLUG, false, {}, Tune.Persist.AUTOSAVE)
	Tune.set_value(SKIP_SLUG, true)

	Engine.time_scale = SIM_TIME_SCALE
	_start_ms = Time.get_ticks_msec()

	var scene: PackedScene = load("res://assets/scenes/NavigatorMain.tscn")
	_nav = scene.instantiate()
	add_child(_nav)


func _process(_delta: float) -> void:
	if _done or _asserted:
		return
	_sample()
	if _saw_running and not _vm_running():
		_assert_and_finish()
		return
	if (Time.get_ticks_msec() - _start_ms) >= TIMEOUT_MS:
		print("  [FAIL] timed out before the opener settled")
		_failed += 1
		_assert_and_finish()


## Per-frame capture. Deploy emits no signal and the VM halts without one, so the two
## time-sensitive readings (who was registered at opener boot, and how the last Focus
## resolved) are latched here rather than reconstructed afterwards.
func _sample() -> void:
	var vm = _nav._vm if _nav != null else null
	if vm == null or not is_instance_valid(vm):
		return
	# The registry reading is time-sensitive and must be taken WHILE the opener plays: the
	# claim is about who was addressable at its first opcode, not who is left at its last.
	if vm.is_running():
		_saw_running = true
		if _uids_at_opener.is_empty() and not vm.units_by_id.is_empty():
			_uids_at_opener = vm.units_by_id.keys()
		var owned: Array = _nav._deployed_owned if _nav != null else []
		if not owned.is_empty():
			# COUNT latches on FIRST sight — the claim is that the squad stood on the field
			# before the opener's first opcode. POSITIONS refresh every frame, because the
			# focus they are compared against is the opener's LAST Focus: pinning the
			# leader's boot position against a halt-time focus would compare two different
			# instants and read as a 5-tile miss that is really a 5-tile walk.
			if _deployed_count == 0:
				_deployed_count = owned.size()
			_squad_where.clear()
			for u in owned:
				_squad_where.append(str(u.global_position) if is_instance_valid(u) else "<freed>")
			if is_instance_valid(owned[0]):
				_leader_pos = owned[0].global_position
	# The focus reading is NOT gated on `is_running()`. The director keeps its last resolution
	# after the halt, and gating cost this arm its subject on the first green run: at
	# time_scale 40 one `_process` frame drains many VM ticks, so the frame that observed the
	# opener still running had not yet reached PC 76 — the latched value was the PC-68
	# Focus(0x04) onto DELITA, four tiles away, and the arm read as "aimed at the wrong unit"
	# when the product was correct.
	var director = vm.camera_director
	if director != null:
		_focus_resolved = bool(director.last_focus_resolved)
		_focus_target = director.last_focus_target_godot


func _vm_running() -> bool:
	var vm = _nav._vm if _nav != null else null
	return vm != null and is_instance_valid(vm) and vm.is_running()


func _assert_and_finish() -> void:
	if _asserted:
		return
	_asserted = true

	# Latched during the walk, NOT read here — see `_deployed_count`'s note. Reading it
	# here is reading the next group's provenance, which is empty.
	_true(_deployed_count > 0,
		"the formation squad was deployed BEFORE the opener played (%d unit(s))" % _deployed_count)

	# (1)+(2) The registry as the opener's first opcode saw it. `0x01` is the protagonist
	# alias the Focus/Display Message name; `0x78`+ are the formation-squad slots the
	# Erase/Draw sweeps name. Both must be present, and present AT OPENER BOOT — a later
	# registration would still leave PC 7-13's Erase addressing nothing.
	_true(_uids_at_opener.has(NavigatorMainClass.RAMZA_EVENT_UID),
		"units_by_id holds 0x01 (Ramza) at opener boot — got %s" % [_fmt_uids(_uids_at_opener)])
	# NON-VACUOUS BY CONSTRUCTION: `want_squad` is floored at 1, so an empty deploy fails this
	# arm instead of passing an empty range. (It passed vacuously on the first red run, which
	# is exactly the reading a burn-down arm must not offer.)
	var want_squad := maxi(mini(_deployed_count, 5), 1)
	var missing: Array = []
	for i in range(want_squad):
		var uid: int = NavigatorMainClass.SQUAD_EVENT_UID_BASE + i
		if not _uids_at_opener.has(uid):
			missing.append("0x%02X" % uid)
	_true(missing.is_empty(),
		"units_by_id holds the formation-squad ids 0x78..0x%02X at opener boot (missing %s, got %s)"
			% [NavigatorMainClass.SQUAD_EVENT_UID_BASE + want_squad - 1, str(missing), _fmt_uids(_uids_at_opener)])

	# (3) The reported defect itself. scn 16's PC 76 Focus(0x01) is the opener's LAST Focus,
	# so the latched value is its result. Assert the FOCUS TARGET, not the camera body — the
	# {19} opcode poses the body at an authored offset + zoom, so it deliberately does not
	# sit on Ramza.
	_true(_focus_resolved,
		"the opener's Focus(0x01) RESOLVED onto a live unit (not the authored-pose fallback)")
	# The leader's POSITION is latched too, for the same reason: the node may be freed by
	# the time the plan halts, and a Vector3 outlives it.
	if _deployed_count > 0:
		var dist := _focus_target.distance_to(_leader_pos)
		_true(_focus_resolved and dist < 2.0,
			"the opener camera aimed at Ramza (%.2f tiles from him; focus=%s leader=%s squad=%s)"
				% [dist, str(_focus_target), str(_leader_pos), str(_squad_where)])
	else:
		_true(false, "a deployed leader was latched for the Focus-target comparison")
	_finish()


## The index of root 15's `opener` action in the real plan — derived, never hardcoded
## (the plan shape is `opener → pre_battle → combat → victory` per battle group).
func _mandalia_opener_index() -> int:
	var plan := GameNavigator.new().plan_actions(MANDALIA_ROOT, STOP_ROOT, StoryMutationScript.build())
	for i in range(plan.size()):
		var a: Dictionary = plan[i]
		if String(a.get("kind", "")) == "opener" \
				and int(a.get("beat", {}).get("scenario_id", -1)) == MANDALIA_OPENER_SID:
			return i
	return -1


func _fmt_uids(uids: Array) -> String:
	var out: Array = []
	for u in uids:
		out.append("0x%02X" % int(u))
	return "[" + ", ".join(out) + "]"


func _true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)


func _finish() -> void:
	if _done:
		return
	_done = true
	Engine.time_scale = 1.0
	print("NavigatorMandaliaOpenerFocusTest: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
