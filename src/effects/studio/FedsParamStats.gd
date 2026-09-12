extends RefCounted
## Reader for the generated feds_param_stats.json — the empirical usage range AND
## the shared per-param signedness source behind ADR-0085's opcode-param honesty
## amendment (2026-08-12). One static parse per session.
##
## The Python producer (tools/generate_feds_param_stats.py) and this reader consult
## the SAME committed file, so they cannot disagree about signedness or the range.
## `of(op, param_index)` returns {signed, bits, min, max, median, mode, n} (signed
## params are in signed space; 0xD3 folds its two bytes into one signed word at
## param_index 0), or {} when the corpus never uses that param.
##
## No class_name (ADR-0004); load()ed by path.

const _PATH := "res://assets/feds_param_stats.json"

static var _stats: Dictionary = {}
static var _loaded := false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(_PATH):
		push_warning("FedsParamStats: %s absent — empirical ranges unavailable" % _PATH)
		return
	var f := FileAccess.open(_PATH, FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK and typeof(json.data) == TYPE_DICTIONARY:
		var s = json.data.get("stats", {})
		if typeof(s) == TYPE_DICTIONARY:
			_stats = s
	f.close()


## The corpus stats for one param, or {} when no shipped effect uses it.
static func of(op: int, param_index: int) -> Dictionary:
	_ensure()
	var e = _stats.get("0x%02X:%d" % [op, param_index])
	return e if typeof(e) == TYPE_DICTIONARY else {}


## The corpus stats for one param CONDITIONED on the active instrument (the last
## 0xAC earlier in the same track — a runtime fact, ADR-0085 2026-08-12). Returns
## {min, max, median, mode, n} for that instrument's bucket, or {} when there is no
## active instrument (instrument_id < 0) or the corpus never used the param under
## it (the honest "none with X" state, decided by the caller). This is a
## CORRELATION — what shipped effects using that instrument did with the byte — not
## a claim the instrument changes the byte's meaning.
static func of_instrument(op: int, param_index: int, instrument_id: int) -> Dictionary:
	if instrument_id < 0:
		return {}
	var e := of(op, param_index)
	var by = e.get("by_instrument", {})
	if typeof(by) != TYPE_DICTIONARY:
		return {}
	var b = by.get(str(instrument_id))
	return b if typeof(b) == TYPE_DICTIONARY else {}
