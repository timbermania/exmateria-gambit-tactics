extends Node
## CAN THE AUTHOR RECOGNISE THE SPRITE IN A RAIL TILE?
##
## `RegionFramesetRail` fits every tile into ONE shared bounds box, the rule
## `SequenceTimeline.bounds` exists to enforce — so two framesets that differ only in where
## the sprite sits draw as the same picture rather than each re-centring into a duplicate.
## That rule came from the sequence strip, where the row is one animation over time.
##
## The rail's row is different: it is a REGION's framesets, and the author's job there is to
## RECOGNISE each one well enough to tick it. A frame quad is a transform (ADR-0099 dec. 3
## amended), so members of one region are routinely the same sheet texels drawn at wildly
## different scales — E317 frameset 15's region is 33x33 beside five sprites 5px tall, which
## fitted into the shared 48x33 box occupy 15% of the tile's height.
##
## This measures both: the SHARED-box share a tile used to get, and the pixel extent it
## actually draws at now that each tile is fit to its OWN bounds. The second number is the
## honest residual — fitting to its own box cannot rescue an extreme ASPECT RATIO, and the
## corpus has 244x4 beams that are a sub-pixel line in any square tile.
##
## Run: <GODOT> --path . --quit-after 3000 res://tools/census_rail_tile_legibility.tscn

const EffectDataClass = ExMateriaEffects.EffectData
const SequenceTimeline = preload("res://src/effects/studio/SequenceTimeline.gd")
const RegionScope = preload("res://src/effects/studio/FramesetRegionScope.gd")

## The inner extent of a 40px tile after `_draw`'s 2px grow — a mid-range tile size.
const INNER := 36.0
const Canvas = preload("res://src/effects/studio/FramesetCanvas.gd")


func _ready() -> void:
	var rows := 0
	var tiles := 0
	var thin := 0            # WAS: tile covers < 25% of the shared box in EITHER axis
	var very_thin := 0       # WAS: < 10%
	var still_thin := 0      # NOW: draws under 2px in its own box, at a 40px tile
	var aspect_bad := 0      # ...and its own aspect ratio is why (>= 12:1)
	var rows_with_thin := 0
	var worst: Array = []
	var d := DirAccess.open("res://assets/effects")
	if d == null:
		print("NO CORPUS"); get_tree().quit(1); return
	var names: Array = []
	for n in d.get_directories():
		names.append(n)
	names.sort()
	for name in names:
		var ed = EffectDataClass.load_from_directory("res://assets/effects/%s" % name)
		if ed == null or not (ed.framesets is Array):
			continue
		var seen := {}
		for fs_i in range(ed.framesets.size()):
			var fs = ed.framesets[fs_i]
			var frames: Array = (fs.get("frames", []) if fs is Dictionary else [])
			for reg in Canvas.group_regions(frames):
				var members: Array = Canvas.region_members(ed.framesets, reg["block"])
				var row: Array = RegionScope.distinct_framesets(members)
				if row.size() < 2:
					continue
				var key: String = str(row)
				if seen.has(key):
					continue
				seen[key] = true
				var entries: Array = []
				for f in row:
					entries.append({"frameset": int(f), "offset": Vector2i.ZERO, "has_sprite": true})
				var shared: Rect2 = SequenceTimeline.bounds(entries, ed.framesets)
				if shared.size.x <= 0.0 or shared.size.y <= 0.0:
					continue
				rows += 1
				var row_thin := 0
				for f in row:
					var one: Rect2 = SequenceTimeline.bounds(
						[{"frameset": int(f), "offset": Vector2i.ZERO, "has_sprite": true}],
						ed.framesets)
					tiles += 1
					var fx: float = one.size.x / shared.size.x
					var fy: float = one.size.y / shared.size.y
					var m: float = minf(fx, fy)
					if m < 0.25:
						thin += 1
						row_thin += 1
					if m < 0.10:
						very_thin += 1
					# NOW: fit to its OWN box in a 40px tile (inner 36 after the 2px grow).
					if one.size.x > 0.0 and one.size.y > 0.0:
						var sc: float = minf(INNER / one.size.x, INNER / one.size.y)
						if minf(one.size.x, one.size.y) * sc < 2.0:
							still_thin += 1
						var ar: float = maxf(one.size.x, one.size.y) / minf(one.size.x, one.size.y)
						if ar >= 12.0:
							aspect_bad += 1
				if row_thin > 0:
					rows_with_thin += 1
					worst.append({"n": row_thin, "s": "%s fs%d: %d of %d tiles under 25%% (shared %.0fx%.0f)"
						% [name, fs_i, row_thin, row.size(), shared.size.x, shared.size.y]})
	worst.sort_custom(func(a, b): return int(a["n"]) > int(b["n"]))
	print("\n=== RAIL TILE LEGIBILITY CENSUS ===")
	print("multi-frameset region rows: %d   tiles across them: %d" % [rows, tiles])
	print("rows with at least one tile under 25%% of the shared box: %d (%.1f%%)"
		% [rows_with_thin, 100.0 * float(rows_with_thin) / float(maxi(1, rows))])
	print("WAS (shared box) — tiles under 25%%: %d (%.1f%%)   under 10%%: %d (%.1f%%)"
		% [thin, 100.0 * float(thin) / float(maxi(1, tiles)),
			very_thin, 100.0 * float(very_thin) / float(maxi(1, tiles))])
	print("NOW (own box, 40px tile) — still drawing under 2px: %d (%.1f%%)"
		% [still_thin, 100.0 * float(still_thin) / float(maxi(1, tiles))])
	print("   of which the sprite's OWN aspect is >= 12:1 (unfixable by any fit): %d (%.1f%%)"
		% [aspect_bad, 100.0 * float(aspect_bad) / float(maxi(1, tiles))])
	print("worst rows:")
	for w in worst.slice(0, 10):
		print("   %s" % w["s"])
	get_tree().quit(0)
