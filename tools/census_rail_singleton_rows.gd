extends Node
## WHAT "ALWAYS SHOW THE RAIL" COSTS.
##
## `_rebind_rail` collapses a row of ONE frameset to an empty row, so the rail hides and the
## scope's member LIST comes back (`list_suppressed = _rail.visible`). Always showing the
## rail therefore always suppresses the list. This measures which regions that trades away:
## those whose row is one frameset but which have SEVERAL members in it — the tile cannot
## enumerate them, and the list could.
##
## Run: <GODOT> --path . --quit-after 3000 res://tools/census_rail_singleton_rows.tscn

const EffectDataClass = ExMateriaEffects.EffectData
const Canvas = preload("res://src/effects/studio/FramesetCanvas.gd")
const RegionScope = preload("res://src/effects/studio/FramesetRegionScope.gd")


func _ready() -> void:
	var regions := 0
	var one_fs := 0            # row would be a single tile
	var one_fs_one_member := 0 # ...and the list would show nothing either (size > 1 gate)
	var one_fs_multi := 0      # ...but several members share that one frameset
	var one_fs_multi_varying := 0  # ...and they DISAGREE about a facet, so rows differ
	var multi_fs := 0
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
				var key: String = "%s|%s" % [name, str(reg["block"])]
				if seen.has(key):
					continue
				seen[key] = true
				regions += 1
				var row: Array = RegionScope.distinct_framesets(members)
				if row.size() >= 2:
					multi_fs += 1
					continue
				one_fs += 1
				if members.size() <= 1:
					one_fs_one_member += 1
					continue
				one_fs_multi += 1
				if not RegionScope.varying_facets(members).is_empty():
					one_fs_multi_varying += 1
	print("\n=== RAIL SINGLETON-ROW CENSUS ===")
	print("regions: %d   row of 2+ framesets (rail shows today): %d (%.1f%%)"
		% [regions, multi_fs, 100.0 * float(multi_fs) / float(maxi(1, regions))])
	print("row of ONE frameset (rail hidden today): %d (%.1f%%)"
		% [one_fs, 100.0 * float(one_fs) / float(maxi(1, regions))])
	print("   of those, a single member — the list is hidden too, so NOTHING is lost: %d (%.1f%% of all)"
		% [one_fs_one_member, 100.0 * float(one_fs_one_member) / float(maxi(1, regions))])
	print("   several members in that one frameset — the list shows them today: %d (%.1f%% of all)"
		% [one_fs_multi, 100.0 * float(one_fs_multi) / float(maxi(1, regions))])
	print("      ...and those members DISAGREE about a facet, so the rows differ: %d (%.1f%% of all)"
		% [one_fs_multi_varying, 100.0 * float(one_fs_multi_varying) / float(maxi(1, regions))])
	get_tree().quit(0)
