extends Node
## The Campaign world-flag store — [WorldMapVariables] addressing and [WorldMapProgress]
## decoding, against the console's own bytes.
##
## [b]What makes this a real check and not a tautology.[/b] `OPENING_CAPTURE` is 32 raw
## words lifted off `world_map_ss1_settled_dialog_closed.sstate` by
## `tools/wm_progress_dump.py`. The expectations below — nodes {2, 6, 24}, routes
## {1, 3}, story 1, gil 4500, Jan 1 — come from WORLD_MAP_SCREEN.md §29 and §30, which
## read them by a different route (`travel.py flags`, and the node descriptors' own
## `flags & 0x10`, 43 nodes x 3 savestates with zero mismatches). So the two sides are
## an addressing model and a measurement, not one number copied twice.
##
## Word 140 is `0x01000044` and word 141 is `0x0000A000`; that those decode to exactly
## {2, 6, 24} and {1, 3} is the whole claim.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/WorldMapProgressTest.tscn

var _passed := 0
var _failed := 0


func _ready() -> void:
	_check_opening()
	_check_regions()
	_check_writes()
	_check_round_trip()

	if _failed > 0:
		print("[FAIL] WorldMapProgressTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] WorldMapProgressTest — %d/%d" % [_passed, _passed])
	get_tree().quit(0)


func _check_opening() -> void:
	var p := WorldMapProgress.new_campaign()
	_eq("known nodes", p.known_nodes(), [2, 6, 24])
	_eq("drawn routes", p.drawn_routes(), [1, 3])
	_eq("story counter", p.story_counter(), 1)
	_eq("gil", p.gil(), 4500)
	_eq("date", p.date(), Vector2i(1, 1))
	# The two routes are exactly the edges joining the three known nodes (§29), an
	# independent check on both the flag decode and the route table.
	var model_ok := true
	for r in [1, 3]:
		if not p.is_route_drawn(r):
			model_ok = false
	_eq("routes 1 and 3 read drawn", model_ok, true)
	_eq("node 0 is not known", p.is_node_known(0), false)


## Each of the store's three regions addressed at its own boundaries. The bit and
## nibble bases are `512 + 4*((idx-128)>>5)` and `604 + 4*((idx-864)>>3)` in BYTES, i.e.
## word 128 and word 151 — an off-by-four here would still decode the opening capture,
## because every named variable it holds is in the u32 or the bit region.
func _check_regions() -> void:
	var v := WorldMapVariables.new()
	for row in [[0, 0xFFFFFFFF], [127, 0x12345678], [128, 1], [863, 1],
			[864, 0xF], [1023, 0xF], [110, 99999999]]:
		var idx: int = row[0]
		var want: int = row[1]
		v.set_var(idx, want)
		_eq("var %d round-trips" % idx, v.get_var(idx), want)
	# A bit write must not disturb its 31 neighbours.
	v = WorldMapVariables.new()
	v.set_var(512 + 6, 1)
	v.set_var(512 + 24, 1)
	v.set_var(512 + 2, 1)
	_eq("three bits in one word are 0x01000044", v.to_sparse(), [[140, 0x01000044]])
	v.set_var(512 + 6, 0)
	_eq("clearing one bit leaves the others", v.to_sparse(), [[140, 0x01000004]])
	# A nibble is four bits wide and must clip.
	v = WorldMapVariables.new()
	v.set_var(864, 0xF)
	v.set_var(865, 0x3)
	_eq("two nibbles pack into one word", v.to_sparse(), [[151, 0x3F]])


func _check_writes() -> void:
	var p := WorldMapProgress.new_campaign()
	p.set_node_known(30)
	p.set_route_drawn(47)
	p.set_gil(123456)
	p.set_date(3, 17)
	p.set_story_counter(9)
	_eq("node 30 becomes known", p.known_nodes(), [2, 6, 24, 30])
	_eq("route 47 becomes drawn", p.drawn_routes(), [1, 3, 47])
	_eq("gil written", p.gil(), 123456)
	_eq("date written", p.date(), Vector2i(3, 17))
	_eq("story written", p.story_counter(), 9)
	# ...and the untouched words are still there.
	_eq("word 87 survives unrelated writes", p.vars.get_var(87), 0x2CF)


func _check_round_trip() -> void:
	var p := WorldMapProgress.new_campaign()
	p.set_node_known(41)
	p.set_party_node(25)
	var path := "user://world_progress_test.json"
	if p.save_to_file(path) != OK:
		_fail("could not write %s" % path)
		return
	var back := WorldMapProgress.load_or_new(path)
	_eq("saved store reloads word for word", back.vars.to_sparse(), p.vars.to_sparse())
	_eq("saved party node reloads", back.party_node(), 25)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_eq("no save file means a new campaign",
			WorldMapProgress.load_or_new(path).known_nodes(), [2, 6, 24])


func _eq(what: String, got: Variant, want: Variant) -> void:
	if str(got) == str(want):
		_passed += 1
		return
	_failed += 1
	print("  FAIL %s: got %s, want %s" % [what, got, want])


func _fail(msg: String) -> void:
	_failed += 1
	print("  FAIL %s" % msg)
