extends Node
## ONE-OFF CENSUS — how many FRAMESETS does a shared sheet region span?
##
## The scope toggle's third mode is "a manual subset of framesets", so the size of that
## toggle list is the design input: three rows fits a 248px overlay, twenty does not. The
## existing corpus numbers count MEMBERS (median ~6, max 107); this counts the distinct
## framesets those members sit in, which is the unit the author actually toggles.
##
## Run: godot --path . --quit-after 4000 res://tools/census_region_framesets.tscn

const EffectDataClass = ExMateriaEffects.EffectData
const Canvas = preload("res://src/effects/studio/FramesetCanvas.gd")


func _ready() -> void:
	var dirs: Array = _scan()
	var fs_counts: Array = []      # distinct framesets per multi-member region
	var member_counts: Array = []
	var singleton := 0
	var one_frameset := 0
	var effects := 0
	for d in dirs:
		var ed = EffectDataClass.load_from_directory(d)
		if ed == null or not (ed.framesets is Array) or ed.framesets.is_empty():
			continue
		effects += 1
		var seen: Dictionary = {}
		for i in range(ed.framesets.size()):
			var fs = ed.framesets[i]
			for fr in (fs.get("frames", []) if fs is Dictionary else []):
				var uv: Dictionary = (fr.get("uv", {}) if fr is Dictionary else {})
				if uv.is_empty():
					continue
				var block: Rect2i = Canvas.normalised_block(uv)
				var key := "%d,%d,%d,%d" % [block.position.x, block.position.y,
					block.size.x, block.size.y]
				if seen.has(key):
					continue
				seen[key] = true
				var members: Array = Canvas.region_members(ed.framesets, block)
				if members.size() <= 1:
					singleton += 1
					continue
				var distinct: Dictionary = {}
				for m in members:
					distinct[int(m["frameset_index"])] = true
				member_counts.append(members.size())
				fs_counts.append(distinct.size())
				if distinct.size() == 1:
					one_frameset += 1
	fs_counts.sort()
	member_counts.sort()
	var total: int = fs_counts.size()
	print("\n=== REGION -> FRAMESET SPAN CENSUS (%d effects) ===" % effects)
	print("singleton regions (1 member, no toggle to make): %d" % singleton)
	print("regions with 2+ members: %d" % total)
	if total == 0:
		get_tree().quit(0); return
	print("  ...of which live in ONE frameset: %d (%.1f%%)" % [one_frameset,
		100.0 * one_frameset / total])
	print("distinct framesets per multi-member region:")
	for p in [50, 75, 90, 95, 99]:
		print("   p%-3d = %d" % [p, fs_counts[mini(total - 1, int(total * p / 100.0))]])
	print("   max  = %d" % fs_counts[total - 1])
	var over := {2: 0, 4: 0, 6: 0, 8: 0, 12: 0}
	for c in fs_counts:
		for k in over.keys():
			if c > k:
				over[k] += 1
	for k in [2, 4, 6, 8, 12]:
		print("   regions spanning MORE THAN %2d framesets: %5d (%.1f%%)" % [k, over[k],
			100.0 * over[k] / total])
	print("members per multi-member region: p50=%d p90=%d max=%d" % [
		member_counts[total / 2], member_counts[mini(total - 1, int(total * 0.9))],
		member_counts[total - 1]])
	print("=== END ===")
	get_tree().quit(0)


func _scan() -> Array:
	var base := "res://assets/effects"
	var out: Array = []
	var da := DirAccess.open(base)
	if da == null:
		return out
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if da.current_is_dir() and name.begins_with("E") and name != "E000":
			out.append(base.path_join(name))
		name = da.get_next()
	da.list_dir_end()
	out.sort()
	return out
