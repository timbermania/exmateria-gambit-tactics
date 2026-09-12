extends Button
## The Effect Studio **curve-assignment thumbnail picker** (ADR-0089 curve-UX
## amendment) — replaces the opaque `Curve N` OptionButton on a param's Curve row.
## The button FACE shows the shape this use site currently draws as a mini sparkline;
## pressing opens a popup GRID of candidate shapes.
##
## Its verb is **COPY, not reference** since the curve-ownership amendment. There is no
## shared slot left to point at: a pick writes that shape into this
## [use site]'s own curve, and nothing links afterward. So a choice carries its SAMPLES,
## not a table index — the widget is fed the effect's DISTINCT SHAPE SET (median 8 tiles),
## never the post-explode curve array (median 22 entries drawing those same 8 shapes).
## That also makes its tile count the live PSX budget gauge: distinct shapes are exactly
## what the compiler must emit against the ROM's 15 slots.
##
## `none` is a real choice, drawn as the IDENTITY curve — flat at zero, dim. That is not a
## picture chosen to look neutral: with no curve the sim HOLDS THE START VALUES and never
## reads the end ones, so zero at every frame is literally what "none" does. (The label
## used to read "none (linear start→end)" and the glyph was drawn through the
## linear-interpolation path; the sim does no such ramp.)
##
## Thumbnails draw the WHOLE curve un-trimmed (fully bright): the used window belongs to
## the param and is identical for every candidate, so trimming there would mislead. The
## row's own sparkline (which opens the painter) is a distinct, untouched affordance.
##
## Pure Control (web/WASM-safe). No `class_name` (ADR-0004). Reuses EffectCurveSparkline
## Controls for every thumbnail — no texture baking.

const Sparkline = preload("res://src/effects/studio/EffectCurveSparkline.gd")

signal picked(value)

const FACE_SPARK_SIZE := Vector2(40.0, 14.0)
const THUMB_SPARK_SIZE := Vector2(64.0, 28.0)
const GRID_COLS := 4

## The `none` glyph: the identity curve, flat at zero. Two samples are enough to draw a
## line, and the sparkline normalizes for display either way.
const _ZERO_GLYPH := [0.0, 0.0]

## The face value for "a shape that is not one of the offered choices" — negative so it can
## never collide with a real ordinal + 1, and distinct from 0, which IS a choice (`none`).
const OUT_OF_SET := -1

var _choices: Array = []          # [{value, label, samples}] — value 0 = none (identity glyph)
var _value: int = 0
var _provider: Callable = func(_ci): return []
var _face_spark
var _face_label: Label
var _popup: PopupPanel
var _thumbs: Array = []            # the popup thumbnail Sparkline controls (test seam)


## Configure the picker: the `choices` (shape ordinal + 1, label, and the shape's own
## 0-255 samples), the current `value`, and a `provider` kept for the legacy
## index→samples lookup a choice without carried samples still falls back to.
func setup(choices: Array, value: int, provider: Callable) -> void:
	_choices = choices
	_value = value
	_provider = provider
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(128.0, 22.0)
	_build_face()
	pressed.connect(_open_popup)


func _build_face() -> void:
	# Face children ignore the mouse so the whole face stays one click target (the Button).
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.add_theme_constant_override("separation", 6)
	# Small left/right inset so the sparkline + label don't touch the button border.
	hb.offset_left = 6.0
	hb.offset_right = -18.0    # leave room for the ▾ affordance
	_face_spark = Sparkline.new()
	_face_spark.custom_minimum_size = FACE_SPARK_SIZE
	_face_spark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_face_spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(_face_spark)
	_face_label = Label.new()
	_face_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face_label.clip_text = true
	_face_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_face_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(_face_label)
	add_child(hb)
	# A dim ▾ hint pinned to the right so it reads as an openable picker, not a value.
	var caret := Label.new()
	caret.text = "▾"
	caret.modulate = Color(0.6, 0.64, 0.72)
	caret.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caret.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	caret.offset_left = -14.0
	add_child(caret)
	_refresh_face()


func _refresh_face() -> void:
	_face_label.text = _short_label(_value)
	_paint_spark(_face_spark, _value)


## Paint a sparkline for one choice. `none` (<= 0) draws the IDENTITY curve — flat at
## zero, dim — because that is exactly what no curve does to the sim: it holds the start
## values at every frame. A shape draws its WHOLE samples, un-trimmed and bright.
##
## Samples ride ON the choice (the picker copies shapes, so a choice IS its samples). The
## `provider` fallback survives for callers that still hand index-shaped choices.
func _paint_spark(spark, value: int) -> void:
	if value <= 0:
		spark.set_curve(_ZERO_GLYPH, false, -1)
		return
	spark.set_curve(_samples_for(value), true, -1)   # whole-curve, un-trimmed, fully bright


## The 0-255 samples a choice draws, normalized to the sparkline's 0-1 display domain.
func _samples_for(value: int) -> Array:
	for c in _choices:
		if int(c.get("value", 0)) == value and c.has("samples"):
			var raw: Array = Array(c["samples"])
			var out: Array = []
			out.resize(raw.size())
			for i in range(raw.size()):
				out[i] = clampf(float(raw[i]) / 255.0, 0.0, 1.0)
			return out
	var s = _provider.call(value - 1)
	return Array(s) if (s is Array or s is PackedFloat32Array) else []


func _label_for(value: int) -> String:
	for c in _choices:
		if int(c.get("value", 0)) == value:
			return str(c.get("label", str(value)))
	# Out of the offered choices — a shape drawn by nothing else in the effect, so it is not
	# in the distinct set the grid was built from. Name it by what it is rather than by an
	# index (indices are an export concern; a private array position tells an author nothing).
	return "none" if value == 0 else "this shape"


## The compact label used on the face and thumbnails — the choice label with any
## parenthetical stripped ("none (linear start→end)" → "none", "Curve 0" stays),
## so it fits a narrow cell instead of clipping mid-word.
func _short_label(value: int) -> String:
	var full := _label_for(value)
	var paren := full.find(" (")
	return full.substr(0, paren) if paren >= 0 else full


func _build_popup() -> void:
	if _popup != null:
		return
	_popup = PopupPanel.new()
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	var grid := GridContainer.new()
	grid.columns = mini(GRID_COLS, maxi(1, _choices.size()))
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	margin.add_child(grid)
	_popup.add_child(margin)
	for c in _choices:
		var v := int(c.get("value", 0))
		grid.add_child(_build_thumb(v))
	add_child(_popup)


## One popup thumbnail: a flat Button wrapping [whole-curve sparkline, short label];
## pressing it chooses that value. Fixed min size so the grid columns lay out instead
## of collapsing (which stacked the labels). The sparkline is recorded for the test seam.
func _build_thumb(v: int) -> Control:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(THUMB_SPARK_SIZE.x + 12.0, THUMB_SPARK_SIZE.y + 24.0)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 2)
	var spark = Sparkline.new()
	spark.custom_minimum_size = THUMB_SPARK_SIZE
	spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paint_spark(spark, v)
	vb.add_child(spark)
	var lbl := Label.new()
	lbl.text = _short_label(v)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The currently-assigned curve reads as selected.
	if v == _value:
		lbl.modulate = Color(0.55, 0.80, 0.95)
	vb.add_child(lbl)
	b.add_child(vb)
	b.pressed.connect(func(): _choose(v))
	_thumbs.append(spark)
	return b


func _open_popup() -> void:
	_build_popup()
	_popup.popup(Rect2i(Vector2i(get_screen_position()) + Vector2i(0, int(size.y)), Vector2i.ZERO))


## Choose a value: update the face, close the popup, and fan the pick. This is
## exactly what a thumbnail press runs; `pick()` exposes it as a test seam.
func _choose(v: int) -> void:
	_value = v
	_refresh_face()
	if _popup:
		_popup.hide()
	picked.emit(v)


# --- test / host seams -----------------------------------------------------

## Programmatic selection (what a thumbnail press runs). Test seam.
func pick(value: int) -> void:
	_choose(value)


## The current choice value (shape ordinal + 1; 0 = none).
func current_value() -> int:
	return _value


## Re-sync the face to one of the OFFERED choices WITHOUT fanning a pick. Distinct from
## `pick()` (which emits `picked`).
func set_value(value: int) -> void:
	_value = value
	_refresh_face()


## Show a shape the offered set does NOT contain, without fanning a pick — the live
## in-place refresh after an edit rewrites this use site's curve into something no other
## use site draws, which is the normal outcome of authoring: the grid was built from the
## effect's distinct shapes as they were, and this one is new. Painting the face from the
## samples keeps it honest instead of leaving it on the shape it used to draw.
func show_shape(normalized_samples: Array) -> void:
	_value = OUT_OF_SET
	if _face_label:
		_face_label.text = _short_label(_value)
	if _face_spark:
		_face_spark.set_curve(normalized_samples, true, -1)


## The button-face mini-sparkline (shows the assigned curve).
func face_sparkline():
	return _face_spark


## The face label text (short form — no clipped parenthetical). Test seam.
func face_label_text() -> String:
	return _face_label.text if _face_label else ""


## The popup thumbnail sparklines (built lazily). Test seam — asserts they are
## whole-curve (un-trimmed).
func thumbnails() -> Array:
	_build_popup()
	return _thumbs
