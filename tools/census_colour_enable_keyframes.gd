extends Node
## WHAT THE AUTHOR SEES AFTER `Colour: off → on`, censused over the whole corpus.
##
## The toggle's promise is a column to author on. This asks the question the toggle's own
## tooltip does not: once the flag is flipped and any missing curve is minted, HOW MANY OF
## THE IMPORTED KEYFRAMES LAND INSIDE THE PARTICLE'S LIFE — i.e. how many the column can
## actually draw. A Douglas-Peucker fit spans all 160 samples; the column's domain is
## `life_n`, and CONTEXT.md's *Colour dead zone* says those two disagree badly.
##
## Run: <GODOT> --path . --quit-after 3000 res://tools/census_colour_enable_keyframes.tscn

const EffectDataClass = ExMateriaEffects.EffectData
const LifeWindow = preload("res://src/effects/studio/EmitterLifeWindow.gd")
const Fit = preload("res://src/effects/studio/ColourKeyframeFit.gd")
const EffectCurveClass = ExMateriaEffects.EffectCurve


func _ready() -> void:
	var inside: Array = []      # keyframes within life_n, per emitter
	var total: Array = []       # keyframes fitted, per emitter
	var minted := 0
	var only_one := 0
	var zero := 0
	var emitters := 0
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
			if em == null or bool(em.flags.get("color_curve_enabled", false)):
				continue          # already on — the toggle's other direction
			var win: Dictionary = LifeWindow.resolve(ed, i)
			var life_n: int = int(win.get("n", -1))
			if life_n <= 0:
				continue
			emitters += 1
			# Simulate `studio_colour_enable`: a channel that does not resolve is minted
			# FLAT AT 255 (the identity); one that does is left exactly as it is.
			var chans := []
			var did_mint := false
			for ch in ["r", "g", "b"]:
				var c = ed.get_curve(int(em.color_curves.get(ch, -1)))
				if c == null or c.samples.is_empty():
					did_mint = true
					var flat: Array = []
					flat.resize(160)
					flat.fill(1.0)
					c = EffectCurveClass.from_array(flat, -1)
				chans.append(c)
			if did_mint:
				minted += 1
			var kfs: Array = Fit.import_from_curves(chans[0], chans[1], chans[2], life_n)["keyframes"]
			var within := 0
			for kf in kfs:
				if int(kf["frame"]) < life_n:
					within += 1
			inside.append(within)
			total.append(kfs.size())
			if within <= 1:
				only_one += 1
			if within == 0:
				zero += 1
			if kfs.size() - within >= 20:
				worst.append("%s em%d life=%d  %d fitted, %d inside" % [name, i, life_n, kfs.size(), within])
	inside.sort()
	total.sort()
	print("\n=== COLOUR-ENABLE KEYFRAME CENSUS ===")
	print("colour-OFF emitters with a resolvable life: %d  (%d of them would MINT)" % [emitters, minted])
	print("keyframes FITTED   : median %d  mean %.1f  max %d" % [_med(total), _mean(total), total[total.size()-1]])
	print("keyframes IN THE COLUMN (frame < life_n): median %d  mean %.1f  max %d"
		% [_med(inside), _mean(inside), inside[inside.size()-1]])
	print("emitters where the column shows <= 1 keyframe: %d (%.1f%%)  of which ZERO: %d"
		% [only_one, 100.0 * float(only_one) / float(maxi(1, emitters)), zero])
	var hist := {}
	for v in inside:
		hist[v] = int(hist.get(v, 0)) + 1
	var keys := hist.keys()
	keys.sort()
	var line := ""
	for k in keys:
		if int(k) <= 8:
			line += "%d:%d  " % [k, hist[k]]
	print("histogram of keyframes-in-column (0..8): %s" % line)
	print("worst dead-zone cases (>=20 fitted keyframes outside the life): %d" % worst.size())
	for w in worst.slice(0, 12):
		print("   %s" % w)
	get_tree().quit(0)


func _med(a: Array) -> int:
	return 0 if a.is_empty() else int(a[a.size() / 2])


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())
