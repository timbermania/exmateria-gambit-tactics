extends Node

## JsonAsset test — pure GDScript, no GPU / SPU.
##
## Guards the one shared JSON-asset loader (`ExMateriaPlatform.JsonAsset`) that ~17
## `class_name` data stores call to absorb the open → parse → error-handle
## boilerplate they used to hand-copy (the "XDatabase shape"; see CONTEXT.md).
## Fixtures live in tests/fixtures/. Failure paths (missing file, malformed
## JSON, missing/wrong-typed key) intentionally emit push_error — that is the
## helper's contract; the runner keys off [PASS]/[FAIL], not ERROR lines.

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

const OK_PATH := "res://tests/fixtures/json_asset_ok.json"
const BAD_PATH := "res://tests/fixtures/json_asset_bad.txt"
const MISSING_PATH := "res://tests/fixtures/does_not_exist.json"


func _ready() -> void:
	var failed := false

	# 1. Whole-object load (empty key) returns the full root dict.
	var root := JsonAsset.load_dict(OK_PATH)
	if not (root.has("wrapper") and root.has("list_under_key") and root.has("nested")):
		print("[FAIL] load_dict(OK) missing top-level keys: %s" % root.keys())
		failed = true

	# 2. Key unwrap returns the sub-object (JSON numbers parse as float).
	var wrapper := JsonAsset.load_dict(OK_PATH, "wrapper")
	if wrapper.get("a") != 1 or wrapper.get("b") != 2:
		print("[FAIL] load_dict(OK, 'wrapper') = %s, expected {a:1, b:2}" % wrapper)
		failed = true

	# 3. Missing key returns {} silently (mirrors data.get(key, {})).
	var missing_key := JsonAsset.load_dict(OK_PATH, "nope")
	if not missing_key.is_empty():
		print("[FAIL] load_dict(OK, 'nope') should be {}, got %s" % missing_key)
		failed = true

	# 4. Key pointing at an Array (not an object) is misuse -> {} + push_error.
	var array_key := JsonAsset.load_dict(OK_PATH, "list_under_key")
	if not array_key.is_empty():
		print("[FAIL] load_dict(OK, 'list_under_key') should be {} (Array is not an object), got %s" % array_key)
		failed = true

	# 5. Documented escape hatch: load root, pluck the Array locally.
	var arr: Array = JsonAsset.load_dict(OK_PATH).get("list_under_key", [])
	if arr.size() != 3 or arr[0] != 10:
		print("[FAIL] root.get('list_under_key') = %s, expected [10,20,30]" % [arr])
		failed = true

	# 6. Nested pluck via the root works.
	var inner: Dictionary = JsonAsset.load_dict(OK_PATH).get("nested", {}).get("inner", {})
	if inner.get("x") != 9:
		print("[FAIL] nested.inner.x = %s, expected 9" % inner)
		failed = true

	# 7. Missing file -> {} (with push_error, not a crash).
	var absent := JsonAsset.load_dict(MISSING_PATH)
	if not absent.is_empty():
		print("[FAIL] load_dict(missing file) should be {}, got %s" % absent)
		failed = true

	# 8. Malformed JSON -> {} (with push_error).
	var malformed := JsonAsset.load_dict(BAD_PATH)
	if not malformed.is_empty():
		print("[FAIL] load_dict(malformed) should be {}, got %s" % malformed)
		failed = true

	if failed:
		print("[FAIL] JsonAsset test")
	else:
		print("[PASS] JsonAsset: root/key load, missing-key {}, Array-key guard, escape-hatch pluck, missing-file/malformed -> {}")
	get_tree().quit()
