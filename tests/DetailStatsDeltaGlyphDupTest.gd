extends Node3D
## §15.26 DEFECT #8 regression guard — the delta/compare stats panel must NOT capture stale glyphs.
##
## Bug ("garbage/kanji-like '-' glyphs in the picker preview until you move a frame dim"): entering the
## equip-picker preview calls `_build_stats_text()`, which clears the prior (real-number) glyphs with a
## DEFERRED `queue_free()` and immediately mounts the new "-" glyphs. `_rebuild_stats_delta()` then does a
## SYNCHRONOUS `_stats_text_root.duplicate()` — in the SAME call, before idle frees anything — so the delta
## panel clones BOTH the not-yet-freed old glyphs AND the new dashes (≈2× the count). The base self-heals
## next idle frame, but the delta's clones are fresh permanent nodes → the doubled garbage persists until a
## full `_rebuild_lower_settled` (what a frame-dim scrub triggers). Guard: after entering preview and
## letting idle run, the delta text subtree must have the SAME glyph-mesh count as the base panel.
##
## Run: <GODOT> --path . --quit-after 20 res://tests/DetailStatsDeltaGlyphDupTest.tscn

const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")

var _passed := 0
var _failed := 0


func _ready() -> void:
	var d = DetailScene.new()
	d.autoplay_open = false
	add_child(d)
	await get_tree().process_frame

	# A view whose real-number build has MORE glyphs than the "-" preview build, so a stale-node
	# duplicate() is detectable as a count divergence (padded "004 / 05%" etc. vs "- / -").
	d.set_stats_view({
		"move": 3, "jump": 3, "speed": 8, "r_power": 4, "r_wev": 5, "l_power": 0, "l_wev": 0,
		"r_at": 4, "c_ev": 5, "s_ev": 0, "a_ev": 0, "l_at": 0})
	await get_tree().process_frame

	# Enter the picker preview (the exact path that showed garbage), then let idle run — matching the
	# real game where the garbage PERSISTS across frames rather than clearing itself.
	d.set_stats_preview(true)
	await get_tree().process_frame
	await get_tree().process_frame

	var base := d.stats_glyph_count()
	var delta := d.stats_delta_glyph_count()
	_expect(base > 0, "base stats panel should have glyphs, got %d" % base)
	_expect(delta > 0, "delta compare panel should have glyphs, got %d" % delta)
	# The delta is a clone of the base — counts must match. Doubling = the stale-duplicate bug.
	_expect(delta == base,
		"delta panel glyph count (%d) must equal base (%d) — a mismatch means duplicate() captured stale/queued glyphs (garbage-glyph bug)" % [delta, base])

	d.queue_free()
	print("\n=== DetailStatsDeltaGlyphDupTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] DetailStatsDeltaGlyphDupTest")
		get_tree().quit(1)
	else:
		print("[PASS] DetailStatsDeltaGlyphDupTest: delta panel clones only the current glyphs")
		get_tree().quit(0)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] " + msg)
