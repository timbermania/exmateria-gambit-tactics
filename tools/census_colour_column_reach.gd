extends Node
## CAN THE AUTHOR CLICK THE AGE THEY WANT? The vertical colour column packs a row's whole
## dwell into a 22px band — one sub-column per life frame — so a row holding more ages than
## the band has pixels has ages that NO pixel resolves to. `frame_at` floors
## `pos.x / width * ticks`, and a click only ever lands on an integer pixel, so an age is
## reachable only if some integer x maps to it. An unreachable age cannot be selected, so it
## cannot be keyframed: the ⬥ button acts on the SELECTION and there is no other way in.
##
## This is the `[[timeline-grip-swallows-short-spans]]` family — unreachable is not refused,
## and nothing on screen says which ages are which.
##
## Run: <GODOT> --path . --quit-after 3000 res://tools/census_colour_column_reach.tscn

const EffectDataClass = ExMateriaEffects.EffectData
const LifeWindow = preload("res://src/effects/studio/EmitterLifeWindow.gd")
const LifeMap = preload("res://src/effects/studio/SequenceLifeMap.gd")
const LifeColumn = preload("res://src/effects/studio/ColourLifeColumn.gd")
const SequenceTimeline = preload("res://src/effects/studio/SequenceTimeline.gd")

const BAND := 22.0     # ColourLifeColumn.band_width
const ROW_H := 34.0    # SequenceThumbnail.SIDE


func _ready() -> void:
	var emitters := 0
	var any_unreachable := 0
	var lost_total := 0
	var age_total := 0
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
		if ed == null or not (ed.emitters is Array):
			continue
		for i in range(ed.emitters.size()):
			var em = ed.emitters[i]
			if em == null:
				continue
			var ai: int = int(em.anim_index)
			if ai < 0 or not (ed.animations is Array) or ai >= ed.animations.size():
				continue
			var life_n: int = int(LifeWindow.resolve(ed, i).get("n", -1))
			if life_n <= 0:
				continue
			var trace: Array = SequenceTimeline.trace(ed.animations[ai])
			if trace.is_empty():
				continue
			var rows: Array = LifeMap.life_rows(trace, life_n)
			if rows.is_empty():
				continue
			emitters += 1
			var reach := {}
			for x in range(int(BAND)):
				for r in range(rows.size()):
					var f: int = LifeColumn.frame_at(Vector2(float(x), ROW_H * float(r) + 1.0),
						rows, ROW_H, BAND)
					if f >= 0:
						reach[f] = true
			var addressed := 0
			var lost := 0
			for r in rows:
				var start: int = int(r["start"])
				for k in range(int(r["ticks"])):
					addressed += 1
					if not reach.has(start + k):
						lost += 1
			age_total += addressed
			lost_total += lost
			if lost > 0:
				any_unreachable += 1
				worst.append({"n": lost, "s": "%s em%d life=%d rows=%d  %d of %d ages unreachable"
					% [name, i, life_n, rows.size(), lost, addressed]})
	worst.sort_custom(func(a, b): return int(a["n"]) > int(b["n"]))
	print("\n=== COLOUR COLUMN REACH CENSUS (band=%.0fpx) ===" % BAND)
	print("emitters with a life column: %d" % emitters)
	print("emitters with at least one UNREACHABLE age: %d (%.1f%%)"
		% [any_unreachable, 100.0 * float(any_unreachable) / float(maxi(1, emitters))])
	print("life ages total: %d;  unreachable by any click: %d (%.1f%%)"
		% [age_total, lost_total, 100.0 * float(lost_total) / float(maxi(1, age_total))])
	print("worst:")
	for w in worst.slice(0, 12):
		print("   %s" % w["s"])
	get_tree().quit(0)
