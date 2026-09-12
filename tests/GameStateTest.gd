extends Node
## Parity guard for [GameState] — the compile-time enum of top-level game states —
## against its source of truth [code]assets/scenarios/game_states.json[/code].
## Asserts the enum order/slugs match the JSON, that the graph-kind and sink
## mappings ([method GameState.for_node_kind] / [method GameState.for_successor]) agree
## with the JSON's `graph_kinds`/`graph_successor`, and that slug round-trips. This is
## the drift guard that lets the navigator trust either representation.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/GameStateTest.tscn

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_catalog_loads()
	_test_count_matches_enum()
	_test_slug_and_order_parity()
	_test_slug_round_trip()
	_test_node_kind_mapping_matches_json()
	_test_sink_mapping_matches_json()

	print("\n=== GameStateTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] GameStateTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] GameStateTest")
		get_tree().quit(1)
	else:
		print("[PASS] GameStateTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	_eq(cond, true, name)


func _catalog() -> Array:
	return GameState.load_catalog()


func _test_catalog_loads() -> void:
	_true(_catalog().size() > 0, "catalog loads non-empty")


func _test_count_matches_enum() -> void:
	_eq(_catalog().size(), GameState.SLUGS.size(), "json state_count == enum size")
	_eq(GameState.State.size(), GameState.SLUGS.size(), "enum member count == SLUGS size")


func _test_slug_and_order_parity() -> void:
	# Each JSON state's `order` must index the matching slug in the enum's SLUGS.
	for st in _catalog():
		var order: int = int(st["order"])
		var slug: String = st["slug"]
		_eq(GameState.slug_of(order), slug, "SLUGS[%d] == %s" % [order, slug])


func _test_slug_round_trip() -> void:
	for i in GameState.SLUGS.size():
		var slug: String = GameState.slug_of(i)
		_eq(GameState.from_slug(slug), i, "round-trip %s" % slug)
	_eq(GameState.from_slug("not_a_state"), -1, "unknown slug -> -1")


func _test_node_kind_mapping_matches_json() -> void:
	# Every graph_kind listed under a state must map to that state via for_node_kind.
	for st in _catalog():
		var owner: int = GameState.from_slug(st["slug"])
		for kind in st["graph_kinds"]:
			_eq(GameState.for_node_kind(kind), owner, "node kind '%s' -> %s" % [kind, st["slug"]])
	# And the two concrete cases the navigator relies on:
	_eq(GameState.for_node_kind("battle"), GameState.State.BATTLE, "battle -> BATTLE")
	_eq(GameState.for_node_kind("quiet"), GameState.State.SCENARIO, "quiet -> SCENARIO")


func _test_sink_mapping_matches_json() -> void:
	for st in _catalog():
		var sink = st["graph_successor"]
		if sink == null:
			continue
		var owner: int = GameState.from_slug(st["slug"])
		_eq(GameState.for_successor(sink), owner, "sink '%s' -> %s" % [sink, st["slug"]])
	_eq(GameState.for_successor("nope"), -1, "non-sink target -> -1")
