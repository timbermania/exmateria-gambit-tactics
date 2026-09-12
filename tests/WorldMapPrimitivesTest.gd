extends Node
## WorldMapPrimitives guard — the generated primitive list, packet for packet against
## the ORACLE.
##
## The oracle is `research/working_documents/world_map_captures/wldgen.py`, which emits
## the console's own primitives exactly: 60/60 main list and 12/12 travel ribbon on two
## captures (WORLD_MAP_SCREEN.md §30). `wldgen.py prims --state <json>` prints them, and
## `tests/goldens/world_map_prims_ss{1,2}.txt` are that output copied verbatim.
##
## [b]Why packets and not pixels.[/b] wldgen's own docstring: a wrong CLUT or a swapped
## uv is a hard miss here and a 0.1% residual in a screenshot. The scaffold's picture was
## 73.32% right with the cursor drawn four pixels low; this test is what says so. The
## pixel harness (tools/wm_compare.py) answers a different question — whether the BLEND
## is right — and it cannot answer this one.
##
## The two fixtures are the two savestates §30 is asserted against. Their state vectors:
##   ss1  selected 7, ramza 7 @ (-4,0), cursor (-4,-4),  pulse 40
##   ss2  selected 25, ramza 7 @ (-4,0), cursor (-46,-15), pulse 25
## `ramza_cel` is an index into frame list 16, not a cel id — both captures sit at 2.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/WorldMapPrimitivesTest.tscn

const RAMZA_FRAME_LIST := 16
## Frame INDEX inside that list, which is what the descriptor holds (§30, `ramza_cel`).
const RAMZA_FRAME_INDEX := 2

var _passed := 0
var _failed := 0


func _ready() -> void:
	var assets := WorldMapAssets.new()
	if not assets.load_all():
		# Regenerable and gitignored — a missing asset is not a failing assertion.
		print("[SKIP] WorldMapPrimitivesTest — %s" % assets.error)
		get_tree().quit(0)
		return
	var gen := WorldMapPrimitives.new(assets)
	# THE ORACLE IS ITSELF EXCLUDED FROM THE STANDALONE REPO. This file's header calls
	# the two goldens "the console's own primitives exactly ... copied verbatim" --
	# every packet's uv window, CLUT id and rgb read out of two PSX savestates -- which
	# is the HUD-capture category in text form, so the user's "no square assets" ruling
	# reaches them (register step 9). `wldgen.py` lives under `research/`, outside the
	# package, so a clone cannot regenerate them either.
	#
	# GATES ONLY THE TWO PACKET DIFFS, and this is the whole reason the check sits here
	# rather than beside the asset skip above. `_check_cursor`,
	# `_check_deactivated_cursor` and `_check_per_texel_blend` assert against the
	# GENERATOR and the ROM-derived assets, not against a golden -- including the
	# per-texel blend arm that the "too light" bug was found by -- so they still run and
	# still fail loudly in a clone. Skipping the file would have thrown those away for
	# an absence that does not touch them. Left alone, `_golden` push_errors and
	# `_diff` reads the empty result as a COUNT MISMATCH, reporting "60 primitives,
	# oracle has 0" -- an absent oracle dressed as a wrong answer.
	var goldens_absent: Array = []
	for name in ["ss1", "ss2"]:
		if not FileAccess.file_exists("res://tests/goldens/world_map_prims_%s.txt" % name):
			goldens_absent.append(name)
	if goldens_absent.is_empty():
		# The two cursor positions are the savestates' own, read by `wldgen.py state`.
		# They are literals here on purpose: deriving them would stop the next block
		# checking anything.
		_check("ss1", gen, assets, WorldMapProgress.ss1_fixture(), Vector2i(-4, -4), 40)
		_check("ss2", gen, assets, WorldMapProgress.ss2_fixture(), Vector2i(-46, -15), 25)
	else:
		print("  [SKIP] packet diff (%s) — the wldgen goldens are absent, excluded "
			% ", ".join(goldens_absent)
			+ "from the standalone repo as Square Enix data (verbatim PSX GPU "
			+ "packets). The three generator arms below still ran.")
	_check_cursor(assets)
	_check_deactivated_cursor(gen, assets)
	_check_per_texel_blend(gen, assets)

	if _failed > 0:
		print("[FAIL] WorldMapPrimitivesTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] WorldMapPrimitivesTest — %d/%d" % [_passed, _passed])
	get_tree().quit(0)


## The node pins are the one thing on this screen that blends PER TEXEL — and the one
## thing whose modulation BRIGHTENS. Both were wrong, and each hid the other.
##
## [b]The bug, reported from play as "the red glowing icons look too light".[/b] A quad's
## `0x2E` command byte only enables semi-transparency; the GPU then blends a texel only
## when its own CLUT entry has bit 15 set. The pin CLUTs `0x784A` / `0x784B` carry that
## bit on 3 of their 8 used entries — the outer ring and the drop shadow — and NOT on the
## five that make the orange ball. Blending the whole quad washed the ball halfway into
## the map. Measured on `world_map_ss1_settled_dialog_closed`: 23 of the pin's 24 opaque
## texels land on `min(31, texel * rgb / 128 + 7)` exactly, the `+ 7` being the additive
## vignette drawn over them (CLUT `0x7940` entry 0 = 7,7,7).
##
## [b]And underneath it, a clamp.[/b] §30.6's pulse runs `96 + 2c`, so half its period
## asks for a modulation ABOVE `0x80` — a brightening — and `Polygon2D.color` is 8 bits a
## channel, so everything over 1.0 clamped to 1.0 and the brightening was lost. Fixing
## only the blend moved the pin from 71.5% to 73.6% against the console; fixing both took
## it to 97.9%, and the whole screen from 99.588% to 99.718%.
##
## The corpus scan at the end is the promise [method WorldMapRenderer._per_texel_blend]
## makes: a mixed CLUT on abr 1/2/3 could not be reproduced by one draw at any alpha, so
## assert that no primitive is one rather than leave the gap silent.
func _check_per_texel_blend(gen: WorldMapPrimitives, assets: WorldMapAssets) -> void:
	for clut in [0x784A, 0x784B]:
		var stp: Array = []
		var opaque: Array = []
		for i in 16:
			if assets.clut_levels(clut, i).w == 0:
				continue
			if assets.clut_stp(clut, i):
				stp.append(i)
			else:
				opaque.append(i)
		if stp == [2, 14, 15] and opaque == [1, 4, 5, 6, 7]:
			_pass("pin CLUT %04X blends entries %s and WRITES %s" % [clut, stp, opaque])
		else:
			_fail("pin CLUT %04X: stp %s opaque %s, expected [2,14,15] / [1,4,5,6,7]"
					% [clut, stp, opaque])
		if assets.clut_stp_mixed(clut, 16):
			_pass("...so %04X is MIXED and needs a per-texel blend" % clut)
		else:
			_fail("%04X did not read as mixed" % clut)

	# The cursor's lit ramp has no STP entry at all, so it must NOT take that path —
	# a CLUT being all-opaque is not the same question as a quad being opaque.
	if not assets.clut_stp_mixed(0x7847, 16):
		_pass("the cursor's CLUT 7847 is all-opaque, so it stays on the whole-quad path")
	else:
		_fail("CLUT 7847 read as mixed")

	# The pulse asks for a brightening on half its period, and that is exactly the half
	# a vertex colour cannot carry.
	var bright := WorldMapPrimitives.pulse_greys(WorldMapPrimitives.PULSE_TOP).x
	var dim := WorldMapPrimitives.pulse_greys(0).x
	if WorldMapRenderer.bakes_modulation(bright * 0x010101) \
			and not WorldMapRenderer.bakes_modulation(dim * 0x010101):
		_pass("the pulse's bright end (%d) bakes its modulation, its dim end (%d) does not"
				% [bright, dim])
	else:
		_fail("bakes_modulation: bright %d / dim %d took the wrong path" % [bright, dim])

	# The corpus: nothing may be semi + mixed + abr != 0.
	var bad := 0
	for fixture in [WorldMapProgress.ss1_fixture(), WorldMapProgress.ss2_fixture()]:
		for prim in gen.main_list(fixture, Vector2i(-4, -4), 40):
			if prim["kind"] != "quad" or not bool(prim["semi"]):
				continue
			var tpage := int(prim["tpage"])
			var n := 256 if int(WorldMapAssets.tpage_origin(tpage)[2]) == 8 else 16
			if int(prim["abr"]) != 0 and assets.clut_stp_mixed(int(prim["clut"]), n):
				bad += 1
	if bad == 0:
		_pass("no primitive is semi + mixed-CLUT + abr 1/2/3 — the one shape a single "
				+ "draw cannot reproduce")
	else:
		_fail("%d primitives are semi + mixed-CLUT on abr 1/2/3; those need two draws"
				% bad)


## [WorldMapCursor]'s two derivations, against the same two captures: resting on a node
## puts the cursor at the hit box's centre, and the hit test gives the node back.
func _check_cursor(assets: WorldMapAssets) -> void:
	var p := WorldMapProgress.ss1_fixture()
	for row in [[7, Vector2i(-4, -4)], [25, Vector2i(-46, -15)]]:
		var node_1based: int = row[0]
		var want: Vector2i = row[1]
		var n: Dictionary = assets.node(node_1based - 1)
		var at := WorldMapCursor.rest_at(
				Vector2i(int(n["screen"][0]), int(n["screen"][1])))
		if at != want:
			_fail("cursor at rest on node %d is %s, the capture holds %s"
					% [node_1based, at, want])
			continue
		var back := WorldMapCursor.node_under(assets, p, at)
		if back != node_1based:
			_fail("cursor %s hit-tests to node %d, want %d" % [at, back, node_1based])
			continue
		_pass("cursor rests at %s on node %d and hit-tests back to it" % [at, node_1based])


## §15.21's "send to background", as the world map runs it — and the claim under test is
## as much about what does NOT change as about what does.
##
## Measured on the console, not designed: diffing `round16_menu_open.png` (the START menu
## up over `ss1`) against `ss1`'s own framebuffer leaves 83 differing pixels in the whole
## right half of the screen — 66 of them inside the cursor's 16x16 lit quad and the rest
## the party marker's own idle animation, which the two captures caught at different
## phases. The four texel indices that move go (239,239,239) -> (140,148,165),
## (181,189,198) -> (107,123,140), (123,140,156) -> (90,107,115) and
## (99,107,115) -> (74,90,99), which is CLUT [b]0x7849[/b] at VRAM (144,481) — the copy of
## FRAME.BIN's `0x7DFC` blue-grey twin that WLDTEX puts in the map's own palette row.
##
## So: exactly ONE primitive of the frame changes, it is the cursor's LIT part, and it
## changes ONLY its CLUT. The pins keep pulsing, the name plate stays cream, the war funds
## and the date and the map itself do not move a pixel — and the cursor's SHADOW keeps
## `0x7844`, because its descriptor sets blend bit 3, which vetoes the override (§24.2).
##
## Rendering the port's own two frames back gives the same 66 pixels and the same four
## colour pairs.
func _check_deactivated_cursor(gen: WorldMapPrimitives,
		assets: WorldMapAssets) -> void:
	var p := WorldMapProgress.ss1_fixture()
	var fl := assets.frame_list(RAMZA_FRAME_LIST)
	var cel_id: int = int(fl[RAMZA_FRAME_INDEX % fl.size()][0])
	var lit := gen.main_list(p, Vector2i(-4, -4), 40, cel_id)
	var dim := gen.main_list(p, Vector2i(-4, -4), 40, cel_id, null,
			WorldMapPrimitives.PAL_DEACTIVATED)
	if lit.size() != dim.size():
		_fail("backgrounding the cursor changed the primitive COUNT (%d -> %d)"
				% [lit.size(), dim.size()])
		return
	var moved: Array = []
	for i in lit.size():
		if describe(lit[i]) != describe(dim[i]):
			moved.append(i)
	if moved.size() != 1:
		_fail("backgrounding changed %d primitives, want exactly 1 (the cursor's lit "
				% moved.size() + "part): %s" % str(moved))
		return
	var i: int = moved[0]
	var a: Dictionary = lit[i]
	var b: Dictionary = dim[i]
	_pass("exactly one primitive backgrounds — the map itself does not")
	if int(a["clut"]) != 0x7847 or int(b["clut"]) != 0x7849:
		_fail("the cursor's lit CLUT goes %04X -> %04X, want 7847 -> 7849"
				% [int(a["clut"]), int(b["clut"])])
	else:
		_pass("the cursor's lit CLUT swaps 0x7847 -> 0x7849 (VRAM (144,481))")
	# ...and nothing else about that primitive moves: same rect, same uv, same tpage,
	# same modulation. A `modulate` dim would show up right here.
	var same: bool = (a["xy"] == b["xy"] and a["uv"] == b["uv"]
			and a["tpage"] == b["tpage"] and a["rgb"] == b["rgb"]
			and a["abr"] == b["abr"] and a["semi"] == b["semi"])
	if same:
		_pass("...and only the CLUT — a discrete palette swap, not an alpha tint")
	else:
		_fail("backgrounding moved something other than the CLUT")
	# The shadow part is the primitive immediately BEFORE it in chain order (part 0 ahead
	# of part 1) and must be untouched — blend bit 3 vetoes the override.
	if i > 0 and int(dim[i - 1]["clut"]) == 0x7844:
		_pass("the cursor's shadow keeps 0x7844 — blend bit 3 vetoes the override")
	else:
		_fail("the cursor's shadow did not keep 0x7844")
	# The four colours the console moved, resolved through the port's own VRAM. This is
	# what makes the CLUT number above a picture rather than a hex constant.
	var want := {2: Vector3i(17, 18, 20), 4: Vector3i(9, 11, 12),
			5: Vector3i(11, 13, 14), 6: Vector3i(13, 15, 17)}
	var bad := 0
	for idx in want:
		var lv := assets.clut_levels(0x7849, int(idx))
		if Vector3i(lv.x, lv.y, lv.z) != want[idx]:
			bad += 1
			print("  0x7849[%d] = %s, want %s" % [idx, lv, want[idx]])
	if bad == 0:
		_pass("0x7849's four moving entries are the console's blue-grey ramp")
	else:
		_fail("%d of 0x7849's entries are not the console's" % bad)


func _check(name: String, gen: WorldMapPrimitives, assets: WorldMapAssets,
		p: WorldMapProgress, cursor: Vector2i, pulse: int) -> void:
	var fl := assets.frame_list(RAMZA_FRAME_LIST)
	var cel_id: int = int(fl[RAMZA_FRAME_INDEX % fl.size()][0])
	var got: Array = []
	for prim in gen.main_list(p, cursor, pulse, cel_id):
		got.append(describe(prim))
	var n_main := got.size()
	for prim in gen.path_quads(p):
		got.append(describe(prim))
	_diff(name, got, n_main, _golden("res://tests/goldens/world_map_prims_%s.txt" % name))


## The golden is wldgen's own stdout. Strip its index column and its two count lines so
## the comparison is over the packets and nothing else.
func _golden(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("missing golden %s" % path)
		return []
	var out: Array = []
	for line in f.get_as_text().split("\n"):
		var s: String = line.strip_edges()
		if s.is_empty() or s.begins_with("--"):
			continue
		# "  0 FT4 2E (..." -> drop the leading index.
		out.append(s.substr(s.find(" ") + 1).strip_edges())
	f.close()
	return out


func _diff(name: String, got: Array, n_main: int, want: Array) -> void:
	if got.size() != want.size():
		_fail("%s: %d primitives, oracle has %d" % [name, got.size(), want.size()])
		return
	var bad := 0
	for i in got.size():
		if got[i] != want[i]:
			bad += 1
			if bad <= 8:
				var where := "main %d" % i if i < n_main else "path %d" % (i - n_main)
				print("  %s %s\n     want %s\n      got %s" % [name, where, want[i], got[i]])
	if bad > 0:
		_fail("%s: %d of %d primitives differ from the oracle" % [name, bad, got.size()])
	else:
		_pass("%s: %d primitives match the oracle packet for packet" % [name, got.size()])


## wldgen.py's `describe()`, reproduced. The golden is its literal output, so this
## format is part of the contract — keep the two in step.
static func describe(prim: Dictionary) -> String:
	if prim["kind"] == "line":
		return "LINE   (%4d,%4d)->(%4d,%4d) rgb=%06X tp=%04X" % [
			prim["a"].x, prim["a"].y, prim["b"].x, prim["b"].y,
			int(prim["rgb"]), int(prim["tpage"])]
	var xy: Array = prim["xy"]
	var uv: Array = prim["uv"]
	if prim.get("sprt", false):
		return "SPRT   (%4d,%4d) %3dx%-3d uv(%3d,%3d) clut=%04X rgb=%06X tp=%04X" % [
			xy[0].x, xy[0].y, xy[3].x - xy[0].x, xy[3].y - xy[0].y,
			uv[0].x, uv[0].y, int(prim["clut"]), int(prim["rgb"]), int(prim["tpage"])]
	# GP0 0x2C is a textured quad; 0x2E is the same command with the semi bit set.
	var code := 0x2E if bool(prim["semi"]) else 0x2C
	return "FT4 %02X (%4d,%4d) %3dx%-3d uv(%d, %d)..(%d, %d) clut=%04X tp=%04X rgb=%06X" % [
		code, xy[0].x, xy[0].y, xy[3].x - xy[0].x, xy[3].y - xy[0].y,
		uv[0].x, uv[0].y, uv[3].x, uv[3].y,
		int(prim["clut"]), int(prim["tpage"]), int(prim["rgb"])]


func _pass(msg: String) -> void:
	_passed += 1
	print("  ok   %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	print("  FAIL %s" % msg)
