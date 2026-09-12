extends Node
## ADR-0203 dec. 4's oracle for the PORT's provide: the enable-time write, CALLED, and every
## one of the six `[shader_globals]` names checked for type and default.
##
## 🔴 WHY THIS TEST HAS TO EXIST, IN THIS COMMIT. `check_addon_portability.py`'s arm 4c
## (ADR-0220 dec. 1) reds a `global uniform` its declaring addon does not provide. Its
## predicate is A STRING APPEARING IN `plugin.gd`. Anyone can drive it to zero by typing six
## names into a const array that no code path reaches, and the guard cannot tell the
## difference — the identical hazard ADR-0203 dec. 4 named for the install register, and it
## takes the identical answer: the guard is the burn-down, this is the oracle, and they ship
## together.
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
## ⚠️ THE SIXTH ARM IS THE ONE THAT IS NOT A COPY of `BattlefieldProvidesTest`'s. It diffs
## `PROVIDED_GLOBALS` against the addon's ACTUAL `global uniform` declarations, read off the
## `.gdshaderinc` files at runtime — so a seventh declaration added tomorrow with no provide
## fails here as well as in arm 4c, and so does an entry left behind by a deleted seam. That
## is ADR-0146's rule applied to this pair: two registers describe one set, so they are
## DIFFED rather than duplicated. It is also the arm a stranger project can run and the
## Python guard cannot — this is the only place in the repo where "a project that did
## nothing for this addon" is real (ADR-0194).
##
## Run: bash tests/stranger/exmateria_platform/run.sh   (ADR-0194 — addon-owned, runs in a
## STRANGER project. Directly: "$GODOT" --path . --quit-after 5
## res://addons/exmateria_platform/tests/PlatformProvidesTest.tscn)

var _passed: int = 0
var _failed: int = 0

## Every test function that RAN TO ITS LAST LINE. 🔴 NOT BOOKKEEPING: calling a nonexistent
## static on a `GDScript` pushes an error and returns null rather than halting, so a
## `plugin.gd` with no `provide_into` at all would leave most of the arms below doing
## nothing while the verdict block printed [PASS] off the two assertions that did run.
## `BattlefieldProvidesTest` shipped exactly that defect; the counter is its regression.
var _completed: Array[String] = []

## The six names this addon declares and provides. One list, read by three arms below, so a
## drift shows up as a diff rather than as three lists agreeing with each other by luck.
const WANT: Dictionary = {
	"pixel_aspect": ["float", 1.0],
	"psx_dither_enabled": ["bool", true],
	"psx_fx_stretch": ["float", 1.0],
	"psx_cursor_stretch": ["float", 1.0],
	"unit_stretch": ["float", 1.0],
	"psx_camera_angle": ["int", 0],
}


## A dictionary-backed stand-in for `ProjectSettings`, exposing the two methods
## `provide_into` uses and nothing else.
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
	_test_all_six_land_on_an_empty_project()
	_test_every_global_lands_with_its_type_and_default()
	_test_an_existing_name_is_never_overwritten()
	_test_revoke_removes_only_what_was_added()
	_test_provided_keys_matches_what_the_write_produces()
	_test_the_provide_covers_every_declaration_in_this_addon()

	print("\n=== PlatformProvidesTest: %d passed, %d failed, %d/7 arms reported ==="
		% [_passed, _failed, _completed.size()])
	if _passed == 0 and _failed == 0:
		print("[FAIL] PlatformProvidesTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _completed.size() != 7:
		print("[FAIL] PlatformProvidesTest: only %d of 7 arms ran to completion — %s"
			% [_completed.size(), str(_completed)])
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] PlatformProvidesTest")
		get_tree().quit(1)
	else:
		print("[PASS] PlatformProvidesTest")
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


## The whole point: on a project holding none of them, all six are written.
func _test_all_six_land_on_an_empty_project() -> void:
	var fake := FakeSettings.new()
	var added: Array[String] = _plugin().provide_into(fake)

	_assert_eq_int(added.size(), 6, "six names added to a bare project")
	_assert_eq_int(fake.store.size(), 6, "six settings present afterwards")
	for name in WANT:
		_assert(fake.store.has("shader_globals/" + name), "shader_globals/%s provided" % name)

	_completed.append("_test_all_six_land_on_an_empty_project")


## A global uniform's declaration is `{type, value}`, and a WRONG default is worse than a
## missing one.
##
## ⚠️ `pixel_aspect` is why this asserts values and not just names. `PSXDisplay`'s reader turns an
## absent name into `0.0`, and a `pixel_aspect` of 0 collapses every vertex's x — the screen goes
## blank with no error. Providing the name but defaulting it to 0 would be the same crash
## wearing a green register (ADR-0203 dec. 7).
func _test_every_global_lands_with_its_type_and_default() -> void:
	var fake := FakeSettings.new()
	_plugin().provide_into(fake)

	for name in WANT:
		var decl = fake.store.get("shader_globals/" + name)
		if typeof(decl) != TYPE_DICTIONARY:
			_fail("shader_globals/%s is a Dictionary" % name)
			continue
		_assert(decl.get("type", "") == WANT[name][0],
			"shader_globals/%s type is %s" % [name, WANT[name][0]])
		_assert(decl.get("value") == WANT[name][1],
			"shader_globals/%s default is %s" % [name, str(WANT[name][1])])

	_completed.append("_test_every_global_lands_with_its_type_and_default")


## A consumer that already declares a name keeps ITS value.
##
## The in-repo game declares all six itself and should keep doing so (ADR-0203 dec. 4). This
## is dec. 2's permitted read doing its job: the `has_setting` guard is part of the write.
func _test_an_existing_name_is_never_overwritten() -> void:
	var fake := FakeSettings.new()
	fake.set_setting("shader_globals/pixel_aspect", {"type": "float", "value": 2.5})

	var added: Array[String] = _plugin().provide_into(fake)

	_assert_eq_int(added.size(), 5, "the pre-declared name is not re-added")
	_assert(not ("shader_globals/pixel_aspect" in added), "pixel_aspect not reported as added")
	_assert(is_equal_approx(float(fake.store["shader_globals/pixel_aspect"]["value"]), 2.5),
		"the consumer's own pixel_aspect survives")

	_completed.append("_test_an_existing_name_is_never_overwritten")


## Disable removes what enable added, and NOTHING the consumer owned.
func _test_revoke_removes_only_what_was_added() -> void:
	var fake := FakeSettings.new()
	fake.set_setting("shader_globals/pixel_aspect", {"type": "float", "value": 2.5})
	fake.set_setting("application/config/name", "someone else's project")

	var added: Array[String] = _plugin().provide_into(fake)
	_plugin().revoke_from(fake, added)

	_assert(fake.store.has("shader_globals/pixel_aspect"),
		"a name the consumer declared SURVIVES disable")
	_assert(fake.store.has("application/config/name"), "an unrelated setting is untouched")
	_assert_eq_int(fake.store.size(), 2, "everything this plugin added is gone")

	_completed.append("_test_revoke_removes_only_what_was_added")


## `provided_keys()` is what the register arms read. If it drifted from what `provide_into`
## actually writes, the register would score a name the addon does not install, or miss one
## it does — the burn-down and the oracle disagreeing silently.
func _test_provided_keys_matches_what_the_write_produces() -> void:
	var fake := FakeSettings.new()
	var added: Array[String] = _plugin().provide_into(fake)
	var declared: Array[String] = _plugin().provided_keys()

	_assert_eq_int(declared.size(), 6, "provided_keys() names six settings")
	for key in declared:
		_assert(key in added, "%s is declared AND actually written" % key)
	for key in added:
		_assert(key in declared, "%s is written AND actually declared" % key)

	_completed.append("_test_provided_keys_matches_what_the_write_produces")


## 🔴 ADR-0220 dec. 1, ASSERTED AGAINST THE DECLARATIONS THEMSELVES rather than against a
## second hand-written list. The rule is *the addon that declares a `global uniform`
## provides it*, so the honest oracle reads the `global uniform` lines out of this addon's
## own `.gdshaderinc` files and diffs them against `provided_keys()` in BOTH directions:
##
##   * a declaration with no provide is the `unit_stretch` defect — created at #744,
##     provided by nothing, and invisible until the install register learned a second
##     subject at #746;
##   * a provide with no declaration is the same list going stale the other way, after a
##     seam is deleted.
##
## The `//` comments are stripped first, deliberately: `unit_stretch.gdshaderinc`'s own
## header discusses `global uniform` in prose, and `pixel_aspect.gdshaderinc` spells its
## `#include` usage inside a comment block. A raw scan reports both. This is the same trap
## `check_addon_portability.strip_shader_comments` exists for, and this file is the one
## place it has to be met in GDScript.
func _test_the_provide_covers_every_declaration_in_this_addon() -> void:
	var declared: Array[String] = []
	for path in _shader_seams(_addon_root()):
		for name in _global_uniform_names(FileAccess.get_file_as_string(path)):
			if not (name in declared):
				declared.append(name)

	_assert(declared.size() >= 6,
		"found %d global uniform declaration(s) under the addon — a scan that found none"
		% declared.size() + " would make every assertion below vacuous")

	var provided: Array[String] = _plugin().provided_keys()
	for name in declared:
		_assert("shader_globals/" + name in provided,
			"`%s` is DECLARED by this addon and must be in PROVIDED_GLOBALS (ADR-0220 dec. 1)"
			% name)
	for key in provided:
		var bare: String = key.substr("shader_globals/".length())
		_assert(bare in declared,
			"`%s` is in PROVIDED_GLOBALS but no `.gdshaderinc` in this addon declares it"
			% bare)

	_completed.append("_test_the_provide_covers_every_declaration_in_this_addon")


# --- helpers -----------------------------------------------------------------

func _plugin() -> GDScript:
	return load("res://addons/exmateria_platform/plugin.gd") as GDScript


## The addon's own directory, DERIVED from `plugin.gd`'s path rather than written as a
## second literal.
##
## ⚠️ `"res://addons/exmateria_platform"` — the root with no trailing slash — is what this
## used to say, and `check_addon_portability`'s arm 6 reds it: the arm's permitted set is
## the addon roots WITH their trailing separator, so a literal spelling a root bare reads
## as a path leaving every addon. Deriving it also means the scan follows the addon if it
## is ever renamed or relocated, which a literal would not.
func _addon_root() -> String:
	return _plugin().resource_path.get_base_dir()


## Every `.gdshader`/`.gdshaderinc` under `root`, recursively. `DirAccess` rather than a
## hardcoded list so a seam added tomorrow is scanned without editing this file.
func _shader_seams(root: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path: String = root + "/" + entry
		if dir.current_is_dir():
			out.append_array(_shader_seams(path))
		elif entry.ends_with(".gdshader") or entry.ends_with(".gdshaderinc"):
			out.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return out


## The `global uniform <type> <name>` names in shader source, with `//` and `/* */` blanked
## first. See this arm's docstring for why the stripping is not optional.
func _global_uniform_names(text: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.create_from_string(r"\bglobal\s+uniform\s+\w+\s+(\w+)")
	for line in _strip_shader_comments(text).split("\n"):
		var m := re.search(line)
		if m != null:
			out.append(m.get_string(1))
	return out


## Shader source with `//` and `/* */` comment bodies blanked, LINE COUNT PRESERVED.
func _strip_shader_comments(text: String) -> String:
	var out := ""
	var i: int = 0
	var n: int = text.length()
	var block: bool = false
	while i < n:
		var ch: String = text[i]
		if block:
			if ch == "*" and i + 1 < n and text[i + 1] == "/":
				block = false
				i += 2
				continue
			out += "\n" if ch == "\n" else " "
			i += 1
		elif ch == "/" and i + 1 < n and text[i + 1] == "*":
			block = true
			i += 2
		elif ch == "/" and i + 1 < n and text[i + 1] == "/":
			while i < n and text[i] != "\n":
				out += " "
				i += 1
		else:
			out += ch
			i += 1
	return out


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
