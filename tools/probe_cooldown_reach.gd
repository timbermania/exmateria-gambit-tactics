extends SceneTree
## #1108 verification probe: did raising MAX_COOLDOWN_ABILITIES actually move
## ADR-0277's DERIVED cooldown reachability, with no edit to LeverSet.gd?
##
## ADR-0277 dec. 8 claims reachability is derived, never listed — the ceiling is
## regex-scanned out of combat_common.glslinc "so #1108 moves the numbers without
## touching this ADR". Dec. 9 recorded the numbers it measured against the old
## 128 ceiling: 60 of the 91 ability category classes sat ENTIRELY above it and
## 14 STRADDLED it. This re-measures both, through LeverSet's own predicate
## rather than a Python replica of its regex — an arm against a transcription
## only tests the transcription.
##
## Run (NOT headless), from the package root:
##   godot --path . -s res://tools/probe_cooldown_reach.gd

const QUANTITY := "cooldown_ticks"


func _initialize() -> void:
	print("[probe] cooldown ceiling scanned out of the kernel: %d" % LeverSet.cooldown_ceiling())

	# Every ability category class, via the same tagged-union partition the
	# lever set uses. One category per record (ADR-0277 dec. 7).
	var classes := {}   # String(key) -> Array[int] of ability ids
	for aid in range(GPUConstants.MAX_ABILITIES):
		var cat: Array = LeverSet.ability_category(aid)
		if cat.is_empty():
			continue
		var k := "%s/%s" % [cat[0], cat[1]]
		if not classes.has(k):
			classes[k] = []
		classes[k].append(aid)

	var all_reach := 0
	var none_reach := 0
	var straddle := 0
	var total_members := 0
	var reaching_members := 0
	for k in classes:
		var ids: Array = classes[k]
		var n := 0
		for aid in ids:
			if LeverSet.ability_reaches(QUANTITY, aid):
				n += 1
		total_members += ids.size()
		reaching_members += n
		if n == 0:
			none_reach += 1
		elif n == ids.size():
			all_reach += 1
		else:
			straddle += 1

	print("[probe] ability category classes: %d" % classes.size())
	print("[probe]   reachable for %s in FULL    : %d" % [QUANTITY, all_reach])
	print("[probe]   reachable for %s NOT AT ALL : %d   (ADR-0277 dec. 9 measured 60 at ceiling 128)" % [QUANTITY, none_reach])
	print("[probe]   STRADDLING the ceiling      : %d   (ADR-0277 dec. 9 measured 14 at ceiling 128)" % straddle)
	print("[probe] ability records reaching %s: %d of %d" % [QUANTITY, reaching_members, total_members])

	# Positive control: the instrument must be able to SEE unreachability, or
	# "0 straddling" is indistinguishable from a predicate that says yes to
	# everything. Reaction/Support/Movement reach NO quantity at all.
	var unreachable_seen := 0
	for aid in range(GPUConstants.MAX_ABILITIES):
		if not LeverSet.ability_reaches(QUANTITY, aid):
			unreachable_seen += 1
	print("[probe] CONTROL — ability ids the predicate still refuses: %d (must be > 0)" % unreachable_seen)

	quit(0)
