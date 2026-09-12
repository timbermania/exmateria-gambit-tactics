class_name FuncTracer
## Runtime function call tracer for dead code detection.
##
## Every instrumented function calls FuncTracer.t("Class.method") on first entry.
## Press F8 or quit the game to dump the trace to user://func_trace.txt.

static var _seen: Dictionary = {}


static func t(sig: String) -> void:
	if sig in _seen:
		return
	_seen[sig] = true


static func dump() -> void:
	# Merge with existing trace file so multiple runs accumulate
	var existing: Dictionary = {}
	var r := FileAccess.open("user://func_trace.txt", FileAccess.READ)
	if r:
		while not r.eof_reached():
			var line := r.get_line().strip_edges()
			if line != "":
				existing[line] = true
		r.close()

	existing.merge(_seen)
	var keys: Array = existing.keys()
	keys.sort()

	var f := FileAccess.open("user://func_trace.txt", FileAccess.WRITE)
	if not f:
		push_error("[FuncTracer] Failed to open user://func_trace.txt for writing")
		return
	for key in keys:
		f.store_line(key)
	f.close()
	var new_count := _seen.size()
	print("[FuncTracer] Dumped %d new + %d existing = %d total signatures to user://func_trace.txt" % [new_count, keys.size() - new_count, keys.size()])


static func get_count() -> int:
	return _seen.size()
