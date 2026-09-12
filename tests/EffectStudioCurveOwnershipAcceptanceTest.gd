extends Node
## ACCEPTANCE (headful, real E009 through the REAL page → host → EffectEditSession) for the
## ADR-0089 curve-ownership amendment. The unit guards prove the explode, the shape set, the
## channels and the picker in isolation; this proves the WIRING — that a stroke painted in
## the Studio on a real ROM effect lands, moves nothing else, and undoes.
##
## E009 is the corpus's worst sharer: curve slot 0 carries 30 referrers (every colour channel
## of 10 emitters). Before the explode, painting any one of them restyled 29 emitters the
## author was not looking at. That is the fault this whole amendment exists to fix, so it is
## the effect the acceptance runs on.
##
## The Studio page lives in DebugDashboard, a separate OS-level Window (ADR-0069/0035), and a
## HIDDEN Window does not lay out — so this calls `DebugOverlay.show_overlay()` and waits
## before touching anything with a size.
##
## Run: <GODOT> --path . --quit-after 400 res://tests/EffectStudioCurveOwnershipAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const EFFECT_ID := 9
const CurveShapeSet = preload("res://src/effects/studio/CurveShapeSet.gd")
const CurveChannel = preload("res://src/effects/studio/CurveChannel.gd")
const CurveExplode = ExMateriaEffects.CurveExplode
const CurveGenerators = preload("res://src/effects/studio/CurveGenerators.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const SHOT := "user://curve_ownership_painter.png"
const SHOT_PICKER := "user://curve_ownership_picker.png"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_a_painted_stroke_lands_privately_and_undoes()

	print("\n=== EffectStudioCurveOwnershipAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioCurveOwnershipAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioCurveOwnershipAcceptanceTest")
		get_tree().quit(0)


func _test_a_painted_stroke_lands_privately_and_undoes() -> void:
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	DebugOverlay.show_overlay()
	await _frames(20)
	scn.studio_select_effect(EFFECT_ID)
	await _frames(30)

	var page = scn._studio_page
	_assert_true(page != null, "the Studio page is mounted")
	if page == null:
		return
	# The host spawns the effect for the SIM; the page picks its own through the effect
	# dropdown, and it opens on whatever it defaulted to. Point it at E009 as well — the two
	# converge on ONE EffectData because load_from_directory caches by path, which is exactly
	# what makes an edit through the page land in the live instance the host is folding.
	page._load_effect("res://assets/effects/E%03d" % EFFECT_ID)
	await _frames(20)
	var data = page._effect_data
	_assert_true(data != null, "E009 is loaded")
	if data == null:
		return

	# (1) The explode reached the LIVE studio data, not just a test fixture.
	var sites: Array = CurveExplode.use_sites(data)
	var owned: Array = []
	for s in sites:
		if int(s["index"]) >= 0:
			owned.append(s)
	_assert_true(owned.size() >= 30, "E009 presents 30+ use sites (got %d)" % owned.size())
	var seen := {}
	var shared := 0
	for s in owned:
		if seen.has(int(s["index"])):
			shared += 1
		seen[int(s["index"])] = true
	_assert_eq(shared, 0, "no two use sites share a curve in the live studio model")

	# (2) The gauge counts SHAPES, not curves, and says so on the painter panel.
	var target: Dictionary = owned[0]
	var idx: int = int(target["index"])
	page._open_param_curve(idx, "Color (R) · curve")
	await _frames(5)
	var shapes: int = CurveShapeSet.shapes(data).size()
	_assert_true(shapes < owned.size(),
		"distinct shapes (%d) < curves in use (%d) — the two are not the same count"
			% [shapes, owned.size()])
	_assert_true(page._painter_gauge != null and page._painter_gauge.visible,
		"the painter panel shows the shape gauge")
	if page._painter_gauge != null:
		_assert_eq(page._painter_gauge.text, "Shapes %d/15" % shapes,
			"the gauge reads the distinct-shape count against the ROM's 15 slots")
	_assert_true(not _has_label_containing(page._painter_panel, "Preview only"),
		"the Preview-only note is gone — the edit is real now")

	_screenshot(page, SHOT)

	# (2b) The PICKER: browse an emitter so its curve rows render, and open one picker's
	# popup grid. The tile count IS the gauge — the grid is fed the distinct SHAPE set, so
	# it shows `none` + one tile per shape, not one tile per curve.
	page._painter_panel.visible = false
	page._navigate_to(Target.emitter(int(target["emitter_index"])))
	await _frames(20)
	var pickers: Array = page._inspector.curve_pick_widgets()
	_assert_true(pickers.size() >= 3, "the emitter view renders curve pickers (%d)" % pickers.size())
	if not pickers.is_empty():
		var grid: Array = pickers[0].thumbnails()
		_assert_eq(grid.size(), shapes + 1,
			"the popup grid is `none` + one tile per distinct SHAPE, not per curve")
		# Expand the param groups — the curve rows live inside them, and the emitter view
		# opens folded.
		for pair in page._inspector.fold_bulk_buttons():
			if pair.has("expand") and is_instance_valid(pair["expand"]):
				pair["expand"].emit_signal("pressed")
		await _frames(15)
		pickers = page._inspector.curve_pick_widgets()
		# Scroll the curve row into view before the shot — the emitter view opens on its
		# provenance header, and the curve rows sit below the fold. (The popup GRID itself is
		# a PopupPanel, i.e. its own OS window, so a viewport capture cannot show it; the
		# tile-count assertion above is what pins it.)
		_scroll_to(pickers[0])
		await _frames(10)
		_screenshot(page, SHOT_PICKER)
	page._navigate_to(Target.emitter(int(target["emitter_index"])))
	await _frames(10)

	# (3) A stroke through the REAL painter signal → page → host → EffectEditSession.
	var before := {}
	for s in owned:
		var c = data.get_curve(int(s["index"]))
		before[str(s["emitter_index"]) + "." + str(s["slot"])] = CurveChannel.to_grid(c)
	var stroke: Array = CurveGenerators.linear(0, 159, 0, 255)
	page._painter.curve_changed.emit(stroke)
	await _frames(10)

	_assert_eq(str(CurveChannel.to_grid(data.get_curve(idx))), str(stroke),
		"the painted stroke landed on the use site's own curve")
	var moved: Array = []
	for s in owned:
		if int(s["index"]) == idx:
			continue
		var key := str(s["emitter_index"]) + "." + str(s["slot"])
		if str(CurveChannel.to_grid(data.get_curve(int(s["index"])))) != str(before[key]):
			moved.append(key)
	_assert_eq(moved.size(), 0,
		"…and moved NO other use site (before the explode this moved 29) — %s"
			% str(moved.slice(0, 4)))

	# (4) One stroke is one undo, through the host's own undo path.
	_assert_true(scn.has_method("studio_undo"), "the host exposes undo")
	if scn.has_method("studio_undo"):
		scn.studio_undo()
		await _frames(10)
		_assert_eq(str(CurveChannel.to_grid(data.get_curve(idx))),
			str(before[str(target["emitter_index"]) + "." + str(target["slot"])]),
			"undo puts the painted curve back exactly")

	scn.queue_free()


# --- helpers ---------------------------------------------------------------

## The dashboard window's framebuffer — NOT the game's viewport (the Studio page lives in a
## separate OS Window), so this is what the author actually sees.
func _screenshot(page, path: String) -> void:
	var vp = page.get_viewport()
	if vp == null:
		return
	var img = vp.get_texture().get_image()
	if img != null:
		img.save_png(ProjectSettings.globalize_path(path))
		print("[shot] %s (%dx%d)" % [ProjectSettings.globalize_path(path),
			img.get_width(), img.get_height()])


## Scroll the inspector so `widget` is on screen — walk up to the enclosing ScrollContainer
## and put the widget's offset at the top.
func _scroll_to(widget: Control) -> void:
	var n: Node = widget
	while n != null and not (n is ScrollContainer):
		n = n.get_parent()
	if n == null:
		return
	var sc: ScrollContainer = n
	sc.scroll_vertical = int(widget.global_position.y - sc.global_position.y) + sc.scroll_vertical - 40


func _has_label_containing(node: Node, needle: String) -> bool:
	if node == null:
		return false
	if node is Label and needle in String((node as Label).text):
		return true
	for c in node.get_children():
		if _has_label_containing(c, needle):
			return true
	return false


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s" % msg)


func _assert_eq(got, want, msg: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s (got %s, want %s)" % [msg, str(got), str(want)])
