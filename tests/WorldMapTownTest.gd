extends Node
## The town page's DATA — WORLD_MAP_SCREEN.md §35, as it reaches the port.
##
## This asserts `model.json`'s `town` block and the two per-node fields the page needs,
## before any of it has a picture. §35 is the oracle; `dispatch.py town` is its
## research-side twin and prints the same counts off the same disc.
##
## [b]Three of these guard a trap that has already caught someone.[/b]
##
## [b]1. The node KIND is not in the node table the port already reads.[/b] There are two
## per-node tables in `WLDCORE.BIN` and they are not the same table: the 8-byte drawing
## record at `0x80094DFC` (§30.1), which this port has read since round 13, and a 4-byte
## record at `0x80094F54` whose byte 2 is the picture id and byte 3 is the kind (§35.2).
## Reusing the drawing record's `tier` bytes as a kind is the obvious mistake and it is
## [i]nearly[/i] right — it agrees on 37 of 43 nodes. The six it gets wrong are the six
## castles, which it calls kind 0 and the console calls kind 1, so the reuse ships a game
## where Lesalia, Riovanes, Igros, Lionel, Limberry and Zeltennia have no town menu. A
## spot check on a plains node cannot see it.
##
## [b]2. A picture is not a menu.[/b] 19 nodes carry a picture; 16 open a list. Murond Holy
## Place, Orbonne Monastery and Bethla Garrison have a picture and no menu, and the Deep
## Dungeon has a menu through a path that does not consult the kind at all —
## `FUN_8008D2C8` tests `node == 22` [i]before[/i] the kind gate. Gating the list on
## "has a picture" gives three nodes a menu the console does not.
##
## [b]3. The drop shadow is a CEL.[/b] §35.7 describes it as 28 subtractive quads and
## stops there; it is in fact frame list 11 → cel 15, which this extractor has been
## emitting since round 13 and which has drawn nothing because `WLDTEX.TM2` never writes
## the ramp texture. Drawn at the model's `shadow.xy`, its 28 parts reproduce the
## console's 28 packets — xy, wh [i]and[/i] uv — and that anchor is the unique (dx, dy)
## over −128…128 in both axes that does so. So this test asserts the cel, not a
## transcription of the packets: if a future extractor change moves cel 15, the shape
## check fails rather than the picture quietly going wrong.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/WorldMapTownTest.tscn

## §35.7's measured ring extent, screen-centred. Four numbers, and the anchor has two
## degrees of freedom, so this is over-determined.
const RING_X0 := -72
const RING_X1 := 72
const RING_Y0 := -80
const RING_Y1 := 15

## §35.10, by name rather than by index — an index would survive a renumbering.
const PICTURE_NO_MENU := ["Murond Holy Place", "Orbonne Monastery", "Bethla Garrison"]

var _passed := 0
var _failed := 0
var _assets: WorldMapAssets


func _ready() -> void:
	_assets = WorldMapAssets.new()
	if not _assets.load_all():
		print("[FAIL] WorldMapTownTest — assets: %s" % _assets.error)
		get_tree().quit(1)
		return
	var town: Variant = _assets.model.get("town")
	if typeof(town) != TYPE_DICTIONARY or (town as Dictionary).is_empty():
		print("[FAIL] WorldMapTownTest — model.json has no `town` block; "
				+ "run `uv run python tools/parse_world_map.py`")
		get_tree().quit(1)
		return

	_check_node_fields()
	_check_picture_vs_menu()
	_check_shadow_cel(town)
	_check_shadow_ramp(town)
	_check_shadow_texture_present()
	_check_picture_rect(town)
	_check_box(town)
	_check_rows(town)
	_check_picture_slots()
	_check_page(town)
	_check_panel_frame()
	_check_name_cel_ink()
	_check_open_transition()

	if _failed > 0:
		print("[FAIL] WorldMapTownTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] WorldMapTownTest — %d/%d" % [_passed, _passed])
	get_tree().quit(0)


## Trap 1. Both fields exist, and the drawing record's `tier` is NOT a substitute.
func _check_node_fields() -> void:
	var nodes := _assets.nodes()
	_eq("43 nodes", nodes.size(), 43)
	var missing := 0
	for n in nodes:
		if not (n as Dictionary).has("picture") or not (n as Dictionary).has("kind"):
			missing += 1
	_eq("every node carries `picture` and `kind`", missing, 0)

	# The kind gate: exactly 15 towns, and they are nodes 0..14.
	var towns: Array = []
	for n in nodes:
		if int(n["kind"]) == 1:
			towns.append(int(n["i"]))
	_eq("15 nodes of kind 1", towns.size(), 15)
	_eq("...and they are nodes 0..14", towns, range(15) as Array)

	# Their picture ids are 1..15, one each, none shared — §35.10.
	var pics: Array = []
	for i in towns:
		pics.append(int(nodes[i]["picture"]))
	pics.sort()
	_eq("the 15 towns carry picture ids 1..15, one each", pics, range(1, 16) as Array)

	# The near-miss that makes this worth a test: `tier[1]` agrees with `kind` on 37 of
	# 43 and is wrong on exactly the six castles.
	var wrong: Array = []
	for n in nodes:
		if int((n["tier"] as Array)[1]) != int(n["kind"]):
			wrong.append(String(n["name"]))
	_eq("`tier` disagrees with `kind` on 6 nodes", wrong.size(), 6)
	_eq("...and they are the six castles", wrong, [
			"Lesalia Imperial Capital", "Riovanes Castle", "Igros Castle",
			"Lionel Castle", "Limberry Castle", "Zeltennia Castle"])


## Trap 2. 19 pictures, 16 menus, and the three that have one and not the other.
func _check_picture_vs_menu() -> void:
	var with_pic: Array = []
	var with_menu: Array = []
	var silent: Array = []
	for n in _assets.nodes():
		if int(n["picture"]) > 0:
			with_pic.append(String(n["name"]))
			if not bool(n["opens_menu"]):
				silent.append(String(n["name"]))
		if bool(n["opens_menu"]):
			with_menu.append(String(n["name"]))
	_eq("19 nodes carry a picture", with_pic.size(), 19)
	_eq("16 nodes open a menu", with_menu.size(), 16)
	_eq("picture but NO menu", silent, PICTURE_NO_MENU)
	# The Deep Dungeon is the one node whose menu does not come from the kind gate.
	var dd: Dictionary = _assets.node(22)
	_eq("node 22 is the Deep Dungeon", String(dd["name"]), "Deep Dungeon")
	_eq("...its kind is NOT 1", int(dd["kind"]) == 1, false)
	_eq("...and it opens a menu anyway", bool(dd["opens_menu"]), true)


## Trap 3. Cel 15, drawn at the model's anchor, IS the console's 28-quad ring.
func _check_shadow_cel(town: Dictionary) -> void:
	var sh: Dictionary = town["shadow"]
	var cel_id := _assets.static_cel(int(sh["frame"]))
	_eq("frame %d resolves to a static cel" % int(sh["frame"]), cel_id >= 0, true)
	if cel_id < 0:
		return
	var cel := _assets.cel(cel_id)
	_eq("the shadow cel has 28 parts", (cel["parts"] as Array).size(), 28)

	# Every part is semi-transparent at abr 2 — B − F, the subtraction §35.7 measured.
	var gen := WorldMapPrimitives.new(_assets)
	var at := Vector2i(int((sh["xy"] as Array)[0]), int((sh["xy"] as Array)[1]))
	var quads := gen.cel_quads(cel_id, at)
	_eq("...and generates 28 quads", quads.size(), 28)
	var not_sub := 0
	for q in quads:
		if int(q["abr"]) != 2 or not bool(q["semi"]):
			not_sub += 1
	_eq("every quad is semi-transparent at abr 2", not_sub, 0)
	# One CLUT for all 28: 0x79C0 = VRAM (0,487), the ramp.
	var cluts: Dictionary = {}
	for q in quads:
		cluts[int(q["clut"])] = true
	_eq("all 28 on one CLUT, 0x79C0", cluts.keys(), [0x79C0])

	# The extent. Four measured numbers against a two-degree-of-freedom anchor.
	var lo := Vector2i(0x7FFF, 0x7FFF)
	var hi := Vector2i(-0x7FFF, -0x7FFF)
	for q in quads:
		for p in (q["xy"] as Array):
			lo = lo.min(p as Vector2i)
			hi = hi.max(p as Vector2i)
	_eq("the ring spans x −72..72", Vector2i(lo.x, hi.x), Vector2i(RING_X0, RING_X1))
	_eq("...and y −80..15", Vector2i(lo.y, hi.y), Vector2i(RING_Y0, RING_Y1))
	# Heavier down and to the right than the picture it sits under — which is what
	# makes it read as a drop shadow rather than a glow (§35.7).
	var pic: Dictionary = town["picture"]
	var px := int((pic["xy"] as Array)[0])
	var py := int((pic["xy"] as Array)[1])
	var pw := int((pic["wh"] as Array)[0])
	var ph := int((pic["wh"] as Array)[1])
	_eq("it extends 8 left, 16 right of the picture",
			Vector2i(px - lo.x, hi.x - (px + pw)), Vector2i(8, 16))
	_eq("...and 4 above, 11 below",
			Vector2i(py - lo.y, hi.y - (py + ph)), Vector2i(4, 11))


## The CLUT is the whole shading model: entry k = 5-bit (k, k−1, k−2) clamped, k = 0..10.
func _check_shadow_ramp(town: Dictionary) -> void:
	var ramp: Dictionary = town["shadow"]["ramp"]
	_eq("the ramp is 11 deep", int(ramp["depth"]), 11)
	var wrong := 0
	for k in 11:
		var lv: Array = (ramp["levels"] as Array)[k]
		for c in 3:
			if int(lv[c]) != maxi(0, k - c):
				wrong += 1
	_eq("entry k = (k, k−1, k−2) clamped at 0, for k = 0..10", wrong, 0)
	_eq("entries 11..15 are one unused sentinel", (ramp["sentinel"] as Array).size(), 1)
	# One texel step subtracts one 5-bit level, and the deepest is (10,9,8) — warmer in
	# red than blue, which tilts the shadow cool as it deepens.
	_eq("the deepest subtraction is (10, 9, 8)", (ramp["levels"] as Array)[10], [10, 9, 8])


## The ramp TEXELS. `WLDTEX.TM2` does not write them, so before this round the cel above
## resolved to 4800 transparent texels and drew a perfectly correct nothing — which is
## exactly the failure a shape-only test cannot see (`[[texture-tab-adr0130-built]]`).
func _check_shadow_texture_present() -> void:
	var nz := 0
	for y in range(464, 512):
		for x in range(512, 536):
			if _assets.halfword(x, y) != 0:
				nz += 1
	_eq("the ramp texture is in vram.bin at (512,464)", nz > 0, true)
	var clut_nz := 0
	for i in 16:
		if _assets.halfword(i, 487) != 0:
			clut_nz += 1
	_eq("...and its CLUT at (0,487) — 15 of 16 entries, entry 0 being black",
			clut_nz, 15)


## §35.6 — one 0x64 textured rect, and its tpage/CLUT decode to the addresses the TIM
## header names. The CLUT id was PREDICTED from that header before the frame was dumped.
func _check_picture_rect(town: Dictionary) -> void:
	var pic: Dictionary = town["picture"]
	_eq("the picture is at screen-centred (−64,−76)", pic["xy"], [-64, -76])
	_eq("...120x80", pic["wh"], [120, 80])
	var o := WorldMapAssets.tpage_origin(int(pic["tpage"]))
	_eq("tpage 0x0298 -> VRAM (512,256)", Vector2i(int(o[0]), int(o[1])), Vector2i(512, 256))
	_eq("...8bpp", int(o[2]), 8)
	_eq("...abr 0", int(o[3]), 0)
	var cw := int(pic["clut"])
	_eq("CLUT 0x7900 -> VRAM (0,484)",
			Vector2i((cw & 0x3F) * 16, (cw >> 6) & 0x1FF), Vector2i(0, 484))


## §35.8's panel, and the row pitch measured off the savestate pair.
func _check_box(town: Dictionary) -> void:
	var box: Dictionary = town["box"]
	_eq("the box spans x −42..34", Vector2i(int((box["xy"] as Array)[0]),
			int((box["xy"] as Array)[0]) + int((box["wh"] as Array)[0])),
			Vector2i(-42, 34))
	_eq("...and y 8..84", Vector2i(int((box["xy"] as Array)[1]),
			int((box["xy"] as Array)[1]) + int((box["wh"] as Array)[1])),
			Vector2i(8, 84))
	_eq("the content band is (−34,20) 66x50", [box["content_xy"], box["content_wh"]],
			[[-34, 20], [66, 50]])
	# Measured: the glove's lit quad moves (−51,22) -> (−52,54) between the row-0 and
	# row-2 savestates, so the pitch is 16 and the 1px of x is the bob.
	_eq("row pitch 16", int(box["row_pitch"]), 16)
	_eq("the glove's row-0 lit top-left is (−51,22)", box["cursor_xy"], [-51, 22])
	# The content band holds three rows at that pitch and not four — which is why the
	# Fur shop's gate matters rather than being cosmetic.
	_eq("the content band holds 3 rows at pitch 16",
			int((box["content_wh"] as Array)[1]) / int(box["row_pitch"]), 3)


## The four rows, their strings and where each one goes. §35.9 / §35.10.
func _check_rows(town: Dictionary) -> void:
	var rows: Array = town["rows"]
	var labels: Array = []
	for r in rows:
		labels.append(String(r["label"]))
	_eq("the four rows, decoded from EVENT/WORLD.LZW",
			labels, ["Bar", "Shop", "Soldier office", "Fur shop"])
	_eq("the first three are unconditional", [
			rows[0].has("gate"), rows[1].has("gate"), rows[2].has("gate")],
			[false, false, false])
	# §27.4 makes the two gates different IN KIND by storage, without knowing what
	# either gates: 144 is in the bit region, 101 in the u32 region.
	var gate: Dictionary = rows[3]["gate"]
	_eq("the Fur shop is gated on var 144", int(gate["var"]), 144)
	_eq("...which is a BIT by storage region", String(gate["var_kind"]), "bit")
	_eq("...and only at Dorter, Warjilis and Zarghidas", gate["nodes"], [9, 12, 14])
	var gate_names: Array = []
	for n in (gate["nodes"] as Array):
		gate_names.append(String(_assets.node(int(n))["name"]))
	_eq("...named", gate_names,
			["Dorter Trade City", "Warjilis Trade City", "Zarghidas Trade City"])

	# Only the Bar pushes a WLDCORE page mode; the other three are one blocking call
	# into WORLD.BIN with a different selector (§35.9 — 1 push, 3 blocking calls).
	var pushes := 0
	var calls: Array = []
	for r in rows:
		if String(r["leads_to"]["kind"]) == "wldcore_page_mode":
			pushes += 1
		else:
			calls.append(int(r["leads_to"]["arg"]))
	_eq("one row pushes a page mode", pushes, 1)
	_eq("...and three are FUN_80133478(0 / 0x65 / 0x64)", calls, [0x00, 0x65, 0x64])

	# The Deep Dungeon's own list: a counter, not a flag, and bounded at ten by the
	# message archive running out — section 23 index 247 is empty.
	var dd: Dictionary = town["deep_dungeon"]
	_eq("the Deep Dungeon's gate is var 101", int(dd["count_var"]), 101)
	_eq("...which is a WORD by storage region", String(dd["var_kind"]), "word")
	_eq("...and its list is ten floors", (dd["floors"] as Array).size(), 10)
	var floor_names: Array = []
	for f in (dd["floors"] as Array):
		floor_names.append(String(f["label"]))
	# [b]The names are QUOTED on the disc[/b], and §35.10's prose is not — it lists them
	# as `Nogias, Terminate, Delta, …`. The raw message bytes for 0xB8ED are
	# `d9 c0 17 32 2a 2c 24 36 d9 c0`: the same `d9 c0` pair opens and closes every one
	# of the ten. So the quotes are the ROM's, the decoder is faithful, and a port that
	# strips them to match the document would be drawing something the console does not.
	_eq("...ten quoted floor names, Nogias..End", floor_names,
			["\"Nogias\"", "\"Terminate\"", "\"Delta\"", "\"Valkyries\"", "\"Mlapan\"",
			"\"Tiger\"", "\"Bridge\"", "\"Voyage\"", "\"Horror\"", "\"End\""])
	var unquoted := 0
	for f in floor_names:
		if not (String(f).begins_with("\"") and String(f).ends_with("\"")):
			unquoted += 1
	_eq("...every one of them", unquoted, 0)


## ADR-0178. Each of the 19 pictures has an ADDRESS of its own, and the packet fields
## that reach it resolve back to the halfwords the extractor blitted.
##
## [b]The port diverges from the console here on purpose[/b]: on the PSX all 92 WLDPIC
## entries land at VRAM (512,256) and are swapped in place, which a single static
## `vram.bin` cannot represent. What must stay true is that the slots are DISTINCT and
## that the picture is not blank — a slot scheme that collided would show 19 nodes the
## same painting, which is exactly the kind of wrong a shape-only check sails past.
func _check_picture_slots() -> void:
	var slots: Dictionary = {}
	var blank := 0
	var picture_nodes := 0
	for n in _assets.nodes():
		if int(n["picture"]) == 0:
			continue
		picture_nodes += 1
		var slot: Variant = (n as Dictionary).get("picture_slot")
		if typeof(slot) != TYPE_DICTIONARY:
			blank += 1
			continue
		var s: Dictionary = slot
		slots["%d:%d:%s" % [int(s["tpage"]), int(s["clut"]), s["uv"]]] = true
		# Sample the middle of the picture. A slot pointing at empty VRAM resolves to
		# index 0 through a CLUT entry that is also 0 — i.e. fully transparent, which
		# draws nothing and looks like "the page did not open".
		var lit := 0
		for k in 16:
			var t := _assets.texel(int(s["tpage"]),
					int((s["uv"] as Array)[0]) + 40 + k,
					int((s["uv"] as Array)[1]) + 40)
			if _assets.clut_levels(int(s["clut"]), t).w != 0:
				lit += 1
		if lit == 0:
			blank += 1
	_eq("every picture-carrying node has a slot, and none samples blank", blank, 0)
	_eq("...19 of them", picture_nodes, 19)
	_eq("...and all 19 slots are DISTINCT", slots.size(), 19)


## The page itself: which nodes open it, and what it puts on screen.
func _check_page(town: Dictionary) -> void:
	var opens: Array = []
	for n in _assets.nodes():
		if WorldMapTownPage.opens_for(_assets, int(n["i"]) + 1):
			opens.append(String(n["name"]))
	_eq("the page opens for 16 nodes", opens.size(), 16)
	for name in PICTURE_NO_MENU:
		_eq("...and NOT for %s" % name, name in opens, false)

	# ss1's campaign: Gariland (node 7, 1-based), var[144] clear, var[101] zero.
	var p := WorldMapProgress.ss1_fixture()
	_eq("the ss1 party is standing on Gariland",
			String(_assets.node(p.party_node() - 1)["name"]), "Gariland Magic City")
	var rows := WorldMapTownPage.rows_for(_assets, p, p.party_node())
	var labels: Array = []
	for r in rows:
		labels.append(String(r["label"]))
	_eq("...and gets three rows", labels, ["Bar", "Shop", "Soldier office"])

	# The Fur shop's gate is a BIT and a node list, and BOTH have to hold. Driving it
	# both ways is the only way to know the `and` is not an `or`.
	var q := WorldMapProgress.ss1_fixture()
	q.vars.set_var(144, 1)
	q.set_party_node(7)
	_eq("var[144] alone does not give Gariland a Fur shop",
			WorldMapTownPage.rows_for(_assets, q, 7).size(), 3)
	for node in [10, 13, 15]:      # 1-based Dorter, Warjilis, Zarghidas
		q.set_party_node(node)
		var got := WorldMapTownPage.rows_for(_assets, q, node)
		_eq("...but %s gets four" % String(_assets.node(node - 1)["name"]),
				got.size(), 4)
		_eq("...the last being the Fur shop", String(got[3]["label"]), "Fur shop")
	q.vars.set_var(144, 0)
	q.set_party_node(10)
	_eq("the node list alone does not either",
			WorldMapTownPage.rows_for(_assets, q, 10).size(), 3)

	# The Deep Dungeon reads a COUNTER, so the list GROWS. Node 23 is 1-based 22.
	var dd := WorldMapProgress.ss1_fixture()
	dd.set_party_node(23)
	_eq("var[101] = 0 gives one floor",
			WorldMapTownPage.rows_for(_assets, dd, 23).size(), 1)
	dd.vars.set_var(101, 3)
	var four := WorldMapTownPage.rows_for(_assets, dd, 23)
	_eq("...var[101] = 3 gives four", four.size(), 4)
	_eq("...and they are the first four floors", String(four[3]["label"]),
			"\"Valkyries\"")
	dd.vars.set_var(101, 99)
	_eq("...and the list is BOUNDED at ten by the archive, not by the counter",
			WorldMapTownPage.rows_for(_assets, dd, 23).size(), 10)

	# [b]Take a row, through the page.[/b] Everything above tests `rows_for` as a static
	# function; this drives the object, because the two bugs this page has had were both
	# on paths a pure-data check cannot reach — one in the SCENE's arrival branch, and
	# one in a `print` on the confirm path (`%#06x`, which GDScript's `%` does not
	# support and which throws only when a row is actually taken).
	var page := WorldMapTownPage.new()
	add_child(page)
	_eq("the page builds for Gariland",
			page.setup(_assets, WorldMapPrimitives.new(_assets), p, p.party_node()), true)
	_eq("...with three rows", page.rows(), 3)
	var taken: Array = []
	page.chose.connect(func(r: int, m: int, l: String, to: Dictionary) -> void:
			taken.append([r, m, l, to.get("kind", "")]))
	page.confirm()
	_eq("row 0 emits `chose` with the Bar's message and destination", taken,
			[[0, 0xB85D, "Bar", "wldcore_page_mode"]])
	page.move(1)
	page.confirm()
	_eq("...and row 1 the Shop's", taken[1], [1, 0xB85E, "Shop", "world_bin_screen"])
	# The wrap is the list's own length, not a record halfword — the list is built at
	# runtime, so three rows wrap at three.
	page.move(1)
	page.move(1)
	_eq("down from the last row wraps to 0", page.row, 0)
	page.move(-1)
	_eq("...and up from 0 to the last", page.row, 2)
	page.queue_free()


## §37.1/§37.2 — the panel's frame is the CONSOLE's, assembled from `frame.tga`.
##
## The console draws nine `0x66` rects, each through its own `GP0(E2)` texture window, on
## CLUT `0x7C3C` = FRAME.BIN palette 0 = what `tools/parse_frame.py` bakes into
## `frame.tga`. So this asserts the two things the port can get wrong without any test
## noticing: that the nine SOURCE rects still hold the art (checked by sampling four
## texels the console's own display list resolves), and that the 9-slice lattice is the
## measured 8 / 8 / 16 / 16 rather than the flat tile's 4 / 4 / 5 / 4.
func _check_panel_frame() -> void:
	_eq("the panel atlas is 32x48 — three 16-tall bands of 8 + 16 + 8",
			WorldMapTownPage.PANEL_ATLAS_WH, Vector2i(32, 48))
	_eq("nine source rects", WorldMapTownPage.PANEL_TILES.size(), 9)
	_eq("the 9-slice margins are the measured lattice, not the flat tile's",
			[WorldMapTownPage.PANEL_MARGIN_L, WorldMapTownPage.PANEL_MARGIN_R,
			WorldMapTownPage.PANEL_MARGIN_T, WorldMapTownPage.PANEL_MARGIN_B],
			[8, 8, 16, 16])
	var tex := WorldMapTownPage._panel_texture()
	if tex == null:
		_eq("frame.tga loads", false, true)
		return
	var img := tex.get_image()
	_eq("...and the built atlas is that size", img.get_size(), Vector2i(32, 48))
	# The header bar, in the packed atlas: the top band's middle column is the top-edge
	# patch, whose rows 3..11 are outline / bevel / three olive / tan / olive / outline /
	# bevel (§37.2). Three samples pin it — a flat crop passes none of them.
	var outline := img.get_pixel(16, 3)
	var bevel := img.get_pixel(16, 4)
	_eq("the top edge's row 3 is the dark outline, row 4 the bright bevel",
			outline.get_luminance() < bevel.get_luminance(), true)
	# The bar is a BAND, and that is what separates it from the flat tile: rows 5, 6 and 7
	# are one flat colour ACROSS the whole 16-wide patch, row 8 is a different flat one,
	# and the body (row 12+) is a two-tone dither that is flat on neither axis.
	var bar := img.get_pixel(8, 5)
	var flat := true
	for x in range(8, 24):
		for y in range(5, 8):
			flat = flat and img.get_pixel(x, y).is_equal_approx(bar)
	_eq("...rows 5-7 are ONE flat olive band across all 16 columns — the header bar",
			flat, true)
	_eq("...row 8 is a different flat row, not more of the bar",
			img.get_pixel(8, 8).is_equal_approx(bar), false)
	_eq("...and the bar is not the outline either",
			bar.is_equal_approx(outline), false)
	_eq("...and it is darker than the body it caps",
			bar.get_luminance() < img.get_pixel(16, 30).get_luminance(), true)
	var dithered := false
	for x in range(8, 24):
		if not img.get_pixel(x, 30).is_equal_approx(img.get_pixel(8, 30)):
			dithered = true
	_eq("...while the body fill IS dithered, so the band is not just more body",
			dithered, true)
	_eq("every atlas pixel is opaque except the corners' 3 blank rows",
			img.get_pixel(0, 0).a, 0.0)
	_eq("...and the body fill is not", img.get_pixel(16, 30).a, 1.0)
	# §37.3's measured ink, expressed the way the page places it.
	_eq("row 0's label cell", WorldMapTownPage.ROW_INK_XY
			- Vector2i(0, WorldMapTownPage.ROW_CELL_INK_DY), Vector2i(-30, 22))


## §37.5 — the fixed name-plate anchor is safe for all 43 nodes, and the "28 of 43 are
## centred 4px off" alarm measured the PADDING.
##
## Every name cel's RECT is padded to a multiple of 8 texels, so 28 sit at `x = -w/2` and
## 15 at `x = -(w-8)/2` — a 4px split that is real in the rect and absent in the art. This
## walks the actual texels of all 43 cels and asserts the INK centres are one cluster
## inside a couple of pixels of the anchor. If a future extractor change moves a name cel,
## or the cel bank's padding rule changes, this fails instead of 42 names drifting.
func _check_name_cel_ink() -> void:
	var centres: Array[float] = []
	for i in _assets.nodes().size():
		var cid := _assets.static_cel(i + 1 + WorldMapPrimitives.NAME_FRAME_BASE)
		if cid < 0:
			continue
		var cel: Dictionary = _assets.cel(cid)
		var page: Array = cel["tpage_xy"]
		var lo := 1 << 30
		var hi := -(1 << 30)
		for part_v in (cel["parts"] as Array):
			var part: Dictionary = part_v
			for yy in int(part["h"]):
				for xx in int(part["w"]):
					var u: int = (int(part["u"]) + xx) & 0xFF
					var v: int = (int(part["v"]) + yy) & 0xFF
					# 4bpp: four texels per VRAM halfword, low nibble first.
					if (_assets.halfword(int(page[0]) + (u >> 2), int(page[1]) + v)
							>> ((u & 3) * 4)) & 0xF == 0:
						continue
					lo = mini(lo, int(part["x"]) + xx)
					hi = maxi(hi, int(part["x"]) + xx)
		if hi < lo:
			continue
		centres.append((lo + hi) * 0.5)
	_eq("all 43 node names have a name cel with ink", centres.size(), 43)
	var worst := 0.0
	for c in centres:
		worst = maxf(worst, absf(c))
	# Measured spread is −3.5..+2.0; 4.0 leaves a pixel of room without admitting a
	# second cluster (a 4px placement rule would put a whole group at ±4).
	_eq("...and every one self-centres on its anchor within 4px — ONE cluster, so the "
			+ "fixed (−4,0) anchor is right for every node", worst <= 4.0, true)


## §38 — the OPEN transition, and this is the test that a popped-open page fails.
##
## [b]Seeded the way §37's frame guard was seeded.[/b] Every assertion below is on a
## frame the settled page does not have, so building the animation as "jump to settled on
## frame 0" — which is what this port did until §38 — makes the picture, the ramp and the
## clip all read their settled values and eleven of these go red. A guard that only
## checked the last frame would pass on the bug it exists to catch.
func _check_open_transition() -> void:
	# --- the aperture arithmetic, straight off FUN_8006B678 (§38.1). The divisor is 200:
	# reading it as 100 doubles every width, so these five are the trap's own tripwire.
	var want := {20: [48, 24], 50: [32, 56], 80: [12, 96], 90: [8, 104], 100: [0, 120]}
	for p in want:
		var got := WorldMapTownPage.aperture(120, int(p))
		_eq("§38.1 aperture(120, %d%%) = inset %d, width %d"
				% [p, want[p][0], want[p][1]], [got.x, got.y], want[p])
	var wanth := {20: [32, 16], 50: [20, 40], 80: [8, 64], 90: [4, 72], 100: [0, 80]}
	for p in wanth:
		var got := WorldMapTownPage.aperture(80, int(p))
		_eq("§38.1 aperture(80, %d%%) = inset %d, height %d"
				% [p, wanth[p][0], wanth[p][1]], [got.x, got.y], wanth[p])

	var page := WorldMapTownPage.new()
	add_child(page)
	if not page.setup(_assets, WorldMapPrimitives.new(_assets),
			WorldMapProgress.ss1_fixture(), 7):
		_eq("§38 the page builds for Gariland", false, true)
		page.queue_free()
		return
	_eq("§38 a page that has not been opened is SETTLED — every existing assertion in "
			+ "this file keeps the frame it already checks", page.opening(), false)

	page.begin_open()
	# --- frame 0: black, and the picture is a 24x16 window on the middle of the painting
	_eq("§38.4 frame 0 the plate and the shadow are LITERALLY black", page.ramp_level(), 0)
	_eq("§38.2 frame 0 the picture is 24x16", _v(page.picture_quad()["xy"]), [-16, -44])
	_eq("§38.7 frame 0 the panel is not on screen at all",
			page.panel_clip().size, Vector2i.ZERO)

	# --- walk the whole transition and record what each clock did
	var ramp: Array = [page.ramp_level()]
	var pics: Array = [_pic_wh(page)]
	var clips: Array = []
	for _i in WorldMapTownPage.OPEN_VSYNCS:
		page.advance_open()
		ramp.append(page.ramp_level())
		pics.append(_pic_wh(page))
		var c := page.panel_clip()
		if c.size.x > 0 and (clips.is_empty() or clips[-1] != c.size.x):
			clips.append(c.size.x)

	_eq("§38.3 the ramp is 0 then +7 a vsync to 128 — the console's own 0, 8, 15, 22 …",
			[ramp[0], ramp[1], ramp[2], ramp[3], ramp[17], ramp[18], ramp[19]],
			[0, 8, 15, 22, 120, 127, 128])
	_eq("§38.3 ...and it holds 128 once it disarms", ramp[ramp.size() - 1], 128)
	# five distinct sizes, each held two vsyncs -- the doubled curve read per vsync
	var sizes: Array = []
	for w in pics:
		if sizes.is_empty() or sizes[-1] != w:
			sizes.append(w)
	_eq("§38.2 the picture walks five sizes and no others", sizes,
			[[24, 16], [56, 40], [96, 64], [104, 72], [120, 80]])
	_eq("§38.2 ...each held exactly two vsyncs", [pics[0], pics[1], pics[2], pics[8]],
			[[24, 16], [24, 16], [56, 40], [120, 80]])
	_eq("§38.7 the panel's clip walks 84*[10,60,90,95,100]/100", clips, [8, 50, 75, 79, 84])
	_eq("§38.0 ...and it does not start until the ramp has finished",
			clips.size() > 0 and ramp[WorldMapTownPage.OPEN_PANEL_DELAY] == 128, true)
	_eq("§38 the transition ends settled", page.opening(), false)
	_eq("§38 ...at exactly the §37 element, 84 wide and not the box's 76 (§37.1)",
			page.panel_clip(),
			Rect2i(page.origin(), WorldMapTownPage.PANEL_ELEM_WH))
	_eq("§38 ...with the picture at §35.6's rect", _pic_wh(page), [120, 80])
	_eq("§38 ...and the plate and shadow at the neutral 0x80",
			page.ramp_level(), WorldMapPrimitives.DEFAULT_RGB & 0xFF)
	page.queue_free()


func _pic_wh(page: WorldMapTownPage) -> Array:
	var q: Dictionary = page.picture_quad()
	if q.is_empty():
		return [0, 0]
	var xy: Array = q["xy"]
	return [int(xy[3].x) - int(xy[0].x), int(xy[3].y) - int(xy[0].y)]


func _v(a: Variant) -> Array:
	var arr: Array = a
	return [int(arr[0].x), int(arr[0].y)]


func _eq(what: String, got: Variant, want: Variant) -> void:
	if str(_norm(got)) == str(_norm(want)):
		_passed += 1
		return
	_failed += 1
	print("  MISMATCH  %s: got %s, want %s" % [what, _norm(got), _norm(want)])


## Compare by VALUE, not by static type.
##
## Two things bite here and both are about the model coming from JSON rather than from
## GDScript. [method JSON.parse_string] hands back every number as a [float], so the
## model's `[-64, -76]` arrives as `[-64.0, -76.0]` and `== [-64, -76]` is false. And an
## `Array[int]` built by `range()` does not compare equal to an untyped Array built by
## `append` even when the elements match. Normalising whole-valued floats to ints and
## then comparing the printed form settles both, and keeps the failure message readable.
func _norm(v: Variant) -> Variant:
	if typeof(v) == TYPE_FLOAT and is_equal_approx(v, roundf(v)):
		return int(roundf(v))
	if typeof(v) == TYPE_ARRAY:
		var out: Array = []
		for e in (v as Array):
			out.append(_norm(e))
		return out
	return v
