extends RefCounted
## The pure freehand-painting core for the Effect Studio curve painter. FFT curves
## are DENSE integer LUTs with no control points, so authoring is a paint gesture,
## not a bezier edit: drag across the grid and each frame-column takes the value
## under the cursor, snapped to the Y-range, with skipped columns interpolated on
## a fast sweep. ONE model, parameterized by Y-range, serves both variants
## (0-255 × 160 lerp curves, 1-9 × 600 time-slow).
##
## Curves are stored normalized 0-1 (EffectCurve.samples); the painter authors in
## the raw integer domain and bridges via curve_to_grid / grid_to_curve.
##
## No `class_name` — preloaded by path (ADR-0004), like the other studio cores.

## Paint one drag segment: fill every integer column between (c0,v0) and (c1,v1)
## with the linearly-interpolated value, clamped to [vmin, vmax]. Mutates `values`
## in place. c0==c1 writes the single column; direction-independent.
static func stroke_segment(values: Array, c0: int, v0: int, c1: int, v1: int,
		vmin: int, vmax: int) -> void:
	var lo: int = mini(c0, c1)
	var hi: int = maxi(c0, c1)
	for c in range(lo, hi + 1):
		if c < 0 or c >= values.size():
			continue
		var t := 0.0 if c1 == c0 else float(c - c0) / float(c1 - c0)
		var v: int = int(round(lerpf(float(v0), float(v1), t)))
		values[c] = clampi(v, vmin, vmax)


## Map a pixel inside the grid rect to a { "col", "val" } cell. X selects the
## column; Y is INVERTED (top of the grid = vmax, bottom = vmin) and snapped into
## the Y-range. Column and value are clamped to their domains.
static func pixel_to_cell(local_pos: Vector2, rect: Rect2, count: int,
		vmin: int, vmax: int) -> Dictionary:
	var fx := 0.0 if rect.size.x <= 0.0 else (local_pos.x - rect.position.x) / rect.size.x
	var col := clampi(int(floor(fx * count)), 0, maxi(0, count - 1))
	var fy := 0.0 if rect.size.y <= 0.0 else (local_pos.y - rect.position.y) / rect.size.y
	fy = clampf(fy, 0.0, 1.0)
	var val := int(round(lerpf(float(vmax), float(vmin), fy)))
	return {"col": col, "val": clampi(val, vmin, vmax)}


## Read an EffectCurve's normalized samples into an integer grid scaled to [0,vmax].
static func curve_to_grid(curve, vmax: int) -> Array:
	var out: Array = []
	for s in curve.samples:
		out.append(clampi(int(round(float(s) * vmax)), 0, vmax))
	return out


## Write an edited integer grid back into an EffectCurve as normalized samples.
static func grid_to_curve(curve, values: Array, vmax: int) -> void:
	curve.samples.resize(values.size())
	for i in range(values.size()):
		curve.samples[i] = clampf(float(values[i]) / float(vmax), 0.0, 1.0)
