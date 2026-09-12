extends Node
## The other half of `stranger_install.gd`'s burn-down arm: it loads ONLY the files
## on the rig's `known_failures.tsv` and asserts each one still fails to compile.
##
## WHY A SECOND SCENE. A script that fails to parse emits `SCRIPT ERROR` on stderr,
## and the rig treats a throw in a stranger project as the finding — a rule worth
## keeping strict, because the only thing this project withholds is the host. So
## the debt is loaded here, where the throws are the expected outcome and `run.sh`
## says so in the same breath, and `stranger_install.tscn` stays throw-free.
##
## THE DIRECTION IS THE POINT. This arm goes RED WHEN THE DEBT IS PAID, which is
## the arm a burn-down usually does not have: a list that only ever grows is a list
## nobody deletes from, and the day one of these compiles this run tells you to
## delete its row instead of letting it sit there describing a fixed file.

const KNOWN_FAILURES := "res://known_failures.tsv"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var rows := _rows()
	if rows.is_empty():
		print("[FAIL] stranger_burn_down ran with no known_failures.tsv rows — this scene "
			+ "should not have been run at all, and a run with nothing to check is not a pass")
		print("0 passed, 1 failed")
		get_tree().quit()
		return
	for path in rows:
		# KIND-AWARE, AND THE `.gd` SPELLING IS NOT THE GENERAL ONE. A row can name a
		# `.tres` as well as a `.gd` (ADR-0202 Class B put `tile_cursor_opaque.tres`
		# on this list), and `s is GDScript` is FALSE for a resource whether it loaded
		# or not — so the script predicate would report a fixed resource as "still
		# failing" forever, which is precisely the direction this scene exists to
		# check. A script is fixed when it COMPILES; anything else is fixed when it
		# LOADS AT ALL.
		var s = load(path)
		var compiled: bool
		if path.get_extension() == "gd":
			compiled = s != null and s is GDScript and s.get_instance_base_type() != ""
		else:
			compiled = s != null
		if compiled:
			_failed += 1
			print("[FAIL] %s is on known_failures.tsv (%s) and it now COMPILES. "
				% [path, rows[path]] + "Delete the row.")
		else:
			_passed += 1
			print("[ok] still failing, as declared: %s — %s" % [path, rows[path]])
	print("%d passed, %d failed" % [_passed, _failed])
	if _failed == 0:
		print("[PASS] every declared portability failure is still a failure: %d file(s). "
			% _passed + "This is goal #5's INSTALL half UNMET, on record, and not a "
			+ "clean bill. The other half is the cross-system reach count this scene "
			+ "cannot see; tools/score_goals.py joins them (ADR-0232)")
	else:
		print("[FAIL] the burn-down describes a file that has been fixed")
	get_tree().quit()


func _rows() -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(KNOWN_FAILURES):
		return out
	for line in FileAccess.get_file_as_string(KNOWN_FAILURES).split("\n"):
		if line.strip_edges() == "" or line.begins_with("#"):
			continue
		var parts := line.split("\t")
		if parts.size() >= 4:
			var path: String = parts[0]
			if not path.begins_with("res://"):
				path = "res://" + path
			out[path] = "%s — %s" % [parts[1], parts[3]]
	return out
