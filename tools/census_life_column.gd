extends Node
## THE LIFE COLUMN, censused — how many ROWS the vertical colour column has to draw, and
## how the corpus splits across the three ways an animation covers a particle's life
## (one pass, parks on a terminal frame, or loops). The instrument behind ADR-0089's
## vertical-column amendment.
##
## Run: <GODOT> --path . --quit-after 3000 res://tools/census_life_column.tscn

const EffectDataClass = ExMateriaEffects.EffectData
const LifeWindow = preload("res://src/effects/studio/EmitterLifeWindow.gd")
const LifeMap = preload("res://src/effects/studio/SequenceLifeMap.gd")
const SequenceTimeline = preload("res://src/effects/studio/SequenceTimeline.gd")


func _ready() -> void:
	var rows_n: Array = []
	var cols_per_row: Array = []
	var strip_cells: Array = []
	var looped := 0
	var parked := 0
	var died := 0
	var one_pass := 0
	var emitters := 0
	var names: Array = []
	var d := DirAccess.open("res://assets/effects")
	if d == null:
		print("NO CORPUS")
		get_tree().quit(1)
		return
	for n in d.get_directories():
		names.append(n)
	names.sort()
	for name in names:
		var ed = EffectDataClass.load_from_directory("res://assets/effects/%s" % name)
		if ed == null or not (ed.emitters is Array):
			continue
		for i in range(ed.emitters.size()):
			var em = ed.emitters[i]
			if em == null or not _colour_enabled(ed, em):
				continue
			var ai: int = int(em.anim_index)
			if ai < 0 or ai >= ed.animations.size():
				continue
			var trace: Array = SequenceTimeline.trace(ed.animations[ai])
			if trace.is_empty():
				continue
			var life_n: int = int(LifeWindow.for_emitter(em, ed)["n"])
			if life_n <= 0:
				continue
			var rows: Array = LifeMap.life_rows(trace, life_n)
			if rows.is_empty():
				continue
			emitters += 1
			rows_n.append(rows.size())
			strip_cells.append(trace.size())
			for r in rows:
				cols_per_row.append(int(r["ticks"]))
			# which of the three shapes
			var seen: Dictionary = {}
			var repeat := false
			for r in rows:
				var c: int = int(r["cell"])
				if seen.has(c):
					repeat = true
				seen[c] = true
			var last_row_cell: int = int(rows[rows.size() - 1]["cell"])
			var last_terminal: bool = bool(trace[last_row_cell].get("is_terminal", false))
			var reached_all: bool = seen.size() >= _occupied(trace)
			if repeat:
				looped += 1
			elif last_terminal and int(rows[rows.size() - 1]["ticks"]) > int(trace[last_row_cell].get("ticks", 1)):
				parked += 1
			elif not reached_all:
				died += 1
			else:
				one_pass += 1
	print("=== LIFE COLUMN CENSUS ===")
	print("colour emitters with a resolvable animation + window: %d" % emitters)
	_stat("ROWS in the column (what the vertical strip instantiates)", rows_n)
	_stat("today's strip CELLS (the trace, laid out by opcode)", strip_cells)
	_stat("COLUMNS per row (life frames one thumbnail holds)", cols_per_row)
	var one_col := 0
	for c in cols_per_row:
		if int(c) == 1:
			one_col += 1
	print("  rows that are ONE column (a single life frame): %d of %d (%.1f%%)"
		% [one_col, cols_per_row.size(), 100.0 * one_col / maxi(1, cols_per_row.size())])
	print("how the animation covers the life:")
	print("  one clean pass            : %d (%.1f%%)" % [one_pass, 100.0 * one_pass / maxi(1, emitters)])
	print("  LOOPS (a cell recurs)     : %d (%.1f%%)" % [looped, 100.0 * looped / maxi(1, emitters)])
	print("  PARKS on a terminal frame : %d (%.1f%%)" % [parked, 100.0 * parked / maxi(1, emitters)])
	print("  particle DIES mid-animation: %d (%.1f%%)" % [died, 100.0 * died / maxi(1, emitters)])
	get_tree().quit(0)


func _stat(label: String, a: Array) -> void:
	if a.is_empty():
		print("%s: none" % label)
		return
	a.sort()
	print("%s: median %d  p90 %d  p99 %d  max %d"
		% [label, a[a.size() / 2], a[int(a.size() * 0.9)], a[int(a.size() * 0.99)], a[a.size() - 1]])


func _occupied(trace: Array) -> int:
	var n := 0
	for c in trace:
		if c is Dictionary and int(c.get("ticks", 0)) > 0:
			n += 1
	return n


func _colour_enabled(ed, em) -> bool:
	if not bool(em.flags.get("color_curve_enabled", false)):
		return false
	for ch in ["r", "g", "b"]:
		var c = ed.get_curve(int(em.color_curves.get(ch, -1)))
		if c == null or c.samples.is_empty():
			return false
	return true
