extends Node
## Guard for extraction #3 loop pass 6 — every `Battlefield` file is AT ITS NEW ADDRESS,
## and the two scenes that moved still BIND THEIR SCRIPTS.
##
## `docs/EXTRACTION-3-MOVE-MANIFEST.tsv` is the register (ADR-0168) and
## `tools/check_move_manifest.py` already asserts set equality against it statically. This
## test exists for the half a static check cannot reach, which is the one ADR-0157 ->
## *Soft spots*, Spike A measured headful on the 4.8 fork:
##
##     a `.tscn` whose script `ext_resource` points at a moved path still LOADS. Godot
##     prints a parse error to stderr, mounts the node STRIPPED OF ITS SCRIPT, and the
##     failure surfaces at whatever line first touches a property.
##
## The engine exits 0 through that, so `rc` does not report it and neither does watching the
## scene come up. **Assert, never observe** — phase 2 instantiates each moved scene and reads
## `get_script()` back off the nodes.
##
## Phases, so no arm is vacuous:
##   1. Every manifest row is at `dst` and NOT at `src`. A copy passes arm 3 of the static
##      guard's set-equality on the dst side alone; this says the host copy is gone too.
##   2. Each moved `.tscn` instantiates, and for every `ext_resource type="Script"` the scene
##      file declares, some node in the instantiated tree carries a script loaded from that
##      exact `resource_path`. Reading the path back off the live node is what distinguishes
##      "the scene came up" from "the script is bound".
##   3. Every `.gd` row `load()`s to a non-null GDScript. `preload` would be a compile-time
##      failure of THIS file; a runtime `load()` is how the tunable owners and the three
##      `UI` menus reach these files, and it returns null in silence.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/BattlefieldAddonAddressTest.tscn

const MANIFEST := "res://docs/EXTRACTION-3-MOVE-MANIFEST.tsv"
const ADDON_ROOT := "res://addons/exmateria_battlefield/"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var rows := _load_manifest()

	# Anti-vacuity, and it is COMPUTED rather than pinned. Phases 1-3 are all
	# `for r in rows`, so a truncated or unreadable manifest passes every one of them
	# in silence — that is the job this assertion does and it is a real job.
	#
	# 🔴 IT USED TO READ `rows.size() == 46`, AND A CORRECT MOVE TURNED IT RED. #642
	# moved `TileOverlayColor.gd` into the addon and declared the 47th row, which is
	# exactly what `check_move_manifest.py` arm 3 exists to REQUIRE — and this test
	# failed for it. A frozen count is a second, weaker spelling of set equality that
	# goes red on the work the register was written to make visible, and this file's own
	# docstring says the static guard already owns that comparison.
	#
	# So count the addon instead. This can never go stale, and it still catches the
	# truncation the magic number was there for.
	var on_disk := _addon_source_files()

	# 🔴 A ROW CAN BE RULED BACK, AND THAT IS NOT A DROP — the third disposition
	# (ADR-0209 dec. 4). `check_move_manifest.py` gained `returned` beside `move`/`new`
	# when `cursor_clut_preview.gdshader` was priced and sent back to the host: it had
	# ONE consumer tree-wide, zero addon users, and had entered `source=census` — by
	# DIRECTORY, in ADR-0184's bulk pass.
	#
	# THIS FILE IS A SECOND IMPLEMENTATION OF THAT SAME QUERY. It re-derives the
	# register's arms in GDScript so they are checked by a running engine's own
	# `FileAccess` and `load()` rather than by a path string the static guard never
	# opens. That redundancy is the point — and it is also the trap: teaching the
	# Python guard about `returned` and not this one left the static register GREEN and
	# this test RED on the same, correct, tree. A register with a second spelling has
	# two things to teach, always.
	#
	# A `returned` row is asserted in the OPPOSITE direction below, never skipped. A
	# skip would let a row claim a disposition to escape being checked at all.
	var moved := rows.filter(func(r): return str(r.get("disposition", "")) != "returned")
	var returned := rows.filter(func(r): return str(r.get("disposition", "")) == "returned")

	_assert_true(moved.size() == on_disk,
		"manifest rows that STAYED moved equal the addon's source files (moved %d of %d rows, on disk %d)"
			% [moved.size(), rows.size(), on_disk])
	_assert_true(rows.size() > 0, "manifest is not empty (phases below iterate it)")
	_assert_true(moved.size() > 0, "manifest holds at least one row that stayed moved")

	# Phase 1 — at dst, and gone from src.
	for r in moved:
		_assert_true(FileAccess.file_exists(r["dst"]),
			"row is at its new address: %s" % r["dst"])
		_assert_true(not FileAccess.file_exists(r["src"]),
			"row left the host: %s" % r["src"])

	# Phase 1b — the ruled-back rows, asserted the other way round. Both arms, because
	# "it is not at its dst" alone is equally true of a file that was deleted.
	for r in returned:
		_assert_true(FileAccess.file_exists(r["src"]),
			"returned row is back at its host address: %s" % r["src"])
		_assert_true(not FileAccess.file_exists(r["dst"]),
			"returned row is gone from the addon: %s" % r["dst"])

	# Phase 2 — the scenes bind their scripts.
	var scenes := moved.filter(func(r): return r["kind"] == "scene")
	_assert_true(scenes.size() == 2, "manifest holds 2 scene rows (read %d)" % scenes.size())
	for r in scenes:
		_assert_scene_scripts_bound(r["dst"])

	# Phase 3 — the scripts resolve through a runtime load(), the way their callers reach them.
	for r in moved:
		if r["kind"] != "script":
			continue
		var s := load(r["dst"]) as GDScript
		_assert_true(s != null, "load() resolves: %s" % r["dst"])

	print("\n=== BattlefieldAddonAddressTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] BattlefieldAddonAddressTest")
		get_tree().quit(1)
	else:
		print("[PASS] BattlefieldAddonAddressTest")
		get_tree().quit(0)


## Instantiate `scene_path` and require every script the SCENE FILE declares to be live on a
## node. The scene file is the independent source of truth here — the expectation is read out
## of the `.tscn` text, never recomputed from the tree the tree itself produced.
func _assert_scene_scripts_bound(scene_path: String) -> void:
	var packed := load(scene_path) as PackedScene
	_assert_true(packed != null, "scene loads: %s" % scene_path)
	if packed == null:
		return

	var declared := _declared_script_paths(scene_path)
	_assert_true(not declared.is_empty(),
		"%s declares at least one Script ext_resource" % scene_path)

	var root := packed.instantiate()
	_assert_true(root != null, "scene instantiates: %s" % scene_path)
	if root == null:
		return
	var bound := _bound_script_paths(root)
	root.free()

	for want in declared:
		_assert_true(want in bound,
			"%s: script is BOUND, not stripped — %s (live: %s)"
				% [scene_path, want, ", ".join(bound)])


## Every `res://…` a `[ext_resource type="Script"]` line of the scene FILE names.
func _declared_script_paths(scene_path: String) -> Array[String]:
	var out: Array[String] = []
	var f := FileAccess.open(scene_path, FileAccess.READ)
	if f == null:
		return out
	var re := RegEx.create_from_string('path="(res://[^"]+)"')
	while not f.eof_reached():
		var line := f.get_line()
		if not line.begins_with("[ext_resource") or not line.contains('type="Script"'):
			continue
		var m := re.search(line)
		if m != null:
			out.append(m.get_string(1))
	f.close()
	return out


## Every `resource_path` a live node's script reports, read off the instantiated tree.
func _bound_script_paths(node: Node) -> Array[String]:
	var out: Array[String] = []
	var s: Script = node.get_script()
	if s != null and s.resource_path != "":
		out.append(s.resource_path)
	for child in node.get_children():
		for p in _bound_script_paths(child):
			if p not in out:
				out.append(p)
	return out


## The addon's own source files, counted the way `check_move_manifest.py` arm 3 counts
## them: `.gd` plus the four shader suffixes plus `.tscn`, less `plugin.gd`, which is
## #561 dec. 5's scaffolding and not a manifest row. Recomputed here rather than imported
## because this test runs in the ENGINE, which is the half the static guard cannot reach.
func _addon_source_files(dir_path: String = ADDON_ROOT) -> int:
	const SUFFIXES := ["gd", "gdshader", "gdshaderinc", "glsl", "glslinc", "tscn"]
	var n := 0
	var d := DirAccess.open(dir_path)
	if d == null:
		return 0
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			# `addons/<name>/tests/` IS NOT ON THE MANIFEST, and must not be counted
			# against it. The manifest describes ONE act — source moving out of the
			# host into the addon (extraction #3). An addon-owned test arrives by a
			# different act with its own ledger, `docs/TEST-BASELINE-E2.tsv`'s
			# `# moved` rows (ADR-0194 dec. 2/10). `check_move_manifest.py` arm 3
			# already excludes it (`"tests" not in q.parts[2:3]`); this arm did not,
			# and read 59 against the manifest's 49 the first time the two lines met
			# — 5 tests, `.gd` + `.tscn` each. Two spellings of one set equality is
			# how they drift, which is the same lesson ADR-0194 dec. 9 records.
			if full == ADDON_ROOT + "tests":
				name = d.get_next()
				continue
			n += _addon_source_files(full)
		elif name.get_extension() in SUFFIXES and full != ADDON_ROOT + "plugin.gd":
			n += 1
		name = d.get_next()
	d.list_dir_end()
	return n


func _load_manifest() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		print("[FAIL] manifest unreadable at %s" % MANIFEST)
		_failed += 1
		return out
	var header := f.get_line().split("\t")
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() == "":
			continue
		var cells := line.split("\t")
		var row := {}
		for i in header.size():
			row[header[i]] = cells[i] if i < cells.size() else ""
		row["src"] = "res://" + str(row["src"])
		row["dst"] = "res://" + str(row["dst"])
		out.append(row)
	f.close()
	return out


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
