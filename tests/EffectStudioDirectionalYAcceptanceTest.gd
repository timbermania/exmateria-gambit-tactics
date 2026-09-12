extends Node
## ADR-0089 amendment "directional Y authors game-up" ACCEPTANCE (headful, real
## E019). Boots the real EffectViewer, parks E019 in the Studio, seeds a known
## negative `position_start_y` raw (PSX -Y = up) through the real edit choke, and
## then drives the LIVE Position "at start" Y cell to prove the chirality contract
## end-to-end on a real effect:
##   * the cell AUTHORS GAME-UP — a negative stored raw shows a positive tile value
##     (author-sees == author-uses, agreeing in sign with the sim cache the runtime
##     renders, `EffectEmitter.position_start.y`);
##   * dialing the cell UP moves the particle UP on screen (the sim cache Y rises)
##     while the stored byte moves the OPPOSITE way (grows more negative).
## Saves a real-window screenshot for the human review pass (field dumps don't count):
##   /tmp/e019_directional_y_position_cell.png
##
## Run: <GODOT> --path . --quit-after 400 res://tests/EffectStudioDirectionalYAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const EFFECT_ID := 19
const EmitterChannel = preload("res://src/effects/studio/EmitterChannel.gd")

# A known negative seed (PSX -Y up): raw -56 authors game-up as +2 tiles.
const SEED_RAW := -56

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_directional_y_cell_authors_game_up_on_real_e019()

	print("\n=== EffectStudioDirectionalYAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioDirectionalYAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioDirectionalYAcceptanceTest")
		get_tree().quit(0)


func _test_directional_y_cell_authors_game_up_on_real_e019() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E019")):
		print("[SKIP] E019 assets not available — acceptance skipped")
		_passed += 1
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)

	var page = scn._studio_page
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E%03d" % EFFECT_ID):
			dir = d
	_assert_true(dir != "", "E%03d is in the effect catalogue" % EFFECT_ID)
	page._load_effect(dir)
	await _frames(30)

	var insp = page._inspector
	var data = page._effect_data
	_assert_true(data != null and not data.emitters.is_empty(), "E019 loads with emitters")
	if data == null or data.emitters.is_empty():
		return

	# Pick the first particle span and its shared emitter.
	var span := _first_particle_span(page._timeline._score, data)
	_assert_true(not span.is_empty(), "E019 offers a particle span")
	if span.is_empty():
		return
	var ei := int(span.get("emitter_index", 0))
	var em = data.emitters[ei]
	var ref := {"channel": "emitter", "emitter_index": ei, "field": "position_start_y"}

	# Seed a known NEGATIVE raw (PSX -Y = up) through the real edit choke, then
	# re-select the span so the inspector re-projects fresh from that raw.
	page._on_span_selected(str(span.get("id", "")))
	await _frames(4)
	page._apply_edit(ref, SEED_RAW)
	await _frames(6)
	page._on_span_selected(str(span.get("id", "")))
	await _frames(6)

	_assert_eq(EmitterChannel.read_raw(em, "position_start_y"), SEED_RAW,
		"the negative raw is stored verbatim")

	# The LIVE Position "at start" Y cell — the 2nd ScrubField under the Position fold
	# (at-start X, at-start Y, at-start Z, at-end X/Y/Z). Expand the fold for the shot.
	var pos_fold := _fold(insp, "position")
	_assert_true(not pos_fold.is_empty(), "the Position group hangs a fold")
	if pos_fold.is_empty():
		return
	pos_fold["header"].button_pressed = true
	await _frames(4)

	# The at-start X/Y/Z cells always render (the "at end" rows are dropped when the
	# group has no curve — an inert end); at-start Y is the 2nd field.
	var pos_fields := _fields_under(insp, pos_fold["body"])
	_assert_true(pos_fields.size() >= 3, "the Position fold hosts its at-start X/Y/Z cells")
	if pos_fields.size() < 3:
		return
	var y_sb = pos_fields[1]

	# GAME-UP: the negative stored raw authors as a POSITIVE tile value (+2), the same
	# sign the sim caches (EffectEmitter.position_start.y, Godot +Y = up).
	_assert_true(abs(y_sb.value - 2.0) < 0.01, "raw -56 authors as +2 tiles (game-up)")
	_assert_true(em.position_start.y > 0.0,
		"the sim cache Y is positive (up) — author-sees == author-uses")
	insp.get_child(0).ensure_control_visible(pos_fold["body"])
	await _frames(2)
	_shot(insp, "/tmp/e019_directional_y_position_cell.png")

	# DIAL UP: raise the cell to +3 tiles. The particle rises (cache Y grows) and the
	# stored byte moves the OPPOSITE way (grows more negative).
	var raw_before := EmitterChannel.read_raw(em, "position_start_y")
	var cache_before: float = em.position_start.y
	y_sb.value = 3.0
	await _frames(8)
	var raw_after := EmitterChannel.read_raw(em, "position_start_y")
	var cache_after: float = em.position_start.y
	_assert_true(cache_after > cache_before,
		"dialing +Y moves the particle UP on screen (cache %.3f → %.3f)" % [cache_before, cache_after])
	_assert_true(raw_after < raw_before,
		"…while the stored byte moves the OPPOSITE way (raw %d → %d)" % [raw_before, raw_after])
	_assert_eq(raw_after, -84, "+3 tiles up commits raw -84 (the opposite sign)")


## The first particle-lane span whose emitter index is valid, else {}.
func _first_particle_span(score: Dictionary, data) -> Dictionary:
	for lane in score.get("lanes", []):
		if lane.get("kind", "") != "particle":
			continue
		for span in lane.get("spans", []):
			var ei := int(span.get("emitter_index", -1))
			if ei >= 0 and ei < data.emitters.size():
				return span
	return {}


## The inspector fold for group `key` (fold keys are "<emitter_index>:<group id>"), or {}.
func _fold(insp, key: String) -> Dictionary:
	for f in insp.param_folds():
		if str(f.get("key", "")).ends_with(":" + key):
			return f
	return {}


## The live int ScrubFields nested under `body`, in creation order.
func _fields_under(insp, body: Control) -> Array:
	var out: Array = []
	for sb in insp.int_widgets():
		if body.is_ancestor_of(sb):
			out.append(sb)
	return out


## Capture the WINDOW that hosts `ctrl` — the Studio lives in the DebugDashboard,
## a separate OS Window (its own viewport), not the main game viewport.
func _shot(ctrl: Control, path: String) -> void:
	var img := ctrl.get_window().get_texture().get_image()
	img.save_png(path)
	print("[SHOT] %s" % path)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


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
