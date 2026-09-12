extends Node
## EquipDeltaPalette test — the "recolour only the ink, keep the plain digit's frame" spec.
##
## The user's verdict (authoritative): a signed stat-delta digit must be IDENTICAL to its
## plain neighbour (the denominator / plain stat value) — same border, same shading, same
## fill — just with a different colour in the MIDDLE (the bright body). The old FRAME-pal-15
## index-bias path produced a foreign-grey, borderless digit; this replaces it.
##
## So EquipDeltaPalette.recolour(base, ink) copies the neighbour's OWN number CLUT and
## overwrites ONLY the ink indices (1·2 = the glyph's bright body) with the sign colour,
## leaving gutter (0), anti-alias tail (3) and background-fill/border (4) untouched.
##
## Two bases in the game:
##   - vitals numerator  → MENU_CLUT (bright white ink on the dark frame)
##   - stats-band value   → 0x7C3C stat-label CLUT (dark ink on tan) — RangeTileAtlas.stat_label_colors()
## The sign colours differ per base because the backgrounds differ (bright ink on dark vs
## dark ink on tan); the recolour mechanism is the same. Pure asset + arithmetic, no emulator.

const RangeTileAtlas = preload("res://src/ui3/elements/RangeTileAtlas.gd")
const EquipDeltaPalette = preload("res://src/ui3/detail/EquipDeltaPalette.gd")

var _failed := false


func _ready() -> void:
	# A representative base CLUT (dark-ink-on-tan stat-label palette): index 1·2 = ink body,
	# 4 = the tan background fill/border that MUST survive recolour.
	var atlas := RangeTileAtlas.new()
	var base: Array = atlas.stat_label_colors()
	_expect(base.size() == 16, "stat label base CLUT must have 16 entries, got %d" % base.size())

	var ink := Color8(16, 82, 132)   # arbitrary sign colour (blue)
	var pos: Array = EquipDeltaPalette.recolour(base, ink)
	_expect(pos.size() == 16, "recoloured CLUT must have 16 entries")

	# ONLY the ink indices (1·2) become the sign colour...
	for idx in EquipDeltaPalette.INK_INDICES:
		_col(pos[idx], ink, "ink index %d recoloured to sign colour" % idx)
	# ...every OTHER entry is preserved bit-for-bit from the base (gutter, anti-alias tail,
	# border, and — crucially — the background fill index 4, whose loss was the reported bug).
	for i in 16:
		if i in EquipDeltaPalette.INK_INDICES:
			continue
		_col(pos[i], base[i], "non-ink index %d preserved from base" % i)
	# The digit therefore keeps the plain glyph's border/fill (index 4 unchanged, opaque).
	_expect(pos[4].a > 0.0, "background-fill (index 4) must stay opaque (border preserved)")
	_expect(pos[0].a == 0.0, "gutter (index 0) stays transparent as in the base")

	# The named sign colours the consumers bind.
	_col(EquipDeltaPalette.STATS_BLUE, Color8(16, 82, 132), "STATS_BLUE = FRAME pal-15 [13]")
	_col(EquipDeltaPalette.STATS_RED, Color8(107, 41, 16), "STATS_RED = FRAME pal-15 [9]")
	_col(EquipDeltaPalette.VITALS_CYAN, Color8(96, 208, 232), "VITALS_CYAN = sampled 0x774C")

	# Works on a PackedColorArray base too (MENU_CLUT is packed): recolour bright ink to cyan.
	var menu := PackedColorArray([
		Color8(0, 0, 0, 0), Color8(239, 239, 231), Color8(156, 156, 148),
		Color8(82, 82, 74), Color8(33, 24, 16), Color8(90, 82, 74),
		Color8(123, 123, 115), Color8(140, 132, 115), Color8(165, 156, 132),
		Color8(156, 148, 123), Color8(115, 107, 90), Color8(140, 123, 107),
		Color8(173, 165, 140), Color8(33, 24, 16), Color8(41, 41, 41), Color8(16, 16, 16),
	])
	var vit: Array = EquipDeltaPalette.recolour(menu, EquipDeltaPalette.VITALS_CYAN)
	_col(vit[1], EquipDeltaPalette.VITALS_CYAN, "vitals ink 1 → cyan")
	_col(vit[4], Color8(33, 24, 16), "vitals border index 4 (dark) preserved")

	# The helper hands back a bindable 16×1 CLUT texture (what mount_number takes).
	var tex := EquipDeltaPalette.texture(pos)
	_expect(tex != null and tex.get_width() == 16 and tex.get_height() == 1,
		"CLUT texture must be 16×1")
	if tex != null:
		_col(tex.get_image().get_pixel(1, 0), ink, "CLUT texture pixel 1 = sign colour")
		_col(tex.get_image().get_pixel(4, 0), base[4], "CLUT texture pixel 4 = preserved border")

	if _failed:
		print("[FAIL] EquipDeltaPalette test")
		get_tree().quit(1)
	else:
		print("[PASS] EquipDeltaPalette: recolour ink 1·2 only, plain digit's border/fill preserved")
		get_tree().quit(0)


func _col(got: Color, want: Color, label: String) -> void:
	var g := Vector4i(int(round(got.r * 255)), int(round(got.g * 255)), int(round(got.b * 255)), int(round(got.a * 255)))
	var w := Vector4i(int(round(want.r * 255)), int(round(want.g * 255)), int(round(want.b * 255)), int(round(want.a * 255)))
	if g != w:
		print("[FAIL] %s: got %s want %s" % [label, g, w])
		_failed = true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] " + msg)
		_failed = true
