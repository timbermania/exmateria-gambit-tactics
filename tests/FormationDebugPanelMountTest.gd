extends Node
## #1267 — the formation screen's three F3 panels are mounted from the HOST side, not by
## `FormationScene`.
##
## `FormationScene` used to construct and register `FormationDebugPanel`,
## `DetailScreenDebugPanel` and `VitalsLayoutDebugPanel` in its own `_setup_debug_panels()`,
## reaching `/root/DebugOverlay` by node path to do it. Those four reaches were the scene's
## entire scored Debug residue, and `FormationScene` is moving into `addons/exmateria_ui/`
## where none of them can ship (ADR-0304 dec. 2). `FormationDebugPanels.register_formation_panels()`
## owns the mount now. Same shape as `MapDebugPanels` (#555) and same three-arm skeleton —
## plus a fourth arm the map never needed.
##
## FOUR ARMS, because no three of them can report the event:
##   1. the mount lands all three panels under DESIGNER, pointed at the subject passed in;
##   2. a SECOND call does not stack duplicates AND re-points the two stateful panels at the
##      new subject. `register_panel` APPENDS (`DebugOverlay.gd:238`), and the formation
##      screen is re-entered every time the player leaves and returns, so without the guard
##      a session accumulates three fresh panels per visit. Re-pointing had to be `rebind()`
##      and not a second `setup()`: `setup()` ends in `_build_ui()`, which `add_child`s
##      another root onto a panel that already has one.
##   3. the member source names neither `DebugOverlay` nor any of the three panel classes in
##      code. Arms 1-2 pass just as well with the old registration still sitting in
##      `FormationScene` beside the new one, so only arm 3 reports the REMOVAL.
##   4. every production file that mounts a formation screen actually calls the installer.
##
## 🔴 ARM 4 IS THE LOAD-BEARING ONE, and it exists because hand-enumeration already failed
## here. `FormationMapHost extends FormationScene`, so the deleted `_setup_debug_panels()`
## ran from `_ready()` on every path that puts either class in the tree. The ticket named
## FOUR such paths and the author wired four; this arm, written before the commit, found
## SEVEN — `GPUArena`, `GambitLabScene` and `CombatUITestScene` mount the screen too and had
## silently lost all three panels. `DebugOverlay` has no discovery hook (no group, no
## `node_added`), so nothing at RUNTIME can notice a mount site that forgot to ask. Arm 4
## rediscovers the sites from source on every run; a list of known-good paths would have
## passed on the broken tree.
##
## 🔴 ARM 3's SUBJECT IS A DIRECTORY, SO IT MOVES. It reads `res://src/ui3/` today and must
## become `res://addons/exmateria_ui/` when extraction #8's move lands. `scanned > 0` is the
## only reason that will surface as a failure rather than as a silent pass over zero files —
## the ADR-0148 shape, and what `MapDebugPanelMountTest` learned the hard way in extraction #3.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/FormationDebugPanelMountTest.tscn

const MEMBER_DIR := "res://src/ui3/"
## Not an extraction-#8 member: it registers two panels of its OWN (`CombatUITestScene.gd:190`),
## which is precisely why it stays host-side. Excluded from arm 3, never from arm 4.
const MEMBER_DIR_EXCLUDE := "res://src/ui3/testing/"
const BANNED := ["DebugOverlay", "FormationDebugPanel", "DetailScreenDebugPanel",
	"VitalsLayoutDebugPanel"]

const SRC_DIR := "res://src/"
## A file naming any of these either mounts a formation screen or is exempt below.
const MOUNT_MARKS := ["FormationScene", "FormationMapHost", "FormationDetailTransition",
	"Formation.tscn", "AllTemplatesFormation.tscn", "FormationDev.tscn"]
## Discovered files that legitimately do NOT call the installer. Every entry must still be
## DISCOVERED (asserted below) — an exempt row for a file that no longer names a mark is a
## row that silently stops meaning anything.
const EXEMPT := {
	"res://src/debug/FormationDebugPanel.gd":
		"the panel itself; its only match is the string literal \"No FormationScene bound.\"",
	"res://src/ui3/detail/DetailSceneBoot.gd":
		"calls the STATIC FormationScene.vitals_view_from_character; instantiates no screen",
	"res://src/ui3/detail/StartActionMenuBoot.gd":
		"calls the STATIC FormationScene.vitals_view_from_character; instantiates no screen",
	"res://src/ui3/formation/FormationDetailTransition.gd":
		"the coordinator that BUILDS the screen — a member, so it may not name src/debug/; " +
		"each of its four hosts is itself a discovered site that calls the installer",
	"res://src/ui3/formation/FormationMapHost.gd": "declares the class (extends FormationScene)",
	"res://src/ui3/formation/FormationScene.gd": "declares the class",
}

var _passed := 0
var _failed := 0


## Stand-in for FormationScene. It declares exactly the properties `FormationDebugPanel`
## SEEDS its rows from — `_vec2` reads them as a typed `Vector2`, so a missing name is a hard
## error, not a blank row — plus the two-hop accessor the installer reads the vitals window
## through. Typed to `Node` on purpose: the installer takes a `Node` and must not need the
## member type to mount (ADR-0164 dec. 4).
class FakeFormationScene extends Node:
	var body_scale := 1.0
	var feet_target_px := Vector2(0, 0)
	var shadow_feet_offset_px := Vector2(0, 0)
	var shadow_size_px := Vector2(8, 4)
	var shadow_intensity := 0.5
	var box_center_px := Vector2(0, 0)
	var box_add_level := 0.5
	var box_sub_level := 0.5
	var box_emboss_dy := 1.0
	var floor_spot_base := 0.5
	var floor_spot_min := 0.1
	var floor_spot_swing := 1.0
	var floor_spot_vfac := 4.0
	var orb_falloff_scale := 1.0

	var cluster := FakeCluster.new()
	func unit_info_cluster() -> Node:
		return cluster


class FakeCluster extends Node:
	var window: UIUnitInfoWindow = UIUnitInfoWindow.new()
	func vitals_panel() -> UIUnitInfoWindow:
		return window


func _ready() -> void:
	_test_mount()
	_test_second_call_rebinds()
	_test_member_names_no_debug_symbols()
	_test_every_mount_site_calls_the_installer()

	print("\n=== FormationDebugPanelMountTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] FormationDebugPanelMountTest")
		get_tree().quit(1)
	else:
		print("[PASS] FormationDebugPanelMountTest")
		get_tree().quit(0)


# --- arm 1 -------------------------------------------------------------------

func _test_mount() -> void:
	for ident in ["FormationDebugPanel", "DetailScreenDebugPanel", "VitalsLayoutDebugPanel"]:
		_assert_eq(_panels_of(ident).size(), 0,
			"no %s is mounted before the host asks for one" % ident)

	var scene := FakeFormationScene.new()
	add_child(scene)
	FormationDebugPanels.register_formation_panels(scene)

	var formation := _panels_of("FormationDebugPanel")
	_assert_eq(formation.size(), 1, "the mount registers exactly one FormationDebugPanel")
	_assert_eq(_panels_of("DetailScreenDebugPanel").size(), 1,
		"the mount registers exactly one DetailScreenDebugPanel")
	var vitals := _panels_of("VitalsLayoutDebugPanel")
	_assert_eq(vitals.size(), 1, "the mount registers exactly one VitalsLayoutDebugPanel")

	if formation.is_empty() or vitals.is_empty():
		return
	_assert_true(formation[0]._scene == scene,
		"the Formation panel points at the scene the HOST passed in, not one it went looking for")
	_assert_true(vitals[0]._window == scene.cluster.window,
		"the Vitals panel points at the window reached through the scene's public accessors")
	_assert_true(formation[0].get_child_count() > 0,
		"the Formation panel built its rows (a null subject would have built a placeholder)")


# --- arm 2 -------------------------------------------------------------------

func _test_second_call_rebinds() -> void:
	var first_formation := _panels_of("FormationDebugPanel")
	var first_vitals := _panels_of("VitalsLayoutDebugPanel")
	if first_formation.is_empty() or first_vitals.is_empty():
		_fail("arm 2 needs arm 1's panels")
		return
	var rows_before: int = first_formation[0].get_child_count()

	var second := FakeFormationScene.new()
	add_child(second)
	FormationDebugPanels.register_formation_panels(second)

	_assert_eq(_panels_of("FormationDebugPanel").size(), 1,
		"a second mount does not stack a second FormationDebugPanel")
	_assert_eq(_panels_of("DetailScreenDebugPanel").size(), 1,
		"a second mount does not stack a second DetailScreenDebugPanel")
	_assert_eq(_panels_of("VitalsLayoutDebugPanel").size(), 1,
		"a second mount does not stack a second VitalsLayoutDebugPanel")

	var survivor: Node = _panels_of("FormationDebugPanel")[0]
	_assert_true(survivor == first_formation[0],
		"the surviving Formation panel is the SAME instance (its UI state is kept)")
	_assert_true(survivor._scene == second,
		"it was REBOUND to the new scene, not merely left standing")
	_assert_eq(survivor.get_child_count(), rows_before,
		"the rebind did not add a second UI root — the bug a repeat setup() would have caused")
	_assert_true(_panels_of("VitalsLayoutDebugPanel")[0]._window == second.cluster.window,
		"the surviving Vitals panel was rebound to the new scene's window")


# --- arm 3 -------------------------------------------------------------------

func _test_member_names_no_debug_symbols() -> void:
	# Positive control on the MATCHER, not on the subject: `FormationDebugPanels` — the
	# installer this pass added, named by two member-adjacent boot files — CONTAINS
	# `FormationDebugPanel`. A substring scan reports it as an offender, and the first draft
	# of this arm did exactly that. Whole-word matching is the thing being controlled.
	_assert_true(_names_in_code("FormationDebugPanels.register_formation_panels(form)",
			"FormationDebugPanel").is_empty(),
		"control: the matcher does NOT read `FormationDebugPanels` as `FormationDebugPanel`")
	_assert_false(_names_in_code("\tvar p := FormationDebugPanel.new()",
			"FormationDebugPanel").is_empty(),
		"control: the matcher DOES read a real `FormationDebugPanel` use")

	var offenders: Array[String] = []
	var scanned := 0
	for rel in _gd_files_under(MEMBER_DIR):
		if rel.begins_with(MEMBER_DIR_EXCLUDE):
			continue
		var text := FileAccess.get_file_as_string(rel)
		if text.is_empty():
			continue
		scanned += 1
		for sym in BANNED:
			for lineno in _names_in_code(text, sym):
				offenders.append("%s:%d names %s" % [rel, lineno, sym])
	_assert_true(scanned > 0, "arm 3 actually opened files under %s" % MEMBER_DIR)
	_assert_true(offenders.is_empty(),
		"no member under %s names a Debug symbol in code (%s)" % [MEMBER_DIR, ", ".join(offenders)])


# --- arm 4 -------------------------------------------------------------------

func _test_every_mount_site_calls_the_installer() -> void:
	var discovered: Array[String] = []
	var callers: Array[String] = []
	var missing: Array[String] = []
	for rel in _gd_files_under(SRC_DIR):
		if rel == "res://src/debug/FormationDebugPanels.gd":
			continue  # the installer itself
		var text := FileAccess.get_file_as_string(rel)
		if text.is_empty():
			continue
		var code := _strip_comments(text)
		var marked := false
		for mark in MOUNT_MARKS:
			if code.contains(mark):
				marked = true
				break
		if not marked:
			continue
		discovered.append(rel)
		if code.contains("register_formation_panels"):
			callers.append(rel)
		elif not EXEMPT.has(rel):
			missing.append(rel)

	_assert_true(discovered.size() > 0, "arm 4 actually discovered mount candidates under %s" % SRC_DIR)
	_assert_true(missing.is_empty(),
		"every discovered mount site calls register_formation_panels or is EXEMPT (missing: %s)"
			% ", ".join(missing))
	_assert_true(callers.size() >= 7,
		"the seven known mount sites still call the installer (found %d)" % callers.size())

	# A stale EXEMPT row is a row that stopped meaning anything: the file it names either
	# moved, was deleted, or no longer touches a formation screen at all. Either way the
	# exemption is now covering nothing, and a future mount site could take the same path
	# under its cover.
	var stale: Array[String] = []
	for rel in EXEMPT.keys():
		if not discovered.has(rel):
			stale.append(rel)
	_assert_true(stale.is_empty(),
		"every EXEMPT entry names a file arm 4 still discovers (stale: %s)" % ", ".join(stale))


# --- helpers -----------------------------------------------------------------

## Line numbers (1-based) where `sym` appears as a WHOLE WORD in `text`, comments stripped.
func _names_in_code(text: String, sym: String) -> Array[int]:
	var out: Array[int] = []
	var re := RegEx.create_from_string("\\b" + sym + "\\b")
	var lineno := 0
	for line in _strip_comments(text).split("\n"):
		lineno += 1
		if re.search(line) != null:
			out.append(lineno)
	return out


## Blank out `#` comments (docstrings included) so a line of PROSE about the inversion cannot
## fail the rule it describes — every file changed by #1267 explains itself by naming the
## symbols it no longer uses. Naive by design: a `#` inside a string literal truncates the
## line, which can only ever HIDE text from the scan, never invent an offender.
func _strip_comments(text: String) -> String:
	var out := PackedStringArray()
	for line in text.split("\n"):
		var hash_at := line.find("#")
		out.append(line if hash_at < 0 else line.substr(0, hash_at))
	return "\n".join(out)


func _gd_files_under(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			out.append_array(_gd_files_under(full))
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out


func _panels_of(class_ident: String) -> Array:
	var out: Array = []
	for panel in DebugOverlay._panels.get(DebugOverlay.Category.DESIGNER, []):
		if is_instance_valid(panel) and panel.get_script() != null \
				and panel.get_script().get_global_name() == class_ident:
			out.append(panel)
	return out


func _assert_eq(actual: int, expected: int, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %d, want %d)" % [label, actual, expected])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)


func _assert_false(cond: bool, label: String) -> void:
	_assert_true(not cond, label)


func _fail(label: String) -> void:
	_failed += 1
	print("[FAIL] %s" % label)
