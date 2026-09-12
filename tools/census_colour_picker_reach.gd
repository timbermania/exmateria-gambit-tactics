extends Node
## WHAT CAN THE AUTHOR ACTUALLY DIAL? The colour picker authors in MUXED (output) space:
## you pick `T`, the tool stores `clamp_to_box(T, S)` and compiles `curve = T ⊘ S`. Both the
## pick and the store are 8-bit, so the picker's byte sliders can only hold values in
## `[0, round(S.k*255)]` — and every distinct curve value has to be addressed through that
## shrunken range. This censuses the CONTROL RESOLUTION, which is the thing the author is
## complaining about ("I am not able to reach every [0,0,0] to [255,255,255]"), as distinct
## from the RENDER reach (the box volume), which a previous census already measured at a
## median 0.75 of the RGB cube.
##
## Also counts the two rival explanations for "I can get more extreme colors changing the
## curves directly": 4bpp frames (a flat RGBA bake would make S itself wrong) and ADD blend
## (the composited pixel is bg + ALBEDO, which the swatch never shows).
##
## Run: <GODOT> --path . --quit-after 6000 res://tools/census_colour_picker_reach.tscn

const EffectDataClass = ExMateriaEffects.EffectData
const EmitterSpriteColor = preload("res://src/effects/studio/EmitterSpriteColor.gd")


func _ready() -> void:
	var n_em := 0
	var n_white := 0            # S is exactly white -> picker range is the full 0..255
	var n_dead := 0             # at least one channel S.k == 0
	var n_ceiling_lt_255 := 0   # no channel's slider can hold 255
	var levels_min: Array = []  # per emitter: fewest authorable byte levels across channels
	var levels_mean: Array = []
	var n_4bpp := 0
	var n_add := 0
	var worst: Array = []

	var d := DirAccess.open("res://assets/effects")
	if d == null:
		print("NO CORPUS"); get_tree().quit(1); return
	var names: Array = []
	for nm in d.get_directories():
		names.append(nm)
	names.sort()
	for nm in names:
		var ed = EffectDataClass.load_from_directory("res://assets/effects/%s" % nm)
		if ed == null or not (ed.emitters is Array):
			continue
		for i in range(ed.emitters.size()):
			var em = ed.emitters[i]
			if em == null:
				continue
			var cc = em.color_curves
			if not (cc is Dictionary):
				continue
			if int(cc.get("r", -1)) < 0 and int(cc.get("g", -1)) < 0 and int(cc.get("b", -1)) < 0:
				continue
			var s: Color = EmitterSpriteColor.representative(ed, i)
			n_em += 1
			if s.r >= 1.0 and s.g >= 1.0 and s.b >= 1.0:
				n_white += 1
			if s.r <= 0.0 or s.g <= 0.0 or s.b <= 0.0:
				n_dead += 1
			# The picker's byte slider ceiling per channel, and how many distinct curve
			# values that ceiling can address (0..ceil inclusive).
			var ce := [int(round(s.r * 255.0)), int(round(s.g * 255.0)), int(round(s.b * 255.0))]
			if ce[0] < 255 and ce[1] < 255 and ce[2] < 255:
				n_ceiling_lt_255 += 1
			var lo: int = mini(ce[0], mini(ce[1], ce[2])) + 1
			levels_min.append(lo)
			levels_mean.append((ce[0] + ce[1] + ce[2] + 3) / 3.0)
			if lo <= 32:
				worst.append("%s e%d S=(%d,%d,%d) levels=%d" % [nm, i, ce[0], ce[1], ce[2], lo])
			# The rival explanations, counted over the frames this emitter's animation shows.
			var flags := _frame_flags(ed, em)
			if flags.get("any_4bpp", false):
				n_4bpp += 1
			if flags.get("any_add", false):
				n_add += 1

	levels_min.sort()
	levels_mean.sort()
	print("=== COLOUR PICKER CONTROL RESOLUTION (muxed authoring) ===")
	print("colour emitters censused: %d" % n_em)
	print("S is exactly white (picker range is the full 0..255): %d (%.1f%%)"
		% [n_white, 100.0 * n_white / maxf(1, n_em)])
	print("at least one DEAD channel: %d (%.1f%%)" % [n_dead, 100.0 * n_dead / maxf(1, n_em)])
	print("NO channel's slider can hold 255: %d (%.1f%%)"
		% [n_ceiling_lt_255, 100.0 * n_ceiling_lt_255 / maxf(1, n_em)])
	_pct("authorable byte levels, WORST channel (of 256)", levels_min)
	_pct("authorable byte levels, mean channel (of 256)", levels_mean)
	print("--- rival explanations ---")
	print("emitters whose frames include a 4bpp frame: %d (%.1f%%)"
		% [n_4bpp, 100.0 * n_4bpp / maxf(1, n_em)])
	print("emitters whose frames include an ADD frame: %d (%.1f%%)"
		% [n_add, 100.0 * n_add / maxf(1, n_em)])
	print("--- worst 20 (<=32 levels in some channel) --- (%d total)" % worst.size())
	for w in worst.slice(0, 20):
		print("  " + w)
	get_tree().quit(0)


func _pct(label: String, sorted_vals: Array) -> void:
	if sorted_vals.is_empty():
		print("%s: (none)" % label); return
	print("%s: min=%.0f p10=%.0f median=%.0f p90=%.0f max=%.0f" % [label,
		sorted_vals[0], _q(sorted_vals, 0.10), _q(sorted_vals, 0.50),
		_q(sorted_vals, 0.90), sorted_vals[sorted_vals.size() - 1]])


func _q(a: Array, f: float) -> float:
	return float(a[clampi(int(f * a.size()), 0, a.size() - 1)])


## is_8bpp / blend_mode over the frames the emitter's animation actually visits — the SAME
## address walk EmitterSpriteColor uses to resolve the representative texel.
func _frame_flags(ed, em) -> Dictionary:
	var any_4bpp := false
	var any_add := false
	var ai: int = int(em.anim_index)
	if ai < 0 or ai >= ed.animations.size():
		return {"any_4bpp": false, "any_add": false}
	var group_off: int = ed.frameset_group_offset(int(em.anim_param))
	for opcode in ed.animations[ai].get("opcodes", []):
		if opcode.get("type", "") != "FRAME":
			continue
		var fs_idx: int = int(opcode.get("frameset", 0)) + group_off
		if fs_idx < 0 or fs_idx >= ed.framesets.size():
			continue
		var frameset = ed.framesets[fs_idx]
		if not (frameset is Dictionary):
			continue
		for frame in frameset.get("frames", []):
			if not bool(frame.get("is_8bpp", true)):
				any_4bpp = true
			if str(frame.get("blend_mode", "")) == "ADD":
				any_add = true
	return {"any_4bpp": any_4bpp, "any_add": any_add}
