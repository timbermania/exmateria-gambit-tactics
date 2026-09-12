extends Node
## HOW WIDE CAN A ROW ACTUALLY BE? The vertical colour column splits a row's dwell into one
## sub-column per life frame across a band fixed at 22px, so a row holding `t` ages draws
## each at `22/t`. Author: *"for sprites which are just one frame and held things get crazy
## on the keyframes — can we maybe do a minimum width keyframes?"*
##
## The band is 22 because that is what THREE pairs can afford inside the slot the page
## declares once at build (`sequence_life_slot_w(3)` = 198px, and 198 - scrollbar over three
## pairs minus the 34px thumbnail and its 2px gap is exactly 22). The slot's width is
## constant on purpose — a per-emitter bid would move the inspector's right edge on every
## click. But a strip that WRAPS INTO FEWER PAIRS leaves that declared width unused, and the
## arithmetic that makes this land is `rows * ticks ~= life_n`: a row is wide exactly when
## there are few rows, which is exactly when there are spare pairs.
##
## Run: <GODOT> --path . --quit-after 5000 res://tools/census_colour_column_width.tscn

const EffectDataClass = ExMateriaEffects.EffectData
const LifeWindow = preload("res://src/effects/studio/EmitterLifeWindow.gd")
const LifeMap = preload("res://src/effects/studio/SequenceLifeMap.gd")
const SequenceTimeline = preload("res://src/effects/studio/SequenceTimeline.gd")
const Page = preload("res://src/effects/studio/EffectStudioPage.gd")

const BAND := 22.0
const KF_W := 3.0
const THUMB := 34.0
const STRIP_SEP := 2.0
const COL_SEP := 6.0
const SCROLLBAR := 12.0
const SLOT := 198.0    # sequence_life_slot_w(3)

var _rows_of: Array = []    # [rows, widest_ticks] per emitter


func _ready() -> void:
	_collect()
	var rowcount: Array = []
	var widest: Array = []
	for e in _rows_of:
		rowcount.append(int(e[0]))
		widest.append(int(e[1]))
	_report("rows per emitter", rowcount)
	_report("widest row per emitter (ticks)", widest)

	print("\n=== THE BAND A WRAP LEAVES ON THE FLOOR ===")
	print("  pairs visible ->  band affordable inside the SAME 198px slot")
	for c in [1, 2, 3]:
		print("    %d pair%s: %6.1f px" % [c, "" if c == 1 else "s", _band_max(c)])

	for cap in [6, 12, 20]:
		print("\n=== CAPACITY %d ROWS PER COLUMN ===" % cap)
		var today: Array = []
		var fixed: Array = []
		var reach_today := 0
		var reach_fixed := 0
		var n := 0
		var still_short: Array = []
		for e in _rows_of:
			var rows: int = int(e[0])
			var t: int = maxi(1, int(e[1]))
			var cols: int = int(Page.strip_columns(rows, cap, 3).get("cols", 1))
			var grown: float = clampf(5.0 * float(t), BAND, _band_max(cols))
			n += 1
			today.append(int(round(BAND / float(t) * 100.0)))
			fixed.append(int(round(grown / float(t) * 100.0)))
			# An age is reachable only if some integer pixel floors to it: width >= ticks.
			if BAND >= float(t):
				reach_today += 1
			if grown >= float(t):
				reach_fixed += 1
			else:
				still_short.append({"n": t, "s": "ticks=%d rows=%d cols=%d band=%.0f -> %.2f px/age"
					% [t, rows, cols, grown, grown / float(t)]})
		_report_100("px per age TODAY (x100)", today)
		_report_100("px per age with min 5px into the slack (x100)", fixed)
		print("  every age reachable:  today %d of %d (%.1f%%)   grown %d of %d (%.1f%%)"
			% [reach_today, n, 100.0 * float(reach_today) / float(n),
				reach_fixed, n, 100.0 * float(reach_fixed) / float(n)])
		still_short.sort_custom(func(a, b): return int(a["n"]) > int(b["n"]))
		for s in still_short.slice(0, 4):
			print("    still short: %s" % s["s"])
	get_tree().quit(0)


## The widest band `c` visible pairs can take inside the declared slot.
func _band_max(c: int) -> float:
	var usable: float = SLOT - SCROLLBAR - COL_SEP * float(c - 1)
	return maxf(BAND, usable / float(c) - THUMB - STRIP_SEP)


func _collect() -> void:
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
			var mx := 1
			for r in rows:
				mx = maxi(mx, maxi(1, int(r.get("ticks", 1))))
			_rows_of.append([rows.size(), mx])


func _report(label: String, v: Array) -> void:
	var s: Array = v.duplicate()
	s.sort()
	print("\n%s: n=%d  min=%d  median=%d  p75=%d  p90=%d  p95=%d  p99=%d  max=%d"
		% [label, s.size(), int(s[0]), int(s[s.size() / 2]),
			int(s[mini(s.size() - 1, s.size() * 3 / 4)]),
			int(s[mini(s.size() - 1, s.size() * 9 / 10)]),
			int(s[mini(s.size() - 1, s.size() * 95 / 100)]),
			int(s[mini(s.size() - 1, s.size() * 99 / 100)]), int(s[s.size() - 1])])


func _report_100(label: String, v: Array) -> void:
	var s: Array = v.duplicate()
	s.sort()
	print("  %-46s p1=%.2f  p5=%.2f  p10=%.2f  median=%.2f  min=%.2f"
		% [label, float(s[maxi(0, s.size() / 100)]) / 100.0,
			float(s[maxi(0, s.size() * 5 / 100)]) / 100.0,
			float(s[maxi(0, s.size() / 10)]) / 100.0,
			float(s[s.size() / 2]) / 100.0, float(s[0]) / 100.0])
