class_name WorldMapPlaceList
extends Node2D
## The Move row's place list — WORLD.BIN window record 6 (WORLD_MAP_SCREEN.md §33.3 row 0).
##
## [b]This is the one START-menu row the map owns[/b] (§33.10 point 3). The other five hand
## off to screens that are not the map's business; this one ends where the map's own ○
## already ends, in `FUN_8008E2BC` — so it is a second [i]input[/i] to
## [signal WorldMapScene.node_entered], never a second mechanism. ADR-0117 dec. 8.
##
## [b]The list is the console's, read not retyped.[/b] `FUN_80105E04` walks `n = 0..0x2A`
## — all 43 nodes, every one of them, not the drawn ones — and keeps those with
## `var[0x200 + n] != 0`. That variable is [constant WorldMapProgress.NODE_KNOWN_BASE],
## which this port already had and already tested, so nothing new is decoded here.
##
## [b]The node you are standing on is REFUSED, not removed.[/b] §33.3: the walk *"marks the
## row where `n == var[0x31]` with a 4"* and *"`FUN_80105F7C` refuses a row flagged 4"*. It
## is a row you can put the cursor on and cannot take. (A summary that drops it from the
## list instead is a row shorter than the console's and renumbers everything under it.)
##
## [b]And it LOOKS exactly like every other row, which is a reading rather than a
## default.[/b] The per-row flag lives in the halfword array at `0x8016E500`, written by
## the walk — `8` or `0` from `var[0x267 + n]`, then overwritten with `4` on the party's
## own row. `WORLD.BIN` materialises that address in exactly two places: `0x80105E20`,
## which builds the base for the walk that WRITES it, and `0x80105FA0`, which is
## [codeblock]
##   80105f9c  addu at,at,a1          ; a1 = row * 2
##   80105fa0  lh   v1,-0x1b00(at)    ; the row's flag
##   80105fa4  ori  v0,zero,0x4
##   80105fa8  beq  v1,v0,0x80106040  ; ...and refuse
## [/codeblock]
## and nothing else — there is no `lui rX,0x8016` anywhere in the overlay and no
## `ori ...,0xE500`, so no second alias can reach it. [b]The flag is a predicate and never
## a style: it never reaches the renderer.[/b] So the console draws the refused row at full
## brightness and simply does not take it, and a port that dims it is inventing feedback
## the console does not give.
##
## That also answers half of §33.11's open `var[0x267 + n]`: whatever it MEANS, its only
## consumer is the `== 4` above, which `8` and `0` fail identically. This file used to
## paint the refused row at `rgb = 0x404040` — an alpha-ish tint of exactly the kind
## §15.21 says FFT never does, guarding a difference the ROM does not draw.
##
## [b]What is NOT built.[/b] Every row of record 6's entry table is `0x100D`, and
## `FUN_800EBB08` strips `0x1000` as a presentation flag — so on the console taking a row
## opens window [b]13[/b], a second record whose handler is the pick. §33 does not read
## what record 13 SHOWS, so there is nothing to port: the confirm here goes straight to the
## walk, and the console's extra press is a gap in the RE rather than in the port. Filed
## against §33.11.
##
## Vault: [[World Map Screen]]

## The place-list rows are the map's OWN node-name cels — the same `NAME_FRAME_BASE + n`
## plates the HUD draws under the cursor, from the same VRAM, through the same renderer.
## No glyph is baked on this screen: the console's own art already spells all 43 names.
const NAME_FRAME_BASE := WorldMapPrimitives.NAME_FRAME_BASE

## ⚠ Synthesis. Record 6's `h` is 0 on disc — the generic list
## driver sizes the window from however many rows the walk produced — and §33 does not read
## the padding it adds. The name cels are anchored on their own horizontal CENTRE (they run
## x −44..+44 for the widest, "Lesalia Imperial Capital"), so a row is drawn at the
## record's mid-x.
static var pad_y: int = 8
## The visible window scrolls when there are more known nodes than `visible_rows`. §33 does
## not read the console's scroll rule either; this keeps the cursor on screen and moves the
## view by the minimum, which is the least-surprising of the readings.

## This screen's name on the [code]Focus[/code] stack (ADR-0177). It is what
## [code]Focus.describe()[/code] prints, so it is this window's own name in every
## diagnostic. record 6's `+0x20` is one level over the MENU — ✕ here goes back to the menu,
## not to the map, and that is the whole reason this is a stack and not a flag.
const FOCUS_STATE := "world_map_place_list"


signal picked(node_1based: int)
signal cancelled()
signal row_changed(row: int)

var record: Dictionary = {}
## The 1-based node ids on the list, in the console's order — ascending `n`, because
## `FUN_80105E04` walks `n` ascending and appends.
var nodes: Array[int] = []
var row: int = 0
var top: int = 0

var _assets: WorldMapAssets
var _gen: WorldMapPrimitives
var _progress: WorldMapProgress
var _box: NinePatchRect
var _render: WorldMapRenderer
## The screen's vsync counter, pushed in by [method set_bob_frame].
var _bob_frame: int = 0


func setup(assets: WorldMapAssets, gen: WorldMapPrimitives,
		progress: WorldMapProgress) -> bool:
	_assets = assets
	_gen = gen
	_progress = progress
	var m: Variant = assets.model.get("place_list")
	if typeof(m) != TYPE_DICTIONARY or (m as Dictionary).is_empty():
		push_error("world map: model.json has no `place_list` — "
				+ "run `uv run python tools/parse_world_map.py`")
		return false
	record = m
	nodes = known_nodes(progress)
	# Open on the node you are standing on when it is on the list, which it always is —
	# it is `var[0x200 + n]` for the node the marker reached. Its row is the refused one,
	# so the first press moves off it.
	row = maxi(0, nodes.find(progress.party_node()))
	_scroll_to_row()
	_build()
	return true


## `FUN_80105E04`, exactly: every `n` in `0..0x2A` whose `var[0x200 + n]` is non-zero,
## ascending, as 1-BASED node ids (the rest of this module counts nodes from 1).
static func known_nodes(p: WorldMapProgress) -> Array[int]:
	var out: Array[int] = []
	for n in WorldMapProgress.NODE_COUNT:
		if p.is_node_known(n):
			out.append(n + 1)
	return out


func rows() -> int:
	return nodes.size()


func visible_rows() -> int:
	return mini(int(record.get("visible_rows", 0)), rows())


## True when row [param r] is the one the walk flagged 4 — the node the marker is on.
## `FUN_80105F7C` refuses it.
func is_refused(r: int) -> bool:
	return r >= 0 and r < nodes.size() and nodes[r] == _progress.party_node()


func node_at(r: int) -> int:
	return nodes[r] if r >= 0 and r < nodes.size() else 0


func origin() -> Vector2i:
	return Vector2i(int(record.get("x", 0)), int(record.get("y", 0)))


## The window's own width, and the height the driver sizes from the visible row count.
func size() -> Vector2i:
	var pitch := int(record.get("row_pitch", 0))
	return Vector2i(int(record.get("w", 0)), pitch * visible_rows() + 2 * pad_y)


## `FUN_800EC5B8` again — the same generic list driver, so the same formula on this
## window's own record, on the VISIBLE row index rather than the absolute one. Both halves
## come from [WorldMapStartMenu] rather than being restated: one console routine, one port
## of it.
func cursor_at(r: int) -> Vector2i:
	return WorldMapStartMenu.cursor_anchor(_assets, record, r - top, bob_x())


## The glove's row-top, which is where a name cel is drawn — the anchor above is the same
## point pushed onto the cursor cel's own origin.
func row_top_left(r: int) -> Vector2i:
	return WorldMapStartMenu.cursor_top_left(record, r - top, 0)


func bob_x() -> int:
	return WorldMapStartMenu.glove_bob(_bob_frame)


## Step the glove's bob — see [method WorldMapStartMenu.set_bob_frame]. This list rebuilds
## its whole primitive array, so the repaint goes through [method _build].
func set_bob_frame(f: int) -> void:
	if f == _bob_frame:
		return
	var was := bob_x()
	_bob_frame = f
	if bob_x() != was:
		_build()


## Move the highlight, wrapping — `FUN_800EBDCC` wraps on the list's own last row, which
## for a runtime-built list is `len - 1` rather than a record halfword.
func move(d: int) -> bool:
	var n := rows()
	if n <= 0 or d == 0:
		return false
	var was := row
	row = posmod(row + d, n)
	if row == was:
		return false
	_scroll_to_row()
	_build()
	row_changed.emit(row)
	return true


## ○. Refused on the row the marker is standing on, and silent about it — the console has
## no message here either, the pick simply does not take.
func confirm() -> void:
	if is_refused(row):
		print("[world map] place list refuses node %d — the party is already there"
				% node_at(row))
		return
	picked.emit(node_at(row))


func cancel() -> void:
	cancelled.emit()



## [b]Claim the input frame the moment this window mounts (ADR-0177).[/b] The screen
## pushes ITSELF, exactly as [WorldMapScene] does, because it is the live screen from
## the instant it enters the tree — the opener adds it as a child and that is the one
## creation path. Before this, [WorldMapScene._unhandled_input] dispatched here through
## an if-chain ordered by nullable precedence: a hand-rolled focus stack, which is the
## mechanism ADR-0177 replaces with the real one.
##
## There is no matching pop and that is deliberate — [code]Focus[/code] drops the frame
## on [signal Node.tree_exiting], which the opener's [code]remove_child[/code] fires. An
## [code]_exit_tree[/code] that popped as well would run AFTER that signal and pop a
## frame that is already gone, which [method Focus.pop] reports as the programming
## error it would be.
func _ready() -> void:
	Focus.push(FOCUS_STATE, self)


## Godot calls this only while this window holds focus — every other registered root is
## deafened by [code]set_process_*input(false)[/code], so the place list cannot be reached
## from underneath. The map's own ✕ not firing while this is up is now true by
## construction rather than by an early [code]return[/code] in the map.
func _unhandled_input(event: InputEvent) -> void:
	# [b]The viewport is read BEFORE the dispatch, and that is not a style choice.[/b]
	# `handle_input` can emit `cancelled`, whose handler is the opener's `_close_*` —
	# which calls `remove_child(self)`. By the time it returns, this node is out of the
	# tree and `get_viewport()` is null, so marking the event handled on the way out
	# crashes with "Cannot call method 'set_input_as_handled' on a null value". Measured,
	# not predicted: it printed four times a run before this line existed, while the
	# suite stayed green — a SCRIPT ERROR is not an assertion failure.
	var vp := get_viewport()
	if handle_input(event) and vp != null:
		vp.set_input_as_handled()


func handle_input(event: InputEvent) -> bool:
	if not event.is_pressed() or event.is_echo():
		return false
	if event.is_action(&"ui_up"):
		move(-1)
		return true
	if event.is_action(&"ui_down"):
		move(1)
		return true
	if event.is_action(&"ui_cancel"):
		cancel()
		return true
	if event.is_action(&"ui_accept") or event.is_action(&"cursor_confirm"):
		confirm()
		return true
	return false


## Keep [member row] inside the visible window by moving the view the minimum. ⚠ §33 does
## not read the console's scroll rule.
func _scroll_to_row() -> void:
	var vis := visible_rows()
	if vis <= 0:
		top = 0
		return
	top = clampi(top, maxi(0, row - vis + 1), row)
	top = clampi(top, 0, maxi(0, rows() - vis))


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()

	var o := origin()
	var sz := size()
	_box = NinePatchRect.new()
	_box.texture = WorldMapStartMenu._frame_texture()
	_box.patch_margin_left = WorldMapStartMenu.FRAME_MARGIN_L
	_box.patch_margin_right = WorldMapStartMenu.FRAME_MARGIN_R
	_box.patch_margin_top = WorldMapStartMenu.FRAME_MARGIN_T
	_box.patch_margin_bottom = WorldMapStartMenu.FRAME_MARGIN_B
	_box.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	_box.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	_box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.position = Vector2(o)
	_box.size = Vector2(sz)
	add_child(_box)

	# The names and the cursor go through the map's own renderer, so they are baked from
	# VRAM and blended by §13's rules like every other sprite on the screen.
	_render = WorldMapRenderer.new()
	_render.setup(_assets)
	add_child(_render)

	var prims: Array = []
	var mid := o.x + sz.x / 2
	for i in visible_rows():
		var r := top + i
		var cid := _assets.static_cel(node_at(r) + NAME_FRAME_BASE)
		if cid < 0:
			continue
		# [b]The refused row is drawn exactly like the others[/b] — see the class note.
		prims.append_array(_gen.cel_quads(cid, Vector2i(mid, row_top_left(r).y)))
	prims.append_array(_gen.cel_quads(
			_assets.static_cel(WorldMapPrimitives.CURSOR_FRAME), cursor_at(row)))
	_render.draw_primitives(prims)
