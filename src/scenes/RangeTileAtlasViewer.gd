extends Node2D

## Viewer for the feedback-HUD sprites (#88) — NOT a test (it asserts nothing;
## see tests/RangeTileAtlasTest.gd for the assertions). Lays out the full
## damage-digit row (0-9 + '/'), the ROM-authoritative word-labels
## (Hp/Mp/Ct/Lv./Exp.) and the 20 status-bubble icons from RangeTileAtlas /
## RANGETILE.json, scaled up, so the extracted cells can be eyeballed (e.g. that
## no digit is clipped and each label is its full glyph). Stays open — close the
## window to exit. Press S to save a PNG.

const RangeTileAtlas = preload("res://src/ui3/elements/RangeTileAtlas.gd")

const DIGIT_SCALE := 7.0
const LABEL_SCALE := 7.0
const ICON_SCALE := 5.0
const BRIGHTEN := Color(6, 6, 6)   # the indexed grays are dim; multiply up


func _ready() -> void:
	var atlas := RangeTileAtlas.new()

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.12)
	bg.size = Vector2(980, 600)
	add_child(bg)

	_label("Damage / HP digits  (0-9  /)", Vector2(20, 12))
	var x := 20.0
	for i in atlas.digit_glyphs().length():
		var glyph := atlas.digit_glyphs()[i]
		_cell(atlas, atlas.digit_rect(glyph), Vector2(x, 36), DIGIT_SCALE)
		x += atlas.digit_rect(glyph).size.x * DIGIT_SCALE + 6

	_label("Word labels (vitals readout, ROM cells)", Vector2(20, 170))
	x = 20.0
	for name in ["Hp", "Mp", "Ct", "Lv.", "Exp."]:
		if not atlas.has_label(name):
			continue
		var lr := atlas.label_rect(name)
		_cell(atlas, lr, Vector2(x, 198), LABEL_SCALE)
		_label(name, Vector2(x, 198 + lr.size.y * LABEL_SCALE + 4))
		x += lr.size.x * LABEL_SCALE + 24

	_label("HP/MP/CT bars: swatch + per-stat CLUT body shades (idx1-3)", Vector2(20, 300))
	_cell(atlas, atlas.bar_swatch_rect(), Vector2(20, 326), 4.0)  # the grey swatch
	for i in atlas.bar_stat_count():
		var cols := atlas.bar_stat_colors(i)
		var bx := 220.0 + i * 230.0
		_label(atlas.bar_stat_name(i), Vector2(bx, 326))
		for k in range(1, 4):  # body shades idx1..3
			if k < cols.size():
				var chip := ColorRect.new()
				chip.color = cols[k]
				chip.size = Vector2(40, 28)
				chip.position = Vector2(bx + 50 + (k - 1) * 44, 322)
				add_child(chip)

	_label("Status / charge icons  (20)", Vector2(20, 380))
	for i in atlas.status_icon_count():
		var rect := atlas.status_icon_rect(i)
		var col := i % 10
		var row := i / 10
		var pos := Vector2(20 + col * (rect.size.x * ICON_SCALE + 8),
						   410 + row * (rect.size.y * ICON_SCALE + 8))
		_cell(atlas, rect, pos, ICON_SCALE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_S:
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://rangetile_atlas_viewer.png")
		print("[VIEWER] saved user://rangetile_atlas_viewer.png")


func _cell(atlas: RangeTileAtlas, rect: Rect2, pos: Vector2, scale: float) -> void:
	var s := Sprite2D.new()
	s.texture = atlas.cell_atlas_texture(rect)
	s.centered = false
	s.position = pos
	s.scale = Vector2(scale, scale)
	s.self_modulate = BRIGHTEN
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(s)


func _label(text: String, pos: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	add_child(l)
