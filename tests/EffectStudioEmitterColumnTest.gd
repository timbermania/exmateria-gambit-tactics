extends Node
## REGRESSION (headful, real E019): THE EMITTER SCREEN CLAIMS THE INSPECTOR ROW'S RIGHT
## COLUMN (ADR-0100 dec. 1, amended 2026-08-19 — "when I click on an emitter event I get a
## very tall pane with tons of empty space on the right").
##
## Measured before the change, on a 1187x507 body: an `emitter` target declared 675px of
## content width and 2027px of content height into a 268px row, and claimed NO column — so
## 512px of the row sat empty beside fields that had to scroll 7.6 screens. The width was
## unclaimed because only `frame` and `animation` targets had an address for the column;
## an emitter has one too (`anim_index` + the `anim_param` LENS), it was simply never read.
##
## THE ADDRESS IS THE WHOLE OF THE RISK, and it is invisible. An emitter index read as an
## animation index decodes a real sequence and draws real sprites — a wrong picture that
## looks exactly like a right one. So every assertion here is on WHAT THE PLAYER IS BOUND
## TO, derived from the emitter's own record rather than hardcoded, and the sharpest case
## deliberately picks an emitter whose `anim_index` differs from its own index so the
## confusion is expressible at all.
##
## Skips when the ROM-derived effect assets are absent (gitignored), and skips WITH THE
## NUMBERS when the compositor hands back a window too small to express a layout invariant
## — this harness family has measured bodies of 153, 507, 1187, 1209 and 1241px.
##
## Run: godot --path . --quit-after 400 res://tests/EffectStudioEmitterColumnTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const FramesBar = preload("res://src/effects/studio/EffectFramesBar.gd")
const Subject = preload("res://src/effects/studio/EmitterSequenceSubject.gd")

var _passed: int = 0
var _failed: int = 0
## Which tests RAN TO THE END — a GDScript coroutine that hits a runtime error aborts
## silently, taking its remaining assertions with it and still reporting `0 failed`.
var _completed: Dictionary = {}
const _EXPECTED_TESTS := [
	"emitter_claims", "address_is_the_emitters_not_its_index", "span_claims",
	"origin_rung", "kinds_that_claim_nothing", "no_film_strip", "layout", "title_width",
	"frameset_stack",
]


func _done(name: String) -> void:
	_completed[name] = true


func _ready() -> void:
	await _run()
	for name in _EXPECTED_TESTS:
		if not _completed.has(name):
			_failed += 1
			print("  FAIL: test '%s' never reached its end — it aborted mid-run, so its assertions were never made" % name)
	print("\n=== EffectStudioEmitterColumnTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioEmitterColumnTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioEmitterColumnTest")
		get_tree().quit(0)


func _run() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E019")):
		print("[SKIP] E019 assets not available — emitter column regression skipped")
		_passed += 1
		for n in _EXPECTED_TESTS:
			_done(n)
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page
	_assert_true(page != null, "the studio page exists")
	if page == null:
		return
	DebugOverlay.show_overlay()
	await _frames(30)
	await _settle(page._body, "the dashboard body")

	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E019"):
			dir = d
	if dir == "":
		print("[SKIP] E019 not in the catalogue")
		_passed += 1
		for n in _EXPECTED_TESTS:
			_done(n)
		return
	page._load_effect(dir)
	await _frames(40)
	await _settle(page._body, "the dashboard body after loading E019")
	if page._effect_data == null or page._effect_data.texture == null:
		print("[SKIP] E019 has no texture")
		_passed += 1
		for n in _EXPECTED_TESTS:
			_done(n)
		return

	await _test_an_emitter_target_claims_the_column(page)
	await _test_the_bound_address_is_the_emitters_sequence_not_its_own_index(page)
	await _test_a_particle_span_claims_it_too(page)
	await _test_the_rung_is_origin_by_construction(page)
	await _test_the_kinds_that_claim_nothing_still_claim_nothing(page)
	await _test_the_emitter_screen_grows_no_film_strip(page)
	await _test_the_column_stays_inside_its_band_on_an_emitter(page)
	await _test_the_title_does_not_widen_the_column(page)
	await _test_the_frameset_block_stacks_under_the_player(page)


func _test_an_emitter_target_claims_the_column(page) -> void:
	var ei: int = _any_playing_emitter(page)
	if ei < 0:
		print("[SKIP] no E019 emitter points at a real sequence — nothing to bind")
		_passed += 1
		_done("emitter_claims")
		return
	page._set_root(Target.emitter(ei))
	await _frames(16)
	_assert_true(page._sequence_panel.visible,
		"an emitter target shows the sequence player (emitter %d)" % ei)
	_assert_true(not page._frameset_panel.visible,
		"…and not the frameset canvas — the slot still holds ONE occupant")
	_assert_true(page._sequence_canvas._trace.size() > 0,
		"the player is bound to a real sequence (%d cells)" % page._sequence_canvas._trace.size())
	_done("emitter_claims")


func _test_the_bound_address_is_the_emitters_sequence_not_its_own_index(page) -> void:
	# THE SHARP CASE. Pick an emitter whose `anim_index` is NOT its own index, so binding
	# `animations[emitter_index]` — the shape every surface used before this change, since
	# a ref's `index` was always an animation index — is a DIFFERENT and detectable answer.
	var ei: int = _emitter_whose_sequence_differs_from_its_index(page)
	if ei < 0:
		print("[SKIP] every E019 emitter plays the sequence at its own index — the confusion is inexpressible here")
		_passed += 1
		_done("address_is_the_emitters_not_its_index")
		return
	var em = page._effect_data.emitters[ei]
	page._set_root(Target.emitter(ei))
	await _frames(16)
	_assert_eq(int(page._sequence_bound.get("anim_index", -1)), int(em.anim_index),
		"emitter %d plays sequence %d, and that is what is bound (not %d, its own index)"
			% [ei, int(em.anim_index), ei])
	_assert_eq(int(page._sequence_bound.get("group", -1)), int(em.anim_param),
		"…through the emitter's own frameset-group lens (%d)" % int(em.anim_param))
	# The title states the bound address, which on this screen is the fact the column is
	# there to give: which sequence this emitter's particles actually play.
	_assert_true(page._sequence_canvas_title.text.find(str(int(em.anim_index))) >= 0,
		"the title names the bound sequence — read '%s'" % page._sequence_canvas_title.text)
	# The one cell count that cannot be a coincidence: the trace is one cell per opcode of
	# the BOUND sequence, and the two sequences have different opcode counts (checked).
	var anim: Dictionary = page._effect_data.animations[int(em.anim_index)]
	_assert_eq(page._sequence_canvas._trace.size(), (anim.get("opcodes", []) as Array).size(),
		"and the decode is that sequence's opcode stream, cell for opcode")
	_done("address_is_the_emitters_not_its_index")


func _test_a_particle_span_claims_it_too(page) -> void:
	# THE PRIMARY CASE — "clicking on an emitter event" IS clicking a particle span, and a
	# span's ref is an opaque `span_id` with no emitter in it. The emitter is reached
	# through the score, which is why `EmitterSequenceSubject.resolve` takes one.
	var sid: String = _any_particle_span_id(page)
	if sid == "":
		print("[SKIP] E019's score has no particle span with an emitter — nothing to follow")
		_passed += 1
		_done("span_claims")
		return
	var score: Dictionary = page._timeline._score
	var want: Dictionary = Subject.resolve(Target.span(sid), page._effect_data, score)
	page._set_root(Target.span(sid))
	await _frames(16)
	_assert_true(page._sequence_panel.visible,
		"a particle span shows the player too — span '%s'" % sid)
	_assert_eq(int(page._sequence_bound.get("anim_index", -1)), int(want["anim_index"]),
		"bound to the sequence the span's emitter (%d) plays" % int(want["emitter_index"]))
	_assert_eq(int(page._sequence_bound.get("group", -1)), int(want["group"]),
		"through that emitter's lens")
	_done("span_claims")


func _test_the_rung_is_origin_by_construction(page) -> void:
	# On an emitter screen there is no ladder to climb: the target IS the emitter, so the
	# rung is `origin` and names THAT emitter. Climbing the trail instead would answer with
	# whatever emitter the author happened to drill through — or nothing, on a span reached
	# straight from the timeline, which is how every span is reached.
	var sid: String = _any_particle_span_id(page)
	if sid == "":
		print("[SKIP] no particle span to check the rung on")
		_passed += 1
		_done("origin_rung")
		return
	var want: Dictionary = Subject.resolve(Target.span(sid), page._effect_data,
		page._timeline._score)
	page._set_root(Target.span(sid))
	await _frames(16)
	_assert_eq(str(page._sequence_provenance.get("rung", "")), "origin",
		"a span names its emitter directly, so the rung is `origin`")
	_assert_eq(int(page._sequence_provenance.get("emitter_index", -1)),
		int(want["emitter_index"]), "and it is the emitter the SPAN fires")
	_assert_eq(int(page._sequence_provenance.get("others", -1)), 0,
		"with no cohort to count — there is no ambiguity to report")
	_done("origin_rung")


func _test_the_kinds_that_claim_nothing_still_claim_nothing(page) -> void:
	# The column is not a general-purpose filler. A target with no sequence behind it must
	# leave it alone, and `_sequence_bound` must be EMPTY when the panel is down — that
	# emptiness is what stops a later in-place refresh from re-decoding a stale address.
	for t in [Target.texture(), Target.effect_settings()]:
		page._set_root(t)
		await _frames(14)
		_assert_true(not page._sequence_panel.visible,
			"a `%s` target claims no column" % Target.kind(t))
		_assert_true(page._sequence_bound.is_empty(),
			"…and leaves no bound address behind it")
	var sid: String = _any_span_id_without_an_emitter(page)
	if sid != "":
		page._set_root(Target.span(sid))
		await _frames(14)
		_assert_true(not page._sequence_panel.visible,
			"a span that fires no emitter claims no column ('%s')" % sid)
		_assert_true(page._sequence_bound.is_empty(), "…and leaves no bound address")
	else:
		print("[NOTE] E019's score has no emitterless span — that half is unmeasured here")
	_done("kinds_that_claim_nothing")


func _test_the_emitter_screen_grows_no_film_strip(page) -> void:
	# DELIBERATE, not an oversight. The film strip is the ANIMATION screen's inspector rows
	# (#247) — only `SequenceProjector` emits a thumb spec, and an emitter's projection is
	# its four characterizing groups. The emitter screen gets the PLAYER, not the strip:
	# its rows are the emitter's own physics, which is what the author is there to edit.
	var ei: int = _any_playing_emitter(page)
	if ei < 0:
		print("[SKIP] no emitter to check the strip on")
		_passed += 1
		_done("no_film_strip")
		return
	page._set_root(Target.emitter(ei))
	await _frames(16)
	_assert_eq(_section_thumbnails(page).size(), 0,
		"the emitter screen's sections carry no thumbnails")
	# And the guard that keeps it that way is keyed on the BOUND address, not on the open
	# target's ref — which on this screen is an emitter index. Feeding it that index must
	# not conjure a picture out of an unrelated sequence.
	var em = page._effect_data.emitters[ei]
	_assert_true(page._sequence_thumbnail_for(
			{"animation_index": ei, "opcode_index": 0}) == null
		or ei == int(em.anim_index),
		"a spec keyed on the EMITTER index draws nothing (emitter %d, sequence %d)"
			% [ei, int(em.anim_index)])
	_assert_true(page._sequence_thumbnail_for(
		{"animation_index": int(em.anim_index), "opcode_index": 0}) != null,
		"…while a spec keyed on the BOUND sequence still draws")
	_done("no_film_strip")


func _test_the_column_stays_inside_its_band_on_an_emitter(page) -> void:
	var ei: int = _any_playing_emitter(page)
	if ei < 0:
		print("[SKIP] no emitter to lay out")
		_passed += 1
		_done("layout")
		return
	page._set_root(Target.emitter(ei))
	await _frames(16)
	await _settle(page._sequence_panel, "the sequence panel on an emitter target")
	if not page._sequence_panel.visible:
		print("[SKIP] the panel is not visible — nothing to measure")
		_passed += 1
		_done("layout")
		return
	var panel: Rect2 = page._sequence_panel.get_global_rect()
	var controls: Rect2 = page._inspector.get_global_rect()
	var timeline: Rect2 = page._scroll.get_global_rect()

	# Skip WITH THE NUMBERS, both axes — the compositor picks the window and this harness
	# family has seen bodies from 153 to 1241px. Asserting through a window that cannot
	# hold the invariant measures the compositor, not the layout.
	var room: float = page._body.size.x - page._inspector.content_width()
	var floor_w: float = page._sequence_panel.get_combined_minimum_size().x
	if room < floor_w:
		print("[SKIP] the dashboard came up too narrow — %.0fpx beside a %.0fpx declared inspector for a %.0fpx panel minimum (body %.0f wide)"
			% [room, page._inspector.content_width(), floor_w, page._body.size.x])
		_passed += 1
		_done("layout")
		return
	var reserved: float = Page.MIN_CHANNELS_H + FramesBar.BAR_H \
		+ (page._path_bar.bar_height() if page._path_bar != null else 0.0)
	var budget: float = page._body.size.y - reserved
	var floor_h: float = 180.0 + page._canvas_chrome_h(page._sequence_canvas)
	if budget < floor_h:
		print("[SKIP] the dashboard came up too short — %.0fpx of row budget for a %.0fpx square-canvas floor (body %.0f tall, %.0f reserved)"
			% [budget, floor_h, page._body.size.y, reserved])
		_passed += 1
		_done("layout")
		return

	_assert_true(panel.position.y + panel.size.y <= timeline.position.y + 1.0,
		"[A] the panel never bleeds into the timeline (ends %.0f, timeline starts %.0f)"
			% [panel.position.y + panel.size.y, timeline.position.y])
	# The row's top edge is shared by the player and the LEFT COLUMN'S STACK, which since
	# ADR-0130 begins with the `[Texture] [Values]` tab strip rather than with the
	# inspector. Two facts instead of one, which is strictly stronger than the equality it
	# replaces: no dead space at the row's top, AND no gap opened between strip and
	# inspector by a stale constant.
	var strip: Rect2 = page._tab_strip.get_global_rect()
	_assert_true(absf((strip.position.y + strip.size.y) - controls.position.y) <= 1.0,
		"[B0] the inspector abuts the tab strip (strip bottom %.0f, inspector top %.0f)"
			% [strip.position.y + strip.size.y, controls.position.y])
	_assert_true(absf(panel.position.y - strip.position.y) <= 1.0,
		"[B] it shares the inspector's row (panel top %.0f, tab strip top %.0f)"
			% [panel.position.y, strip.position.y])
	_assert_true(absf((panel.position.x + panel.size.x)
			- (page._body.get_global_rect().position.x + page._body.size.x)) <= 1.0,
		"[C] docked to the row's right edge (panel right %.0f, body right %.0f)"
			% [panel.position.x + panel.size.x,
				page._body.get_global_rect().position.x + page._body.size.x])
	# [D] THE POINT OF THE WHOLE CHANGE: the panel does not LAND on the inspector. This is
	# `column_width`'s leftover clamp doing its job for a third target kind — the failure
	# that cost the column its first life (108px of overlap, `0306ae37c`).
	_assert_true(panel.position.x + 1.0 >= controls.position.x + controls.size.x,
		"[D] and never lands on the inspector (panel left %.0f, inspector right %.0f)"
			% [panel.position.x, controls.position.x + controls.size.x])
	# [E] and the row is measurably USED now: the width the emitter screen left empty is
	# claimed. Reported with the numbers whether it passes or not.
	print("[MEASURED] emitter %d, body %.0fx%.0f: inspector %.0fpx wide (declares %.0f), column %.0fpx, unused %.0f"
		% [ei, page._body.size.x, page._body.size.y, controls.size.x,
			page._inspector.content_width(), panel.size.x,
			page._body.size.x - controls.size.x - panel.size.x])
	_assert_true(panel.size.x > 0.0, "[E] the column has real width (%.0fpx)" % panel.size.x)
	_done("layout")


func _test_the_title_does_not_widen_the_column(page) -> void:
	# `_canvas_floor_w` measures the panel's WIDEST non-canvas child, and the title Label is
	# one of them — so a longer title is not free, it is a bid for column width taken from
	# the focus block and then from the inspector. The transport row (⏮ op / op ⏭ / speed)
	# is the incumbent widest at ~202px; the title must stay under it, or the emitter
	# screen's column silently grows and the inspector beside it silently shrinks.
	var ei: int = _any_playing_emitter(page)
	if ei < 0:
		print("[SKIP] no emitter to title")
		_passed += 1
		_done("title_width")
		return
	page._set_root(Target.emitter(ei))
	await _frames(16)
	# IT WALKS UP, like `_canvas_floor_w` does since the 2026-08-20 vertical-column
	# amendment. The canvas's immediate parent is a ROW now (the player's square beside the
	# colour column), so a single-level walk finds only the 70px column and misses the 202px
	# transport one level above — and then reports the title as too wide against the wrong
	# incumbent.
	var title_w: float = page._sequence_canvas_title.get_combined_minimum_size().x
	var widest: float = 0.0
	var node: Control = page._sequence_canvas
	var parent = node.get_parent()
	while parent is BoxContainer:
		for child in (parent as BoxContainer).get_children():
			if child == node or child == page._sequence_canvas_title \
					or not (child is Control) or not (child as Control).visible:
				continue
			widest = maxf(widest, (child as Control).get_combined_minimum_size().x)
		node = parent as Control
		parent = node.get_parent()
	print("[MEASURED] title '%s' is %.0fpx against the panel's other chrome at %.0fpx"
		% [page._sequence_canvas_title.text, title_w, widest])
	_assert_true(title_w <= widest,
		"the title bids for no more width than the chrome already beside it (%.0f vs %.0f)"
			% [title_w, widest])
	_done("title_width")


## THE FRAMESET CONTROLS STACK UNDER THE PLAYER ON THIS SCREEN TOO (author, 2026-08-19:
## "I thought the plan was to put them on this screen…because we had space").
##
## The block was gated on `kind == "animation"` — the same thing while only an animation
## target could bind the player, and wrong the moment an emitter or span can. So the screen
## the author spends the most time in showed a running sequence with no frameset controls
## under it at all.
##
## THE ADDRESS IS THE RISK, AGAIN AND SILENTLY. `SequenceFocusBlock.section` reads `ref.index`
## as an animation index and `ref.group` as the frameset lens; on an emitter target
## `ref.index` is an emitter index. Fed the open target it would name — and EDIT — a real
## frameset belonging to an unrelated sequence, and nothing on screen would say so. It is fed
## `_sequence_bound` instead, so the block, the player and the strip are all one address.
func _test_the_frameset_block_stacks_under_the_player(page) -> void:
	var ei: int = _any_playing_emitter(page)
	if ei < 0:
		print("[SKIP] no emitter to stack under")
		_passed += 1
		_done("frameset_stack")
		return
	page._set_root(Target.emitter(ei))
	await _frames(20)
	await _settle(page._sequence_panel, "the sequence panel")
	if not page._sequence_panel.visible:
		print("[SKIP] the player is not up — nothing to stack under")
		_passed += 1
		_done("frameset_stack")
		return
	# The block is dropped when the column has no slack under the player's constant box, and
	# on a WM-shrunk window that is the usual case — a 268px row against a 448px box has none.
	# Skip WITH the numbers rather than fail on a window the compositor chose.
	var slack: float = Page.focus_stack_height(page._inspector.size.y,
		page._sequence_panel.size.y, page._focus_inspector.content_height())
	if slack <= 0.0 or not page._focus_panel.visible:
		print("[SKIP] no room to stack — row %.0fpx, player's box %.0f, %.0f of slack under it"
			% [page._inspector.size.y, page._sequence_panel.size.y, slack])
		_passed += 1
		_done("frameset_stack")
		return
	var block_r: Rect2 = page._focus_panel.get_global_rect()
	var player_r: Rect2 = page._sequence_panel.get_global_rect()
	_assert_true(absf(block_r.position.x - player_r.position.x) < 2.0,
		"the block is in the PLAYER's column (block x %.0f, player x %.0f)"
			% [block_r.position.x, player_r.position.x])
	_assert_true(absf(block_r.size.x - player_r.size.x) < 2.0, "…at the player's width")
	_assert_true(block_r.position.y >= player_r.position.y + player_r.size.y - 1.0,
		"…and UNDER it, never over the box")
	# THE BLOCK IS ABOUT THE BOUND SEQUENCE, not about `ref.index`. On an emitter whose
	# `anim_index` differs from its own index the two disagree, and only one of them names
	# the sequence the player is actually running.
	var folds: Array = page._focus_inspector.section_folds()
	_assert_true(not folds.is_empty(), "the block rendered a section")
	if not folds.is_empty():
		var title := str(folds[0].get("title", ""))
		print("[MEASURED] emitter %d bound to %s — block reads '%s'"
			% [ei, str(page._sequence_bound), title])
		_assert_true(title.find("Frameset") >= 0 or title.find("opcode") >= 0,
			"…and it names a frameset or the spriteless opcode it is parked on")
	_done("frameset_stack")


# --- fixtures ---------------------------------------------------------------

## The first emitter that points at a real sequence — the resolver's own answer, so the
## test and the code agree on what "playing" means without a second rule.
func _any_playing_emitter(page) -> int:
	for i in range(page._effect_data.emitters.size()):
		if not Subject.resolve(Target.emitter(i), page._effect_data, {}).is_empty():
			return i
	return -1


## An emitter whose `anim_index` differs from its own index AND whose sequence has a
## different opcode count, so both the address assertion and the cell-count one can tell
## a right bind from a wrong one.
func _emitter_whose_sequence_differs_from_its_index(page) -> int:
	var anims: Array = page._effect_data.animations
	for i in range(page._effect_data.emitters.size()):
		var s: Dictionary = Subject.resolve(Target.emitter(i), page._effect_data, {})
		if s.is_empty():
			continue
		var a: int = int(s["anim_index"])
		if a == i or i >= anims.size():
			continue
		if (anims[a].get("opcodes", []) as Array).size() \
				!= (anims[i].get("opcodes", []) as Array).size():
			return i
	return -1


func _any_particle_span_id(page) -> String:
	for lane in page._timeline._score.get("lanes", []):
		for span in lane.get("spans", []):
			var sid := str(span.get("id", ""))
			if not Subject.resolve(Target.span(sid), page._effect_data,
					page._timeline._score).is_empty():
				return sid
	return ""


func _any_span_id_without_an_emitter(page) -> String:
	for lane in page._timeline._score.get("lanes", []):
		for span in lane.get("spans", []):
			var sid := str(span.get("id", ""))
			if sid != "" and Subject.resolve(Target.span(sid), page._effect_data,
					page._timeline._score).is_empty():
				return sid
	return ""


func _section_thumbnails(page) -> Array:
	var out: Array = []
	_collect_thumbnails(page._inspector, out)
	return out


func _collect_thumbnails(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child.get_script() != null \
				and str(child.get_script().resource_path).ends_with("SequenceThumbnail.gd"):
			out.append(child)
		_collect_thumbnails(child, out)


# --- harness ----------------------------------------------------------------

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _settle(node: Control, what: String, max_frames: int = 240) -> void:
	var last := Vector2.ZERO
	var stable := 0
	for i in range(max_frames):
		await get_tree().process_frame
		if node == null:
			return
		if node.size == last:
			stable += 1
			if stable >= 8:
				return
		else:
			stable = 0
			last = node.size
	print("[NOTE] %s never settled in %d frames (last %s)" % [what, max_frames, last])


func _assert_eq(actual, expected, msg: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s\n         expected: %s\n         actual:   %s" % [msg, expected, actual])


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)
