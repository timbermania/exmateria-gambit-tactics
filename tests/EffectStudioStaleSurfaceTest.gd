extends Node
## REGRESSION (headful, real E019 + E317): CLEARING THE SELECTION AND LOADING A NEW EFFECT
## BOTH PARK THE PER-TARGET SURFACES.
##
## Two paths clear `_nav` — Esc (`_deselect`) and `_load_effect` — and both relied on
## `_render_current()` to update the inspector row's canvases. It EARLY-RETURNS on an empty
## nav, which both functions had a comment celebrating as a saving. It was a gap.
##
## Measured before the fix, driving this exact sequence:
##   after Esc      — sequence player still visible, still bound to {anim_index: 1}
##   after E317     — STILL bound to E019's animation 1, and the Texture tab still held
##                    E019's sheet (instance …977776 against the loaded …091137)
## An author looking at E317 was looking at E019's art. That is the same class as the #280
## import staleness ("who cached this object"), except nothing re-bound at all.
##
## Run: godot --path . --quit-after 700 res://tests/EffectStudioStaleSurfaceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

var _passed: int = 0
var _failed: int = 0
var _completed: Dictionary = {}
const _EXPECTED_TESTS := ["esc_parks", "load_parks"]


func _done(n: String) -> void:
	_completed[n] = true


func _ready() -> void:
	await _run()
	for n in _EXPECTED_TESTS:
		if not _completed.has(n):
			_failed += 1
			print("  FAIL: test '%s' never reached its end" % n)
	print("\n=== EffectStudioStaleSurfaceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioStaleSurfaceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioStaleSurfaceTest")
		get_tree().quit(0)


func _run() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E019")):
		print("[SKIP] E019 assets not available")
		_passed += 1
		for n in _EXPECTED_TESTS:
			_done(n)
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page
	if page == null:
		return
	DebugOverlay.show_overlay()
	await _frames(40)

	var d19 := ""
	var d_other := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E019"):
			d19 = d
		elif d_other == "" and String(d).ends_with("E317"):
			d_other = d
	if d19 == "" or d_other == "":
		print("[SKIP] need both E019 and E317 in the catalogue")
		_passed += 1
		for n in _EXPECTED_TESTS:
			_done(n)
		return

	page._load_effect(d19)
	await _frames(50)
	var tex19 = page._effect_data.texture

	# --- Esc parks the player -----------------------------------------------------
	page._set_root(Target.emitter(0))
	await _frames(40)
	_assert_true(page._sequence_panel.visible,
		"precondition: an emitter target shows the sequence player")
	_assert_true(not page._sequence_bound.is_empty(),
		"precondition: …bound to a real address (%s)" % page._sequence_bound)

	page._deselect()
	await _frames(40)
	_assert_eq(page._nav.size(), 0, "Esc clears the inspection path")
	_assert_true(not page._sequence_panel.visible,
		"Esc parks the sequence player — it used to keep playing the deselected emitter")
	_assert_true(page._sequence_bound.is_empty(),
		"…and drops the address with it (%s)" % page._sequence_bound)
	_done("esc_parks")

	# --- a new effect re-binds every surface ---------------------------------------
	page._set_root(Target.emitter(0))
	await _frames(40)
	page._load_effect(d_other)
	await _frames(60)
	var tex_other = page._effect_data.texture
	_assert_true(tex_other != tex19,
		"precondition: the two effects really are different sheets")
	_assert_true(not page._sequence_panel.visible,
		"a new effect parks the previous effect's sequence player")
	_assert_true(page._sequence_bound.is_empty(),
		"…and its address (%s)" % page._sequence_bound)

	# THE ONE THAT BIT: the tab held the OLD sheet, so E317 showed E019's art.
	var tab_tex = page._texture_panel.canvas()._texture
	_assert_true(tab_tex == null or tab_tex == tex_other,
		"the Texture tab never shows the PREVIOUS effect's sheet")
	_assert_true(tab_tex != tex19,
		"…specifically, not E019's sheet while E317 is loaded")
	_done("load_parks")


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _assert_eq(a, b, m: String) -> void:
	if a == b:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected %s, got %s" % [m, str(b), str(a)])


func _assert_true(c: bool, m: String) -> void:
	if c:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected true" % m)
