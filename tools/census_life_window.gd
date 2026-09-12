extends Node
## THE PARTICLE-LIFE WINDOW, censused over the whole corpus — the instrument behind
## ADR-0089's 2026-08-20 correction block. Re-runnable, because the ADR quotes its output.
##
## It answers three things:
##   1. the SHAPE of the four lifetime fields (all real / mixed / all −1), and how many
##      emitters carry a lifetime CURVE — which is what decides whether the end pair is
##      read at all;
##   2. how far the corrected rule (`EmitterLifeWindow`, live) moves against the rule that
##      shipped before it — `min(all four) >= 0 ? max(all four) : animation length`;
##   3. which direction it moves, since a window that was too LARGE drew dead zone as live.
##
## Run: <GODOT> --path . --quit-after 3000 res://tools/census_life_window.tscn

const EffectDataClass = ExMateriaEffects.EffectData
const LifeWindow = preload("res://src/effects/studio/EmitterLifeWindow.gd")


func _ready() -> void:
	var effects := 0
	var all_pos := 0
	var mixed := 0
	var all_neg := 0
	var curved := 0
	var start_pair_split := 0
	var unresolved := 0
	var shrink: Array = []
	var grow: Array = []
	var names: Array = []
	var d := DirAccess.open("res://assets/effects")
	if d == null:
		print("NO CORPUS at res://assets/effects — see SETUP.md")
		get_tree().quit(1)
		return
	for n in d.get_directories():
		names.append(n)
	names.sort()
	for name in names:
		var ed = EffectDataClass.load_from_directory("res://assets/effects/%s" % name)
		if ed == null or not (ed.emitters is Array):
			continue
		effects += 1
		for i in range(ed.emitters.size()):
			var em = ed.emitters[i]
			if em == null or not _colour_enabled(ed, em):
				continue
			var life := [int(em.lifetime_min_start), int(em.lifetime_max_start),
				int(em.lifetime_min_end), int(em.lifetime_max_end)]
			var neg := 0
			for v in life:
				if int(v) < 0:
					neg += 1
			if neg == 0:
				all_pos += 1
			elif neg == 4:
				all_neg += 1
			else:
				mixed += 1
			if (life[0] < 0) != (life[1] < 0):
				start_pair_split += 1
			if LifeWindow.has_lifetime_curve(em, ed):
				curved += 1
			var now: int = int(LifeWindow.for_emitter(em, ed)["n"])
			var was: int = _old_rule(life, em, ed)
			if now < 0 or was < 0:
				unresolved += 1
				continue
			if now < was:
				shrink.append(was - now)
			elif now > was:
				grow.append(now - was)
	var total := all_pos + mixed + all_neg
	print("=== PARTICLE-LIFE WINDOW CENSUS · %d effects ===" % effects)
	print("colour-enabled emitters: %d" % total)
	print("  all four fields >= 0 : %d (%.1f%%)" % [all_pos, 100.0 * all_pos / maxi(1, total)])
	print("  MIXED                : %d (%.1f%%)" % [mixed, 100.0 * mixed / maxi(1, total)])
	print("  all four are -1      : %d (%.1f%%)" % [all_neg, 100.0 * all_neg / maxi(1, total)])
	print("  with a LIFETIME CURVE: %d (%.1f%%)  <- the only ones whose END pair is read"
		% [curved, 100.0 * curved / maxi(1, total)])
	print("  START pair split (one field -1, the other real): %d" % start_pair_split)
	print("the correction, against the pre-2026-08-20 rule (max over all four):")
	_report("  window SHRANK (dead zone the old rule drew as live)", shrink, total)
	_report("  window GREW   (live ages the old rule hid)", grow, total)
	print("  unresolvable under either rule: %d" % unresolved)
	get_tree().quit(0)


func _report(label: String, d: Array, total: int) -> void:
	d.sort()
	print("%s: %d (%.1f%%)" % [label, d.size(), 100.0 * d.size() / maxi(1, total)])
	if not d.is_empty():
		print("      median %d  p90 %d  max %d" % [d[d.size() / 2],
			d[int(d.size() * 0.9)], d[d.size() - 1]])


## The ribbon's own colour-enabled test (`SequenceCellColour._curves`): the flag AND three
## resolvable, non-empty channel curves. All-or-nothing, so this counts the same emitters
## the colour surface actually draws for.
func _colour_enabled(ed, em) -> bool:
	if not bool(em.flags.get("color_curve_enabled", false)):
		return false
	for ch in ["r", "g", "b"]:
		var c = ed.get_curve(int(em.color_curves.get(ch, -1)))
		if c == null or c.samples.is_empty():
			return false
	return true


## The rule as it stood before the correction, transcribed so the delta is against what
## actually shipped rather than against a second call into the module under test.
func _old_rule(life: Array, em, ed) -> int:
	if int(life.min()) >= 0:
		return int(life.max())
	var anim_len: int = -1
	if ed != null and ed.has_method("get_animation_display_length"):
		anim_len = int(ed.get_animation_display_length(int(em.anim_index)))
	return anim_len if anim_len > 0 else -1
