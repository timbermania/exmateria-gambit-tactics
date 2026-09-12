extends Node

## NumberFont test — pure GDScript, no GPU / no rendering.
##
## Guards the HUD number-font layout (#91): the HP/MP/CT cur/max block FFT
## composes from EVENT/FRAME.BIN — `cur` right-aligned to the divider, the
## bridging `/`, then `max` staggered a baseline lower, ALL in the SMALL set
## (one size; disasm FUN_801363dc draws the fraction via the small routine
## FUN_8014aec0 @0x8014aec0). The window renders these placements each frame;
## the layout is pure so the size/stagger/advance rules are testable headless.
##
## Provenance (geometry + advance): docs/frame-bin-number-font.md (disasm-
## confirmed) + tools/test_parse_frame_font.py.

const NumberFont = preload("res://src/ui3/elements/NumberFont.gd")


func _ready() -> void:
	var failed := false
	var font := NumberFont.new()

	# 0. The atlas + both authored sizes loaded.
	if font.texture == null:
		print("[FAIL] FRAMEFONT.tga did not load"); failed = true
	if not font.has_size(NumberFont.BIG) or not font.has_size(NumberFont.SMALL):
		print("[FAIL] missing a size set: big=%s small=%s" % [
				font.has_size(NumberFont.BIG), font.has_size(NumberFont.SMALL)])
		failed = true

	# 1. Metrics came from the manifest. There are two authored sizes (big + small)
	#    and each advances overlap-1 of its cell width (big 8->7, small 6->5), so
	#    big advances WIDER than small. (The HP/MP/CT vitals happen to use the
	#    small set for everything — see place_pair below — but the resource still
	#    carries both.) Positions derive from advance_for() so this survives a
	#    headful advance re-tune.
	var abig := font.advance_for(NumberFont.BIG)
	var asmall := font.advance_for(NumberFont.SMALL)
	if abig <= 0.0 or asmall <= 0.0:
		print("[FAIL] non-positive advance: big=%s small=%s" % [abig, asmall]); failed = true
	if abig <= asmall:
		print("[FAIL] big advance %s not > small advance %s (two authored sizes)"
				% [abig, asmall]); failed = true
	if font.max_baseline_dy != 4.0:
		print("[FAIL] max_baseline_dy %s != 4" % font.max_baseline_dy); failed = true

	# 2. The two sizes are genuinely different cells (big cur vs small max), and
	#    small is shorter — the whole reason FFT authored two sets.
	var big0: Rect2 = font.cell_for("0", NumberFont.BIG)
	var small0: Rect2 = font.cell_for("0", NumberFont.SMALL)
	if big0.size.y <= small0.size.y:
		print("[FAIL] big '0' (h=%d) not taller than small '0' (h=%d)" % [
				big0.size.y, small0.size.y]); failed = true

	# 3. place_number advances each glyph by the size's advance, left-aligned.
	var run: Array = font.place_number("100", 40.0, 20.0, NumberFont.BIG, false)
	if run.size() != 3:
		print("[FAIL] '100' -> %d placements" % run.size()); failed = true
	elif not (run[0]["pos"] == Vector2(40, 20)
			and run[1]["pos"] == Vector2(40 + abig, 20)
			and run[2]["pos"] == Vector2(40 + 2 * abig, 20)):
		print("[FAIL] left-align advance: %s" % str(run.map(func(g): return g["pos"])))
		failed = true

	# 4. right_align ends the run AT x (cur numerator right-aligns to the divider).
	var rr: Array = font.place_number("999", 93.0, 19.0, NumberFont.BIG, true)
	if rr[0]["pos"].x != 93.0 - 3 * abig or rr[2]["pos"].x != 93.0 - abig:
		print("[FAIL] right-align: first=%s last=%s" % [rr[0]["pos"], rr[2]["pos"]])
		failed = true

	# 5. place_pair composes the vitals block: cur + '/' + max, ALL in the small
	#    set (the HP/MP/CT readout is one size — disasm FUN_801363dc draws each
	#    fraction via the small routine FUN_8014aec0). max staggers lower-right.
	var block: Array = font.place_pair(999, 999, 93.0, 19.0)
	if block.size() != 7:   # 3 cur + 1 slash + 3 max
		print("[FAIL] '999/999' block -> %d placements (want 7)" % block.size())
		failed = true
	else:
		var cur_parts := block.slice(0, 3)
		var slash: Dictionary = block[3]
		var max_parts := block.slice(4, 7)
		# cur is SMALL (same size as max), right-aligned to divider 93.
		if cur_parts.any(func(g): return g["size"] != NumberFont.SMALL):
			print("[FAIL] cur digits not all small"); failed = true
		if cur_parts[2]["pos"].x != 93.0 - asmall:
			print("[FAIL] cur not right-aligned to divider: %s" % cur_parts[2]["pos"])
			failed = true
		# the bridging slash is SMALL and sits at the divider (+ default slash offset).
		if slash["glyph"] != "/" or slash["size"] != NumberFont.SMALL:
			print("[FAIL] slash wrong: %s" % str(slash)); failed = true
		if slash["pos"] != Vector2(93, 21):
			print("[FAIL] slash pos %s != (93,21)" % slash["pos"]); failed = true
		# max is SMALL too, staggered down-right by (5, max_baseline_dy) from divider.
		if max_parts.any(func(g): return g["size"] != NumberFont.SMALL):
			print("[FAIL] max digits not all small"); failed = true
		if max_parts[0]["pos"] != Vector2(98, 23):   # 93+5, 19+4
			print("[FAIL] max start %s != (98,23)" % max_parts[0]["pos"]); failed = true
		if max_parts[1]["pos"].x != 98.0 + asmall:
			print("[FAIL] max advance: %s" % max_parts[1]["pos"]); failed = true
		# cur and max are the SAME (small) cell size.
		if cur_parts[0]["cell"].size.y != small0.size.y:
			print("[FAIL] cur glyph not small-cell sized"); failed = true
		if max_parts[0]["cell"].size.y != small0.size.y:
			print("[FAIL] max glyph not small-cell sized"); failed = true

	# 6. Zero-pad to a fixed field width (item 4 — the oracle shows `044/044`, `Exp.05`).
	var padp: Array = font.place_pair(44, 44, 93.0, 19.0, Vector2(0, 2), Vector2(5, 4), 1.0, 3)
	if padp.size() != 7:
		print("[FAIL] padded pair -> %d placements (want 7)" % padp.size()); failed = true
	else:
		var padded := "".join(padp.slice(0, 3).map(func(g): return g["glyph"]))
		if padded != "044":
			print("[FAIL] place_pair pad_width 3: cur '%s' != '044'" % padded); failed = true
	var solo: Array = font.place_number("5", 60.0, 20.0, NumberFont.SMALL, false, 1.0, 2)
	if "".join(solo.map(func(g): return g["glyph"])) != "05":
		print("[FAIL] place_number pad_width 2: '5' -> '%s' != '05'"
				% "".join(solo.map(func(g): return g["glyph"]))); failed = true

	# 7. The out-of-battle CT dash pair "---/---" (item 5): a real '-' glyph in the SMALL
	#    set (FRAMEFONT index 11), three dashes / slash / three dashes in the digit slots.
	var dash_cell: Rect2 = font.cell_for("-", NumberFont.SMALL)
	if dash_cell.size.x <= 0.0 or dash_cell.size.y <= 0.0:
		print("[FAIL] SMALL '-' glyph missing from FRAMEFONT (%s)" % dash_cell); failed = true
	var dp: Array = font.place_pair_text("---", "---", 93.0, 19.0)
	if dp.size() != 7:
		print("[FAIL] '---/---' -> %d placements (want 7)" % dp.size()); failed = true
	else:
		var cur_glyphs := dp.slice(0, 3).map(func(g): return g["glyph"])
		if cur_glyphs != ["-", "-", "-"]:
			print("[FAIL] dash-pair cur glyphs %s != 3 dashes" % str(cur_glyphs)); failed = true
		if dp[3]["glyph"] != "/":
			print("[FAIL] dash-pair missing bridging slash"); failed = true
		# The dashes occupy the same right-aligned slots the 3 digits would.
		if dp[2]["pos"].x != 93.0 - asmall:
			print("[FAIL] dash-pair cur not right-aligned to divider: %s" % dp[2]["pos"]); failed = true

	# 8. Defect #9 (§15.26 §D) — vitals numeric fields are fixed-width right-aligned 3-digit,
	#    even in the equip-picker PREVIEW where the numerator is blanked to a single dash. The
	#    string layout (`place_pair_text`) takes a `field_width` that zero-pads a NUMERIC part to
	#    that width (`44` -> `044`, so the strip's `0x78+6*d` cells always render 3), while a
	#    non-numeric blanked part (the "-" numerator) stays a single dash right-aligned to the
	#    divider. Round-34's preview drew a 2-digit denominator — this is the port bug.
	var prev: Array = font.place_pair_text("-", "44", 93.0, 19.0,
			Vector2(0, 2), Vector2(5, 4), 1.0, 3)
	if prev.size() != 5:   # 1 dash numerator + slash + 3 max
		print("[FAIL] preview field_width=3 -> %d placements (want 5: 1 dash + / + 3 max)"
				% prev.size()); failed = true
	else:
		var maxg := "".join(prev.slice(2, 5).map(func(g): return g["glyph"]))
		if maxg != "044":
			print("[FAIL] preview max not zero-padded to 3: '%s' != '044'" % maxg); failed = true
		if prev[0]["glyph"] != "-":
			print("[FAIL] preview numerator not a single dash: '%s'" % prev[0]["glyph"]); failed = true
		# §15.26: the ROM CENTERS the blanked numerator in the fixed 3-cell field (" - " —
		# dash cell 0xba in the MIDDLE digit cell), so the dash sits at divider - 2*advance
		# (the middle of the three right-aligned digit slots), NOT flush to the divider.
		if prev[0]["pos"].x != 93.0 - 2.0 * asmall:
			print("[FAIL] preview dash numerator not centered in the 3-cell field: %s"
					% prev[0]["pos"]); failed = true
	# A numeric numerator also pads: `44/44` field_width 3 -> `044` numerator + `044` max.
	var prevn: Array = font.place_pair_text("44", "8", 93.0, 19.0,
			Vector2(0, 2), Vector2(5, 4), 1.0, 3)
	if prevn.size() == 7:
		if "".join(prevn.slice(0, 3).map(func(g): return g["glyph"])) != "044":
			print("[FAIL] field_width numeric numerator not padded to 044"); failed = true
		if "".join(prevn.slice(4, 7).map(func(g): return g["glyph"])) != "008":
			print("[FAIL] field_width numeric max not padded to 008"); failed = true
	else:
		print("[FAIL] field_width numeric pair -> %d placements (want 7)" % prevn.size()); failed = true

	if failed:
		print("[FAIL] NumberFont test")
	else:
		print("[PASS] NumberFont: vitals all-small, right-align cur, slash, staggered max, "
				+ "zero-pad field width, and the '---/---' dash pair")
	get_tree().quit()
