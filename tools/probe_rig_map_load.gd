extends Node

## #745 — DOES THE ANIMATION-RESOLUTION MAP STILL LOAD WITH ITS THREE RESOURCE SCRIPTS
## STRIPPED OF THEIR GLOBAL NAMES?
##
## #744 stripped the `class_name` off `AnimationResolutionMapResource`,
## `SpriteTypeResource` and `ActivityRowResource`, and the register's note says "a boot
## proved `map.tres` still loads without them". #745's criterion asks for that boot as
## evidence rather than as a claim, because the `.tres` still carries
## `script_class="AnimationResolutionMapResource"` in its header — a GLOBAL NAME that no
## longer exists — and because a resource that half-loads is exactly ADR-0157 Spike A's
## shape: the object comes back, and the failure waits for the first property read.
##
## So this walks the whole nesting: the outer resource, its typed `sprite_types`
## dictionary, and the per-activity rows inside those. A stripped load would give an
## object whose exported members are empty rather than an error.
##
## The resource's path comes in on the command line — `tools/` is inside
## `check_lattice_scene.py`'s corpus and a literal `res://addons/…` here would add a
## criterion-4 site to the register this pass is scoring (ADR-0208 dec. 7 scores
## comments too).
##
##     godot --path . res://tools/probe_rig_map_load.tscn -- --map=res://…/map.tres
##
## Every line is prefixed `[map]`.


func _ready() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2 and kv[0].lstrip("-") == "map":
			path = kv[1]
	if path == "":
		print("[map] no --map= given")
		get_tree().quit(1)
		return

	print("[map] ResourceLoader.exists=%s  %s" % [str(ResourceLoader.exists(path)), path])
	var res: Resource = load(path)
	if res == null:
		print("[map] load()=null — THE MAP DOES NOT LOAD WITHOUT THE GLOBAL NAMES")
		get_tree().quit(1)
		return
	var s: Script = res.get_script()
	print("[map] loaded %s  script=%s  global_name='%s'" % [
		res.get_class(),
		"null" if s == null else str(s.resource_path),
		"" if s == null else str((s as GDScript).get_global_name())])

	var types: Variant = res.get("sprite_types")
	if types == null:
		print("[map] sprite_types is null — the outer resource mounted STRIPPED (Spike A's shape)")
		get_tree().quit(1)
		return
	var d: Dictionary = types
	print("[map] sprite_types: %d entry(ies)" % d.size())
	var shown := 0
	var rows_total := 0
	for k in d.keys():
		var st: Resource = d[k]
		var acts: Variant = null if st == null else st.get("states")
		var n: int = 0 if acts == null else (acts as Dictionary).size()
		rows_total += n
		if shown < 3:
			var sts: Script = null if st == null else st.get_script()
			print("[map]   '%s' -> %s script=%s seq=%s states=%d" % [
				str(k), "null" if st == null else st.get_class(),
				"null" if sts == null else str(sts.resource_path).get_file(),
				"-" if st == null else str(st.get("seq_file")), n])
			if acts != null and n > 0:
				var ak = (acts as Dictionary).keys()[0]
				var row: Resource = (acts as Dictionary)[ak]
				var rs: Script = null if row == null else row.get_script()
				print("[map]     row '%s' script=%s front=%s back=%s" % [
					str(ak), "null" if rs == null else str(rs.resource_path).get_file(),
					str(null if row == null else row.get("front")),
					str(null if row == null else row.get("back"))])
			shown += 1
	print("[map] %d state row(s) across %d sprite type(s)" % [rows_total, d.size()])
	print("[map] VERDICT %s" % (
		"THE MAP LOADS AND ITS NESTING RESOLVES with no global names"
		if d.size() > 0 and rows_total > 0 else "THE MAP CAME BACK EMPTY — stripped mount"))
	print("[map] DONE")
	get_tree().quit(0)
