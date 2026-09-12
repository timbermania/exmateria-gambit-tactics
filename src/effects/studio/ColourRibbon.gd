extends Control
## Colour ribbon — the read-only resolved-colour bar drawn under an emitter's three
## R/G/B colour sparklines in the keyframe inspector (CONTEXT.md "Colour ribbon"). It
## answers "what colour is the particle at each point in its life?" — the clarity the
## three abstract per-channel wiggles don't give.
##
## A PURE VIEW: no storage, no edit session, no save — the host re-feeds it on the
## existing curve_changed path. It resolves each frame through EffectCurve.sample_rgb,
## the SAME source the particle renderer paints with, so the preview can never drift
## from the render path. Opaque RGB only — particle transparency is a separate per-frame
## flag (semi_trans_on) the colour curves don't drive, so it stays out of the ribbon.
## HIDDEN entirely when the emitter's colour is disabled (draws nothing).
##
## Web/WASM-safe pure Control; no `class_name` (ADR-0004), preloaded by path.

const EffectCurveClass = ExMateriaEffects.EffectCurve
const Sparkline = preload("res://src/effects/studio/EffectCurveSparkline.gd")

const RIBBON_HEIGHT := 10.0
const RULER_HEIGHT := 12.0
# The studio ruler-step ladder (shared with EffectFramesBar): pick the smallest step whose
# on-screen spacing is at least this many pixels.
const RULER_LADDER := [1, 5, 10, 30, 60, 120, 300, 600]
const RULER_MIN_PX := 48.0
const COL_RULER := Color(0.62, 0.66, 0.74, 0.85)

var _cr = null
var _cg = null
var _cb = null
var _enabled: bool = false
var _used_n: int = -1
var _show_ruler: bool = false
var _sprite_base: Color = Color.WHITE  # the emitter's representative sprite colour muxed into each band


func _init() -> void:
	custom_minimum_size = Vector2(52.0, RIBBON_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # a passive read-out, never a click target


## The OPAQUE per-frame colours, windowed to the used region when `trim` is on so the
## band count equals EffectCurveSparkline.windowed_samples for the same window — the
## strip is drawn at half the section's width, left-aligned, so its pixel columns no
## longer align 1:1 with the full-width sparklines. Pure; reads EffectCurve.sample_rgb.
## `sprite_base` is the emitter's representative sprite colour (EmitterSpriteColor): the ribbon
## MULTIPLIES the resolved curve colour by it, mirroring the renderer's `ALBEDO = col.rgb *
## COLOR.rgb` (effect_particle_opaque.gdshader) so the bar shows the colour the particle
## actually IS, not the pure curve. White (the default) is the identity — a sprite that can
## show any colour, so the ribbon is the raw curve.
static func frame_colors(cr, cg, cb, used_n: int, trim: bool, sprite_base: Color = Color.WHITE) -> Array:
	var n := _frame_count(used_n, trim)
	var out: Array = []
	out.resize(n)
	for f in range(n):
		var c: Color = EffectCurveClass.sample_rgb(cr, cg, cb, f)
		# The multiplicative mux: a sprite channel of 0 can never light up (the E138 green case).
		out[f] = Color(c.r * sprite_base.r, c.g * sprite_base.g, c.b * sprite_base.b, 1.0)
	return out


## The band count: the used window's leading N frames when trimming (mirroring
## windowed_samples: maxi(N, 2)), else the whole 160-frame curve. A wrapping (>=160)
## or animation-driven (-1) window also falls back to the whole curve.
static func _frame_count(used_n: int, trim: bool) -> int:
	if trim and used_n > 0 and used_n < 160:
		return maxi(used_n, 2)
	return 160


## Feed the three per-channel curves + the emitter's colour-enabled state + the used
## window (the particle-age lifetime). `show_ruler` draws a frame-number ruler under the
## bands. Disabled (or any curve missing) ⇒ hidden.
func set_curves(cr, cg, cb, enabled: bool, used_n: int = -1, show_ruler: bool = false,
		sprite_base: Color = Color.WHITE) -> void:
	_cr = cr
	_cg = cg
	_cb = cb
	_enabled = enabled and cr != null and cg != null and cb != null
	_used_n = used_n
	_show_ruler = show_ruler
	_sprite_base = sprite_base
	custom_minimum_size = Vector2(52.0, RIBBON_HEIGHT + (RULER_HEIGHT if show_ruler else 0.0))
	visible = _enabled
	queue_redraw()


## True when the frame ruler is drawn under the colour bands. Test seam.
func has_frame_ruler() -> bool:
	return _show_ruler


## The particle-age window count + representative sprite base the ribbon was last fed — so a
## live in-place recolour (colour-keyframe authoring) can re-feed set_curves with the emitter's
## new (forked) curves while keeping the same axis + mux.
func used_n() -> int:
	return _used_n


func sprite_base() -> Color:
	return _sprite_base


## The smallest ruler-step whose pixel spacing (width ÷ n frames) is ≥ RULER_MIN_PX — the
## same ladder the studio frames-bar uses. Pure; a test seam.
static func ruler_step(n: int, width: float) -> int:
	if n <= 0:
		return 1
	var ppf := width / float(n)
	for c in RULER_LADDER:
		if float(c) * ppf >= RULER_MIN_PX:
			return c
	return RULER_LADDER[-1]


## The interior tick frames (0, step, 2·step, … below n). n itself is drawn as its own end
## marker, so it is excluded here. Pure; a test seam.
static func ruler_ticks(n: int, width: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	if n <= 0:
		return out
	var step := ruler_step(n, width)
	var f := 0
	while f < n:
		out.append(f)
		f += step
	return out


## True when the ribbon draws (colour enabled + all three curves present). Test seam.
func is_shown() -> bool:
	return _enabled


## The colours _draw paints — honouring the GLOBAL trim toggle (display_trim_width) the
## sparklines read, so the ribbon and the curves above it rescale together. A test seam
## AND the single source _draw reads, so the toggle and the render never diverge.
func colors() -> Array:
	if not _enabled:
		return []
	return frame_colors(_cr, _cg, _cb, _used_n, Sparkline.display_trim_width, _sprite_base)


func _draw() -> void:
	if not _enabled:
		return
	var cols := colors()
	var n := cols.size()
	if n <= 0:
		return
	var sz := size
	var bar_h := RIBBON_HEIGHT if _show_ruler else sz.y
	for i in range(n):
		# Compute both edges from the same ratio so adjacent bands share a seam (no
		# rounding gaps): band i spans [x_i, x_{i+1}).
		var x0 := sz.x * float(i) / float(n)
		var x1 := sz.x * float(i + 1) / float(n)
		draw_rect(Rect2(x0, 0.0, x1 - x0, bar_h), cols[i])
	if _show_ruler:
		_draw_ruler(sz, n, bar_h)


## Tick marks + frame numbers under the bands (frame f sits at the left edge of band f, so
## the ruler lines up with the colours above it). The end marker labels the total frame count.
func _draw_ruler(sz: Vector2, n: int, top: float) -> void:
	var font := get_theme_default_font()
	var fs := 8
	for f in ruler_ticks(n, sz.x):
		var x := sz.x * float(f) / float(n)
		draw_line(Vector2(x, top), Vector2(x, top + 3.0), COL_RULER, 1.0)
		if font != null:
			draw_string(font, Vector2(x + 2.0, top + RULER_HEIGHT), str(f),
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, COL_RULER)
	# End marker: a tick + the total count at the right edge (the particle's lifespan).
	draw_line(Vector2(sz.x - 0.5, top), Vector2(sz.x - 0.5, top + 3.0), COL_RULER, 1.0)
	if font != null:
		var label := str(n)
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
		draw_string(font, Vector2(sz.x - w - 1.0, top + RULER_HEIGHT), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, COL_RULER)
