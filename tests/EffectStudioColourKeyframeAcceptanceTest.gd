extends Node
## Slice 6 — ACCEPTANCE (headful, real E019): authoring a colour actually repaints the live burst
## end-to-end (ADR-0089 colour-keyframe amendment). Drives the REAL studio: picker → page → host
## studio_author_colour → compile → renderer cache refresh + refold. Proves the pick lands as the
## rendered colour, not just in a green unit test.
##
## THE TARGET IS AN ASYMMETRIC, OUT-OF-BOX COLOUR (decision 4, amended 2026-08-21). It used to be
## the box CENTRE `S ⊙ 0.5`, and the assertion was that the renderer's modulate came back at ~0.5
## after the inverse mux — a round trip through a projection that is gone. The pick IS the curve
## now, so `(0.95, 0.6, 0.15)` is picked and `(0.95, 0.6, 0.15)` is what the renderer paints, for
## any sprite; 0.95 is outside the old reachable box in almost every channel (97.5% of corpus
## colour emitters had none that could hold 255), so this is the author's ask driven through the
## whole pipeline. What the sprite makes of it is asserted separately, against the picker's
## renders-as swatch — the bound, reported.
## Also confirms studio_save writes the game-JSON half (curves.json + emitters.json).
##
## Skips when E019 assets are absent (gitignored/ROM-derived).
## Run: godot --path . --quit-after 400 res://tests/EffectStudioColourKeyframeAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const ParticleClass = preload("res://addons/exmateria_effects/particles/Particle.gd")
const EmitterSpriteColor = preload("res://src/effects/studio/EmitterSpriteColor.gd")
const ColourKeyframeTrack = preload("res://src/effects/studio/ColourKeyframeTrack.gd")
const ColourLifeColumn = preload("res://src/effects/studio/ColourLifeColumn.gd")
const SequenceThumbnail = preload("res://src/effects/studio/SequenceThumbnail.gd")

var _passed: int = 0
var _failed: int = 0


## DID `_run` REACH ITS END? A GDScript coroutine that hits a runtime error aborts SILENTLY,
## taking every remaining assertion with it — and this suite then printed `[PASS] 2 passed,
## 0 failed`, which is how the vertical-column build got a green light from a file that had
## stopped running at its ninth line. Sibling suites already carried this; this one did not.
var _completed: bool = false


func _ready() -> void:
	await _run()
	if not _completed:
		_failed += 1
		print("  [FAIL] _run never reached its end — it aborted mid-run, so most of this "
			+ "suite's assertions were never made")
	print("\n=== EffectStudioColourKeyframeAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioColourKeyframeAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioColourKeyframeAcceptanceTest")
		get_tree().quit(0)


func _run() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E019")):
		print("[SKIP] E019 assets not available — acceptance skipped")
		_passed += 1
		_completed = true
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)

	var page = scn._studio_page
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E019"):
			dir = d
	_assert_true(dir != "", "E019 in the effect catalogue")
	if dir == "":
		return
	page._load_effect(dir)
	await _frames(40)

	var data = page._effect_data
	var rend = scn._current_effect.sprite_renderer
	_assert_true(rend != null, "particle renderer present")

	# Find an emitter whose PLAYER COLUMN shows the colour track (colour enabled). The whole
	# surface moved there from the inspector in the ADR-0089 colour-move amendment, so the
	# tell is the track's visibility, not the picker's existence: the picker panel is built
	# once and lives for the page's lifetime (a constant-height reserved slot), so `!= null`
	# would now be true on every emitter including the ones with no colour at all.
	var emitter_index := -1
	var picker = page._colour_picker
	for i in range(data.emitters.size()):
		page._set_root(Target.emitter(i))
		await _frames(12)
		if page._sequence_life_column != null and page._sequence_life_column.visible:
			emitter_index = i
			break
	_assert_true(emitter_index >= 0, "an emitter exposes the colour track in the player column")
	if emitter_index < 0:
		return

	var s: Color = EmitterSpriteColor.representative(data, emitter_index)
	_assert_true(picker.gamut().is_equal_approx(Color(s.r, s.g, s.b, 1.0)), "picker gamut == representative texel")

	# Choose a NON-ZERO particle-age on the track (the axis a colour curve lives on) — proving
	# authoring is age-domain, not frame-0. Click the track at that age's band centre.
	var ribbon = page._sequence_ribbon
	var n: int = ribbon.colors().size()
	_assert_true(n > 2, "ribbon has an age window (%d frames)" % n)
	var col = page._sequence_life_column
	_assert_true(col != null and col.size.x > 0.0,
		"the colour column is laid out (w=%.0f)" % (col.size.x if col else 0.0))
	var rows: Array = page._sequence_life_rows
	var age: int = clampi(int(n * 0.6), 1, n - 1)
	# AN AGE IS A (row, column) CELL, IN ONE OF SEVERAL COLUMNS. It was enough to ask
	# `page._sequence_life_column` for the cell while the strip was a single column; since
	# the wrap (2026-08-20) that column holds only its SLICE of the rows, and an age in
	# column 1 resolves to an empty rect on column 0 — a click at (0,0) that selects
	# nothing. Find the column whose slice actually contains the age and click THAT, the
	# same way the author's mouse finds it: by looking at where it is drawn.
	var hit: Dictionary = _cell_of(page, age)
	col = hit.get("col")
	var cell: Rect2 = hit.get("rect", Rect2())
	_assert_true(cell.size.x > 0.0, "age %d has a cell on one of the columns" % age)
	col._gui_input(_click_at(cell.position + cell.size * 0.5))   # SELECT `age` — no mint
	await _frames(30)
	_assert_true(page._colour_selected_frame == age,
		"clicking the column selected age %d (got %d)" % [age, page._colour_selected_frame])

	# THE SECOND STEP, DRIVEN EXPLICITLY (author, 2026-08-20). This suite passed WITHOUT it
	# on the first run after the change, which is worth stating: `age` is 60% into the window
	# and on this emitter it already carried a keyframe, so the round trip below worked by
	# coincidence and would have kept working while the two-step gesture was broken. It now
	# forces the interpolated path — key an age that is definitely NOT one — so the acceptance
	# actually exercises what an author does.
	var plain: int = -1
	for f in range(1, n):
		if page._colour_index_of_frame(f) < 0 \
				and not (_cell_of(page, f).get("rect", Rect2()) as Rect2).size.x <= 0.0:
			plain = f
			break
	if plain >= 0:
		var kf_before: int = page._colour_keyframes.size()
		var phit: Dictionary = _cell_of(page, plain)
		var pcell: Rect2 = phit.get("rect", Rect2())
		phit["col"]._gui_input(_click_at(pcell.position + pcell.size * 0.5))
		await _frames(20)
		_assert_true(page._colour_selected_frame == plain,
			"an interpolated age selects (%d)" % plain)
		_assert_true(page._colour_keyframes.size() == kf_before,
			"…and minted nothing by being selected")
		page._colour_key_button.pressed.emit()
		await _frames(30)
		_assert_true(page._colour_index_of_frame(plain) >= 0,
			"⬥ locked age %d in as a real keyframe" % plain)
		# Put the selection back where the round trip below expects it.
		var bhit: Dictionary = _cell_of(page, age)
		var back: Rect2 = bhit.get("rect", Rect2())
		bhit["col"]._gui_input(_click_at(back.position + back.size * 0.5))
		await _frames(20)
		_assert_true(page._colour_selected_frame == age, "re-selected age %d" % age)
	else:
		print("  [NOTE] every addressable age on this emitter is already a keyframe — the "
			+ "⬥ arm is unexercised here")
		_passed += 1

	# The round trip below recolours age %d, which must therefore BE a keyframe by now.
	if page._colour_index_of_frame(age) < 0:
		page._colour_key_button.pressed.emit()
		await _frames(30)
	_assert_true(page._colour_index_of_frame(age) >= 0,
		"age %d is a real keyframe before the recolour round trip" % age)

	# The picker is the page's own now and survives the reproject the add triggers — but it
	# must have SWAPPED from the dimmed "pick a frame" plate to the live grid, which is the
	# conditional appearance the author asked for.
	picker = page._colour_picker
	# THE PANEL IS UP; WHETHER THE GRID IS depends on the window (2026-08-20). The picker's
	# height is a three-way choice now — the full panel when the column's slack affords the
	# 439px grid, the HEADER ALONE otherwise — because the old rule hid the whole panel on a
	# short row and took ⬥ with it, and ⬥ is the only way to mint a keyframe since ADR-0089
	# dec. 5. Asserting `picker.visible` here asserted the tall window, not the feature; the
	# feature is that the panel is up and the gesture is reachable either way.
	_assert_true(page._colour_picker_panel != null and page._colour_picker_panel.visible,
		"the picker panel is up once a keyframe is selected")
	_assert_true(picker != null and (picker.visible or page._colour_key_button.visible),
		"…and it is live: the colour grid where there is room for it, the ⬥ header where "
		+ "there is not (grid %s, panel %.0fpx)"
		% [str(picker.visible), page._colour_picker_panel.size.y])
	# THE PICK IS THE CURVE (ADR-0089 decision 4, amended 2026-08-21). It used to be the MUXED
	# target, so this line picked `S * 0.5` and expected the inverse mux to recover 0.5. The
	# sprite is no longer between the pick and the sample: 0.5 is picked and 0.5 is written, for
	# any sprite, which is the whole of *"reach every [0,0,0] to [255,255,255]"*.
	# ASYMMETRIC ON PURPOSE, and 0.95 is the assertion the author asked for: against a real
	# corpus sprite that value is outside the old reachable box in almost every channel (97.5%
	# of colour emitters have none that could hold 255), so it is exactly what used to come back
	# projected. It also makes the three channels genuinely diverge, which the sparkline check
	# below needs — under the muxed model that divergence came from dividing by three different
	# `S.k`, an artifact of the projection rather than of anything the author did.
	var target := Color(0.95, 0.6, 0.15, 1.0)
	picker.pick(target)
	await _frames(30)

	# The renderer paints modulate = the picked curve, verbatim, in every channel — INCLUDING a
	# dead one, which is the behaviour change: the channel is authored and the SPRITE is what
	# zeroes it downstream, rather than the widget zeroing it on the way in.
	var mod: Color = rend._compute_color_modulate(_particle(emitter_index, age))
	_assert_channel(mod.r, target.r, "R modulate @age after author")
	_assert_channel(mod.g, target.g, "G modulate @age after author")
	_assert_channel(mod.b, target.b, "B modulate @age after author")

	# …and the bound is still REAL, just reported rather than imposed: what the particle renders
	# is that curve muxed through the sprite, which is exactly what the picker's renders-as
	# swatch shows. A dead channel renders black here and the picker says which one it is.
	var shows: Color = picker.renders_as()
	_assert_true(absf(shows.r - mod.r * s.r) <= 0.01 and absf(shows.b - mod.b * s.b) <= 0.01,
		"the renders-as swatch IS the curve muxed through the sprite")
	var lit: bool = s.r > 0.0 and s.g > 0.0 and s.b > 0.0
	_assert_true((picker.dead_channel_tag() == "") == lit,
		"the dead-channel tag is present exactly when the sprite has a dead channel")

	# The forked curves are independent (the un-alias that unlocks the box).
	var em = data.emitters[emitter_index]
	var ri := int(em.color_curves["r"])
	var gi := int(em.color_curves["g"])
	var bi := int(em.color_curves["b"])
	_assert_true(ri != gi and gi != bi and ri != bi, "emitter forked to 3 independent curves")

	# Live sparkline refresh (ADR-0089 editing-UX, decision 5, the BUG): after the recolour un-aliases
	# r=g=b onto 3 forked curves, the three `Color (R/G/B) · curve` sparklines on the LEFT must track
	# the forked curves — not a stale snapshot of the aliased curve 0.
	var sparks: Dictionary = page._inspector.colour_channel_sparklines()
	if sparks.has("r") and sparks.has("g") and sparks.has("b"):
		_assert_true(Array(sparks["r"].samples()) == data.get_curve(ri).samples,
			"the R sparkline tracks the forked R curve (not a stale snapshot)")
		_assert_true(Array(sparks["g"].samples()) == data.get_curve(gi).samples,
			"the G sparkline tracks the forked G curve")
		var rg_differ: bool = Array(sparks["r"].samples()) != Array(sparks["g"].samples())
		_assert_true(rg_differ, "R and G sparklines now differ (the un-alias is visible on the left)")
	else:
		_assert_true(false, "the three colour-channel sparklines are recorded")

	# Delete round-trip (ADR-0089 editing-UX, decision 4): right-click the authored handle → the host
	# removes it and the curve interps across the gap. Drive the REAL UI path (track → page → host).
	_assert_true(page._colour_delete_available(), "a real selected keyframe → Del/Remove available")
	var khit: Dictionary = _cell_of(page, age)
	var kf_cell: Rect2 = khit.get("rect", Rect2())
	_assert_true(kf_cell.size.x > 0.0, "the authored age still has a cell to right-click")
	khit["col"]._gui_input(_right_click_at(kf_cell.position + kf_cell.size * 0.5))
	await _frames(30)
	var after: Dictionary = scn.studio_colour_keyframes(emitter_index)
	var frames_after: Array = []
	for kf in after.get("keyframes", []):
		frames_after.append(int(kf["frame"]))
	_assert_true(not (age in frames_after), "the authored keyframe is gone after right-click Remove")
	_assert_true(not page._colour_delete_available(), "delete no longer offered (selection cleared)")

	# The game-JSON save half writes curves.json + emitters.json.
	var res: Dictionary = scn.studio_save()
	_assert_true(res.get("ok", false), "studio_save ok after colour authoring")
	var out: String = res.get("out_path", "")
	_assert_true(FileAccess.file_exists(out.path_join("curves.json")), "curves.json written")
	_assert_true(FileAccess.file_exists(out.path_join("emitters.json")), "emitters.json written")
	_completed = true


## A live channel (S.k > 0) renders ~0.5 (box centre); a dead channel (S.k == 0) renders 0.
## The authored curve value, which no longer depends on the sprite at all — this used to take
## the sprite channel `s_k` and expect 0.5-or-0, because the pick was projected through it. That
## projection is what made 97.5% of corpus colour emitters unable to hold 255 in any channel.
func _assert_channel(modulate: float, expected: float, label: String) -> void:
	if absf(modulate - expected) <= 0.03:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %f, expected %f)" % [label, modulate, expected])


## A click at a POINT — the vertical column needs both axes, because an age is a
## (row, column) cell rather than a position along a line.
func _click_at(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	return ev


func _right_click_at(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	ev.position = pos
	return ev


func _click(x: float) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(x, 6.0)
	return ev


func _right_click(x: float) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	ev.position = Vector2(x, 6.0)
	return ev


func _particle(emitter_index: int, age: int):
	var p = ParticleClass.new()
	p.emitter_index = emitter_index
	p.age = age
	return p


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s" % label)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


## WHICH COLUMN HOLDS THIS AGE, and where in it — `{col, rect}`.
##
## Every click in this suite used to go through `page._sequence_life_column`, which was the
## whole strip. Since the wrap (2026-08-20) that is only column 0's SLICE of the rows, and
## `rect_of_frame` answers an EMPTY rect for an age outside a column's slice — so a click
## built from it lands at (0,0) and selects nothing. The failure reads as "selecting an age
## stopped working", which is a long way from "the fixture asked the wrong column".
##
## Falls back to column 0 so a caller always has something to drive; the empty rect is what
## the assertions test.
func _cell_of(page, age: int) -> Dictionary:
	for lc in page._sequence_life_columns:
		var r: Rect2 = ColourLifeColumn.rect_of_frame(age, lc._rows, SequenceThumbnail.SIDE,
			lc.size.x)
		if r.size.x > 0.0:
			return {"col": lc, "rect": r}
	return {"col": page._sequence_life_column, "rect": Rect2()}
