extends Node
## HOW SHOULD THE KEYFRAME BUDGET BE SPENT? Three fits compared on every colour emitter.
##
##  (a) GLOBAL   — today: one Douglas-Peucker over all 160 samples, budget 24.
##  (b) WINDOW   — refit to [0, life_n) only. CONTEXT.md's *Colour dead zone* _Avoid_ list
##                 rejects this: `apply()` compiles all 160 from the keyframes, so the dead
##                 samples go flat and bytes are rewritten.
##  (c) SPLIT    — DP over [0, life_n-1] and DP over [life_n-1, 159] with a budget EACH,
##                 sharing the boundary point. Nothing truncated, nothing flattened, and the
##                 live window can no longer be starved by the dead zone.
##
## Reported per region, because the two are consumed differently: the live residual is the
## only error that RENDERS; the dead residual is what `apply()` would rewrite.
##
## Run: <GODOT> --path . --quit-after 3000 res://tools/census_colour_fit_window.tscn

const EffectDataClass = ExMateriaEffects.EffectData
const LifeWindow = preload("res://src/effects/studio/EmitterLifeWindow.gd")
const Fit = preload("res://src/effects/studio/ColourKeyframeFit.gd")
const ColourMux = preload("res://src/effects/studio/ColourMux.gd")
const SpriteColor = preload("res://src/effects/studio/EmitterSpriteColor.gd")

const EPS := 0.5 / 255.0
const BUDGET := 24


func _ready() -> void:
	var n_em := 0
	var live_g: Array = []; var live_w: Array = []; var live_s: Array = []
	var dead_g: Array = []; var dead_s: Array = []
	var kf_g: Array = []; var kf_s: Array = []
	var in_g: Array = []; var in_s: Array = []
	var rescued := 0
	var d := DirAccess.open("res://assets/effects")
	if d == null:
		print("NO CORPUS"); get_tree().quit(1); return
	var names: Array = []
	for nm in d.get_directories():
		names.append(nm)
	names.sort()
	for name in names:
		var ed = EffectDataClass.load_from_directory("res://assets/effects/%s" % name)
		if ed == null or not (ed.emitters is Array):
			continue
		for i in range(ed.emitters.size()):
			var em = ed.emitters[i]
			if em == null:
				continue
			var life_n: int = int(LifeWindow.resolve(ed, i).get("n", -1))
			if life_n <= 1 or life_n >= 160:
				continue
			var chans := []
			var ok := true
			for ch in ["r", "g", "b"]:
				var c = ed.get_curve(int(em.color_curves.get(ch, -1)))
				if c == null or c.samples.is_empty():
					ok = false
					break
				chans.append(c)
			if not ok:
				continue
			n_em += 1
			var s: Color = SpriteColor.representative(ed, i)
			var full: Array = []
			for f in range(160):
				full.append(ColourMux.mux(Color(chans[0].sample_by_frame(f),
					chans[1].sample_by_frame(f), chans[2].sample_by_frame(f), 1.0), s))

			var g: Array = Fit._douglas_peucker(full, EPS, BUDGET)
			var w: Array = Fit._douglas_peucker(full.slice(0, life_n), EPS, BUDGET)
			var sp: Array = _split(full, life_n, EPS, BUDGET)

			live_g.append(_res(full, g, 0, life_n))
			live_w.append(_res(full, w, 0, life_n))
			live_s.append(_res(full, sp, 0, life_n))
			dead_g.append(_res(full, g, life_n, 160))
			dead_s.append(_res(full, sp, life_n, 160))
			kf_g.append(g.size()); kf_s.append(sp.size())
			var a := _count_in(g, life_n)
			var b := _count_in(sp, life_n)
			in_g.append(a); in_s.append(b)
			if a <= 1 and b > 1:
				rescued += 1
	for a in [live_g, live_w, live_s, dead_g, dead_s, kf_g, kf_s, in_g, in_s]:
		a.sort()
	print("\n=== COLOUR FIT BUDGET CENSUS (%d emitters) ===" % n_em)
	print("keyframes INSIDE the life   global: median %d mean %.2f | split: median %d mean %.2f"
		% [_med(in_g), _mean(in_g), _med(in_s), _mean(in_s)])
	print("  emitters going from <=1 keyframe in the live window to more: %d (%.1f%%)"
		% [rescued, 100.0 * float(rescued) / float(maxi(1, n_em))])
	print("LIVE residual (the only error that renders)")
	print("  global: median %.4f p90 %.4f max %.4f" % [_med(live_g), _p90(live_g), live_g[live_g.size()-1]])
	print("  window: median %.4f p90 %.4f max %.4f" % [_med(live_w), _p90(live_w), live_w[live_w.size()-1]])
	print("  split : median %.4f p90 %.4f max %.4f" % [_med(live_s), _p90(live_s), live_s[live_s.size()-1]])
	print("DEAD residual (what apply() would rewrite; WINDOW flattens it entirely)")
	print("  global: median %.4f p90 %.4f max %.4f" % [_med(dead_g), _p90(dead_g), dead_g[dead_g.size()-1]])
	print("  split : median %.4f p90 %.4f max %.4f" % [_med(dead_s), _p90(dead_s), dead_s[dead_s.size()-1]])
	print("total keyframes  global: median %d max %d | split: median %d max %d"
		% [_med(kf_g), kf_g[kf_g.size()-1], _med(kf_s), kf_s[kf_s.size()-1]])
	get_tree().quit(0)


## DP over [0, life_n-1] and [life_n-1, 159] with a budget EACH, sharing the boundary.
func _split(full: Array, life_n: int, eps: float, budget: int) -> Array:
	var b: int = clampi(life_n - 1, 0, full.size() - 1)
	var head: Array = Fit._douglas_peucker(full.slice(0, b + 1), eps, budget)
	var tail: Array = Fit._douglas_peucker(full.slice(b), eps, budget)
	var keep := {}
	for f in head:
		keep[int(f)] = true
	for f in tail:
		keep[int(f) + b] = true
	var out := keep.keys()
	out.sort()
	return out


func _count_in(kept: Array, life_n: int) -> int:
	var c := 0
	for f in kept:
		if int(f) < life_n:
			c += 1
	return c


## Max per-channel residual of the kept polyline against the truth over [lo, hi).
func _res(full: Array, kept: Array, lo: int, hi: int) -> float:
	var kfs: Array = []
	for f in kept:
		kfs.append({"frame": int(f), "color": full[int(f)]})
	var worst := 0.0
	for f in range(lo, mini(hi, full.size())):
		var it: Color = Fit.curve_at(kfs, f)
		var c: Color = full[f]
		worst = maxf(worst, maxf(absf(c.r - it.r), maxf(absf(c.g - it.g), absf(c.b - it.b))))
	return worst


func _med(a: Array): return 0 if a.is_empty() else a[a.size() / 2]
func _p90(a: Array): return 0 if a.is_empty() else a[int(float(a.size()) * 0.9)]
func _mean(a: Array) -> float:
	if a.is_empty(): return 0.0
	var s := 0.0
	for v in a: s += float(v)
	return s / float(a.size())
