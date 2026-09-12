extends Node
# test-kind: logic
# seeded-break: _body_mat_template() rebuilds the template on every call (if true instead of if _body_material_template == null) — the pre-scroll-hitch-fix per-cell re-load of unit.tres; the 'template is REUSED across a rebuild (not re-loaded per scroll)' assert reds (a fresh template object replaces tmpl_first), the template-exists / cell-material-is-a-distinct-duplicate / duplicate-carries-the-shader, and all three cache invariants (cache populated / re-show adds zero entries / cell bound to the CACHED texture object) stay green

## TDD guard for the formation SCROLL-PERF caching (follow-up to ADR-0081).
##
## The all-templates view rebuilds all 8 cells from scratch on every scroll step
## (`rebuild_cells`). The dominant cost WAS `load(_UNIT_MATERIAL)` per cell — unit.tres
## drags its ext_resources (unit.gdshader + the 256×488 WEP1/EFF1 TGAs) off disk, and
## nothing held the base alive between rebuilds, so each scroll re-read it ~24 ms × 8.
## The fix caches (a) a body-material TEMPLATE built once and duplicated per cell, and
## (b) the per-folder body sheet + palette Texture2D objects, so a scroll re-show is a
## map hit not a forced disk re-decode. This guard pins both invariants AS STATE:
##
##   1. The material template is built ONCE — the same object survives across rebuilds
##      (a per-cell reload would replace it every scroll).
##   2. Returning to an already-shown scroll offset adds ZERO new body-texture cache
##      entries — i.e. every sheet in that window was already resident (no disk re-hit).
##
## Render is unchanged: the per-cell material is still a `.duplicate()` of the template
## and the bound texture IS the cached object, so pixels are byte-identical (see /verify).
##
## Run: <GODOT> --path . --quit-after 8 res://tests/FormationScrollCacheTest.tscn

const FormationSceneClass = preload("res://src/ui3/formation/FormationScene.gd")
const AllTemplatesSeeder = ExMateriaCatalogue.AllTemplatesSeeder

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	await _run()
	print("\n=== FormationScrollCacheTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] FormationScrollCacheTest")
		get_tree().quit(1)
	else:
		print("[PASS] FormationScrollCacheTest")
		get_tree().quit(0)


func _run() -> void:
	CharacterCatalog.reset_to_new_game()
	AllTemplatesSeeder.seed()
	var owned: Array = CharacterCatalog.owned_units()
	_assert_true(owned.size() > FormationSceneClass.ROWS * FormationSceneClass.COLS,
		"seeded roster overflows the grid so scrolling is real (%d units)" % owned.size())

	var form: FormationSceneClass = FormationSceneClass.new()
	form.name = "Formation"
	form.set_owned_characters(owned)
	add_child(form)
	await get_tree().process_frame
	await get_tree().process_frame

	# (1) Template built once and REUSED across rebuilds — a per-cell reload of unit.tres
	# would mint a fresh template every rebuild.
	var tmpl_first = form._body_material_template
	_assert_true(tmpl_first != null, "body-material template is built after the first mount")
	form.rebuild_cells()
	_assert_true(form._body_material_template == tmpl_first,
		"template is REUSED across a rebuild (not re-loaded per scroll)")

	# The per-cell material must still be a DISTINCT duplicate of the template (independent
	# per-unit params), never the shared template itself.
	var a_cell_mat = form._body_mats_by_cell.values()[0]
	_assert_true(a_cell_mat != tmpl_first, "a cell's material is a duplicate, not the shared template")
	_assert_true(a_cell_mat.shader == tmpl_first.shader, "the duplicate carries the template's shader")

	# (2) Returning to an already-shown offset adds ZERO new body-texture cache entries.
	form.scroll_offset = 0
	form.rebuild_cells()
	var size_at_0 := (form._body_tex_cache as Dictionary).size()
	_assert_true(size_at_0 > 0, "body-texture cache populated after showing offset 0 (%d)" % size_at_0)

	# Scroll away (warm new sheets), then return to offset 0.
	form.scroll_offset = 1
	form.rebuild_cells()
	form.scroll_offset = 0
	var before_return := (form._body_tex_cache as Dictionary).size()
	form.rebuild_cells()
	var after_return := (form._body_tex_cache as Dictionary).size()
	_assert_eq(after_return, before_return,
		"re-showing offset 0 is a pure cache hit — no new texture entries (disk not re-hit)")

	# The bound body texture on a re-shown cell IS the cached object (byte-identical render).
	var render: Dictionary = FormationSceneClass.resolve_body_render(owned[0])
	var key: String = render.template_folder if not render.template_folder.is_empty() else render.flat_texture_path
	_assert_true((form._body_tex_cache as Dictionary).has(key),
		"offset-0 unit's sheet is resident in the cache")
	var cached_pair: Array = form._body_tex_cache[key]
	var bound = form._body_mats_by_cell[Vector2i(0, 0)].get_shader_parameter("type1_tex")
	_assert_true(bound == cached_pair[0], "cell (0,0) is bound to the CACHED body texture object")

	form.queue_free()


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
