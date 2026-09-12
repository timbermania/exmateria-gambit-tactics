extends Node
## ADR-0203 dec. 4's oracle: the addon's enable-time provide, CALLED, and every one of the
## eight names checked for its real bindings.
##
## ⚠️ IT USED TO BE THIRTEEN, AND THE FIVE THAT LEFT DID NOT STOP BEING PROVIDED. ADR-0220
## dec. 2 moved `pixel_aspect`, `psx_dither_enabled`, `psx_fx_stretch`, `psx_cursor_stretch` and
## `psx_camera_angle` to `addons/exmateria_platform/plugin.gd`, the addon that DECLARES
## them — see `PlatformProvidesTest.gd`, which asserts their types and defaults now. This
## addon's install register did not move (`check_addon_install` arm 3, still 0), because the
## port is inside this subject's own install target. What changed is that the port is inside
## EVERY subject's target, so `exmateria_sprite_rig` gets them too; it did not before, and
## it did not install.
##
## 🔴 WHY THIS TEST HAS TO EXIST, IN THIS COMMIT. Once ADR-0203 dec. 3 re-points the install
## register's arms 2 and 3, their predicate becomes "the addon requires a name no addon in
## the walk provides". That is satisfied by a STRING APPEARING IN `plugin.gd`. Anyone can
## drive the register to zero by typing eight names into a const array that no code path
## reaches, and the guard cannot tell the difference. dec. 4 calls the register a burn-down
## and calls this the oracle, and requires the two to ship together.
##
## 🔴 AND BOOTING THE GAME PROVES NOTHING HERE. `godot-learning/project.godot` has no
## `[editor_plugins]` section, so no `plugin.gd` in this package has ever had `_enter_tree`
## called. A pass reporting "headful boot, no errors" as evidence for the provide has
## measured the branch where the write does not happen. This test reaches the write the only
## way anything in this repo can: by calling it.
##
## 🔴 IT MUST NEVER TOUCH THE REAL `ProjectSettings`. `_enter_tree` pairs the write with
## `ProjectSettings.save()`, which rewrites `project.godot` on disk. `provide_into` takes its
## surface as a PARAMETER precisely so this test can hand it a double; a test that wrote the
## real settings would edit the repo as a side effect of being run.
##
## Run: bash tests/stranger/exmateria_battlefield/run.sh   (ADR-0194 — addon-owned, runs in
## a STRANGER project. Directly: "$GODOT" --path . --quit-after 5
## res://addons/exmateria_battlefield/tests/BattlefieldProvidesTest.tscn)

var _passed: int = 0
var _failed: int = 0

## Every test function that RAN TO ITS LAST LINE. 🔴 THIS COUNTER IS NOT BOOKKEEPING — it
## was added because this test file green-lit a `plugin.gd` that did not have a
## `provide_into` at all. Calling a nonexistent static on a `GDScript` pushes an error and
## returns null rather than halting, so five of the seven functions then below did nothing,
## and the verdict block saw `2 passed, 0 failed` and printed **[PASS]**. The `_passed == 0
## and _failed == 0` guard cannot catch that: two assertions DID pass. A test whose subject
## is missing must go RED, not quiet, so the verdict demands every arm reported — six of
## them since ADR-0220 dec. 2 retired the shader-global arm to `PlatformProvidesTest`.
var _completed: Array[String] = []


## A dictionary-backed stand-in for `ProjectSettings`, exposing the two methods
## `provide_into` uses and nothing else. Records write ORDER, which no arm reads today —
## it was for asserting the eight actions landed before the five globals, and since
## ADR-0220 dec. 2 this addon provides no globals to order against.
class FakeSettings extends RefCounted:
	var store: Dictionary = {}
	var order: Array[String] = []

	func has_setting(key: String) -> bool:
		return store.has(key)

	func set_setting(key: String, value) -> void:
		if value == null:
			store.erase(key)
			order.erase(key)
			return
		if not store.has(key):
			order.append(key)
		store[key] = value


func _ready() -> void:
	_test_the_script_actually_compiled()
	_test_all_eight_land_on_an_empty_project()
	_test_every_action_carries_its_real_bindings()
	_test_an_existing_name_is_never_overwritten()
	_test_revoke_removes_only_what_was_added()
	_test_provided_keys_matches_what_the_write_produces()

	print("\n=== BattlefieldProvidesTest: %d passed, %d failed, %d/6 arms reported ==="
		% [_passed, _failed, _completed.size()])
	if _passed == 0 and _failed == 0:
		print("[FAIL] BattlefieldProvidesTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _completed.size() != 6:
		# See `_completed`. An arm that aborted mid-way — because the subject is missing a
		# method, not because an assertion failed — contributes NO failures, so the counts
		# above look clean while most of this file did not run.
		print("[FAIL] BattlefieldProvidesTest: only %d of 6 arms ran to completion — %s"
			% [_completed.size(), str(_completed)])
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] BattlefieldProvidesTest")
		get_tree().quit(1)
	else:
		print("[PASS] BattlefieldProvidesTest")
		get_tree().quit(0)


## The subject loads AND compiles.
##
## ⚠️ `load()` is not a compile witness — a script whose parse FAILED still comes back as a
## `GDScript`, so every assertion below would run against a corpse and the static calls
## would silently do nothing. `get_instance_base_type()` is `""` for a script that did not
## compile, which is the cheap way to tell the two apart.
func _test_the_script_actually_compiled() -> void:
	var script: GDScript = _plugin()
	_assert(script != null, "plugin.gd loads")
	if script == null:
		_completed.append("_test_the_script_actually_compiled")
		return
	_assert(script.get_instance_base_type() != "",
		"plugin.gd COMPILED — a parse-failed script still `load()`s as a GDScript, and every"
		+ " assertion below would then pass vacuously against a script that does nothing")

	_completed.append("_test_the_script_actually_compiled")

## The whole point: on a project holding none of them, all eight are written.
##
## 🔴 AND NOTHING ELSE IS. The `shader_globals/` half of the assertion is a NEGATIVE now,
## and it is the arm that pins ADR-0220 dec. 2 from this side: an entry re-added to this
## addon's `PROVIDED_GLOBALS` would be provided from an addon that declares none of them,
## which is the layering inversion that left `exmateria_sprite_rig` uninstallable. Arm 4c
## of `check_addon_portability` cannot see it — 4c scores DECLARERS, and a provide with no
## declaration behind it is invisible to a scan that starts at the declarations.
func _test_all_eight_land_on_an_empty_project() -> void:
	var fake := FakeSettings.new()
	var added: Array[String] = _plugin().provide_into(fake)

	_assert_eq_int(added.size(), 8, "eight names added to a bare project")
	_assert_eq_int(fake.store.size(), 8, "eight settings present afterwards")

	for name in ["camera_up", "camera_down", "camera_left", "camera_right",
			"rotate_camera_cw", "rotate_camera_ccw", "unit_inspect", "cursor_confirm"]:
		_assert(fake.store.has("input/" + name), "input/%s provided" % name)
	for key in fake.store:
		_assert(not str(key).begins_with("shader_globals/"),
			"%s must NOT be provided here — this addon declares no `global uniform` and"
			% key + " therefore provides none (ADR-0220 dec. 2)")

	_completed.append("_test_all_eight_land_on_an_empty_project")

## Every action arrives as a real Godot input-map entry — a deadzone and REAL `InputEvent`
## objects, not the description of one.
##
## The specific bindings are asserted rather than merely counted, because "the name exists"
## is not what a provide is for: a bare project is supposed to behave like the in-repo one.
## `cursor_confirm` carrying Enter and NOT Space is the one with a live consequence — Space
## starts the battle, so riding `ui_accept` would make starting a battle also a confirm
## (ADR-0137). `CursorConfirmEndToEndTest` pins the same fact from the host's side.
func _test_every_action_carries_its_real_bindings() -> void:
	var fake := FakeSettings.new()
	_plugin().provide_into(fake)

	var want := {
		"camera_up": [KEY_W, KEY_UP],
		"camera_down": [KEY_S, KEY_DOWN],
		"camera_left": [KEY_A, KEY_LEFT],
		"camera_right": [KEY_D, KEY_RIGHT],
		"rotate_camera_cw": [KEY_Q],
		"rotate_camera_ccw": [KEY_E],
		"unit_inspect": [KEY_TAB],
		"cursor_confirm": [KEY_ENTER, KEY_KP_ENTER],
	}
	for name in want:
		var decl = fake.store.get("input/" + name)
		if typeof(decl) != TYPE_DICTIONARY:
			_fail("input/%s is a Dictionary" % name)
			continue
		_assert(is_equal_approx(float(decl.get("deadzone", -1.0)), 0.5),
			"input/%s deadzone is 0.5" % name)
		var keys: Array = []
		for e in decl.get("events", []):
			_assert(e is InputEvent, "input/%s event is a real InputEvent" % name)
			if e is InputEventKey:
				keys.append(e.physical_keycode)
		for code in want[name]:
			_assert(code in keys, "input/%s binds physical keycode %d" % [name, code])

	# THE PAD HALF, which this arm did not have and which ADR-0268 dec. 6 made load-bearing.
	# The provide's whole claim is *"a bare project behaves like the in-repo one"*, and it was
	# only ever checked on keys — so the four pad buttons `PROVIDED_ACTIONS` already carried
	# were unguarded, and adding L1/R1 to the two rotate actions would have been unguarded too.
	# Pads asserted the same way the keys are: PRESENT, not exclusive, because `project.godot`
	# is free to add a binding the addon's default does not know about (and this is the arm
	# that would notice if it stopped being free to).
	var want_pads := {
		"camera_up": [JOY_BUTTON_DPAD_UP],
		"camera_down": [JOY_BUTTON_DPAD_DOWN],
		"camera_left": [JOY_BUTTON_DPAD_LEFT],
		"camera_right": [JOY_BUTTON_DPAD_RIGHT],
		"rotate_camera_cw": [JOY_BUTTON_LEFT_SHOULDER],
		"rotate_camera_ccw": [JOY_BUTTON_RIGHT_SHOULDER],
		"unit_inspect": [JOY_BUTTON_Y],
		"cursor_confirm": [JOY_BUTTON_B],
	}
	for name in want_pads:
		var decl2 = fake.store.get("input/" + name)
		if typeof(decl2) != TYPE_DICTIONARY:
			continue
		var pads: Array = []
		for e in decl2.get("events", []):
			if e is InputEventJoypadButton:
				pads.append(e.button_index)
		for idx in want_pads[name]:
			_assert(idx in pads, "input/%s binds pad button %d" % [name, idx])

	var confirm_keys: Array = []
	for e in fake.store["input/cursor_confirm"].get("events", []):
		if e is InputEventKey:
			confirm_keys.append(e.physical_keycode)
	_assert(not (KEY_SPACE in confirm_keys),
		"cursor_confirm must NOT carry Space — Space starts the battle (ADR-0137)")

	_completed.append("_test_every_action_carries_its_real_bindings")

## A consumer that already declares a name keeps ITS value.
##
## The in-repo game declares all eight itself and should keep doing so (ADR-0203 dec. 4).
## This is ADR-0203 dec. 2's permitted read doing its job: the `has_setting` guard is part
## of the write, and without it the idempotent spelling of the thing dec. 8 permits would
## itself be forbidden.
##
## ⚠️ THE `pixel_aspect` SEED STAYS, AND IT ASSERTS SOMETHING DIFFERENT NOW. It used to prove the
## `has_setting` guard skipped a name this addon provides; since ADR-0220 dec. 2 this addon
## provides no shader globals at all, so it proves the SHED — the value survives because
## nothing here ever writes that key.
func _test_an_existing_name_is_never_overwritten() -> void:
	var fake := FakeSettings.new()
	fake.set_setting("input/cursor_confirm", {"deadzone": 0.25, "events": []})
	fake.set_setting("shader_globals/pixel_aspect", {"type": "float", "value": 2.5})

	var added: Array[String] = _plugin().provide_into(fake)

	_assert_eq_int(added.size(), 7, "the pre-declared action is not re-added")
	_assert(not ("input/cursor_confirm" in added), "cursor_confirm not reported as added")
	_assert(not ("shader_globals/pixel_aspect" in added),
		"pixel_aspect is not this addon's to provide (ADR-0220 dec. 2)")
	_assert(is_equal_approx(float(fake.store["input/cursor_confirm"]["deadzone"]), 0.25),
		"the consumer's own deadzone survives")
	_assert(is_equal_approx(float(fake.store["shader_globals/pixel_aspect"]["value"]), 2.5),
		"the consumer's own pixel_aspect survives")

	_completed.append("_test_an_existing_name_is_never_overwritten")

## Disable removes what enable added, and NOTHING the consumer owned.
##
## Removing on the way out what a consumer declared itself would delete their line from
## their project file — `exmateria_sound/plugin.gd` carries `_added` for the same reason.
func _test_revoke_removes_only_what_was_added() -> void:
	var fake := FakeSettings.new()
	fake.set_setting("input/cursor_confirm", {"deadzone": 0.25, "events": []})
	fake.set_setting("application/config/name", "someone else's project")

	var added: Array[String] = _plugin().provide_into(fake)
	_plugin().revoke_from(fake, added)

	_assert(fake.store.has("input/cursor_confirm"),
		"a name the consumer declared SURVIVES disable")
	_assert(fake.store.has("application/config/name"),
		"an unrelated setting is untouched")
	_assert_eq_int(fake.store.size(), 2, "everything this plugin added is gone")

	_completed.append("_test_revoke_removes_only_what_was_added")

## `provided_keys()` is what the re-pointed register arms read. If it drifted from what
## `provide_into` actually writes, the register would score a name the addon does not
## install, or miss one it does — the burn-down and the oracle disagreeing silently.
func _test_provided_keys_matches_what_the_write_produces() -> void:
	var fake := FakeSettings.new()
	var added: Array[String] = _plugin().provide_into(fake)
	var declared: Array[String] = _plugin().provided_keys()

	_assert_eq_int(declared.size(), 8, "provided_keys() names eight settings")
	for key in declared:
		_assert(key in added, "%s is declared AND actually written" % key)
	for key in added:
		_assert(key in declared, "%s is written AND actually declared" % key)

	_completed.append("_test_provided_keys_matches_what_the_write_produces")

func _plugin() -> GDScript:
	return load("res://addons/exmateria_battlefield/plugin.gd") as GDScript


# --- assert helpers ----------------------------------------------------------

func _assert(ok: bool, name: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("  [x] %s" % name)


func _assert_eq_int(got: int, want: int, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [x] %s — got %d, want %d" % [name, got, want])


func _fail(name: String) -> void:
	_failed += 1
	print("  [x] %s" % name)
